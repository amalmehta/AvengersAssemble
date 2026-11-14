"""Client-side tools the agents can call, confined to the run's workspace folder.

run_python runs under macOS sandbox-exec: no network, and writes allowed only inside
the workspace (which holds its own temp folder). Environment variables (including the API key) are not passed through.

read_file serves uploads (inputs/) in a form the model can read: images and PDFs as native image and
document blocks, Office files as converted Markdown. See inputs.py for how they are prepared.
"""
from __future__ import annotations

import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from . import inputs as uploads

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
        "description": "Read a file from the workspace: your uploads under inputs/ and other agents' work under "
                       "tasks/. Uploaded images come back as images you can see, PDFs as the real document (text, "
                       "tables and figures), and Word, Excel and PowerPoint files as text. A PDF longer than "
                       f"{uploads.NATIVE_PDF_PAGES} pages comes back as extracted text; pass pages (e.g. \"12-18\") "
                       f"to see up to {uploads.NATIVE_PDF_PAGES} pages of it as the real document.",
        "input_schema": {"type": "object", "additionalProperties": False, "required": ["path"],
                         "properties": {"path": {"type": "string"},
                                        "pages": {"type": "string",
                                                  "description": "PDF page range, e.g. \"5\" or \"12-18\""}}},
    },
    {
        "name": "list_files",
        "description": "List every file in the workspace with its size.",
        "input_schema": {"type": "object", "additionalProperties": False, "properties": {}},
    },
    {
        "name": "run_python",
        "description": "Run a Python 3 script in a sandbox whose working directory is the workspace. No network. "
                       "Has the standard library plus pypdf, python-docx, openpyxl and python-pptx for working "
                       "with uploads. Returns stdout and stderr. Time limit 60 s.",
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

    def run(self, name: str, args: dict) -> str | list[dict]:
        if name == "write_file":
            path = self.resolve(args["path"])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(args["content"])
            return f"Wrote {path.relative_to(self.root)} ({len(args['content'])} chars)."
        if name == "read_file":
            path = self.resolve(args["path"])
            if not path.is_file():
                raise ToolError(f"No such file: {args['path']}")
            rel = path.relative_to(self.root)
            if len(rel.parts) == 2 and rel.parts[0] == "inputs":
                manifest = uploads.manifest(self.root, path.name)
                if manifest:
                    return self.read_input(path, manifest, args.get("pages"))
            return self.read_text(path)
        if name == "list_files":
            rows = [f"{f}  ({self.resolve(f).stat().st_size} bytes)" for f in self.files()]
            return "\n".join(rows) or "(workspace is empty)"
        if name == "run_python":
            return self.run_python(args["code"])
        raise ToolError(f"Unknown tool {name}")

    def read_text(self, path: Path, limit: int = MAX_OUTPUT) -> str:
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            return (f"{path.name} is a binary file ({len(raw):,} bytes) that can't be shown as text. "
                    "Use run_python to inspect it.")
        return text if len(text) <= limit else text[:limit] + "\n…[truncated]"

    def read_input(self, path: Path, m: dict, pages: str | None) -> str | list[dict]:
        """An upload, in the most useful form the model can take."""
        prepared = self.root / "inputs" / uploads.PREPARED
        label = f"inputs/{path.name}"
        kind = m.get("kind")
        if kind == "image":
            image = prepared / m["prepared"] if not m.get("original") else path
            data = base64.standard_b64encode(image.read_bytes()).decode()
            size = f"{m.get('width')}×{m.get('height')} px"
            if m.get("original_width") and m.get("original_width") != m.get("width"):
                size += f", downscaled from {m['original_width']}×{m['original_height']}"
            return [{"type": "text", "text": f"{label} (image, {size})"},
                    {"type": "image", "source": {"type": "base64", "media_type": m["media_type"], "data": data}}]
        if kind == "pdf":
            return self.read_pdf(path, m, pages, label)
        if kind == "office":
            text = self.read_text(prepared / m["text"], uploads.MAX_TEXT_CHARS)
            return f"{label}, converted to text:\n\n{text}"
        if kind == "unreadable":
            raise ToolError(f"{label} could not be read: {m.get('error', 'unknown error')}")
        return self.read_text(path)

    def read_pdf(self, path: Path, m: dict, pages: str | None, label: str) -> str | list[dict]:
        total, limit = int(m.get("pages") or 0), uploads.NATIVE_PDF_PAGES
        if pages:
            match = re.fullmatch(r"\s*(\d+)\s*(?:-\s*(\d+))?\s*", pages)
            if not match:
                raise ToolError(f"pages must look like \"5\" or \"12-18\", not {pages!r}")
            first, last = int(match[1]), int(match[2] or match[1])
            if not 1 <= first <= last <= total:
                raise ToolError(f"{label} has pages 1-{total}; {pages!r} is out of range")
        else:
            first, last = 1, total
        if last - first + 1 <= limit:
            if (first, last) == (1, total):
                pdf = path
            else:
                pdf = self.root / "inputs" / uploads.PREPARED / "slices" / f"{path.name}.{first}-{last}.pdf"
                if not pdf.exists():
                    pdf.parent.mkdir(parents=True, exist_ok=True)
                    uploads.run_sandboxed(self.root, "slice", str(path), str(first), str(last), str(pdf))
                    if not pdf.exists():
                        raise ToolError(f"Could not extract pages {first}-{last} of {label}")
            data = base64.standard_b64encode(pdf.read_bytes()).decode()
            if (first, last) == (1, total):
                span = f"{total} page{'s' if total != 1 else ''}"
            else:
                span = (f"page {first}" if first == last else f"pages {first}-{last}") + f" of {total}"
            return [{"type": "text", "text": f"{label} (PDF, {span})"},
                    {"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": data}}]
        # Too long to send whole: text of the requested pages (or the first ones), and how to see more.
        upto = min(last, first + limit - 1) if not pages else last
        chunks = (self.root / "inputs" / uploads.PREPARED / m["text"]).read_text().split("--- Page ")
        body = "--- Page ".join([""] + chunks[first:upto + 1]).strip()
        if len(body) > uploads.MAX_TEXT_CHARS:
            body = body[:uploads.MAX_TEXT_CHARS] + "\n…[truncated]"
        return (f"{label} has {total} pages, too many to show at once, so here is the extracted text of pages "
                f"{first}-{upto}. Call read_file with pages (at most {limit}, e.g. \"{first}-{first + limit - 1}\") "
                f"to see pages as the real document, with tables and figures.\n\n{body}")

    def run_python(self, code: str) -> str:
        tmp = self.root / ".tmp"
        tmp.mkdir(exist_ok=True)
        # A unique script per call: agents working in parallel share this workspace.
        fd, name = tempfile.mkstemp(suffix=".py", dir=tmp)
        script = Path(name)
        with os.fdopen(fd, "w") as f:
            f.write(code)
        cmd = [sys.executable, "-I", str(script)]
        if shutil.which("sandbox-exec"):
            cmd = ["sandbox-exec", "-p", sandbox_profile(self.root), *cmd]
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
