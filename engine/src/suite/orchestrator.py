"""Runs one goal: plan → route → work → judge → learn → review → … → report."""
from __future__ import annotations

import json
import queue
import re
import shutil
import threading
from pathlib import Path
from typing import Callable

from .agents import load_agents
from .bandit import Bandits
from .config import JUDGE_VARIANT, KIND_IDS, KINDS, PLANNER_VARIANT, VARIANTS, home, load_settings
from .providers import Provider, ProviderError, Reply
from .store import Store
from .tools import ToolError, Workspace

MAX_ROUNDS = 3
DELIVERABLE_CHARS = 30_000

TASK_ITEM = {
    "type": "object", "additionalProperties": False,
    "required": ["title", "description", "kind", "depends_on"],
    "properties": {
        "title": {"type": "string"},
        "description": {"type": "string"},
        "kind": {"type": "string", "enum": KIND_IDS},
        "depends_on": {"type": "array", "items": {"type": "integer"}},
    },
}
PLAN_SCHEMA = {"type": "object", "additionalProperties": False, "required": ["tasks"],
               "properties": {"tasks": {"type": "array", "items": TASK_ITEM}}}
REVIEW_SCHEMA = {"type": "object", "additionalProperties": False, "required": ["done", "reason", "tasks"],
                 "properties": {"done": {"type": "boolean"}, "reason": {"type": "string"},
                                "tasks": {"type": "array", "items": TASK_ITEM}}}
JUDGE_SCHEMA = {"type": "object", "additionalProperties": False, "required": ["score", "rationale"],
                "properties": {"score": {"type": "number"}, "rationale": {"type": "string"}}}

WORK_RULES = """
You are one specialist in a company of AI agents working toward a shared goal. You have tools:
web_search (cite URLs), write_file / read_file / list_files on the shared workspace, and run_python
(sandboxed, no network) to check numbers or test code.

Rules:
- Put your full deliverable in the workspace with write_file at tasks/{slug}.md (code or data can go in
  additional files; mention them in the deliverable).
- Read inputs/ and other agents' tasks/ files when they are relevant.
- Be concrete and specific to this goal. State assumptions. Never invent sources or numbers.
- When finished, reply with a 2–3 sentence summary of what you produced and the key conclusion.
"""


class BudgetExceeded(Exception):
    pass


class Canceled(Exception):
    pass


def slugify(text: str, seq: int) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:48].strip("-")
    return f"{seq:02d}-{slug or 'task'}"


