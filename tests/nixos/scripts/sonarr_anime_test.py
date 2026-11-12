"""Exercise sonarr anime with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json

machine.wait_for_unit("multi-user.target")
for name in ["sonarr", "sonarr-anime"]:
    machine.wait_for_unit(f"{name}.service")
    machine.succeed(
        f"test $(systemctl show -p ExecMainStartTimestampMonotonic --value homelab-integrate-{name}.service) -gt 0"
    )
    machine.succeed(
        f"test $(systemctl show -p Result --value homelab-integrate-{name}.service) = success"
    )

assert (
    machine.succeed(
        "curl -s -o /dev/null -w '%{http_code}' -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:8989/api/v3/system/status"
    )
    == "200"
)
assert (
    machine.succeed(
        "curl -s -o /dev/null -w '%{http_code}' -H 'X-Api-Key: fedcba9876543210fedcba9876543210' http://127.0.0.1:8990/api/v3/system/status"
    )
    == "200"
)
assert (
    machine.succeed(
        "curl -s -o /dev/null -w '%{http_code}' -H 'X-Api-Key: fedcba9876543210fedcba9876543210' http://127.0.0.1:8989/api/v3/system/status"
    )
    == "401"
)
assert (
    machine.succeed(
        "curl -s -o /dev/null -w '%{http_code}' -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:8990/api/v3/system/status"
    )
    == "401"
)

for name, port, key, expected in [
    ("sonarr", 8989, "0123456789abcdef0123456789abcdef", "/srv/media/library/tv"),
    (
        "sonarr-anime",
        8990,
        "fedcba9876543210fedcba9876543210",
        "/srv/media/library/anime",
    ),
]:
    folders = json.loads(
        machine.succeed(
            f"curl -sf -H 'X-Api-Key: {key}' http://127.0.0.1:{port}/api/v3/rootfolder"
        )
    )
    assert [folder["path"] for folder in folders] == [expected], (name, folders)
    machine.succeed(f"systemctl start homelab-integrate-{name}.service")
    folders_again = json.loads(
        machine.succeed(
            f"curl -sf -H 'X-Api-Key: {key}' http://127.0.0.1:{port}/api/v3/rootfolder"
        )
    )
    assert [folder["id"] for folder in folders_again] == [
        folder["id"] for folder in folders
    ]

machine.succeed("test -f /var/lib/sonarr/.config/NzbDrone/sonarr.db")
machine.succeed("test -f /var/lib/homelab-sonarr-anime/sonarr.db")
