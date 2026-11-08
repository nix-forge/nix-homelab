"""Managed website credentials preserve application settings and verified state."""

from __future__ import annotations

import json
import os
import runpy
import tempfile
import unittest
import urllib.error
from email.message import Message
from pathlib import Path
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/integration/web_auth.py"
MODULE = runpy.run_path(str(SCRIPT))


class WebAuthTests(unittest.TestCase):
    """Exercise native API payloads and private migration markers."""

    def test_read_waits_for_listener_without_replaying_writes(self) -> None:
        """Connection refusal during startup is retried only for safe reads."""
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.status = 200
        response.headers = {}
        response.read.return_value = b'{"id": 1}'
        opener = Mock()
        opener.open.side_effect = [
            urllib.error.URLError(ConnectionRefusedError()),
            response,
        ]
        environment = {
            "HTTP_TIMEOUT_SECONDS": "10",
            "HTTP_READ_RETRY_BUDGET_SECONDS": "60",
            "HTTP_READ_ATTEMPTS": "10",
        }
        with (
            patch.dict(os.environ, environment),
            patch("urllib.request.build_opener", return_value=opener),
        ):
            self.assertEqual(
                MODULE["_request"]("http://127.0.0.1:8989", "/api/v3/config/host")[2],
                {"id": 1},
            )
        self.assertEqual(opener.open.call_count, 2)

    def test_auth_failure_and_write_failure_are_not_retried(self) -> None:
        """Bad credentials and mutating API requests fail after one attempt."""
        for method, status in (("GET", 401), ("PUT", 503)):
            with self.subTest(method=method):
                opener = Mock()
                opener.open.side_effect = urllib.error.HTTPError(
                    "http://127.0.0.1:8989", status, "fixture", Message(), None
                )
                with (
                    patch.dict(
                        os.environ,
                        {
                            "HTTP_TIMEOUT_SECONDS": "10",
                            "HTTP_READ_RETRY_BUDGET_SECONDS": "60",
                            "HTTP_READ_ATTEMPTS": "10",
                        },
                    ),
                    patch("urllib.request.build_opener", return_value=opener),
                    self.assertRaises(MODULE["ProvisionError"]),
                ):
                    MODULE["_request"](
                        "http://127.0.0.1:8989", "/api/v3/config/host", method=method
                    )
                opener.open.assert_called_once()

    def test_read_deadline_caps_requests_and_backoff(self) -> None:
        """A slow failed read cannot extend the total startup deadline."""
        opener = Mock()
        opener.open.side_effect = urllib.error.URLError(ConnectionRefusedError())
        clock = Mock(side_effect=[100, 100, 100.8, 101])
        delay = Mock()
        with (
            patch.dict(
                os.environ,
                {
                    "HTTP_TIMEOUT_SECONDS": "10",
                    "HTTP_READ_RETRY_BUDGET_SECONDS": "1",
                    "HTTP_READ_ATTEMPTS": "10",
                },
            ),
            patch("urllib.request.build_opener", return_value=opener),
            patch.dict(
                MODULE["_open"].__globals__,
                {
                    "time": Mock(monotonic=clock, sleep=delay),
                },
            ),
            self.assertRaises(MODULE["ProvisionError"]),
        ):
            MODULE["_request"]("http://127.0.0.1:8989", "/api/v3/config/host")
        self.assertEqual(opener.open.call_count, 1)
        self.assertEqual(opener.open.call_args.kwargs["timeout"], 1)
        self.assertAlmostEqual(delay.call_args.args[0], 0.2)

    def test_arr_preserves_resource_and_replaces_hash_with_plaintext(self) -> None:
        """Only credentials change and the existing host resource ID is used."""
        current = {
            "id": 7,
            "authenticationMethod": "forms",
            "authenticationRequired": "enabled",
            "password": "old-hash",
            "port": 8989,
            "custom": {"preserve": True},
        }
        request = Mock(
            side_effect=[
                (200, {}, current),
                (200, {}, {}),
                (302, {"Set-Cookie": "fixture"}, None),
            ]
        )
        with patch.dict(MODULE["_configure"].__globals__, {"_request": request}):
            MODULE["_configure"](
                "http://127.0.0.1:8989",
                "v3",
                "admin",
                "fixture-password",
                "fixture-key",
            )
        update = request.call_args_list[1]
        self.assertEqual(update.args[1], "/api/v3/config/host/7")
        desired = update.args[4]
        self.assertEqual(desired["password"], "fixture-password")
        self.assertEqual(desired["passwordConfirmation"], "fixture-password")
        self.assertEqual(
            desired["authenticationRequired"], current["authenticationRequired"]
        )
        self.assertEqual(desired["custom"], current["custom"])
        self.assertEqual(current["password"], "old-hash")

    def test_arr_bootstraps_only_empty_initial_auth(self) -> None:
        """A fresh service gets Forms auth and sealed credentials in one update."""
        current = {
            "id": 1,
            "authenticationMethod": "none",
            "authenticationRequired": "enabled",
            "username": "",
            "password": "",
            "port": 8989,
        }
        request = Mock(
            side_effect=[
                (200, {}, current),
                (200, {}, {}),
                (302, {"Set-Cookie": "fixture"}, None),
            ]
        )
        with patch.dict(MODULE["_configure"].__globals__, {"_request": request}):
            MODULE["_configure"](
                "http://127.0.0.1:8989",
                "v3",
                "admin",
                "fixture-password",
                "fixture-key",
            )
        desired = request.call_args_list[1].args[4]
        self.assertEqual(desired["authenticationMethod"], "forms")
        self.assertEqual(desired["authenticationRequired"], "enabled")
        self.assertEqual(desired["port"], 8989)
        self.assertEqual(desired["username"], "admin")

    def test_arr_refuses_initial_auth_with_existing_account(self) -> None:
        """An unexpected existing account must not be overwritten as bootstrap."""
        request = Mock(
            return_value=(
                200,
                {},
                {"id": 1, "authenticationMethod": "none", "username": "someone"},
            )
        )
        with (
            patch.dict(MODULE["_configure"].__globals__, {"_request": request}),
            self.assertRaises(MODULE["ProvisionError"]),
        ):
            MODULE["_configure"](
                "http://127.0.0.1:8989",
                "v3",
                "admin",
                "fixture-password",
                "fixture-key",
            )
        request.assert_called_once()

    def test_bazarr_partial_update_preserves_provider_settings(self) -> None:
        """Bazarr receives only native auth fields and login is verified."""
        request = Mock(
            side_effect=[
                (200, {}, {"auth": {"type": "form"}, "providers": ["fixture"]}),
                (204, {}, None),
                (204, {}, None),
            ]
        )
        with patch.dict(MODULE["_configure"].__globals__, {"_request": request}):
            MODULE["_configure"](
                "http://127.0.0.1:6767",
                "v1",
                "admin",
                "fixture-password",
                "fixture-key",
                bazarr=True,
            )
        self.assertEqual(
            request.call_args_list[1].args[4],
            {
                "settings-auth-username": "admin",
                "settings-auth-password": "fixture-password",
            },
        )
        self.assertEqual(request.call_args_list[2].args[1], "/api/system/account")

    def test_bazarr_bootstraps_only_empty_initial_auth(self) -> None:
        """A fresh Bazarr instance enables form login with sealed credentials."""
        request = Mock(
            side_effect=[
                (200, {}, {"auth": {"type": None, "username": "", "password": ""}}),
                (204, {}, None),
                (204, {}, None),
            ]
        )
        with patch.dict(MODULE["_configure"].__globals__, {"_request": request}):
            MODULE["_configure"](
                "http://127.0.0.1:6767",
                "v1",
                "admin",
                "fixture-password",
                "fixture-key",
                bazarr=True,
            )
        self.assertEqual(
            request.call_args_list[1].args[4],
            {
                "settings-auth-type": "form",
                "settings-auth-username": "admin",
                "settings-auth-password": "fixture-password",
            },
        )

    def test_failed_login_does_not_commit_marker(self) -> None:
        """Failed native verification leaves credentials retryable without secret errors."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in (
                ("username", "admin"),
                ("password", "fixture-password"),
                ("api-key", "fixture-key"),
            ):
                (root / name).write_text(value, encoding="utf-8")
            configure = Mock(side_effect=MODULE["ProvisionError"])
            environment = {
                **os.environ,
                "CREDENTIALS_DIRECTORY": directory,
                "STATE_DIRECTORY": directory,
            }
            with (
                patch.dict(
                    MODULE["main"].__globals__,
                    {"_configure": configure, "_verify_current": Mock()},
                ),
                patch.dict(os.environ, environment),
                patch(
                    "sys.argv",
                    [str(SCRIPT), "sonarr", "sonarr", "http://127.0.0.1:8989", "v3"],
                ),
                self.assertRaises(MODULE["ProvisionError"]) as caught,
            ):
                MODULE["main"]()
            self.assertNotIn("fixture-password", str(caught.exception))
            self.assertFalse((root / "sonarr.fingerprint").exists())
            configure.assert_called_once()

    def test_current_login_verification_changes_no_configuration(self) -> None:
        """Matching fingerprints use native login without writing host settings."""
        request = Mock(
            side_effect=[
                (200, {}, {"authenticationMethod": "forms"}),
                (302, {"Set-Cookie": "fixture"}, None),
            ]
        )
        with patch.dict(MODULE["_verify_current"].__globals__, {"_request": request}):
            MODULE["_verify_current"](
                "http://127.0.0.1:8989",
                "v3",
                "admin",
                "fixture-password",
                "fixture-key",
                bazarr=False,
            )
        self.assertEqual(request.call_args_list[0].args[1], "/api/v3/config/host")
        self.assertEqual(request.call_args_list[1].args[1], "/login")
        self.assertEqual(request.call_count, 2)

    def test_arr_basic_mode_is_refused_before_configuration_write(self) -> None:
        """Unsupported Basic mode cannot masquerade as a verified loopback login."""
        request = Mock(
            return_value=(200, {}, {"id": 7, "authenticationMethod": "basic"})
        )
        with (
            patch.dict(MODULE["_configure"].__globals__, {"_request": request}),
            self.assertRaises(MODULE["ProvisionError"]),
        ):
            MODULE["_configure"](
                "http://127.0.0.1:8989",
                "v3",
                "admin",
                "fixture-password",
                "fixture-key",
            )
        request.assert_called_once()

    def test_matching_marker_with_restored_database_repairs_login(self) -> None:
        """A database restore cannot make a matching marker hide stale credentials."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in (
                ("username", "admin"),
                ("password", "fixture-password"),
                ("api-key", "fixture-key"),
            ):
                (root / name).write_text(value, encoding="utf-8")
            configure = Mock()
            verify = Mock(side_effect=MODULE["ProvisionError"])
            environment = {
                **os.environ,
                "CREDENTIALS_DIRECTORY": directory,
                "STATE_DIRECTORY": directory,
            }
            with (
                patch.dict(
                    MODULE["main"].__globals__,
                    {"_configure": configure, "_verify_current": verify},
                ),
                patch.dict(os.environ, environment),
                patch(
                    "sys.argv",
                    [str(SCRIPT), "sonarr", "sonarr", "http://127.0.0.1:8989", "v3"],
                ),
            ):
                MODULE["main"]()
                configure.reset_mock()
                MODULE["main"]()
            verify.assert_called_once()
            configure.assert_called_once()
            self.assertTrue((root / "sonarr.fingerprint").exists())

    def test_verified_marker_is_private_and_prevents_repeat_mutation(self) -> None:
        """Unchanged credentials produce no API writes and store no plaintext."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in (
                ("username", "admin"),
                ("password", "fixture-password"),
                ("api-key", "fixture-key"),
            ):
                (root / name).write_text(value, encoding="utf-8")
            configure = Mock()
            environment = {
                **os.environ,
                "CREDENTIALS_DIRECTORY": directory,
                "STATE_DIRECTORY": directory,
            }
            with (
                patch.dict(
                    MODULE["main"].__globals__,
                    {"_configure": configure, "_verify_current": Mock()},
                ),
                patch.dict(os.environ, environment),
                patch(
                    "sys.argv",
                    [str(SCRIPT), "sonarr", "sonarr", "http://127.0.0.1:8989", "v3"],
                ),
            ):
                MODULE["main"]()
                MODULE["main"]()
            configure.assert_called_once()
            marker = root / "sonarr.fingerprint"
            self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("fixture-password", marker.read_text())
            self.assertNotIn("admin", marker.read_text())
            self.assertRaises(json.JSONDecodeError, json.loads, marker.read_text())

    def test_named_second_instance_uses_its_kind_and_separate_marker(self) -> None:
        """A second Sonarr job retains its own state and the Sonarr API adapter."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for field, value in (
                ("username", "admin"),
                ("password", "fixture-password"),
                ("api-key", "fixture-key"),
            ):
                (root / field).write_text(value, encoding="utf-8")
            configure = Mock()
            environment = {
                **os.environ,
                "CREDENTIALS_DIRECTORY": directory,
                "STATE_DIRECTORY": directory,
            }
            with (
                patch.dict(MODULE["main"].__globals__, {"_configure": configure}),
                patch.dict(os.environ, environment),
                patch(
                    "sys.argv",
                    [
                        str(SCRIPT),
                        "sonarr-anime",
                        "sonarr",
                        "http://127.0.0.1:8990",
                        "v3",
                    ],
                ),
            ):
                MODULE["main"]()
            self.assertTrue((root / "sonarr-anime.fingerprint").exists())
            self.assertFalse((root / "sonarr.fingerprint").exists())
            self.assertFalse(configure.call_args.kwargs["bazarr"])
