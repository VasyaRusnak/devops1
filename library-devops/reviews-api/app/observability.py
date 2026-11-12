"""Метрики Prometheus, JSON-логи та імітація збоїв (FAIL_RATE) для сервісу."""

import json
import logging
import os
import random
import sys
import time
from datetime import UTC, datetime

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

# Службові маршрути не рахуються в метриках і не потрапляють у логи запитів
SKIP_PATHS = {"/health", "/metrics"}
# Імітація збоїв не зачіпає службові маршрути (інакше впадуть проби Kubernetes)
NO_FAIL_PATHS = {"/health", "/metrics", "/version"}

# Мітки лише з малою кардинальністю: метод, шаблон маршруту (не сирий URL), код статусу
HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Кількість HTTP-запитів",
    ["method", "route", "status"],
)
HTTP_DURATION = Histogram(
    "http_request_duration_seconds",
    "Тривалість обробки HTTP-запитів у секундах",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)

LOG_FIELDS = ("method", "route", "path", "status", "duration_ms", "version", "injected")


class JsonFormatter(logging.Formatter):
    """Один рядок JSON на запис: час, рівень, повідомлення та поля запиту."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
        }
        for field in LOG_FIELDS:
            if hasattr(record, field):
                payload[field] = getattr(record, field)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    # Логи uvicorn теж виводяться в JSON (access-лог вимкнено прапорцем --no-access-log)
    for name in ("uvicorn", "uvicorn.error"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers = [handler]
        uv_logger.propagate = False


def fail_rate() -> float:
    try:
        return min(max(float(os.getenv("FAIL_RATE", "0")), 0.0), 1.0)
    except ValueError:
        return 0.0


async def inject_failure(request: Request) -> None:
    """Глобальна залежність: частка запитів FAIL_RATE отримує 500 (для демонстрації відкату)."""
    if request.url.path in NO_FAIL_PATHS:
        return
    if random.random() < fail_rate():
        request.state.injected = True
        raise HTTPException(status_code=500, detail="injected failure (FAIL_RATE)")


def setup_observability(app: FastAPI, service: str, version: str) -> None:
    configure_logging()
    logger = logging.getLogger("access")

    @app.middleware("http")
    async def observe(request: Request, call_next):
        if request.url.path in SKIP_PATHS:
            return await call_next(request)
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            duration = time.perf_counter() - start
            route = getattr(request.scope.get("route"), "path", "unmatched")
            HTTP_REQUESTS.labels(request.method, route, str(status)).inc()
            HTTP_DURATION.labels(request.method, route).observe(duration)
            logger.info(
                "request",
                extra={
                    "method": request.method,
                    "route": route,
                    "path": request.url.path,
                    "status": status,
                    "duration_ms": round(duration * 1000, 2),
                    "version": version,
                    "injected": bool(getattr(request.state, "injected", False)),
                },
            )

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
