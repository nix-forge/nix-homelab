import json
import os
import shlex
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from notification_process import run as run_command

SCRIPT = (
    Path(__file__).resolve().parents[2] / "scripts/downloaders/qbittorrent_config.py"
)
CREDENTIALS_SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "scripts/downloaders/qbittorrent_credentials.py"
)
API_KEY_SCRIPT = (
    Path(__file__).resolve().parents[2] / "scripts/downloaders/qbittorrent_api_key.py"
)


class QbittorrentConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.key = "qbt_" + "a" * 28
        self.categories = {"manual": {"name": "manual", "savePath": "/manual"}}
        self.tags = ["manual"]
        self.writes = []
        case = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:
                pass

            def do_GET(self):
                if self.headers.get("Authorization") != "Bearer " + case.key:
                    self.send_response(401)
                    self.end_headers()
                    self.wfile.write(b"secret response body")
                    return
                self.send_response(200)
                self.end_headers()
                if self.path.endswith("/webapiVersion"):
                    self.wfile.write(b"2.14.1")
                elif self.path.endswith("/categories"):
                    self.wfile.write(json.dumps(case.categories).encode())
                elif self.path.endswith("/tags"):
                    self.wfile.write(json.dumps(case.tags).encode())

            def do_POST(self):
                if self.headers.get("Authorization") != "Bearer " + case.key:
                    self.send_response(401)
                    self.end_headers()
                    return
                body = urllib.parse.parse_qs(
                    self.rfile.read(int(self.headers["Content-Length"])).decode()
                )
                case.writes.append((self.path, body))
                if self.path.endswith("/createCategory"):
                    name = body["category"][0]
                    case.categories[name] = {
                        "name": name,
                        "savePath": body["savePath"][0],
                    }
                elif self.path.endswith("/editCategory"):
                    name = body["category"][0]
                    case.categories[name]["savePath"] = body["savePath"][0]
                elif self.path.endswith("/createTags"):
                    case.tags.extend(body["tags"][0].split(","))
                self.send_response(200)
                self.end_headers()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        (self.directory / "api-key").write_text(self.key + "\n")
        self.category_config = {"sonarr": {"savePath": "/downloads/sonarr"}}
        self.config = {
            "url": f"http://127.0.0.1:{self.server.server_port}",
            "mode": "managed",
            "categories": self.category_config,
            "tags": ["homelab", "manual"],
        }

    def run_cli(self, *arguments):
        path = self.directory / "config.json"
        path.write_text(json.dumps(self.config))
        return run_command(
            [sys.executable, str(SCRIPT), str(path), *arguments],
            env={**os.environ, "CREDENTIALS_DIRECTORY": str(self.directory)},
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )

    def test_create_reapply_update_and_preserve_unmanaged_resources(self):
        first = self.run_cli()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("sonarr", self.categories)
        self.assertIn("homelab", self.tags)
        self.assertIn("manual", self.categories)
        self.writes.clear()
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.writes, [])
        self.category_config["sonarr"]["savePath"] = "/downloads/tv"
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.categories["sonarr"]["savePath"], "/downloads/tv")
        self.assertIn("manual", self.categories)

    def test_bootstrap_and_dry_run_do_not_update_existing_category(self):
        self.categories["sonarr"] = {
            "name": "sonarr",
            "savePath": "/operator/path",
        }
        self.config["mode"] = "bootstrap"
        self.assertEqual(self.run_cli().returncode, 0)
        self.assertEqual(self.categories["sonarr"]["savePath"], "/operator/path")
        self.category_config["radarr"] = {"savePath": "/downloads/radarr"}
        self.assertEqual(self.run_cli("--dry-run").returncode, 0)
        self.assertNotIn("radarr", self.categories)

    def test_rejects_bad_key_and_never_prints_credentials_or_response(self):
        (self.directory / "api-key").write_text("not-an-api-key\n")
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("not-an-api-key", result.stderr)
        self.key = "qbt_" + "b" * 28
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("secret response", result.stderr)

    def test_startup_prepares_credentials_before_exec_and_preserves_arguments(self):
        preferences = self.directory / "preferences.ini"
        preferences.write_text("[Preferences]\n")
        marker = self.directory / "listener.json"
        fixture = Path(__file__).parent / "fixtures/verify_startup.py"
        source = (
            Path(__file__).resolve().parents[2]
            / "modules/downloaders/scripts/start-qbittorrent.sh"
        ).read_text()
        command = shlex.join([sys.executable, str(API_KEY_SCRIPT), str(preferences)])
        wrapper = self.directory / "start.sh"
        wrapper.write_text(
            "set -euo pipefail\n"
            + source.replace("@configureWebCredentials@", "").replace(
                "@configureApiKey@", command
            )
        )
        arguments = ["argument with spaces", "$literal", "--custom-option=chosen"]
        for key, success in ((self.key, True), ("invalid-fixture", False)):
            with self.subTest(success=success):
                marker.unlink(missing_ok=True)
                (self.directory / "api-key").write_text(key)
                result = run_command(
                    [
                        "bash",
                        str(wrapper),
                        sys.executable,
                        str(fixture),
                        str(preferences),
                        self.key,
                        str(marker),
                        *arguments,
                    ],
                    env={**os.environ, "CREDENTIALS_DIRECTORY": str(self.directory)},
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertEqual(marker.exists(), success)
                if success:
                    self.assertEqual(json.loads(marker.read_text()), arguments)

    def test_credentials_fragment_rejects_module_setting_overrides(self):
        source = self.directory / "webui.ini"
        target = self.directory / "validated.ini"
        source.write_text(
            "[Preferences]\n"
            "WebUI\\Username=fixture\n"
            'WebUI\\Password_PBKDF2="@ByteArray(public-hash)"\n'
            "[Network]\n"
            "Port=9999\n"
        )
        result = subprocess.run(
            [sys.executable, str(CREDENTIALS_SCRIPT), str(source), str(target)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(target.exists())

    def test_credentials_fragment_emits_only_allowed_keys(self):
        source = self.directory / "webui.ini"
        target = self.directory / "validated.ini"
        source.write_text(
            "[Preferences]\n"
            "WebUI\\Username=fixture\n"
            'WebUI\\Password_PBKDF2="@ByteArray(public-hash)"\n'
        )
        result = subprocess.run(
            [sys.executable, str(CREDENTIALS_SCRIPT), str(source), str(target)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            target.read_text(),
            '[Preferences]\nWebUI\\Password_PBKDF2="@ByteArray(public-hash)"\nWebUI\\Username=fixture\n',
        )

    def test_api_key_installer_updates_private_preferences_without_leaking_key(self):
        preferences = self.directory / "qBittorrent.conf"
        preferences.write_text(
            "[Preferences]\nWebUI\\APIKey=old\nWebUI\\Username=fixture\n"
        )
        preferences.chmod(0o600)
        result = subprocess.run(
            [sys.executable, str(API_KEY_SCRIPT), str(preferences)],
            env={**os.environ, "CREDENTIALS_DIRECTORY": str(self.directory)},
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("WebUI\\APIKey=" + self.key, preferences.read_text())
        self.assertEqual(preferences.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(self.key, result.stdout + result.stderr)

    def test_api_key_installer_rejects_invalid_key_without_modifying_preferences(self):
        preferences = self.directory / "qBittorrent.conf"
        original = "[Preferences]\nWebUI\\Username=fixture\n"
        preferences.write_text(original)
        (self.directory / "api-key").write_text("invalid-private-key")
        result = subprocess.run(
            [sys.executable, str(API_KEY_SCRIPT), str(preferences)],
            env={**os.environ, "CREDENTIALS_DIRECTORY": str(self.directory)},
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(preferences.read_text(), original)
        self.assertNotIn("invalid-private-key", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
