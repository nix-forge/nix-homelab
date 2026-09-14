import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2] / "scripts/downloaders/qbittorrent-config.py"
)
CREDENTIALS_SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "scripts/downloaders/qbittorrent-credentials.py"
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
        return subprocess.run(
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


if __name__ == "__main__":
    unittest.main()
