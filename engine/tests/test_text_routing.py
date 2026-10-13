import json
import random
import sqlite3

import pytest

from suite.bandit import Bandits
from suite.cli import main
from suite.config import DEFAULT_SETTINGS
from suite.orchestrator import Orchestrator
from suite.providers import MockProvider
from suite.similarity import Similarity, tokens
from suite.store import Store

AGENTS = [
    {"id": "hw", "skills": ["hardware"], "variants": ["opus-high", "haiku"], "routable": True},
    {"id": "phys", "skills": ["physics"], "variants": ["opus-high", "haiku"], "routable": True},
]


def obs(i, kind, agent, title, score, variant="haiku", cost=0.0):
    return {"id": f"t{i}", "title": title, "description": "", "kind": kind, "agent": agent, "variant": variant,
            "judge_score": score, "cost_usd": cost}


def test_tokens_fold_plurals_and_drop_stopwords():
    assert tokens("The Grippers and the gripper") == ["gripper", "gripper"]
    assert "the" not in tokens("the battery")


def test_cosine_identical_and_disjoint():
    sim = Similarity(["battery thermal limits", "pricing tiers forecast"])
    a, b = sim.vector("battery thermal limits"), sim.vector("pricing tiers forecast")
    assert Similarity.cosine(a, a) == pytest.approx(1.0)
    assert Similarity.cosine(a, b) == 0.0


def test_text_weight_zero_is_exactly_kind_only():
    history = [obs(i, "physics", "phys", "battery thermal budget", 0.9) for i in range(5)]
    b = Bandits(AGENTS, text_weight=0.0).fit(history, 3, 0)
    for agent in ("hw", "phys"):
        assert b.agent_arm("hardware", agent, "battery thermal design") is b._routing_arm("hardware", agent)
    assert b.similar("battery thermal design") == []


def test_similar_wording_carries_evidence_across_kinds():
    # The physicist excelled at battery work filed under physics: a hardware battery task now rates them higher.
    history = [obs(i, "physics", "phys", "Battery thermal limits and energy budget", 0.95) for i in range(8)]
    kind_only = Bandits(AGENTS, text_weight=0.0).fit(history, 3, 0)
    textual = Bandits(AGENTS, text_weight=0.5).fit(history, 3, 0)
    text = "Design the battery thermal system"
    assert textual.agent_arm("hardware", "phys", text).mean > kind_only.agent_arm("hardware", "phys", text).mean + 0.1
    assert textual.agent_arm("hardware", "phys", "Enclosure layout").mean == pytest.approx(
        kind_only.agent_arm("hardware", "phys", "Enclosure layout").mean)  # no shared words, no transfer


def test_wording_splits_one_kind_between_agents():
    # Within "hardware", the physicist is better at battery work and the hardware engineer at enclosures.
    # Flat priors isolate what the wording adds; with skill priors it takes more evidence to flip a specialist.
    history = [obs(i, "hardware", "phys", "Battery thermal limits and energy budget", 0.95) for i in range(8)]
    history += [obs(10 + i, "hardware", "hw", "Battery thermal limits and energy budget", 0.4) for i in range(8)]
    history += [obs(20 + i, "hardware", "hw", "Enclosure and connector layout", 0.95) for i in range(8)]
    history += [obs(30 + i, "hardware", "phys", "Enclosure and connector layout", 0.3) for i in range(8)]
    kind_only = Bandits(AGENTS, skill_priors=False, text_weight=0.0).fit(history, 3, 0)
    textual = Bandits(AGENTS, skill_priors=False, text_weight=0.5).fit(history, 3, 0)
    battery, enclosure = "Design the battery thermal system", "Enclosure connector layout"
    mean = lambda b, agent, text: b.agent_arm("hardware", agent, text).mean
    # Kind-only sees one "hardware" posterior per agent, whatever the task says...
    assert mean(kind_only, "hw", battery) == mean(kind_only, "hw", enclosure)
    assert mean(kind_only, "phys", battery) == mean(kind_only, "phys", enclosure)
    # ...wording sends each task to the agent who did that kind of work well.
    assert mean(textual, "phys", battery) > mean(textual, "hw", battery)
    assert mean(textual, "hw", enclosure) > mean(textual, "phys", enclosure)