class Orchestrator:
    def __init__(self, provider: Provider, emit: Callable[[dict], None], store: Store | None = None,
                 settings: dict | None = None, suite_home: Path | None = None, rng=None, skill_priors: bool = True):
        self.home = suite_home or home()
        self.home.mkdir(parents=True, exist_ok=True)
        self.provider = provider
        self.settings = settings or load_settings()
        self.store = store or Store(self.home / "suite.db")
        self.agents = {a["id"]: a for a in load_agents(self.home)}
        self.emit_cb = emit
        self.rng = rng
        self.skill_priors = skill_priors
        self.spent = 0.0
        self.tasks_started = 0  # dispatched to a worker; the task cap counts these
        self.tasks_done = 0
        self.canceled = False
        # Guards spend, the store, the counters and the event stream, which worker threads share.
        self.lock = threading.RLock()
        self.run_id = ""
        self.events_file = None

    # --- plumbing -------------------------------------------------------------------
    def emit(self, event: dict) -> None:
        with self.lock:
            if self.events_file:
                self.events_file.write(json.dumps(event) + "\n")
                self.events_file.flush()
            self.emit_cb(event)

    def call(self, variant_id: str, system: str, messages: list[dict], **kw) -> tuple[Reply, float]:
        with self.lock:
            if self.canceled:
                raise Canceled()
            if self.spent >= self.settings["max_cost_usd"]:
                raise BudgetExceeded()
        variant = VARIANTS[variant_id]
        reply = self.provider.create(variant, system, messages, **kw)  # outside the lock: calls run concurrently
        cost = reply.usage.cost(variant)
        with self.lock:
            self.spent += cost
            self.store.update_run(self.run_id, spent_usd=self.spent)
        return reply, cost

    def call_json(self, variant_id: str, system: str, prompt: str, schema: dict, purpose: str,
                  meta: dict) -> tuple[dict, float]:
        reply, cost = self.call(variant_id, system, [{"role": "user", "content": prompt}],
                                purpose=purpose, json_schema=schema, meta=meta)
        if reply.stop_reason == "refusal":
            raise ProviderError(f"The model declined the {purpose} step.")
        text = reply.text
        match = re.search(r"\{.*\}", text, re.S)
        try:
            return json.loads(match.group(0) if match else text), cost
        except json.JSONDecodeError as e:
            raise ProviderError(f"The {purpose} step returned malformed JSON.") from e

    def bandits(self) -> Bandits:
        return Bandits(list(self.agents.values()), rng=self.rng, skill_priors=self.skill_priors).fit(
            self.store.scored_tasks(), self.settings["user_rating_weight"], self.settings["cost_penalty_per_usd"])

    def budget_event(self) -> None:
        with self.lock:
            self.emit({"type": "budget", "spent_usd": round(self.spent, 4),
                       "max_cost_usd": self.settings["max_cost_usd"], "tasks_done": self.tasks_done,
                       "max_tasks": self.settings["max_tasks"]})

    # --- the run --------------------------------------------------------------------
    def run(self, goal: str, inputs: list[Path] | None = None) -> str:
        mock = self.provider.name == "mock"
        self.run_id = self.store.create_run(goal, mock)
        run_dir = self.home / "runs" / self.run_id
        ws = Workspace(run_dir / "workspace")
        for src in inputs or []:
            dest = ws.root / "inputs" / src.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(src, dest)
        self.events_file = open(run_dir / "events.jsonl", "a")
        self.emit({"type": "run_started", "run_id": self.run_id, "goal": goal, "mock": mock,
                   "max_cost_usd": self.settings["max_cost_usd"], "max_tasks": self.settings["max_tasks"]})
        status = "done"
        try:
            self.plan(goal, ws)
            for round_ in range(1, MAX_ROUNDS + 1):
                self.execute_ready(goal, ws)
                if round_ == MAX_ROUNDS or not self.review(goal, round_ + 1):
                    break
        except BudgetExceeded:
            status = "budget"
        except (Canceled, KeyboardInterrupt):
            status = "canceled"
        except ProviderError as e:
            status = "error"
            self.emit({"type": "error", "message": str(e)})
        with self.lock:
            if status == "canceled":
                self.canceled = True  # workers still in flight stop at their next call and record nothing
            for t in self.store.tasks(self.run_id):
                if t["status"] in ("pending", "running"):
                    self.store.update_task(t["id"], status="skipped")
        report_path = run_dir / "report.md"
        report_path.write_text(self.report(goal, ws, allow_llm=status == "done"))
        self.store.update_run(self.run_id, status=status, spent_usd=self.spent)
        self.budget_event()
        self.emit({"type": "run_finished", "run_id": self.run_id, "status": status,
                   "report_path": str(report_path), "spent_usd": round(self.spent, 4)})
        self.events_file.close()
        return self.run_id

    def team_text(self) -> str:
        return "\n".join(f"- {a['name']}: {a['role']} (skills: {', '.join(a['skills'])})"
                         for a in self.agents.values() if a.get("routable", True))

    def add_tasks(self, items: list[dict], round_: int) -> None:
        existing = {t["seq"]: t["id"] for t in self.store.tasks(self.run_id)}
        added = []
        for item in items:
            if item.get("kind") not in KIND_IDS:
                item["kind"] = "strategy"
            deps = [existing[s] for s in item.get("depends_on", []) if s in existing]
            task = self.store.add_task(self.run_id, round_, item["title"], item["description"], item["kind"], deps)
            existing[task["seq"]] = task["id"]
            added.append(task)
        self.emit({"type": "plan", "round": round_, "tasks": added})

    def plan(self, goal: str, ws: Workspace) -> None:
        ceo = self.agents["ceo"]
        inputs = [f for f in ws.files() if f.startswith("inputs/")]
        prompt = (f"Company goal: {goal}\n\nUploaded inputs: {inputs or 'none'}\n\nYour team:\n{self.team_text()}\n\n"
                  f"Task kinds: {', '.join(KIND_IDS)}\n\n"
                  "Break the goal into 4–10 concrete tasks, numbered 1..N in the order given. Each task needs "
                  "a short title, a description of the exact deliverable, the kind that best fits it, and "
                  "depends_on: the numbers of earlier tasks whose results it needs. Don't name who does it; "
                  "routing is decided separately.")
        data, _ = self.call_json(PLANNER_VARIANT, ceo["system"], prompt, PLAN_SCHEMA, "plan", {"goal": goal})
        self.add_tasks(data.get("tasks", [])[:10], 1)

    def review(self, goal: str, next_round: int) -> bool:
        """CEO looks at the results so far and adds follow-up tasks. Returns True if it added any."""
        ceo = self.agents["ceo"]
        tasks = self.store.tasks(self.run_id)
        room = self.settings["max_tasks"] - self.tasks_started
        if room <= 0:
            return False
        lines = "\n".join(f"{t['seq']}. [{t['kind']}] {t['title']} ({t['status']}, score {t['judge_score']}): "
                          f"{t['summary'] or ''}" for t in tasks)
        prompt = (f"Company goal: {goal}\n\nWork so far:\n{lines}\n\nIs the goal adequately covered? If not, add up "
                  f"to {min(5, room)} follow-up tasks (number them from {len(tasks) + 1}; depends_on may reference "
                  "any task number). If it is covered, return done=true and no tasks.")
        data, _ = self.call_json(PLANNER_VARIANT, ceo["system"], prompt, REVIEW_SCHEMA, "review",
                                 {"goal": goal, "round": next_round})
        new = [] if data.get("done") else data.get("tasks", [])[:min(5, room)]
        if new:
            self.add_tasks(new, next_round)
        return bool(new)

    def execute_ready(self, goal: str, ws: Workspace) -> None:
        """Run every task whose dependencies are finished, up to max_parallel_tasks at a time.

        Routing happens here on the main thread, one task at a time, so bandit decisions stay serialized.
        Tasks dispatched together don't see each other's rewards (batched Thompson sampling).
        """
        limit = max(1, int(self.settings.get("max_parallel_tasks", 1)))
        results: queue.Queue = queue.Queue()
        running: set[str] = set()
        failure: BaseException | None = None
        while True:
            if failure is None:
                tasks = self.store.tasks(self.run_id)
                finished = {t["id"] for t in tasks if t["status"] in ("done", "failed", "skipped")}
                ready = [t for t in tasks if t["status"] == "pending"
                         and all(d in finished for d in t["depends_on"])]
                while ready and len(running) < limit and self.tasks_started < self.settings["max_tasks"]:
                    task = ready.pop(0)
                    agent_id, variant_id = self.dispatch(task)
                    running.add(task["id"])
                    threading.Thread(target=self._worker, args=(results, goal, task, agent_id, variant_id, ws),
                                     name=f"task-{task['seq']}", daemon=True).start()
                if not running:
                    if ready:  # work is left but the task cap is reached
                        raise BudgetExceeded()
                    return
            elif not running:
                raise failure
            try:
                task_id, error = results.get(timeout=0.25)
            except queue.Empty:
                continue
            running.discard(task_id)
            if error is not None and failure is None:
                failure = error  # stop dispatching; let the tasks in flight finish, then raise

    def _worker(self, results: queue.Queue, goal, task, agent_id, variant_id, ws) -> None:
        try:
            self.work(goal, task, agent_id, variant_id, ws)
            results.put((task["id"], None))
        except BaseException as e:  # reported to the scheduler on the main thread
            results.put((task["id"], e))

    def dispatch(self, task: dict) -> tuple[str, str]:
        bandits = self.bandits()
        agent_id, samples = bandits.choose_agent(task["kind"])
        variant_id, _ = bandits.choose_variant(agent_id)
        with self.lock:
            self.tasks_started += 1
            self.store.update_task(task["id"], status="running", agent=agent_id, variant=variant_id)
        self.emit({"type": "task_assigned", "task_id": task["id"], "kind": task["kind"], "agent": agent_id,
                   "variant": variant_id, "samples": {k: round(v, 4) for k, v in samples.items()}})
        return agent_id, variant_id

    def work(self, goal: str, task: dict, agent_id: str, variant_id: str, ws: Workspace) -> None:
        agent = self.agents[agent_id]
        slug = slugify(task["title"], task["seq"])
        all_tasks = {t["id"]: t for t in self.store.tasks(self.run_id)}
        deps = "\n".join(f"- {all_tasks[d]['title']}: {all_tasks[d]['summary'] or '(no summary)'} "
                         f"→ {all_tasks[d]['output_path'] or ''}" for d in task["depends_on"]) or "none"
        prompt = (f"Company goal: {goal}\n\nYour task ({task['kind']}): {task['title']}\n{task['description']}\n\n"
                  f"Results you depend on:\n{deps}\n\nFiles in the workspace:\n" + ("\n".join(ws.files()) or "(none)"))
        system = agent["system"].strip() + "\n" + WORK_RULES.format(slug=slug)
        meta = {"kind": task["kind"], "title": task["title"], "description": task["description"], "slug": slug}
        messages: list[dict] = [{"role": "user", "content": prompt}]
        cost = 0.0
        summary, status = "", "done"
        try:
            for _ in range(self.settings["max_agent_steps"]):
                reply, c = self.call(variant_id, system, messages, purpose="work", tools=True, meta=meta)
                cost += c
                messages.append({"role": "assistant", "content": reply.content})
                for b in reply.content:
                    if b.get("type") == "server_tool_use":
                        self.emit({"type": "tool_call", "task_id": task["id"], "tool": b.get("name", "web_search"),
                                   "summary": f"web search: {(b.get('input') or {}).get('query', '')}"[:120]})
                if reply.stop_reason == "refusal":
                    summary, status = "The model declined this task.", "failed"
                    break
                if reply.stop_reason == "pause_turn":  # server-side web search paused a long turn; resume it
                    continue
                uses = [b for b in reply.content if b.get("type") == "tool_use"]
                if not uses:
                    summary = reply.text
                    break
                if reply.text:
                    self.emit({"type": "agent_text", "task_id": task["id"], "text": reply.text[:300]})
                results = []
                for use in uses:
                    args = use.get("input") or {}
                    self.emit({"type": "tool_call", "task_id": task["id"], "tool": use["name"],
                               "summary": _tool_summary(use["name"], args)})
                    try:
                        out, err = ws.run(use["name"], args), False
                    except (ToolError, KeyError, OSError) as e:
                        out, err = f"Error: {e}", True
                    results.append({"type": "tool_result", "tool_use_id": use["id"], "content": out, "is_error": err})
                messages.append({"role": "user", "content": results})
            else:
                summary = summary or "Stopped at the step limit."
        except ProviderError as e:
            summary, status = f"Failed: {e}", "failed"

        output = f"tasks/{slug}.md"
        output_path = f"workspace/{output}" if (ws.root / output).exists() else None
        with self.lock:
            if self.canceled:
                raise Canceled()
            self.tasks_done += 1
            self.store.update_task(task["id"], status=status, summary=summary, output_path=output_path,
                                   cost_usd=cost)
        self.emit({"type": "task_finished", "task_id": task["id"], "status": status, "summary": summary,
                   "output_path": output_path, "cost_usd": round(cost, 4)})
        if status == "done":
            self.judge(goal, task, agent, variant_id, summary, ws, output)
        self.budget_event()

    def judge(self, goal, task, agent, variant_id, summary, ws: Workspace, output: str) -> None:
        reviewer = self.agents.get("reviewer", {"system": "You are a fair reviewer."})
        path = ws.root / output
        deliverable = path.read_text(errors="replace")[:DELIVERABLE_CHARS] if path.exists() else "(no deliverable file)"
        prompt = (f"Company goal: {goal}\n\nTask ({task['kind']}): {task['title']}\n{task['description']}\n\n"
                  f"Agent's summary: {summary}\n\nDeliverable:\n<<<\n{deliverable}\n>>>\n\n"
                  "Score from 0.0 (useless) to 1.0 (excellent, would act on it as-is), and give a one-sentence rationale.")
        meta = {"kind": task["kind"], "skills": agent["skills"], "variant": variant_id}
        data, cost = self.call_json(JUDGE_VARIANT, reviewer["system"], prompt, JUDGE_SCHEMA, "judge", meta)
        score = min(1.0, max(0.0, float(data.get("score", 0))))
        with self.lock:
            if self.canceled:
                raise Canceled()
            current = self.store.task(task["id"])
            self.store.update_task(task["id"], judge_score=score, judge_rationale=data.get("rationale", ""),
                                   cost_usd=(current["cost_usd"] or 0) + cost)
        self.emit({"type": "task_scored", "task_id": task["id"], "score": round(score, 3),
                   "rationale": data.get("rationale", "")})

    def report(self, goal: str, ws: Workspace, allow_llm: bool) -> str:
        tasks = self.store.tasks(self.run_id)
        names = {a["id"]: a["name"] for a in self.agents.values()}
        rows = [{"title": t["title"], "agent": names.get(t["agent"], t["agent"]), "judge_score": t["judge_score"],
                 "summary": t["summary"], "output_path": t["output_path"]} for t in tasks if t["status"] == "done"]
        if allow_llm:
            excerpts = []
            for t in tasks:
                if t["output_path"]:
                    text = (ws.root.parent / t["output_path"]).read_text(errors="replace")[:4000]
                    excerpts.append(f"## {t['title']} ({names.get(t['agent'])})\n{text}")
            prompt = (f"Company goal: {goal}\n\nYour team's deliverables (excerpts):\n\n" + "\n\n".join(excerpts) +
                      "\n\nWrite the final report in Markdown for the founder: an executive summary, the decisions "
                      "made, the plan, the key numbers, the open risks, and the next three actions. Link each "
                      "section to its deliverable file path (e.g. workspace/tasks/01-…md).")
            try:
                reply, _ = self.call(PLANNER_VARIANT, self.agents["ceo"]["system"],
                                     [{"role": "user", "content": prompt}], purpose="report",
                                     meta={"goal": goal, "tasks": rows})
                if reply.text and reply.stop_reason != "refusal":
                    return reply.text + "\n"
            except (BudgetExceeded, Canceled, ProviderError):
                pass
        lines = [f"# {goal}", "", "*Report assembled without the CEO (the run stopped early).*", ""]
        for r in rows:
            lines.append(f"- **{r['title']}** — {r['agent']}, score {r['judge_score']}: {r['summary']} "
                         f"({r['output_path'] or 'no file'})")
        return "\n".join(lines) + "\n"


def _tool_summary(name: str, args: dict) -> str:
    if name in ("write_file", "read_file"):
        return f"{name.replace('_', ' ')} {args.get('path', '')}"
    if name == "run_python":
        first = (args.get("code") or "").strip().splitlines()[:1]
        return f"run python: {first[0][:80] if first else ''}"
    return name.replace("_", " ")


def kinds() -> list[dict]:
    return KINDS
