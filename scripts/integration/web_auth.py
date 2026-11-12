"""Set managed web credentials through native APIs without changing other settings."""

from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast, override

if TYPE_CHECKING:
    from email.message import Message
    from http.client import HTTPResponse


class ProvisionError(RuntimeError):
    """Sanitized failure which cannot echo application responses or credentials."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Reject redirects to prevent forwarding local credentials."""

    @override
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: object,
        code: int,
        msg: str,
        headers: Message,
        newurl: str,
    ) -> None:
        """Return no redirected request."""


def _backoff(deadline: float, attempt: int) -> None:
    """Block between safe protocol reads without extending their deadline."""
    remaining = deadline - time.monotonic()
    if remaining > 0:
        # The remote protocol has no readiness notification. Finite
        # exponential backoff blocks between idempotent requests.
        time.sleep(min(2**attempt, remaining))


def _open(
    opener: urllib.request.OpenerDirector, request: urllib.request.Request
) -> HTTPResponse:
    """Wait within one deadline for read response headers; never replay a write.

    Returns:
        The native HTTP response.

    Raises:
        ProvisionError: The read deadline or retry limit was exhausted.
        urllib.error.HTTPError: A request failed with a non-retryable HTTP status.

    """
    timeout = float(os.environ["HTTP_TIMEOUT_SECONDS"])
    budget = float(os.environ["HTTP_READ_RETRY_BUDGET_SECONDS"])
    attempts = int(os.environ["HTTP_READ_ATTEMPTS"])
    if min(timeout, budget, attempts) <= 0:
        raise ProvisionError
    if request.get_method() != "GET":
        return cast("HTTPResponse", opener.open(request, timeout=timeout))
    deadline = time.monotonic() + budget
    for attempt in range(attempts):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ProvisionError
        try:
            return cast(
                "HTTPResponse", opener.open(request, timeout=min(timeout, remaining))
            )
        except urllib.error.HTTPError as error:
            if error.code not in {429, 502, 503, 504}:
                raise
            error.close()
        except urllib.error.URLError, TimeoutError:
            if attempt + 1 == attempts:
                raise ProvisionError from None
        if attempt + 1 == attempts:
            break
        _backoff(deadline, attempt)
    raise ProvisionError


