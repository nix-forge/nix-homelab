"""Exercise optional media with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

from datetime import timedelta

machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("syncthing.service")
machine.wait_for_unit("nginx.service")
machine.wait_for_unit("maintainerr-fixture.service")
machine.succeed(
    "test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6246/api/health/ready) = 401"
)
machine.succeed(
    "test $(curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready) = cleared"
)
machine.fail(
    "runuser -u nobody -- curl -fsS --max-time 3 http://127.0.0.1:6247/api/health/ready"
)
machine.wait_until_succeeds("test -f /var/lib/syncthing/.config/syncthing/config.xml")
machine.wait_until_succeeds("test -d /var/lib/syncthing/shared/.stfolder")
machine.wait_until_succeeds("systemctl is-failed homelab-storage.service")
machine.fail("systemctl is-active unpackerr.service")
machine.fail("test -e /mnt/media/data")
machine.succeed("mkdir -p /mnt/media; mount -t tmpfs tmpfs /mnt/media")
machine.succeed("systemctl reset-failed; systemctl start unpackerr.service")
machine.wait_for_unit("unpackerr.service")
machine.succeed(
    "python3 /etc/create_unpackerr_fixture.py /mnt/media/data/downloads/torrents/fixture"
)
machine.succeed(
    "chown -R unpackerr:media /mnt/media/data/downloads/torrents/fixture; chmod 2770 /mnt/media/data/downloads/torrents/fixture"
)
machine.wait_until_succeeds(
    "test -f /mnt/media/data/downloads/torrents/fixture/fixture.txt",
    timeout=timedelta(minutes=2),
)
machine.succeed(
    "test $(stat -c %a:%G /mnt/media/data/downloads/torrents/fixture/fixture.txt) = 660:media"
)
machine.succeed("test -f /mnt/media/data/downloads/torrents/fixture/fixture.zip")
machine.succeed(
    "grep -q 'permitted fixture media' /mnt/media/data/downloads/torrents/fixture/fixture.txt"
)
# Check the live service mount namespace, not only the host user's DAC rights.
pid = machine.succeed("systemctl show unpackerr.service -p MainPID --value").strip()
machine.fail(f"nsenter -t {pid} -m touch /mnt/media/data/library/forbidden")
machine.succeed("systemctl restart unpackerr.service")
machine.wait_for_unit("unpackerr.service")
machine.succeed("test -f /mnt/media/data/downloads/torrents/fixture/fixture.zip")
machine.succeed(
    "mkdir -m 0700 /var/lib/guard-victim; rmdir /mnt/media/data/cross-seed; ln -s /var/lib/guard-victim /mnt/media/data/cross-seed"
)
machine.fail("systemctl restart homelab-optional-storage.service")
machine.succeed("test $(stat -c %a:%U:%G /var/lib/guard-victim) = 700:root:root")
