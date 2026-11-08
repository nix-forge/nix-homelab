"""Private, bounded chat-completion adapter for official Codex OAuth."""

import asyncio
import base64
import binascii
import hmac
import io
import json
import os
import re
import secrets
import signal
import sys
import tempfile
import time
import uuid
from contextlib import asynccontextmanager, contextmanager, suppress
from pathlib import Path
from typing import Literal, override
from urllib.parse import parse_qs, urlsplit

import uvicorn
from fastapi import FastAPI, HTTPException, Request  # ruff: ignore[typing-only-third-party-import] - FastAPI evaluates annotations.
from PIL import Image

MAX_BODY = 20 * 1024 * 1024
MAX_OUTPUT = 1024 * 1024
MAX_IMAGES = 4
MAX_MESSAGES = 64
MAX_PIXELS = 16_000_000
MAX_TEXT = 100_000
MAX_MODELS = 256


def prepare_content(content, directory, images):
    parts = [{"type": "text", "text": content}] if isinstance(content, str) else content
    if not isinstance(parts, list):
        raise HTTPException(400, "Invalid message content")
    texts, total = [], 0
    for part in parts:
        if not isinstance(part, dict):
            raise HTTPException(400, "Invalid content part")
        if part.get("type") == "text" and isinstance(part.get("text"), str):
            total += len(part["text"])
            texts.append(part["text"])
        elif part.get("type") == "image_url":
            images.append(save_image(part, directory, len(images)))
            texts.append(f"[Attached image {len(images)}]")
        else:
            raise HTTPException(400, "Unsupported content part")
    return texts, total


def save_image(part, directory, index):
    image_url = part.get("image_url")
    url = image_url.get("url", "") if isinstance(image_url, dict) else ""
    if index >= MAX_IMAGES or not isinstance(url, str):
        raise HTTPException(400, "Invalid image input")
    prefix, separator, encoded = url.partition(",")
    if not separator or prefix not in {
        "data:image/jpeg;base64",
        "data:image/png;base64",
        "data:image/webp;base64",
    }:
        raise HTTPException(
            400, "Only embedded JPEG, PNG and WebP images are supported"
        )
    try:
        raw = base64.b64decode(encoded, validate=True)
        image_format = validate_image(raw)
    except (ValueError, binascii.Error, OSError, Image.DecompressionBombError) as error:
        raise HTTPException(400, "Invalid or oversized image") from error
    suffix = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}.get(image_format)
    if suffix is None:
        raise HTTPException(400, "Unsupported image encoding")
    path = directory / f"image-{index}.{suffix}"
    path.write_bytes(raw)
    return path


def validate_image(raw):
    with Image.open(io.BytesIO(raw)) as image:
        if image.width * image.height > MAX_PIXELS:
            raise ValueError("Image too large")
        image.verify()
        return image.format


def catalog_slugs(entries):
    if not isinstance(entries, list):
        raise TypeError("Invalid catalog list")
    return [entry["slug"] for entry in entries]


def sanitize_catalog(raw, model, directory):
    try:
        catalog = json.loads(raw)
        entries = catalog["models"]
        slugs = catalog_slugs(entries)
        found = model in slugs
    except (ValueError, KeyError, TypeError) as error:
        raise HTTPException(502, "Invalid Codex model catalog") from error
    if not found:
        raise HTTPException(400, "Model is unavailable in this Codex CLI catalog")
    for entry in entries:
        entry.update(
            shell_type="disabled",
            apply_patch_tool_type=None,
            experimental_supported_tools=[],
            supports_search_tool=False,
        )
    path = directory / "models.json"
    path.write_text(json.dumps(catalog))
    return path


