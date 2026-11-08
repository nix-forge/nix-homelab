{ homelabModule }: {
  name = "homelab-native-pressure";
  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      homelabModule
      ../fixtures/qbittorrent-offline.nix
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1024;
    environment.systemPackages = [ pkgs.python3 ];
    environment.etc = {
      "pressure-fixture/pressure.py".source = ../../scripts/operations/pressure.py;
      "pressure-fixture/run.py".source = ../fixtures/pressure_runtime.py;
    };
    homelab.operations = {
      enable = true;
      monitoring.enable = true;
      pressure = {
        enable = true;
        path = "/var/lib";
        requiredMounts = [ ];
        pauseBytes = 1;
        resumeBytes = 2;
        clients.qbittorrent = {
          url = "http://127.0.0.1:8081";
          credentialsFile = "/run/pressure-api.json";
        };
      };
    };
    systemd.timers.homelab-storage-pressure.wantedBy = lib.mkForce [ ];

    homelab.apps.qbittorrent = {
      enable = true;
      vpn.enable = false;
      credentialsFile = "/run/pressure-qbit.ini";
    };
    systemd.services.pressure-credentials = {
      before = [ "qbittorrent.service" ];
      requiredBy = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = (import ../../lib/render-text.nix) ./scripts/prepare-pressure-credentials.sh {
        pkgs_python3 = pkgs.python3;
        pythonCheck1 = ./scripts/prepare_pressure_credentials.py;

      };
    };
  };
  testScript = builtins.readFile ./scripts/pressure_test.py;
}
