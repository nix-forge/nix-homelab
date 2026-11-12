"""Shared lyric identity, preservation, filesystem and retry behavior."""

import importlib.util
import io
import json
import os
import sqlite3
from email.message import Message
from pathlib import Path
from typing import Any
from urllib.error import HTTPError

import pytest

SOURCE = Path(__file__).resolve().parents[2] / "scripts/media/lyrics.py"
spec = importlib.util.spec_from_file_location("music_lyrics", SOURCE)
assert spec is not None
assert spec.loader is not None
lyrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lyrics)
TRACK: dict[str, Any] = {
    "title": "Song",
    "artist": "Artist",
    "album": "Album",
    "duration": 120,
}
RESULT: dict[str, Any] = {
    "trackName": "Song",
    "artistName": "Artist",
    "albumName": "Album",
    "duration": 121,
    "instrumental": False,
    "syncedLyrics": "[00:01.00]Line\n[00:04.00]Next",
}


def test_exact_match():
    assert lyrics.matched_lyrics(TRACK, RESULT).startswith("[00:01.00]")


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("trackName", "Song (Live)"),
        ("artistName", "Someone else"),
        ("albumName", "Another edition"),
        ("duration", 123),
        ("duration", float("nan")),
        ("duration", True),
        ("instrumental", True),
        ("syncedLyrics", "Plain text"),
        ("syncedLyrics", "[03:00.00]Late"),
        ("syncedLyrics", "[00:05]One\n[00:01]Two"),
        ("syncedLyrics", "[00:01]\0bad"),
        ("syncedLyrics", "[00:01]"),
    ],
)
def test_rejects_wrong_recording_and_bad_timing(field, value):
    assert lyrics.matched_lyrics(TRACK, RESULT | {field: value}) is None


def fixture(tmp_path, paths=("album/song.flac",)):
    root = tmp_path / "music"
    root.mkdir()
    db = tmp_path / "navidrome.db"
    with sqlite3.connect(db) as connection:
        connection.execute(
            "CREATE TABLE media_file (path, title, artist, album, duration, missing, library_id)"
        )
        connection.execute("CREATE TABLE library (id, path)")
        connection.execute("INSERT INTO library VALUES (1, ?)", (str(root),))
        for path in paths:
            audio = root / path
            audio.parent.mkdir(parents=True, exist_ok=True)
            audio.write_bytes(b"original audio")
            connection.execute(
                "INSERT INTO media_file VALUES (?, 'Song', 'Artist', 'Album', 120, 0, 1)",
                (path,),
            )
    return db, root, tmp_path / "retry.sqlite"


def test_writes_complete_sidecar_and_never_rewrites_audio(tmp_path):
    db, root, state = fixture(tmp_path)
    audio = root / "album/song.flac"
    original = audio.stat()
    result = lyrics.sync(db, root, state, download=lambda _: RESULT)
    assert result["written"] == 1
    assert audio.read_bytes() == b"original audio"
    assert audio.stat().st_mtime_ns == original.st_mtime_ns
    assert (root / "album/song.lrc").read_text() == RESULT["syncedLyrics"] + "\n"
    assert not list(root.rglob(".music-lyrics-*"))
    assert (
        lyrics.sync(db, root, state, download=lambda _: pytest.fail("refetch"))[
            "requested"
        ]
        == 0
    )


@pytest.mark.parametrize("extension", [".LRC", ".elrc", ".txt", ".ttml", ".yaml"])
def test_preserves_every_existing_lyric_format(tmp_path, extension):
    db, root, state = fixture(tmp_path)
    sidecar = root / ("album/song" + extension)
    sidecar.write_text("curated")
    assert (
        lyrics.sync(db, root, state, download=lambda _: pytest.fail("fetch"))[
            "requested"
        ]
        == 0
    )
    assert sidecar.read_text() == "curated"


def test_misses_expire_and_requests_are_bounded(tmp_path):
    db, root, state = fixture(tmp_path, ("a.flac", "b.flac"))
    assert (
        lyrics.sync(db, root, state, limit=1, download=lambda _: None, now=0)[
            "requested"
        ]
        == 1
    )
    assert (
        lyrics.sync(db, root, state, limit=1, download=lambda _: None, now=1)[
            "requested"
        ]
        == 1
    )
    assert (
        lyrics.sync(db, root, state, download=lambda _: pytest.fail("cached"), now=2)[
            "requested"
        ]
        == 0
    )
    assert (
        lyrics.sync(db, root, state, download=lambda _: RESULT, now=8 * 86400)[
            "written"
        ]
        == 2
    )


def test_failure_stops_provider_requests_without_caching_a_miss(tmp_path):
    db, root, state = fixture(tmp_path, ("a.flac", "b.flac"))

    def failure(_):
        raise OSError("unavailable")

    assert lyrics.sync(db, root, state, download=failure)["failed"] == 1
    assert lyrics.sync(db, root, state, download=lambda _: RESULT)["written"] == 2