async def fetch_catalog(executable, home):
    catalog_process = await asyncio.create_subprocess_exec(
        executable,
        "debug",
        "models",
        # Refresh through the official CLI's account-aware catalog. The bundled
        # snapshot can predate models already available to this signed-in user.
        env={
            "CODEX_HOME": str(home),
            "HOME": str(home),
            "PATH": os.environ.get("PATH", ""),
        },
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        catalog_raw, _ = await asyncio.wait_for(catalog_process.communicate(), 10)
    except (TimeoutError, asyncio.CancelledError) as error:
        os.killpg(catalog_process.pid, signal.SIGKILL)
        await catalog_process.wait()
        if isinstance(error, asyncio.CancelledError):
            raise
        raise HTTPException(504, "Codex catalog inspection timed out") from error
    if catalog_process.returncode:
        raise HTTPException(502, "Codex catalog inspection failed")
    try:
        catalog = parse_catalog(catalog_raw)
    except (ValueError, KeyError, TypeError) as error:
        raise HTTPException(502, "Invalid Codex model catalog") from error
    return catalog


def parse_catalog(raw):
    catalog = json.loads(raw)
    entries = catalog["models"]
    if not isinstance(entries, list) or not entries or len(entries) > MAX_MODELS:
        raise ValueError("Invalid model collection")
    for entry in entries:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("slug"), str)
            or not re.fullmatch(r"[A-Za-z0-9_.:-]+", entry["slug"])
        ):
            raise ValueError("Invalid model identifier")
        modalities = entry.get("input_modalities", ["text", "image"])
        if not isinstance(modalities, list) or not all(
            isinstance(value, str) for value in modalities
        ):
            raise ValueError("Invalid input modalities")
    if len({entry["slug"] for entry in entries}) != len(entries):
        raise ValueError("Duplicate model identifiers")
    return catalog


async def load_catalog(executable, home, model, directory):
    catalog = await fetch_catalog(executable, home)
    return sanitize_catalog(json.dumps(catalog), model, directory)


def visible_models(catalog, allowed):
    return [
        entry
        for entry in catalog["models"]
        if entry.get("visibility", "list") == "list"
        and "text" in entry.get("input_modalities", ["text", "image"])
        and (not allowed or entry["slug"] in allowed)
    ]


def value_model(entries, modality):
    compatible = [
        entry
        for entry in entries
        if modality in entry.get("input_modalities", ["text", "image"])
    ]
    if not compatible:
        raise HTTPException(503, "No compatible Codex model is available")

    def rank(entry):
        description = str(entry.get("description", "")).lower()
        old = bool(entry.get("upgrade")) or any(
            word in description for word in ("older", "legacy", "previous")
        )
        specialty = bool(entry.get("model_specialty"))
        efficient = any(
            word in description
            for word in (
                "affordable",
                "efficient",
                "cost-sensitive",
                "economical",
                "high-volume",
            )
        )
        balanced = any(
            word in description
            for word in ("balanced", "balance", "workhorse", "everyday")
        )
        suitable = balanced if modality == "text" else efficient
        alternative = efficient if modality == "text" else balanced
        priority = entry.get("priority", 1000)
        if not isinstance(priority, (int, float)):
            priority = 1000
        return (
            specialty,
            old,
            0 if suitable else 1 if alternative else 2,
            priority,
            entry["slug"],
        )

    return min(compatible, key=rank)["slug"]


def make_command(executable, model, directory, catalog_path, images):
    output = directory / "response.txt"
    instructions = directory / "instructions.txt"
    command = [
        executable,
        "exec",
        "--strict-config",
        "--ignore-user-config",
        "--ignore-rules",
        "--ephemeral",
        "--skip-git-repo-check",
        "--sandbox",
        "read-only",
        "--model",
        model,
        "--output-last-message",
        str(output),
    ]
    settings = {
        "model_catalog_json": str(catalog_path),
        "model_provider": "openai",
        "mcp_servers": {},
        "forced_login_method": "chatgpt",
        "cli_auth_credentials_store": "file",
        "web_search": "disabled",
        "features.shell_tool": False,
        "features.unified_exec": False,
        "features.multi_agent": False,
        "features.apps": False,
        "features.hooks": False,
        "features.view_image": False,
        "features.plugins": False,
        "features.image_generation": False,
        "features.memories": False,
        "features.request_permissions_tool": False,
        "history.persistence": "none",
        "include_environment_context": False,
        "analytics.enabled": False,
        "feedback.enabled": False,
        "otel.log_user_prompt": False,
        "model_instructions_file": str(instructions),
    }
    for key, value in settings.items():
        command.extend(["-c", f"{key}={json.dumps(value)}"])
    for path in images:
        command.extend(["--image", str(path)])
    command.append("-")
    return command


