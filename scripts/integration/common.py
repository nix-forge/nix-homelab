"""Shared transport, credential, and comparison rules for integration adapters."""

import copy
import hashlib
import hmac
import http.cookiejar
import ipaddress
import json
import os
import re
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class ConfigurationError(Exception):
    pass


class APIError(ConfigurationError):
    def __init__(self, status):
        self.status = status
        super().__init__(f"API request failed with HTTP {status}")


class APIUnavailableError(ConfigurationError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        raise ConfigurationError("API redirects are forbidden")


def validate_url(url):
    if (
        not isinstance(url, str)
        or url != url.strip()
        or any(ord(char) < 32 for char in url)
    ):
        raise ConfigurationError("Invalid API URL")
    try:
        parsed = urllib.parse.urlsplit(url)
        hostname = parsed.hostname
        # urlsplit defers invalid port syntax and range checks until this access.
        _port = parsed.port
    except ValueError as error:
        raise ConfigurationError("Invalid API URL") from error
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ConfigurationError(
            "API URL must not contain credentials, query or fragment"
        )
    if not hostname or parsed.scheme not in {"http", "https"}:
        raise ConfigurationError("Invalid API URL")
    try:
        loopback = ipaddress.ip_address(hostname).is_loopback
    except ValueError:
        loopback = hostname == "localhost"
    if parsed.scheme != "https" and not loopback:
        raise ConfigurationError("Non-loopback API endpoints require HTTPS")
    return url.rstrip("/")


def resolve(value):
    if isinstance(value, dict):
        if "_credential" in value:
            name = value["_credential"]
            if set(value) != {"_credential"} or not re.fullmatch(
                r"[A-Za-z0-9_-]+", name
            ):
                raise ConfigurationError("Invalid credential reference")
            directory = Path(os.environ["CREDENTIALS_DIRECTORY"])
            result = (directory / name).read_text().rstrip("\r\n")
            if not result:
                raise ConfigurationError("Empty credential")
            return result
        return {key: resolve(item) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item) for item in value]
    return value


class Client:
    def __init__(self, url, headers=None):
        self.url = validate_url(url)
        self.headers = headers or {}
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            NoRedirect(),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        )

    def request(
        self, method, path, body=None, form=False, json_response=True, read_only=None
    ):
        if not path.startswith("/") or path.startswith("//") or ".." in path:
            raise ConfigurationError("Invalid API path")
        payload = (
            None
            if body is None
            else (
                urllib.parse.urlencode(body, doseq=True).encode()
                if form
                else json.dumps(body).encode()
            )
        )
        content_type = (
            "application/x-www-form-urlencoded" if form else "application/json"
        )
        request = urllib.request.Request(
            self.url + path,
            data=payload,
            method=method,
            headers={"Content-Type": content_type, **self.headers},
        )
        read_only = method == "GET" if read_only is None else read_only
        for attempt in range(4 if read_only else 1):
            try:
                with self.opener.open(request, timeout=15) as response:
                    data = response.read(8 * 1024 * 1024 + 1)
                    if len(data) > 8 * 1024 * 1024:
                        raise ConfigurationError("API response exceeded size limit")
                    return (
                        (json.loads(data) if data else None) if json_response else data
                    )
            except urllib.error.HTTPError as error:
                if read_only and error.code in {429, 502, 503, 504} and attempt < 3:
                    time.sleep(2**attempt)
                    continue
                if error.code in {429, 502, 503, 504}:
                    raise APIUnavailableError("API is not ready") from None
                raise APIError(error.code) from None
            except urllib.error.URLError, TimeoutError:
                if read_only and attempt < 3:
                    time.sleep(2**attempt)
                    continue
                raise APIUnavailableError(
                    "API unavailable or request timed out"
                ) from None
        raise ConfigurationError("API retry limit exceeded")

    def wait_ready(self, path, json_response=True, expected_body=None):
        deadline = time.monotonic() + 90
        while True:
            try:
                result = self.request("GET", path, json_response=json_response)
                if expected_body is not None and result.strip() != expected_body:
                    raise APIUnavailableError("API has not completed initialization")
                return
            except APIUnavailableError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)


def merge(current, values):
    result = copy.deepcopy(current)
    for key, value in values.items():
        if key == "fields" and isinstance(value, dict):
            fields = {field["name"]: field for field in result.get("fields", [])}
            if not set(value).issubset(fields):
                raise ConfigurationError("Unknown provider schema field")
            for name, field_value in value.items():
                fields[name]["value"] = field_value
        elif isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def password_fingerprint(password, previous=None):
    if isinstance(previous, str) and previous.startswith("scrypt$"):
        _, salt_hex, digest_hex = previous.split("$")
        salt = bytes.fromhex(salt_hex)
        digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1).hex()
        if hmac.compare_digest(digest, digest_hex):
            return previous
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1).hex()
    return "scrypt$" + salt.hex() + "$" + digest


def contains(current, declared):
    if isinstance(declared, dict):
        return isinstance(current, dict) and all(
            key in current and contains(current[key], value)
            for key, value in declared.items()
        )
    if isinstance(declared, list):
        return (
            isinstance(current, list)
            and len(current) == len(declared)
            and all(map(contains, current, declared, strict=True))
        )
    return current == declared
