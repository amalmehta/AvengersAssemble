"""LLM providers: the Claude API, and an offline mock with the same interface.

Every call returns a Reply whose content is a list of plain dict blocks (text,
tool_use, server tool blocks...), so the agent loop can append it back unchanged.
"""
from __future__ import annotations

import json
import os
import random
import re
import textwrap
import zlib
from dataclasses import dataclass, field

from .config import VARIANTS, WEB_SEARCH_USD, Variant
from .tools import TOOL_DEFS

FALLBACK_BETA = "server-side-fallback-2026-07-01"


@dataclass
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0
    web_searches: int = 0

    def cost(self, variant: Variant) -> float:
        return (self.input_tokens * variant.input_per_mtok + self.output_tokens * variant.output_per_mtok) / 1e6 \
            + self.web_searches * WEB_SEARCH_USD


@dataclass
class Reply:
    content: list[dict]
    stop_reason: str
    usage: Usage = field(default_factory=Usage)

    @property
    def text(self) -> str:
        return "\n".join(b["text"] for b in self.content if b.get("type") == "text").strip()


class ProviderError(Exception):
    pass


class Provider:
    name = "base"

    def create(self, variant: Variant, system: str, messages: list[dict], *, purpose: str,
               tools: bool = False, json_schema: dict | None = None, meta: dict | None = None) -> Reply:
        raise NotImplementedError


class AnthropicProvider(Provider):
    name = "anthropic"

    def __init__(self, api_key: str | None = None):
        import anthropic
        self.anthropic = anthropic
        self.client = anthropic.Anthropic(api_key=api_key or os.environ.get("ANTHROPIC_API_KEY"), max_retries=3)

    def create(self, variant, system, messages, *, purpose, tools=False, json_schema=None, meta=None):
        params: dict = {"model": variant.model, "max_tokens": 16000, "system": system, "messages": messages}
        output_config: dict = {}
        if variant.effort:
            output_config["effort"] = variant.effort
        if json_schema:
            output_config["format"] = {"type": "json_schema", "schema": json_schema}
        if output_config:
            params["output_config"] = output_config
        if tools:
            params["tools"] = [*TOOL_DEFS, {"type": variant.web_search_tool, "name": "web_search", "max_uses": 5}]
        if variant.model != "claude-haiku-4-5":
            # If a safety classifier declines, the API re-runs the request on its recommended fallback model.
            params["betas"] = [FALLBACK_BETA]
            params["fallbacks"] = "default"
        try:
            resp = self.client.beta.messages.create(**params)
        except self.anthropic.AuthenticationError as e:
            raise ProviderError("The Anthropic API key was rejected. Check it in Settings.") from e
        except self.anthropic.RateLimitError as e:
            raise ProviderError("Rate limited by the Anthropic API even after retries.") from e
        except self.anthropic.APIStatusError as e:
            raise ProviderError(f"Anthropic API error {e.status_code}: {e.message}") from e
        except self.anthropic.APIConnectionError as e:
            raise ProviderError("Could not reach the Anthropic API.") from e

        blocks = [b.model_dump(mode="json", exclude_none=True) for b in resp.content]
        return Reply(_drop_pre_fallback(blocks), resp.stop_reason or "end_turn", _usage(resp.usage))


def _drop_pre_fallback(blocks: list[dict]) -> list[dict]:
    """After a mid-output fallback only text before the switch may be echoed back."""
    last = max((i for i, b in enumerate(blocks) if b.get("type") == "fallback"), default=None)
    if last is None:
        return blocks
    return [b for b in blocks[:last] if b.get("type") == "text"] + blocks[last + 1:]


