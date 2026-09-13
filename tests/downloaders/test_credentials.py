import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/downloaders/nzbget-credentials.py"


class CredentialsTest(unittest.TestCase):
    def test_rotation_preserves_ui_settings_and_rejects_configuration_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "nzbget.conf"
            target.write_text("ControlPassword=old\nServer1.Connections=4\n")
            source = root / "nzbget-credentials"
            source.write_text("ControlPassword=public-fixture\nServer1.Password=provider-fixture\n")

            def run():
                return subprocess.run(
                    [sys.executable, str(SCRIPT), str(target)],
                    env={**os.environ, "CREDENTIALS_DIRECTORY": directory},
                    capture_output=True,
                    text=True,
                    check=False,
                )

            self.assertEqual(run().returncode, 0)
            self.assertIn("Server1.Connections=4", target.read_text())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            source.write_text("ControlPassword=rotated-public-fixture\n")
            self.assertEqual(run().returncode, 0)
            original = target.read_text()
            self.assertIn("Server1.Password=provider-fixture", original)
            source.write_text("ControlPassword=fixture\nCertCheck=no\n")
            result = run()
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("fixture", result.stderr)
            self.assertEqual(target.read_text(), original)
