{ homelabModule }: {
  name = "homelab-sonarr-anime";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    environment.systemPackages = [ pkgs.curl ];
    systemd.services.anime-test-keys = {
      before = [
        "homelab-key-sonarr.service"
        "homelab-key-sonarr-anime.service"
      ];
      requiredBy = [
        "homelab-key-sonarr.service"
        "homelab-key-sonarr-anime.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = builtins.readFile ./scripts/prepare-sonarr-api-keys.sh;
    };
    homelab = {
      apps.sonarr.enable = true;
      optional.apps.sonarr-anime.enable = true;
      integration = {
        enable = true;
        services = {
          sonarr = {
            url = "http://127.0.0.1:8989";
            apiKeyFile = "/run/sonarr-key";
            installApiKey = true;
            resources = [
              {
                endpoint = "rootfolder";
                match.path = "/srv/media/library/tv";
                values = { };
              }
            ];
          };
          sonarr-anime = {
            kind = "sonarr";
            localService = "sonarr-anime";
            url = "http://127.0.0.1:8990";
            apiKeyFile = "/run/anime-key";
            installApiKey = true;
            resources = [
              {
                endpoint = "rootfolder";
                match.path = "/srv/media/library/anime";
                values = { };
              }
            ];
          };
        };
      };
    };
  };
  testScript = builtins.readFile ./scripts/sonarr_anime_test.py;
}