class Adapter:
    def __init__(self, executable, home, models, timeout=270, concurrency=1):
        self.executable = executable
        self.home = Path(home)
        self.models = models
        self.timeout = timeout
        self.slots = asyncio.Semaphore(concurrency)
        self.catalog_lock = asyncio.Lock()
        self.catalog = None
        self.catalog_expires = 0.0
        self.refreshed_at = 0
        self.auth_stamp = None

    async def information(self):
        async with self.catalog_lock:
            auth_file = self.home / "auth.json"
            stamp = auth_file.stat().st_mtime_ns if auth_file.is_file() else None
            if (
                self.catalog is None
                or time.monotonic() >= self.catalog_expires
                or stamp != self.auth_stamp
            ):
                self.catalog = await fetch_catalog(self.executable, self.home)
                self.auth_stamp = stamp
                self.catalog_expires = time.monotonic() + 300
                self.refreshed_at = int(time.time())
            entries = visible_models(self.catalog, self.models)
            if not entries:
                raise HTTPException(503, "No visible Codex models are available")
            image_entries = [
                entry
                for entry in entries
                if "image" in entry.get("input_modalities", ["text", "image"])
            ]
            selection = {
                "text_model": value_model(entries, "text"),
                "vision_model": value_model(image_entries, "image")
                if image_entries
                else None,
                "reason": "Uses current provider descriptions and catalog order: balanced models for outfits, efficient image models for tagging. Exact subscription costs are not exposed by Codex.",
                "refreshed_at": self.refreshed_at,
            }
            return {
                "models": ["auto-value", *(entry["slug"] for entry in entries)],
                "selection": selection,
                "text_models": ["auto-value", *(entry["slug"] for entry in entries)],
                "vision_models": [
                    "auto-value",
                    *(entry["slug"] for entry in image_entries),
                ]
                if image_entries
                else [],
            }

    def invalidate_catalog(self):
        self.catalog_expires = 0.0

    def ready(self):
        return (self.home / "auth.json").is_file()

    def prepare(self, body, directory):
        model = body.get("model")
        if self.models and model not in self.models and model != "auto-value":
            raise HTTPException(
                400, "Model is not in the administrator's allowedModels"
            )
        if body.get("stream") or body.get("tools") or body.get("functions"):
            raise HTTPException(400, "Streaming and tools are not supported")
        messages = body.get("messages")
        if not isinstance(messages, list) or not 1 <= len(messages) <= MAX_MESSAGES:
            raise HTTPException(400, "Expected 1 to 64 messages")
        prompt, images, total = [], [], 0
        for message in messages:
            if not isinstance(message, dict) or message.get("role") not in {
                "system",
                "developer",
                "user",
                "assistant",
            }:
                raise HTTPException(400, "Unsupported message role")
            texts, count = prepare_content(message.get("content"), directory, images)
            total += count
            if total > MAX_TEXT:
                raise HTTPException(413, "Prompt is too large")
            prompt.append({"role": message["role"], "content": "\n".join(texts)})
        return model, json.dumps(prompt), images

    async def prepare_model(self, body, directory):
        model, prompt, images = self.prepare(body, directory)
        info = await self.information()
        if model not in info["models"]:
            raise HTTPException(
                400, "Model is unavailable in the current Codex catalog"
            )
        if model == "auto-value":
            model = info["selection"]["vision_model" if images else "text_model"]
        if model is None:
            raise HTTPException(503, "No compatible image model is available")
        catalog = self.catalog
        if catalog is None:
            raise HTTPException(503, "Model catalog is unavailable")
        entry = next(entry for entry in catalog["models"] if entry["slug"] == model)
        if images and "image" not in entry.get("input_modalities", ["text", "image"]):
            raise HTTPException(400, "Selected model does not support images")
        return model, prompt, images

    async def complete(self, body):
        if not self.ready():
            raise HTTPException(503, "Connect OpenAI in Wardrowbe Settings")
        try:
            await asyncio.wait_for(self.slots.acquire(), timeout=2)
        except TimeoutError as error:
            raise HTTPException(429, "Codex is busy; retry shortly") from error
        try:
            with tempfile.TemporaryDirectory(prefix="wardrowbe-codex-") as temporary:
                directory = Path(temporary)
                model, prompt, images = await self.prepare_model(body, directory)
                output = directory / "response.txt"
                instructions = directory / "instructions.txt"
                instructions.write_text(
                    "You are a wardrobe assistant. Answer the supplied conversation directly. "
                    "Follow its system instructions and requested output format. "
                    "Never use tools or read files. Attached images are the conversation's images."
                )
                catalog_path = sanitize_catalog(
                    json.dumps(self.catalog), model, directory
                )
                command = make_command(
                    self.executable, model, directory, catalog_path, images
                )
                environment = {
                    key: value
                    for key, value in os.environ.items()
                    if key in {"PATH", "SSL_CERT_FILE", "NIX_SSL_CERT_FILE", "TMPDIR"}
                }
                environment.update(CODEX_HOME=str(self.home), HOME=str(self.home))
                process = await asyncio.create_subprocess_exec(
                    *command,
                    cwd=directory,
                    env=environment,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL,
                    start_new_session=True,
                )
                try:
                    await asyncio.wait_for(
                        process.communicate(prompt.encode()), self.timeout
                    )
                except (TimeoutError, asyncio.CancelledError) as error:
                    os.killpg(process.pid, signal.SIGKILL)
                    await process.wait()
                    if isinstance(error, asyncio.CancelledError):
                        raise
                    raise HTTPException(504, "Codex request timed out") from error
                if process.returncode or not output.is_file():
                    raise HTTPException(
                        502, "Codex failed; check login and account model availability"
                    )
                if output.stat().st_size > MAX_OUTPUT:
                    raise HTTPException(502, "Codex response exceeds size limit")
                content = output.read_text().strip()
                if not content:
                    raise HTTPException(502, "Codex returned an empty response")
                return {
                    "id": f"chatcmpl-{uuid.uuid4().hex}",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": content},
                            "finish_reason": "stop",
                        }
                    ],
                }
        finally:
            self.slots.release()


