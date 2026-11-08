"""Canonical shared-library artwork and failure recovery tests."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import sqlite3
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable
from pathlib import Path

import pytest
from PIL import Image

SOURCE = Path(__file__).resolve().parents[2] / "scripts/media/artwork.py"
spec = importlib.util.spec_from_file_location("music_artwork", SOURCE)
assert spec is not None
assert spec.loader is not None
artwork = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artwork)
GROUP = "11111111-1111-4111-8111-111111111111"
URL = "https://coverartarchive.org/release/22222222-2222-4222-8222-222222222222/1-1200.jpg"


def image_bytes(size: tuple[int, int] = (1200, 1200)) -> bytes:
    """Return an independently generated test image.

    Returns:
        Encoded JPEG fixture bytes.

    """
    output = io.BytesIO()
    Image.new("RGB", size, "blue").save(output, "JPEG")
    return output.getvalue()


def downloader(
    data: bytes | None = None, fields: dict[str, bool] | None = None
) -> Callable[[str], bytes]:
    """Return a deterministic archive transport fixture.

    Returns:
        A downloader that rejects unexpected endpoints.

    """
    candidate = {
        "front": True,
        "approved": True,
        "thumbnails": {"1200": URL},
        **(fields or {}),
    }

    def download(url: str) -> bytes:
        if url == f"https://coverartarchive.org/release-group/{GROUP}":
            return json.dumps({"images": [candidate]}).encode()
        assert url == URL
        return image_bytes() if data is None else data

    return download


def test_canonical_cover_replaces_embedded_fallback_without_editing_audio(
    tmp_path: Path,
) -> None:
    """Verify canonical cover replaces embedded fallback without editing audio."""
    folder = tmp_path / "album"
    folder.mkdir()
    audio = folder / "track.flac"
    audio.write_bytes(b"audio-with-packaging-picture")
    state = tmp_path / "state"
    state.mkdir()
    assert artwork.sync_album(folder, GROUP, state, downloader(), now=1) == "updated"
    assert (folder / "cover.jpg").read_bytes() == image_bytes()
    assert audio.read_bytes() == b"audio-with-packaging-picture"

    def no_network(_url: str) -> bytes:
        pytest.fail("unchanged artwork should use its receipt")

    assert artwork.sync_album(folder, GROUP, state, no_network, now=2) == "cached"
    receipt = json.loads(next(state.glob("*.json")).read_text())
    assert receipt["source"] == URL
    assert receipt["sha256"] == hashlib.sha256(image_bytes()).hexdigest()


@pytest.mark.parametrize(
    ("fields", "data"),
    [
        ({"front": False}, None),
        ({"approved": False}, None),
        ({}, image_bytes((600, 600))),
        ({}, image_bytes((1200, 1800))),
    ],
)
def test_rejects_nonfront_unapproved_small_and_packaging_shaped_art(
    fields: dict[str, bool], data: bytes | None
) -> None:
    """Verify rejects nonfront unapproved small and packaging shaped art."""
    assert artwork.canonical_image(GROUP, downloader(data, fields)) is None


@pytest.mark.parametrize("filename", ["cover.jpg", "folder.png", "front.webp"])
def test_preserves_user_art(tmp_path: Path, filename: str) -> None:
    """Verify preserves user art."""
    (tmp_path / filename).write_bytes(b"curated artwork")

    def no_network(_url: str) -> bytes:
        pytest.fail("user artwork must not be replaced")

    assert artwork.sync_album(tmp_path, GROUP, tmp_path, no_network) == "preserved"
    assert (tmp_path / filename).read_bytes() == b"curated artwork"


def test_transient_failure_keeps_existing_cover_and_receipt(tmp_path: Path) -> None:
    """Verify transient failure keeps existing cover and receipt."""
    state = tmp_path / "state"
    state.mkdir()
    artwork.sync_album(tmp_path, GROUP, state, downloader(), now=1)
    original = (tmp_path / "cover.jpg").read_bytes()
    receipt = next(state.glob("*.json")).read_bytes()

    def unavailable(_url: str) -> bytes:
        raise TimeoutError

    with pytest.raises(TimeoutError):
        artwork.sync_album(tmp_path, GROUP, state, unavailable, now=40 * 86400)
    assert (tmp_path / "cover.jpg").read_bytes() == original
    assert next(state.glob("*.json")).read_bytes() == receipt


def test_library_does_not_assign_cover_to_mixed_albums_or_escape_root(
    tmp_path: Path,
) -> None:
    """Verify library does not assign cover to mixed albums or escape root."""
    database = tmp_path / "library.db"
    with sqlite3.connect(database) as connection:
        connection.executescript(
            (
                Path(__file__).with_name("fixtures")
                / "artwork-mixed-release-groups.sql"
            ).read_text(encoding="utf-8")
        )
    assert artwork.library_albums(database, tmp_path) == []
    with sqlite3.connect(database) as connection:
        connection.execute("INSERT INTO media_file VALUES ('../escape.flac', 'a', 0)")
    with pytest.raises(ValueError, match="escapes"):
        artwork.library_albums(database, tmp_path)


def test_refresh_queues_only_the_identified_album(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Verify artwork refresh addresses exact indexed album IDs."""
    database = tmp_path / "library.db"
    with sqlite3.connect(database) as connection:
        connection.executescript(
            "CREATE TABLE album (id TEXT, mbz_release_group_id TEXT, missing INT);"
        )
        connection.executemany(
            "INSERT INTO album VALUES (?, ?, ?)",
            [
                ("wanted", GROUP, 0),
                ("missing", GROUP, 1),
                ("unrelated", "other", 0),
            ],
        )
    calls = []

    def run(command: list[str], *, check: bool, capture_output: bool) -> None:
        assert check
        assert capture_output
        calls.append(command)

    monkeypatch.setattr(artwork.subprocess, "run", run)
    artwork.refresh_album(
        database, GROUP, Path("/fixture/navidrome"), Path("/fixture/config.json")
    )
    assert calls == [
        [
            "/fixture/navidrome",
            "--configfile",
            "/fixture/config.json",
            "--nobanner",
            "--loglevel",
            "error",
            "artwork",
            "refresh",
            "al",
            "wanted",
        ]
    ]


