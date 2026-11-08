"""Check an isolated Maintainerr state restore without starting the service."""

import argparse
import os
import pathlib
import sqlite3
from contextlib import closing


def verify(directory, expected_uid):
    root = pathlib.Path(directory)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("restored data path must be a real directory")
    if root.stat().st_uid != expected_uid:
        raise ValueError("restored data owner UID does not match")
    databases = []
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [name for name in dirs if not pathlib.Path(base, name).is_symlink()]
        for name in files:
            path = pathlib.Path(base, name)
            if path.is_symlink() or not path.is_file():
                continue
            with path.open("rb") as stream:
                if stream.read(16) == b"SQLite format 3\x00":
                    databases.append(path)
    if not databases:
        raise ValueError("no SQLite database found in restored data")
    for path in databases:
        uri = f"file:{path}?mode=ro"
        with closing(sqlite3.connect(uri, uri=True)) as db:
            result = db.execute("PRAGMA integrity_check").fetchone()
        if result != ("ok",):
            raise ValueError(f"SQLite integrity check failed: {path}")
        print(f"SQLite integrity ok: {path}")
    return len(databases)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir")
    parser.add_argument("--uid", type=int, required=True)
    args = parser.parse_args()
    verify(args.data_dir, args.uid)


if __name__ == "__main__":
    main()
