"""Exercise maintainerr with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

from datetime import timedelta

machine.wait_for_unit("nginx.service")
machine.wait_for_unit("homelab-maintainerr.service")
machine.wait_until_succeeds(
    "curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready >/dev/null",
    timeout=timedelta(minutes=3),
)
machine.succeed("curl -fsS -u viewer:test http://127.0.0.1:6246/ >/dev/null")
machine.succeed(
    "getent ahostsv4 host.containers.internal | grep -q '^127\\.0\\.0\\.1 '"
)
machine.succeed(
    "test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6246/api/health/ready) = 401"
)
machine.fail(
    "runuser -u nobody -- curl -fsS --max-time 3 http://127.0.0.1:6247/api/health/ready"
)
machine.fail("runuser -u nobody -- test -r /var/lib/homelab-maintainerr/data")
properties = machine.succeed(
    "systemctl show homelab-maintainerr.service -p User -p NoNewPrivileges -p ProtectSystem -p RestrictNamespaces"
)
assert "User=homelab-maintainerr" in properties
assert "NoNewPrivileges=yes" in properties
assert "ProtectSystem=strict" in properties
assert "RestrictNamespaces=yes" in properties
pid = machine.succeed(
    "systemctl show --property MainPID --value homelab-maintainerr.service"
).strip()
status = machine.succeed(f"cat /proc/{pid}/status")
fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
assert fields["Uid"].split()[1] != "0"
assert int(fields["CapEff"].strip(), 16) == 0
assert fields["NoNewPrivs"].strip() == "1"
machine.succeed(
    "runuser -u homelab-maintainerr -- sh -c 'echo fixture > /var/lib/homelab-maintainerr/data/restart-fixture'"
)
machine.succeed("systemctl restart homelab-maintainerr.service")
machine.wait_until_succeeds(
    "curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready >/dev/null",
    timeout=timedelta(minutes=3),
)
machine.succeed("grep -q fixture /var/lib/homelab-maintainerr/data/restart-fixture")
machine.succeed("systemctl start homelab-maintainerr-policy.service")
machine.succeed(
    "systemctl show homelab-maintainerr-policy.service -p Result | grep -Fx 'Result=success'"
)
machine.succeed(
    "mkdir -p /srv/media; mountpoint -q /srv/media || mount -t tmpfs tmpfs /srv/media"
)
machine.succeed("mkdir -p /srv/media/shows/Empty /srv/media/shows/Manual")
machine.succeed("chmod -R 0777 /srv/media/shows")
machine.succeed("printf 'specials\\n' > /srv/media/shows/Manual/.ignore")
machine.succeed("systemctl start homelab-jellyfin-ignore.service")
machine.succeed("test -f /srv/media/shows/Empty/.ignore")
machine.succeed(
    "touch /srv/media/shows/Empty/episode.mkv /srv/media/shows/Manual/episode.mkv"
)
machine.succeed("systemctl start homelab-jellyfin-ignore.service")
machine.succeed("test ! -e /srv/media/shows/Empty/.ignore")
machine.succeed("grep -Fx specials /srv/media/shows/Manual/.ignore")
