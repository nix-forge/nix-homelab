"""Exercise quality with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.start()
machine.wait_for_unit("radarr.service")
machine.wait_for_unit("sonarr.service")
for port in (7878, 8989):
    machine.wait_until_succeeds(
        f"curl -fsS -o /dev/null -H X-Api-Key:0123456789abcdef0123456789abcdef http://127.0.0.1:{port}/api/v3/qualityprofile"
    )
machine.succeed("python /etc/quality_runtime.py before")
machine.succeed("systemctl start recyclarr.service")
machine.succeed("test $(stat -c %a /var/lib/recyclarr) = 700")
machine.succeed("test $(stat -c %a /var/lib/recyclarr/config.yml) = 600")
machine.succeed("test $(stat -c %a /var/lib/recyclarr/settings.yml) = 600")
machine.succeed("python /etc/quality_runtime.py preview")
apply = "su -s /bin/sh recyclarr -c 'RECYCLARR_CONFIG_DIR=/var/lib/recyclarr RECYCLARR_DATA_DIR=/var/lib/recyclarr recyclarr sync --config /var/lib/recyclarr/config.yml'"
machine.succeed(apply)
# Native Arr bulk updates retain the five-second quality-definition cache.
# Poll the exact bounds; do not mistake a stale read for failed persistence.
machine.wait_until_succeeds("python /etc/quality_runtime.py applied", timeout=30)
machine.succeed("python /etc/quality_runtime.py manual-score")
machine.succeed(apply)
machine.succeed("python /etc/quality_runtime.py repeat")
