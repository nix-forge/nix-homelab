"""Real native API acceptance. All content and credentials are disposable fixtures."""

import http.cookiejar
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

KEY = Path("/run/workflow-api-key").read_text(encoding="utf-8")
PASSWORD = Path("/run/workflow-password").read_text(encoding="utf-8")
JELLY_AUTH = (
    'MediaBrowser Client="fixture", Device="vm", DeviceId="fixture", Version="1"'
)


def api(port, path, body=None, headers=None, method=None, opener=None):
    payload = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}" + path,
        data=payload,
        headers={"Content-Type": "application/json", **(headers or {})},
        method=method,
    )
    try:
        with (opener or urllib.request.build_opener()).open(
            request, timeout=20
        ) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        # Only this disposable VM uses the helper. Production reconciliation never
        # prints API bodies, which may contain provider credentials.
        raise AssertionError(
            f"Fixture API {request.method} {path}: HTTP {error.code} "
            + error.read(2048).decode(errors="replace")
        ) from error


def wait_for(function, timeout=120):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        result = function()
        if result:
            return result
        time.sleep(2)
    raise AssertionError("Timed out waiting for API-visible state")


def radarr(path, body=None, method=None):
    return api(7878, "/api/v3/" + path, body, {"X-Api-Key": KEY}, method)


roots = radarr("rootfolder")
assert len(roots) == 1
assert roots[0]["path"] == "/srv/media/library/movies"
admin = api(
    8096,
    "/Users/AuthenticateByName",
    {"Username": "admin", "Pw": PASSWORD},
    {"Authorization": JELLY_AUTH},
)
viewer = api(
    8096,
    "/Users/AuthenticateByName",
    {"Username": "viewer", "Pw": PASSWORD},
    {"Authorization": JELLY_AUTH},
)
assert not viewer["User"]["Policy"]["IsAdministrator"]
assert not viewer["User"]["Policy"]["EnableContentDeletion"]
jelly_headers = {
    "Authorization": JELLY_AUTH + ", Token=" + json.dumps(admin["AccessToken"])
}
viewer_headers = {
    "Authorization": JELLY_AUTH + ", Token=" + json.dumps(viewer["AccessToken"])
}
libraries = api(8096, "/Library/VirtualFolders", headers=jelly_headers)
assert len(libraries) == 1
assert libraries[0]["Name"] == "Movies"
portal = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
)
api(
    5055,
    "/api/v1/auth/jellyfin",
    {"username": "admin", "password": PASSWORD},
    opener=portal,
)
servers = api(5055, "/api/v1/settings/radarr", opener=portal)
assert len(servers) == 1
assert servers[0]["activeDirectory"] == roots[0]["path"]
assert servers[0]["activeProfileName"] == "HD-1080p"
print("Native Radarr roots, Jellyfin accounts/libraries and Seerr destination verified")

# Configure real provider schemas through supported application APIs. The small
# synthetic video intentionally has no production minimum-size policy.
for definition in radarr("qualitydefinition"):
    definition["minSize"] = 0
    radarr("qualitydefinition/" + str(definition["id"]), definition, "PUT")


def provider(endpoint, implementation, fields, extra):
    template = next(
        value
        for value in radarr(endpoint + "/schema")
        if value["implementation"] == implementation
    )
    template.pop("id", None)
    template.update(extra)
    for field in template["fields"]:
        if field["name"] in fields:
            field["value"] = fields[field["name"]]
    return radarr(endpoint, template)


provider(
    "downloadclient",
    "QBittorrent",
    {
        "host": "127.0.0.1",
        "port": 8081,
        "username": "admin",
        "password": PASSWORD,
        "movieCategory": "radarr",
    },
    {
        "name": "Public fixture downloader",
        "enable": True,
        "priority": 1,
        "removeCompletedDownloads": False,
        "removeFailedDownloads": False,
    },
)
provider(
    "indexer",
    "Torznab",
    {
        "baseUrl": "http://127.0.0.1:18090",
        "apiPath": "/api",
        "apiKey": "publicfixture",
        "categories": [2000],
        "minimumSeeders": 1,
    },
    {
        "name": "Public fixture indexer",
        "enableRss": False,
        "enableAutomaticSearch": True,
        "enableInteractiveSearch": True,
        "priority": 1,
    },
)

