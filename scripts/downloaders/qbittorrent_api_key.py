"""Install a runtime qBittorrent API key into its private preferences file."""

import os
import pathlib
import re
import sys
import tempfile


def main():
    if len(sys.argv) != 2:
        return 2
    credential_path = pathlib.Path(os.environ["CREDENTIALS_DIRECTORY"]) / "api-key"
    key = credential_path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"qbt_[A-Za-z0-9]{28}", key):
        raise SystemExit("Invalid qBittorrent API key format")

    path = pathlib.Path(sys.argv[1])
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    section = None
    found = False
    for index, line in enumerate(lines):
        if line.startswith("[") and line.rstrip().endswith("]"):
            section = line.strip()
        elif section == "[Preferences]" and line.startswith("WebUI\\APIKey="):
            lines[index] = "WebUI\\APIKey=" + key + "\n"
            found = True
    if not found:
        for index, line in enumerate(lines):
            if line.strip() == "[Preferences]":
                lines.insert(index + 1, "WebUI\\APIKey=" + key + "\n")
                found = True
                break
    if not found:
        raise SystemExit("qBittorrent preferences section is missing")
    original = path.stat()
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".homelab-api-key-", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            os.fchmod(output.fileno(), 0o600)
            if os.geteuid() == 0:
                os.fchown(output.fileno(), original.st_uid, original.st_gid)
            output.write("".join(lines))
            output.flush()
            os.fsync(output.fileno())
        pathlib.Path(temporary_name).replace(path)
    finally:
        pathlib.Path(temporary_name).unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
