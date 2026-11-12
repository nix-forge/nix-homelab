"""Exercise audio runtime with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

for name in ("navidrome", "audiobookshelf"):
    machine.wait_for_unit(name + ".service")
    unit = "homelab-integrate-" + name
    machine.wait_until_succeeds(
        f'test -n "$(systemctl show -p ExecMainExitTimestamp --value {unit})" && test $(systemctl show -p Result --value {unit}) = success'
    )
machine.succeed("python3 @fixtures_audio_runtime_py@ --initialize-progress")
machine.succeed(
    "systemctl restart homelab-integrate-navidrome homelab-integrate-audiobookshelf"
)
machine.succeed("python3 @fixtures_audio_runtime_py@")
machine.succeed("systemctl restart navidrome audiobookshelf")
machine.wait_until_succeeds("curl -sf http://127.0.0.1:4533/ping")
machine.wait_until_succeeds("curl -sf http://127.0.0.1:8000/status")
machine.succeed("python3 @fixtures_audio_runtime_py@")
# Match systemd's actual supplementary groups as well as its mount namespace.
media_gid = machine.succeed("getent group media | cut -d: -f3").strip()
for name in ("navidrome", "audiobookshelf"):
    groups = machine.succeed(
        f"grep '^Groups:' /proc/$(systemctl show -p MainPID --value {name})/status"
    ).split()[1:]
    assert media_gid in groups, (name, groups)
machine.succeed(
    "nsenter -t $(systemctl show -p MainPID --value audiobookshelf) -m -- runuser -u audiobookshelf -g audiobookshelf -G media -- test -r /srv/media/library/audiobooks/Fixture/fixture.flac"
)
# Navidrome has a native RootDirectory and no ordinary executable PATH.
python = machine.succeed("readlink -f $(command -v python3)").strip()
nav_namespace = (
    "nsenter -t $(systemctl show -p MainPID --value navidrome) -m --root -- " + python
)
machine.succeed(
    nav_namespace
    + ' -c \'import os; from pathlib import Path; assert Path("/srv/media/library/music/fixture.flac").read_bytes(); assert os.statvfs("/srv/media/library/music").f_flag & os.ST_RDONLY\''
)
machine.fail(
    "nsenter -t $(systemctl show -p MainPID --value audiobookshelf) -m -- touch /srv/media/library/audiobooks/forbidden"
)
machine.succeed(
    "nsenter -t $(systemctl show -p MainPID --value audiobookshelf) -m -- runuser -u audiobookshelf -g audiobookshelf -G media -- touch /srv/media/downloads/podcasts/allowed"
)
machine.fail(
    nav_namespace
    + ' -c \'from pathlib import Path; Path("/srv/media/library/music/forbidden").write_text("forbidden")\''
)
