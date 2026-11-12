"""Exercise caption provisioning against a disposable HTTP API."""

from __future__ import annotations

import json
import runpy
import threading
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import TYPE_CHECKING, Any, override

import pytest

if TYPE_CHECKING:
    from collections.abc import Iterator

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/media/configure_captions.py"
type Api = tuple[int, dict[str, Any]]
type Setup = tuple[dict[str, Any], tuple[Any, Path, Path, dict[str, Any]]]

SERVER_ID = "00000000000000000000000000000001"
USER_ID = "00000000000000000000000000000002"


@pytest.fixture
def api() -> Iterator[Api]:
    """Serve only the endpoints used by caption setup.

    Yields:
        The local port and mutable server response state.

    """
    state: dict[str, Any] = {"saved": [], "fail": False, "logout": 0, "sync": True}

    class Handler(BaseHTTPRequestHandler):
        @override
        def log_message(self, format: str, *args: object) -> None:
            del format, args

        def do_GET(self) -> None:
            if self.path == "/Users":
                self.reply(200, [{"Name": "viewer", "Id": USER_ID}])
            elif self.path == f"/Moonfin/Settings/{USER_ID}":
                self.reply(
                    200, {"syncEnabled": state["sync"], **state.get("current", {})}
                )
            else:
                self.reply(404, {})

        def do_POST(self) -> None:
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            payload = json.loads(body) if body else None
            if self.path == "/Users/AuthenticateByName":
                assert payload == {"Username": "viewer", "Pw": "secret"}
                self.reply(200, {"AccessToken": "test-token", "ServerId": SERVER_ID})
            elif self.path == f"/Moonfin/Settings/{USER_ID}":
                assert 'Token="test-token"' in self.headers["Authorization"]
                if state["fail"]:
                    self.reply(503, {"private": "must not be logged"})
                else:
                    state["saved"].append(payload)
                    self.reply(200, {"Success": True})
            elif self.path == "/Sessions/Logout":
                state["logout"] += 1
                self.reply(204, None)
            else:
                # Test redirect rejection without following to any other server.
                self.send_response(302)
                self.send_header("Location", "/Users")
                self.end_headers()

        def reply(self, status: int, payload: object) -> None:
            self.send_response(status)
            self.end_headers()
            if payload is not None:
                self.wfile.write(json.dumps(payload).encode())

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        yield server.server_port, state
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


@pytest.fixture
def setup(tmp_path: Path, api: Api) -> Setup:
    """Use real credential files and the production API client.

    Returns:
        The loaded command module and arguments for its provisioning entrypoint.

    """
    module = runpy.run_path(str(SCRIPT))
    module["configure"] = partial(
        module["configure"],
        policy=module["CaptionPolicy"](
            username_credentials=["admin-username", "viewer-username"],
            revision="v3",
            previous_revision="v2",
            previous_profiles={
                "desktop": {
                    "subtitlesTextSize": 24.0,
                    "assDirectPlay": True,
                    "subtitlesBackgroundColor": "#BF000000",
                }
            },
        ),
    )
    credentials = tmp_path / "credentials"
    credentials.mkdir()
    for name, value in {
        "admin-username": "viewer",
        "admin-password": "secret",
        "viewer-username": "viewer",
    }.items():
        (credentials / name).write_text(value, encoding="utf-8")
    preset = {"desktop": {"subtitlesTextSize": 18.0, "assDirectPlay": True}}
    return module, (module["Client"](api[0]), credentials, tmp_path / "state", preset)


def test_seeds_only_caption_fields_once(setup: Setup, api: Api) -> None:
    """Leave later GUI edits alone after successful setup."""
    module, arguments = setup
    module["configure"](*arguments)
    assert api[1]["saved"] == [
        {
            "settings": {
                "schemaVersion": 2,
                "desktop": {"subtitlesTextSize": 18.0, "assDirectPlay": True},
            },
            "clientId": "nix-caption-setup",
            "mergeMode": "merge",
        }
    ]
    # Subsequent activation must not reset GUI edits, even if the preset changes.
    arguments[3]["desktop"]["subtitlesTextSize"] = 25.0
    module["configure"](*arguments)
    assert len(api[1]["saved"]) == 1
    assert api[1]["logout"] == 2


def test_failed_save_can_retry_without_marking_success(setup: Setup, api: Api) -> None:
    """Record completion only after the server accepts the change."""
    module, arguments = setup
    api[1]["fail"] = True
    with pytest.raises(module["ApiError"], match="503"):
        module["configure"](*arguments)
    assert not list(arguments[2].iterdir())
    assert api[1]["logout"] == 1
    api[1]["fail"] = False
    module["configure"](*arguments)
    assert len(api[1]["saved"]) == 1


def test_disabled_sync_is_preserved(setup: Setup, api: Api) -> None:
    """Reject disabled synchronization without changing it."""
    module, arguments = setup
    api[1]["sync"] = False
    with pytest.raises(module["CaptionError"], match="settings sync"):
        module["configure"](*arguments)
    assert api[1]["saved"] == []
    assert not list(arguments[2].iterdir())


def test_redirect_is_not_followed(setup: Setup) -> None:
    """Never follow an API redirect with an authenticated request."""
    module, arguments = setup
    with pytest.raises(module["ApiError"], match="302"):
        arguments[0].request("POST", "/redirect")


def test_previous_preset_is_migrated_once(setup: Setup, api: Api) -> None:
    """Apply the requested readability upgrade despite an earlier seed marker."""
    module, arguments = setup
    state = arguments[2]
    state.mkdir()
    (state / f"{SERVER_ID}-{USER_ID}-v1").touch()
    module["configure"](*arguments)
    assert len(api[1]["saved"]) == 1
    assert (state / f"{SERVER_ID}-{USER_ID}-v3").exists()
    module["configure"](*arguments)
    assert len(api[1]["saved"]) == 1


def test_v2_migration_preserves_viewer_adjustments(setup: Setup, api: Api) -> None:
    """Reduce managed size without overwriting a viewer's deliberate choices."""
    module, arguments = setup
    state = arguments[2]
    state.mkdir()
    (state / f"{SERVER_ID}-{USER_ID}-v2").touch()
    arguments[3]["desktop"]["subtitlesBackgroundColor"] = "#00000000"
    api[1]["current"] = {
        "desktop": {
            "subtitlesTextSize": 24.0,
            "assDirectPlay": False,
            "subtitlesBackgroundColor": "#FF000000",
            "unrelated": "retained",
        }
    }
    module["configure"](*arguments)
    assert api[1]["saved"][0]["settings"]["desktop"] == {
        "subtitlesTextSize": 18.0,
    }
    assert (state / f"{SERVER_ID}-{USER_ID}-v3").exists()
