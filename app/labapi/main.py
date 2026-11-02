"""FastAPI application: health endpoints, a DNS lookup API and Prometheus metrics."""

from __future__ import annotations

import logging
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    ProcessCollector,
    generate_latest,
)
from pydantic import BaseModel

from labapi.config import Settings
from labapi.dns_lookup import (
    DnsFailure,
    DnsPythonResolver,
    DnsTimeout,
    Resolver,
    StubResolver,
    resolve_domain,
    validate_domain,
)

logger = logging.getLogger("labapi")


class DnsResponse(BaseModel):
    domain: str
    status: str
    records: dict[str, list[str]]


def create_app(settings: Settings | None = None, resolver: Resolver | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    if resolver is None:
        resolver = StubResolver() if settings.dns_stub else DnsPythonResolver(settings.dns_timeout_seconds)

    # One registry per app instance keeps tests independent (no duplicate metric names).
    registry = CollectorRegistry()
    ProcessCollector(registry=registry)
    requests_total = Counter(
        "http_requests_total", "HTTP requests", ["method", "route", "status"], registry=registry
    )
    request_seconds = Histogram(
        "http_request_duration_seconds", "HTTP request latency", ["method", "route"], registry=registry
    )
    dns_lookups_total = Counter("dns_lookups_total", "DNS lookups by outcome", ["result"], registry=registry)
    build_info = Gauge("app_build_info", "Build information", ["version", "git_sha"], registry=registry)
    build_info.labels(settings.version, settings.git_sha).set(1)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.ready = True
        yield
        app.state.ready = False

    app = FastAPI(title="terraform-k8s-devops-lab", version=settings.version, lifespan=lifespan)
    app.state.ready = False

    @app.middleware("http")
    async def metrics_middleware(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            # The route template (not the raw path) keeps label cardinality bounded.
            route = getattr(request.scope.get("route"), "path", "unmatched")
            requests_total.labels(request.method, route, str(status)).inc()
            request_seconds.labels(request.method, route).observe(time.perf_counter() - start)

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        """Liveness: the process is up and serving."""
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz(response: Response) -> dict[str, str]:
        """Readiness: safe to receive traffic."""
        if not app.state.ready:
            response.status_code = 503
            return {"status": "not_ready"}
        return {"status": "ready"}

    @app.get("/version")
    def version() -> dict[str, str | bool]:
        return {"version": settings.version, "git_sha": settings.git_sha, "dns_stub": settings.dns_stub}

    @app.get("/api/dns", response_model=DnsResponse)
    def dns_lookup(domain: str = Query(..., description="Hostname, for example example.com")) -> DnsResponse:
        try:
            name = validate_domain(domain)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        try:
            result = resolve_domain(resolver, name)
        except DnsTimeout as exc:
            logger.warning("dns timeout for %s", name)
            dns_lookups_total.labels("timeout").inc()
            raise HTTPException(status_code=504, detail="DNS lookup timed out") from exc
        except DnsFailure as exc:
            logger.warning("dns failure for %s: %s", name, exc)
            dns_lookups_total.labels("error").inc()
            raise HTTPException(status_code=502, detail="DNS resolver failure") from exc
        dns_lookups_total.labels(result.status).inc()
        return DnsResponse(domain=result.domain, status=result.status, records=result.records)

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)

    return app


app = create_app()