def require_api_key(request, api_key):
    if not hmac.compare_digest(
        request.headers.get("authorization", ""), f"Bearer {api_key}"
    ):
        raise HTTPException(401, "Unauthorized")


def create_app(adapter):
    api_key = Path(os.environ["CODEX_API_KEY_FILE"]).read_text(encoding="utf-8").strip()
    if not api_key:
        raise RuntimeError("Codex adapter API key is empty")
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.get("/v1/models")
    async def models(request: Request):
        require_api_key(request, api_key)
        if not adapter.ready():
            raise HTTPException(503, "Connect OpenAI in Wardrowbe Settings")
        info = await adapter.information()
        return {
            "object": "list",
            "data": [
                {"id": model, "object": "model", "owned_by": "openai"}
                for model in info["models"]
            ],
            "selection": info["selection"],
        }

    @app.post("/v1/chat/completions")
    async def complete(request: Request):
        require_api_key(request, api_key)
        raw = bytearray()
        async for chunk in request.stream():
            raw.extend(chunk)
            if len(raw) > MAX_BODY:
                raise HTTPException(413, "Request body exceeds size limit")
        try:
            body = json.loads(raw)
        except (ValueError, UnicodeError) as error:
            raise HTTPException(400, "Invalid JSON") from error
        if not isinstance(body, dict):
            raise HTTPException(400, "Expected a JSON object")
        return await adapter.complete(body)

    return app


