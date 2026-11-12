"""Install declared Jellyfin plugins without replacing UI-managed plugins."""

import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9 _.-]*\Z")
MARKER = ".nix-managed"


def copy_payload(source: Path, staged: Path, source_name: str) -> None:
    shutil.copytree(source, staged)
    for path in staged.rglob("*"):
        path.chmod(0o700 if path.is_dir() else 0o600)
    staged.chmod(0o700)
    (staged / MARKER).write_text(source_name + "\n", encoding="utf-8")


def install_one(plugin_dir: Path, name: str, source_name: str) -> None:
    if not NAME.fullmatch(name) or name in {".", ".."}:
        raise ValueError(f"Invalid plugin name: {name!r}")
    source = Path(source_name)
    if not source.is_dir() or source.is_symlink():
        raise ValueError(f"Plugin package is not a directory: {source}")
    destination = plugin_dir / name
    marker = destination / MARKER
    if destination.is_symlink():
        raise ValueError(f"Plugin destination is a symlink: {destination}")
    if destination.exists():
        managed = destination.is_dir() and marker.is_file()
        if not managed or marker.is_symlink():
            raise ValueError(f"unmanaged plugin directory: {destination}")
        if marker.read_text(encoding="utf-8").strip() == source_name:
            return

    with tempfile.TemporaryDirectory(
        prefix=".homelab-plugin-", dir=plugin_dir
    ) as work_name:
        work = Path(work_name)
        staged = work / "new"
        copy_payload(source, staged, source_name)
        old = work / "old"
        if destination.exists():
            destination.replace(old)
        try:
            staged.replace(destination)
        except OSError:
            if old.exists():
                old.replace(destination)
            raise


def install_plugins(plugin_dir: Path, packages: dict[str, str]) -> None:
    if plugin_dir.is_symlink():
        raise ValueError(f"Plugin directory is a symlink: {plugin_dir}")
    plugin_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name, source_name in packages.items():
        install_one(plugin_dir, name, source_name)


def main() -> None:
    expected_arguments = 3
    if len(sys.argv) != expected_arguments:
        raise SystemExit("usage: installer MANIFEST PLUGIN_DIR")
    packages = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    if not isinstance(packages, dict) or not all(
        isinstance(name, str) and isinstance(source, str)
        for name, source in packages.items()
    ):
        raise ValueError("Plugin manifest must map names to packages")
    install_plugins(Path(sys.argv[2]), packages)


if __name__ == "__main__":
    main()
