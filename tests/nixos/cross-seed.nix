{ homelabModule }: {
  name = "homelab-cross-seed";
  nodes.machine =
    { pkgs, ... }:
    let
      fixture = pkgs.runCommand "public-cross-seed-media" { nativeBuildInputs = [ pkgs.ffmpeg ]; } ''
        mkdir -p $out
        ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i color=c=blue:s=1920x1080:r=1 \
          -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
          -t 120 -c:v mpeg4 -c:a aac $out/Workflow.Fixture.2026.1080p.WEB-DL.mkv
      '';
    in
    {
      imports = [
        homelabModule
        ../fixtures/qbittorrent-offline.nix
        ../../modules/optional
      ];
      system.stateVersion = "26.05";
      virtualisation = {
        memorySize = 2048;
        diskSize = 4096;
        cores = 2;
      };
      environment.systemPackages = [
        pkgs.python3
        pkgs.curl
      ];
      environment.etc."cross-seed-fixture/acceptance.py".source = ../fixtures/cross-seed/acceptance.py;
      systemd.services.cross-seed-fixture = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python ${../fixtures/cross-seed/provider.py} ${fixture}";
      };
      systemd.services.cross-seed-credentials = {
        before = [
          "qbittorrent.service"
          "cross-seed.service"
        ];
        requiredBy = [
          "qbittorrent.service"
          "cross-seed.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          umask 077
          ${pkgs.python3}/bin/python - <<'PY'
          import base64, hashlib, json
          salt = b'public-cross-seed-salt'
          password = b'public-cross-seed-password'
          digest = hashlib.pbkdf2_hmac('sha512', password, salt, 100000)
          encoded = base64.b64encode(salt).decode() + ':' + base64.b64encode(digest).decode()
          with open('/run/cross-seed-qbit.ini', 'w') as handle:
              handle.write('[Preferences]\nWebUI\\Username=admin\nWebUI\\Password_PBKDF2="@ByteArray(' + encoded + ')"\n')
          with open('/run/cross-seed-settings.json', 'w') as handle:
              json.dump({
                  'apiKey': 'public-cross-seed-api-key-0123456789',
                  'torrentClients': ['qbittorrent:http://admin:public-cross-seed-password@127.0.0.1:8081'],
                  'torznab': ['http://127.0.0.1:18091/api?apikey=public-fixture'],
              }, handle)
          PY
        '';
      };
      homelab.apps.qbittorrent = {
        enable = true;
        vpn.enable = false;
        credentialsFile = "/run/cross-seed-qbit.ini";
      };
      homelab.optional.apps.cross-seed.enable = true;

      services.cross-seed = {
        settingsFile = "/run/cross-seed-settings.json";
        settings = {
          rssCadence = null;
          searchCadence = null;
          delay = 30;
        };
      };
      systemd.services.cross-seed = {
        after = [
          "cross-seed-fixture.service"
          "qbittorrent.service"
        ];
        requires = [
          "cross-seed-fixture.service"
          "qbittorrent.service"
        ];
      };
    };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:2468/api/ping")
    machine.succeed("python -u /etc/cross-seed-fixture/acceptance.py 2>&1", timeout=240)
  '';
}
