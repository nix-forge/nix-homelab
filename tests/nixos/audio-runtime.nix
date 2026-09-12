{ homelabModule }: {
  name = "homelab-audio-runtime";
  nodes.machine =
    { pkgs, lib, ... }:
    let
      audio = pkgs.runCommand "public-audio-fixture" { nativeBuildInputs = [ pkgs.ffmpeg ]; } ''
        mkdir -p $out
        ffmpeg -hide_banner -loglevel error -f lavfi -i sine=frequency=440:duration=3 \
          -metadata title='Public fixture' -metadata artist='Fixture' -metadata album='Fixture' $out/fixture.flac
      '';
    in
    {
      imports = [
        homelabModule
        ../../examples/audio.nix
      ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.python3 ];
      environment.etc."audio-fixture.flac".source = "${audio}/fixture.flac";
      systemd.services = {
        audio-fixture = {
          wantedBy = [ "multi-user.target" ];
          before = [
            "navidrome.service"
            "audiobookshelf.service"
            "homelab-integrate-navidrome.service"
            "homelab-integrate-audiobookshelf.service"
          ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script = ''
            install -d -m 0700 /run/nix-seal/system/secrets
            for name in navidrome-admin-password navidrome-listener-password audiobookshelf-admin-password audiobookshelf-listener-password; do
              printf '%s' 'public-disposable-audio-password' > /run/nix-seal/system/secrets/$name
              chmod 0600 /run/nix-seal/system/secrets/$name
            done
            printf '%s\n' 'ND_PASSWORDENCRYPTIONKEY=public-disposable-audio-encryption-key' > /run/nix-seal/system/secrets/navidrome.env
            chmod 0600 /run/nix-seal/system/secrets/navidrome.env
          '';
        };
        homelab-storage.script = lib.mkAfter ''
          install -m 0640 -o root -g media ${audio}/fixture.flac /srv/media/library/music/fixture.flac
          install -d -m 2770 -o root -g media /srv/media/library/audiobooks/Fixture
          install -m 0640 -o root -g media ${audio}/fixture.flac /srv/media/library/audiobooks/Fixture/fixture.flac
        '';
        navidrome.requires = [ "audio-fixture.service" ];
        audiobookshelf.requires = [ "audio-fixture.service" ];
      };
      homelab.integration.services.navidrome.after = [ "audio-fixture.service" ];
      homelab.integration.services.audiobookshelf.after = [ "audio-fixture.service" ];
    };
  testScript = ''
    for name in ("navidrome", "audiobookshelf"):
        machine.wait_for_unit(name + ".service")
        unit = "homelab-integrate-" + name
        machine.wait_until_succeeds(f"test -n \"$(systemctl show -p ExecMainExitTimestamp --value {unit})\" && test $(systemctl show -p Result --value {unit}) = success")
    machine.succeed("python3 ${../fixtures/audio-runtime.py} --initialize-progress")
    machine.succeed("systemctl restart homelab-integrate-navidrome homelab-integrate-audiobookshelf")
    machine.succeed("python3 ${../fixtures/audio-runtime.py}")
    machine.succeed("systemctl restart navidrome audiobookshelf")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:4533/ping")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:8000/status")
    machine.succeed("python3 ${../fixtures/audio-runtime.py}")
    # Match systemd's actual supplementary groups as well as its mount namespace.
    media_gid = machine.succeed("getent group media | cut -d: -f3").strip()
    for name in ("navidrome", "audiobookshelf"):
        groups = machine.succeed(f"grep '^Groups:' /proc/$(systemctl show -p MainPID --value {name})/status").split()[1:]
        assert media_gid in groups, (name, groups)
    machine.succeed("nsenter -t $(systemctl show -p MainPID --value audiobookshelf) -m -- runuser -u audiobookshelf -g audiobookshelf -G media -- test -r /srv/media/library/audiobooks/Fixture/fixture.flac")
    # Navidrome has a native RootDirectory and no ordinary executable PATH.
    python = machine.succeed("readlink -f $(command -v python3)").strip()
    nav_namespace = "nsenter -t $(systemctl show -p MainPID --value navidrome) -m --root -- " + python
    machine.succeed(nav_namespace + " -c 'import os; from pathlib import Path; assert Path(\"/srv/media/library/music/fixture.flac\").read_bytes(); assert os.statvfs(\"/srv/media/library/music\").f_flag & os.ST_RDONLY'")
    machine.fail("nsenter -t $(systemctl show -p MainPID --value audiobookshelf) -m -- touch /srv/media/library/audiobooks/forbidden")
    machine.succeed("nsenter -t $(systemctl show -p MainPID --value audiobookshelf) -m -- runuser -u audiobookshelf -g audiobookshelf -G media -- touch /srv/media/downloads/podcasts/allowed")
    machine.fail(nav_namespace + " -c 'from pathlib import Path; Path(\"/srv/media/library/music/forbidden\").write_text(\"forbidden\")'")
  '';
}
