{ homelabModule }: {
  name = "homelab-arr-postgresql";
  nodes.machine = { pkgs, ... }: {
    imports = [
      homelabModule
      ../../modules/operations
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 2048;
    homelab = {
      apps = {
        sonarr.enable = true;
        prowlarr.enable = true;
      };
      operations = {
        enable = true;
        arrPostgresql.services = [
          "sonarr"
          "prowlarr"
        ];
      };
    };
    services.postgresql.settings = {
      port = 15432;
      unix_socket_directories = "/run/fixture-postgresql";
    };
    systemd.tmpfiles.rules = [ "d /run/fixture-postgresql 0755 postgres postgres -" ];
    services.prowlarr.dataDir = "/srv/fixture-indexer-state";
    homelab.apps.prowlarr.customDefinitions."example.yml" =
      pkgs.writeText "example.yml" "id: fixture\n";
    # Public, disposable fixture keys, never deployment credentials.
    services.sonarr.settings.auth.apikey = "11111111111111111111111111111111";
    services.prowlarr.settings.auth.apikey = "22222222222222222222222222222222";
  };
  testScript = builtins.readFile ./scripts/arr_postgresql_test.py;
}
