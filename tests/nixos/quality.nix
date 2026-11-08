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
      preferSubtitleLabeledReleases = true;
      enableAnimeProfile = true;
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
        "quality_runtime.py".source = ../fixtures/quality_runtime.py;
      };
    };
  };
  testScript = builtins.readFile ./scripts/quality_test.py;
}
