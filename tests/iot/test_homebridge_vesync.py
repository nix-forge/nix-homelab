"""Behavior checks for VeSync credential path migration."""

import json
import subprocess
import sys
from pathlib import Path

SOURCE = Path(__file__).parents[2] / "modules/iot/scripts/homebridge_vesync_config.py"


def test_plaintext_is_removed_and_unrelated_settings_survive(tmp_path: Path) -> None:
    """A previous UI credential is replaced by runtime file references."""
    config = tmp_path / "config.json"
    username = tmp_path / "username"
    password = tmp_path / "password"
    username.write_text("private-test-user")
    password.write_text("private-test-password")
    config.write_text(
        json.dumps({
            "bridge": {"name": "Living Room"},
            "platforms": [
                {
                    "platform": "TSVESyncPlatform",
                    "name": "Air",
                    "username": "old-user",
                    "password": "old-password",
                    "devices": [{"id": "lamp"}],
                },
                {"platform": "OtherPlatform", "enabled": True},
            ],
        })
    )
    command = [sys.executable, str(SOURCE), str(config), str(username), str(password)]
    subprocess.run(command, check=True)
    first = config.read_bytes()
    document = json.loads(first)
    vesync, other = document["platforms"]
    assert vesync["usernameFile"] == str(username)
    assert vesync["passwordFile"] == str(password)
    assert "username" not in vesync
    assert "password" not in vesync
    assert vesync["devices"] == [{"id": "lamp"}]
    assert other == {"platform": "OtherPlatform", "enabled": True}
    assert document["bridge"] == {"name": "Living Room"}
    assert b"private-test-password" not in first
    assert b"old-password" not in first
    subprocess.run(command, check=True)
    assert config.read_bytes() == first
