"""Behavior tests with disposable local HTTP servers and filesystem state."""

import importlib.util
import json
import os
import sqlite3
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, ROOT / "scripts" / "operations" / f"{name}.py"
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load operations module {name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pressure = load("pressure")
recovery = load("recovery")
restore_postgres = load("restore_postgres")
health = load("health")


class PressureTest(unittest.TestCase):
    def test_hysteresis_uses_available_bytes_and_missing_mount_pauses(self):
        config = {
            "path": "/media",
            "requiredMounts": ["/media"],
            "pauseBytes": 40,
            "resumeBytes": 60,
        }
        with (
            patch.object(pressure.os.path, "ismount", return_value=True),
            patch.object(pressure.os, "statvfs") as stat,
        ):
            stat.return_value.f_bavail = 50
            stat.return_value.f_frsize = 1
            self.assertFalse(pressure.pressured(config, False))
            self.assertTrue(pressure.pressured(config, True))
        with patch.object(pressure.os.path, "ismount", return_value=False):
            self.assertTrue(pressure.pressured(config, False))
        with (
            patch.object(pressure.os.path, "ismount", return_value=True),
            patch.object(pressure.os, "statvfs", side_effect=FileNotFoundError),
        ):
            self.assertTrue(pressure.pressured(config, False))

    def test_qbit_preserves_previously_stopped_and_seeding_torrents(self):
        api = object.__new__(pressure.Qbit)
        torrents = [
            {"hash": "active", "state": "downloading"},
            {"hash": "manual", "state": "stoppedDL"},
            {"hash": "seed", "state": "uploading"},
        ]
        calls = []

        def request(path, fields=None):
            calls.append((path, fields))
            return json.dumps(torrents).encode()

        api.request = request
        owned = api.reconcile(True, [])
        self.assertEqual(owned, ["active"])
        self.assertEqual(calls[-1], ("/api/v2/torrents/stop", {"hashes": "active"}))
        torrents[0]["state"] = "stoppedDL"
        self.assertEqual(api.reconcile(False, owned), [])
        self.assertEqual(calls[-1], ("/api/v2/torrents/start", {"hashes": "active"}))

    def test_uncertain_pause_response_does_not_authorize_automatic_resume(self):
        api = object.__new__(pressure.Qbit)
        torrents = [{"hash": "uncertain", "state": "downloading"}]
        calls = []

        def request(path, _fields=None):
            calls.append(path)
            if path.endswith("/stop"):
                torrents[0]["state"] = "stoppedDL"
                raise TimeoutError("response lost after server mutation")
            return json.dumps(torrents).encode()

        api.request = request
        with self.assertRaises(TimeoutError):
            api.reconcile(True, [])
        self.assertEqual(api.reconcile(False, []), [])
        self.assertNotIn("/api/v2/torrents/start", calls)

    def test_sab_preserves_manual_pause_and_owns_only_its_pause(self):
        api = object.__new__(pressure.Sab)
        calls = []
        paused = True

        def call(mode):
            calls.append(mode)
            return (
                {"queue": {"paused": paused}} if mode == "queue" else {"status": True}
            )

        api.call = call
        self.assertFalse(api.reconcile(True, False))
        self.assertFalse(api.reconcile(False, False))
        self.assertEqual(calls, ["queue", "queue"])
        paused = False
        self.assertTrue(api.reconcile(True, False))
        self.assertEqual(calls[-1], "pause")
        paused = True
        self.assertFalse(api.reconcile(False, True))
        self.assertEqual(calls[-1], "resume")

    def test_failure_preserves_ownership_and_journal_is_private(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            journal = Path(temp) / "journal.json"
            journal.write_text(
                json.dumps({"pressured": True, "qbittorrent": ["owned"]})
            )
            config = {"clients": {"qbittorrent": {"url": "http://localhost"}}}
            with (
                patch.object(pressure, "pressured", return_value=False),
                patch.object(
                    pressure, "Qbit", side_effect=RuntimeError("private credential")
                ),
                self.assertRaises(RuntimeError),
            ):
                pressure.reconcile(config, journal, temp)
            self.assertEqual(json.loads(journal.read_text())["qbittorrent"], ["owned"])
            self.assertEqual(journal.stat().st_mode & 0o777, 0o600)


class TransportTest(unittest.TestCase):
    def test_qbit_empty_login_requires_authenticated_api_before_pause(self):
        calls = []
        torrents = [
            {"hash": "active", "state": "downloading"},
            {"hash": "manual", "state": "stoppedDL"},
            {"hash": "seed", "state": "uploading"},
        ]

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                calls.append((self.path, None))
                if self.headers.get("Cookie") != "SID=public-fixture-session":
                    self.send_response(403)
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(torrents).encode())

            def do_POST(self):
                fields = urllib.parse.parse_qs(
                    self.rfile.read(
                        int(self.headers.get("Content-Length", "0"))
                    ).decode()
                )
                calls.append((self.path, fields))
                if self.path == "/api/v2/auth/login":
                    # Even an empty successful HTTP response must not authorize
                    # actions when authentication did not grant a session cookie.
                    self.send_response(204)
                    if fields.get("password") == ["public-fixture-password"]:
                        self.send_header(
                            "Set-Cookie", "SID=public-fixture-session; Path=/"
                        )
                    self.end_headers()
                    return
                if self.headers.get("Cookie") != "SID=public-fixture-session":
                    self.send_response(403)
                    self.end_headers()
                    return
                if self.path.endswith("/stop"):
                    torrents[0]["state"] = "stoppedDL"
                elif self.path.endswith("/start"):
                    torrents[0]["state"] = "downloading"
                self.send_response(204)
                self.end_headers()

            def log_message(self, format: str, *_args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(dir="/tmp") as temp:
                secret = Path(temp) / "qbittorrent"
                secret.write_text(
                    json.dumps({"username": "admin", "password": "wrong"})
                )
                url = f"http://127.0.0.1:{server.server_port}"
                with self.assertRaises(urllib.error.HTTPError):
                    pressure.Qbit(url, secret)
                self.assertEqual(
                    [path for path, _ in calls],
                    [
                        "/api/v2/auth/login",
                        "/api/v2/torrents/info",
                    ],
                )
                secret.write_text(
                    json.dumps({
                        "username": "admin",
                        "password": "public-fixture-password",
                    })
                )
                client = pressure.Qbit(url, secret)
                owned = client.reconcile(True, [])
                self.assertEqual(owned, ["active"])
                self.assertEqual(
                    calls[-1], ("/api/v2/torrents/stop", {"hashes": ["active"]})
                )
                self.assertEqual(client.reconcile(False, owned), [])
                self.assertEqual(
                    calls[-1], ("/api/v2/torrents/start", {"hashes": ["active"]})
                )
                self.assertEqual(torrents[1]["state"], "stoppedDL")
                self.assertEqual(torrents[2]["state"], "uploading")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_secrets_use_post_and_redirects_are_rejected(self):
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(
                    int(self.headers.get("Content-Length", "0"))
                ).decode()
                requests.append((self.path, urllib.parse.parse_qs(body)))
                if self.path == "/redirect":
                    self.send_response(307)
                    self.send_header("Location", "/leaked")
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"queue":{"paused":true}}')

            def log_message(self, format: str, *_args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(dir="/tmp") as temp:
                secret = Path(temp) / "secret"
                secret.write_text("disposable-key")
                url = f"http://127.0.0.1:{server.server_port}"
                self.assertFalse(pressure.Sab(url, secret).reconcile(True, False))
                self.assertEqual(requests[0][0], "/api")
                self.assertEqual(requests[0][1]["apikey"], ["disposable-key"])
                with self.assertRaises(RuntimeError):
                    pressure.API(url).request("/redirect", {"secret": "disposable"})
                self.assertEqual(len(requests), 2)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


class RecoveryTest(unittest.TestCase):
    def setUp(self):
        # Nix's user namespace maps the sandbox / and /tmp owners to nobody.
        # Model trusted host ancestors outside each private fixture subtree;
        # keep actual modes and all fixture ownership checks unchanged.
        original_stat = Path.stat

        def host_ancestors(path, *args, **kwargs):
            metadata = original_stat(path, *args, **kwargs)
            if path in {Path("/"), Path("/tmp")}:
                fields = list(metadata)
                fields[4] = 0
                return os.stat_result(fields)
            return metadata

        ancestor_patch = patch.object(Path, "stat", host_ancestors)
        ancestor_patch.start()
        self.addCleanup(ancestor_patch.stop)

    def test_sticky_ancestor_requires_trusted_owner(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            root = Path(temp)
            root.chmod(0o1777)
            private = root / "private"
            private.mkdir(mode=0o700)
            self.assertEqual(
                recovery.validate_target({}, private / "snapshot"),
                private / "snapshot",
            )
            original_stat = Path.stat

            def untrusted_owner(path, *args, **kwargs):
                metadata = original_stat(path, *args, **kwargs)
                if path == root:
                    fields = list(metadata)
                    fields[4] = os.geteuid() + 1234
                    return os.stat_result(fields)
                return metadata

            with (
                patch.object(Path, "stat", untrusted_owner),
                self.assertRaises(RuntimeError),
            ):
                recovery.validate_target({}, private / "snapshot")

    def test_staging_returns_canonical_path_before_ancestor_retarget(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            root = Path(temp)
            private = root / "private"
            private.mkdir(mode=0o700)
            alias = root / "alias"
            alias.symlink_to(private)
            validated = recovery.validate_target({}, alias / "snapshot")
            alias.unlink()
            alias.symlink_to(root / "unrelated")
            self.assertEqual(validated, private / "snapshot")

    def test_staging_rejects_renameable_ancestor(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            root = Path(temp)
            root.chmod(0o770)
            private = root / "private"
            private.mkdir(mode=0o700)
            with self.assertRaises(RuntimeError):
                recovery.validate_target({}, private / "snapshot")

    def test_dynamic_user_symlink_and_database_are_copied_after_stop(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            root = Path(temp)
            real = root / "private"
            real.mkdir()
            source = root / "public"
            source.symlink_to(real)
            with closing(sqlite3.connect(real / "application.db")) as db:
                db.execute("create table requests (title text)")
                db.execute("insert into requests values ('fixture')")
                db.commit()
            calls = []
            active = True

            def ctl(*args):
                nonlocal active
                calls.append(args)
                if "--property=LoadState" in args:
                    return type("Result", (), {"stdout": b"loaded\n"})()
                if args[0] == "stop":
                    active = False
                if args[0] == "start":
                    active = True
                return type(
                    "Result", (), {"stdout": b"active\n" if active else b"inactive\n"}
                )()

            inventory = {
                "fixture": {"units": ["fixture.service"], "paths": [str(source)]}
            }
            with patch.object(recovery, "systemctl", side_effect=ctl):
                recovery.snapshot(inventory, root / "snapshot")
            self.assertTrue(active)
            copy = root / "snapshot/services/fixture/0"
            self.assertFalse(copy.is_symlink())
            with closing(sqlite3.connect(copy / "application.db")) as db:
                self.assertEqual(
                    db.execute("select title from requests").fetchone(), ("fixture",)
                )
            self.assertEqual(calls[-1], ("start", "fixture.service"))
            self.assertFalse((root / "snapshot.writers").exists())

    def test_failure_restarts_writers_and_removes_partial_copy(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            target = Path(temp) / "snapshot"
            calls = []
            active = True

            def ctl(*args):
                nonlocal active
                calls.append(args)
                if "--property=LoadState" in args:
                    return type("Result", (), {"stdout": b"loaded\n"})()
                if args[0] == "stop":
                    active = False
                if args[0] == "start":
                    active = True
                return type(
                    "Result", (), {"stdout": b"active\n" if active else b"inactive\n"}
                )()

            with (
                patch.object(recovery, "systemctl", side_effect=ctl),
                self.assertRaises(FileNotFoundError),
            ):
                recovery.snapshot(
                    {
                        "fixture": {
                            "units": ["fixture.service"],
                            "paths": [temp + "/missing"],
                        }
                    },
                    target,
                )
            self.assertTrue(active)
            self.assertFalse(target.exists())
            self.assertEqual(calls[-1], ("start", "fixture.service"))

    def test_cleanup_refuses_unowned_files_and_resolved_overlap(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            root = Path(temp)
            target = root / "snapshot"
            target.mkdir()
            (target / "precious").write_text("preserve")
            with self.assertRaises(RuntimeError):
                recovery.cleanup({}, target)
            self.assertEqual((target / "precious").read_text(), "preserve")
            source = root / "alias"
            source.symlink_to(root)
            with self.assertRaises(RuntimeError):
                recovery.snapshot(
                    {"fixture": {"paths": [str(source)], "units": ["fixture.service"]}},
                    root / "new",
                )
            link = root / "linked"
            link.symlink_to(target)
            with self.assertRaises(RuntimeError):
                recovery.cleanup({}, link)
            self.assertTrue((target / "precious").exists())

    def test_prepare_runs_with_writers_stopped_and_failure_resumes_them(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            source = Path(temp) / "state"
            source.mkdir()
            target = Path(temp) / "snapshot"
            active = True
            prepared = False

            def ctl(*args):
                nonlocal active
                if "--property=LoadState" in args:
                    return type("Result", (), {"stdout": b"loaded"})()
                if args[0] == "stop":
                    active = False
                if args[0] == "start":
                    active = True
                return type(
                    "Result", (), {"stdout": b"active" if active else b"inactive"}
                )()

            def command(args, **_kwargs):
                nonlocal prepared
                self.assertFalse(active)
                self.assertEqual(args, ["/host/export"])
                prepared = True
                raise RuntimeError("export failed")

            inventory = {
                "fixture": {
                    "paths": [str(source)],
                    "units": ["fixture.service"],
                    "prepareCommand": "/host/export",
                }
            }
            with (
                patch.object(recovery, "systemctl", side_effect=ctl),
                patch.object(recovery.subprocess, "run", side_effect=command),
                self.assertRaises(RuntimeError),
            ):
                recovery.snapshot(inventory, target)
            self.assertTrue(prepared)
            self.assertTrue(active)
            self.assertFalse(target.exists())

    def test_remote_dump_uses_private_pgpass_and_verified_tls(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            database = {
                "database": "fixture",
                "host": "db.example.invalid",
                "port": 5432,
                "user": "fixture",
                "local": False,
                "caFile": "/etc/ssl/certs/ca-certificates.crt",
            }
            with (
                patch.dict(recovery.os.environ, {"CREDENTIALS_DIRECTORY": temp}),
                patch.object(recovery.subprocess, "run") as run,
            ):
                recovery.dump_databases({"fixture": database}, temp)
            command = run.call_args.args[0]
            self.assertEqual(command[0], "pg_dump")
            environment = run.call_args.kwargs["env"]
            self.assertEqual(environment["PGPASSFILE"], temp + "/postgres-fixture")
            self.assertEqual(environment["PGSSLMODE"], "verify-full")
            self.assertNotIn(temp + "/postgres-fixture", command)
            self.assertEqual(
                (Path(temp) / "databases/fixture.dump").stat().st_mode & 0o777, 0o600
            )

    def test_cleanup_recovers_interrupted_writer_journal(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            journal = Path(temp) / "writers"
            journal.write_text(
                json.dumps({"owner": recovery.MARKER, "units": ["fixture.service"]})
            )
            with patch.object(recovery, "systemctl") as ctl:
                recovery.resume({"fixture": {"units": ["fixture.service"]}}, journal)
                ctl.assert_called_once_with("start", "fixture.service")
            self.assertFalse(journal.exists())


class DatabaseRestoreTest(unittest.TestCase):
    def test_unknown_writer_prevents_restore_before_database_connection(self):
        inventory = {"fixture": {"units": ["misspelled.service"]}}
        with patch.object(restore_postgres.subprocess, "run") as run:
            run.return_value.stdout = b"not-found"
            with self.assertRaises(RuntimeError):
                restore_postgres.restore(inventory, {}, "/missing/archive")
            self.assertEqual(run.call_count, 1)
            self.assertIn("--property=LoadState", run.call_args.args[0])

    def test_running_writer_prevents_restore(self):
        inventory = {"fixture": {"units": ["fixture.service"]}}
        results = [
            type("Result", (), {"stdout": b"loaded"})(),
            type("Result", (), {"stdout": b"active"})(),
        ]
        with (
            patch.object(
                restore_postgres.subprocess, "run", side_effect=results
            ) as run,
            self.assertRaises(RuntimeError),
        ):
            restore_postgres.restore(inventory, {}, "/missing/archive")
        self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()


class HealthTest(unittest.TestCase):
    @staticmethod
    def run_doctor(config) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            path = Path(temp) / "doctor.json"
            path.write_text(json.dumps(config))
            return subprocess.run(
                [
                    "python3",
                    str(ROOT / "scripts/operations/health.py"),
                    "--check",
                    str(path),
                    "--json",
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=10,
            )

    def test_doctor_reports_healthy_json_and_zero_exit(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            downloads = Path(temp) / "downloads"
            library = Path(temp) / "library"
            downloads.mkdir()
            library.mkdir()
            result = self.run_doctor({
                "backup": False,
                "mounts": [],
                "path": temp,
                "minimumFree": 0,
                "units": [],
                "hardlinkPaths": [str(downloads), str(library)],
            })
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "healthy")
        self.assertEqual(report["checks"]["hardlinks"]["status"], "healthy")

    def test_doctor_distinguishes_unsafe_degraded_and_inconclusive(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            missing_mount = self.run_doctor({
                "backup": False,
                "mounts": [str(Path(temp) / "missing-mount")],
                "path": temp,
                "minimumFree": 0,
                "units": [],
            })
            self.assertEqual(missing_mount.returncode, 2, missing_mount.stderr)
            self.assertEqual(json.loads(missing_mount.stdout)["status"], "unsafe")

            missing_backup = self.run_doctor({
                "backup": True,
                "stamp": str(Path(temp) / "missing-stamp"),
                "maxAge": 60,
                "mounts": [],
                "path": temp,
                "minimumFree": 0,
                "units": [],
            })
            self.assertEqual(missing_backup.returncode, 1, missing_backup.stderr)
            self.assertEqual(json.loads(missing_backup.stdout)["status"], "degraded")

            unknown_storage = self.run_doctor({
                "backup": False,
                "mounts": [],
                "path": str(Path(temp) / "missing-path"),
                "minimumFree": 0,
                "units": [],
            })
            self.assertEqual(unknown_storage.returncode, 3, unknown_storage.stderr)
            self.assertEqual(
                json.loads(unknown_storage.stdout)["status"], "inconclusive"
            )

    def test_doctor_checks_vpn_dns_listener_exposure_and_backup_separation(self):
        now = int(health.time.time())
        config = {
            "backup": False,
            "mounts": [],
            "path": "/tmp",
            "minimumFree": 0,
            "units": [],
            "vpn": {
                "namespace": "vpnapps",
                "interface": "wg0",
                "maxHandshakeAge": 180,
                "dnsProbeHost": "example.com",
            },
            "privateTcpPorts": [8096],
        }

        def command(args, **_kwargs):
            if "latest-handshakes" in args:
                return subprocess.CompletedProcess(args, 0, f"peer {now}\n", "")
            if "getent" in args:
                return subprocess.CompletedProcess(
                    args, 0, "192.0.2.1 STREAM example.com\n", ""
                )
            if args[0] == "ss":
                return subprocess.CompletedProcess(
                    args, 0, "LISTEN 0 4096 127.0.0.1:8096 0.0.0.0:*\n", ""
                )
            raise AssertionError(args)

        with patch.object(health.subprocess, "run", side_effect=command):
            report = health.diagnose(config)
        self.assertEqual(report["checks"]["vpn"]["status"], "healthy")
        self.assertEqual(report["checks"]["listeners"]["status"], "healthy")

        def exposed(args, **kwargs):
            result = command(args, **kwargs)
            if args[0] == "ss":
                result.stdout = "LISTEN 0 4096 0.0.0.0:8096 0.0.0.0:*\n"
            return result

        with patch.object(health.subprocess, "run", side_effect=exposed):
            report = health.diagnose(config)
        self.assertEqual(report["checks"]["listeners"]["status"], "unsafe")

        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            config.update({
                "backupRepositoryPath": temp,
                "backupStagingPath": temp,
            })
            with patch.object(health.subprocess, "run", side_effect=command):
                report = health.diagnose(config)
        self.assertEqual(report["checks"]["backupSeparation"]["status"], "unsafe")

    def test_pressure_health_preserves_hysteresis_without_exposing_queue(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            root = Path(temp)
            journal = root / "journal"
            public = root / "pressure"
            config = {
                "backup": False,
                "pressureFile": str(public),
                "pressureMaxAge": 60,
                "mounts": [],
                "path": temp,
                "minimumFree": 1,
                "units": [],
            }
            self.assertFalse(health.status(config)["pressure"])
            journal.write_text(
                json.dumps({"pressured": True, "qbittorrent": ["private-queue-id"]})
            )
            health.publish_pressure(journal, public)
            self.assertEqual(public.read_text(), "paused\n")
            self.assertFalse(health.status(config)["pressure"])
            journal.write_text(json.dumps({"pressured": False}))
            health.publish_pressure(journal, public)
            self.assertTrue(health.status(config)["pressure"])
            with patch.object(
                health.time, "time", return_value=public.stat().st_mtime + 61
            ):
                self.assertFalse(health.status(config)["pressure"])

    def test_missing_stale_future_backup_and_failed_jobs_are_unhealthy(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            stamp = Path(temp) / "stamp"
            config = {
                "backup": True,
                "stamp": str(stamp),
                "maxAge": 60,
                "mounts": [],
                "path": temp,
                "minimumFree": 1,
                "units": ["fixture.service"],
            }
            with patch.object(health.subprocess, "run") as run:
                run.return_value.stdout = (
                    "LoadState=loaded\nActiveState=inactive\nResult=success\n"
                )
                self.assertFalse(health.status(config)["backup"])
                stamp.touch()
                self.assertTrue(all(health.status(config).values()))
                with patch.object(
                    health.time, "time", return_value=stamp.stat().st_mtime + 61
                ):
                    self.assertFalse(health.status(config)["backup"])
                with patch.object(
                    health.time, "time", return_value=stamp.stat().st_mtime - 1
                ):
                    self.assertFalse(health.status(config)["backup"])
                run.return_value.stdout = (
                    "LoadState=loaded\nActiveState=failed\nResult=exit-code\n"
                )
                self.assertFalse(health.status(config)["jobs"])
                config["mounts"] = [str(Path(temp) / "missing")]
                self.assertFalse(health.status(config)["storage"])
                config["minimumFree"] = 2**63
                self.assertFalse(health.status(config)["storage"])