def _usage(u) -> Usage:
    iterations = getattr(u, "iterations", None) or []
    if iterations:  # with a fallback, every attempt is listed here; the top-level fields cover only the last
        inp = sum((getattr(i, "input_tokens", 0) or 0) + (getattr(i, "cache_read_input_tokens", 0) or 0)
                  + (getattr(i, "cache_creation_input_tokens", 0) or 0) for i in iterations)
        out = sum(getattr(i, "output_tokens", 0) or 0 for i in iterations)
    else:
        inp = (u.input_tokens or 0) + (getattr(u, "cache_read_input_tokens", 0) or 0) \
            + (getattr(u, "cache_creation_input_tokens", 0) or 0)
        out = u.output_tokens or 0
    stu = getattr(u, "server_tool_use", None)
    searches = (getattr(stu, "web_search_requests", 0) or 0) if stu else 0
    return Usage(inp, out, searches)


# --------------------------------------------------------------------------------------
# Offline mock
# --------------------------------------------------------------------------------------

KEYWORD_KINDS = {
    "software": ["app", "software", "platform", "saas", "api", "website", "code"],
    "hardware": ["device", "hardware", "robot", "sensor", "battery", "chip", "drone", "machine"],
    "robotics": ["robot", "drone", "autonomous", "arm", "fold"],
    "ai": ["ai", "model", "learning", "vision", "agent", "llm", "intelligen"],
    "physics": ["energy", "battery", "physics", "rocket", "solar", "fusion", "thermal", "drone"],
    "math": ["math", "optimiz", "pricing", "forecast", "proof", "statistic"],
}

TASK_TEMPLATES = {
    "strategy": ("Define the business model", "Decide who pays, for what, how much, and why now. State the key bets."),
    "research": ("Research the market and competitors", "Size the market, list competitors with links, find gaps."),
    "product": ("Write the v1 product spec", "User stories, acceptance criteria, scope cuts and a roadmap."),
    "marketing": ("Plan the launch", "Positioning, ideal customer, channels with costs, and launch copy."),
    "software": ("Build the software prototype", "Design and write the core software, with a quick test."),
    "hardware": ("Design the hardware and BOM", "Block diagram, key components and a bill-of-materials cost."),
    "robotics": ("Design the robot system", "Mechanism, sensors, control loop and a feasibility check."),
    "ai": ("Design the AI system", "Model choice, data strategy, compute estimate and evaluation plan."),
    "physics": ("Check the physics", "First-principles feasibility: energy, forces, materials, with units."),
    "math": ("Build the quantitative model", "Unit economics or optimisation model, verified numerically."),
}
# Alternative tasks of the same kind whose wording calls for a different expert than the kind's
# specialist: the kind label alone is too coarse to route them well. The mock judge knows this.
HIDDEN_EXPERT_TEMPLATES = {
    "strategy": ("Map the competitor landscape", "Competitor teardown with sources, their pricing and market gaps."),
    "research": ("Survey gripper mechanisms", "Survey gripper and manipulator designs and how they grasp soft objects."),
    "product": ("Set the pricing tiers", "Pricing elasticity model and tiers with a twelve-month revenue forecast."),
    "marketing": ("Build the signup landing page", "A working landing page with a signup form and its code."),
    "software": ("Build the vision dataset pipeline", "Collect and label a vision dataset and the training data pipeline."),
    "hardware": ("Design the battery and thermal system", "Battery chemistry, thermal limits and an energy budget with units."),
    "robotics": ("Design the vision model for grasp detection", "Train a vision model on a labelled dataset to find grasp points."),
    "ai": ("Model the compute and pricing economics", "Forecast inference compute cost and the pricing that covers it."),
    "physics": ("Design the drive motor and battery", "Motor torque and battery energy with thermal limits, in units."),
    "math": ("Research prior proofs and competitor methods", "Literature and competitor survey of existing methods, with sources."),
}
HIDDEN_EXPERTS = {  # word in the task → the agent who is actually best at it
    "competitor": "researcher", "gripper": "robotics", "manipulator": "robotics", "pricing": "math",
    "elasticity": "math", "forecast": "math", "signup": "swe", "landing": "swe", "vision": "ai", "dataset": "ai",
    "battery": "physics", "thermal": "physics", "torque": "physics",
}


