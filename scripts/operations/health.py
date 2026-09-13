"""Private operational status without application data or credentials."""

import json
import os
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def status(config):
    checks = {}
    if config["backup"]:
        try:
            age = time.time() - Path(config["stamp"]).stat().st_mtime
            checks["backup"] = 0 <= age <= config["maxAge"]
        except OSError:
            checks["backup"] = False
    if config.get("pressureFile"):
        try:
            pressure = Path(config["pressureFile"])
            age = time.time() - pressure.stat().st_mtime
            checks["pressure"] = (
                pressure.read_text() == "ready\n" and 0 <= age <= config["pressureMaxAge"]
            )
        except OSError:
            checks["pressure"] = False
    checks["storage"] = all(os.path.ismount(path) for path in config["mounts"])
    try:
        storage = os.statvfs(config["path"])
        checks["storage"] &= storage.f_bavail * storage.f_frsize >= config["minimumFree"]
    except OSError:
        checks["storage"] = False
    checks["jobs"] = True
    for unit in config["units"]:
        try:
            result = subprocess.run(
                ["systemctl", "show", "--property=LoadState,ActiveState,Result", unit],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
            fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
            checks["jobs"] &= (
                fields.get("LoadState") == "loaded"
                and fields.get("ActiveState") != "failed"
                and fields.get("Result") == "success"
            )
        except (OSError, subprocess.SubprocessError):
            checks["jobs"] = False
    return checks


def publish_pressure(journal, destination):
    pressured = json.loads(Path(journal).read_text())["pressured"]
    if not isinstance(pressured, bool):
        raise TypeError("pressure state must be boolean")
    destination = Path(destination)
    with tempfile.NamedTemporaryFile(mode="w", dir=destination.parent, delete=False) as handle:
        handle.write("paused\n" if pressured else "ready\n")
        temporary = Path(handle.name)
    try:
        temporary.chmod(0o644)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


class BoundedServer(HTTPServer):
    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(5)
        return connection, address


def serve(config):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/health":
                self.send_error(404)
                return
            checks = status(config)
            body = json.dumps(checks).encode()
            self.send_response(200 if all(checks.values()) else 503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    BoundedServer(("127.0.0.1", config["port"]), Handler).serve_forever()


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--publish-pressure":
        try:
            publish_pressure(sys.argv[2], sys.argv[3])
        except (OSError, ValueError, TypeError, KeyError):
            sys.exit("Could not publish pressure health")
    else:
        serve(json.loads(Path(sys.argv[1]).read_text()))
