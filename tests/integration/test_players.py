"""Player onboarding through the public reconciliation command and HTTP API."""

import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class JellyfinTest(unittest.TestCase):
    def test_api_key_rotates_admin_password_without_stale_current_password(self):
        writes = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def respond(self, value, status=200):
                self.send_response(status)
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())

            def do_GET(self):
                responses = {
                    "/System/Info/Public": {"StartupWizardCompleted": True},
                    "/Library/VirtualFolders": [],
                    "/Users": [
                        {
                            "Name": "admin",
                            "Id": "admin-id",
                            "Policy": {"IsAdministrator": True},
                        }
                    ],
                }
                if self.path == "/health":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"Healthy")
                    return
                self.respond(
                    responses.get(self.path, {}), 200 if self.path in responses else 404
                )

            def do_POST(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    or b"{}"
                )
                if self.path != "/Users/admin-id/Password" or body != {
                    "NewPw": "new-password"
                }:
                    self.respond({}, 400)
                    return
                writes.append(body)
                self.respond({})

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            config = {
                "kind": "jellyfin",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": "public-test-token",
                "settings": {
                    "login": {"username": "admin", "password": "new-password"},
                    "users": {
                        "admin": {
                            "password": "new-password",
                            "policy": {"IsAdministrator": True},
                        }
                    },
                },
            }
            path = Path(directory) / "config.json"
            path.write_text(json.dumps(config))
            result = subprocess.run(
                ["python3", str(SCRIPT), str(path)],
                check=False,
                capture_output=True,
                text=True,
                timeout=15,
                env={**os.environ, "STATE_DIRECTORY": directory},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(writes, [{"NewPw": "new-password"}])

    def test_managed_paths_replace_actual_shortcuts_and_preserve_other_libraries(self):
        library: dict[str, Any] = {
            "Name": "Movies",
            "ItemId": "movies-id",
            "Locations": ["/old movies"],
            "LibraryOptions": {
                "PathInfos": [{"Path": "/old movies"}],
                "EnableRealtimeMonitor": False,
            },
        }
        other: dict[str, Any] = {
            "Name": "Manual",
            "ItemId": "manual-id",
            "Locations": ["/manual"],
            "LibraryOptions": {},
        }
        writes = []
        fail_add_on = [0]
        add_attempts = [0]

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def respond(self, value, status=200):
                self.send_response(status)
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())

            def do_GET(self):
                if self.path == "/health":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"Healthy")
                    return
                self.respond(
                    {
                        "/System/Info/Public": {"StartupWizardCompleted": True},
                        "/Library/VirtualFolders": [library, other],
                        "/Users": [],
                    }[self.path]
                )

            def do_POST(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    or b"{}"
                )
                writes.append(("POST", self.path))
                if self.path.startswith("/Library/VirtualFolders/Paths?"):
                    add_attempts[0] += 1
                    if fail_add_on[0] == add_attempts[0]:
                        self.respond({}, 400)
                        return
                    assert body["Name"] == "Movies"
                    library["Locations"].append(body["PathInfo"]["Path"])
                elif self.path == "/Library/VirtualFolders/LibraryOptions":
                    # Match the native API: options updates do not remove shortcuts.
                    assert body["Id"] == "movies-id"
                    library["LibraryOptions"] = body["LibraryOptions"]
                else:
                    self.respond({}, 404)
                    return
                self.respond({})

            def do_DELETE(self):
                from urllib.parse import parse_qs, urlsplit

                query = parse_qs(urlsplit(self.path).query)
                assert query["name"] == ["Movies"]
                writes.append(("DELETE", self.path))
                library["Locations"].remove(query["path"][0])
                self.respond({})

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            config = {
                "kind": "jellyfin",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": "public-test-token",
                "settings": {
                    "libraries": {
                        "Movies": {"collectionType": "movies", "paths": ["/new movies"]}
                    }
                },
            }
            path = Path(directory) / "config.json"

            def run(*args):
                path.write_text(json.dumps(config))
                return subprocess.run(
                    ["python3", str(SCRIPT), str(path), *args],
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    env={**os.environ, "STATE_DIRECTORY": directory},
                )

            self.assertEqual(run("--dry-run").returncode, 0)
            self.assertEqual(writes, [])
            config["mode"] = "bootstrap"
            self.assertEqual(run().returncode, 0)
            self.assertEqual(writes, [])
            config["mode"] = "managed"
            fail_add_on[0] = 1
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(library["Locations"], ["/old movies"])
            self.assertEqual(len(writes), 1)
            fail_add_on[0] = 0
            writes.clear()
            add_attempts[0] = 0
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(library["Locations"], ["/new movies"])
            self.assertFalse(library["LibraryOptions"]["EnableRealtimeMonitor"])
            self.assertEqual(other["Locations"], ["/manual"])
            self.assertEqual(
                [method for method, _ in writes], ["POST", "DELETE", "POST"]
            )
            library["Locations"] = ["/old movies"]
            writes.clear()
            add_attempts[0] = 0
            fail_add_on[0] = 2
            config["settings"]["libraries"]["Movies"]["paths"] = [
                "/new movies",
                "/newer movies",
            ]
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(library["Locations"], ["/old movies"])
            self.assertEqual(
                [method for method, _ in writes], ["POST", "POST", "DELETE"]
            )
            config["settings"]["libraries"]["Movies"]["paths"] = ["/new movies"]
            fail_add_on[0] = 0
            writes.clear()
            self.assertEqual(run().returncode, 0)
            self.assertEqual(library["Locations"], ["/new movies"])
            writes.clear()
            self.assertEqual(run().returncode, 0)
            self.assertEqual(writes, [])

    def test_bootstrap_libraries_and_restricted_user_survive_repeated_apply(self):
        state: dict[str, Any] = {
            "initialized": False,
            "encoding": {"EncodingThreadCount": -1, "EnableHardwareEncoding": False},
            "libraries": [],
            "users": [],
            "writes": [],
        }

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def do_GET(self):
                if self.path == "/health":
                    state["healthProbes"] = state.get("healthProbes", 0) + 1
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(
                        b"Degraded" if state["healthProbes"] == 1 else b"Healthy"
                    )
                    return
                if self.path in {
                    "/Library/VirtualFolders",
                    "/Users",
                } and 'Token="public-test-token"' not in self.headers.get(
                    "Authorization", ""
                ):
                    self.send_response(401)
                    self.end_headers()
                    return
                responses = {
                    "/health": "Healthy",
                    "/System/Configuration/encoding": state["encoding"],
                    "/System/Info/Public": {
                        "StartupWizardCompleted": state["initialized"]
                    },
                    "/Startup/User": {},
                    "/Library/VirtualFolders": state["libraries"],
                    "/Users": state["users"],
                }
                self.send_response(200 if self.path in responses else 404)
                self.end_headers()
                self.wfile.write(json.dumps(responses.get(self.path)).encode())

            def do_POST(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    or b"{}"
                )
                state["writes"].append(self.path)
                response = {}
                if self.path == "/System/Configuration/encoding":
                    state["encoding"] = body
                elif self.path == "/Startup/Complete":
                    state["initialized"] = True
                elif self.path == "/Users/AuthenticateByName":
                    response = {"AccessToken": "public-test-token"}
                elif self.path.startswith("/Library/VirtualFolders?"):
                    state["libraries"].append({
                        "Name": "Movies",
                        "ItemId": "library-id",
                        "LibraryOptions": body["LibraryOptions"],
                        "Locations": [
                            item["Path"] for item in body["LibraryOptions"]["PathInfos"]
                        ],
                    })
                elif self.path == "/Users/New":
                    response = {"Name": body["Name"], "Id": "viewer-id", "Policy": {}}
                    state["users"].append(response)
                elif self.path == "/Users/viewer-id/Policy":
                    state["users"][0]["Policy"] = body
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "password").write_text("public-test-password")
            config = {
                "kind": "jellyfin",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": "",
                "settings": {
                    "encoding": {"EncodingThreadCount": 2},
                    "login": {
                        "username": "admin",
                        "password": {"_credential": "password"},
                    },
                    "libraries": {
                        "Movies": {
                            "collectionType": "movies",
                            "paths": ["/srv/media/library/movies"],
                        }
                    },
                    "users": {
                        "viewer": {
                            "password": {"_credential": "password"},
                            "policy": {"IsAdministrator": False},
                        }
                    },
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            command = ["python3", str(SCRIPT), str(path / "config.json")]
            for _ in range(2):
                result = subprocess.run(
                    command,
                    env={
                        **os.environ,
                        "CREDENTIALS_DIRECTORY": directory,
                        "STATE_DIRECTORY": directory,
                    },
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("password", result.stdout + result.stderr)
            self.assertTrue(state["initialized"])
            self.assertEqual(state["encoding"]["EncodingThreadCount"], 2)
            self.assertFalse(state["encoding"]["EnableHardwareEncoding"])
            self.assertEqual(len(state["libraries"]), 1)
            self.assertEqual(len(state["users"]), 1)
            self.assertFalse(state["users"][0]["Policy"]["IsAdministrator"])
            self.assertEqual(state["writes"].count("/Startup/Complete"), 1)
