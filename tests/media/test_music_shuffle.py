"""Managed shuffle resources preserve overrides and unrelated playlists."""

# Native API fixtures intentionally use dynamic JSON.
# ruff: file-ignore[any-type]

import copy
import importlib.util
import io
import json
from datetime import UTC, datetime
from email.message import Message
from email.utils import format_datetime
from http import HTTPStatus
from pathlib import Path
from typing import Any
from urllib.error import HTTPError

import pytest

EXPECTED_PLAYLISTS = 3
EXPECTED_LOGIN_ATTEMPTS = 5

SPEC = importlib.util.spec_from_file_location(
    "music_shuffle",
    Path(__file__).parents[2] / "scripts/media/configure_music_shuffle.py",
)
assert SPEC is not None
assert SPEC.loader is not None
shuffle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shuffle)


@pytest.mark.parametrize("status", [429, 401, 403])
def test_login_retries_only_rate_limits(
    status: int, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Retry throttled authentication before any playlist requests or writes."""
    username = tmp_path / "username"
    password = tmp_path / "password"
    username.write_text("fixture-user")
    password.write_text("fixture-password")
    calls = []
    delays = []

    class Opener:
        @staticmethod
        def open(request: Any, *, timeout: int) -> io.BytesIO:
            assert timeout > 0
            calls.append((request.full_url, request.method))
            if len(calls) == 1:
                raise HTTPError(
                    request.full_url, status, "Fixture failure", Message(), None
                )
            payload = {"token": "fixture-token"} if request.method == "POST" else []
            return io.BytesIO(json.dumps(payload).encode())

    monkeypatch.setattr(shuffle, "build_opener", lambda *_args: Opener())
    monkeypatch.setattr(shuffle, "sleep", delays.append)
    monkeypatch.setattr(
        shuffle.sys,
        "argv",
        [
            "shuffle",
            "--server-url",
            "http://127.0.0.1:4533",
            "--username-file",
            str(username),
            "--password-file",
            str(password),
            "--dry-run",
        ],
    )
    if status == HTTPStatus.TOO_MANY_REQUESTS:
        shuffle.main()
        assert delays == [15]
        assert [method for _, method in calls] == ["POST", "POST", "GET"]
    else:
        with pytest.raises(HTTPError) as failure:
            shuffle.main()
        assert failure.value.code == status
        assert len(calls) == 1
        assert delays == []


def test_persistent_login_rate_limit_is_bounded(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Stop retrying a persistent throttle within the unit's startup budget."""
    credential = tmp_path / "credential"
    credential.write_text("fixture")
    calls = []
    delays = []

    class Opener:
        @staticmethod
        def open(request: Any, *, timeout: int) -> io.BytesIO:
            assert timeout > 0
            calls.append(request.full_url)
            raise HTTPError(
                request.full_url,
                HTTPStatus.TOO_MANY_REQUESTS,
                "Fixture throttle",
                Message(),
                None,
            )

    monkeypatch.setattr(shuffle, "build_opener", lambda *_args: Opener())
    monkeypatch.setattr(shuffle, "sleep", delays.append)
    monkeypatch.setattr(
        shuffle.sys,
        "argv",
        [
            "shuffle",
            "--server-url",
            "http://127.0.0.1:4533",
            "--username-file",
            str(credential),
            "--password-file",
            str(credential),
        ],
    )
    with pytest.raises(HTTPError) as failure:
        shuffle.main()
    assert failure.value.code == HTTPStatus.TOO_MANY_REQUESTS
    assert len(calls) == EXPECTED_LOGIN_ATTEMPTS
    assert delays == [15] * 4
    assert all(url.endswith("/auth/login") for url in calls)


class Server:
    """Native playlist resource fixture that records mutations."""

    def __init__(self) -> None:
        """Start with an empty account."""
        self.playlists: list[dict[str, Any]] = []
        self.writes: list[tuple[str, str, dict[str, Any]]] = []

    def request(
        self, path: str, body: dict[str, Any] | None = None, *, method: str = "GET"
    ) -> Any:
        """Model a partial resource update, leaving tracks intact.

        Returns:
            The requested native resource payload.

        """
        if method == "GET":
            return copy.deepcopy(self.playlists)
        assert body is not None
        self.writes.append((method, path, copy.deepcopy(body)))
        if method == "POST":
            playlist = {**body, "id": str(len(self.playlists)), "tracks": []}
            self.playlists.append(playlist)
            return copy.deepcopy(playlist)
        assert method == "PUT"
        playlist_id = path.rsplit("/", 1)[1]
        playlist = next(p for p in self.playlists if p["id"] == playlist_id)
        playlist.update(body)
        return copy.deepcopy(playlist)


def test_private_creation_then_no_writes() -> None:
    """Provision private editable controls and then leave the server untouched."""
    server = Server()
    assert shuffle.reconcile(server.request) == EXPECTED_PLAYLISTS
    assert all(not p["public"] for p in server.playlists)
    assert server.playlists[0]["rules"] is None
    assert server.playlists[1]["rules"] is None
    # The smart criteria must reference the resources actually returned by the API.
    rules = server.playlists[2]["rules"]["all"]
    assert rules[0] == {"notInPlaylist": {"id": "0"}}
    assert rules[1]["any"][0] == {"inPlaylist": {"id": "1"}}
    server.writes.clear()
    assert shuffle.reconcile(server.request) == 0
    assert server.writes == []


def test_repair_preserves_memberships_names_art_and_other_playlists() -> None:
    """Only managed rules change when repairing a modified smart playlist."""
    server = Server()
    shuffle.reconcile(server.request)
    server.playlists[0]["tracks"] = ["excluded-track"]
    server.playlists[1]["tracks"] = ["included-track"]
    server.playlists[2].update(
        name="My shuffle",
        uploadedImage="cover",
        rules={"all": [{"gt": {"year": 2000}}]},
    )
    server.playlists.append({"id": "other", "name": "My favorites", "tracks": ["song"]})
    before = copy.deepcopy(server.playlists)
    server.writes.clear()
    assert shuffle.reconcile(server.request) == 1
    assert server.writes[0][:2] == ("PUT", "/api/playlist/2")
    assert set(server.writes[0][2]) == {"rules"}
    before[2]["rules"] = server.playlists[2]["rules"]
    assert before == server.playlists


@pytest.mark.parametrize(
    "alteration", ["duplicate", "name_collision", "public", "sync", "smart_override"]
)
def test_conflicts_refuse_all_writes(alteration: str) -> None:
    """Detect all conflicting resources before applying partial changes."""
    server = Server()
    shuffle.reconcile(server.request)
    if alteration == "duplicate":
        server.playlists.append(copy.deepcopy(server.playlists[0]))
    elif alteration == "name_collision":
        server.playlists[0]["comment"] = "User owned"
    elif alteration == "smart_override":
        server.playlists[1]["rules"] = {"all": [{"gt": {"year": 2000}}]}
    else:
        server.playlists[0][alteration] = True
    server.writes.clear()
    with pytest.raises(RuntimeError):
        shuffle.reconcile(server.request)
    assert server.writes == []


def test_dry_run_does_not_write() -> None:
    """An empty account can preview setup without creating resources."""
    server = Server()
    assert shuffle.reconcile(server.request, dry_run=True) == EXPECTED_PLAYLISTS
    assert server.playlists == []
    assert server.writes == []


def test_redirect_is_rejected() -> None:
    """Never redirect local authentication credentials."""
    with pytest.raises(OSError, match="redirect"):
        shuffle.NoRedirect().redirect_request()


def test_failure_does_not_reset_existing_overrides() -> None:
    """An interrupted request preserves already configured overrides for retry."""
    server = Server()
    shuffle.reconcile(server.request)
    server.playlists[0]["tracks"] = ["album-only"]
    server.playlists.pop()
    before = copy.deepcopy(server.playlists)

    def failing_request(
        path: str, body: dict[str, Any] | None = None, *, method: str = "GET"
    ) -> Any:
        if method == "POST":
            message = "Unavailable"
            raise OSError(message)
        return server.request(path, body, method=method)

    with pytest.raises(OSError, match="Unavailable"):
        shuffle.reconcile(failing_request)
    assert before == server.playlists
    assert shuffle.reconcile(server.request) == 1
    assert server.playlists[0]["tracks"] == ["album-only"]


@pytest.mark.parametrize(
    ("hint", "expected"),
    [
        ("7", 7),
        ("0", 1),
        ("invalid", 15),
        ("1.5", 15),
        ("9999999", None),
        ("999", None),
        ("0" * 129, None),
    ],
)
def test_login_server_backoff_is_bounded(hint: str, expected: float | None) -> None:
    """Honor server minimums and refuse waits that exhaust the overall budget."""
    headers = Message()
    headers["Retry-After"] = hint
    error = HTTPError("http://localhost/auth/login", 429, "Fixture", headers, None)
    assert shuffle.login_retry_delay(error, 60) == expected


def test_login_http_date_backoff(monkeypatch: pytest.MonkeyPatch) -> None:
    """HTTP date delays use wall time while past dates still impose a floor."""
    monkeypatch.setattr(shuffle, "time", lambda: 1000)
    headers = Message()
    headers["Retry-After"] = format_datetime(
        datetime.fromtimestamp(1012, UTC), usegmt=True
    )
    error = HTTPError("http://localhost/auth/login", 429, "Fixture", headers, None)
    expected_delay = 12
    assert shuffle.login_retry_delay(error, 60) == expected_delay
    headers.replace_header(
        "Retry-After", format_datetime(datetime.fromtimestamp(900, UTC), usegmt=True)
    )
    assert shuffle.login_retry_delay(error, 60) == 1
    assert shuffle.login_retry_delay(error, 1) is None
