"""Native cross-seed linking, client injection and recheck against public media."""

import http.cookiejar
import json
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

KEY = "public-cross-seed-api-key-0123456789"
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def request(port, path, body=None, headers=None, opener=None):
    value = urllib.request.Request(
        f"http://127.0.0.1:{port}" + path,
        data=body,
        headers=headers or {},
    )
    with (opener or urllib.request.build_opener()).open(value, timeout=15) as response:
        data = response.read()
        return json.loads(data) if data[:1] in (b"[", b"{") else data


def qbit(path, body=None):
    return request(
        8081,
        "/api/v2/" + path,
        None if body is None else urllib.parse.urlencode(body).encode(),
        opener=client,
    )


def wait_for(function):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        value = function()
        if value:
            return value
        time.sleep(2)
    raise AssertionError("Native cross-seed workflow did not complete")


qbit("auth/login", {"username": "admin", "password": "public-cross-seed-password"})
assert qbit("app/version").startswith(b"v")
preferences = qbit("app/preferences")
assert all(preferences[key] is False for key in ("dht", "pex", "lsd"))
stats = request(18091, "/stats")
qbit("torrents/add", {"urls": "http://127.0.0.1:18091/original.torrent"})


def complete(info_hash):
    return next(
        (
            torrent
            for torrent in qbit("torrents/info")
            if torrent["hash"] == info_hash
            and torrent["progress"] == 1
            and torrent["state"] in ("uploading", "stalledUP", "queuedUP", "forcedUP")
        ),
        None,
    )


original = wait_for(lambda: complete(stats["original"]))
source = Path(original["content_path"])
assert source.is_file() and source.stat().st_nlink == 1
webseed_bytes = request(18091, "/stats")["webseedBytes"]
assert webseed_bytes > 0
payload = json.dumps({"infoHash": stats["original"], "ignoreExcludeRecentSearch": True}).encode()
try:
    request(2468, "/api/webhook", payload, {"Content-Type": "application/json"})
except urllib.error.HTTPError as error:
    assert error.code == 401
else:
    raise AssertionError("Unauthenticated cross-seed webhook was accepted")
request(18091, "/enable", b"")
request(
    2468,
    "/api/webhook",
    payload,
    {"Content-Type": "application/json", "X-Api-Key": KEY},
)
candidate = wait_for(lambda: complete(stats["candidate"]))
target = Path(candidate["content_path"])
assert target.is_relative_to("/srv/media/downloads/cross-seed")
assert target != source and target.is_file()
assert (target.stat().st_dev, target.stat().st_ino) == (
    source.stat().st_dev,
    source.stat().st_ino,
)
assert source.stat().st_nlink >= 2
assert candidate["completed"] == source.stat().st_size
assert candidate["amount_left"] == 0
assert len(qbit("torrents/info")) == 2
final = request(18091, "/stats")
assert final["candidateGrabs"] > 0 and final["searches"] > 0
assert final["webseedBytes"] == webseed_bytes
subprocess.run(["systemctl", "restart", "qbittorrent.service"], check=True, timeout=30)


def restarted():
    try:
        qbit("auth/login", {"username": "admin", "password": "public-cross-seed-password"})
        preferences = qbit("app/preferences")
    except urllib.error.URLError:
        return False
    assert all(preferences[key] is False for key in ("dht", "pex", "lsd"))
    return True


wait_for(restarted)
print(
    "Native cross-seed searched, matched, hardlinked and injected a second torrent; qBittorrent rechecked existing bytes without another webseed transfer"
)
