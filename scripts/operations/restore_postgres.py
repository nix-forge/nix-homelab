"""Attended logical PostgreSQL restore into an existing host-owned database."""

import json
import os
import subprocess
import sys
from pathlib import Path


def restore(inventory, database, archive):
    for unit in sorted({unit for entry in inventory.values() for unit in entry["units"]}):
        loaded = subprocess.run(
            ["systemctl", "show", "--property=LoadState", "--value", unit],
            check=True,
            capture_output=True,
        ).stdout.strip()
        if loaded != b"loaded":
            raise RuntimeError("every inventory writer must exist before restoring")
        state = subprocess.run(
            ["systemctl", "show", "--property=ActiveState", "--value", unit],
            check=True,
            capture_output=True,
        ).stdout.strip()
        if state not in (b"inactive", b"failed"):
            raise RuntimeError("stop all inventory writers and timers before restoring")
    command = [
        "pg_restore",
        "--clean",
        "--if-exists",
        "--single-transaction",
        "--exit-on-error",
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
        environment["PGPASSFILE"] = database["passwordFile"]
    # Open as the operator so postgres need not read the private restore directory.
    with Path(archive).open("rb") as source:
        subprocess.run(
            command,
            stdin=source,
            capture_output=True,
            env=environment,
            check=True,
        )


def main():
    try:
        if len(sys.argv) != 6 or sys.argv[5] != "--replace":
            raise RuntimeError("expected database archive --replace")
        inventory = json.loads(Path(sys.argv[1]).read_text())
        database = json.loads(Path(sys.argv[2]).read_text())[sys.argv[3]]
        restore(inventory, database, sys.argv[4])
    except Exception:  # noqa: BLE001 - errors may contain application data or credentials
        print(
            "Database restore failed. Supply NAME ARCHIVE --replace and stop inventory writers first; inspect host database connectivity locally.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
