"""Runtime configuration, read from environment variables (set by the ConfigMap in Kubernetes)."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    version: str = "dev"
    git_sha: str = "unknown"
    # When true, DNS answers come from a small built-in table instead of a real resolver.
    # Used by the CI end-to-end test so it needs no outbound DNS. Never enable it for real use.
    dns_stub: bool = False
    # Per-lookup budget in seconds (both the per-server timeout and the total lifetime).
    dns_timeout_seconds: float = 2.0

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> Settings:
        env = dict(os.environ) if env is None else env
        return cls(
            version=env.get("APP_VERSION", cls.version),
            git_sha=env.get("GIT_SHA", cls.git_sha),
            dns_stub=_as_bool(env.get("DNS_STUB")),
            dns_timeout_seconds=float(env.get("DNS_TIMEOUT_SECONDS", cls.dns_timeout_seconds)),
        )
