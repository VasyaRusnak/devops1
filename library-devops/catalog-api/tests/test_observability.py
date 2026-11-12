import json
import logging

import mongomock
import pytest
from fastapi.testclient import TestClient

from app.db import get_database
from app.main import app
from app.observability import JsonFormatter

fake_client = mongomock.MongoClient()


def override_get_database():
    return fake_client["library_test"]


app.dependency_overrides[get_database] = override_get_database
client = TestClient(app)


def test_metrics_endpoint_counts_requests() -> None:
    assert client.get("/books").status_code == 200
    resp = client.get("/metrics")
    assert resp.status_code == 200
    body = resp.text
    assert "http_requests_total" in body
    assert 'route="/books"' in body
    assert "http_request_duration_seconds_bucket" in body


def test_health_is_not_counted_in_metrics() -> None:
    client.get("/health")
    assert 'route="/health"' not in client.get("/metrics").text


def test_fail_rate_returns_500_except_for_service_routes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FAIL_RATE", "1")
    assert client.get("/books").status_code == 500
    assert client.get("/health").status_code == 200
    assert client.get("/version").status_code == 200
    assert 'status="500"' in client.get("/metrics").text
    monkeypatch.delenv("FAIL_RATE")
    assert client.get("/books").status_code == 200


def test_json_formatter_outputs_valid_json() -> None:
    record = logging.LogRecord("access", logging.INFO, __file__, 1, "request %s", ("ok",), None)
    record.status = 200
    record.route = "/books"
    data = json.loads(JsonFormatter().format(record))
    assert data["level"] == "INFO"
    assert data["message"] == "request ok"
    assert data["status"] == 200
    assert data["route"] == "/books"
    assert "ts" in data