def _request(  # ruff: ignore[too-many-arguments] - native JSON/form protocol fields
    base: str,
    path: str,
    key: str | None = None,
    method: str = "GET",
    data: dict[str, Any] | None = None,
    *,
    form: bool = False,
) -> tuple[int, Message, dict[str, Any] | None]:

    headers = {"Accept": "application/json"}
    if key:
        headers["X-Api-Key"] = key
    payload = None
    if data is not None:
        payload = (urllib.parse.urlencode(data) if form else json.dumps(data)).encode()
        headers["Content-Type"] = (
            "application/x-www-form-urlencoded" if form else "application/json"
        )
    req = urllib.request.Request(  # ruff: ignore[suspicious-url-open-usage] - main restricts local HTTP endpoints
        base + path, data=payload, headers=headers, method=method
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        response = _open(opener, req)
    except urllib.error.HTTPError as error:
        if error.code not in {
            HTTPStatus.MOVED_PERMANENTLY,
            HTTPStatus.FOUND,
            HTTPStatus.SEE_OTHER,
        }:
            error.close()
            raise ProvisionError from None
        response = error
    with response:
        raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise ProvisionError
        return (
            cast("int", response.status),
            response.headers,
            json.loads(raw) if raw and not form else None,
        )


def _verify_login(base: str, username: str, password: str, *, bazarr: bool) -> None:
    if bazarr:
        status, _, _ = _request(
            base,
            "/api/system/account",
            method="POST",
            data={
                "action": "login",
                "username": username,
                "password": password,
            },
            form=True,
        )
        if status != HTTPStatus.NO_CONTENT:
            raise ProvisionError
    else:
        status, headers, _ = _request(
            base,
            "/login",
            method="POST",
            data={
                "username": username,
                "password": password,
                "rememberMe": "off",
            },
            form=True,
        )
        if (
            status not in {HTTPStatus.FOUND, HTTPStatus.SEE_OTHER}
            or not headers.get("Set-Cookie")
            or "loginFailed" in headers.get("Location", "")
        ):
            raise ProvisionError


def _verify_current(  # ruff: ignore[too-many-arguments] - explicit application credential fields
    base: str,
    version: str,
    username: str,
    password: str,
    key: str,
    *,
    bazarr: bool,
) -> None:
    path = "/api/system/settings" if bazarr else f"/api/{version}/config/host"
    _, _, current = _request(base, path, key)
    if not current:
        raise ProvisionError
    if bazarr:
        if current.get("auth", {}).get("type") not in {"form", "basic"}:
            raise ProvisionError
    elif str(current.get("authenticationMethod", "")).lower() != "forms":
        # Basic auth may bypass authentication for loopback requests. Refuse
        # unsupported mode rather than report a bypass as verified credentials.
        raise ProvisionError
    _verify_login(base, username, password, bazarr=bazarr)


def _configure(  # ruff: ignore[too-many-arguments] - explicit application credential fields
    base: str,
    version: str,
    username: str,
    password: str,
    key: str,
    *,
    bazarr: bool = False,
) -> None:

    if bazarr:
        _, _, current = _request(base, "/api/system/settings", key)
        if not current:
            raise ProvisionError
        auth = current.get("auth", {})
        auth_type = auth.get("type")
        if auth_type not in {"form", "basic", None, ""}:
            raise ProvisionError
        if not auth_type and (auth.get("username") or auth.get("password")):
            raise ProvisionError
        desired = {
            "settings-auth-username": username,
            "settings-auth-password": password,
        }
        if not auth_type:
            desired["settings-auth-type"] = "form"
        _request(base, "/api/system/settings", key, "POST", desired, form=True)
        _verify_login(base, username, password, bazarr=True)
    else:
        path = f"/api/{version}/config/host"
        _, _, current = _request(base, path, key)
        if not current:
            raise ProvisionError
        mode = str(current.get("authenticationMethod", "")).lower()
        if mode not in {"forms", "none"}:
            raise ProvisionError
        # A new installation starts without a website account. Bootstrap it
        # only when no existing credentials could be replaced accidentally.
        if mode == "none" and (current.get("username") or current.get("password")):
            raise ProvisionError
        identity = current.get("id")
        if not isinstance(identity, int) or identity < 1:
            raise ProvisionError
        # Returned password is a hash. Replace it with the sealed plaintext;
        # preserve every other resource field, including authenticationRequired.
        desired = {
            **current,
            "authenticationMethod": "forms",
            "username": username,
            "password": password,
            "passwordConfirmation": password,
        }
        _request(base, f"{path}/{identity}", key, "PUT", desired)
        _verify_login(base, username, password, bazarr=False)


def main() -> None:
    """Apply runtime credentials and commit a private verification marker.

    Raises:
        ProvisionError: Credential provisioning or login verification failed.

    """
    name, kind, base, version = sys.argv[1:]
    parsed = urllib.parse.urlsplit(base)
    if (
        parsed.scheme != "http"
        or not parsed.hostname
        or not (
            ipaddress.ip_address(parsed.hostname).is_loopback
            or ipaddress.ip_address(parsed.hostname).is_link_local
        )
        or any((parsed.username, parsed.query, parsed.fragment, parsed.path))
    ):
        raise ProvisionError
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    username, password, key = [
        (credentials / field).read_text().rstrip("\r\n")
        for field in ("username", "password", "api-key")
    ]
    if not username or not password or not key or "\n" in username:
        raise ProvisionError
    marker = Path(os.environ["STATE_DIRECTORY"]) / f"{name}.fingerprint"
    digest = hashlib.sha256(json.dumps([username, password]).encode()).hexdigest()
    if marker.exists() and marker.read_text().strip() == digest:
        try:
            _verify_current(
                base, version, username, password, key, bazarr=kind == "bazarr"
            )
        except RuntimeError, urllib.error.URLError, ValueError, OSError:
            # A restored database can invalidate the marker. Repair through
            # the native API while preserving existing authentication policy.
            marker.unlink(missing_ok=True)
        else:
            return
    try:
        _configure(base, version, username, password, key, bazarr=kind == "bazarr")
    except RuntimeError, urllib.error.URLError, ValueError, OSError:
        raise ProvisionError from None
    temporary = marker.with_suffix(".tmp")
    temporary.write_text(digest + "\n")
    temporary.chmod(0o600)
    temporary.replace(marker)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError, OSError, ValueError, KeyError:
        sys.stderr.write("Managed website credential update failed\n")
        sys.exit(1)
