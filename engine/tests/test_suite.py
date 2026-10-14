import json
import random
import signal
import subprocess
import sys
import threading
import time

import pytest

from suite.bandit import Bandits, task_reward
from suite.cli import main
from suite.config import DEFAULT_SETTINGS, KIND_IDS
from suite.orchestrator import Orchestrator
from suite.providers import MockProvider, ProviderError, _drop_pre_fallback
from suite.store import Store
from suite.tools import ToolError, Workspace

AGENTS = [
    {"id": "a", "skills": ["math"], "variants": ["opus-high", "haiku"], "routable": True},
    {"id": "b", "skills": ["marketing"], "variants": ["opus-high", "haiku"], "routable": True},
    {"id": "judge", "skills": [], "variants": ["haiku"], "routable": False},
]


@pytest.fixture
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("SUITE_HOME", str(tmp_path))
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    return tmp_path


# --- bandits ------------------------------------------------------------------------

def test_skill_prior_makes_specialist_favourite_before_any_data():
    b = Bandits(AGENTS, rng=random.Random(0))
    picks = [b.choose_agent("math")[0] for _ in range(400)]
    assert picks.count("a") > picks.count("b")
    assert "judge" not in picks


def test_routing_bandit_learns_better_agent_against_prior():
    # b has no math skill, but keeps scoring higher on math tasks: the bandit should switch to it.
    tasks = [{"kind": "math", "agent": "a", "variant": "haiku", "judge_score": 0.2, "cost_usd": 0}] * 15 + \
            [{"kind": "math", "agent": "b", "variant": "haiku", "judge_score": 0.9, "cost_usd": 0}] * 15
    b = Bandits(AGENTS, rng=random.Random(1)).fit(tasks, user_weight=3, cost_penalty=0)
    picks = [b.choose_agent("math")[0] for _ in range(300)]
    assert picks.count("b") > 250


def test_user_rating_overrides_judge_and_weighs_more():
    t = {"kind": "math", "agent": "a", "variant": "haiku", "judge_score": 0.9, "user_rating": 0}
    assert task_reward(t, 3.0) == (0.0, 3.0)
    assert task_reward({**t, "user_rating": None}, 3.0) == (0.9, 1.0)
    b = Bandits(AGENTS).fit([t], user_weight=3, cost_penalty=0)
    arm = b.routing[("math", "a")]
    assert arm.beta == pytest.approx(1.0 + 3.0) and arm.alpha == pytest.approx(4.0)


def test_variant_bandit_pays_for_cost():
    tasks = [{"kind": "math", "agent": "a", "variant": "opus-high", "judge_score": 0.8, "cost_usd": 1.0}] * 10 + \
            [{"kind": "math", "agent": "a", "variant": "haiku", "judge_score": 0.75, "cost_usd": 0.05}] * 10
    b = Bandits(AGENTS).fit(tasks, user_weight=3, cost_penalty=0.5)
    assert b.variants[("a", "haiku")].mean > b.variants[("a", "opus-high")].mean


# --- tools --------------------------------------------------------------------------

def test_workspace_rejects_paths_outside(tmp_path):
    ws = Workspace(tmp_path / "ws")
    with pytest.raises(ToolError):
        ws.run("write_file", {"path": "../evil.txt", "content": "x"})
    ws.run("write_file", {"path": "a/b.txt", "content": "hi"})
    assert ws.run("read_file", {"path": "a/b.txt"}) == "hi"
    assert "a/b.txt" in ws.run("list_files", {})


def test_run_python_sandbox_blocks_network_and_outside_writes(tmp_path):
    ws = Workspace(tmp_path / "ws")
    outside = tmp_path / "outside.txt"
    code = (
        "import urllib.request\n"
        "open('inside.txt','w').write('ok')\n"
        "try:\n urllib.request.urlopen('https://example.com', timeout=5); print('NET-OPEN')\n"
        "except Exception: print('net-blocked')\n"
        f"try:\n open({str(outside)!r},'w').write('x'); print('WRITE-OPEN')\n"
        "except Exception: print('write-blocked')\n"
    )
    result = ws.run("run_python", {"code": code})
    assert "net-blocked" in result and "write-blocked" in result
    assert (ws.root / "inside.txt").exists() and not outside.exists()


def test_drop_pre_fallback_keeps_only_text_before_switch():
    blocks = [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "a"},
              {"type": "tool_use", "id": "x"}, {"type": "fallback"}, {"type": "text", "text": "b"}]
    assert _drop_pre_fallback(blocks) == [{"type": "text", "text": "a"}, {"type": "text", "text": "b"}]


# --- orchestration ------------------------------------------------------------------

