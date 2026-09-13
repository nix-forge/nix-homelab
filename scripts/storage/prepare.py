"""Create media directories without following service-controlled symlinks."""

import grp
import os
import sys


def prepare(path, group):
    components = [part for part in path.split("/") if part not in ("", ".")]
    if not path.startswith("/") or not components or ".." in components:
        raise ValueError("Dedicated absolute directory required")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open("/", flags)
    try:
        for component in components:
            created = False
            try:
                os.mkdir(component, mode=0o755, dir_fd=descriptor)
                created = True
            except FileExistsError:
                pass
            child = os.open(component, flags, dir_fd=descriptor)
            if created:
                # Parent directories permit traversal without granting media write access.
                os.fchmod(child, 0o755)
            os.close(descriptor)
            descriptor = child
        os.fchown(descriptor, 0, group)
        os.fchmod(descriptor, 0o2770)
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    try:
        gid = grp.getgrnam(sys.argv[1]).gr_gid
        for target in sys.argv[2:]:
            prepare(target, gid)
    except (OSError, KeyError, ValueError, IndexError):
        sys.exit("Media directory preparation failed; paths must not contain symlinks")
