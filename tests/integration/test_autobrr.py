"""Exercise named autobrr resources against an authenticated HTTP fixture."""

import copy
import importlib.util
import json
import os
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/integration/autobrr.py"
spec = importlib.util.spec_from_file_location("autobrr_adapter", SOURCE)
if spec is None or spec.loader is None:
    raise ImportError(f"Could not load autobrr adapter from {SOURCE}")
autobrr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(autobrr)


class Client:
    def __init__(self, url):
        self.url = url
        self.headers = {}

    def request(self, method, path, body=None):
        request = urllib.request.Request(
            self.url + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Content-Type": "application/json", **self.headers},
            method=method,
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            data = response.read()
            return json.loads(data) if data else None


class AutobrrTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.state = Path(directory.name)
        environment = patch.dict(os.environ, {"STATE_DIRECTORY": str(self.state)})
        environment.start()
        self.addCleanup(environment.stop)
        self.objects: dict[str, list[dict[str, Any]]] = {
            "download_clients": [],
            "filters": [],
            "actions": [],
            "indexer": [{"id": 101, "name": "Fixture"}, {"id": 102, "name": "Manual"}],
        }
        self.writes: list[tuple[str, str, Any]] = []
        self.fail_action = False
        case = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def handle_api(self):
                if self.path == "/api/healthz/readiness":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"OK")
                    return
                if self.headers.get("X-API-Token") != "fixture-api-key":
                    self.send_response(401)
                    self.end_headers()
                    return
                parts = self.path.strip("/").split("/")
                resource = parts[1]
                objects = case.objects[resource]
                status = 200
                if self.command == "GET":
                    body = copy.deepcopy(objects)
                    if resource == "actions":
                        for action in body:
                            action.pop("filter_id", None)
                    elif resource == "filters" and len(parts) == 3:
                        body = next(
                            item for item in body if item["id"] == int(parts[2])
                        )
                        body["actions"] = [
                            {
                                key: value
                                for key, value in action.items()
                                if key != "filter_id"
                            }
                            for action in case.objects["actions"]
                            if action["filter_id"] == body["id"]
                        ]
                else:
                    body = json.loads(
                        self.rfile.read(int(self.headers["Content-Length"]))
                    )
                    case.writes.append((self.command, self.path, copy.deepcopy(body)))
                    if resource == "actions" and case.fail_action:
                        self.send_response(503)
                        self.end_headers()
                        return
                    if (
                        self.command == "POST"
                        and resource == "filters"
                        and (
                            body.get("resolutions") is None
                            or body.get("codecs") is None
                        )
                    ):
                        self.send_response(500)
                        self.end_headers()
                        return
                    if self.command == "POST":
                        body["id"] = len(objects) + 1
                        objects.append(copy.deepcopy(body))
                        status = 201
                    else:
                        identity = int(parts[2]) if len(parts) == 3 else body["id"]
                        current = next(
                            item for item in objects if item["id"] == identity
                        )
                        if (
                            resource == "download_clients"
                            and body.get("password") == "<redacted>"
                        ):
                            body["password"] = current.get("password", "")
                        if self.command == "PATCH":
                            current.update(copy.deepcopy(body))
                        else:
                            current.clear()
                            current.update(copy.deepcopy(body))
                        body = copy.deepcopy(current)
                if resource == "download_clients":
                    rows = body if isinstance(body, list) else [body]
                    for row in rows:
                        if row.get("password"):
                            row["password"] = "<redacted>"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            do_GET = handle_api
            do_POST = handle_api
            do_PUT = handle_api
            do_PATCH = handle_api

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.client = Client(f"http://127.0.0.1:{server.server_port}")
        self.config: dict[str, Any] = {
            "apiKey": "fixture-api-key",
            "mode": "managed",
            "settings": {
                "downloadClients": {
                    "Downloads": {
                        "type": "QBITTORRENT",
                        "host": "http://127.0.0.1:8081",
                        "enabled": True,
                        "username": "fixture",
                        "password": "disposable-password",
                    }
                },
                "filters": {
                    "Selected releases": {
                        "values": {
                            "enabled": True,
                            "match_releases": "Permitted.*",
                            "max_size": "5GB",
                            "max_downloads": 2,
                            "max_downloads_unit": "DAY",
                        },
                        "indexers": ["Fixture"],
                        "actions": {
                            "Download": {
                                "type": "QBITTORRENT",
                                "client": "Downloads",
                                "enabled": True,
                                "category": "manual",
                                "paused": True,
                            }
                        },
                    }
                },
            },
        }

    def run_adapter(self, dry_run=False):
        return autobrr.reconcile(self.client, self.config, dry_run)

    def test_action_names_are_scoped_by_filter_detail(self):
        self.run_adapter()
        second = copy.deepcopy(
            self.config["settings"]["filters"][
                next(iter(self.config["settings"]["filters"]))
            ]
        )
        self.config["settings"]["filters"]["Second"] = second
        self.run_adapter()
        self.assertEqual(len(self.objects["actions"]), 2)
        self.assertEqual(
            {item["filter_id"] for item in self.objects["actions"]}, {1, 2}
        )
        self.writes.clear()
        self.run_adapter()
        self.assertEqual(self.writes, [])

    def test_idempotence_rotation_and_undeclared_relationships(self):
        self.run_adapter()
        self.assertEqual(self.objects["actions"][0]["client_id"], 1)
        self.assertTrue(self.objects["filters"][0]["enabled"])
        self.assertFalse(
            next(
                body
                for method, path, body in self.writes
                if method == "POST" and path == "/api/filters"
            )["enabled"]
        )
        self.writes.clear()
        self.run_adapter()
        self.assertEqual(self.writes, [])
        self.objects["filters"][0]["indexers"].append({"id": 102, "name": "Manual"})
        self.objects["filters"][0]["except_releases"] = "Keep.UI.Rule"
        self.objects["actions"].append({
            "id": 50,
            "name": "Manual action",
            "filter_id": 1,
            "type": "TEST",
            "enabled": True,
        })
        self.objects["filters"].append({"id": 50, "name": "Unmanaged", "enabled": True})
        self.config["settings"]["filters"]["Selected releases"]["values"][
            "max_downloads"
        ] = 3
        self.run_adapter()
        self.assertEqual(self.objects["filters"][0]["except_releases"], "Keep.UI.Rule")
        self.assertIn(
            102, [item["id"] for item in self.objects["filters"][0]["indexers"]]
        )
        self.assertEqual(self.objects["actions"][1]["name"], "Manual action")
        self.assertTrue(self.objects["filters"][1]["enabled"])
        self.writes.clear()
        self.config["settings"]["downloadClients"]["Downloads"]["password"] = (
            "rotated-password"
        )
        self.run_adapter()
        self.assertEqual(len(self.writes), 1)
        self.assertEqual(
            self.objects["download_clients"][0]["password"], "rotated-password"
        )
        self.writes.clear()
        self.run_adapter()
        self.assertEqual(self.writes, [])
        serialized = (self.state / "autobrr-password-state.json").read_text()
        self.assertNotIn("rotated-password", serialized)
        self.assertEqual(
            (self.state / "autobrr-password-state.json").stat().st_mode & 0o777, 0o600
        )

    def test_undeclared_redacted_password_survives_host_update(self):
        self.run_adapter()
        desired = self.config["settings"]["downloadClients"]["Downloads"]
        del desired["password"]
        desired["host"] = "http://127.0.0.1:8082"
        self.run_adapter()
        self.assertEqual(
            self.objects["download_clients"][0]["password"], "disposable-password"
        )
        self.assertEqual(self.objects["download_clients"][0]["host"], desired["host"])

    def test_preview_and_bootstrap_do_not_mutate_existing_state(self):
        self.run_adapter(dry_run=True)
        self.assertEqual(self.writes, [])
        self.assertFalse((self.state / "autobrr-password-state.json").exists())
        self.run_adapter()
        self.writes.clear()
        self.config["mode"] = "bootstrap"
        self.config["settings"]["downloadClients"]["Downloads"]["password"] = (
            "different"
        )
        self.config["settings"]["filters"]["Selected releases"]["values"][
            "max_downloads"
        ] = 4
        self.run_adapter()
        self.assertEqual(self.writes, [])

    def test_rejects_ambiguous_names_and_unbounded_filters(self):
        self.objects["download_clients"] = [
            {"id": 1, "name": "Downloads"},
            {"id": 2, "name": "Downloads"},
        ]
        with self.assertRaises(ValueError):
            self.run_adapter()
        self.assertEqual(self.writes, [])
        self.objects["download_clients"] = []
        self.config["settings"]["filters"]["Selected releases"]["values"].pop(
            "max_size"
        )
        with self.assertRaises(ValueError):
            self.run_adapter()
        self.assertEqual(self.writes, [])

    def test_failed_action_leaves_filter_disabled(self):
        self.fail_action = True
        with self.assertRaises(urllib.error.HTTPError) as raised:
            self.run_adapter()
        raised.exception.close()
        self.assertFalse(self.objects["filters"][0]["enabled"])
        self.assertEqual(sum(path == "/api/actions" for _, path, _ in self.writes), 1)
        self.fail_action = False
        self.run_adapter()
        self.assertTrue(self.objects["filters"][0]["enabled"])
        self.assertEqual(len(self.objects["filters"]), 1)
        self.assertEqual(len(self.objects["actions"]), 1)

    def test_common_cli_authentication_and_packaging(self):
        settings = {**self.config, "kind": "autobrr", "url": self.client.url}
        settings["apiKey"] = {"_credential": "api-key"}
        (self.state / "api-key").write_text("fixture-api-key")
        config = self.state / "config.json"
        config.write_text(json.dumps(settings))
        result = subprocess.run(
            ["python3", str(SOURCE.parent / "reconcile.py"), str(config), "--dry-run"],
            env={**os.environ, "CREDENTIALS_DIRECTORY": str(self.state)},
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["dryRun"])
        self.assertEqual(self.writes, [])

    def test_enabled_intent_is_required_before_any_mutation(self):
        self.config["settings"]["filters"]["Selected releases"]["values"].pop("enabled")
        with self.assertRaises(TypeError):
            self.run_adapter()
        self.assertEqual(self.writes, [])

    def test_qbittorrent_cannot_silently_downgrade_https(self):
        desired = self.config["settings"]["downloadClients"]["Downloads"]
        for host, tls in (
            ("https://downloads.example.test", None),
            ("https://downloads.example.test", False),
            ("http://downloads.example.test", True),
        ):
            with self.subTest(host=host, tls=tls):
                desired["host"] = host
                if tls is None:
                    desired.pop("tls", None)
                else:
                    desired["tls"] = tls
                with self.assertRaises(ValueError):
                    self.run_adapter()
                self.assertEqual(self.writes, [])
        desired.update(host="https://downloads.example.test", tls=True)
        self.run_adapter()
        self.assertTrue(self.objects["download_clients"][0]["tls"])
