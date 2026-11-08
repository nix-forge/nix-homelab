"""Keep VeSync credentials out of Homebridge's persistent config.json."""

import json
import os
import pathlib
import stat
import sys
import tempfile


def main() -> None:
    config_path = pathlib.Path(sys.argv[1])
    username_file, password_file = sys.argv[2:4]
    for file_path in (username_file, password_file):
        if not pathlib.Path(file_path).is_file():
            raise RuntimeError("VeSync credential file is unavailable")

    original = config_path.read_text(encoding="utf-8")
    document = json.loads(original)
    platforms = document.setdefault("platforms", [])
    matches = [
        entry for entry in platforms if entry.get("platform") == "TSVESyncPlatform"
    ]
    if len(matches) > 1:
        raise RuntimeError("Multiple VeSync platform entries in Homebridge config")
    platform = (
        matches[0] if matches else {"platform": "TSVESyncPlatform", "name": "TSVESync"}
    )
    if not matches:
        platforms.append(platform)
    platform.pop("username", None)
    platform.pop("password", None)
    platform.update(usernameFile=username_file, passwordFile=password_file)
    updated = json.dumps(document, indent=4, ensure_ascii=False) + "\n"
    if updated == original:
        return

    file_stat = config_path.stat()
    fd, temporary = tempfile.mkstemp(prefix=".config-vesync-", dir=config_path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(updated)
            output.flush()
            os.fsync(output.fileno())
        os.chown(temporary, file_stat.st_uid, file_stat.st_gid)
        pathlib.Path(temporary).chmod(stat.S_IMODE(file_stat.st_mode))
        pathlib.Path(temporary).replace(config_path)
    finally:
        if pathlib.Path(temporary).exists():
            pathlib.Path(temporary).unlink()


if __name__ == "__main__":
    main()
