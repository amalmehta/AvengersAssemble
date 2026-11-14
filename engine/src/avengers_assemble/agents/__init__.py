"""Agent definitions: YAML files seeded into the data folder, where people can edit them."""
from __future__ import annotations

import shutil
from pathlib import Path

import yaml

from ..config import VARIANTS

DEFAULTS_DIR = Path(__file__).parent


def agents_dir(home: Path) -> Path:
    """The editable agents folder; seeded with the defaults the first time."""
    folder = home / "agents"
    if not folder.exists():
        folder.mkdir(parents=True)
        for f in DEFAULTS_DIR.glob("*.yaml"):
            shutil.copy(f, folder / f.name)
    return folder


def load_agents(home: Path) -> list[dict]:
    agents = []
    for path in sorted(agents_dir(home).glob("*.yaml")):
        data = yaml.safe_load(path.read_text()) or {}
        if not data.get("id"):
            continue
        data.setdefault("name", data["id"])
        data.setdefault("role", "")
        data.setdefault("skills", [])
        data.setdefault("routable", True)
        data.setdefault("system", "")
        data["variants"] = [v for v in data.get("variants") or list(VARIANTS) if v in VARIANTS] or ["sonnet-medium"]
        data["path"] = str(path)
        agents.append(data)
    return agents
