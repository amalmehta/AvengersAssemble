"""Drive the real AnthropicProvider through a fake HTTP transport: no network, no key needed."""
import json
import random

import httpx2 as httpx
import anthropic

from suite.config import DEFAULT_SETTINGS, VARIANTS
from suite.orchestrator import Orchestrator
from suite.providers import AnthropicProvider


def message(content, stop="end_turn", model="claude-opus-5-5"):
    return {"id": "msg_1", "type": "message", "role": "assistant", "model": model, "content": content,
            "stop_reason": stop, "stop_sequence": None,
            "usage": {"input_tokens": 1000, "output_tokens": 500, "server_tool_use": {"web_search_requests": 1}}}


def provider_with(responder, sent):
    def handler(request: httpx.Request):
        body = json.loads(request.content)
        sent.append({"body": body, "headers": dict(request.headers)})
        return httpx.Response(200, json=responder(body))
    p = AnthropicProvider(api_key="sk-test")
    p.client = anthropic.Anthropic(api_key="sk-test", http_client=httpx.Client(transport=httpx.MockTransport(handler)))
    return p


def test_request_shape_and_cost():
    sent = []
    p = provider_with(lambda b: message([{"type": "text", "text": "hi"}]), sent)
    reply = p.create(VARIANTS["opus-high"], "sys", [{"role": "user", "content": "x"}], purpose="work", tools=True)
    body, headers = sent[0]["body"], sent[0]["headers"]
    assert body["model"] == "claude-opus-5-5"
    assert body["output_config"] == {"effort": "high"}
    assert body["fallbacks"] == "default" and "server-side-fallback-2026-07-01" in headers["anthropic-beta"]
    assert "thinking" not in body and "tool_choice" not in body
    names = [t["name"] for t in body["tools"]]
    assert names == ["write_file", "read_file", "list_files", "run_python", "web_search"]
    assert body["tools"][-1]["type"] == "web_search_20260209"
    assert reply.text == "hi"
    # 1000 in * $4/M + 500 out * $20/M + 1 search * $0.01
    assert abs(reply.usage.cost(VARIANTS["opus-high"]) - (0.004 + 0.01 + 0.01)) < 1e-9


def test_haiku_has_no_effort_or_fallbacks_and_uses_basic_search():
    sent = []
    p = provider_with(lambda b: message([{"type": "text", "text": "ok"}], model="claude-haiku-4-5"), sent)
    p.create(VARIANTS["haiku"], "sys", [{"role": "user", "content": "x"}], purpose="work", tools=True)
    body = sent[0]["body"]
    assert body["model"] == "claude-haiku-4-5"
    assert "output_config" not in body and "fallbacks" not in body
    assert body["tools"][-1]["type"] == "web_search_20250305"


def test_structured_output_request():
    sent = []
    p = provider_with(lambda b: message([{"type": "text", "text": '{"score": 0.5, "rationale": "ok"}'}]), sent)
    schema = {"type": "object", "properties": {"score": {"type": "number"}}}
    p.create(VARIANTS["sonnet-medium"], "sys", [{"role": "user", "content": "x"}], purpose="judge", json_schema=schema)
    assert sent[0]["body"]["output_config"] == {"effort": "medium", "format": {"type": "json_schema", "schema": schema}}


def test_full_run_through_fake_api(tmp_path, monkeypatch):
    """A whole run against scripted API replies: plan → tool loop → judge → review → report."""
    monkeypatch.setenv("SUITE_HOME", str(tmp_path))
    sent = []

    def responder(body):
        system, last = body["system"], body["messages"][-1]
        fmt = (body.get("output_config") or {}).get("format")
        if fmt and "tasks" in fmt["schema"]["properties"] and "done" not in fmt["schema"]["properties"]:
            plan = {"tasks": [{"title": "Model unit economics", "description": "Per-unit margin.", "kind": "math",
                               "depends_on": []}]}
            return message([{"type": "text", "text": json.dumps(plan)}])
        if fmt and "done" in fmt["schema"]["properties"]:
            return message([{"type": "text", "text": json.dumps({"done": True, "reason": "ok", "tasks": []})}])
        if fmt:
            return message([{"type": "text", "text": json.dumps({"score": 0.9, "rationale": "Solid."})}])
        if body.get("tools"):
            if last["role"] == "user" and isinstance(last["content"], str):
                return message([{"type": "thinking", "thinking": "", "signature": "sig"},
                                {"type": "tool_use", "id": "toolu_1", "name": "write_file",
                                 "input": {"path": "tasks/01-model-unit-economics.md", "content": "# Margin 42%"}}],
                               stop="tool_use")
            assert last["content"][0]["type"] == "tool_result"  # tool results go back in one user message
            assert body["messages"][1]["content"][0]["type"] == "thinking"  # assistant blocks echoed unchanged
            return message([{"type": "text", "text": "Margin is 42%."}])
        return message([{"type": "text", "text": "# Report\nMargin 42%."}])

    p = provider_with(responder, sent)
    events = []
    orch = Orchestrator(p, events.append, settings=dict(DEFAULT_SETTINGS), suite_home=tmp_path, rng=random.Random(0))
    run_id = orch.run("Sell robots")
    assert events[-1]["status"] == "done"
    task = orch.store.tasks(run_id)[0]
    assert task["judge_score"] == 0.9 and task["summary"] == "Margin is 42%."
    assert task["output_path"] == "workspace/tasks/01-model-unit-economics.md"
    assert (tmp_path / "runs" / run_id / "report.md").read_text().startswith("# Report")
