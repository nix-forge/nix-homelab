"""Check native Jellyfin shortcut replacement through the reconciliation CLI."""

import json
import subprocess
import tempfile
import urllib.request
from pathlib import Path

password = Path("/run/workflow-password").read_text(encoding="utf-8")
auth = 'MediaBrowser Client="fixture", Device="vm", DeviceId="paths", Version="1"'


def api(path, body=None):
    request = urllib.request.Request(
        "http://127.0.0.1:8096" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": auth, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


token = api("/Users/AuthenticateByName", {"Username": "admin", "Pw": password})[
    "AccessToken"
]
auth += ", Token=" + json.dumps(token)
original = next(
    item for item in api("/Library/VirtualFolders") if item["Name"] == "Movies"
)
old = "/srv/media/library/movies"
new = "/srv/media/library/path replacement"
Path(new).mkdir(mode=0o755)
sentinel = Path(old) / "path-reconciliation-sentinel.txt"
sentinel.write_text(
    "Public disposable fixture: removing a shortcut must preserve media.\n"
)
config = {
    "kind": "jellyfin",
    "url": "http://127.0.0.1:8096",
    "apiKey": token,
    "mode": "managed",
    "settings": {"libraries": {"Movies": {"collectionType": "movies", "paths": [new]}}},
}
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "config.json"

    def reconcile(*args):
        path.write_text(json.dumps(config))
        subprocess.run(
            ["python", "/etc/workflow/integration/reconcile.py", str(path), *args],
            check=True,
            timeout=60,
        )

    reconcile("--dry-run")
    assert next(
        item for item in api("/Library/VirtualFolders") if item["Name"] == "Movies"
    )["Locations"] == [old]
    for desired in [new, old]:
        config["settings"]["libraries"]["Movies"]["paths"] = [desired]
        reconcile()
        reconcile()
        actual = next(
            item for item in api("/Library/VirtualFolders") if item["Name"] == "Movies"
        )
        assert actual["Locations"] == [desired], actual["Locations"]
        assert actual["ItemId"] == original["ItemId"]
        assert actual["LibraryOptions"]["EnableRealtimeMonitor"] is False
        assert sentinel.is_file()
sentinel.unlink()
Path(new).rmdir()
print(
    "Native Jellyfin path replacement preserved the library ID, options, and original files."
)
