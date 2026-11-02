from labapi.config import Settings
from labapi.dns_lookup import DnsFailure, DnsNxDomain, DnsTimeout


def test_healthz(make_client):
    client, _ = make_client()
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readyz_ready_after_startup(make_client):
    client, _ = make_client()
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_readyz_503_when_not_ready(make_client):
    client, _ = make_client()
    client.app.state.ready = False
    response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json() == {"status": "not_ready"}


def test_version(make_client):
    client, _ = make_client()
    assert client.get("/version").json() == {"version": "9.9.9", "git_sha": "abc123", "dns_stub": False}


def test_dns_ok_returns_a_mx_txt(make_client):
    table = {
        ("example.com", "A"): ["192.0.2.1"],
        ("example.com", "MX"): ["10 mail.example.com."],
        ("example.com", "TXT"): ['"v=spf1 -all"'],
    }
    client, resolver = make_client(table)
    response = client.get("/api/dns", params={"domain": "Example.COM."})
    assert response.status_code == 200
    assert response.json() == {
        "domain": "example.com",
        "status": "ok",
        "records": {
            "A": ["192.0.2.1"],
            "MX": ["10 mail.example.com."],
            "TXT": ['"v=spf1 -all"'],
        },
    }
    assert [rtype for _, rtype in resolver.calls] == ["A", "MX", "TXT"]


def test_dns_name_without_records(make_client):
    client, _ = make_client()
    body = client.get("/api/dns", params={"domain": "empty.example.org"}).json()
    assert body["status"] == "no_records"
    assert body["records"] == {"A": [], "MX": [], "TXT": []}


def test_dns_nxdomain_is_a_normal_result(make_client):
    client, _ = make_client({("nope.example.org", "A"): DnsNxDomain("nope.example.org")})
    response = client.get("/api/dns", params={"domain": "nope.example.org"})
    assert response.status_code == 200
    assert response.json() == {
        "domain": "nope.example.org",
        "status": "nxdomain",
        "records": {"A": [], "MX": [], "TXT": []},
    }


def test_dns_timeout_maps_to_504(make_client):
    client, _ = make_client({("slow.example.org", "A"): DnsTimeout("slow.example.org")})
    response = client.get("/api/dns", params={"domain": "slow.example.org"})
    assert response.status_code == 504


def test_dns_resolver_failure_maps_to_502(make_client):
    client, _ = make_client({("broken.example.org", "A"): DnsFailure("SERVFAIL")})
    response = client.get("/api/dns", params={"domain": "broken.example.org"})
    assert response.status_code == 502
    assert "SERVFAIL" not in response.text  # internal detail is not leaked


def test_dns_missing_parameter_is_422(make_client):
    client, _ = make_client()
    assert client.get("/api/dns").status_code == 422


def test_dns_invalid_input_is_rejected_before_any_lookup(make_client):
    client, resolver = make_client()
    for bad in ["localhost", "-bad.example.com", "a..b.com", "exa mple.com", "1.2.3.4", "x" * 64 + ".com"]:
        response = client.get("/api/dns", params={"domain": bad})
        assert response.status_code == 422, bad
    assert resolver.calls == []


def test_stub_mode_needs_no_network():
    from fastapi.testclient import TestClient

    from labapi.main import create_app

    with TestClient(create_app(Settings(dns_stub=True))) as client:
        assert client.get("/version").json()["dns_stub"] is True
        ok = client.get("/api/dns", params={"domain": "example.com"}).json()
        assert ok["status"] == "ok"
        assert ok["records"]["A"] == ["192.0.2.10"]
        assert client.get("/api/dns", params={"domain": "a-only.example.com"}).json()["records"]["MX"] == []
        assert client.get("/api/dns", params={"domain": "missing.invalid"}).json()["status"] == "nxdomain"
        assert client.get("/api/dns", params={"domain": "slow.example.com"}).status_code == 504


def test_metrics_exposes_request_counters_with_route_templates(make_client):
    client, _ = make_client({("example.com", "A"): ["192.0.2.1"]})
    client.get("/healthz")
    client.get("/api/dns", params={"domain": "example.com"})
    client.get("/does-not-exist")
    text = client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/healthz",status="200"} 1.0' in text
    assert 'http_requests_total{method="GET",route="/api/dns",status="200"} 1.0' in text
    assert 'route="unmatched",status="404"' in text
    assert 'dns_lookups_total{result="ok"} 1.0' in text
    assert 'app_build_info{git_sha="abc123",version="9.9.9"} 1.0' in text
