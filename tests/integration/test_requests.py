"""Request portal integration uses named profiles and preserves unmanaged servers."""

import json
import os
import subprocess
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class RequestPortalTest(unittest.TestCase):
    def test_resolves_named_profile_and_preserves_unmanaged_server(self):
        state = {
            "servers": [{"name": "manual", "id": 8}],
            "writes": [],
            "libraries": [
                {"id": "1", "name": "Manual", "enabled": True},
                {"id": "2", "name": "Movies", "enabled": False},
            ],
            "libraryWrites": 0,
        }

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                if self.path.startswith("/api/v1/settings/jellyfin/library"):
                    raw_query = urllib.parse.urlsplit(self.path).query
                    if "enable=" in raw_query and not urllib.parse.parse_qs(raw_query).get(
                        "enable"
                    ):
                        self.send_response(400)
                        self.end_headers()
                        return
                    query = urllib.parse.parse_qs(raw_query)
                    if query.get("sync") and not state["libraries"]:
                        state["libraries"].append({"id": "2", "name": "Movies", "enabled": False})
                    enabled = query.get("enable", [""])[0].split(",")
                    for library in state["libraries"]:
                        library["enabled"] = library["id"] in enabled
                    state["libraryWrites"] += 1
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps(state["libraries"]).encode())
                    return
                values = {
                    "/api/v1/status": {},
                    "/api/v1/settings/public": {"initialized": True},
                    "/api/v1/settings/radarr": state["servers"],
                    "/api/v1/settings/jellyfin": {"libraries": state["libraries"]},
                }
                self.send_response(200 if self.path in values else 404)
                self.end_headers()
                self.wfile.write(json.dumps(values.get(self.path)).encode())

            def do_POST(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}"
                )
                if self.path.endswith("/test"):
                    response = {
                        "profiles": [{"id": 4, "name": "HD-1080p"}],
                        "rootFolders": [{"path": "/media/movies"}],
                    }
                else:
                    state["writes"].append(self.path)
                    body["id"] = 9
                    state["servers"].append(body)
                    response = body
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "key").write_text("public-fixture-key")
            config = {
                "kind": "seerr",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": {"_credential": "key"},
                "settings": {
                    "libraries": ["Movies"],
                    "radarr": {
                        "movies": {
                            "hostname": "127.0.0.1",
                            "port": 7878,
                            "apiKey": {"_credential": "key"},
                            "useSsl": False,
                            "activeProfileName": "HD-1080p",
                            "activeDirectory": "/media/movies",
                        }
                    },
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            for args in (["--dry-run"], [], []):
                result = subprocess.run(
                    ["python3", str(SCRIPT), str(path / "config.json"), *args],
                    env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                if args:
                    self.assertEqual(state["libraryWrites"], 0)
                    self.assertTrue(state["libraries"][0]["enabled"])
            self.assertEqual(state["libraryWrites"], 1)
            self.assertTrue(all(item["enabled"] for item in state["libraries"]))
            self.assertEqual(len(state["servers"]), 2)
            self.assertEqual(state["servers"][0]["name"], "manual")
            self.assertEqual(state["servers"][1]["activeProfileId"], 4)
            self.assertEqual(len(state["writes"]), 1)

            # A fresh portal has no enabled IDs. The pinned API rejects enable=.
            state["libraries"] = []
            state["libraryWrites"] = 0
            for args in (["--dry-run"], [], []):
                result = subprocess.run(
                    ["python3", str(SCRIPT), str(path / "config.json"), *args],
                    env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                if args:
                    self.assertEqual(state["libraryWrites"], 0)
            self.assertEqual(state["libraryWrites"], 2)
            self.assertTrue(state["libraries"][0]["enabled"])
