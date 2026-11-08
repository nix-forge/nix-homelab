"""Install migration notifications before startup and await committed schema."""

import asyncio
import select
import sys
import time
from contextlib import closing
from pathlib import Path

import psycopg2


async def database_ready(podman: str) -> None:
    """Follow database startup output instead of probing its socket.

    Raises:
        RuntimeError: The database exits before advertising its final listener.

    """
    process = await asyncio.create_subprocess_exec(
        podman,
        "logs",
        "--follow",
        "bookorbit-db",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        if process.stdout is None:
            raise RuntimeError("Database startup output is unavailable")
        listening = False
        async with asyncio.timeout(60):
            while line := await process.stdout.readline():
                # The image's initialization server listens only on Unix sockets.
                # Wait for the final server that exposes the private IPv4 endpoint.
                if b"listening on IPv4 address" in line:
                    listening = True
                if (
                    listening
                    and b"database system is ready to accept connections" in line
                ):
                    return
            raise RuntimeError("BookOrbit database exited before readiness")
    finally:
        if process.returncode is None:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), 5)
            except TimeoutError:
                process.kill()
                await process.wait()


def wait_schema(connection, timeout: float = 60) -> None:
    """Wait for committed app_settings after subscribing to migration events.

    Raises:
        TimeoutError: The schema does not appear before the monotonic deadline.

    """
    with connection.cursor() as cursor:
        # Subscribe before the snapshot. The producer was installed before
        # application startup, including transactions already in progress.
        cursor.execute("LISTEN homelab_bookorbit_schema")
        deadline = time.monotonic() + timeout
        while True:
            # A query can consume socket notifications into the client queue.
            # Discard old events before the snapshot, then inspect newly queued
            # events before blocking on the descriptor.
            connection.notifies.clear()
            cursor.execute("SELECT to_regclass('public.app_settings') IS NOT NULL")
            row = cursor.fetchone()
            if row is not None and row[0]:
                return
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("BookOrbit migration did not create app_settings")
            if connection.notifies:
                continue
            if not select.select([connection], [], [], remaining)[0]:
                raise TimeoutError("BookOrbit migration did not create app_settings")
            connection.poll()


def main() -> None:
    """Install the DDL producer or block on migration notifications.

    Raises:
        ValueError: The caller selected an unknown mode.

    """
    mode, podman, password_path, notification_sql = sys.argv[1:]
    if mode == "prepare":
        asyncio.run(database_ready(podman))
    password = Path(password_path).read_text(encoding="utf-8").strip()
    with closing(
        psycopg2.connect(
            host="127.0.0.1",
            user="bookorbit",
            dbname="bookorbit",
            password=password,
            connect_timeout=10,
        )
    ) as connection:
        connection.autocommit = True
        with connection.cursor() as cursor:
            if mode == "prepare":
                cursor.execute(Path(notification_sql).read_text(encoding="utf-8"))
                return
            if mode != "wait":
                raise ValueError("Unknown schema readiness mode")
        wait_schema(connection)


if __name__ == "__main__":
    try:
        main()
    except OSError, psycopg2.Error, ValueError, RuntimeError:
        # Database errors can contain connection details; keep diagnostics generic.
        sys.stderr.write("BookOrbit schema readiness failed\n")
        sys.exit(1)
