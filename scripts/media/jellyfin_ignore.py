"""Manage only empty Jellyfin .ignore markers created by this program."""

import argparse
import json
import os
import pathlib
import stat
import tempfile

VIDEO = {
    ".mkv",
    ".mp4",
    ".m4v",
    ".avi",
    ".mov",
    ".wmv",
    ".ts",
    ".flv",
    ".mpg",
    ".mpeg",
    ".webm",
    ".m2ts",
}


def has_video(directory):
    for base, subdirs, files in os.walk(directory, followlinks=False):
        subdirs[:] = [
            name for name in subdirs if not (pathlib.Path(base) / name).is_symlink()
        ]
        if any(pathlib.Path(name).suffix.lower() in VIDEO for name in files):
            return True
    return False


def save(path, entries):
    parent = pathlib.Path(path).parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=parent, prefix=".ignore-")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(entries, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        pathlib.Path(temporary).replace(path)
    finally:
        if pathlib.Path(temporary).exists():
            pathlib.Path(temporary).unlink()


def scan(mount, roots, ledger_path):
    mount = pathlib.Path(mount).resolve(strict=True)
    if not os.path.ismount(mount):
        raise RuntimeError(f"required mount is unavailable: {mount}")
    try:
        with pathlib.Path(ledger_path).open(encoding="utf-8") as stream:
            ledger = json.load(stream)
    except FileNotFoundError:
        ledger = {}
    if not isinstance(ledger, dict):
        raise ValueError("invalid marker ledger")
    for root_arg in roots:
        root = pathlib.Path(root_arg)
        if root.is_symlink():
            raise RuntimeError(f"media root is a symlink: {root}")
        root = root.resolve(strict=True)
        if root == mount or mount not in root.parents:
            raise RuntimeError(f"media root is outside required mount: {root}")
        for directory in root.iterdir():
            if not directory.is_dir() or directory.is_symlink():
                continue
            marker = directory / ".ignore"
            key = str(marker)
            owned = ledger.get(key)
            video = has_video(directory)
            if video and owned:
                try:
                    info = marker.lstat()
                except FileNotFoundError:
                    del ledger[key]
                    save(ledger_path, ledger)
                    continue
                if (
                    stat.S_ISREG(info.st_mode)
                    and info.st_size == 0
                    and [info.st_dev, info.st_ino, info.st_ctime_ns] == owned
                ):
                    marker.unlink()
                    del ledger[key]
                    save(ledger_path, ledger)
                    print(f"removed owned marker: {marker}")
            elif not video and not marker.exists() and not marker.is_symlink():
                fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                os.close(fd)
                info = marker.lstat()
                ledger[key] = [info.st_dev, info.st_ino, info.st_ctime_ns]
                save(ledger_path, ledger)
                print(f"created marker: {marker}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mount", required=True)
    parser.add_argument("--root", action="append", required=True)
    parser.add_argument("--ledger", required=True)
    args = parser.parse_args()
    scan(args.mount, args.root, args.ledger)


if __name__ == "__main__":
    main()
