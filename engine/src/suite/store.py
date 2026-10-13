"""SQLite storage for runs, tasks and the rewards the bandits learn from."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
    id TEXT PRIMARY KEY, goal TEXT NOT NULL, status TEXT NOT NULL,
    created_at REAL NOT NULL, spent_usd REAL NOT NULL DEFAULT 0, mock INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES runs(id), seq INTEGER NOT NULL,
    round INTEGER NOT NULL DEFAULT 1, title TEXT NOT NULL, description TEXT NOT NULL,
    kind TEXT NOT NULL, depends_on TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL DEFAULT 'pending',
    agent TEXT, variant TEXT, summary TEXT, output_path TEXT,
    judge_score REAL, judge_rationale TEXT, user_rating INTEGER, cost_usd REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS tasks_run ON tasks(run_id, seq);
"""

TASK_FIELDS = ["id", "run_id", "seq", "round", "title", "description", "kind", "depends_on", "status",
               "agent", "variant", "summary", "output_path", "judge_score", "judge_rationale",
               "user_rating", "cost_usd"]


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:10]}"


def _locked(method):
    """One connection is shared by the run's worker threads; serialize every use of it."""
    def wrapper(self, *args, **kwargs):
        with self.lock:
            return method(self, *args, **kwargs)
    wrapper.__name__, wrapper.__doc__ = method.__name__, method.__doc__
    return wrapper


class Store:
    def __init__(self, path: Path):
        self.lock = threading.RLock()
        self.db = sqlite3.connect(str(path), isolation_level=None, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)

    # Runs
    @_locked
    def create_run(self, goal: str, mock: bool) -> str:
        run_id = time.strftime("r_%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:4]
        self.db.execute("INSERT INTO runs (id, goal, status, created_at, mock) VALUES (?,?,?,?,?)",
                        (run_id, goal, "running", time.time(), int(mock)))
        return run_id

    @_locked
    def update_run(self, run_id: str, **fields) -> None:
        sets = ", ".join(f"{k}=?" for k in fields)
        self.db.execute(f"UPDATE runs SET {sets} WHERE id=?", (*fields.values(), run_id))

    @_locked
    def runs(self) -> list[dict]:
        rows = self.db.execute(
            "SELECT r.*, (SELECT COUNT(*) FROM tasks t WHERE t.run_id=r.id) AS task_count "
            "FROM runs r ORDER BY created_at DESC").fetchall()
        return [_run_dict(r) for r in rows]

    @_locked
    def run(self, run_id: str) -> dict | None:
        row = self.db.execute(
            "SELECT r.*, (SELECT COUNT(*) FROM tasks t WHERE t.run_id=r.id) AS task_count "
            "FROM runs r WHERE id=?", (run_id,)).fetchone()
        return _run_dict(row) if row else None

    # Tasks
    @_locked
    def add_task(self, run_id: str, round_: int, title: str, description: str, kind: str,
                 depends_on: list[str]) -> dict:
        seq = self.db.execute("SELECT COALESCE(MAX(seq),0)+1 FROM tasks WHERE run_id=?", (run_id,)).fetchone()[0]
        task_id = new_id("t")
        self.db.execute(
            "INSERT INTO tasks (id, run_id, seq, round, title, description, kind, depends_on) VALUES (?,?,?,?,?,?,?,?)",
            (task_id, run_id, seq, round_, title, description, kind, json.dumps(depends_on)))
        return self.task(task_id)

    @_locked
    def update_task(self, task_id: str, **fields) -> None:
        sets = ", ".join(f"{k}=?" for k in fields)
        self.db.execute(f"UPDATE tasks SET {sets} WHERE id=?", (*fields.values(), task_id))

    @_locked
    def task(self, task_id: str) -> dict | None:
        row = self.db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()
        return _task_dict(row) if row else None

    @_locked
    def tasks(self, run_id: str) -> list[dict]:
        return [_task_dict(r) for r in self.db.execute("SELECT * FROM tasks WHERE run_id=? ORDER BY seq", (run_id,))]

    @_locked
    def scored_tasks(self) -> list[dict]:
        """Every finished task with a reward signal: the bandits' training data."""
        rows = self.db.execute(
            "SELECT * FROM tasks WHERE agent IS NOT NULL AND (judge_score IS NOT NULL OR user_rating IS NOT NULL)")
        return [_task_dict(r) for r in rows]


def _run_dict(row: sqlite3.Row) -> dict:
    d = dict(row)
    d["mock"] = bool(d["mock"])
    return d


def _task_dict(row: sqlite3.Row) -> dict:
    d = {k: row[k] for k in TASK_FIELDS}
    d["depends_on"] = json.loads(d["depends_on"] or "[]")
    return d
