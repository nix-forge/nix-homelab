{ homelabModule }: {
  name = "homelab-cross-seed";
  nodes.machine =
    { pkgs, ... }:
    let
      fixture = pkgs.runCommand "public-cross-seed-media" { nativeBuildInputs = [ pkgs.ffmpeg ]; } (
        builtins.readFile ./scripts/public-cross-seed-media.sh
      );
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
        (pkgs.python3.withPackages (_: [ pkgs.notification-process ]))
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
        script = (import ../../lib/render-text.nix) ./scripts/prepare-cross-seed-credentials.sh {
          pkgs_python3 = pkgs.python3;
          pythonCheck1 = ./scripts/prepare_cross_seed_settings.py;

        };
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
  testScript = builtins.readFile ./scripts/cross_seed_test.py;
}
