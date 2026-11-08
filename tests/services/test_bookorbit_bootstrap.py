"""The public BookOrbit gate opens only for a verified sealed administrator."""

import json
import os
import runpy
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, override
from unittest import mock
from urllib.parse import parse_qs

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/services/bootstrap_bookorbit.py"


class BookOrbitBootstrapTest(unittest.TestCase):
    """Exercise first claim, restart, and a rejected credential change."""

    def test_sealed_admin_controls_readiness(self) -> None:  # ruff: ignore[too-many-statements] - The fake API exercises one startup transaction.
        """A different password cannot leave the proxy readiness file present."""
        state: dict[str, Any] = {
            "setup": False,
            "registration": False,
            "password": "",
            "libraries": [],
            "manager": None,
            "source_enabled": False,
            "source_test_ok": True,
            "tag_label": "vpn",
            "proxy_host": "169.254.1.2",
            "download_client": None,
            "automation": {},
        }

        class Handler(BaseHTTPRequestHandler):
            @override
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def reply(self, status: int, value: object) -> None:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())

            def do_GET(self) -> None:  # ruff: ignore[too-many-branches] - One API fixture for the bootstrap transaction.
                if self.path == "/api/v1/auth/setup-status":
                    self.reply(
                        200,
                        {
                            "needsSetup": not state["setup"],
                            "allowRegistration": state["registration"],
                        },
                    )
                elif self.path == "/api/v1/libraries":
                    if (
                        self.headers.get("Authorization")
                        != "Bearer fixture-access-token"
                    ):
                        self.reply(401, {})
                    else:
                        self.reply(200, state["libraries"])
                elif self.path == "/api/v2/torrents/categories":
                    if self.headers.get("Cookie") != "SID=fixture":
                        self.reply(403, {})
                    else:
                        self.reply(
                            200,
                            {
                                "bookorbit": {
                                    "savePath": "/media/downloads/torrents/bookorbit/downloads"
                                }
                            },
                        )
                elif self.path == "/api/v1/admin/download-clients":
                    self.reply(
                        200,
                        {
                            "clients": [state["download_client"]]
                            if state["download_client"]
                            else [],
                            "encryptionConfigured": True,
                        },
                    )
                elif self.path == "/api/v1/admin/book-request-automation":
                    self.reply(200, state["automation"])
                elif self.path == "/api/v1/tag":
                    self.reply(200, [{"id": 2, "label": state["tag_label"]}])
                elif self.path == "/api/v1/indexer":
                    self.reply(
                        200,
                        [
                            {
                                "id": 3,
                                "enable": True,
                                "protocol": "torrent",
                                "tags": [2],
                                "capabilities": {"categories": [{"id": 7000}]},
                            }
                        ],
                    )
                elif self.path == "/api/v1/indexerProxy":
                    self.reply(
                        200,
                        [
                            {
                                "implementation": "Socks5",
                                "name": "vpn",
                                "tags": [2],
                                "fields": [
                                    {
                                        "name": "host",
                                        "value": state["proxy_host"],
                                    },
                                    {"name": "port", "value": 1080},
                                ],
                            }
                        ],
                    )
                elif self.path == "/api/v1/admin/request-indexer-managers":
                    self.reply(
                        200,
                        {"managers": [state["manager"]] if state["manager"] else []},
                    )
                elif self.path == "/api/v1/book-requests/source-status":
                    self.reply(
                        200,
                        {
                            "configured": 1,
                            "enabled": int(state["source_enabled"]),
                        },
                    )
                else:
                    self.reply(404, {})

            def do_POST(self) -> None:  # ruff: ignore[too-many-branches] - One API fixture for the bootstrap transaction.
                length = int(self.headers.get("Content-Length", "0"))
                if self.path == "/api/v2/auth/login":
                    form = parse_qs(self.rfile.read(length).decode())
                    if form != {
                        "username": ["qbit-user"],
                        "password": ["qbit-password"],
                    }:
                        self.reply(403, {})
                    else:
                        self.send_response(204)
                        self.send_header("Set-Cookie", "SID=fixture; Path=/")
                        self.end_headers()
                    return
                body = json.loads(self.rfile.read(length)) if length else {}
                if self.path == "/api/v1/auth/setup":
                    if self.headers.get("X-Setup-Token") != "fixture-token":
                        self.reply(403, {})
                        return
                    state["setup"] = True
                    state["password"] = body["password"]
                    self.reply(201, {"user": {"username": body["username"]}})
                elif self.path == "/api/v1/auth/login":
                    if body["password"] != state["password"]:
                        self.reply(401, {})
                    else:
                        self.reply(
                            200,
                            {
                                "user": {
                                    "username": body["username"],
                                    "isSuperuser": True,
                                },
                                "accessToken": "fixture-access-token",
                            },
                        )
                elif self.path == "/api/v1/libraries":
                    if (
                        self.headers.get("Authorization")
                        != "Bearer fixture-access-token"
                    ):
                        self.reply(401, {})
                        return
                    created = {
                        "id": len(state["libraries"]) + 1,
                        **body,
                        "folders": [
                            {"id": len(state["libraries"]) + 10, "path": path}
                            for path in body["folders"]
                        ],
                    }
                    state["libraries"].append(created)
                    self.reply(201, created)
                elif self.path == "/api/v1/admin/request-indexer-managers":
                    state["manager"] = {
                        "id": 1,
                        "name": body["name"],
                        "type": "prowlarr",
                    }
                    self.reply(201, state["manager"])
                elif self.path == "/api/v1/admin/request-indexer-managers/1/test":
                    self.reply(200, {"success": True})
                elif self.path == "/api/v1/admin/request-indexer-managers/1/sync":
                    self.reply(
                        200,
                        {
                            "manager": {
                                "sources": [
                                    {
                                        "id": 5,
                                        "externalId": "3",
                                        "adapterType": "torznab",
                                        "available": True,
                                        "enabled": state["source_enabled"],
                                    }
                                ]
                            }
                        },
                    )
                elif self.path == "/api/v1/admin/request-indexers/5/test":
                    self.reply(
                        200 if state["source_test_ok"] else 502,
                        {"success": state["source_test_ok"]},
                    )
                elif self.path == "/api/v1/admin/download-clients":
                    state["download_client"] = {
                        "id": 7,
                        **{
                            key: value
                            for key, value in body.items()
                            if key != "password"
                        },
                        "pathMappings": [{"id": 8, **body["pathMappings"][0]}],
                    }
                    self.reply(201, state["download_client"])
                elif self.path == "/api/v1/admin/download-clients/7/test":
                    self.reply(200, {"success": True})
                elif self.path == "/api/v1/admin/download-clients/7/test-path-mapping":
                    self.reply(200, {"hardlinkWorks": body["mappingId"] == 8})
                else:
                    self.reply(404, {})

            def do_PUT(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if self.path == "/api/v1/admin/request-indexer-managers/1":
                    self.reply(200, state["manager"])
                elif self.path == "/api/v1/admin/request-indexer-managers/1/sources/5":
                    state["source_enabled"] = body["enabled"]
                    self.reply(200, {"id": 1})
                elif self.path == "/api/v1/admin/download-clients/7":
                    state["download_client"].update({
                        key: value for key, value in body.items() if key != "password"
                    })
                    state["download_client"]["pathMappings"] = [
                        {"id": 8, **body["pathMappings"][0]}
                    ]
                    self.reply(200, state["download_client"])
                elif self.path == "/api/v1/admin/book-request-automation":
                    # BookOrbit 3.6 rejects unknown destination media kinds.
                    if set(body["destinations"]) - {"ebook", "audiobook"}:
                        self.reply(400, {"message": "Unsupported destination medium"})
                        return
                    state["automation"].update(body)
                    self.reply(200, state["automation"])
                else:
                    self.reply(404, {})

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in (
                ("admin-username", "sealed-admin"),
                ("admin-email", "admin@books.invalid"),
                ("admin-password", "FixturePassword123"),
                ("setup-token", "fixture-token"),
                ("prowlarr-api-key", "fixture-prowlarr-key"),
                ("qbittorrent-username", "qbit-user"),
                ("qbittorrent-password", "qbit-password"),
            ):
                (root / name).write_text(value)
            ready = root / "ready"
            settings = root / "settings.json"
            settings.write_text(
                json.dumps({
                    "vpnTag": "vpn",
                    "proxy": {
                        "name": "vpn",
                        "host": "169.254.1.2",
                        "port": 1080,
                    },
                    "bookCategories": [3000, 7000],
                    "managerName": "Prowlarr VPN books",
                    "acquisition": {
                        "enabled": True,
                        "name": "qBittorrent books",
                        "url": f"http://127.0.0.1:{server.server_port}",
                        "category": "bookorbit",
                        "downloadDir": "/media/downloads/torrents/bookorbit/downloads",
                        "localDownloadDir": "/intake/downloads",
                        "minReleaseScore": 90,
                        "minImportScore": 85,
                        "destinations": {
                            "audiobook": "Audiobooks",
                            "ebook": "Books and comics",
                        },
                    },
                    "libraries": [
                        {
                            "name": "Audiobooks",
                            "icon": "Headphones",
                            "folders": ["/books/audiobooks"],
                            "allowedFormats": ["m4b", "mp3"],
                            "organizationMode": "book_per_folder",
                        },
                        {
                            "name": "Books and comics",
                            "icon": "BookOpen",
                            "folders": ["/books/books"],
                            "allowedFormats": ["epub", "cbz"],
                            "organizationMode": "book_per_file",
                        },
                    ],
                })
            )
            env = {
                **os.environ,
                "CREDENTIALS_DIRECTORY": directory,
                "BOOKORBIT_READY_DIR": directory,
                "http_proxy": "http://127.0.0.1:1",
            }
            argv = [
                str(SCRIPT),
                f"http://127.0.0.1:{server.server_port}",
                f"http://127.0.0.1:{server.server_port}",
                str(settings),
            ]
            with (
                mock.patch.dict(os.environ, env),
                mock.patch.object(sys, "argv", argv),
            ):
                runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertTrue(ready.exists())
                self.assertEqual(len(state["libraries"]), 2)
                self.assertTrue(state["source_enabled"])
                assert state["manager"] is not None
                assert state["download_client"] is not None
                self.assertEqual(state["manager"]["name"], "Prowlarr VPN books")
                self.assertEqual(state["download_client"]["category"], "bookorbit")
                self.assertEqual(
                    state["download_client"]["pathMappings"][0]["localPath"],
                    "/intake/downloads",
                )
                self.assertTrue(state["automation"]["autoGrabEnabled"])
                self.assertFalse(state["automation"]["autoRetryEnabled"])
                self.assertEqual(state["automation"]["autoGrabMinScore"], 90)
                self.assertEqual(
                    {library["folders"][0]["path"] for library in state["libraries"]},
                    {"/books/audiobooks", "/books/books"},
                )
                self.assertTrue(all(library["watch"] for library in state["libraries"]))
                self.assertTrue(
                    all(
                        not library["fileWriteEnabled"]
                        for library in state["libraries"]
                    )
                )
                ready.unlink()
                runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertTrue(ready.exists())
                self.assertEqual(len(state["libraries"]), 2)
                ready.unlink()
                state["tag_label"] = "direct"
                with self.assertRaisesRegex(RuntimeError, "no VPN route tag"):
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertFalse(ready.exists())
                state["tag_label"] = "vpn"
                state["proxy_host"] = "127.0.0.1"
                with self.assertRaisesRegex(RuntimeError, "VPN SOCKS proxy"):
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertFalse(ready.exists())
                state["proxy_host"] = "169.254.1.2"
                state["source_test_ok"] = False
                state["source_enabled"] = False
                runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertTrue(ready.exists())
                self.assertTrue(state["source_enabled"])
                ready.unlink()
                state["source_test_ok"] = True
                (root / "admin-password").write_text("WrongPassword123")
                with self.assertRaises(RuntimeError):
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertFalse(ready.exists())
                (root / "admin-password").write_text("FixturePassword123")
                state["registration"] = True
                with self.assertRaises(RuntimeError):
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertFalse(ready.exists())