def best_agent(kind: str, text: str, agents: dict) -> str | None:
    """Who the mock judge rewards most for a task: a hidden expert if the wording names one."""
    words = text.lower()
    for word, expert in HIDDEN_EXPERTS.items():
        if word in words:
            return expert
    return next((a["id"] for a in agents.values() if a.get("skills") and a["skills"][0] == kind), None)


FOLLOW_UPS = [
    ("strategy", "Stress-test the plan", "List the five biggest risks across all work so far and a mitigation for each."),
    ("math", "Model the first-year financials", "Revenue, costs and cash by month for year one, with assumptions."),
]


class MockProvider(Provider):
    """Deterministic stand-in for the API, for tests, demos and running without a key.

    Its judge prefers specialists and stronger models, with noise, so the bandits have something
    real to learn: run it a few times and watch the Bandit view converge.
    """
    name = "mock"

    def __init__(self, seed: int | None = None):
        self.rng = random.Random(seed)

    def create(self, variant, system, messages, *, purpose, tools=False, json_schema=None, meta=None):
        meta = meta or {}
        handler = getattr(self, f"_{purpose}")
        content, stop = handler(messages, meta)
        media = [0]

        def strip_media(obj):  # count images and documents as a flat token cost, not by base64 length
            if isinstance(obj, dict):
                if obj.get("type") in ("image", "document") and isinstance(obj.get("source"), dict):
                    media[0] += 1
                    return {"type": obj["type"]}
                return {k: strip_media(v) for k, v in obj.items()}
            if isinstance(obj, list):
                return [strip_media(v) for v in obj]
            return obj
        prompt_chars = len(system) + len(json.dumps(strip_media(messages)))
        out_chars = len(json.dumps(content))
        return Reply(content, stop, Usage(prompt_chars // 4 + 1500 * media[0], out_chars // 4, 0))

    @staticmethod
    def _text(s: str) -> tuple[list[dict], str]:
        return [{"type": "text", "text": s}], "end_turn"

    def _plan(self, messages, meta):
        goal = meta.get("goal", "").lower()
        kinds = ["strategy", "research", "product"]
        for kind, words in KEYWORD_KINDS.items():
            if any(re.search(rf"\b{w}", goal) for w in words) and kind not in kinds:
                kinds.append(kind)
        kinds.append("marketing")
        tasks = []
        for i, kind in enumerate(kinds):
            # Half the goals get the hidden-expert version of a kind's task (stable per goal and kind).
            alt = zlib.crc32(f"{goal}|{kind}".encode()) % 2 == 1
            title, desc = (HIDDEN_EXPERT_TEMPLATES if alt else TASK_TEMPLATES)[kind]
            deps = [] if kind in ("strategy", "research") else [1]
            tasks.append({"title": title, "description": desc, "kind": kind, "depends_on": [d for d in deps if d < i]})
        return self._text(json.dumps({"tasks": tasks}))

    def _review(self, messages, meta):
        if meta.get("round", 2) >= 3:
            return self._text(json.dumps({"done": True, "reason": "The plan is covered.", "tasks": []}))
        tasks = [{"title": t, "description": d, "kind": k, "depends_on": []} for k, t, d in FOLLOW_UPS]
        return self._text(json.dumps({"done": False, "reason": "Two gaps remain.", "tasks": tasks}))

    def _work(self, messages, meta):
        kind, title, slug = meta.get("kind", "strategy"), meta.get("title", "Task"), meta.get("slug", "task")
        turns = sum(1 for m in messages if m["role"] == "assistant")
        numeric = kind in ("math", "physics", "software", "ai", "robotics")
        # Open an upload (a PDF or image if there is one) before doing anything else.
        listed = re.findall(r"^(inputs/.+?)\s*$", messages[0]["content"], re.M) if messages else []
        listed.sort(key=lambda f: not re.search(r"\.(pdf|png|jpe?g|gif|webp|heic)$", f, re.I))
        first_input = re.match(r"(.+)", listed[0]) if listed else None
        seen = self._seen_inputs(messages)
        if turns == 0 and first_input:
            return [{"type": "text", "text": "Reading the founder's upload first."},
                    {"type": "tool_use", "id": f"toolu_mock_{self.rng.randrange(10**8)}", "name": "read_file",
                     "input": {"path": first_input.group(1)}}], "tool_use"
        turns -= 1 if first_input else 0
        if turns == 0 and numeric:
            code = "import math\nmass, g, h = 1.2, 9.81, 0.5\nprint(f'energy per lift: {mass*g*h:.2f} J')\n"
            return [{"type": "text", "text": "Checking the numbers first."},
                    {"type": "tool_use", "id": f"toolu_mock_{self.rng.randrange(10**8)}", "name": "run_python",
                     "input": {"code": code}}], "tool_use"
        if turns == (1 if numeric else 0):
            body = textwrap.dedent(f"""\
                # {title}

                *Offline mock output, produced without calling a model.*

                ## Approach
                {meta.get('description', '')}

                ## Findings
                - Assumption A: the target customer has the problem weekly.
                - Assumption B: a v1 can ship in 6 months with a team of five.
                - Open question: which channel converts best (to test in the first month).
                """)
            return [{"type": "tool_use", "id": f"toolu_mock_{self.rng.randrange(10**8)}", "name": "write_file",
                     "input": {"path": f"tasks/{slug}.md", "content": body}}], "tool_use"
        note = f" Read {seen}." if seen else ""
        return self._text(f"Done: wrote tasks/{slug}.md covering {title.lower()} with three stated assumptions.{note}")

    @staticmethod
    def _seen_inputs(messages) -> str:
        """What the mock 'saw' in tool results: proof the upload reached the model as a native block."""
        kinds = []
        for m in messages:
            for block in m["content"] if isinstance(m["content"], list) else []:
                for part in block.get("content", []) if block.get("type") == "tool_result" and \
                        isinstance(block.get("content"), list) else []:
                    if part.get("type") in ("image", "document"):
                        kinds.append(part["type"])
        return " and ".join(sorted(set(kinds)))

    def _judge(self, messages, meta):
        kind, skills, variant = meta.get("kind"), meta.get("skills", []), meta.get("variant")
        text, agent = meta.get("text", "").lower(), meta.get("agent")
        expert = next((e for w, e in HIDDEN_EXPERTS.items() if w in text), None)
        score = 0.40
        if expert and agent == expert:
            score += 0.35
        elif expert:  # the kind's specialist is only middling when the work needs someone else
            score += 0.10 if kind in skills else 0.0
        elif skills and skills[0] == kind:
            score += 0.35
        elif kind in skills:
            score += 0.15
        score += {"opus-high": 0.08, "sonnet-medium": 0.05}.get(variant, 0.0)
        score = min(1.0, max(0.0, score + self.rng.uniform(-0.12, 0.12)))
        why = "Specialist work with concrete assumptions." if score > 0.7 else "Generic; a specialist would go deeper."
        return self._text(json.dumps({"score": round(score, 2), "rationale": why}))

    def _report(self, messages, meta):
        lines = [f"# {meta.get('goal', 'Report')}", "", "*Offline mock report.*", "", "## What the team did"]
        for t in meta.get("tasks", []):
            lines.append(f"- **{t['title']}** ({t['agent']}, score {t.get('judge_score')}): {t.get('summary')}")
        lines += ["", "## Next steps", "- Validate the riskiest assumption with ten customer calls."]
        return self._text("\n".join(lines))


def make_provider(mock: bool) -> Provider:
    if mock or not os.environ.get("ANTHROPIC_API_KEY"):
        return MockProvider()
    return AnthropicProvider()


__all__ = ["Provider", "AnthropicProvider", "MockProvider", "Reply", "Usage", "ProviderError", "make_provider",
           "VARIANTS"]
