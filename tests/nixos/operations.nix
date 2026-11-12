{ homelabModule }: {
  name = "homelab-operations";
  nodes.machine = { pkgs, lib, ... }: {
    imports = [
      homelabModule
      ../../modules/operations
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1024;
    environment.systemPackages = [ pkgs.sqlite ];
    homelab.operations = {
      enable = true;
      state.fixture = {
        paths = [ "/var/lib/fixture" ];
        units = [ "fixture.service" ];
        prepareCommand = "test ! -e /run/fixture-export-failure && ${pkgs.sqlite}/bin/sqlite3 /var/lib/fixture/application.db '.backup /var/lib/fixture/export.sqlite'";
      };
      backup.job = "fixture";
      postgresql.fixture = {
        database = "fixture";
      };
      notifications.enable = true;
      monitoring.enable = true;
      pressure = {
        path = "/var/lib";
        requiredMounts = [ ];
        pauseBytes = 1;
      };
    };
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "fixture" ];
      ensureUsers = [
        {
          name = "fixture";
          ensureDBOwnership = true;
        }
      ];
    };
    systemd.services.fixture = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        StateDirectory = "fixture";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      preStart = (import ../../lib/render-text.nix) ./scripts/initialize-application-database.sh {
        pkgs_sqlite = pkgs.sqlite;
      };
    };
    systemd.services.restic-backups-fixture.preStart = lib.mkBefore (
      builtins.readFile ./scripts/prepare-backup-password.sh
    );
    services.restic.backups.fixture = {
      repository = "/var/lib/restic-fixture";
      passwordFile = "/run/restic-password";
      initialize = true;
      timerConfig = null;
      checkOpts = [ "--read-data" ];
    };
  };
  testScript = builtins.readFile ./scripts/operations_test.py;
}
