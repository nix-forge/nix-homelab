"""Maintain private standalone-song shuffle and editable album-only overrides."""

# Dynamic native API payloads; fixed diagnostics never include credentials.
# ruff: file-ignore[any-type]
from __future__ import annotations

import argparse
import json
import sys
from email.utils import parsedate_to_datetime
from http import HTTPStatus
from pathlib import Path
from time import monotonic, sleep, time
from typing import TYPE_CHECKING, Any, NoReturn, override
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

if TYPE_CHECKING:
    from collections.abc import Callable

MARKER = "Managed standalone shuffle v1. "
PAGE_SIZE = 500
SMART_INDEX = 2
LOGIN_ATTEMPTS = 5
LOGIN_BUDGET = 90
RETRY_HEADER_LIMIT = 128
RETRY_SECONDS_DIGITS = 6
DEFINITIONS = (
    ("Album-only tracks", MARKER + "Exclude these tracks from Standalone songs."),
    ("Shuffle inclusions", MARKER + "Include these tracks despite title hints."),
    ("Standalone songs", MARKER + "Shuffle this playlist; albums remain complete."),
)


def standalone_rules(excluded_id: str, included_id: str) -> dict[str, Any]:
    """Build conservative criteria with explicit exclusion taking precedence.

    Returns:
        Native smart playlist criteria.

    """
    hints = [
        {"isNot": {"title": title}}
        for title in ("skit", "Skit", "SKIT", "interlude", "Interlude", "INTERLUDE")
    ] + [
        {"notContains": {"title": label}}
        for label in ("(skit)", "[skit]", "(interlude)", "[interlude]")
    ]
    return {
        "all": [
            {"notInPlaylist": {"id": excluded_id}},
            {
                "any": [
                    {"inPlaylist": {"id": included_id}},
                    {"all": hints},
                ],
            },
        ],
        # Stable server ordering avoids repeated random evaluation changing pages.
        # Clients shuffle the complete playlist at playback time.
        "sort": "album,discnumber,tracknumber,title",
    }


def managed_playlists(request: Callable[..., Any]) -> list[dict[str, Any] | None]:
    """Find managed resources without trusting names as ownership.

    Returns:
        The validated resources, with None for missing playlists.

    Raises:
        TypeError: The server returned an invalid listing.
        RuntimeError: Resources are ambiguous, altered, or exceed the bound.

    """
    playlists = []
    for start in range(0, 100_000, PAGE_SIZE):
        page = request(f"/api/playlist?_start={start}&_end={start + PAGE_SIZE}")
        if not isinstance(page, list):
            raise TypeError("Invalid playlist listing")
        playlists.extend(page)
        if len(page) < PAGE_SIZE:
            break
    else:
        raise RuntimeError("Playlist listing exceeded the safety bound")

    managed = []
    # Validate all existing targets before any writes. Names alone confer no ownership.
    for index, (name, comment) in enumerate(DEFINITIONS):
        matches = [p for p in playlists if p.get("comment") == comment]
        if len(matches) > 1:
            raise RuntimeError("Duplicate managed shuffle playlists need review")
        current = matches[0] if matches else None
        if current and (current.get("public") or current.get("sync")):
            raise RuntimeError("Managed shuffle playlist privacy or sync changed")
        if current and index < SMART_INDEX and current.get("rules"):
            raise RuntimeError("Shuffle override playlist must remain editable")
        if current is None and any(p.get("name") == name for p in playlists):
            raise RuntimeError("An unmanaged playlist already uses a reserved name")
        managed.append(current)

    return managed


def reconcile(request: Callable[..., Any], *, dry_run: bool = False) -> int:
    """Create missing managed playlists and repair only the smart rules.

    Returns:
        Number of planned or applied writes.

    """
    managed = managed_playlists(request)
    writes = 0
    ids = []
    for index, (name, comment) in enumerate(DEFINITIONS):
        current = managed[index]
        rules = standalone_rules(*ids) if index == SMART_INDEX else None
        if current is None:
            writes += 1
            if dry_run:
                ids.append(f"planned-{index}")
                continue
            current = request(
                "/api/playlist",
                {"name": name, "comment": comment, "public": False, "rules": rules},
                method="POST",
            )
        elif index == SMART_INDEX and current.get("rules") != rules:
            writes += 1
            if not dry_run:
                # PUT is a partial resource update. Leave names, art and memberships alone.
                request(
                    "/api/playlist/" + quote(current["id"], safe=""),
                    {"rules": rules},
                    method="PUT",
                )
        ids.append(current["id"])
    return writes


