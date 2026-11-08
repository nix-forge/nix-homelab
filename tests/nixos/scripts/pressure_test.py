"""Exercise pressure with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

from datetime import timedelta

machine.wait_for_unit("qbittorrent.service")
machine.wait_for_open_port(8081)
machine.succeed(
    "PYTHONPATH=/etc/pressure-fixture python /etc/pressure-fixture/run.py",
    timeout=timedelta(seconds=90),
)
machine.succeed("systemctl start homelab-storage-pressure.service")
machine.succeed("test $(cat /var/lib/homelab-monitoring/pressure) = ready")
# Exercise the boot race while retaining the real downloader and its state.
machine.succeed("systemctl stop qbittorrent")
machine.succeed(
    "systemd-run --on-active=2s --unit=pressure-delayed-downloader systemctl start qbittorrent"
)
machine.succeed("systemctl start homelab-storage-pressure.service")
machine.succeed(
    "systemctl show homelab-storage-pressure.service --property=Result --value | grep -x success"
)
machine.wait_for_open_port(8081)
machine.succeed(
    "PYTHONPATH=/etc/pressure-fixture python /etc/pressure-fixture/run.py verify",
    timeout=timedelta(seconds=90),
)
