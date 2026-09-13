"""Runtime credential installers preserve private application configuration."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts/integration"


class CredentialTest(unittest.TestCase):
    def test_servarr_environment_is_private_and_invalid_key_preserves_previous_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            key = path / "api-key"
            key.write_text("0123456789abcdef0123456789abcdef\n")
            target = path / "environment"
            command = ["python3", str(SCRIPTS / "api-key.py"), "RADARR", str(target)]
            environment = {**os.environ, "CREDENTIALS_DIRECTORY": directory}
            first = subprocess.run(
                command, env=environment, capture_output=True, text=True, check=False
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(
                target.read_text(), "RADARR__AUTH__APIKEY=0123456789abcdef0123456789abcdef\n"
            )
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            key.write_text("invalid\nINJECTED=value")
            second = subprocess.run(
                command, env=environment, capture_output=True, text=True, check=False
            )
            self.assertNotEqual(second.returncode, 0)
            self.assertNotIn("INJECTED", second.stderr)
            self.assertNotIn("INJECTED", target.read_text())

    def test_bazarr_key_rotation_preserves_provider_and_user_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            key = path / "homelab-api-key"
            key.write_text("0123456789abcdef0123456789abcdef\n")
            (path / "config").mkdir()
            target = path / "config/config.yaml"
            target.write_text(
                "general:\n  ip: 127.0.0.1\nsonarr:\n  port: 9999\nauth:\n  username: viewer\n"
            )
            command = ["python3", str(SCRIPTS / "bazarr-key.py"), directory]
            environment = {**os.environ, "CREDENTIALS_DIRECTORY": directory}
            first = subprocess.run(
                command, env=environment, capture_output=True, text=True, check=False
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn("port: 9999", target.read_text())
            self.assertIn("username: viewer", target.read_text())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            key.write_text("abcdef0123456789abcdef0123456789")
            second = subprocess.run(
                command, env=environment, capture_output=True, text=True, check=False
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertNotIn("0123456789abcdef0123456789abcdef", target.read_text())
            self.assertIn("apikey: abcdef0123456789abcdef0123456789", target.read_text())
