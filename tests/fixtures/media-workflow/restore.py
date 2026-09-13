"""Restore genuine application state in the disposable workflow VM only."""

import http.cookiejar
import json
import shutil
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path


def run(*args):
    subprocess.run(args, check=True, timeout=180)


def api(port, path, body=None, headers=None, opener=None):
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with (opener or urllib.request.build_opener()).open(request, timeout=15) as response:
        data = response.read()
        return json.loads(data) if data else None


def ready(port, path):
    for _ in range(60):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}" + path, timeout=15) as response:
                if path != "/health" or response.read().strip() == b"Healthy":
                    return
        except (OSError, ValueError):
            pass
        time.sleep(2)
    raise AssertionError("Restored application did not become ready")


proof = json.loads(Path("/run/workflow-proof.json").read_text())
run("systemctl", "start", "restic-backups-workflow.service")
for name in ("radarr", "jellyfin", "seerr", "qbittorrent"):
    run("systemctl", "is-active", name + ".service")
assert not Path("/var/lib/homelab-recovery/snapshot").exists()
run("restic-workflow", "check", "--read-data")
run("restic-workflow", "restore", "latest", "--target", "/var/lib/workflow-restored")
staging = Path("/var/lib/workflow-restored/var/lib/homelab-recovery/snapshot")
manifest = json.loads((staging / "manifest.json").read_text())
units = sorted({unit for item in manifest.values() for unit in item["units"]})
run("systemctl", "stop", *units)
# Keep all reconcilers stopped while proving restored state. Otherwise onboarding
# could recreate missing objects and hide an incomplete backup.
for item in manifest.values():
    for entry in item["paths"]:
        target = Path(entry["resolved"])
        assert str(target).startswith("/var/lib/") and target != Path("/var/lib")
        if target.exists():
            shutil.rmtree(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        run("cp", "--archive", "--", str(staging / entry["copy"]), str(target))
run("systemctl", "start", "radarr", "jellyfin", "seerr", "qbittorrent")
ready(8096, "/health")
ready(5055, "/api/v1/status")
ready(7878, "/ping")
ready(8081, "/")
key = Path("/run/workflow-api-key").read_text()
password = Path("/run/workflow-password").read_text()
movies = api(7878, "/api/v3/movie", headers={"X-Api-Key": key})
assert any(movie["id"] == proof["movieId"] and movie["hasFile"] for movie in movies)
authorization = 'MediaBrowser Client="restore", Device="vm", DeviceId="restore", Version="1"'
viewer = api(
    8096,
    "/Users/AuthenticateByName",
    {"Username": "viewer", "Pw": password},
    {"Authorization": authorization},
)
assert viewer["User"]["Id"] == proof["viewerId"]
assert not viewer["User"]["Policy"]["IsAdministrator"]
assert not viewer["User"]["Policy"]["EnableContentDeletion"]
viewer_headers = {"Authorization": authorization + ", Token=" + json.dumps(viewer["AccessToken"])}
item = api(
    8096,
    "/Users/" + proof["viewerId"] + "/Items/" + proof["itemId"],
    headers=viewer_headers,
)
assert item["Id"] == proof["itemId"]
portal = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
api(
    5055,
    "/api/v1/auth/jellyfin",
    {"username": "admin", "password": password},
    opener=portal,
)
request = api(5055, "/api/v1/request/" + str(proof["requestId"]), opener=portal)
assert request["media"]["tmdbId"] == 999999
servers = api(5055, "/api/v1/settings/radarr", opener=portal)
assert len(servers) == 1 and servers[0]["name"] == "movies"
qbit = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
login = urllib.request.Request(
    "http://127.0.0.1:8081/api/v2/auth/login",
    data=urllib.parse.urlencode({"username": "admin", "password": password}).encode(),
)
with qbit.open(login, timeout=15):
    pass
with qbit.open("http://127.0.0.1:8081/api/v2/app/preferences", timeout=15) as response:
    preferences = json.load(response)
assert all(preferences[key] is False for key in ("dht", "pex", "lsd"))
with qbit.open("http://127.0.0.1:8081/api/v2/torrents/info", timeout=15) as response:
    torrents = json.load(response)
torrent = next(item for item in torrents if item["hash"] == proof["torrentHash"])
source = Path(torrent["content_path"])
stream = urllib.request.Request(
    f"http://127.0.0.1:8096/Videos/{proof['itemId']}/stream?static=true",
    headers={**viewer_headers, "Range": "bytes=0-1023"},
)
with urllib.request.urlopen(stream, timeout=20) as response:
    assert response.status == 206
    assert response.read() == source.read_bytes()[:1024]
print(
    "Restic restored native requests, movie state, restricted user, library item and torrent resume state"
)