class BrowserLogin:
    """Own the official stdio RPC connection without exposing its token responses."""

    def __init__(self, adapter, login_timeout=900):
        self.adapter = adapter
        self.process = None
        self.reader = None
        self.pending = {}
        self.serial = 0
        self.lock = asyncio.Lock()
        self.login = None
        self.login_timeout = login_timeout
        self.expiry = None
        self.error = None

    def authorize(self, user, claim=False):
        # This is an installation-wide provider account. Only its connecting
        # Wardrowbe user may replace it. The UUID arrives over the private socket.
        try:
            uuid.UUID(user)
        except (ValueError, TypeError, AttributeError) as error:
            raise HTTPException(400, "Invalid Wardrowbe user") from error
        owner = self.adapter.home / "browser-owner"
        if owner.exists():
            if owner.read_text() != user:
                raise HTTPException(
                    403, "Another Wardrowbe user manages this connection"
                )
        elif claim:
            descriptor = os.open(owner, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as stream:
                stream.write(user)

    async def read_messages(self):
        if self.process is None or self.process.stdout is None:
            raise RuntimeError("Authentication reader has no subprocess stream")
        try:
            while line := await self.process.stdout.readline():
                await self.handle_message(json.loads(line))
        except ValueError, OSError, asyncio.LimitOverrunError:
            self.error = "OpenAI connection interrupted. Try again."
        finally:
            for future in self.pending.values():
                if not future.done():
                    future.set_exception(
                        HTTPException(503, "OpenAI connection interrupted. Try again.")
                    )
            self.pending.clear()
            self.login = None

    async def handle_message(self, message):
        if message.get("id") in self.pending:
            future = self.pending.pop(message["id"])
            if not future.done():
                if "error" in message:
                    future.set_exception(
                        HTTPException(
                            502,
                            "OpenAI sign-in failed. Try again on OpenAI's website.",
                        )
                    )
                else:
                    future.set_result(message.get("result", {}))
        elif message.get("method") == "account/login/completed":
            result = message.get("params", {})
            if self.login and result.get("loginId") == self.login["loginId"]:
                self.login = None
                self.adapter.invalidate_catalog()
                self.error = (
                    None
                    if result.get("success")
                    else "OpenAI sign-in did not complete. Try again."
                )
                if self.expiry:
                    self.expiry.cancel()
        elif "id" in message and "method" in message:
            # This connection is authentication-only. Refuse any server
            # request instead of launching tools or accepting arbitrary RPC.
            await self.send({
                "id": message["id"],
                "error": {"code": -32601, "message": "Unsupported request"},
            })

    async def send(self, message):
        if self.process is None or self.process.stdin is None:
            raise HTTPException(503, "OpenAI connection is unavailable. Try again.")
        self.process.stdin.write((json.dumps(message) + "\n").encode())
        await self.process.stdin.drain()

    async def rpc(self, method, params=None):
        self.serial += 1
        identifier = self.serial
        future = asyncio.get_running_loop().create_future()
        self.pending[identifier] = future
        try:
            await self.send({"id": identifier, "method": method, "params": params})
            return await asyncio.wait_for(future, 20)
        except (TimeoutError, BrokenPipeError, ConnectionResetError) as error:
            await self.close()
            raise HTTPException(
                503, "OpenAI connection timed out. Try again."
            ) from error
        finally:
            self.pending.pop(identifier, None)

    async def ensure_server(self):
        if (
            self.process
            and self.process.returncode is None
            and self.reader
            and not self.reader.done()
        ):
            return
        await self.close()
        environment = {
            key: value
            for key, value in os.environ.items()
            if key in {"PATH", "SSL_CERT_FILE", "NIX_SSL_CERT_FILE", "TMPDIR"}
        }
        environment.update(
            HOME=str(self.adapter.home), CODEX_HOME=str(self.adapter.home)
        )
        self.process = await asyncio.create_subprocess_exec(
            self.adapter.executable,
            "-c",
            'cli_auth_credentials_store="file"',
            "-c",
            'forced_login_method="chatgpt"',
            "-c",
            "mcp_servers={}",
            "-c",
            "analytics.enabled=false",
            "app-server",
            "--listen",
            "stdio://",
            env=environment,
            cwd=self.adapter.home,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
            start_new_session=True,
            limit=1024 * 1024,
        )
        self.reader = asyncio.create_task(self.read_messages())
        try:
            await self.rpc(
                "initialize",
                {
                    "clientInfo": {
                        "name": "wardrowbe",
                        "title": "Wardrowbe AI settings",
                        "version": "1.0.0",
                    }
                },
            )
            await self.send({"method": "initialized"})
        except BaseException:
            await self.close()
            raise

    async def status(self, user):
        async with self.lock:
            self.authorize(user)
            await self.ensure_server()
            account = (await self.rpc("account/read", {"refreshToken": False})).get(
                "account"
            )
            return {
                "enabled": True,
                "connected": isinstance(account, dict)
                and account.get("type") == "chatgpt",
                "pending": self.login,
                "error": self.error,
                **(
                    await self.adapter.information()
                    if isinstance(account, dict)
                    else {"models": []}
                ),
            }

    async def start(self, user, method="browser"):
        async with self.lock:
            if method not in {"browser", "device"}:
                raise HTTPException(400, "Unsupported sign-in method")
            self.authorize(user, claim=True)
            await self.ensure_server()
            if self.login:
                return self.login
            params = (
                {"type": "chatgptDeviceCode"}
                if method == "device"
                else {"type": "chatgpt", "useHostedLoginSuccessPage": True}
            )
            result = await self.rpc("account/login/start", params)
            # Accept only supported provider URLs; OAuth state and PKCE stay
            # under the official CLI's control. Never rewrite its redirect URI.
            valid = isinstance(result.get("loginId"), str)
            if method == "browser":
                url = result.get("authUrl", "")
                try:
                    parsed = urlsplit(url)
                    redirect = parse_qs(parsed.query).get("redirect_uri", [])
                    callback = urlsplit(redirect[0]) if len(redirect) == 1 else None
                    valid = (
                        valid
                        and result.get("type") == "chatgpt"
                        and (
                            parsed.scheme == "https"
                            and parsed.hostname in {"auth.openai.com", "chatgpt.com"}
                            and parsed.port in {None, 443}
                            and not parsed.username
                            and not parsed.password
                            and not parsed.fragment
                            and callback is not None
                            and callback.scheme == "http"
                            and callback.hostname in {"localhost", "127.0.0.1", "::1"}
                            and callback.port is not None
                            and callback.path == "/auth/callback"
                            and not callback.username
                            and not callback.password
                            and not callback.query
                            and not callback.fragment
                        )
                    )
                except TypeError, ValueError:
                    valid = False
                fields = ("loginId", "authUrl")
            else:
                valid = valid and (
                    result.get("type") == "chatgptDeviceCode"
                    and result.get("verificationUrl")
                    == "https://auth.openai.com/codex/device"
                    and isinstance(result.get("userCode"), str)
                )
                fields = ("loginId", "verificationUrl", "userCode")
            if not valid:
                await self.close()
                raise HTTPException(502, "Unsupported OpenAI sign-in response")
            self.login = {key: result[key] for key in fields}
            self.login["method"] = method
            self.login["expiresAt"] = int(time.time()) + self.login_timeout
            self.error = None
            self.expiry = asyncio.create_task(self.expire())
            return self.login

    async def expire(self):
        await asyncio.sleep(self.login_timeout)
        async with self.lock:
            if self.login:
                try:
                    await self.rpc(
                        "account/login/cancel", {"loginId": self.login["loginId"]}
                    )
                except HTTPException:
                    await self.close()
                self.login = None
                self.error = "Sign-in expired. Start again."

    async def disconnect(self, user):
        async with self.lock:
            self.authorize(user, claim=True)
            await self.ensure_server()
            if self.login:
                await self.rpc(
                    "account/login/cancel", {"loginId": self.login["loginId"]}
                )
                self.login = None
            await self.rpc("account/logout")
            self.adapter.invalidate_catalog()
            self.error = None
            if self.expiry:
                self.expiry.cancel()
            # Keep the owner binding after logout so a different app user cannot
            # silently replace the installation's provider credentials.

    async def close(self):
        if self.expiry and self.expiry is not asyncio.current_task():
            self.expiry.cancel()
        if self.process:
            if self.process.returncode is None:
                try:
                    with suppress(ProcessLookupError):
                        os.killpg(self.process.pid, signal.SIGTERM)
                    await asyncio.wait_for(self.process.wait(), 3)
                except TimeoutError:
                    with suppress(ProcessLookupError):
                        os.killpg(self.process.pid, signal.SIGKILL)
                    await self.process.wait()
            if self.reader:
                await self.reader
            self.process = None
        self.login = None


def create_control_app(login):
    @asynccontextmanager
    async def lifespan(_app):
        try:
            yield
        finally:
            await login.close()

    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)

    @app.get("/status")
    async def status(user: str):
        return await login.status(user)

    @app.post("/login")
    async def start(user: str, method: Literal["browser", "device"] = "browser"):
        return await login.start(user, method)

    @app.post("/disconnect")
    async def disconnect(user: str):
        await login.disconnect(user)
        return {"connected": False}

    return app


