"""Audio account reconciliation through the HTTP interface."""

import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class AudioTest(unittest.TestCase):
    def test_navidrome_creates_restricted_account_without_overwriting_manual_user(self):
        state = {
            "users": [{"id": "manual", "userName": "manual", "isAdmin": False}],
            "writes": 0,
            "password": "public-audio-password",
        }

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(
                    b"OK" if self.path == "/ping" else json.dumps(state["users"]).encode()
                )

            def do_POST(self):
                data = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}"
                )
                if self.path == "/auth/login":
                    response = {"token": "public-audio-token"}
                else:
                    if self.headers.get("X-ND-Authorization") != "Bearer public-audio-token":
                        self.send_response(401)
                        self.end_headers()
                        return
                    if data.pop("password", None) != state["password"]:
                        self.send_response(400)
                        self.end_headers()
                        return
                    response = {**data, "id": "listener"}
                    if self.command == "PUT":
                        state["users"][1] = response
                    else:
                        state["users"].append(response)
                    state["writes"] += 1
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

            do_PUT = do_POST

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "password").write_text("public-audio-password")
            config = {
                "kind": "navidrome",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": "",
                "settings": {
                    "login": {"username": "admin", "password": {"_credential": "password"}},
                    "users": {
                        "listener": {"name": "Listener", "password": {"_credential": "password"}}
                    },
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            for attempt in range(5):
                if attempt == 4:
                    config["settings"]["users"]["LISTENER"] = config["settings"]["users"].pop(
                        "listener"
                    )
                    (path / "config.json").write_text(json.dumps(config))
                if attempt == 2:
                    state["password"] = "public-rotated-audio-password"
                    (path / "password").write_text(state["password"])
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
            self.assertEqual(state["writes"], 2)
            self.assertEqual(len(state["users"]), 2)
            self.assertFalse(state["users"][1]["isAdmin"])

            for names in (("listener", "LISTENER"), ("ADMIN",)):
                config["settings"]["users"] = {
                    name: {"password": {"_credential": "password"}} for name in names
                }
                (path / "config.json").write_text(json.dumps(config))
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
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(state["writes"], 2)
