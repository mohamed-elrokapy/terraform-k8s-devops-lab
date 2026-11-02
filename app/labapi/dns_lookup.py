"""DNS lookups: input validation, a dnspython-backed resolver and a stub resolver for tests."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Protocol

import dns.exception
import dns.resolver

RECORD_TYPES: tuple[str, ...] = ("A", "MX", "TXT")

_LABEL = re.compile(r"^(?!-)[a-z0-9-]{1,63}(?<!-)$")


class DnsError(Exception):
    """Base class for lookup failures."""


class DnsNxDomain(DnsError):
    """The name does not exist."""


class DnsTimeout(DnsError):
    """The lookup did not finish within the time budget."""


class DnsFailure(DnsError):
    """Any other resolver failure (SERVFAIL, no usable nameserver, ...)."""


class Resolver(Protocol):
    def lookup(self, domain: str, rtype: str) -> list[str]:
        """Return record values as text. An empty list means the name exists but has no such record."""
        ...


def validate_domain(raw: str) -> str:
    """Normalise and validate a hostname. Raises ValueError with a short reason."""
    name = raw.strip().lower().rstrip(".")
    if not name:
        raise ValueError("domain is empty")
    if len(name) > 253:
        raise ValueError("domain is longer than 253 characters")
    labels = name.split(".")
    if len(labels) < 2:
        raise ValueError("domain needs at least two labels, for example example.com")
    for label in labels:
        if not _LABEL.match(label):
            raise ValueError(f"invalid label {label!r}: use a-z, 0-9 and hyphens, 1-63 characters")
    if labels[-1].isdigit():
        raise ValueError("IP addresses are not accepted, pass a hostname")
    return name


class DnsPythonResolver:
    """Resolver backed by dnspython, using the system resolver configuration."""

    def __init__(self, timeout_seconds: float = 2.0) -> None:
        self._timeout = timeout_seconds

    def lookup(self, domain: str, rtype: str) -> list[str]:
        try:
            resolver = dns.resolver.Resolver()
            resolver.timeout = self._timeout
            resolver.lifetime = self._timeout
            answer = resolver.resolve(domain, rtype)
        except dns.resolver.NXDOMAIN as exc:
            raise DnsNxDomain(domain) from exc
        except dns.resolver.NoAnswer:
            return []
        except dns.exception.Timeout as exc:
            raise DnsTimeout(domain) from exc
        except dns.exception.DNSException as exc:
            raise DnsFailure(f"{type(exc).__name__}: {exc}") from exc
        return _sorted([rdata.to_text() for rdata in answer], rtype)


# Documentation-range address (RFC 5737) and reserved example names only.
_STUB_TABLE: dict[str, dict[str, list[str]]] = {
    "example.com": {
        "A": ["192.0.2.10"],
        "MX": ["10 mail.example.com."],
        "TXT": ['"v=spf1 -all"'],
    },
    # Exists, but has only an A record: exercises the "empty list" path.
    "a-only.example.com": {"A": ["192.0.2.20"]},
}
_STUB_TIMEOUT_NAME = "slow.example.com"


class StubResolver:
    """Deterministic resolver for tests and the CI end-to-end run (DNS_STUB=true)."""

    def lookup(self, domain: str, rtype: str) -> list[str]:
        if domain == _STUB_TIMEOUT_NAME:
            raise DnsTimeout(domain)
        if domain not in _STUB_TABLE:
            raise DnsNxDomain(domain)
        return list(_STUB_TABLE[domain].get(rtype, []))


@dataclass(frozen=True)
class DnsResult:
    domain: str
    status: str  # "ok", "no_records" or "nxdomain"
    records: dict[str, list[str]]


def resolve_domain(resolver: Resolver, domain: str) -> DnsResult:
    """Look up A, MX and TXT. NXDOMAIN is a normal result; timeouts and failures propagate."""
    records: dict[str, list[str]] = {}
    for rtype in RECORD_TYPES:
        try:
            records[rtype] = resolver.lookup(domain, rtype)
        except DnsNxDomain:
            return DnsResult(domain, "nxdomain", {t: [] for t in RECORD_TYPES})
    status = "ok" if any(records.values()) else "no_records"
    return DnsResult(domain, status, records)


def _sorted(values: list[str], rtype: str) -> list[str]:
    if rtype == "MX":
        return sorted(values, key=lambda v: (int(v.split()[0]), v))
    return sorted(values)
