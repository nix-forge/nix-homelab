"""Fetch exact LRCLIB matches as shared LRC sidecars without changing audio."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sqlite3
import stat
import time
import unicodedata
import uuid
from contextlib import closing
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

DURATION_TOLERANCE = 2
FIRST_PRINTABLE = 32
HTTP_NOT_FOUND = 404
HTTP_UNAVAILABLE = 503
FETCH_ATTEMPTS = 3
MAX_RETRY_AFTER = 10
MAX_BYTES = 1024 * 1024
LYRIC_SUFFIXES = (".lrc", ".elrc", ".ttml", ".yaml", ".yml", ".srt", ".txt")
TIMESTAMP = re.compile(r"^\[(\d+):([0-5]\d)(?:[.:](\d{1,3}))?\](.*)$")


def normalized(value):
    """Compare identity without dropping edition or featured-artist text.

    Returns:
        Normalized text preserving punctuation and edition suffixes.

    """
    return " ".join(unicodedata.normalize("NFC", value).casefold().split())


def matched_lyrics(track, result):  # ruff: ignore[complex-structure, too-many-return-statements] - Reject malformed candidates before any write.
    """Reject wrong recordings, unsynchronized content and invalid timing.

    Returns:
        Validated LRC text or None for an unsuitable candidate.

    """
    if not isinstance(result, dict) or result.get("instrumental"):
        return None
    for local, remote in (
        ("title", "trackName"),
        ("artist", "artistName"),
        ("album", "albumName"),
    ):
        value = result.get(remote)
        if not isinstance(value, str) or normalized(track[local]) != normalized(value):
            return None
    duration = result.get("duration")
    if (
        isinstance(duration, bool)
        or not isinstance(duration, (float, int))
        or not math.isfinite(duration)
        or abs(duration - track["duration"]) > DURATION_TOLERANCE
    ):
        return None
    lyrics = result.get("syncedLyrics")
    if not isinstance(lyrics, str) or len(lyrics.encode("utf-8")) > MAX_BYTES:
        return None
    if any(ord(char) < FIRST_PRINTABLE and char not in "\r\n\t" for char in lyrics):
        return None
    previous = -1
    text_lines = 0
    for line in lyrics.splitlines():
        if not line.strip():
            continue
        match = TIMESTAMP.fullmatch(line)
        if not match:
            return None
        minute, second, fraction, text = match.groups()
        timestamp = int(minute) * 60 + int(second) + float("0." + (fraction or "0"))
        if timestamp < previous or timestamp > track["duration"] + DURATION_TOLERANCE:
            return None
        previous = timestamp
        text_lines += bool(text.strip())
    return lyrics.strip() + "\n" if text_lines else None


class NoRedirect(HTTPRedirectHandler):
    """Keep lyric requests on the fixed HTTPS provider origin."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # ruff: ignore[too-many-arguments, too-many-positional-arguments, no-self-use, unused-method-argument] - urllib callback signature.
        """Reject redirects instead of forwarding library metadata elsewhere.

        Raises:
            OSError: The provider attempted a redirect.

        """
        raise OSError("Unexpected lyric provider redirect")


def fetch(track):
    """Use only the exact endpoint; bound requests, time and response size.

    Returns:
        Provider JSON or None for a missing recording.

    Raises:
        ValueError: The response exceeds the size limit.
        HTTPError: The provider failed or throttled requests.

    """
    query = urlencode({
        "track_name": track["title"],
        "artist_name": track["artist"],
        "album_name": track["album"],
        "duration": track["duration"],
    })
    request = Request(
        "https://lrclib.net/api/get?" + query,
        headers={"User-Agent": "nix-homelab-lyrics/1.0", "Accept": "application/json"},
    )
    time.sleep(1)
    for attempt in range(FETCH_ATTEMPTS):
        try:
            with build_opener(NoRedirect).open(request, timeout=20) as response:
                body = response.read(MAX_BYTES + 1)
            break
        except HTTPError as error:
            if error.code == HTTP_NOT_FOUND:
                return None
            retry_after = error.headers.get("Retry-After", "2")
            if (
                error.code != HTTP_UNAVAILABLE
                or attempt == FETCH_ATTEMPTS - 1
                or not retry_after.isdecimal()
                or not 1 <= int(retry_after) <= MAX_RETRY_AFTER
            ):
                raise
            error.close()
            time.sleep(max(int(retry_after), 2 ** (attempt + 1)))
    if len(body) > MAX_BYTES:
        raise ValueError("Lyric response exceeds limit")
    return json.loads(body)


def open_parent(root, relative):
    """Open a track directory beneath the library without following symlinks.

    Returns:
        Directory descriptor owned by the caller.

    Raises:
        ValueError: The path is absolute or traverses a parent directory.

    """
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts or not path.name:
        raise ValueError("Invalid library-relative track path")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open(root, flags)
    try:
        for part in path.parts[:-1]:
            child = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
    except BaseException:
        os.close(descriptor)
        raise
    else:
        return descriptor


def has_lyrics(descriptor, stem):
    """Preserve existing lyrics, including case variants and broken symlinks.

    Returns:
        Whether any supported lyric path already exists.

    """
    names = {name.casefold() for name in os.listdir(descriptor)}
    return any((stem + suffix).casefold() in names for suffix in LYRIC_SUFFIXES)


