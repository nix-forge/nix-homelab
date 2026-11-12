"""Create media directories without following service-controlled symlinks."""

import argparse
import grp
import os
import pwd
import stat
import sys

SYSTEM_DIRECTORIES = {
    "/",
    "/bin",
    "/sbin",
    "/lib",
    "/lib64",
    "/boot",
    "/dev",
    "/etc",
    "/media",
    "/mnt",
    "/opt",
    "/var/lib/private",
    "/home",
    "/root",
    "/nix",
    "/proc",
    "/run",
    "/srv",
    "/sys",
    "/usr",
    "/var",
    "/var/lib",
    "/var/cache",
    "/var/log",
    "/var/tmp",  # ruff: ignore[hardcoded-temp-file] - system directory refusal.
    "/tmp",  # ruff: ignore[hardcoded-temp-file] - refuse altering these system directories.
}
SYSTEM_TREES = (
    "/bin",
    "/sbin",
    "/lib",
    "/lib64",
    "/boot",
    "/dev",
    "/etc",
    "/nix",
    "/proc",
    "/sys",
    "/usr",
    "/var/lib/private",
    "/run/credentials",
    "/run/secrets",
)


def prepare(path, group, *, owner=0, mode=0o2770):
    components = [part for part in path.split("/") if part not in {"", "."}]
    if not path.startswith("/") or not components or ".." in components:
        raise ValueError("Dedicated absolute directory required")
    normalized = "/" + "/".join(components)
    if normalized in SYSTEM_DIRECTORIES or any(
        normalized.startswith(tree + "/") for tree in SYSTEM_TREES
    ):
        raise ValueError("Media directories must not replace system directories")
    if mode & stat.S_IRWXO or mode & stat.S_IRWXU != stat.S_IRWXU:
        raise ValueError("Media directories require private owner-write permissions")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open("/", flags)
    try:
        for component in components:
            created = False
            try:
                os.mkdir(component, mode=0o755, dir_fd=descriptor)
                created = True
            except FileExistsError:
                created = False
            child = os.open(component, flags, dir_fd=descriptor)
            if created:
                # Parent directories permit traversal without granting media write access.
                os.fchmod(child, 0o755)
            os.close(descriptor)
            descriptor = child
        os.fchown(descriptor, owner, group)
        os.fchmod(descriptor, mode)
    finally:
        os.close(descriptor)


def main():
    """Prepare selected dedicated directories with the requested ownership."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner", default="root")
    parser.add_argument("--mode", default="2770")
    parser.add_argument("group")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    gid = grp.getgrnam(args.group).gr_gid
    uid = pwd.getpwnam(args.owner).pw_uid
    for target in args.paths:
        prepare(target, gid, owner=uid, mode=int(args.mode, 8))


if __name__ == "__main__":
    try:
        main()
    except OSError, KeyError, ValueError, IndexError:
        sys.exit(
            "Media directory preparation failed; use dedicated private paths without symlinks"
        )
