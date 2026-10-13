"""Client-side tools the agents can call, confined to the run's workspace folder.

run_python runs under macOS sandbox-exec: no network, and writes allowed only inside
the workspace (which holds its own temp folder). Environment variables (including the API key) are not passed through.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

MAX_OUTPUT = 12_000
PYTHON_TIMEOUT_S = 60

TOOL_DEFS = [
    {
        "name": "write_file",
        "description": "Write a text file into the shared company workspace (creates folders). Use it for every "
                       "deliverable: documents, code, data. Paths are relative to the workspace.",
        "input_schema": {"type": "object", "additionalProperties": False, "required": ["path", "content"],
                         "properties": {"path": {"type": "string"}, "content": {"type": "string"}}},
    },
    {
        "name": "read_file",
        "description": "Read a text file from the workspace, including uploaded inputs under inputs/ and other "
                       "agents' work under tasks/.",
        "input_schema": {"type": "object", "additionalProperties": False, "required": ["path"],
                         "properties": {"path": {"type": "string"}}},
    },
    {
        "name": "list_files",
        "description": "List every file in the workspace with its size.",
        "input_schema": {"type": "object", "additionalProperties": False, "properties": {}},
    },
    {
        "name": "run_python",
        "description": "Run a Python 3 script in a sandbox whose working directory is the workspace. No network. "
                       "Has the standard library only. Returns stdout and stderr. Time limit 60 s.",
        "input_schema": {"type": "object", "additionalProperties": False, "required": ["code"],
                         "properties": {"code": {"type": "string"}}},
    },
]


class ToolError(Exception):
    pass


class Workspace:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def resolve(self, rel: str) -> Path:
        path = (self.root / rel).resolve()
        if path != self.root and self.root not in path.parents:
            raise ToolError(f"Path {rel!r} is outside the workspace.")
        return path

    def files(self) -> list[str]:
        rels = (p.relative_to(self.root) for p in self.root.rglob("*") if p.is_file())
        return sorted(str(r) for r in rels if not any(part.startswith(".") for part in r.parts))

    def run(self, name: str, args: dict) -> str:
        if name == "write_file":
            path = self.resolve(args["path"])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(args["content"])
            return f"Wrote {path.relative_to(self.root)} ({len(args['content'])} chars)."
        if name == "read_file":
            path = self.resolve(args["path"])
            if not path.is_file():
                raise ToolError(f"No such file: {args['path']}")
            text = path.read_text(errors="replace")
            return text if len(text) <= MAX_OUTPUT else text[:MAX_OUTPUT] + "\n…[truncated]"
        if name == "list_files":
            rows = [f"{f}  ({self.resolve(f).stat().st_size} bytes)" for f in self.files()]
            return "\n".join(rows) or "(workspace is empty)"
        if name == "run_python":
            return self.run_python(args["code"])
        raise ToolError(f"Unknown tool {name}")

    def run_python(self, code: str) -> str:
        script = self.root / ".run.py"
        script.write_text(code)
        cmd = [sys.executable, "-I", str(script)]
        if shutil.which("sandbox-exec"):
            cmd = ["sandbox-exec", "-p", sandbox_profile(self.root), *cmd]
        tmp = self.root / ".tmp"
        tmp.mkdir(exist_ok=True)
        env = {"PATH": "/usr/bin:/bin", "HOME": str(self.root), "TMPDIR": str(tmp)}
        try:
            proc = subprocess.run(cmd, cwd=self.root, env=env, capture_output=True, text=True,
                                  timeout=PYTHON_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return f"Timed out after {PYTHON_TIMEOUT_S} s."
        finally:
            script.unlink(missing_ok=True)
        out = f"exit code {proc.returncode}\n--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        return out if len(out) <= MAX_OUTPUT else out[:MAX_OUTPUT] + "\n…[truncated]"


def sandbox_profile(root: Path) -> str:
    root = os.path.realpath(root)
    return f"""(version 1)
(allow default)
(deny network*)
(deny file-write*)
(allow file-write* (subpath "{root}") (literal "/dev/null") (literal "/dev/dtracehelper"))
"""
