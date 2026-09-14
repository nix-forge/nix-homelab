"""Exercise the public reconciliation CLI against an authenticated HTTP API."""

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


class ReconciliationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.key = "public-disposable-api-key"
        self.objects: list[dict[str, Any]] = []
        self.writes: list[dict[str, Any]] = []
        self.handling: dict[str, Any] = {
            "id": 1,
            "enableCompletedDownloadHandling": False,
            "autoRedownloadFailed": True,
            "downloadClientWorkingFolders": "_manual",
        }
        self.media: dict[str, Any] = {
            "id": 1,
            "copyUsingHardlinks": False,
            "recycleBin": "/manual",
            "recycleBinCleanupDays": 7,
            "rescanAfterRefresh": "always",
            "skipFreeSpaceCheckWhenImporting": False,
            "minimumFreeSpaceWhenImporting": 100,
            "enableMediaInfo": True,
        }
        self.naming: dict[str, Any] = {
            "id": 1,
            "renameMovies": False,
            "replaceIllegalCharacters": True,
            "standardMovieFormat": "{Movie Title} ({Release Year})",
            "movieFolderFormat": "{Movie Title} ({Release Year})",
            "colonReplacementFormat": "smart",
        }
        case = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def do_GET(self):
                if self.headers.get("X-Api-Key") != case.key:
                    self.send_response(401)
                    self.end_headers()
                    self.wfile.write(b"sensitive error response must never be printed")
                    return
                self.send_response(200)
                self.end_headers()
                if self.path.endswith("/config/downloadclient"):
                    value = case.handling
                elif self.path.endswith("/config/mediamanagement"):
                    value = case.media
                elif self.path.endswith("/config/naming"):
                    value = case.naming
                elif self.path.endswith("/qualityprofile"):
                    value = [{"id": 19, "name": "Lossless"}]
                elif self.path.endswith("/indexerproxy/schema"):
                    value = [
                        {
                            "implementation": "Http",
                            "configContract": "HttpSettings",
                            "fields": [
                                {"name": "host", "value": "localhost"},
                                {"name": "port", "value": 8080},
                            ],
                        }
                    ]
                elif self.path.endswith("/schema"):
                    value = [
                        {
                            "implementation": "QBittorrent",
                            "configContract": "QBittorrentSettings",
                            "fields": [
                                {"name": "host", "value": "localhost"},
                                {"name": "password", "value": ""},
                            ],
                        }
                    ]
                else:
                    value = case.objects
                self.wfile.write(json.dumps(value).encode())

            def do_POST(self):
                self.write_object()

            def do_PUT(self):
                self.write_object()

            def write_object(self):
                if self.headers.get("X-Api-Key") != case.key:
                    self.send_response(401)
                    self.end_headers()
                    return
                value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                case.writes.append(value)
                if self.path.endswith("/config/downloadclient"):
                    case.handling = value
                elif self.path.endswith("/config/mediamanagement"):
                    case.media = value
                elif self.path.endswith("/config/naming"):
                    case.naming = value
                elif self.command == "POST":
                    value["id"] = len(case.objects) + 1
                    case.objects.append(value)
                else:
                    case.objects[int(value["id"]) - 1] = value
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        (self.directory / "api").write_text(self.key + "\n")
        (self.directory / "password").write_text("public-disposable-password\n")
        self.config: dict[str, Any] = {
            "kind": "radarr",
            "url": f"http://127.0.0.1:{self.server.server_port}",
            "apiKey": {"_credential": "api"},
            "mode": "managed",
            "resources": [
                {
                    "endpoint": "downloadclient",
                    "match": {"name": "torrents"},
                    "values": {
                        "implementation": "QBittorrent",
                        "enable": True,
                        "fields": {
                            "host": "127.0.0.1",
                            "password": {"_credential": "password"},
                        },
                    },
                }
            ],
        }

    def run_cli(self, *arguments):
        config = self.directory / "config.json"
        config.write_text(json.dumps(self.config))
        return subprocess.run(
            ["python3", str(SCRIPT), str(config), *arguments],
            env={**os.environ, "CREDENTIALS_DIRECTORY": str(self.directory)},
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )

    def test_create_then_reapply_preserves_manual_fields_and_rotates_secret(self):
        first = self.run_cli()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(len(self.objects), 1)
        self.assertEqual(self.objects[0]["configContract"], "QBittorrentSettings")
        self.objects[0]["priority"] = 17
        self.writes.clear()
        second = self.run_cli()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.writes, [])
        (self.directory / "password").write_text("rotated-public-password\n")
        third = self.run_cli()
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertEqual(self.objects[0]["priority"], 17)
        self.assertEqual(
            self.objects[0]["fields"][1]["value"], "rotated-public-password"
        )
        self.assertNotIn("password", third.stdout + third.stderr)

    def test_preview_does_not_write_and_bootstrap_preserves_existing_object(self):
        preview = self.run_cli("--dry-run")
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertEqual(self.objects, [])
        self.assertEqual(self.run_cli().returncode, 0)
        self.config["mode"] = "bootstrap"
        self.config["resources"][0]["values"]["enable"] = False
        self.writes.clear()
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])
        self.assertTrue(self.objects[0]["enable"])

    def test_authentication_errors_do_not_echo_response_or_credentials(self):
        self.key = "different-server-key"
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("sensitive", result.stderr)
        self.assertNotIn("disposable", result.stderr)

    def test_unknown_fields_fail_without_mutation(self):
        self.config["resources"][0]["values"]["fields"]["unknown"] = "value"
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes, [])

    def test_nonlocal_plaintext_endpoint_is_rejected_before_secret_read(self):
        self.config["url"] = "http://example.com"
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTPS", result.stderr)

    def test_named_profile_lookup_uses_server_id_and_rejects_missing_name(self):
        self.config["kind"] = "lidarr"
        self.config["resources"] = [
            {
                "endpoint": "rootfolder",
                "match": {"path": "/music"},
                "values": {
                    "name": "Music",
                    "defaultQualityProfileId": {
                        "_lookup": {"endpoint": "qualityprofile", "name": "Lossless"}
                    },
                },
            }
        ]
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.objects[0]["defaultQualityProfileId"], 19)
        self.config["resources"][0]["values"]["defaultQualityProfileId"]["_lookup"][
            "name"
        ] = "Missing"
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertEqual(len(self.writes), 1)

    def test_prowlarr_proxy_resolves_tag_created_earlier_in_the_same_plan(self):
        self.config["kind"] = "prowlarr"
        self.config["resources"] = [
            {
                "endpoint": "tag",
                "match": {"label": "through-proxy"},
                "values": {},
            },
            {
                "endpoint": "indexerproxy",
                "match": {"name": "local proxy"},
                "values": {
                    "implementation": "Http",
                    "tags": [
                        {
                            "_lookup": {
                                "endpoint": "tag",
                                "name": "through-proxy",
                            }
                        }
                    ],
                    "fields": {"host": "127.0.0.1", "port": 8080},
                },
            },
        ]

        preview = self.run_cli("--dry-run")
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertEqual(self.objects, [])
        self.assertEqual(
            json.loads(preview.stdout)["plannedDependencies"],
            [{"endpoint": "tag", "name": "through-proxy"}],
        )

        applied = self.run_cli()
        self.assertEqual(applied.returncode, 0, applied.stderr)
        proxy = next(item for item in self.objects if item.get("name") == "local proxy")
        tag = next(
            item for item in self.objects if item.get("label") == "through-proxy"
        )
        self.assertEqual(proxy["tags"], [tag["id"]])

    def test_indexer_proxy_is_rejected_for_non_prowlarr_managers(self):
        self.config["resources"][0]["endpoint"] = "indexerproxy"
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Prowlarr", result.stderr)
        self.assertEqual(self.writes, [])

    def test_download_handling_preview_bootstrap_and_managed_preservation(self):
        self.config["resources"] = []
        self.config["settings"] = {
            "mediaManagement": {"copyUsingHardlinks": True},
            "downloadHandling": {
                "enableCompletedDownloadHandling": True,
                "autoRedownloadFailed": False,
            },
        }
        self.assertEqual(self.run_cli("--dry-run").returncode, 0)
        self.assertEqual(self.writes, [])
        self.config["mode"] = "bootstrap"
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])
        self.config["mode"] = "managed"
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.handling["enableCompletedDownloadHandling"])
        self.assertFalse(self.handling["autoRedownloadFailed"])
        self.assertTrue(self.media["copyUsingHardlinks"])
        self.assertEqual(self.media["recycleBin"], "/manual")
        self.assertEqual(self.handling["downloadClientWorkingFolders"], "_manual")
        self.writes.clear()
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])
        self.config["settings"]["downloadHandling"]["unknown"] = True
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])

    def test_media_management_applies_safe_storage_policy_and_preserves_other_fields(
        self,
    ):
        self.config["resources"] = []
        self.config["settings"] = {
            "mediaManagement": {
                "copyUsingHardlinks": True,
                "recycleBin": "/media/.recycle/radarr",
                "recycleBinCleanupDays": 30,
                "rescanAfterRefresh": "afterManual",
                "skipFreeSpaceCheckWhenImporting": False,
                "minimumFreeSpaceWhenImporting": 20480,
                "enableMediaInfo": True,
            }
        }
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.media["recycleBin"], "/media/.recycle/radarr")
        self.assertEqual(self.media["recycleBinCleanupDays"], 30)
        self.assertEqual(self.media["rescanAfterRefresh"], "afterManual")
        self.assertEqual(self.media["minimumFreeSpaceWhenImporting"], 20480)
        self.assertTrue(self.media["copyUsingHardlinks"])
        self.assertTrue(self.media["enableMediaInfo"])
        self.assertEqual(self.media["id"], 1)

    def test_naming_policy_retains_release_metadata_and_preserves_other_fields(self):
        self.config["resources"] = []
        self.config["settings"] = {
            "naming": {
                "renameMovies": True,
                "replaceIllegalCharacters": True,
                "standardMovieFormat": (
                    "{Movie CleanTitle} {(Release Year)} {[Quality Full]}"
                    "{[MediaInfo VideoCodec]}{-Release Group}"
                ),
                "movieFolderFormat": "{Movie CleanTitle} ({Release Year})",
            }
        }
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.naming["renameMovies"])
        self.assertIn("{[Quality Full]}", self.naming["standardMovieFormat"])
        self.assertIn("{-Release Group}", self.naming["standardMovieFormat"])
        self.assertEqual(self.naming["colonReplacementFormat"], "smart")

    def test_manager_policy_rejects_invalid_enums_and_empty_naming_formats(self):
        self.config["resources"] = []
        self.config["settings"] = {
            "mediaManagement": {"rescanAfterRefresh": "whenever"}
        }
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])

        self.config["settings"] = {"naming": {"standardMovieFormat": ""}}
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])
