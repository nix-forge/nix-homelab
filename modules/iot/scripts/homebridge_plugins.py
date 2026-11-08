"""Reconcile only the Homebridge plugin symlinks previously installed by Nix."""

import grp
import json
import os
import pwd
import re
import sys
import tempfile
import uuid
from pathlib import Path

NAME = re.compile(r"(?:@[a-z0-9-]+/)?homebridge-[a-z0-9-]+\Z")
LEDGER = ".nix-managed-plugins.json"
ARGUMENT_COUNT = 5


def read_manifest(path: Path) -> dict[str, str]:
    entries = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise TypeError("Invalid Homebridge plugin manifest")
    managed: dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"name", "source"}:
            raise ValueError("Invalid Homebridge plugin manifest")
        name, source = entry["name"], entry["source"]
        if (
            not isinstance(name, str)
            or not NAME.fullmatch(name)
            or not isinstance(source, str)
            or not source.startswith("/nix/store/")
            or name in managed
        ):
            raise ValueError("Invalid Homebridge plugin manifest")
        managed[name] = source
    return managed


def read_ledger(path: Path) -> dict[str, str]:
    if path.is_symlink():
        raise ValueError("Homebridge plugin ledger must not be a symlink")
    if not path.exists():
        return {}
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("schema") != 1:
        raise ValueError("Invalid Homebridge plugin ledger")
    managed = document.get("managed")
    if not isinstance(managed, dict) or any(
        not isinstance(name, str)
        or not NAME.fullmatch(name)
        or not isinstance(source, str)
        or not source.startswith("/")
        for name, source in managed.items()
    ):
        raise ValueError("Invalid Homebridge plugin ledger")
    return managed


def write_ledger(path: Path, managed: dict[str, str]) -> None:
    descriptor, temporary = tempfile.mkstemp(
        prefix=".nix-managed-plugins.", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump({"schema": 1, "managed": managed}, output, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        Path(temporary).chmod(0o600)
        Path(temporary).replace(path)
    finally:
        if os.path.lexists(temporary):
            Path(temporary).unlink()


def install_links(
    plugin_path: Path,
    managed: dict[str, str],
    previous: dict[str, str],
    uid: int,
    gid: int,
) -> None:
    for name, source in managed.items():
        if not Path(source).is_dir():
            raise ValueError(f"Homebridge plugin package has no node module: {name}")
        destination = plugin_path / name
        if destination.parent.is_symlink():
            raise ValueError(f"Homebridge plugin scope must not be a symlink: {name}")
        destination.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        ownership = destination.parent.stat()
        if (ownership.st_uid, ownership.st_gid) != (uid, gid):
            raise ValueError(
                f"Homebridge plugin directory has unexpected owner: {name}"
            )
        if destination.exists() and not destination.is_symlink():
            raise ValueError(f"Refusing to replace a mutable Homebridge plugin: {name}")
        if destination.is_symlink() and destination.readlink() not in {
            Path(source),
            Path(previous.get(name, "")),
        }:
            raise ValueError(
                f"Refusing to replace a Homebridge plugin link changed outside Nix: {name}"
            )
        if destination.is_symlink() and destination.readlink() == Path(source):
            continue
        temporary = destination.parent / f".nix-plugin-{uuid.uuid4().hex}"
        try:
            temporary.symlink_to(source)
            temporary.replace(destination)
        finally:
            if temporary.is_symlink():
                temporary.unlink()


def prune_links(
    plugin_path: Path, previous: dict[str, str], managed: dict[str, str]
) -> None:
    for name, source in previous.items():
        if name in managed:
            continue
        destination = plugin_path / name
        if destination.parent.is_symlink():
            raise ValueError(f"Homebridge plugin scope must not be a symlink: {name}")
        if destination.is_symlink() and destination.readlink() == Path(source):
            destination.unlink()


def reconcile(manifest: Path, plugin_path: Path, user: str, group: str) -> None:
    managed = read_manifest(manifest)
    if plugin_path.is_symlink():
        raise ValueError("Homebridge plugin directory must not be a symlink")
    plugin_path.mkdir(mode=0o755, parents=True, exist_ok=True)
    previous = read_ledger(plugin_path / LEDGER)
    uid = pwd.getpwnam(user).pw_uid
    gid = grp.getgrnam(group).gr_gid
    install_links(plugin_path, managed, previous, uid, gid)
    prune_links(plugin_path, previous, managed)
    write_ledger(plugin_path / LEDGER, managed)


if __name__ == "__main__":
    if len(sys.argv) != ARGUMENT_COUNT:
        raise SystemExit("usage: homebridge-plugins MANIFEST PLUGIN_PATH USER GROUP")
    reconcile(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4])
