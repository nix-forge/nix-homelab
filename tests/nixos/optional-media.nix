{ homelabModule }: {
  name = "homelab-optional-media";
  nodes.machine = { pkgs, lib, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    services = {
      cross-seed = {
        package = pkgs.writeShellScriptBin "cross-seed" "exit 0";
        settings.linkDirs = [ "/mnt/media/data/cross-seed" ];
        settingsFile = "/etc/cross-seed-test.json";
      };
      syncthing.settings.folders.fixture = {
        path = "/var/lib/syncthing/shared";
        devices = [ ];
      };
      unpackerr.settings = {
        start_delay = "1s";
        retry_delay = "1s";
        folders.interval = "1s";
        folder = [
          {
            path = "/mnt/media/data/downloads/torrents";
            move_back = true;
            delete_after = "0s";
            delete_original = false;
            disable_recursion = true;
          }
        ];
      };
    };
    environment = {
      etc."create_unpackerr_fixture.py".source = ./scripts/create_unpackerr_fixture.py;
      systemPackages = [
        pkgs.python3
        pkgs.curl
      ];
      etc."cross-seed-test.json".text = "{}";
      etc."maintainerr-test.htpasswd".text = "viewer:{SHA}qUqP5cyxm6YcTAhz05Hph5gvu9M=\n";
    };
    systemd = {
      services.cross-seed.wantedBy = lib.mkForce [ ];
      services.maintainerr-fixture = {
        after = [ "nftables.service" ];
        requires = [ "nftables.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "homelab-maintainerr";
          ExecStart = "${pkgs.python3}/bin/python3 ${
            pkgs.writers.writePython3 "maintainerr_fixture.py" {
              flakeIgnore = [
                "E501"
                "W503"
              ];
            } (builtins.readFile ./scripts/maintainerr_fixture.py)
          }";
        };
      };
    };
    homelab = {
      optional = {
        apps = {
          unpackerr.enable = true;
          cross-seed.enable = true;
          syncthing.enable = true;
          maintainerr.enable = true;
        };
        maintainerr.htpasswdFile = "/etc/maintainerr-test.htpasswd";
      };
      storage = {
        rootDir = "/mnt/media/data";
        requiredMounts = [ "/mnt/media" ];
      };
    };
    # This fixture supplies its own backend and tests only the proxy boundary.
    systemd.services.homelab-maintainerr.wantedBy = lib.mkForce [ ];
  };
  testScript = builtins.readFile ./scripts/optional_media_test.py;
}
