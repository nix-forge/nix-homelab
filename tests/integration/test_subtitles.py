"""Bazarr's settings endpoint requires form data, not JSON."""

import importlib
import json
import os
import re
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from notification_process import run as run_command

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/reconcile.py"


class SubtitleTest(unittest.TestCase):
    def test_release_preference_excludes_japanese_only_label(self):
        definition = json.loads(
            (
                SCRIPT.parents[2]
                / "modules/optional/quality/custom-formats/subtitled-release.json"
            ).read_text()
        )
        pattern = definition["specifications"][0]["fields"]["value"]
        for title in (
            "Episode 1080p (Multi-Subs)",
            "Episode 1080p (English-Sub)",
            "Episode 1080p ESub",
        ):
            self.assertIsNotNone(re.search(pattern, title), title)
        self.assertIsNone(re.search(pattern, "Episode 1080p (Japanese Sub)"))

    def test_anime_profile_is_assigned_to_existing_series_idempotently(self):
        sys.path.insert(0, str(SCRIPT.parent))
        reconcile_bazarr = importlib.import_module("adapters.bazarr").reconcile_bazarr

        class Client:
            def __init__(self):
                self.series = [
                    {"sonarrSeriesId": 1, "seriesType": "anime", "profileId": 1},
                    {"sonarrSeriesId": 2, "seriesType": "standard", "profileId": 1},
                ]
                self.writes = []

            def request(self, method, path, data=None, *, form=False):
                if (method, path) == ("GET", "/api/system/settings"):
                    return {}
                if (method, path) == ("GET", "/api/system/languages/profiles"):
                    return [
                        {
                            "profileId": 2,
                            "name": "Anime English and Japanese",
                            "items": [],
                        }
                    ]
                if (method, path) == ("GET", "/api/series"):
                    return {"data": self.series}
                if (method, path) == ("POST", "/api/series"):
                    if not form:
                        raise AssertionError("Bazarr requires form data")
                    assert data is not None
                    self.writes.append(data)
                    self.series[0]["profileId"] = data["profileid"]
                    return None
                raise AssertionError((method, path))

        client = Client()
        config = {
            "mode": "managed",
            "settings": {"seriesTypeProfiles": {"anime": "Anime English and Japanese"}},
        }
        self.assertEqual(reconcile_bazarr(client, config, True), {"changed": 1})
        self.assertEqual(client.writes, [])
        self.assertEqual(reconcile_bazarr(client, config, False), {"changed": 1})
        self.assertEqual(client.writes, [{"seriesid": 1, "profileid": 2}])
        self.assertEqual(reconcile_bazarr(client, config, False), {"changed": 0})

    def test_existing_profile_keeps_server_managed_language_fields(self):
        sys.path.insert(0, str(SCRIPT.parent))
        reconcile_bazarr = importlib.import_module("adapters.bazarr").reconcile_bazarr

        profile = {
            "profileId": 7,
            "name": "English",
            "items": [
                {
                    "id": 1,
                    "language": "en",
                    "hi": "False",
                    "forced": "False",
                    "audio_exclude": "False",
                    "audio_only_include": "False",
                }
            ],
            "cutoff": None,
            "mustContain": "",
            "mustNotContain": "",
            "originalFormat": False,
            "tag": None,
        }

        class Client:
            def __init__(self):
                self.posted = None

            def request(self, method, path, data=None, *, form=False):
                if method == "GET" and path == "/api/system/settings":
                    return {}
                if method == "GET" and path == "/api/system/languages/profiles":
                    return [profile]
                if method == "POST" and path == "/api/system/settings":
                    if not form:
                        raise AssertionError("Bazarr requires form data")
                    assert data is not None
                    payload = json.loads(data["languages-profiles"])
                    if "audio_only_include" not in payload[0]["items"][0]:
                        raise RuntimeError(
                            "Bazarr rejected an incomplete language item"
                        )
                    self.posted = payload
                    return None
                raise AssertionError((method, path))

        config = {
            "mode": "managed",
            "settings": {
                "languageProfiles": {
                    "English": {
                        "cutoff": 1,
                        "items": [
                            {
                                "id": 1,
                                "language": "en",
                                "hi": "False",
                                "forced": "False",
                                "audio_exclude": "False",
                            }
                        ],
                    }
                }
            },
        }
        client = Client()
        self.assertEqual(reconcile_bazarr(client, config, False), {"changed": 1})
        assert client.posted is not None
        self.assertEqual(client.posted[0]["items"][0]["audio_only_include"], "False")

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
                                    "audio_only_include": "False",
                                }
                            ],
                            "cutoff": 1,
                        }
                    },
                },
            }
            (path / "config.json").write_text(json.dumps(config))
            preview = run_command(
                ["python3", str(SCRIPT), str(path / "config.json"), "--dry-run"],
                env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                check=False,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertEqual(state["writes"], 0)
            for _ in range(2):
                result = run_command(
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