class ManagedServer(uvicorn.Server):
    @override
    @contextmanager
    def capture_signals(self):
        yield


def prepare_api_key():
    api_key_path = Path(os.environ["CODEX_API_KEY_FILE"])
    try:
        descriptor = os.open(
            api_key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
        )
    except FileExistsError:
        descriptor = None
    if descriptor is not None:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(secrets.token_urlsafe(48) + "\n")
            handle.flush()
            os.fchmod(handle.fileno(), 0o640)


async def serve(adapter):
    servers = [
        ManagedServer(
            uvicorn.Config(
                create_app(adapter),
                host="127.0.0.1",
                port=int(os.environ["PORT"]),
                access_log=False,
                limit_concurrency=16,
                timeout_keep_alive=5,
            )
        )
    ]
    socket = os.environ.get("CODEX_CONTROL_SOCKET")
    if socket:
        servers.append(
            ManagedServer(
                uvicorn.Config(
                    create_control_app(BrowserLogin(adapter)),
                    uds=socket,
                    access_log=False,
                    limit_concurrency=16,
                    timeout_keep_alive=5,
                )
            )
        )
    loop = asyncio.get_running_loop()

    def stop():
        for server in servers:
            server.should_exit = True

    for signum in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signum, stop)
    try:
        await asyncio.gather(*(server.serve() for server in servers))
    finally:
        stop()
        for signum in (signal.SIGINT, signal.SIGTERM):
            loop.remove_signal_handler(signum)


if __name__ == "__main__":
    if sys.argv[1:] == ["--prepare-key"]:
        prepare_api_key()
    else:
        adapter = Adapter(
            os.environ["CODEX_EXECUTABLE"],
            os.environ["CODEX_HOME"],
            json.loads(os.environ["CODEX_MODELS"]),
            int(os.environ["CODEX_TIMEOUT"]),
            int(os.environ["CODEX_CONCURRENCY"]),
        )
        asyncio.run(serve(adapter))
