import json

import pytest

import tools


class LokiResponse:
    def raise_for_status(self):
        return None

    def json(self):
        return {
            "data": {
                "result": [
                    {
                        "stream": {"pod": "order-service-abc", "container": "order-service"},
                        "values": [
                            ["1730000000000000000", "password=do-not-store request failed"]
                        ],
                    }
                ]
            }
        }


def test_get_loki_logs_queries_window_and_redacts_values(monkeypatch):
    calls = {}

    def fake_get(url, params, timeout):
        calls.update(url=url, params=params, timeout=timeout)
        return LokiResponse()

    monkeypatch.setattr(tools, "LOKI_URL", "http://loki:3100/")
    monkeypatch.setattr(tools.requests, "get", fake_get)

    result = json.loads(
        tools.get_loki_logs("apps", pod='order-service-"blue"', since_minutes=30, limit=20)
    )

    assert calls["url"] == "http://loki:3100/loki/api/v1/query_range"
    assert calls["params"]["query"] == (
        '{namespace="apps",pod=' + json.dumps('order-service-"blue"') + "}"
    )
    assert calls["params"]["limit"] == 20
    assert calls["timeout"] == (2, 10)
    assert result[0]["line"] == "password=[REDACTED] request failed"


def test_get_loki_logs_rejects_non_allowlisted_namespace(monkeypatch):
    monkeypatch.setattr(tools, "ALLOWED", {"apps"})

    with pytest.raises(ValueError, match="not allowed"):
        tools.get_loki_logs("other")