def test_variant_bandit_uses_wording():
    history = [obs(i, "physics", "phys", "Derive the proof of convergence", 0.95, "opus-high") for i in range(6)]
    history += [obs(10 + i, "physics", "phys", "Derive the proof of convergence", 0.3, "haiku") for i in range(6)]
    history += [obs(20 + i, "physics", "phys", "Summarise unit conventions", 0.9, "haiku") for i in range(6)]
    history += [obs(30 + i, "physics", "phys", "Summarise unit conventions", 0.6, "opus-high", cost=1.0) for i in range(6)]
    b = Bandits(AGENTS, text_weight=0.8).fit(history, 3, cost_penalty=0.2)
    proof, summary = "Derive a convergence proof", "Summarise the unit conventions"
    assert b.variant_arm("phys", "opus-high", proof).mean > b.variant_arm("phys", "haiku", proof).mean
    assert b.variant_arm("phys", "haiku", summary).mean > b.variant_arm("phys", "opus-high", summary).mean


def test_similar_lists_closest_past_tasks():
    history = [obs(1, "physics", "phys", "Battery thermal limits", 0.9),
               obs(2, "hardware", "hw", "Battery enclosure", 0.7),
               obs(3, "hardware", "hw", "Marketing copy", 0.5)]
    found = Bandits(AGENTS, text_weight=0.5).fit(history, 3, 0).similar("battery thermal design")
    assert [f["task_id"] for f in found] == ["t1", "t2"]
    assert found[0]["similarity"] > found[1]["similarity"] > 0
    assert set(found[0]) == {"task_id", "title", "kind", "agent", "variant", "reward", "similarity"}


def test_old_database_gains_routing_column(tmp_path):
    db = sqlite3.connect(tmp_path / "suite.db")
    db.execute("CREATE TABLE tasks (id TEXT PRIMARY KEY, run_id TEXT NOT NULL, seq INTEGER NOT NULL, "
               "round INTEGER NOT NULL DEFAULT 1, title TEXT NOT NULL, description TEXT NOT NULL, kind TEXT NOT NULL, "
               "depends_on TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL DEFAULT 'pending', agent TEXT, variant TEXT, "
               "summary TEXT, output_path TEXT, judge_score REAL, judge_rationale TEXT, user_rating INTEGER, "
               "cost_usd REAL NOT NULL DEFAULT 0)")
    db.execute("INSERT INTO tasks (id, run_id, seq, title, description, kind) VALUES ('t1','r1',1,'a','b','math')")
    db.commit()
    db.close()
    task = Store(tmp_path / "suite.db").task("t1")
    assert task["routing"] is None and task["title"] == "a"


def test_runs_record_routing_evidence(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SUITE_HOME", str(tmp_path))
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    for i in range(2):  # the second run has history to match against
        events = []
        orch = Orchestrator(MockProvider(seed=i), events.append, suite_home=tmp_path, rng=random.Random(i),
                            settings={**DEFAULT_SETTINGS, "max_parallel_tasks": 1})
        run_id = orch.run("Launch a company selling a home robot that folds laundry")
    assigned = [e for e in events if e["type"] == "task_assigned"]
    assert all(set(e["samples"]) and isinstance(e["similar"], list) for e in assigned)
    assert any(e["similar"] for e in assigned)
    main(["show", run_id, "--json"])
    tasks = json.loads(capsys.readouterr().out)["tasks"]
    assert all(t["routing"]["samples"] for t in tasks if t["agent"])
    assert any(t["routing"]["similar"] for t in tasks if t["agent"])
