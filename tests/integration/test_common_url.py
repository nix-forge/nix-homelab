"""Malformed API endpoints fail before an integration client is created."""

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/common.py"
spec = importlib.util.spec_from_file_location("integration_common", SCRIPT)
assert spec is not None
assert spec.loader is not None
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


class URLPolicyTest(unittest.TestCase):
    def test_malformed_authority_and_control_characters_are_rejected(self):
        for value in (
            "https://[broken",
            "https://example.test:99999",
            "http://localhost\n.evil.test",
            " http://localhost",
        ):
            with (
                self.subTest(value=value),
                self.assertRaises(common.ConfigurationError),
            ):
                common.validate_url(value)

    def test_loopback_http_and_remote_https_are_allowed(self):
        self.assertEqual(
            common.validate_url("http://127.0.0.1:8080/"), "http://127.0.0.1:8080"
        )
        self.assertEqual(
            common.validate_url("https://example.test/"), "https://example.test"
        )
