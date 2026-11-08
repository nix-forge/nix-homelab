"""Install public definitions without following links in service-owned state."""

import argparse
import json
import os
import re
import secrets
import shutil
import stat
import sys
from contextlib import ExitStack, contextmanager, suppress
from pathlib import Path

DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_MODE = 0o644


@contextmanager
def public_source(source: Path, store: Path):
    """Open an immutable regular file inside the trusted Nix store.

    Yields:
        A readable binary file with a bounded lifetime.

    Raises:
        ValueError: The source escapes the store or is not a regular file.

    """
    resolved = source.resolve(strict=True)
    if not source.is_relative_to(store) or not resolved.is_relative_to(store):
        raise ValueError("Definition sources must stay inside the immutable store")
    descriptor = os.open(resolved, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as original:
        if not stat.S_ISREG(os.fstat(original.fileno()).st_mode):
            raise ValueError("Definition sources must be regular files")
        yield original


def install(state: Path, definitions: dict[str, str], store: Path) -> None:
    """Atomically replace declared files through anchored directory descriptors.

    Raises:
        ValueError: A filename is unsafe or its source escapes the immutable store.

    """
    if not all(
        re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*\.(yml|yaml)", name)
        for name in definitions
    ):
        raise ValueError("Invalid definition filename")
    with ExitStack() as cleanup:
        directory = os.open(state, DIRECTORY_FLAGS)
        cleanup.callback(os.close, directory)
        for name in ("Definitions", "Custom"):
            created = False
            with suppress(FileExistsError):
                os.mkdir(name, mode=0o755, dir_fd=directory)
                created = True
            directory = os.open(name, DIRECTORY_FLAGS, dir_fd=directory)
            cleanup.callback(os.close, directory)
            if created:
                # The service must read definitions even with a private unit umask.
                os.fchmod(directory, 0o755)
        for name, source in definitions.items():
            temporary = ".homelab-" + secrets.token_hex(12)
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                FILE_MODE,
                dir_fd=directory,
            )
            try:
                with (
                    os.fdopen(descriptor, "wb") as target,
                    public_source(Path(source), store) as original,
                ):
                    shutil.copyfileobj(original, target)
                    target.flush()
                    os.fchmod(target.fileno(), FILE_MODE)
                    os.fsync(target.fileno())
                os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
                os.fsync(directory)
            finally:
                with suppress(FileNotFoundError):
                    os.unlink(temporary, dir_fd=directory)


def load_specification(path: Path) -> dict[str, str]:
    """Read a public filename-to-source mapping.

    Returns:
        The declared public filenames and source paths.

    Raises:
        ValueError: The mapping contains non-string filenames or sources.

    """
    definitions = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(definitions, dict) or not all(
        isinstance(name, str) and isinstance(source, str)
        for name, source in definitions.items()
    ):
        raise ValueError(
            "Definition specification must map filenames to public source paths"
        )
    return definitions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state", type=Path)
    parser.add_argument("specification", type=Path)
    parser.add_argument("store", type=Path)
    arguments = parser.parse_args()
    try:
        install(
            arguments.state,
            load_specification(arguments.specification),
            arguments.store,
        )
    except OSError, ValueError:
        print(  # ruff: ignore[print] - one sanitized CLI diagnostic, never credentials.
            "Custom definition installation failed; check public sources and state directory links",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
