"""Exercise storage missing with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.wait_for_unit("multi-user.target")
machine.wait_until_succeeds("systemctl is-failed homelab-storage.service")
machine.fail("systemctl is-active nzbget.service")
machine.fail("systemctl is-active navidrome.service")
machine.fail("systemctl is-active slskd.service")
machine.fail("test -d /mnt/absent/media")
machine.succeed("mkdir -p /mnt/absent; mount -t tmpfs tmpfs /mnt/absent")
machine.succeed("systemctl reset-failed homelab-storage nzbget; systemctl start nzbget")
machine.wait_for_unit("nzbget.service")
machine.succeed("test -d /mnt/absent/media/downloads/usenet")
machine.succeed(
    "systemctl reset-failed homelab-slskd-directories slskd; systemctl start slskd"
)
machine.wait_for_unit("slskd.service")
machine.succeed(
    "test $(stat -c %U:%G /mnt/absent/media/downloads/soulseek/complete) = fixture-downloads:media"
)
machine.succeed(
    "test $(stat -c %a /mnt/absent/media/downloads/soulseek/complete) = 2770"
)
machine.succeed("systemctl stop nzbget navidrome homelab-storage")
machine.succeed(
    "mkdir -m 0700 /var/lib/storage-victim; rmdir /mnt/absent/media/library/music; ln -s /var/lib/storage-victim /mnt/absent/media/library/music"
)
machine.fail("systemctl start homelab-storage")
machine.succeed("test $(stat -c %a /var/lib/storage-victim) = 700")
machine.succeed("test $(stat -c %U:%G /var/lib/storage-victim) = root:root")
machine.succeed(
    "rm /mnt/absent/media/library/music; systemctl reset-failed homelab-storage; systemctl start homelab-storage"
)
machine.succeed("test $(stat -c %a /mnt/absent/media/library/music) = 2770")