class NoRedirect(HTTPRedirectHandler):
    """Keep authentication on the configured loopback origin."""

    @override
    def redirect_request(self, *args: object, **kwargs: object) -> NoReturn:
        """Reject redirects before sending credentials to another endpoint.

        Raises:
            OSError: Always, before following the redirect.

        """
        raise OSError("Unexpected redirect from music server")


def login_retry_delay(error: HTTPError, remaining: float) -> float | None:
    """Respect server backoff without an immediate retry or unbounded wait.

    Returns:
        A positive delay within the operation budget, or None to stop retrying.

    """
    value = (error.headers.get("Retry-After") or "").strip()
    delay = 15.0  # Navidrome's shared local login window when no hint is supplied.
    if len(value) > RETRY_HEADER_LIMIT:
        return None
    if value.isascii() and value.isdecimal():
        if len(value) > RETRY_SECONDS_DIGITS:
            return None
        delay = float(int(value))
    elif value:
        try:
            date = parsedate_to_datetime(value)
            if date.tzinfo is not None:
                delay = date.timestamp() - time()
        except ValueError, OverflowError:
            delay = 15.0  # Malformed hints use the local fallback.
    delay = max(1.0, delay)
    return delay if delay < remaining else None


def main() -> None:
    """Authenticate as the listener and reconcile their private playlists.

    Raises:
        HTTPError: Authentication failed or remained rate-limited after retries.
        ValueError: The server URL is not a credential-free HTTP(S) endpoint.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-url", required=True)
    parser.add_argument("--username-file", required=True, type=Path)
    parser.add_argument("--password-file", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    url = urlsplit(args.server_url)
    if (
        url.scheme not in {"http", "https"}
        or not url.hostname
        or any([url.username, url.password, url.query, url.fragment])
    ):
        raise ValueError("Music shuffle requires a credential-free HTTP(S) server URL")
    opener = build_opener(ProxyHandler({}), NoRedirect)
    token = ""

    def request(
        path: str, body: Any = None, *, method: str = "GET", timeout: float = 20
    ) -> Any:
        headers = {"Content-Type": "application/json"}
        if token:
            headers["x-nd-authorization"] = "Bearer " + token
        req = Request(  # ruff: ignore[suspicious-url-open-usage] - HTTP(S) checked before constructing authenticated requests.
            args.server_url.rstrip("/") + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers=headers,
            method=method,
        )
        with opener.open(req, timeout=timeout) as response:
            payload = response.read(8 * 1024 * 1024 + 1)
        if len(payload) > 8 * 1024 * 1024:
            raise RuntimeError("Music server response exceeded the safety bound")
        return json.loads(payload) if payload else None

    credentials = {
        "username": args.username_file.read_text(encoding="utf-8").rstrip("\r\n"),
        "password": args.password_file.read_text(encoding="utf-8").rstrip("\r\n"),
    }
    # Activation clients share Navidrome's loopback login rate limit. Retry
    # only throttled login, before reconciling, under one monotonic deadline.
    deadline = monotonic() + LOGIN_BUDGET
    for attempt in range(LOGIN_ATTEMPTS):
        try:
            login = request(
                "/auth/login",
                credentials,
                method="POST",
                timeout=min(20, max(0.001, deadline - monotonic())),
            )
            break
        except HTTPError as error:
            if (
                error.code != HTTPStatus.TOO_MANY_REQUESTS
                or attempt == LOGIN_ATTEMPTS - 1
            ):
                raise
            delay = login_retry_delay(error, deadline - monotonic())
            if delay is None:
                raise
            sleep(delay)
            if monotonic() >= deadline:
                raise
    token = login["token"]
    writes = reconcile(request, dry_run=args.dry_run)
    sys.stdout.write(
        f"Shuffle playlists: {writes} {'planned' if args.dry_run else 'applied'} writes\n"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError, ValueError, KeyError, TypeError, RuntimeError:
        sys.stderr.write(
            "Music shuffle configuration failed; check service access and playlist ownership.\n"
        )
        sys.exit(1)
