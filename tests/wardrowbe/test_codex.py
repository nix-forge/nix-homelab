import asyncio
import base64
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient
from notification_process import run as run_command
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "adapter", ROOT / "modules/services/scripts/wardrowbe_codex.py"
)
assert SPEC is not None
assert SPEC.loader is not None
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)

FAKE = "#!@python@\n" + (
    Path(__file__).with_name("fixtures") / "codex_command.py"
).read_text(encoding="utf-8")


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.home = Path(self.directory.name)
        self.fake = self.home / "fake-codex"
        self.fake.write_text(FAKE.replace("@python@", sys.executable))
        self.fake.chmod(0o700)
        self.api_key = "public-fixture-token-with-sufficient-length"
        self.api_key_file = self.home / "api-key"
        self.api_key_file.write_text(self.api_key)
        os.environ["CODEX_API_KEY_FILE"] = str(self.api_key_file)
        self.backend = adapter.Adapter(
            str(self.fake), self.home, ["fixture-model"], timeout=2
        )
        self.client = TestClient(adapter.create_app(self.backend))
        self.client.headers["Authorization"] = f"Bearer {self.api_key}"
        self.request: dict[str, Any] = {
            "model": "fixture-model",
            "messages": [{"role": "user", "content": "outfit"}],
        }

    def tearDown(self):
        self.client.close()
        os.environ.pop("CODEX_API_KEY_FILE", None)
        self.directory.cleanup()

    def test_inference_requires_private_token(self):
        self.login()
        self.assertEqual(
            self.client.get("/v1/models", headers={"Authorization": ""}).status_code,
            401,
        )
        self.assertEqual(
            self.client.post(
                "/v1/chat/completions",
                json=self.request,
                headers={"Authorization": "Bearer invalid"},
            ).status_code,
            401,
        )

    def test_runtime_key_is_private_and_stable_across_restart(self):
        self.api_key_file.unlink()
        adapter.prepare_api_key()
        first = self.api_key_file.read_text()
        self.assertGreaterEqual(len(first.strip()), 48)
        self.assertEqual(self.api_key_file.stat().st_mode & 0o777, 0o640)
        adapter.prepare_api_key()
        self.assertEqual(self.api_key_file.read_text(), first)

    def login(self):
        (self.home / "auth.json").write_text("public fixture")

    def test_login_required(self):
        self.assertEqual(self.client.get("/v1/models").status_code, 503)
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=self.request).status_code, 503
        )

    def test_models_and_completion(self):
        self.login()
        self.assertEqual(
            self.client.get("/v1/models").json()["data"][1]["id"], "fixture-model"
        )
        os.environ["OPENAI_API_KEY"] = "public-secret-fixture"
        os.environ["CODEX_API_KEY"] = "public-secret-fixture"
        try:
            result = self.client.post("/v1/chat/completions", json=self.request)
        finally:
            os.environ.pop("OPENAI_API_KEY")
            os.environ.pop("CODEX_API_KEY")
        self.assertEqual(result.status_code, 200, result.text)
        self.assertIn(
            "fixture outfit", result.json()["choices"][0]["message"]["content"]
        )

    def test_rejects_models_tools_urls_and_invalid_images(self):
        self.login()
        for extra in (
            {"model": "unknown"},
            {"stream": True},
            {"tools": [{}]},
            {"messages": [{"role": "tool", "content": "x"}]},
            {
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {"url": "https://example.org/image"},
                            }
                        ],
                    }
                ]
            },
            {
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": "data:image/png;base64,aW52YWxpZA=="
                                },
                            }
                        ],
                    }
                ]
            },
        ):
            with self.subTest(extra=extra):
                self.assertEqual(
                    self.client.post(
                        "/v1/chat/completions", json=self.request | extra
                    ).status_code,
                    400,
                )

    def test_embedded_image(self):
        self.login()
        stream = io.BytesIO()
        Image.new("RGB", (8, 8)).save(stream, "PNG")
        url = "data:image/png;base64," + base64.b64encode(stream.getvalue()).decode()
        self.request["messages"][0]["content"] = [
            {"type": "text", "text": "photo"},
            {"type": "image_url", "image_url": {"url": url}},
        ]
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=self.request).status_code, 200
        )

    def test_timeout(self):
        self.login()
        self.backend.timeout = 0.1
        self.request["messages"][0]["content"] = "timeout-fixture"
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=self.request).status_code, 504
        )

    def test_private_provider_errors(self):
        self.login()
        self.request["messages"][0]["content"] = "failure-fixture"
        result = self.client.post("/v1/chat/completions", json=self.request)
        self.assertEqual(result.status_code, 502)
        self.assertNotIn("PRIVATE", result.text)

    def test_invalid_and_oversized_requests(self):
        self.login()
        self.assertEqual(
            self.client.post("/v1/chat/completions", content=b"[").status_code, 400
        )
        self.request["messages"][0]["content"] = "x" * (adapter.MAX_TEXT + 1)
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=self.request).status_code, 413
        )
        self.assertEqual(
            self.client.post(
                "/v1/chat/completions", content=b"x" * (adapter.MAX_BODY + 1)
            ).status_code,
            413,
        )

    def test_busy_and_catalog_rejection(self):
        self.login()
        self.backend.slots = asyncio.Semaphore(0)
        result = self.client.post("/v1/chat/completions", json=self.request)
        self.assertEqual(result.status_code, 429)
        self.backend.slots = asyncio.Semaphore(1)
        self.backend.models = ["missing-from-catalog"]
        self.request["model"] = "missing-from-catalog"
        result = self.client.post("/v1/chat/completions", json=self.request)
        self.assertEqual(result.status_code, 503)
        self.assertIn("No visible Codex models", result.text)

    def test_automatic_selection_and_discovery_without_allowlist(self):
        self.login()
        self.backend.models = []
        body = {**self.request, "model": "auto-value"}
        response = self.client.post("/v1/chat/completions", json=body)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["model"], "fixture-model")
        self.assertIn("selection", self.client.get("/v1/models").json())

    def test_text_only_catalog_and_auth_change_refresh(self):
        self.login()
        self.backend.models = []
        self.fake.write_text(
            self.fake.read_text().replace(
                '"slug": "fixture-model",',
                '"slug": "fixture-model", "input_modalities": ["text"],',
            )
        )
        info = self.client.get("/v1/models").json()
        self.assertIsNone(info["selection"]["vision_model"])
        result = self.client.post(
            "/v1/chat/completions", json={**self.request, "model": "auto-value"}
        )
        self.assertEqual(result.status_code, 200, result.text)
        image = io.BytesIO()
        Image.new("RGB", (1, 1), "red").save(image, format="PNG")
        content = [
            {
                "type": "image_url",
                "image_url": {
                    "url": "data:image/png;base64,"
                    + base64.b64encode(image.getvalue()).decode()
                },
            }
        ]
        body = {
            "model": "auto-value",
            "messages": [{"role": "user", "content": content}],
        }
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=body).status_code, 503
        )
        body["model"] = "fixture-model"
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=body).status_code, 400
        )
        self.fake.write_text(
            self.fake.read_text().replace('"fixture-model"', '"other-account-model"')
        )
        (self.home / "auth.json").write_text("different public fixture")
        info = self.client.get("/v1/models").json()
        self.assertEqual(info["selection"]["text_model"], "other-account-model")

    def test_value_policy_uses_metadata_and_modalities(self):
        entries = [
            {
                "slug": "new-capable",
                "description": "Frontier intelligence",
                "priority": 1,
                "input_modalities": ["text", "image"],
            },
            {
                "slug": "new-balanced",
                "description": "Workhorse for everyday work",
                "priority": 2,
                "input_modalities": ["text", "image"],
            },
            {
                "slug": "new-efficient",
                "description": "Fast and affordable",
                "priority": 3,
                "input_modalities": ["text", "image"],
            },
            {
                "slug": "old-efficient",
                "description": "Older efficient model",
                "priority": 0,
                "input_modalities": ["text", "image"],
            },
            {
                "slug": "special",
                "description": "Efficient balanced",
                "priority": 0,
                "model_specialty": "special",
                "input_modalities": ["text", "image"],
            },
        ]
        self.assertEqual(adapter.value_model(entries, "text"), "new-balanced")
        self.assertEqual(adapter.value_model(entries, "image"), "new-efficient")
        entries[2]["input_modalities"] = ["text"]
        self.assertEqual(adapter.value_model(entries, "image"), "new-balanced")
        newer = {
            "slug": "future-efficient",
            "description": "Efficient",
            "priority": 1,
            "input_modalities": ["text", "image"],
        }
        self.assertEqual(
            adapter.value_model([*entries, newer], "image"), "future-efficient"
        )
        self.assertEqual(
            adapter.visible_models(
                {"models": [*entries, {"slug": "hidden", "visibility": "hide"}]}, []
            ),
            entries,
        )
        self.assertEqual(
            adapter.visible_models({"models": entries}, ["new-balanced"]), [entries[1]]
        )

    def test_cached_catalog_expires_and_removed_models_are_rejected(self):
        self.login()
        self.backend.models = []
        first = self.client.get("/v1/models").json()
        self.assertIn("fixture-model", [entry["id"] for entry in first["data"]])
        self.fake.write_text(
            self.fake.read_text().replace('"fixture-model"', '"future-model"')
        )
        self.backend.catalog_expires = 0
        refreshed = self.client.get("/v1/models").json()
        self.assertIn("future-model", [entry["id"] for entry in refreshed["data"]])
        self.assertEqual(
            self.client.post("/v1/chat/completions", json=self.request).status_code, 400
        )

    def test_malformed_catalog_fails_closed(self):
        for raw in (
            b"invalid",
            b'{"models": {}}',
            b'{"models": [{"slug": "fixture-model"}, 42]}',
        ):
            with (
                self.subTest(raw=raw),
                self.assertRaises(adapter.HTTPException) as caught,
            ):
                adapter.sanitize_catalog(raw, "fixture-model", self.home)
            self.assertEqual(caught.exception.status_code, 502)

    @unittest.skipUnless(
        os.environ.get("CODEX_TEST_EXECUTABLE"),
        "Nix check supplies the real packaged CLI",
    )
    def test_packaged_cli_accepts_catalog_and_configuration(self):
        executable = os.environ["CODEX_TEST_EXECUTABLE"]
        environment = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "CODEX_HOME": str(self.home),
        }
        raw = run_command(
            [executable, "debug", "models", "--bundled"],
            env=environment,
            stderr=subprocess.DEVNULL,
            timeout=30,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        model = json.loads(raw)["models"][0]["slug"]
        catalog = adapter.sanitize_catalog(raw, model, self.home)
        (self.home / "instructions.txt").write_text(
            "Answer the wardrobe request directly without tools."
        )
        command = adapter.make_command(executable, model, self.home, catalog, [])
        configs = []
        for index, arg in enumerate(command):
            if arg == "-c":
                configs.extend(["-c", command[index + 1]])
        result = run_command(
            [
                executable,
                "debug",
                "prompt-input",
                "-c",
                "model=" + json.dumps(model),
                *configs,
                "Public wardrobe fixture",
            ],
            cwd=self.home,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())


LOGIN_FAKE = "#!@python@\n" + (
    Path(__file__).with_name("fixtures") / "codex_login.py"
).read_text(encoding="utf-8")


class BrowserLoginTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.home = Path(self.directory.name)
        fake = self.home / "fake-codex"
        fake.write_text(LOGIN_FAKE.replace("@python@", sys.executable))
        fake.chmod(0o700)
        self.adapter = adapter.Adapter(str(fake), self.home, ["fixture-model"])
        self.api_key_file = self.home / "api-key"
        self.api_key_file.write_text("public-fixture-token-with-sufficient-length")
        os.environ["CODEX_API_KEY_FILE"] = str(self.api_key_file)
        self.login = adapter.BrowserLogin(self.adapter, login_timeout=1)
        self.user = "00000000-0000-4000-8000-000000000001"

    async def asyncTearDown(self):
        await self.login.close()
        os.environ.pop("CODEX_API_KEY_FILE", None)
        self.directory.cleanup()

    async def test_browser_login_status_disconnect_and_private_fields(self):
        self.assertFalse((await self.login.status(self.user))["connected"])
        pending = await self.login.start(self.user)
        self.assertEqual(pending["method"], "browser")
        self.assertTrue(pending["authUrl"].startswith("https://auth.openai.com/"))
        self.assertNotIn("userCode", pending)
        self.assertNotIn("PRIVATE", json.dumps(pending))
        self.assertEqual((await self.login.status(self.user))["pending"], pending)
        self.assertEqual(await self.login.start(self.user), pending)
        (self.home / "approve").touch()
        result = await self.login.status(self.user)
        self.assertTrue(result["connected"])
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertGreater(self.adapter.catalog_expires, 0)
        await self.login.disconnect(self.user)
        self.assertEqual(self.adapter.catalog_expires, 0)
        self.assertFalse(self.adapter.ready())
        self.assertIsNone((await self.login.status(self.user))["pending"])
        self.assertEqual((self.home / "browser-owner").stat().st_mode & 0o777, 0o600)

    async def test_explicit_device_login_and_invalid_method(self):
        pending = await self.login.start(self.user, "device")
        self.assertEqual(pending["method"], "device")
        self.assertEqual(pending["userCode"], "TEST-CODE")
        self.assertNotIn("authUrl", pending)
        self.assertNotIn("PRIVATE", json.dumps(pending))
        await self.login.disconnect(self.user)
        with self.assertRaises(adapter.HTTPException):
            await self.login.start(self.user, "invalid")
        await self.login.close()
        with TestClient(adapter.create_control_app(self.login)) as client:
            self.assertEqual(
                client.post(
                    "/login", params={"user": self.user, "method": "invalid"}
                ).status_code,
                422,
            )

    async def test_owner_binding_and_invalid_identity(self):
        await self.login.start(self.user)
        for user in ("00000000-0000-4000-8000-000000000002", "invalid"):
            for method in (self.login.start, self.login.status, self.login.disconnect):
                with self.assertRaises(adapter.HTTPException) as caught:
                    await method(user)
                self.assertIn(caught.exception.status_code, (400, 403))

    async def test_expiry_cancellation_and_restart(self):
        await self.login.start(self.user)
        await asyncio.sleep(1.1)
        result = await self.login.status(self.user)
        self.assertIsNone(result["pending"])
        self.assertIn("expired", result["error"])
        await self.login.start(self.user)
        await self.login.close()
        result = await self.login.status(self.user)
        self.assertIsNone(result["pending"])

    async def test_provider_errors_and_urls_are_not_forwarded(self):
        for fixture in ("fail", "bad-url", "bad-callback", "bad-userinfo", "bad-port"):
            (self.home / fixture).touch()
            with self.assertRaises(adapter.HTTPException) as caught:
                await self.login.start(self.user)
            self.assertNotIn("PRIVATE", caught.exception.detail)
            self.assertNotIn("evil", caught.exception.detail)
            (self.home / fixture).unlink()

    async def test_management_not_exposed_on_inference_app(self):
        with TestClient(adapter.create_app(self.adapter)) as client:
            self.assertEqual(
                client.post("/login", params={"user": self.user}).status_code, 404
            )
            self.assertEqual(
                client.get("/status", params={"user": self.user}).status_code, 404
            )

    @unittest.skipUnless(
        os.environ.get("CODEX_TEST_EXECUTABLE"), "Nix supplies real CLI"
    )
    async def test_packaged_app_server_handshake_without_authentication(self):
        await self.login.close()
        self.adapter.executable = os.environ["CODEX_TEST_EXECUTABLE"]
        result = await self.login.status(self.user)
        self.assertFalse(result["connected"])
        self.assertIsNone(result["pending"])
        pending = await self.login.start(self.user)
        self.assertEqual(pending["method"], "browser")
        self.assertTrue(pending["authUrl"].startswith("https://auth.openai.com/"))
        await self.login.disconnect(self.user)

    async def test_reader_failure_recovers_without_service_restart(self):
        await self.login.status(self.user)
        original = self.login.process
        (self.home / "malformed").touch()
        with self.assertRaises(adapter.HTTPException):
            await self.login.status(self.user)
        (self.home / "malformed").unlink()
        result = await self.login.status(self.user)
        self.assertFalse(result["connected"])
        self.assertIsNot(original, self.login.process)
