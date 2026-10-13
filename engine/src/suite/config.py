"""Paths, settings, task kinds, model variants and prices."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_SETTINGS = {
    "mock": False,
    "max_cost_usd": 2.0,
    "max_tasks": 40,
    "user_rating_weight": 3.0,
    "cost_penalty_per_usd": 0.2,
    "max_agent_steps": 10,
}

# Task kinds, grouped into families. The app colours each family with one hue range.
KINDS = [
    {"id": "strategy", "name": "Strategy", "family": "business"},
    {"id": "marketing", "name": "Marketing", "family": "business"},
    {"id": "product", "name": "Product", "family": "business"},
    {"id": "software", "name": "Software", "family": "engineering"},
    {"id": "hardware", "name": "Hardware", "family": "engineering"},
    {"id": "robotics", "name": "Robotics", "family": "engineering"},
    {"id": "research", "name": "Research", "family": "science"},
    {"id": "ai", "name": "AI", "family": "science"},
    {"id": "math", "name": "Math", "family": "science"},
    {"id": "physics", "name": "Physics", "family": "science"},
]
KIND_IDS = [k["id"] for k in KINDS]


@dataclass(frozen=True)
class Variant:
    id: str
    model: str
    effort: str | None  # None = model does not take an effort setting
    input_per_mtok: float
    output_per_mtok: float
    web_search_tool: str


VARIANTS = {
    "opus-high": Variant("opus-high", "claude-opus-5-5", "high", 4.0, 20.0, "web_search_20260209"),
    "sonnet-medium": Variant("sonnet-medium", "claude-sonnet-5-5", "medium", 2.0, 10.0, "web_search_20260209"),
    "haiku": Variant("haiku", "claude-haiku-4-5", None, 1.0, 5.0, "web_search_20250305"),
}
WEB_SEARCH_USD = 0.01  # $10 per 1,000 searches

# Fixed models for the two roles that are not bandit-routed.
PLANNER_VARIANT = "opus-high"
JUDGE_VARIANT = "sonnet-medium"


def home() -> Path:
    env = os.environ.get("SUITE_HOME")
    path = Path(env) if env else Path.home() / "Library" / "Application Support" / "Suite of Agents"
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_settings() -> dict:
    settings = dict(DEFAULT_SETTINGS)
    path = home() / "settings.json"
    if path.exists():
        try:
            settings.update({k: v for k, v in json.loads(path.read_text()).items() if k in DEFAULT_SETTINGS})
        except (json.JSONDecodeError, OSError):
            pass
    return settings