def test_rejects_symlinked_directory_and_traversal(tmp_path):
    root = tmp_path / "music"
    root.mkdir()
    (root / "linked").symlink_to(tmp_path, target_is_directory=True)
    with pytest.raises(NotADirectoryError):
        lyrics.open_parent(root, "linked/song.flac")
    with pytest.raises(ValueError, match="relative"):
        lyrics.open_parent(root, "../song.flac")
    with pytest.raises(ValueError, match="relative"):
        lyrics.open_parent(root, "/song.flac")


def test_concurrent_curated_sidecar_wins(tmp_path):
    descriptor = os.open(tmp_path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        (tmp_path / "song.lrc").symlink_to(tmp_path / "missing")
        assert not lyrics.publish(descriptor, "song", "[00:01]new\n")
        assert (tmp_path / "song.lrc").is_symlink()
        assert not list(tmp_path.glob(".music-lyrics-*"))
    finally:
        os.close(descriptor)


def test_track_replacement_during_fetch_is_not_enriched(tmp_path):
    db, root, state = fixture(tmp_path)

    def replace(_):
        (root / "album/song.flac").write_bytes(b"a different recording")
        return RESULT

    assert lyrics.sync(db, root, state, download=replace)["written"] == 0
    assert not (root / "album/song.lrc").exists()


def test_stale_index_entry_does_not_block_later_tracks(tmp_path):
    db, root, state = fixture(tmp_path, ("a.flac", "b.flac"))
    (root / "a.flac").unlink()
    counts = lyrics.sync(db, root, state, download=lambda _: RESULT)
    assert counts["written"] == 1
    assert counts["skipped"] == 1


def test_selects_configured_library_only(tmp_path):
    db, root, state = fixture(tmp_path)
    with sqlite3.connect(db) as connection:
        connection.execute("INSERT INTO library VALUES (2, '/other')")
        connection.execute(
            "INSERT INTO media_file VALUES ('album/song.flac', 'Wrong song', 'Artist', 'Album', 120, 0, 2)"
        )

    def fetch_only_our_track(track):
        assert track["title"] == "Song"
        return RESULT

    assert lyrics.sync(db, root, state, download=fetch_only_our_track)["written"] == 1


def test_refuses_unindexed_library(tmp_path):
    db, root, state = fixture(tmp_path)
    with sqlite3.connect(db) as connection:
        connection.execute("DELETE FROM library")
    with pytest.raises(ValueError, match="exactly one"):
        lyrics.sync(db, root, state, download=lambda _: pytest.fail("fetch"))


def test_retry_expiry_cannot_starve_later_tracks(tmp_path):
    db, root, state = fixture(tmp_path, tuple(f"{i}.flac" for i in range(8)))
    requested = []

    def miss(track):
        requested.append(track["path"])

    for day in range(16):
        lyrics.sync(db, root, state, limit=1, download=miss, now=day * 86400)
    assert requested == [f"{i}.flac" for i in range(8)] * 2


@pytest.mark.parametrize("failures", [1, 2, 3])
def test_fetch_retries_temporary_overload_but_preserves_failure(monkeypatch, failures):
    sleeps = []
    calls = []

    class Opener:
        @staticmethod
        def open(request, timeout) -> io.BytesIO:
            calls.append((request.full_url, timeout))
            if len(calls) <= failures:
                headers = Message()
                headers["Retry-After"] = "1"
                raise HTTPError(request.full_url, 503, "Busy", headers, io.BytesIO())
            return io.BytesIO(json.dumps(RESULT).encode())

    monkeypatch.setattr(lyrics, "build_opener", lambda _: Opener())
    monkeypatch.setattr(lyrics, "sleep", sleeps.append)
    if failures == 3:
        with pytest.raises(HTTPError, match="503"):
            lyrics.fetch(TRACK)
    else:
        assert lyrics.fetch(TRACK) == RESULT
    assert len(calls) == min(failures + 1, 3)
    assert sleeps == [1, 2, 4][: min(failures + 1, 3)]


@pytest.mark.parametrize(
    "retry_after", ["30", "0", "invalid", "Wed, 21 Oct 2030 07:28:00 GMT"]
)
def test_fetch_does_not_retry_before_long_or_unknown_provider_deadline(
    monkeypatch, retry_after
):
    sleeps = []
    calls = []

    class Opener:
        @staticmethod
        def open(request, timeout) -> io.BytesIO:
            calls.append(timeout)
            headers = Message()
            headers["Retry-After"] = retry_after
            raise HTTPError(
                request.full_url,
                503,
                "Busy",
                headers,
                io.BytesIO(),
            )

    monkeypatch.setattr(lyrics, "build_opener", lambda _: Opener())
    monkeypatch.setattr(lyrics, "sleep", sleeps.append)
    with pytest.raises(HTTPError, match="503"):
        lyrics.fetch(TRACK)
    assert calls == [20]
    assert sleeps == [1]
