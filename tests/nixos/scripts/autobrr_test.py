"""Exercise autobrr with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.start()
machine.wait_for_unit("autobrr.service")
machine.wait_until_succeeds("curl -fsS http://127.0.0.1:7474/api/healthz/readiness")
machine.succeed("python /etc/autobrr_runtime.py")
machine.succeed("systemctl restart autobrr")
machine.wait_until_succeeds("curl -fsS http://127.0.0.1:7474/api/healthz/readiness")
machine.succeed("python /etc/autobrr_runtime.py verify-persistence")
