"""Request portal integration uses named profiles and preserves unmanaged servers."""

import importlib
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from unittest.mock import patch

from notification_process import run as run_command

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class RequestPortalTest(unittest.TestCase):
    def test_anime_profile_resolves_by_name_and_rejects_missing_or_ambiguous(self):
        sys.path.insert(0, str(SCRIPT.parent))
        reconcile_seerr = importlib.import_module("adapters.seerr").reconcile_seerr
        configuration_error = importlib.import_module("common").ConfigurationError

        class Client:
            def __init__(self, anime):
                self.anime = anime
                self.servers = []
                self.writes = []

            def request(self, method, path, body=None):
                if path.endswith("/public"):
                    return {"initialized": True}
                if path.endswith("/test"):
                    return {
                        "profiles": [{"id": 8, "name": "Combined"}, *self.anime],
                        "rootFolders": [{"path": "/media/tv"}],
                    }
                if method == "GET":
                    return self.servers
                assert body is not None
                self.writes.append(body)
                self.servers = [{**body, "id": 1}]
                return self.servers[0]

        config = {
            "mode": "managed",
            "apiKey": "public-test-key",
            "settings": {
                "sonarr": {
                    "tv": {
                        "activeProfileName": "Combined",
                        "activeAnimeProfileName": "Anime",
                        "activeDirectory": "/media/tv",
                    }
                }
            },
        }
        client = Client([{"id": 19, "name": "Anime"}])
        reconcile_seerr(client, config, True)
        self.assertEqual(client.writes, [])
        reconcile_seerr(client, config, False)
        self.assertEqual(client.writes[0]["activeProfileId"], 8)
        self.assertEqual(client.writes[0]["activeAnimeProfileId"], 19)
        reconcile_seerr(client, config, False)
        self.assertEqual(len(client.writes), 1)
        config["settings"]["sonarr"]["tv"]["activeAnimeDirectory"] = "/missing"
        with self.assertRaises(configuration_error):
            reconcile_seerr(client, config, False)
        self.assertEqual(len(client.writes), 1)
        del config["settings"]["sonarr"]["tv"]["activeAnimeDirectory"]
        for profiles in (
            [],
            [{"id": 19, "name": "Anime"}, {"id": 20, "name": "Anime"}],
        ):
            with self.subTest(profiles=profiles), patch("adapters.seerr.time.sleep"):
                client = Client(profiles)
                with self.assertRaises(configuration_error):
                    reconcile_seerr(client, config, False)
                self.assertEqual(client.writes, [])

    def test_resolves_named_profile_and_preserves_unmanaged_server(self):  # ruff: ignore[too-many-statements] - One fixture verifies the full preservation lifecycle.
        state: dict[str, Any] = {
            "servers": [{"name": "manual", "id": 8}],
            "writes": [],
            "libraries": [
                {"id": "1", "name": "Manual", "enabled": True},
                {"id": "2", "name": "Movies", "enabled": False},
                {"id": "3", "name": "Unselected", "enabled": False},
            ],
            "libraryWrites": 0,
            "profile": {"id": 4, "name": "HD-1080p"},
            "profileMisses": 0,
            "network": {"proxy": {"enabled": False, "hostname": ""}},
            "jellyfin": {
                "hostname": "http://127.0.0.1:8096",
                "externalHostname": "http://127.0.0.1:8096",
                "libraries": [],
            },
            "main": {"apiKey": "read-only-fixture-key", "defaultPermissions": 0},
            "users": [
                {"id": 1, "jellyfinUsername": "admin", "permissions": 2},
                {"id": 2, "jellyfinUsername": "viewer", "permissions": 32},
                {"id": 3, "username": "guest", "permissions": 160},
            ],
        }

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def do_GET(self):
                if self.path == "/api/v1/user?take=100&skip=0":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(
                        json.dumps({
                            "pageInfo": {"page": 1, "pages": 1},
                            "results": state["users"],
                        }).encode()
                    )
                    return
                if self.path.startswith("/api/v1/settings/jellyfin/library"):
                    valid = self.path == "/api/v1/settings/jellyfin/library"
                    self.send_response(200 if valid else 400)
                    self.end_headers()
                    if valid:
                        self.wfile.write(json.dumps(state["libraries"]).encode())
                    return
                values = {
                    "/api/v1/status": {},
                    "/api/v1/settings/public": {"initialized": True},
                    "/api/v1/settings/radarr": state["servers"],
                    "/api/v1/settings/jellyfin": {
                        **state["jellyfin"],
                        "libraries": state["libraries"],
                    },
                    "/api/v1/settings/network": state["network"],
                    "/api/v1/settings/main": state["main"],
                }
                self.send_response(200 if self.path in values else 404)
                self.end_headers()
                self.wfile.write(json.dumps(values.get(self.path)).encode())

            def do_POST(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    or b"{}"
                )
                if self.path.startswith("/api/v1/user/") and self.path.endswith(
                    "/settings/permissions"
                ):
                    user_id = int(self.path.split("/")[4])
                    user = next(
                        item for item in state["users"] if item["id"] == user_id
                    )
                    user["permissions"] = body["permissions"]
                    state["writes"].append(self.path)
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps(body).encode())
                    return
                if self.path == "/api/v1/settings/jellyfin/library/sync":
                    if not any(item["name"] == "Movies" for item in state["libraries"]):
                        state["libraries"].append({
                            "id": "2",
                            "name": "Movies",
                            "enabled": False,
                        })
                    state["libraryWrites"] += 1
                    response = state["libraries"]
                elif self.path.endswith("/test"):
                    profiles = [state["profile"]]
                    if state["profileMisses"]:
                        state["profileMisses"] -= 1
                        profiles = []
                    response = {
                        "profiles": profiles,
                        "rootFolders": [{"path": "/media/movies"}],
                    }
                else:
                    state["writes"].append(self.path)
                    if self.path == "/api/v1/settings/network":
                        state["network"] = body
                        response = body
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(json.dumps(response).encode())
                        return
                    if self.path == "/api/v1/settings/jellyfin":
                        if set(body) != {"externalHostname"}:
                            self.send_response(400)
                            self.end_headers()
                            return
                        state["jellyfin"].update(body)
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(json.dumps(state["jellyfin"]).encode())
                        return
                    if self.path == "/api/v1/settings/main":
                        if "apiKey" in body:
                            self.send_response(400)
                            self.end_headers()
                            return
                        state["main"].update(body)
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(json.dumps(state["main"]).encode())
                        return
                    body["id"] = 9
                    state["servers"].append(body)
                    response = body
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

            def do_PUT(self):
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    or b"{}"
                )
                if self.path == "/api/v1/settings/radarr/9":
                    if "id" in body:
                        self.send_response(400)
                        self.end_headers()
                        return
                    state["servers"][1] = {**body, "id": 9}
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps(state["servers"][1]).encode())
                    return
                prefix = "/api/v1/settings/jellyfin/library/"
                library_id = urllib.parse.unquote(self.path.removeprefix(prefix))
                library = next(
                    (
                        item
                        for item in state["libraries"]
                        if str(item["id"]) == library_id
                    ),
                    None,
                )
                if (
                    not self.path.startswith(prefix)
                    or set(body) != {"enabled"}
                    or type(body["enabled"]) is not bool
                    or library is None
                ):
                    self.send_response(400)
                    self.end_headers()
                    return
                library["enabled"] = body["enabled"]
                state["libraryWrites"] += 1
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(library).encode())

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
                    "jellyfin": {
                        "externalHostname": "https://jellyfin.example.invalid"
                    },
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
                    "network": {
                        "proxy": {
                            "enabled": True,
                            "hostname": "169.254.202.94",
                            "port": 8888,
                            "bypassLocalAddresses": True,
                        }
                    },
                    "main": {"defaultPermissions": 32},
                    "autoApproveUsers": ["admin", "viewer"],
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            for args in (["--dry-run"], [], []):
                result = run_command(
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
                    self.assertEqual(
                        state["jellyfin"]["externalHostname"], "http://127.0.0.1:8096"
                    )
            self.assertEqual(state["libraryWrites"], 1)
            self.assertTrue(state["libraries"][0]["enabled"])
            self.assertTrue(state["libraries"][1]["enabled"])
            self.assertFalse(state["libraries"][2]["enabled"])
            self.assertEqual(len(state["servers"]), 2)
            self.assertEqual(state["servers"][0]["name"], "manual")
            self.assertEqual(state["servers"][1]["activeProfileId"], 4)
            self.assertEqual(state["writes"].count("/api/v1/settings/network"), 1)
            self.assertEqual(state["writes"].count("/api/v1/settings/main"), 1)
            self.assertEqual(state["writes"].count("/api/v1/settings/jellyfin"), 1)
            self.assertEqual(state["jellyfin"]["hostname"], "http://127.0.0.1:8096")
            self.assertEqual(
                state["jellyfin"]["externalHostname"],
                "https://jellyfin.example.invalid",
            )
            self.assertEqual(state["main"]["defaultPermissions"], 32)
            self.assertEqual(
                [user["permissions"] for user in state["users"]], [2, 160, 32]
            )
            self.assertEqual(
                len([
                    path
                    for path in state["writes"]
                    if path.endswith("/settings/permissions")
                ]),
                2,
            )
            self.assertTrue(state["network"]["proxy"]["enabled"])
            self.assertEqual(state["network"]["proxy"]["hostname"], "169.254.202.94")

            # Updating a managed destination must omit the read-only ID from
            # the request body, even though GET includes it.
            state["profile"] = {"id": 5, "name": "HD-2160p"}
            state["profileMisses"] = 1
            config["settings"]["radarr"]["movies"]["activeProfileName"] = "HD-2160p"
            (path / "config.json").write_text(json.dumps(config))
            result = run_command(
                ["python3", str(SCRIPT), str(path / "config.json")],
                env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                check=False,
                capture_output=True,
                text=True,
                timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state["servers"][1]["activeProfileId"], 5)

            # A fresh portal synchronizes its libraries before enabling the selection.
            state["libraries"] = []
            state["libraryWrites"] = 0
            for args in (["--dry-run"], [], []):
                result = run_command(
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

            # Discovery must also preserve existing manual library choices.
            state["libraries"] = [
                {"id": "1", "name": "Manual", "enabled": True},
                {"id": "3", "name": "Unselected", "enabled": False},
            ]
            state["libraryWrites"] = 0
            for args in (["--dry-run"], [], []):
                result = run_command(
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
            self.assertEqual(
                {item["name"]: item["enabled"] for item in state["libraries"]},
                {"Manual": True, "Unselected": False, "Movies": True},
            )

            # An incorrect allowlist must fail before changing any account.
            permission_writes = len([
                item
                for item in state["writes"]
                if item.endswith("/settings/permissions")
            ])
            for names in (["admin", "missing"], ["viewer"]):
                config["settings"]["autoApproveUsers"] = names
                (path / "config.json").write_text(json.dumps(config))
                result = run_command(
                    ["python3", str(SCRIPT), str(path / "config.json")],
                    env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(
                    len([
                        item
                        for item in state["writes"]
                        if item.endswith("/settings/permissions")
                    ]),
                    permission_writes,
                )
