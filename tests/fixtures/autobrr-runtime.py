"""Exercise the pinned native API using disposable, VM-local credentials."""

import http.cookiejar
import importlib.util
import json
import os
import sys
import urllib.request
from pathlib import Path

spec = importlib.util.spec_from_file_location("autobrr", "/etc/autobrr-adapter.py")
if spec is None or spec.loader is None:
    raise ImportError("Could not load /etc/autobrr-adapter.py")
autobrr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(autobrr)


class Client:
    def __init__(self):
        self.headers = {}
        self.writes = []
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
        )

    def request(self, method, path, body=None):
        if method != "GET":
            self.writes.append((method, path))
        req = urllib.request.Request(
            "http://127.0.0.1:7474" + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Content-Type": "application/json", **self.headers},
            method=method,
        )
        with self.opener.open(req, timeout=10) as response:
            data = response.read()
            return json.loads(data) if data else None


client = Client()
if len(sys.argv) > 1 and sys.argv[1] == "verify-persistence":
    client.headers = {
        "X-API-Token": Path("/var/lib/autobrr-test/api-key").read_text(encoding="utf-8")
    }
    assert len(client.request("GET", "/api/download_clients")) == 1
    assert len(client.request("GET", "/api/filters")) == 1
    assert len(client.request("GET", "/api/actions")) == 2
    print("Native autobrr resources and API credential survived restart")
    raise SystemExit(0)
os.environ["STATE_DIRECTORY"] = "/var/lib/autobrr-test"
Path(os.environ["STATE_DIRECTORY"]).mkdir(exist_ok=True, mode=0o700)
user = {"username": "fixture", "password": "Disposable-VM-password-only-123"}
client.request("POST", "/api/auth/onboard", user)
client.request("POST", "/api/auth/login", user)
key = client.request("POST", "/api/keys", {"name": "VM fixture", "scopes": []})["key"]
Path("/var/lib/autobrr-test/api-key").write_text(key, encoding="utf-8")
Path("/var/lib/autobrr-test/api-key").chmod(0o600)
# Drop the admin session; every adapter request must authenticate using its API key.
client = Client()
config = {
    "apiKey": key,
    "mode": "managed",
    "settings": {
        "downloadClients": {
            "Fixture client": {
                "type": "QBITTORRENT",
                "host": "http://127.0.0.1:8081",
                "enabled": False,
                "username": "fixture",
                "password": "Disposable-downloader-password",
            }
        },
        "filters": {
            "Fixture filter": {
                "values": {
                    "enabled": False,
                    "match_releases": "Fixture.*",
                    "max_size": "5GB",
                },
                "indexers": [],
                "actions": {
                    "No download": {"type": "TEST", "enabled": False},
                    "Named client": {
                        "type": "QBITTORRENT",
                        "client": "Fixture client",
                        "enabled": False,
                        "paused": True,
                    },
                },
            }
        },
    },
}
client.writes.clear()
autobrr.reconcile(client, config, True)
assert not client.writes
autobrr.reconcile(client, config, False)
clients = client.request("GET", "/api/download_clients")
filters = client.request("GET", "/api/filters")
actions = client.request("GET", "/api/actions")
assert len(clients) == len(filters) == 1
assert len(actions) == 2
scoped = client.request("GET", f"/api/filters/{filters[0]['id']}")["actions"]
assert {item["id"] for item in scoped} == {item["id"] for item in actions}
assert not filters[0]["enabled"]
linked = next(action for action in actions if action["name"] == "Named client")
assert linked["client_id"] == clients[0]["id"]
assert not linked["enabled"]
client.writes.clear()
autobrr.reconcile(client, config, False)
assert not client.writes, client.writes
config["settings"]["downloadClients"]["Fixture client"]["password"] = (
    "Rotated-disposable-password"
)
autobrr.reconcile(client, config, False)
assert client.writes == [("PUT", "/api/download_clients")], client.writes
client.writes.clear()
autobrr.reconcile(client, config, False)
assert not client.writes, client.writes
print("Native autobrr authenticated creation, preview, repeat and rotation passed")
