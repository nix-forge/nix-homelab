"""Public disposable native audio authentication and persistence assertions."""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PASSWORD = "public-disposable-audio-password"


def request(base, path, value=None, headers=None, method=None, parse=True):
    data = None if value is None else json.dumps(value).encode()
    headers = {"Content-Type": "application/json", **(headers or {})}
    deadline = time.monotonic() + 75
    while True:
        try:
            with urllib.request.urlopen(
                urllib.request.Request(
                    base + path, data=data, headers=headers, method=method
                ),
                timeout=15,
            ) as response:
                return json.load(response) if parse else response.read()
        except urllib.error.HTTPError as error:
            # Repeated assertions share one loopback client. Keep native login
            # throttling enabled and wait only for explicit rejected logins.
            if (
                path != "/auth/login"
                or error.code != 429
                or time.monotonic() >= deadline
            ):
                raise
            error.close()
            time.sleep(5)


navidrome = "http://127.0.0.1:4533"
login = request(
    navidrome, "/auth/login", {"username": "listener", "password": PASSWORD}
)
assert login["isAdmin"] is False, login
admin = request(navidrome, "/auth/login", {"username": "admin", "password": PASSWORD})
users = request(
    navidrome, "/api/user", headers={"X-ND-Authorization": "Bearer " + admin["token"]}
)
assert {user["userName"] for user in users} == {"admin", "listener"}, users

abs_url = "http://127.0.0.1:8000"
listener = request(abs_url, "/login", {"username": "listener", "password": PASSWORD})[
    "user"
]
assert listener["type"] == "user", listener
assert listener["isActive"] is True, listener
for permission in ("download", "upload", "update", "delete"):
    assert listener["permissions"][permission] is False, listener
libraries = request(
    abs_url,
    "/api/libraries",
    headers={"Authorization": "Bearer " + listener["accessToken"]},
)["libraries"]
assert {library["name"] for library in libraries} == {"Audiobooks", "Podcasts"}, (
    libraries
)
for library in libraries:
    expected = (
        "/srv/media/library/audiobooks"
        if library["name"] == "Audiobooks"
        else "/srv/media/downloads/podcasts"
    )
    assert [folder["fullPath"] for folder in library["folders"]] == [expected], library
print("Native audio accounts, libraries and permissions verified")


query = urllib.parse.urlencode({
    "u": "listener",
    "p": PASSWORD,
    "v": "1.16.1",
    "c": "homelab-fixture",
    "f": "json",
})
for _attempt in range(40):
    response = request(navidrome, "/rest/getRandomSongs.view?" + query)
    songs = response["subsonic-response"].get("randomSongs", {}).get("song", [])
    if songs:
        break
    time.sleep(1)
assert len(songs) == 1, response
assert songs[0]["title"] == "Public fixture", response
stream_url = (
    navidrome
    + "/rest/stream.view?"
    + query
    + "&format=raw&id="
    + urllib.parse.quote(songs[0]["id"])
)
with urllib.request.urlopen(stream_url, timeout=15) as stream:
    assert stream.read() == Path("/etc/audio-fixture.flac").read_bytes()
print("Native music discovery and exact original audio playback verified")


books = next(library for library in libraries if library["name"] == "Audiobooks")
headers = {"Authorization": "Bearer " + listener["accessToken"]}
items_url = "/api/libraries/" + books["id"] + "/items"
items = request(abs_url, items_url, headers=headers)["results"]
if not items:
    admin = request(abs_url, "/login", {"username": "admin", "password": PASSWORD})[
        "user"
    ]
    request(
        abs_url,
        "/api/libraries/" + books["id"] + "/scan",
        {},
        headers={"Authorization": "Bearer " + admin["accessToken"]},
        parse=False,
    )
    for _attempt in range(40):
        items = request(abs_url, items_url, headers=headers)["results"]
        if items:
            break
        time.sleep(1)
assert len(items) == 1, items
item_id = items[0]["id"]
progress_url = "/api/me/progress/" + item_id
if "--initialize-progress" in sys.argv:
    request(
        abs_url,
        progress_url,
        {"currentTime": 1, "duration": 3, "progress": 1 / 3, "isFinished": False},
        headers=headers,
        method="PATCH",
        parse=False,
    )
progress = request(abs_url, progress_url, headers=headers)
assert progress["currentTime"] == 1, progress
session = request(
    abs_url,
    "/api/items/" + item_id + "/play",
    {
        "supportedMimeTypes": ["audio/flac"],
        "mediaPlayer": "html5",
        "forceDirectPlay": True,
    },
    headers=headers,
)
track_url = session["audioTracks"][0]["contentUrl"]
with urllib.request.urlopen(
    urllib.request.Request(
        abs_url + track_url, headers={**headers, "Range": "bytes=0-99"}
    ),
    timeout=15,
) as stream:
    assert stream.status == 206
    assert stream.read() == Path("/etc/audio-fixture.flac").read_bytes()[:100]
print("Native audiobook scan, progress persistence and ranged playback verified")
