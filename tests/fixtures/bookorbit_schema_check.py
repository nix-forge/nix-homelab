"""Verify notification ordering and committed DDL against isolated PostgreSQL."""

import asyncio
import importlib.util
import os
import select
import sys
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path

import psycopg2


def scenarios(socket_path, helper_path, sql_path):
    spec = importlib.util.spec_from_file_location("schema_ready", helper_path)
    assert spec is not None
    assert spec.loader is not None
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    settings = {"host": socket_path, "user": "bookorbit", "dbname": "postgres"}
    with closing(psycopg2.connect(**settings)) as producer:
        producer.autocommit = True
        with producer.cursor() as cursor:
            cursor.execute(Path(sql_path).read_text(encoding="utf-8"))
        producer.autocommit = False
        first_snapshot = threading.Event()
        unrelated_snapshot = threading.Event()
        snapshots = []

        class Cursor:
            def __init__(self, cursor):
                self.cursor = cursor

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return self.cursor.__exit__(*args)

            def execute(self, query):
                self.cursor.execute(query)

            def fetchone(self):
                row = self.cursor.fetchone()
                snapshots.append(row[0])
                if len(snapshots) == 1:
                    first_snapshot.set()
                elif len(snapshots) == 2:
                    unrelated_snapshot.set()
                return row

        class Connection:
            def __init__(self, connection):
                self.connection = connection
                self.notifies = connection.notifies

            def cursor(self):
                return Cursor(self.connection.cursor())

            def fileno(self):
                return self.connection.fileno()

            def poll(self):
                return self.connection.poll()

        with (
            closing(psycopg2.connect(**settings)) as listener,
            ThreadPoolExecutor(max_workers=1) as executor,
        ):
            listener.autocommit = True
            future = executor.submit(helper.wait_schema, Connection(listener), 2)
            assert first_snapshot.wait(2), (
                "listener did not take its subscribed snapshot"
            )
            with producer.cursor() as cursor:
                cursor.execute("CREATE TABLE unrelated (id integer)")
            producer.commit()
            assert unrelated_snapshot.wait(2), "unrelated DDL did not wake the listener"
            assert not future.done(), "unrelated DDL incorrectly established readiness"
            with producer.cursor() as cursor:
                cursor.execute("CREATE TABLE app_settings (id integer)")
            # Commit can race entering select: LISTEN must retain the notification.
            producer.commit()
            future.result(timeout=2)
            assert snapshots == [False, False, True]
            helper.wait_schema(listener, 0.1)
            with producer.cursor() as cursor:
                cursor.execute("DROP TABLE app_settings")
            producer.commit()
            with producer.cursor() as cursor:
                cursor.execute("CREATE TABLE app_settings (id integer)")
            timed_out = False
            try:
                helper.wait_schema(listener, 0.05)
            except TimeoutError:
                timed_out = True
            assert timed_out, "Uncommitted DDL established readiness"
            producer.rollback()

            class BufferedCursor(Cursor):
                def fetchone(self):
                    row = self.cursor.fetchone()
                    if row is not None and not row[0]:
                        with producer.cursor() as ddl:
                            ddl.execute("CREATE TABLE app_settings (id integer)")
                        producer.commit()
                        # Consume the real notification after obtaining the old
                        # row and before returning it to the readiness helper.
                        assert select.select([listener], [], [], 2)[0]
                        listener.poll()
                        assert listener.notifies
                    return row

            class BufferedConnection(Connection):
                def cursor(self):
                    return BufferedCursor(self.connection.cursor())

            helper.wait_schema(BufferedConnection(listener), 2)


async def main():
    postgres, initdb, helper, sql = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="bookorbit-schema-") as directory:
        root = Path(directory)
        socket_path = root / "socket"
        socket_path.mkdir(mode=0o700)
        async with asyncio.timeout(30):
            initialize = await asyncio.create_subprocess_exec(
                initdb,
                "-D",
                str(root / "database"),
                "--auth=trust",
                "--username=bookorbit",
                "--no-locale",
                "--encoding=UTF8",
                stdout=asyncio.subprocess.DEVNULL,
            )
            try:
                assert await initialize.wait() == 0
            finally:
                if initialize.returncode is None:
                    initialize.kill()
                    await initialize.wait()
            server = await asyncio.create_subprocess_exec(
                postgres,
                "-D",
                str(root / "database"),
                "-k",
                str(socket_path),
                "-c",
                "listen_addresses=",
                env=os.environ | {"LC_ALL": "C"},
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
            try:
                assert server.stdout is not None
                while line := await server.stdout.readline():
                    if b"database system is ready to accept connections" in line:
                        break
                else:
                    raise AssertionError("PostgreSQL exited before readiness")
                await asyncio.to_thread(scenarios, str(socket_path), helper, sql)
            finally:
                if server.returncode is None:
                    server.terminate()
                    try:
                        await asyncio.wait_for(server.wait(), 5)
                    except TimeoutError:
                        server.kill()
                        await server.wait()


if __name__ == "__main__":
    asyncio.run(main())