media_request = api(
    5055,
    "/api/v1/request",
    {"mediaType": "movie", "mediaId": 999999, "is4k": False},
    opener=portal,
)
assert media_request["media"]["tmdbId"] == 999999
movie = wait_for(
    lambda: next((item for item in radarr("movie") if item["tmdbId"] == 999999), None)
)
print("Seerr request created the intended Radarr movie through real APIs")

# A real client fetches a torrent over HTTP and verifies its webseed pieces.
# No test code writes or links files into the manager's library.
qbit = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
)


def qrequest(path, values=None):
    payload = None if values is None else urllib.parse.urlencode(values).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:8081/api/v2/" + path, data=payload
    )
    with qbit.open(request, timeout=20) as response:
        content = response.read()
        return (
            json.loads(content) if content and content[:1] in {b"[", b"{"} else content
        )


qrequest("auth/login", {"username": "admin", "password": PASSWORD})
preferences = qrequest("app/preferences")
assert all(preferences[key] is False for key in ("dht", "pex", "lsd"))
# Radarr's search triggered by Seerr must send this torrent to qBittorrent.
torrents = wait_for(lambda: qrequest("torrents/info"))
wait_for(lambda: qrequest("torrents/info")[0]["progress"] == 1)
source = Path(qrequest("torrents/info")[0]["content_path"])
assert source.is_file()
assert source.stat().st_size > 0
print("qBittorrent completed and hash-verified generated local media")

# Poll through the application's public command API rather than waiting for its
# production scheduler. Import decisions and filesystem operations remain Radarr's.
refresh = radarr("command", {"name": "RefreshMonitoredDownloads"})
wait_for(lambda: radarr("command/" + str(refresh["id"]))["status"] == "completed")
radarr("command", {"name": "ProcessMonitoredDownloads"})
imported = wait_for(lambda: radarr("moviefile?movieId=" + str(movie["id"])))
target = Path(imported[0]["path"])
assert target.is_file()
assert target.stat().st_ino == source.stat().st_ino
assert target.stat().st_dev == source.stat().st_dev
assert source.stat().st_nlink >= 2
print("Radarr completed-download handling imported a seeding hardlink")

api(8096, "/Library/Refresh", headers=jelly_headers, method="POST")


def scanned_movie():
    items = api(
        8096,
        "/Items?"
        + urllib.parse.urlencode({
            "Recursive": "true",
            "IncludeItemTypes": "Movie",
            "Fields": "Path",
        }),
        headers=jelly_headers,
    )["Items"]
    return next((item for item in items if item.get("Path") == str(target)), None)


item = wait_for(scanned_movie)
try:
    deletion = urllib.request.Request(
        "http://127.0.0.1:8096/Items/" + item["Id"],
        headers=viewer_headers,
        method="DELETE",
    )
    urllib.request.urlopen(deletion, timeout=20).close()
except urllib.error.HTTPError as error:
    assert error.code in {401, 403}
else:
    raise AssertionError("Non-admin viewer was allowed to delete media")
assert target.is_file()
request = urllib.request.Request(
    f"http://127.0.0.1:8096/Videos/{item['Id']}/stream?static=true",
    headers={**viewer_headers, "Range": "bytes=0-1023"},
)
with urllib.request.urlopen(request, timeout=20) as response:
    assert response.status == 206
    assert response.read() == source.read_bytes()[:1024]
print(
    "Jellyfin scanned the imported movie and served exact ranged media bytes to viewer"
)

stats = api(18090, "/stats")
assert all(stats[name] > 0 for name in ("search", "torrent", "webseed"))
print("External fixture observed search, torrent grab and webseed transfer")

Path("/run/workflow-proof.json").write_text(
    json.dumps({
        "movieId": movie["id"],
        "viewerId": viewer["User"]["Id"],
        "itemId": item["Id"],
        "requestId": media_request["id"],
        "torrentHash": torrents[0]["hash"],
    }),
    encoding="utf-8",
)
