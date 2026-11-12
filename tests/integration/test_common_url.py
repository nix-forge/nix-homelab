"""Malformed API endpoints fail before an integration client is created."""

import importlib.util
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

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

    def test_only_explicit_ipv4_link_local_http_exception_is_allowed(self):
        with self.assertRaises(common.ConfigurationError):
            common.validate_url("http://169.254.202.94:8081")
        self.assertEqual(
            common.validate_url(
                "http://169.254.202.94:8081", allow_link_local_http=True
            ),
            "http://169.254.202.94:8081",
        )
        for url in ("http://192.168.1.20:8081", "http://example.test:8081"):
            with self.subTest(url=url), self.assertRaises(common.ConfigurationError):
                common.validate_url(url, allow_link_local_http=True)

    def test_api_error_identifies_method_and_path_without_response_body(self):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def do_POST(self):
                self.send_response(400)
                self.end_headers()
                self.wfile.write(json.dumps({"token": "must-not-leak"}).encode())

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

        client = common.Client(f"http://127.0.0.1:{server.server_port}")
        with self.assertRaisesRegex(
            common.APIError, r"POST /api/v1/settings/network failed with HTTP 400"
        ) as raised:
            client.request("POST", "/api/v1/settings/network", {"enabled": True})
        self.assertNotIn("must-not-leak", str(raised.exception))

    def test_wait_ready_survives_initial_api_unavailability(self):
        client = common.Client("http://127.0.0.1:5055")
        attempts = []

        def request(_method, path, **_kwargs):
            attempts.append(path)
            if len(attempts) == 1:
                raise common.APIUnavailableError("API is not ready")
            return {"ready": True}

        client.request = request
        with patch.object(common, "sleep") as sleep:
            client.wait_ready("/api/v1/status")
        self.assertEqual(attempts, ["/api/v1/status", "/api/v1/status"])
        sleep.assert_called_once_with(2)

    def test_wait_ready_stops_after_deadline(self):
        client = common.Client("http://127.0.0.1:5055")
        attempts = []

        def request(_method, path, **_kwargs):
            attempts.append(path)
            raise common.APIUnavailableError("API is not ready")

        client.request = request
        with (
            patch.object(common, "monotonic", side_effect=[0, 76]),
            self.assertRaises(common.APIUnavailableError),
        ):
            client.wait_ready("/api/v1/status")
        self.assertEqual(attempts, ["/api/v1/status"])
