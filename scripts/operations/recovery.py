"""Create a stopped-writer recovery copy, preserving filesystem metadata."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def systemctl(*args):
    return subprocess.run(["systemctl", *args], check=True, capture_output=True)


MARKER = "nix-homelab-recovery-v1"


def validate_target(inventory, target):
    target = Path(target)
    if target.is_symlink():
        raise RuntimeError("staging destination must not be a symlink")
    resolved = target.resolve()
    parent = resolved.parent.stat()
    if parent.st_uid != os.geteuid() or parent.st_mode & 0o077:
        raise RuntimeError(
            "staging parent must be private and owned by the backup user"
        )
    # A private final directory is insufficient beneath a renameable ancestor.
    # Sticky ancestors owned by root or the backup user protect our child directories.
    for ancestor in resolved.parent.parents:
        metadata = ancestor.stat()
        trusted = metadata.st_uid in {0, os.geteuid()}
        protected = not (metadata.st_mode & 0o022)
        sticky_trusted = trusted and bool(metadata.st_mode & 0o1000)
        if not trusted or not (protected or sticky_trusted):
            raise RuntimeError(
                "staging ancestors must not be renameable by other users"
            )
    for entry in inventory.values():
        for original in entry["paths"]:
            source = Path(original).resolve()
            if (
                resolved == source
                or source in resolved.parents
                or resolved in source.parents
            ):
                raise RuntimeError("resolved source and staging paths overlap")
    return resolved


def cleanup(inventory, target):
    target = validate_target(inventory, target)
    if target.exists():
        marker = target / ".homelab-staging"
        if marker.is_symlink() or not marker.is_file() or marker.read_text() != MARKER:
            raise RuntimeError("refusing to remove unowned staging content")
    resume(inventory, str(target) + ".writers")
    if target.exists():
        shutil.rmtree(target)


def resume(inventory, journal):
    journal = Path(journal)
    if journal.is_symlink():
        raise RuntimeError("writer journal must not be a symlink")
    if journal.exists():
        record = json.loads(journal.read_text())
        if not isinstance(record, dict) or record.get("owner") != MARKER:
            raise RuntimeError("unowned writer journal")
        active = record["units"]
        allowed = {unit for entry in inventory.values() for unit in entry["units"]}
        if not isinstance(active, list) or not set(active) <= allowed:
            raise RuntimeError("invalid writer journal")
        if active:
            systemctl("start", *active)
        journal.unlink()


def dump_databases(databases, target):
    for name, database in databases.items():
        destination = Path(target) / "databases" / f"{name}.dump"
        destination.parent.mkdir(mode=0o700, exist_ok=True)
        command = [
            "pg_dump",
            "--format=custom",
            "--host",
            database["host"],
            "--port",
            str(database["port"]),
            "--username",
            database["user"],
            "--dbname",
            database["database"],
        ]
        environment = os.environ.copy()
        environment["PGCONNECT_TIMEOUT"] = "20"
        environment["PGSSLMODE"] = "disable" if database["local"] else "verify-full"
        environment["PGSSLROOTCERT"] = database["caFile"]
        if database["local"]:
            command = ["runuser", "--user", "postgres", "--", *command]
        else:
            environment["PGPASSFILE"] = str(
                Path(os.environ["CREDENTIALS_DIRECTORY"]) / f"postgres-{name}"
            )
        with destination.open("xb") as output:
            destination.chmod(0o600)
            subprocess.run(
                command,
                env=environment,
                stdout=output,
                stderr=subprocess.PIPE,
                check=True,
            )
    if databases:
        # Connection metadata is public configuration; secret paths/values are excluded.
        (Path(target) / "databases" / "manifest.json").write_text(
            json.dumps(databases, indent=2) + "\n"
        )


def snapshot(inventory, target, databases=None):
    target = validate_target(inventory, target)
    if target.exists():
        raise RuntimeError("staging destination must be absent")
    journal = Path(str(target) + ".writers")
    if journal.exists() or journal.is_symlink():
        raise RuntimeError("recover previous writer journal before staging")
    target.mkdir(mode=0o700)
    (target / ".homelab-staging").write_text(MARKER)
    active = []
    try:
        units = sorted({
            unit for entry in inventory.values() for unit in entry["units"]
        })
        for unit in units:
            if (
                systemctl(
                    "show", "--property=LoadState", "--value", unit
                ).stdout.strip()
                != b"loaded"
            ):
                raise RuntimeError("writer unit must exist")
            state = systemctl(
                "show", "--property=ActiveState", "--value", unit
            ).stdout.strip()
            if state not in {b"active", b"activating", b"inactive", b"failed"}:
                raise RuntimeError("writer in transitional state; retry backup later")
            if state in {b"active", b"activating"}:
                active.append(unit)
        journal.write_text(
            json.dumps({"owner": MARKER, "units": active}), encoding="utf-8"
        )
        journal.chmod(0o600)
        if active:
            systemctl("stop", *active)
        for unit in units:
            state = systemctl(
                "show", "--property=ActiveState", "--value", unit
            ).stdout.strip()
            if state not in {b"inactive", b"failed"}:
                raise RuntimeError("writer did not stop")
        for entry in inventory.values():
            if entry.get("prepareCommand"):
                subprocess.run(
                    [entry["prepareCommand"]],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        dump_databases(databases or {}, target)
        manifest = {}
        for name, entry in inventory.items():
            manifest[name] = {"units": entry["units"], "paths": []}
            for index, original in enumerate(entry["paths"]):
                # DynamicUser public paths can be symlinks into /var/lib/private.
                source = Path(original).resolve(strict=True)
                if not source.is_dir():
                    raise RuntimeError("state source must be a directory")
                destination = target / "services" / name / str(index)
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                subprocess.run(
                    [
                        "cp",
                        "--archive",
                        "--reflink=auto",
                        "--",
                        str(source),
                        str(destination),
                    ],
                    check=True,
                    capture_output=True,
                )
                manifest[name]["paths"].append({
                    "original": original,
                    "resolved": str(source),
                    "copy": str(destination.relative_to(target)),
                })
        (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        Path(target / "manifest.json").chmod(0o600)
    except BaseException:
        shutil.rmtree(target)
        raise
    finally:
        resume(inventory, journal)


def main():
    try:
        inventory = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
        target = sys.argv[3]
        if sys.argv[1] == "stage":
            snapshot(
                inventory,
                target,
                json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
                if len(sys.argv) > 4
                else {},
            )
        elif sys.argv[1] == "cleanup":
            cleanup(inventory, target)
        else:
            raise RuntimeError("unknown operation")
    except Exception:  # ruff: ignore[blind-except] - never expose credential-bearing exception values
        # API credentials may be embedded in application filenames: never print
        # subprocess output or exception values in the system journal.
        print(
            "Recovery staging failed; inspect writer status and state paths locally.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
