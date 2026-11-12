{ homelabModule }: {
  name = "homelab-media-runtime";
  nodes.machine = { pkgs, ... }: {
    imports = [
      homelabModule
      ../fixtures/qbittorrent-offline.nix
      ../fixtures/nzbget-credentials.nix
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 4096;
    virtualisation.diskSize = 8192;
    homelab = {
      profiles.media.enable = true;
      apps = {
        qbittorrent = {
          vpn.enable = false;
          credentialsFile = "/run/test-qbit-webui.ini";
        };
        sabnzbd.enable = true;
        nzbget.enable = true;
        lidarr.enable = true;
        navidrome.enable = true;
        audiobookshelf.enable = true;
      };
    };
    systemd.services.test-qbit-credentials = {
      before = [ "qbittorrent.service" ];
      requiredBy = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = (import ../../lib/render-text.nix) ./scripts/prepare-media-runtime-credentials.sh {
        pkgs_python3 = pkgs.python3;
        pythonCheck1 = ./scripts/prepare_media_runtime_credentials.py;

      };
    };
    environment.systemPackages = [ pkgs.curl ];
  };
  testScript = builtins.readFile ./scripts/media_runtime_test.py;
}
