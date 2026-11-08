import os
import pathlib
import sqlite3
import sys
import tempfile
import unittest
from contextlib import closing

sys.path.insert(
    0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts" / "operations")
)
import verify_maintainerr_restore as restore


class RestoreTest(unittest.TestCase):
    def test_isolated_sqlite_integrity_and_uid(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "data.db"
            with closing(sqlite3.connect(path)) as db:
                db.execute("CREATE TABLE items (title TEXT)")
                db.execute("INSERT INTO items VALUES ('fixture')")
                db.commit()
            self.assertEqual(restore.verify(directory, os.getuid()), 1)
            with self.assertRaisesRegex(ValueError, "UID"):
                restore.verify(directory, os.getuid() + 1)

    def test_missing_database_rejected(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(ValueError, "no SQLite"),
        ):
            restore.verify(directory, os.getuid())


if __name__ == "__main__":
    unittest.main()
