"""The `suite` command line. The Mac app drives the engine through these commands."""
from __future__ import annotations

import argparse
import json
import signal
import sys
from pathlib import Path

from .agents import agents_dir, load_agents
from .bandit import Bandits
from .config import KIND_IDS, KINDS, home, load_settings
from .orchestrator import Canceled, Orchestrator
from .providers import make_provider
from .store import Store

ICONS = {"run_started": "▶", "plan": "🗺", "task_assigned": "→", "tool_call": "  ·", "agent_text": "  …",
         "task_finished": "✓", "task_scored": "  ★", "run_finished": "■", "error": "✗"}


def pretty(event: dict) -> str | None:
    t = event["type"]
    icon = ICONS.get(t, " ")
    if t == "run_started":
        return f"{icon} Run {event['run_id']}{' (offline mock)' if event['mock'] else ''}: {event['goal']}"
    if t == "plan":
        return f"{icon} Round {event['round']} plan:\n" + "\n".join(
            f"   {x['seq']:>2}. [{x['kind']}] {x['title']}" for x in event["tasks"])
    if t == "task_assigned":
        return f"{icon} {event['agent']} ({event['variant']}) takes a {event['kind']} task"
    if t in ("tool_call",):
        return f"{icon} {event['summary']}"
    if t == "agent_text":
        return f"{icon} {event['text'][:120]}"
    if t == "task_finished":
        return f"{icon} {event['status']}: {event['summary'][:160]}  (${event['cost_usd']:.3f})"
    if t == "task_scored":
        return f"{icon} judge {event['score']:.2f}: {event['rationale'][:120]}"
    if t == "run_finished":
        return f"{icon} {event['status']} · spent ${event['spent_usd']:.3f} · report: {event['report_path']}"
    if t == "error":
        return f"{icon} {event['message']}"
    return None


def out(data) -> None:
    print(json.dumps(data, indent=None), flush=True)


def cmd_run(args) -> int:
    settings = load_settings()
    if args.mock:
        settings["mock"] = True
    if args.max_cost is not None:
        settings["max_cost_usd"] = args.max_cost
    if args.max_tasks is not None:
        settings["max_tasks"] = args.max_tasks
    if args.parallel is not None:
        settings["max_parallel_tasks"] = max(1, args.parallel)

    def emit(event: dict) -> None:
        if args.json:
            out(event)
        else:
            line = pretty(event)
            if line:
                print(line, flush=True)

    orch = Orchestrator(make_provider(settings["mock"]), emit, settings=settings)

    def stop(signum, frame):
        orch.canceled = True
        raise Canceled()

    signal.signal(signal.SIGTERM, stop)
    inputs = [Path(p).expanduser().resolve() for p in args.input or []]
    missing = [str(p) for p in inputs if not p.is_file()]
    if missing:
        print(f"Input file not found: {', '.join(missing)}", file=sys.stderr)
        return 2
    orch.run(args.goal, inputs)
    return 0


def cmd_runs(args) -> int:
    runs = Store(home() / "suite.db").runs()
    if args.json:
        out(runs)
    else:
        for r in runs:
            print(f"{r['id']}  {r['status']:<8} ${r['spent_usd']:.3f}  {r['task_count']:>2} tasks  {r['goal'][:70]}")
    return 0


def cmd_show(args) -> int:
    store = Store(home() / "suite.db")
    run = store.run(args.run_id)
    if not run:
        print(f"No run {args.run_id}", file=sys.stderr)
        return 1
    run_dir = home() / "runs" / run["id"]
    report = run_dir / "report.md"
    run["report"] = report.read_text() if report.exists() else None
    run["workspace"] = str(run_dir / "workspace")
    tasks = store.tasks(run["id"])
    if args.json:
        out({"run": run, "tasks": tasks})
    else:
        print(f"{run['goal']}  [{run['status']}, ${run['spent_usd']:.3f}]")
        for t in tasks:
            score = "" if t["judge_score"] is None else f"{t['judge_score']:.2f}"
            print(f" {t['seq']:>2}. [{t['kind']}] {t['title']}  — {t['agent']}/{t['variant']}  {t['status']} {score}")
        if run["report"]:
            print("\n" + run["report"])
    return 0


def cmd_rate(args) -> int:
    store = Store(home() / "suite.db")
    if not store.task(args.task_id):
        print(f"No task {args.task_id}", file=sys.stderr)
        return 1
    rating = {"up": 1, "down": 0, "clear": None}[args.rating]
    store.update_task(args.task_id, user_rating=rating)
    if args.json:
        out({"ok": True, "task_id": args.task_id, "rating": rating})
    else:
        print(f"Rated {args.task_id}: {args.rating}")
    return 0


def cmd_agents(args) -> int:
    agents = load_agents(home())
    if args.json:
        out([{k: a[k] for k in ("id", "name", "role", "skills", "variants", "routable", "path")} for a in agents])
    else:
        print(f"Agents folder: {agents_dir(home())}")
        for a in agents:
            print(f" {a['name']:<20} {', '.join(a['skills']):<28} {a['role']}")
    return 0


def cmd_bandit(args) -> int:
    s = load_settings()
    b = Bandits(load_agents(home())).fit(Store(home() / "suite.db").scored_tasks(),
                                          s["user_rating_weight"], s["cost_penalty_per_usd"])
    snap = b.snapshot(KIND_IDS)
    if args.json:
        out(snap)
    else:
        agents = sorted({r["agent"] for r in snap["routing"]})
        print("Routing posterior means (rows: kinds, cols: agents)")
        print(" " * 10 + "".join(f"{a[:9]:>10}" for a in agents))
        for kind in snap["kinds"]:
            cells = {r["agent"]: r for r in snap["routing"] if r["kind"] == kind}
            print(f"{kind:<10}" + "".join(f"{cells[a]['mean']:>10.2f}" for a in agents))
    return 0


def cmd_kinds(args) -> int:
    if args.json:
        out(KINDS)
    else:
        for k in KINDS:
            print(f"{k['name']:<10} {k['family']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="suite", description="Avengers Assemble: a company of agents routed by bandits.")
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="Run a goal with the whole team")
    r.add_argument("goal")
    r.add_argument("--input", action="append", help="A file to give the team (repeatable)")
    r.add_argument("--mock", action="store_true", help="Use the offline mock instead of the Claude API")
    r.add_argument("--max-cost", type=float, help="Budget cap in US dollars for this run")
    r.add_argument("--max-tasks", type=int, help="Cap on tasks executed in this run")
    r.add_argument("--parallel", type=int, help="How many independent tasks may run at once (1 = one at a time)")
    r.set_defaults(fn=cmd_run)

    for name, fn, help_ in [("runs", cmd_runs, "List runs"), ("agents", cmd_agents, "List agents"),
                            ("bandit", cmd_bandit, "Show what the bandits have learned"),
                            ("kinds", cmd_kinds, "List task kinds")]:
        sp = sub.add_parser(name, help=help_)
        sp.set_defaults(fn=fn)
    s = sub.add_parser("show", help="Show one run")
    s.add_argument("run_id")
    s.set_defaults(fn=cmd_show)
    rt = sub.add_parser("rate", help="Rate a task's result: up, down or clear")
    rt.add_argument("task_id")
    rt.add_argument("rating", choices=["up", "down", "clear"])
    rt.set_defaults(fn=cmd_rate)

    for sp in sub.choices.values():
        sp.add_argument("--json", action="store_true", help="Machine-readable output")
    args = p.parse_args(argv)
    try:
        return args.fn(args)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
