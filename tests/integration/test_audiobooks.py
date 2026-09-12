"""Audiobook library setup uses supported initialization and authenticated APIs."""

import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class AudiobookTest(unittest.TestCase):
    def test_initialization_and_libraries_are_idempotent(self):
        state = {"ready": False, "libraries": [], "users": [], "writes": []}

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                response = {
                    "/status": {"isInit": state["ready"]},
                    "/api/libraries": {"libraries": state["libraries"]},
                    "/api/users": {"users": state["users"]},
                }[self.path]
                self.wfile.write(json.dumps(response).encode())

            def do_POST(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}"
                )
                if self.path == "/init":
                    state["ready"] = True
                    response = b"OK"
                elif self.path == "/login":
                    response = json.dumps({"user": {"accessToken": "public-abs-token"}}).encode()
                else:
                    if self.headers.get("Authorization") != "Bearer public-abs-token":
                        self.send_response(401)
                        self.end_headers()
                        return
                    state["writes"].append(self.path)
                    value = {**body, "id": "fixture-id"}
                    if self.path == "/api/libraries":
                        state["libraries"].append(value)
                        response = json.dumps(value).encode()
                    else:
                        value.pop("password", None)
                        state["users"].append(value)
                        response = json.dumps({"user": value}).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(response)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "password").write_text("public-audio-password")
            config = {
                "kind": "audiobookshelf",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": "",
                "settings": {
                    "login": {"username": "admin", "password": {"_credential": "password"}},
                    "libraries": {
                        "Books": {
                            "folders": [{"fullPath": "/media/audiobooks"}],
                            "mediaType": "book",
                        }
                    },
                    "users": {
                        "listener": {
                            "password": {"_credential": "password"},
                            "permissions": {"delete": False, "upload": False},
                        }
                    },
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            for _ in range(2):
                result = subprocess.run(
                    ["python3", str(SCRIPT), str(path / "config.json")],
                    env={
                        **os.environ,
                        "CREDENTIALS_DIRECTORY": directory,
                        "STATE_DIRECTORY": directory,
                    },
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(state["ready"])
            self.assertEqual(len(state["libraries"]), 1)
            self.assertEqual(len(state["users"]), 1)
            self.assertEqual(state["users"][0]["type"], "user")
            self.assertTrue(state["users"][0]["isActive"])
            self.assertEqual(len(state["writes"]), 2)