def test_mock_run_end_to_end(home, tmp_path):
    events = []
    brief = tmp_path / "brief.txt"
    brief.write_text("We have $2M.")
    orch = Orchestrator(MockProvider(seed=3), events.append, settings=dict(DEFAULT_SETTINGS), suite_home=home,
                        rng=random.Random(3))
    run_id = orch.run("Launch a company selling a home robot that folds laundry", [brief])
    types = [e["type"] for e in events]
    assert types[0] == "run_started" and types[-1] == "run_finished"
    assert events[-1]["status"] == "done"
    assert types.count("plan") == 2  # initial plan + one follow-up round
    tasks = orch.store.tasks(run_id)
    assert all(t["status"] == "done" for t in tasks)
    assert all(t["kind"] in KIND_IDS and t["agent"] and 0 <= t["judge_score"] <= 1 for t in tasks)
    run_dir = home / "runs" / run_id
    assert (run_dir / "workspace" / "inputs" / "brief.txt").exists()
    assert (run_dir / "report.md").read_text().startswith("# Launch")
    assert len((run_dir / "events.jsonl").read_text().splitlines()) == len(events)


def test_budget_cap_stops_run_and_still_writes_report(home):
    events = []
    settings = {**DEFAULT_SETTINGS, "max_cost_usd": 0.01}
    orch = Orchestrator(MockProvider(seed=1), events.append, settings=settings, suite_home=home)
    run_id = orch.run("Start a software company")
    assert events[-1]["status"] == "budget"
    assert any(t["status"] == "skipped" for t in orch.store.tasks(run_id))
    assert "stopped early" in (home / "runs" / run_id / "report.md").read_text()


def test_task_cap(home):
    events = []
    settings = {**DEFAULT_SETTINGS, "max_tasks": 2}
    orch = Orchestrator(MockProvider(seed=1), events.append, settings=settings, suite_home=home)
    run_id = orch.run("Start a software company")
    assert sum(t["status"] == "done" for t in orch.store.tasks(run_id)) == 2
    assert events[-1]["status"] == "budget"


def test_mock_bandit_learns_over_runs(home):
    """Across runs the routing bandit should come to prefer specialists (the mock judge rewards them)."""
    for i in range(6):
        # One task at a time keeps the mock's random stream in a fixed order, so this stays deterministic.
        Orchestrator(MockProvider(seed=i), lambda e: None, settings={**DEFAULT_SETTINGS, "max_parallel_tasks": 1},
                     suite_home=home, rng=random.Random(i)).run("Launch a company selling a home robot that folds laundry")
    store = Store(home / "suite.db")
    late = [t for t in store.scored_tasks() if t["run_id"] in [r["id"] for r in store.runs()[:2]]]
    early = [t for t in store.scored_tasks() if t["run_id"] in [r["id"] for r in store.runs()[-2:]]]
    avg = lambda ts: sum(t["judge_score"] for t in ts) / len(ts)
    assert avg(late) >= avg(early) - 0.02


# --- CLI ----------------------------------------------------------------------------

def test_cli_json_commands(home, capsys):
    assert main(["run", "Build an AI app", "--mock", "--json"]) == 0
    lines = [json.loads(l) for l in capsys.readouterr().out.splitlines()]
    run_id = lines[0]["run_id"]
    assert lines[-1]["type"] == "run_finished"

    main(["runs", "--json"])
    assert json.loads(capsys.readouterr().out)[0]["id"] == run_id
    main(["show", run_id, "--json"])
    shown = json.loads(capsys.readouterr().out)
    task_id = shown["tasks"][0]["id"]
    assert shown["run"]["report"]

    main(["rate", task_id, "down", "--json"])
    assert json.loads(capsys.readouterr().out) == {"ok": True, "task_id": task_id, "rating": 0}
    main(["agents", "--json"])
    assert {a["id"] for a in json.loads(capsys.readouterr().out)} >= {"ceo", "swe", "physics", "reviewer"}
    main(["bandit", "--json"])
    snap = json.loads(capsys.readouterr().out)
    assert snap["kinds"] == KIND_IDS and snap["routing"] and snap["variants"]
    assert all(r["agent"] != "reviewer" for r in snap["routing"])


def test_sigterm_cancels_run(home, tmp_path):
    proc = subprocess.Popen([sys.executable, "-c",
                             "import time, suite.providers as p\n"
                             "orig = p.MockProvider.create\n"
                             "def slow(*a, **k):\n    time.sleep(0.5); return orig(*a, **k)\n"
                             "p.MockProvider.create = slow\n"
                             "from suite.cli import main; main(['run','Build an app','--mock','--json'])"],
                            stdout=subprocess.PIPE, text=True)
    time.sleep(2.5)
    proc.send_signal(signal.SIGTERM)
    out, _ = proc.communicate(timeout=20)
    last = json.loads(out.strip().splitlines()[-1])
    assert last["type"] == "run_finished" and last["status"] == "canceled"


# --- parallel execution -------------------------------------------------------------

