"""Exercise cross seed with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.wait_for_unit("multi-user.target")
machine.wait_until_succeeds("curl -fsS http://127.0.0.1:2468/api/ping")
machine.succeed("python -u /etc/cross-seed-fixture/acceptance.py 2>&1", timeout=240)
