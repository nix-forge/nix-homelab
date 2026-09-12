"""Exercise pressure ownership against native qBittorrent using inert magnets."""

import http.cookiejar
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from pressure import Qbit

URL = "http://127.0.0.1:8081"
ACTIVE = "a" * 40
MANUAL = "b" * 40
PASSWORD = "public-pressure-fixture-password"
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def request(path, values=None):
    body = None if values is None else urllib.parse.urlencode(values).encode()
    with client.open(
        urllib.request.Request(URL + "/api/v2/" + path, data=body), timeout=15
    ) as reply:
        return reply.read()


def wait_for_state(info_hash, state):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        torrents = json.loads(request("torrents/info"))
        if any(item["hash"] == info_hash and item["state"] == state for item in torrents):
            return
        time.sleep(0.2)
    raise AssertionError((info_hash, state, torrents))


request("auth/login", {"username": "admin", "password": PASSWORD})
# Discovery must be disabled by native startup configuration, before API use.
preferences = json.loads(request("app/preferences"))
assert not any(preferences[key] for key in ("dht", "pex", "lsd"))
if len(sys.argv) > 1:
    wait_for_state(ACTIVE, "metaDL")
    wait_for_state(MANUAL, "stoppedDL")
    print("Native discovery policy and torrent pause state survived restart")
    sys.exit(0)
for info_hash, stopped in ((ACTIVE, "false"), (MANUAL, "true")):
    request("torrents/add", {"urls": "magnet:?xt=urn:btih:" + info_hash, "stopped": stopped})
wait_for_state(ACTIVE, "metaDL")
wait_for_state(MANUAL, "stoppedDL")
secret = Path("/run/pressure-api.json")
secret.write_text(json.dumps({"username": "admin", "password": PASSWORD}))
secret.chmod(0o600)
pressure = Qbit(URL, secret)
owned = pressure.reconcile(True, [])
assert owned == [ACTIVE], owned
wait_for_state(ACTIVE, "stoppedDL")
wait_for_state(MANUAL, "stoppedDL")
assert pressure.reconcile(False, owned) == []
wait_for_state(ACTIVE, "metaDL")
wait_for_state(MANUAL, "stoppedDL")
print("Native pressure login, owned pause/resume and manual-pause preservation passed")