class SlowMock(MockProvider):
    """Mock whose agent work takes a while, and which records how many work calls overlap."""

    def __init__(self, delay=0.15, **kw):
        super().__init__(**kw)
        self.delay, self.active, self.peak = delay, 0, 0
        self.gate = threading.Lock()

    def create(self, variant, system, messages, *, purpose, **kw):
        if purpose == "work":
            with self.gate:
                self.active += 1
                self.peak = max(self.peak, self.active)
            try:
                time.sleep(self.delay)
                return super().create(variant, system, messages, purpose=purpose, **kw)
            finally:
                with self.gate:
                    self.active -= 1
        return super().create(variant, system, messages, purpose=purpose, **kw)


def run_with(home, parallel, provider=None, **settings):
    events = []
    provider = provider or SlowMock(seed=1)
    orch = Orchestrator(provider, events.append, suite_home=home, rng=random.Random(1),
                        settings={**DEFAULT_SETTINGS, "max_parallel_tasks": parallel, **settings})
    run_id = orch.run("Launch a company selling a home robot that folds laundry")
    return orch, run_id, events, provider


def test_independent_tasks_run_in_parallel_and_respect_dependencies(home):
    orch, run_id, events, provider = run_with(home, 3)
    assert events[-1]["status"] == "done"
    assert provider.peak == 3
    tasks = {t["id"]: t for t in orch.store.tasks(run_id)}
    assert all(t["status"] == "done" and t["judge_score"] is not None for t in tasks.values())
    position = {}
    for i, e in enumerate(events):
        if e["type"] in ("task_assigned", "task_finished"):
            position[(e["type"], e["task_id"])] = i
    for t in tasks.values():
        for dep in t["depends_on"]:  # a task only starts after everything it depends on has finished
            assert position[("task_finished", dep)] < position[("task_assigned", t["id"])]


def test_parallel_is_faster_than_sequential(home, tmp_path):
    start = time.monotonic()
    run_with(home, 1)
    sequential = time.monotonic() - start
    start = time.monotonic()
    _, _, _, provider = run_with(tmp_path / "other", 4)
    assert provider.peak > 1
    assert time.monotonic() - start < sequential * 0.8


def test_parallel_one_never_overlaps(home):
    _, _, events, provider = run_with(home, 1)
    assert provider.peak == 1 and events[-1]["status"] == "done"


def test_parallel_task_cap_counts_dispatched_tasks(home):
    orch, run_id, events, _ = run_with(home, 3, max_tasks=4)
    assert events[-1]["status"] == "budget"
    statuses = [t["status"] for t in orch.store.tasks(run_id)]
    assert statuses.count("done") == 4 and "running" not in statuses


def test_parallel_budget_cap_drains_in_flight_tasks(home):
    orch, run_id, events, _ = run_with(home, 3, max_cost_usd=0.02)
    assert events[-1]["status"] == "budget"
    assert "running" not in [t["status"] for t in orch.store.tasks(run_id)]
    assert events[-1]["type"] == "run_finished" and events[-2]["type"] == "budget"


def test_worker_error_stops_dispatch_and_ends_run_with_error(home):
    class BadJudge(SlowMock):
        def _judge(self, messages, meta):
            raise ProviderError("judge exploded")
    orch, run_id, events, _ = run_with(home, 3, provider=BadJudge(seed=1))
    assert events[-1]["status"] == "error"
    assert any(e["type"] == "error" and "judge exploded" in e["message"] for e in events)
    statuses = [t["status"] for t in orch.store.tasks(run_id)]
    assert "running" not in statuses and "skipped" in statuses


def test_concurrent_run_python_calls_do_not_collide(tmp_path):
    ws = Workspace(tmp_path / "ws")
    outputs = {}

    def go(n):
        outputs[n] = ws.run("run_python", {"code": f"import time; time.sleep(0.2); print('result-{n}')"})
    threads = [threading.Thread(target=go, args=(n,)) for n in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert all(f"result-{n}" in outputs[n] for n in range(4))
    assert not list((ws.root / ".tmp").glob("*.py"))  # scripts cleaned up


def test_legacy_data_folder_moves_once_and_drops_venv(tmp_path):
    from suite.config import migrate_legacy_home
    legacy = tmp_path / "Suite of Agents"
    (legacy / "venv" / "bin").mkdir(parents=True)
    (legacy / "agents").mkdir()
    (legacy / "suite.db").write_text("db")
    current = migrate_legacy_home(tmp_path)
    assert current == tmp_path / "Avengers Assemble"
    assert (current / "suite.db").read_text() == "db" and (current / "agents").is_dir()
    assert not legacy.exists() and not (current / "venv").exists()
    legacy.mkdir()  # both present: nothing moves
    assert migrate_legacy_home(tmp_path) == current and legacy.exists()