def publish(descriptor, stem, lyrics):
    """Publish a complete file atomically, without replacing an existing file.

    Returns:
        True if a new sidecar was published.

    """
    temporary = ".music-lyrics-" + uuid.uuid4().hex
    fd = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o640,
        dir_fd=descriptor,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(lyrics)
            stream.flush()
            os.fsync(stream.fileno())
        if has_lyrics(descriptor, stem):
            return False
        try:
            os.link(
                temporary,
                stem + ".lrc",
                src_dir_fd=descriptor,
                dst_dir_fd=descriptor,
                follow_symlinks=False,
            )
        except FileExistsError:
            return False
        return True
    finally:
        os.unlink(temporary, dir_fd=descriptor)


def enrich_track(library, track, download, counts):
    """Keep stale local entries from preventing enrichment of other tracks.

    Returns:
        A status distinguishing provider failure, misses and local skips.

    """
    descriptor = None
    try:
        descriptor = open_parent(library, track["path"])
        path = Path(track["path"])
        audio = os.stat(path.name, dir_fd=descriptor, follow_symlinks=False)
        if not stat.S_ISREG(audio.st_mode) or has_lyrics(descriptor, path.stem):
            counts["skipped"] += 1
            return "skip"
        counts["requested"] += 1
        try:
            text = matched_lyrics(track, download(track))
        except OSError, ValueError:
            counts["failed"] += 1
            return "provider-failure"
        current = os.stat(path.name, dir_fd=descriptor, follow_symlinks=False)
        if (audio.st_ino, audio.st_size, audio.st_mtime_ns) != (
            current.st_ino,
            current.st_size,
            current.st_mtime_ns,
        ):
            counts["skipped"] += 1
            return "skip"
        if text:
            counts["written"] += publish(descriptor, path.stem, text)
            return "written"
    except OSError, ValueError:
        counts["skipped"] += 1
        return "skip"
    else:
        return "miss"
    finally:
        if descriptor is not None:
            os.close(descriptor)


def indexed_tracks(database, library, start_after=""):
    """Read bounded pages without holding the server index during network I/O.

    Yields:
        Track identities belonging only to the configured library.

    Raises:
        ValueError: The configured path does not identify one indexed library.

    """
    last_path = start_after
    wrapped = not bool(start_after)
    while True:
        with closing(
            sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)
        ) as source:
            source.row_factory = sqlite3.Row
            libraries = source.execute(
                "SELECT id FROM library WHERE path = ?", (str(library),)
            ).fetchall()
            if len(libraries) != 1:
                raise ValueError("Expected exactly one indexed library with this path")
            rows = source.execute(
                "SELECT path, title, artist, album, duration FROM media_file "
                "WHERE missing=0 AND library_id=? AND path>? "
                "AND (? IS NULL OR path<=?) ORDER BY path LIMIT 256",
                (
                    libraries[0]["id"],
                    last_path,
                    start_after if wrapped and start_after else None,
                    start_after,
                ),
            ).fetchall()
        if not rows:
            if wrapped:
                return
            wrapped = True
            last_path = ""
            continue
        for row in rows:
            yield dict(row)
        last_path = rows[-1]["path"]


def sync(database, library, state, limit=100, *, download=fetch, now=None):  # ruff: ignore[too-many-arguments] - Inject transport and clock for deterministic retry tests.
    """Fill missing sidecars; cache misses and stop on provider failures.

    Returns:
        Aggregate request, write, skip and failure counts.

    """
    now = time.time() if now is None else now
    counts = {"written": 0, "requested": 0, "skipped": 0, "failed": 0}
    with closing(sqlite3.connect(state)) as cache:
        cache.execute(
            "CREATE TABLE IF NOT EXISTS retry (key TEXT PRIMARY KEY, after REAL)"
        )
        cache.execute(
            "CREATE TABLE IF NOT EXISTS cursor (id INTEGER PRIMARY KEY, path TEXT)"
        )
        cache.execute("DELETE FROM retry WHERE after <= ?", (now,))
        cache.commit()
        cursor = cache.execute("SELECT path FROM cursor WHERE id=1").fetchone()
        for track in indexed_tracks(database, library, cursor[0] if cursor else ""):
            if counts["requested"] >= limit:
                break
            if (
                not all(
                    isinstance(track[k], str) and track[k].strip()
                    for k in ("title", "artist", "album")
                )
                or not isinstance(track["duration"], (int, float))
                or not math.isfinite(track["duration"])
                or track["duration"] <= 0
            ):
                counts["skipped"] += 1
                continue
            key = hashlib.sha256(json.dumps(track, sort_keys=True).encode()).hexdigest()
            if cache.execute("SELECT 1 FROM retry WHERE key=?", (key,)).fetchone():
                counts["skipped"] += 1
                continue
            outcome = enrich_track(library, track, download, counts)
            if outcome == "provider-failure":
                break
            if outcome == "skip":
                continue
            cache.execute(
                "INSERT OR REPLACE INTO cursor VALUES (1, ?)", (track["path"],)
            )
            if outcome == "miss":
                cache.execute(
                    "INSERT OR REPLACE INTO retry VALUES (?, ?)", (key, now + 7 * 86400)
                )
            cache.commit()
    return counts


def main():
    """Run one bounded enrichment pass and report aggregate counts.

    Raises:
        SystemExit: A provider or filesystem operation failed.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()
    if args.limit < 1:
        parser.error("--limit must be positive")
    counts = sync(args.database, args.library, args.state, args.limit)
    print(json.dumps(counts, sort_keys=True))
    if counts["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