def test_unknown_identity_in_shared_folder_prevents_album_art_assignment(
    tmp_path: Path,
) -> None:
    """Verify untagged tracks cannot inherit another album's cover."""
    database = tmp_path / "library.db"
    with sqlite3.connect(database) as connection:
        connection.executescript(
            (
                Path(__file__).with_name("fixtures")
                / "artwork-missing-release-group.sql"
            ).read_text(encoding="utf-8")
        )
    assert artwork.library_albums(database, tmp_path) == []


def test_untagged_album_requires_unique_exact_artist_title_and_year() -> None:
    """Accept one exact identity and reject ambiguous or mismatched results."""
    group = "22222222-2222-4222-8222-222222222222"

    def candidate(**changes: object) -> dict[str, object]:
        return {
            "id": group,
            "title": "Sample Album",
            "score": 100,
            "first-release-date": "2023-03-03",
            "artist-credit": [{"name": "Sample Artist"}],
            **changes,
        }

    def download(rows: list[dict[str, object]]) -> Callable[[str], bytes]:
        def respond(url: str) -> bytes:
            assert url.startswith("https://musicbrainz.org/ws/2/release-group/?")
            return json.dumps({"release-groups": rows}).encode()

        return respond

    assert (
        artwork.resolve_release_group(
            "Sample Artist", "sample album", 2023, download([candidate()])
        )
        == group
    )
    assert (
        artwork.resolve_release_group(
            "Other Artist", "Sample Album", 2023, download([candidate()])
        )
        is None
    )
    assert (
        artwork.resolve_release_group(
            "Sample Artist", "Sample Album", 2026, download([candidate()])
        )
        is None
    )
    assert (
        artwork.resolve_release_group(
            "Sample Artist",
            "Sample Album",
            2023,
            download([
                candidate(),
                candidate(id="33333333-3333-4333-8333-333333333333"),
            ]),
        )
        is None
    )
    assert (
        artwork.resolve_release_group(
            "Sample Artist",
            "Sample Album",
            2023,
            download([
                candidate(score=75),
            ]),
        )
        is None
    )
    assert (
        artwork.resolve_release_group(
            "Sample Artist", 'Quoted "Album"', 2023, download([candidate()])
        )
        is None
    )


def test_untagged_album_identity_cache_and_exact_refresh(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Resolve untagged albums once and refresh only their indexed album ID."""
    database = tmp_path / "library.db"
    with sqlite3.connect(database) as connection:
        connection.executescript(
            (
                Path(__file__).with_name("fixtures")
                / "artwork-searchable-album-metadata.sql"
            ).read_text(encoding="utf-8")
        )
    folder, artist, title, year, album_id = artwork.unresolved_albums(
        database, tmp_path
    )[0]
    assert (artist, title, year, album_id) == ("Artist", "New Album", 2024, "unknown")
    state = tmp_path / "state"
    state.mkdir()
    group = "44444444-4444-4444-8444-444444444444"

    def download(_url: str) -> bytes:
        return json.dumps({
            "release-groups": [
                {
                    "id": group,
                    "title": title,
                    "score": 100,
                    "first-release-date": "2024-01-01",
                    "artist-credit": [{"name": artist}],
                }
            ]
        }).encode()

    assert (
        artwork.resolved_group_for_folder(
            folder, (artist, title, year), state, download=download, now=1
        )
        == group
    )

    def no_network(_url: str) -> bytes:
        pytest.fail("validated identity should use its receipt")

    assert (
        artwork.resolved_group_for_folder(
            folder, (artist, title, year), state, download=no_network, now=2
        )
        == group
    )
    calls = []

    def run(command: list[str], *, check: bool, capture_output: bool) -> None:
        assert check
        assert capture_output
        calls.append(command)

    monkeypatch.setattr(artwork.subprocess, "run", run)
    artwork.refresh_album(
        database,
        group,
        Path("/fixture/navidrome"),
        Path("/fixture/config.json"),
        album_id,
    )
    assert calls[0][-2:] == ["al", "unknown"]
