"""Private operational status without application data or credentials."""

import errno
import json
import os
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

EXIT_STATUS = {
    "healthy": 0,
    "degraded": 1,
    "unsafe": 2,
    "inconclusive": 3,
}


def result(state, detail):
    return {"status": state, "detail": detail}


def diagnose(config):
    checks = {}
    if config["backup"]:
        try:
            age = time.time() - Path(config["stamp"]).stat().st_mtime
            checks["backup"] = (
                result("healthy", "latest successful backup is within policy")
                if 0 <= age <= config["maxAge"]
                else result(
                    "degraded", "latest successful backup is missing or outside policy"
                )
            )
        except OSError:
            checks["backup"] = result(
                "degraded", "no successful backup marker is available"
            )
    if config.get("pressureFile"):
        try:
            pressure = Path(config["pressureFile"])
            age = time.time() - pressure.stat().st_mtime
            ready = (
                pressure.read_text(encoding="utf-8") == "ready\n"
                and 0 <= age <= config["pressureMaxAge"]
            )
            checks["pressure"] = (
                result("healthy", "storage pressure is within policy")
                if ready
                else result(
                    "degraded", "storage pressure is active or its marker is stale"
                )
            )
        except OSError:
            checks["pressure"] = result(
                "inconclusive", "storage pressure marker cannot be read"
            )
    missing_mounts = [path for path in config["mounts"] if not os.path.ismount(path)]
    if missing_mounts:
        checks["storage"] = result("unsafe", "one or more required mounts are absent")
    else:
        checks["storage"] = result(
            "healthy", "required mounts and free space satisfy policy"
        )
    try:
        storage = os.statvfs(config["path"])
        if (
            checks["storage"]["status"] == "healthy"
            and storage.f_bavail * storage.f_frsize < config["minimumFree"]
        ):
            checks["storage"] = result("degraded", "available storage is below policy")
    except OSError:
        if checks["storage"]["status"] == "healthy":
            checks["storage"] = result(
                "inconclusive", "storage capacity cannot be read"
            )
    if config.get("hardlinkPaths"):
        source, destination = map(Path, config["hardlinkPaths"])
        source_file = None
        linked_file = destination / f".homelab-doctor-{os.getpid()}"
        try:
            with tempfile.NamedTemporaryFile(
                dir=source, prefix=".homelab-doctor-", delete=False
            ) as handle:
                source_file = Path(handle.name)
            os.link(source_file, linked_file)
            checks["hardlinks"] = result(
                "healthy", "download and library paths support hardlinks"
            )
        except OSError as error:
            checks["hardlinks"] = (
                result("unsafe", "download and library paths cannot hardlink")
                if error.errno == errno.EXDEV
                else result("inconclusive", "hardlink capability could not be tested")
            )
        finally:
            linked_file.unlink(missing_ok=True)
            if source_file is not None:
                source_file.unlink(missing_ok=True)
    repository = config.get("backupRepositoryPath")
    staging = config.get("backupStagingPath")
    if repository and staging:
        try:
            separated = Path(repository).stat().st_dev != Path(staging).stat().st_dev
            checks["backupSeparation"] = (
                result("healthy", "local backup repository is on a separate filesystem")
                if separated
                else result(
                    "unsafe", "local backup repository shares the staging filesystem"
                )
            )
        except OSError:
            checks["backupSeparation"] = result(
                "inconclusive", "local backup repository separation cannot be verified"
            )
    vpn = config.get("vpn")
    if vpn:
        base = ["ip", "netns", "exec", vpn["namespace"]]
        try:
            handshake = subprocess.run(
                base + ["wg", "show", vpn["interface"], "latest-handshakes"],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
            timestamps = [
                int(line.split()[1])
                for line in handshake.stdout.splitlines()
                if len(line.split()) == 2
            ]
            fresh = (
                timestamps
                and 0 <= time.time() - max(timestamps) <= vpn["maxHandshakeAge"]
            )
            dns = subprocess.run(
                base + ["getent", "ahosts", vpn["dnsProbeHost"]],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
            checks["vpn"] = (
                result("healthy", "WireGuard handshake and namespace DNS are current")
                if fresh and dns.stdout.strip()
                else result(
                    "degraded", "WireGuard handshake or namespace DNS is unavailable"
                )
            )
        except OSError, subprocess.SubprocessError, ValueError, IndexError:
            checks["vpn"] = result(
                "inconclusive",
                "WireGuard handshake or namespace DNS could not be tested",
            )
    if config.get("privateTcpPorts"):
        try:
            sockets = subprocess.run(
                ["ss", "--numeric", "--listening", "--tcp"],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
            exposed = set()
            for line in sockets.stdout.splitlines():
                fields = line.split()
                if len(fields) < 4 or ":" not in fields[3]:
                    continue
                address, raw_port = fields[3].rsplit(":", 1)
                if raw_port.isdigit() and int(raw_port) in config["privateTcpPorts"]:
                    if address.strip("[]") not in {"127.0.0.1", "::1"}:
                        exposed.add(int(raw_port))
            checks["listeners"] = (
                result(
                    "unsafe",
                    "one or more private TCP ports listen on a non-loopback address",
                )
                if exposed
                else result("healthy", "declared private TCP ports are loopback-only")
            )
        except OSError, subprocess.SubprocessError:
            checks["listeners"] = result(
                "inconclusive", "listener exposure could not be inspected"
            )
    checks["jobs"] = result("healthy", "all declared jobs are loaded and non-failed")
    for unit in config["units"]:
        try:
            command_result = subprocess.run(
                ["systemctl", "show", "--property=LoadState,ActiveState,Result", unit],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
            fields = dict(
                line.split("=", 1)
                for line in command_result.stdout.splitlines()
                if "=" in line
            )
            healthy = (
                fields.get("LoadState") == "loaded"
                and fields.get("ActiveState") != "failed"
                and fields.get("Result") == "success"
            )
            if not healthy:
                checks["jobs"] = result("degraded", "one or more declared jobs failed")
        except OSError, subprocess.SubprocessError:
            if checks["jobs"]["status"] == "healthy":
                checks["jobs"] = result("inconclusive", "job state could not be read")
    states = {check["status"] for check in checks.values()}
    overall = next(
        (state for state in ("unsafe", "degraded", "inconclusive") if state in states),
        "healthy",
    )
    return {"status": overall, "checks": checks}


def status(config):
    return {
        name: check["status"] == "healthy"
        for name, check in diagnose(config)["checks"].items()
    }


def check(config, json_output=False):
    report = diagnose(config)
    if json_output:
        print(json.dumps(report, sort_keys=True))
    else:
        print(f"homelab: {report['status']}")
        for name, item in sorted(report["checks"].items()):
            print(f"{name}: {item['status']}: {item['detail']}")
    return EXIT_STATUS[report["status"]]


def publish_pressure(journal, destination):
    pressured = json.loads(Path(journal).read_text(encoding="utf-8"))["pressured"]
    if not isinstance(pressured, bool):
        raise TypeError("pressure state must be boolean")
    destination = Path(destination)
    with tempfile.NamedTemporaryFile(
        encoding="utf-8", mode="w", dir=destination.parent, delete=False
    ) as handle:
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

        def log_message(self, format: str, *_args: object) -> None:
            pass

    BoundedServer(("127.0.0.1", config["port"]), Handler).serve_forever()


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--publish-pressure":
        try:
            publish_pressure(sys.argv[2], sys.argv[3])
        except OSError, ValueError, TypeError, KeyError:
            sys.exit("Could not publish pressure health")
    elif len(sys.argv) in {3, 4} and sys.argv[1] == "--check":
        configuration = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
        sys.exit(
            check(
                configuration,
                json_output=len(sys.argv) == 4 and sys.argv[3] == "--json",
            )
        )
    else:
        serve(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
