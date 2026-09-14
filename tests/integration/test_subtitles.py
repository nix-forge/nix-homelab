"""Bazarr's settings endpoint requires form data, not JSON."""

import json
import os
import subprocess
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class SubtitleTest(unittest.TestCase):
    def test_settings_are_encoded_as_form_and_repeated_apply_is_idle(self):
        state: dict[str, Any] = {
            "sonarr": {"ip": "localhost", "apikey": ""},
            "writes": 0,
            "general": {
                "serie_default_enabled": False,
                "serie_default_profile": "",
                "movie_default_enabled": False,
                "movie_default_profile": "",
            },
            "languages": [
                {"code2": "fr", "enabled": True},
                {"code2": "en", "enabled": False},
            ],
            "profiles": [
                {
                    "profileId": 7,
                    "name": "Manual",
                    "items": [],
                    "cutoff": None,
                    "mustContain": "",
                    "mustNotContain": "",
                    "originalFormat": False,
                    "tag": None,
                }
            ],
        }
        case = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                value = (
                    state["profiles"]
                    if self.path.endswith("/languages/profiles")
                    else state["languages"]
                    if self.path.endswith("/system/languages")
                    else {"sonarr": state["sonarr"], "general": state["general"]}
                )
                self.wfile.write(json.dumps(value).encode())

            def do_POST(self):
                case.assertEqual(
                    self.headers["Content-Type"], "application/x-www-form-urlencoded"
                )
                fields = urllib.parse.parse_qs(
                    self.rfile.read(int(self.headers["Content-Length"])).decode()
                )
                state["sonarr"]["ip"] = fields["settings-sonarr-ip"][0]
                state["sonarr"]["apikey"] = fields["settings-sonarr-apikey"][0]
                if "languages-profiles" in fields:
                    state["profiles"] = json.loads(fields["languages-profiles"][0])
                for key in state["general"]:
                    if "settings-general-" + key in fields:
                        raw = fields["settings-general-" + key][0]
                        state["general"][key] = (
                            raw == "true" if key.endswith("enabled") else int(raw)
                        )
                if "languages-enabled" in fields:
                    for language in state["languages"]:
                        language["enabled"] = (
                            language["code2"] in fields["languages-enabled"]
                        )
                state["writes"] += 1
                self.send_response(204)
                self.end_headers()

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "key").write_text("public-fixture-key")
            config = {
                "kind": "bazarr",
                "url": f"http://127.0.0.1:{server.server_port}",
                "mode": "managed",
                "apiKey": {"_credential": "key"},
                "settings": {
                    "enabledLanguages": ["en"],
                    "defaultProfiles": {"series": "English", "movies": "English"},
                    "sonarr": {"ip": "127.0.0.1", "apikey": {"_credential": "key"}},
                    "languageProfiles": {
                        "English": {
                            "items": [
                                {
                                    "id": 1,
                                    "language": "en",
                                    "hi": "False",
                                    "forced": "False",
                                    "audio_exclude": "False",
                                }
                            ],
                            "cutoff": 1,
                        }
                    },
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            preview = subprocess.run(
                ["python3", str(SCRIPT), str(path / "config.json"), "--dry-run"],
                env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                check=False,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertEqual(state["writes"], 0)
            for _ in range(2):
                result = subprocess.run(
                    ["python3", str(SCRIPT), str(path / "config.json")],
                    env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state["writes"], 1)
            self.assertEqual(
                [profile["name"] for profile in state["profiles"]],
                ["Manual", "English"],
            )
            self.assertEqual(state["profiles"][0]["profileId"], 7)
            self.assertEqual(state["sonarr"]["apikey"], "public-fixture-key")
            self.assertTrue(all(item["enabled"] for item in state["languages"]))
            self.assertEqual(state["general"]["serie_default_profile"], 8)
            self.assertEqual(state["general"]["movie_default_profile"], 8)
