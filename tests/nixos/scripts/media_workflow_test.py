"""Exercise media workflow with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json

machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("workflow-provider.service")
for service in ["radarr", "jellyfin", "seerr"]:
    machine.succeed(
        f"test $(systemctl show -p Result --value homelab-integrate-{service}.service) = success"
    )
    machine.succeed(
        f"test $(systemctl show -p ExecMainStartTimestampMonotonic --value homelab-integrate-{service}.service) -gt 0"
    )
    machine.succeed(f"systemctl start homelab-integrate-{service}.service")
radarr_naming = json.loads(
    machine.succeed(
        "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:7878/api/v3/config/naming"
    )
)
assert radarr_naming["renameMovies"], radarr_naming
assert "{[Quality Full]}" in radarr_naming["standardMovieFormat"], radarr_naming
machine.succeed("python -u /etc/workflow/library_paths.py 2>&1", timeout=180)
machine.succeed("python -u /etc/workflow/acceptance.py 2>&1", timeout=300)
machine.succeed("python -u /etc/workflow/restore.py 2>&1", timeout=300)
