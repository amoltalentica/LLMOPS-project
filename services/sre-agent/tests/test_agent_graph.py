from types import SimpleNamespace

import agent


def _block(block_type, **values):
    return SimpleNamespace(type=block_type, **values)


def test_chat_graph_runs_tool_cycle(monkeypatch):
    calls = []

    def fake_create_message(**kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            return SimpleNamespace(
                stop_reason="tool_use",
                content=[
                    _block(
                        "tool_use",
                        id="tool-1",
                        name="list_pods",
                        input={"namespace": "apps"},
                    )
                ],
            )
        return SimpleNamespace(
            stop_reason="end_turn",
            content=[_block("text", text="The app is healthy.")],
        )

    monkeypatch.setattr(agent, "client", object())
    monkeypatch.setattr(agent, "_create_message", fake_create_message)
    monkeypatch.setattr(agent, "call_tool", lambda name, args: '[{"name":"order"}]')

    messages = [{"role": "user", "content": "Check the apps namespace."}]
    answer = agent.run_loop(messages, max_steps=3)

    assert answer == "The app is healthy."
    assert [message["role"] for message in messages] == ["user", "assistant", "user", "assistant"]
    assert messages[2]["content"][0]["tool_use_id"] == "tool-1"
    assert len(calls) == 2


def test_rca_graph_runs_tools_then_structured_submission(monkeypatch):
    calls = []
    expected_rca = {"title": "CrashLoopBackOff", "severity": "SEV2"}

    def fake_create_message(**kwargs):
        calls.append(kwargs)
        if kwargs.get("tool_choice"):
            return SimpleNamespace(
                content=[
                    _block(
                        "tool_use",
                        name="submit_rca",
                        input=expected_rca,
                    )
                ]
            )
        if len(calls) == 1:
            return SimpleNamespace(
                stop_reason="tool_use",
                content=[
                    _block(
                        "tool_use",
                        id="tool-1",
                        name="scan_cluster_for_issues",
                        input={},
                    )
                ],
            )
        return SimpleNamespace(
            stop_reason="end_turn",
            content=[_block("text", text="The pod is restarting.")],
        )

    monkeypatch.setattr(agent, "client", object())
    monkeypatch.setattr(agent, "_create_message", fake_create_message)
    monkeypatch.setattr(agent, "call_tool", lambda name, args: "[]")

    result = agent.investigate_and_rca("Investigate the restart.")

    assert result == expected_rca
    assert len(calls) == 3
    assert calls[-1]["tool_choice"] == {"type": "tool", "name": "submit_rca"}


def test_rca_graph_uses_heuristic_fallback_on_model_error(monkeypatch):
    expected_rca = {"title": "Heuristic result", "severity": "SEV3"}

    def fail_model(**kwargs):
        raise RuntimeError("model unavailable")

    monkeypatch.setattr(agent, "client", object())
    monkeypatch.setattr(agent, "_create_message", fail_model)
    monkeypatch.setattr(agent, "generate_heuristic_rca", lambda question: expected_rca)

    assert agent.investigate_and_rca("Investigate the outage.") == expected_rca
