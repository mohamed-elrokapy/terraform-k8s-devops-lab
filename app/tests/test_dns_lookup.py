import dns.exception
import dns.resolver
import pytest

from labapi.config import Settings
from labapi.dns_lookup import (
    DnsFailure,
    DnsNxDomain,
    DnsPythonResolver,
    DnsTimeout,
    validate_domain,
)


class FakeRdata:
    def __init__(self, text):
        self._text = text

    def to_text(self):
        return self._text


def patch_resolve(monkeypatch, behaviour):
    """Replace dns.resolver.Resolver.resolve so no packet ever leaves the machine."""
    seen = {}

    def fake_resolve(self, qname, rdtype, *args, **kwargs):
        seen["timeout"] = self.timeout
        seen["lifetime"] = self.lifetime
        if isinstance(behaviour, Exception):
            raise behaviour
        return behaviour

    monkeypatch.setattr(dns.resolver.Resolver, "resolve", fake_resolve)
    return seen


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("example.com", "example.com"),
        ("  Example.COM. ", "example.com"),
        ("sub-1.example.co.uk", "sub-1.example.co.uk"),
        ("xn--bcher-kva.example", "xn--bcher-kva.example"),
    ],
)
def test_validate_domain_accepts(raw, expected):
    assert validate_domain(raw) == expected


@pytest.mark.parametrize(
    "raw",
    [
        "",
        "   ",
        "localhost",
        "a" * 64 + ".com",
        ("a." * 130) + "com",
        "-a.com",
        "a-.com",
        "a_b.com",
        "10.0.0.1",
        "a b.com",
    ],
)
def test_validate_domain_rejects(raw):
    with pytest.raises(ValueError, match=r".+"):
        validate_domain(raw)


def test_resolver_applies_short_timeout_and_returns_text(monkeypatch):
    seen = patch_resolve(monkeypatch, [FakeRdata("192.0.2.2"), FakeRdata("192.0.2.1")])
    result = DnsPythonResolver(timeout_seconds=1.5).lookup("example.com", "A")
    assert result == ["192.0.2.1", "192.0.2.2"]
    assert seen == {"timeout": 1.5, "lifetime": 1.5}


def test_resolver_sorts_mx_by_preference_not_alphabetically(monkeypatch):
    patch_resolve(monkeypatch, [FakeRdata("10 a.example.com."), FakeRdata("5 z.example.com.")])
    assert DnsPythonResolver().lookup("example.com", "MX") == ["5 z.example.com.", "10 a.example.com."]


def test_resolver_no_answer_is_empty_list(monkeypatch):
    patch_resolve(monkeypatch, dns.resolver.NoAnswer())
    assert DnsPythonResolver().lookup("example.com", "MX") == []


def test_resolver_translates_nxdomain(monkeypatch):
    patch_resolve(monkeypatch, dns.resolver.NXDOMAIN())
    with pytest.raises(DnsNxDomain):
        DnsPythonResolver().lookup("nope.example.com", "A")


def test_resolver_translates_timeout(monkeypatch):
    patch_resolve(monkeypatch, dns.resolver.LifetimeTimeout(timeout=1.0, errors=[]))
    with pytest.raises(DnsTimeout):
        DnsPythonResolver().lookup("slow.example.com", "A")


def test_resolver_translates_other_errors(monkeypatch):
    patch_resolve(monkeypatch, dns.resolver.NoNameservers())
    with pytest.raises(DnsFailure):
        DnsPythonResolver().lookup("example.com", "A")


def test_settings_from_env():
    settings = Settings.from_env(
        {"APP_VERSION": "1.2.3", "GIT_SHA": "deadbee", "DNS_STUB": "TRUE", "DNS_TIMEOUT_SECONDS": "0.5"}
    )
    assert settings == Settings(version="1.2.3", git_sha="deadbee", dns_stub=True, dns_timeout_seconds=0.5)
    assert Settings.from_env({}) == Settings()
