"""Pause only owned downloads while the actual media filesystem is pressured."""

import http.cookiejar
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError("credential-bearing redirects are forbidden")


class API:
    def __init__(self, url):
        self.url = url.rstrip("/")
        self.client = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
            NoRedirect(),
        )

    def request(self, path, fields=None):
        data = None if fields is None else urllib.parse.urlencode(fields).encode()
        request = urllib.request.Request(
            self.url + path, data=data, headers={"Referer": self.url + "/"}
        )
        with self.client.open(request, timeout=20) as response:
            return response.read()


class Qbit(API):
    def __init__(self, url, secret):
        super().__init__(url)
        credentials = json.loads(Path(secret).read_text())
        if self.request("/api/v2/auth/login", credentials).strip() not in (b"Ok.", b""):
            raise RuntimeError("login failed")
        # Newer qBittorrent returns an empty 204; older releases return "Ok.".
        # Neither body alone establishes that the cookie grants API access.
        if not isinstance(json.loads(self.request("/api/v2/torrents/info")), list):
            raise RuntimeError("authenticated torrent API unavailable")

    def reconcile(self, pressured, owned):
        torrents = json.loads(self.request("/api/v2/torrents/info"))
        current = {torrent["hash"]: torrent["state"] for torrent in torrents}
        if pressured:
            active = {
                key
                for key, state in current.items()
                if state
                in {
                    "downloading",
                    "stalledDL",
                    "queuedDL",
                    "metaDL",
                    "forcedDL",
                    "allocating",
                }
            }
            if active:
                self.request("/api/v2/torrents/stop", {"hashes": "|".join(sorted(active))})
            return sorted(set(owned) | active)
        resume = set(owned) & {key for key, state in current.items() if state == "stoppedDL"}
        if resume:
            self.request("/api/v2/torrents/start", {"hashes": "|".join(sorted(resume))})
        return []


class Sab(API):
    def __init__(self, url, secret):
        super().__init__(url)
        self.key = Path(secret).read_text().strip()

    def call(self, mode):
        # POST keeps the API key out of URL/access logs.
        return json.loads(
            self.request("/api", {"apikey": self.key, "mode": mode, "output": "json"})
        )

    def reconcile(self, pressured, owned):
        paused = self.call("queue")["queue"]["paused"]
        if pressured and not paused:
            if not self.call("pause")["status"]:
                raise RuntimeError("pause rejected")
            return True
        if not pressured and owned:
            if paused and not self.call("resume")["status"]:
                raise RuntimeError("resume rejected")
            return False
        return owned


def pressured(config, previous):
    path = Path(config["path"])
    if not all(os.path.ismount(mount) for mount in config["requiredMounts"]):
        return True
    # A missing directory never falls back to a parent's free-space reading.
    try:
        stat = os.statvfs(path)
    except OSError:
        return True
    available = stat.f_bavail * stat.f_frsize
    threshold = config["resumeBytes"] if previous else config["pauseBytes"]
    return available < threshold


def reconcile(config, journal, credentials):
    journal = Path(journal)
    state = json.loads(journal.read_text()) if journal.exists() else {}
    pressure = pressured(config, state.get("pressured", False))
    state["pressured"] = pressure
    failures = False
    for name, client in config["clients"].items():
        try:
            constructor = {"qbittorrent": Qbit, "sabnzbd": Sab}[name]
            api = constructor(client["url"], Path(credentials) / name)
            state[name] = api.reconcile(
                pressure, state.get(name, [] if name == "qbittorrent" else False)
            )
        except Exception:  # noqa: BLE001 - never expose credential-bearing exception values
            # Preserve ownership on timeout/failure for a subsequent attempt.
            failures = True
    temporary = journal.with_suffix(".tmp")
    temporary.write_text(json.dumps(state) + "\n")
    temporary.chmod(0o600)
    temporary.replace(journal)
    if failures:
        raise RuntimeError("one or more downloader APIs unavailable")


def main():
    try:
        reconcile(
            json.loads(Path(sys.argv[1]).read_text()),
            sys.argv[2],
            os.environ["CREDENTIALS_DIRECTORY"],
        )
    except Exception:  # noqa: BLE001 - never expose credential-bearing exception values
        print(
            "Storage pressure check failed; inspect mount and downloader health locally.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
