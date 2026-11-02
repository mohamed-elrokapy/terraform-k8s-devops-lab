import pytest
from fastapi.testclient import TestClient

from labapi.config import Settings
from labapi.main import create_app


class FakeResolver:
    """Resolver double: maps (domain, rtype) to a list, or to an exception instance to raise."""

    def __init__(self, table):
        self.table = table
        self.calls = []

    def lookup(self, domain, rtype):
        self.calls.append((domain, rtype))
        result = self.table.get((domain, rtype), [])
        if isinstance(result, Exception):
            raise result
        return result


@pytest.fixture
def make_client():
    """Factory returning (client, resolver). Clients run the app lifespan and are closed afterwards."""
    clients = []

    def _make(table=None, settings=None):
        resolver = FakeResolver(table or {})
        app = create_app(settings or Settings(version="9.9.9", git_sha="abc123"), resolver)
        client = TestClient(app)
        client.__enter__()
        clients.append(client)
        return client, resolver

    yield _make
    for client in clients:
        client.__exit__(None, None, None)
