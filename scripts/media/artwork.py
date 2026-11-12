"""Maintain canonical album covers for the shared music library."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import sqlite3
import subprocess
import tempfile
import time
import unicodedata
import uuid
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable
from pathlib import Path
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

from PIL import Image

UUID_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
MIN_MATCH_SCORE = 95
MAX_YEAR_DIFFERENCE = 1
MIN_PIXELS = 1000
MAX_ASPECT_RATIO = 1.1
MAX_BYTES = 20 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 40_000_000


def fetch(url: str) -> bytes:
    """Download bounded artwork from the archive over HTTPS.

    Returns:
        Encoded image or JSON response bytes.

    Raises:
        ValueError: The scheme or response size is unsupported.

    """
    if urlparse(url).scheme != "https":
        message = "Artwork requires HTTPS"
        raise ValueError(message)
    time.sleep(1)  # Keep archive requests serial and rate-limited.
    request = Request(url, headers={"User-Agent": "nix-homelab-artwork/1.0"})
    with urlopen(request, timeout=25) as response:
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        message = "Artwork exceeds size limit"
        raise ValueError(message)
    return data


def canonical_image(
    group_id: str, download: Callable[[str], bytes] = fetch
) -> tuple[bytes, str] | None:
    """Choose approved canonical front artwork with sufficient decoded resolution.

    Returns:
        Image bytes and provenance URL, or None when no cover qualifies.

    """
    group_id = str(uuid.UUID(group_id))
    listing = json.loads(
        download(f"https://coverartarchive.org/release-group/{group_id}")
    )
    # The selected release-group image represents the album, rather than a
    # particular physical edition. Never fall back to backs, discs or stickers.
    for candidate in listing.get("images", []):
        if candidate.get("front") is not True or candidate.get("approved") is not True:
            continue
        url = candidate.get("thumbnails", {}).get("1200") or candidate.get("image")
        if not url:
            continue
        parsed = urlparse(url)
        if parsed.hostname != "coverartarchive.org" or parsed.scheme not in {
            "http",
            "https",
        }:
            continue
        url = parsed._replace(scheme="https").geturl()
        data = download(url)
        with Image.open(io.BytesIO(data)) as image:
            image.load()
            width, height = image.size
            if (
                min(width, height) < MIN_PIXELS
                or max(width, height) / min(width, height) > MAX_ASPECT_RATIO
            ):
                continue
            # Keep the original JPEG bytes; convert other formats once for
            # consistent sidecar support across music servers.
            if image.format != "JPEG":
                output = io.BytesIO()
                image.convert("RGB").save(output, "JPEG", quality=95)
                data = output.getvalue()
        return data, url
    return None


def normalized_name(value: str) -> str:
    """Normalize punctuation and case only for conservative identity checks.

    Returns:
        The comparable artist or album name.

    """
    value = unicodedata.normalize("NFKC", value).casefold().replace("\u2019", "'")
    return re.sub(r"[^\w]+", " ", value.replace("'", "")).strip()


def resolve_release_group(
    artist: str,
    title: str,
    year: int | None,
    download: Callable[[str], bytes] = fetch,
) -> str | None:
    """Resolve one exact title, artist and release year from MusicBrainz.

    Returns:
        A unique release-group MBID, or None when the identity is ambiguous.

    """
    if not artist or not title or any(c in artist + title for c in ('"', "\\")):
        return None
    query = f'releasegroup:"{title}" AND artist:"{artist}"'
    url = "https://musicbrainz.org/ws/2/release-group/?" + urlencode({
        "query": query,
        "fmt": "json",
        "limit": 100,
    })
    matches = []
    for candidate in json.loads(download(url)).get("release-groups", []):
        if int(candidate.get("score", 0)) < MIN_MATCH_SCORE:
            continue
        credit = "".join(
            part.get("name", "") if isinstance(part, dict) else str(part)
            for part in candidate.get("artist-credit", [])
        )
        if normalized_name(candidate.get("title", "")) != normalized_name(title):
            continue
        if normalized_name(credit) != normalized_name(artist):
            continue
        released = candidate.get("first-release-date", "")[:4]
        if (
            year
            and released.isdigit()
            and abs(int(released) - year) > MAX_YEAR_DIFFERENCE
        ):
            continue
        value = candidate.get("id")
        if not value or not UUID_PATTERN.fullmatch(value):
            continue
        matches.append(str(uuid.UUID(value)))
    unique = set(matches)
    return unique.pop() if len(unique) == 1 else None


def unresolved_albums(
    database: Path, root: Path
) -> list[tuple[Path, str, str, int | None, str]]:
    """Find untagged album folders without sharing art across album identities.

    Returns:
        Folders with one album identity and enough metadata to search exactly.

    Raises:
        ValueError: An indexed music path escapes the configured library.

    """
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        rows = connection.execute("""
            SELECT DISTINCT a.id, a.name, a.album_artist, a.min_year,
                a.mbz_release_group_id, m.path
            FROM album a JOIN media_file m ON m.album_id = a.id
            WHERE a.missing = 0 AND m.missing = 0
        """)
        folders = {}
        for album_id, title, artist, year, group, relative in rows:
            folder = (root / relative).parent.resolve()
            if not folder.is_relative_to(root.resolve()):
                message = "Music path escapes library"
                raise ValueError(message)
            folders.setdefault(folder, {})[album_id] = (
                group or "",
                artist,
                title,
                year,
            )
        return [
            (folder, artist, title, year, album_id)
            for folder, albums in folders.items()
            if len(albums) == 1
            for album_id, (group, artist, title, year) in albums.items()
            if not group and artist and title
        ]


def resolved_group_for_folder(
    folder: Path,
    identity: tuple[str, str, int | None],
    state: Path,
    *,
    download: Callable[[str], bytes] = fetch,
    now: float | None = None,
) -> str | None:
    """Reuse a validated identity until its monthly MusicBrainz recheck.

    Returns:
        The exact resolved release-group identifier, if available.

    """
    now = time.time() if now is None else now
    key = hashlib.sha256(str(folder).encode()).hexdigest()
    receipt = state / f"{key}.identity.json"
    previous = json.loads(receipt.read_text()) if receipt.exists() else {}
    artist, title, year = identity
    if (
        previous.get("identity") == list(identity)
        and now - previous.get("checked", 0) < 30 * 86400
    ):
        return previous.get("group_id")
    group = resolve_release_group(artist, title, year, download)
    if group:
        atomic_write(
            receipt,
            json.dumps({
                "identity": list(identity),
                "group_id": group,
                "checked": now,
            }).encode(),
        )
    return group


def atomic_write(destination: Path, data: bytes) -> None:
    """Replace a sidecar only after its complete contents are flushed."""
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
            Path(temporary).chmod(0o644)
            Path(temporary).replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def sync_album(
    folder: Path,
    group_id: str,
    state: Path,
    download: Callable[[str], bytes] = fetch,
    now: float | None = None,
) -> str:
    """Refresh managed covers while preserving independently supplied artwork.

    Returns:
        The reconciliation outcome for this album folder.

    """
    now = time.time() if now is None else now
    cover = folder / "cover.jpg"
    receipt = state / (hashlib.sha256(str(folder).encode()).hexdigest() + ".json")
    previous = json.loads(receipt.read_text()) if receipt.exists() else {}
    if cover.is_symlink():
        return "preserved"
    if cover.exists():
        digest = hashlib.sha256(cover.read_bytes()).hexdigest()
        if digest != previous.get("sha256"):
            return "preserved"
        if (
            previous.get("group_id") == group_id
            and now - previous.get("checked", 0) < 30 * 86400
        ):
            return "cached"
    # A separately supplied cover in another supported format is also curated.
    if not cover.exists() and any(
        p.is_file()
        for p in folder.iterdir()
        if p.stem.lower() in {"cover", "folder", "front"}
        and p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    ):
        return "preserved"
    result = canonical_image(group_id, download)
    if result is None:
        return "unavailable"
    data, source = result
    # Save recoverable previous bytes before updating a managed image.
    if cover.exists():
        backup = state / (hashlib.sha256(cover.read_bytes()).hexdigest() + ".jpg")
        if not backup.exists():
            atomic_write(backup, cover.read_bytes())
    atomic_write(cover, data)
    atomic_write(
        receipt,
        json.dumps({
            "group_id": group_id,
            "source": source,
            "checked": now,
            "sha256": hashlib.sha256(data).hexdigest(),
        }).encode(),
    )
    return "updated"


def library_albums(database: Path, root: Path) -> list[tuple[Path, str]]:
    """Read exact album identifiers and reject ambiguous or escaping folders.

    Returns:
        Unambiguous album folders paired with their release-group identifiers.

    Raises:
        ValueError: An indexed music path escapes the configured library.

    """
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        rows = connection.execute("""
            SELECT DISTINCT m.path, a.mbz_release_group_id
            FROM album a JOIN media_file m ON m.album_id = a.id
            WHERE a.missing = 0 AND m.missing = 0
        """)
        folders = {}
        for relative, group in rows:
            folder = (root / relative).parent.resolve()
            if not folder.is_relative_to(root.resolve()):
                message = "Music path escapes library"
                raise ValueError(message)
            folders.setdefault(folder, set()).add(group or "")
        # Mixed album folders are ambiguous, so do not assign one album's art.
        return [
            (p, next(iter(ids)))
            for p, ids in folders.items()
            if len(ids) == 1 and "" not in ids
        ]
    finally:
        connection.close()


def refresh_album(
    database: Path,
    group: str,
    executable: Path,
    configuration: Path,
    album_id: str | None = None,
) -> None:
    """Queue canonical artwork resolution for each edition of a known album."""
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        if album_id:
            ids = [
                row[0]
                for row in connection.execute(
                    "SELECT id FROM album WHERE id = ? AND missing = 0",
                    (album_id,),
                )
            ]
        else:
            ids = [
                row[0]
                for row in connection.execute(
                    "SELECT id FROM album WHERE mbz_release_group_id = ? AND missing = 0",
                    (group,),
                )
            ]
    if ids:
        subprocess.run(
            [
                str(executable),
                "--configfile",
                str(configuration),
                "--nobanner",
                "--loglevel",
                "error",
                "artwork",
                "refresh",
                "al",
                *ids,
            ],
            check=True,
            capture_output=True,
        )


def main() -> None:
    """Reconcile library artwork and leave failed downloads retryable.

    Raises:
        SystemExit: At least one download or write failed.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--navidrome", type=Path)
    parser.add_argument("--navidrome-config", type=Path)
    args = parser.parse_args()
    if bool(args.navidrome) != bool(args.navidrome_config):
        parser.error("--navidrome and --navidrome-config must be supplied together")
    args.state.mkdir(parents=True, exist_ok=True)
    failures = 0
    albums = [
        (folder, group, None)
        for folder, group in library_albums(args.database, args.library)
    ]
    for folder, artist, title, year, album_id in unresolved_albums(
        args.database, args.library
    ):
        try:
            group = resolved_group_for_folder(folder, (artist, title, year), args.state)
            if group:
                albums.append((folder, group, album_id))
        except Exception as error:
            failures += 1
            print(f"retry identity: {type(error).__name__}", flush=True)
    for folder, group, album_id in albums:
        try:
            result = sync_album(folder, group, args.state)
            if args.navidrome and result in {"updated", "cached"}:
                refresh_album(
                    args.database,
                    group,
                    args.navidrome,
                    args.navidrome_config,
                    album_id,
                )
            print(f"{result}: {group}", flush=True)
        except Exception as error:
            failures += 1
            print(f"retry: {group}: {type(error).__name__}", flush=True)
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
