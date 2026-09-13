{ homelabModule }: {
  name = "homelab-quality";
  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      homelabModule
      ../../examples/quality-4k.nix
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 2048;
    services = {
      radarr = {
        enable = true;
        environmentFiles = [ "/etc/radarr-fixture" ];
      };
      sonarr = {
        enable = true;
        environmentFiles = [ "/etc/sonarr-fixture" ];
      };
      recyclarr.command = "sync --preview";
    };
    homelab.optional.quality = {
      sonarrApiKeyFile = lib.mkForce "/etc/quality-api-key";
      radarrApiKeyFile = lib.mkForce "/etc/quality-api-key";
    };
    systemd.timers.recyclarr.wantedBy = lib.mkForce [ ];
    environment = {
      systemPackages = [
        pkgs.python3
        pkgs.curl
        pkgs.recyclarr
      ];
      etc = {
        "quality-api-key".text = "0123456789abcdef0123456789abcdef";
        "radarr-fixture".text = "RADARR__AUTH__APIKEY=0123456789abcdef0123456789abcdef\n";
        "sonarr-fixture".text = "SONARR__AUTH__APIKEY=0123456789abcdef0123456789abcdef\n";
        "quality-runtime.py".source = ../fixtures/quality-runtime.py;
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("radarr.service")
    machine.wait_for_unit("sonarr.service")
    for port in (7878, 8989):
        machine.wait_until_succeeds(f"curl -fsS -o /dev/null -H X-Api-Key:0123456789abcdef0123456789abcdef http://127.0.0.1:{port}/api/v3/qualityprofile")
    machine.succeed("python /etc/quality-runtime.py before")
    machine.succeed("systemctl start recyclarr.service")
    machine.succeed("python /etc/quality-runtime.py preview")
    apply = "su -s /bin/sh recyclarr -c 'RECYCLARR_CONFIG_DIR=/var/lib/recyclarr RECYCLARR_DATA_DIR=/var/lib/recyclarr recyclarr sync --config /var/lib/recyclarr/config.yml'"
    machine.succeed(apply)
    # Native Arr bulk updates retain the five-second quality-definition cache.
    # Poll the exact bounds; do not mistake a stale read for failed persistence.
    machine.wait_until_succeeds("python /etc/quality-runtime.py applied", timeout=30)
    machine.succeed("python /etc/quality-runtime.py manual-score")
    machine.succeed(apply)
    machine.succeed("python /etc/quality-runtime.py repeat")
  '';
}
