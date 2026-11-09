"""Exercise SQL formatting through treefmt's actual CI change detection."""

import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(
    os.environ.get(
        "SQL_FORMATTER_SCRIPT",
        str(Path(__file__).resolve().parents[2] / "flake/dev/scripts/format-sql.sh"),
    )
)


class SqlFormattingTest(unittest.TestCase):
    def exercise(self, dialect: str, *, malformed: bool = False) -> None:
        with tempfile.TemporaryDirectory(prefix="SQL formatting ") as directory:
            root = Path(directory)
            source = root / "query with spaces.sql"
            original = "select 'unterminated" if malformed else "select 1 as answer;"
            source.write_text(original)
            source.chmod(0o600)
            os.utime(source, ns=(1_000_000_000, 1_000_000_000))
            before = source.stat()
            config = root / "treefmt.toml"
            bash = shutil.which("bash")
            assert bash is not None
            config.write_text(
                "[formatter.sql]\ncommand = "
                + json.dumps(bash)
                + "\noptions = "
                + json.dumps([str(SCRIPT), dialect])
                + '\nincludes = ["*.sql"]\n'
            )
            command = [
                "treefmt",
                "--tree-root",
                str(root),
                "--config-file",
                str(config),
                "--walk",
                "filesystem",
                "--ci",
            ]
            first = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertNotEqual(first.returncode, 0, first.stdout + first.stderr)
            if malformed:
                self.assertEqual(source.read_text(), original)
                self.assertEqual(source.stat().st_mtime_ns, before.st_mtime_ns)
                return
            self.assertNotEqual(source.read_text(), original)
            with sqlite3.connect(":memory:") as connection:
                self.assertEqual(
                    connection.execute(source.read_text()).fetchall(), [(1,)]
                )
            self.assertEqual(source.stat().st_mode, before.st_mode)
            formatted = source.read_bytes()
            stamp = source.stat().st_mtime_ns
            second = subprocess.run(
                command, capture_output=True, text=True, check=False
            )
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertEqual(source.read_bytes(), formatted)
            self.assertEqual(source.stat().st_mtime_ns, stamp)

    def test_postgresql_ci_preserves_clean_timestamps(self) -> None:
        self.exercise("postgresql")

    def test_sqlite_ci_preserves_clean_timestamps(self) -> None:
        self.exercise("sqlite")

    def test_postgresql_error_preserves_input(self) -> None:
        self.exercise("postgresql", malformed=True)

    def test_sqlite_error_preserves_input(self) -> None:
        self.exercise("sqlite", malformed=True)


if __name__ == "__main__":
    unittest.main()
