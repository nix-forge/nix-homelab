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
      preStart = ''
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/fixture/application.db 'CREATE TABLE IF NOT EXISTS requests (title TEXT);'
      '';
    };
    systemd.services.restic-backups-fixture.preStart = lib.mkBefore ''
      install -m 600 /dev/null /run/restic-password
      printf '%s' disposable-fixture-password > /run/restic-password
    '';
    services.restic.backups.fixture = {
      repository = "/var/lib/restic-fixture";
      passwordFile = "/run/restic-password";
      initialize = true;
      timerConfig = null;
      checkOpts = [ "--read-data" ];
    };
  };
  testScript = ''
    machine.wait_for_unit("fixture.service")
    machine.wait_for_unit("ntfy-sh.service")
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("homelab-operational-health.service")
    machine.wait_until_succeeds("test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9086/health) = 503")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:2586/v1/health")
    machine.succeed("test $(curl -s -o /dev/null -w '%{http_code}' -d private http://127.0.0.1:2586/alerts) = 403")
    machine.succeed("NTFY_PASSWORD=disposable-password ntfy user add fixture")
    machine.succeed("ntfy access fixture homelab-health rw")
    machine.succeed("systemctl restart ntfy-sh")
    machine.wait_for_unit("ntfy-sh.service")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:2586/v1/health")
    machine.succeed("curl -fsS -u fixture:disposable-password -d 'native application fixture' http://127.0.0.1:2586/homelab-health")
    machine.succeed("sqlite3 /var/lib/fixture/application.db \"INSERT INTO requests VALUES ('permitted fixture');\"")
    machine.succeed("runuser -u postgres -- psql -d fixture -c \"SET ROLE fixture; CREATE TABLE requests (title text); INSERT INTO requests VALUES ('database fixture');\"")
    machine.succeed("systemctl start restic-backups-fixture.service")
    machine.succeed("systemctl is-active fixture.service")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:9086/health")
    machine.succeed("test ! -e /var/lib/homelab-recovery/snapshot")
    machine.succeed("restic-fixture restore latest --target /var/lib/restore-fixture")
    machine.succeed("test -f /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/services/fixture/0/export.sqlite")
    machine.succeed("test $(sqlite3 /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/services/fixture/0/application.db 'PRAGMA integrity_check;') = ok")
    machine.succeed("sqlite3 /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/services/fixture/0/application.db 'SELECT title FROM requests;' | grep -Fx 'permitted fixture'")
    machine.succeed("systemctl stop fixture; rm /var/lib/fixture/application.db; cp -a /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/services/fixture/0/application.db /var/lib/fixture/; systemctl start fixture")
    machine.succeed("sqlite3 /var/lib/fixture/application.db 'SELECT title FROM requests;' | grep -Fx 'permitted fixture'")
    machine.succeed("runuser -u postgres -- psql -d fixture -c 'TRUNCATE requests'")
    machine.fail("homelab-restore-postgresql fixture /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/databases/fixture.dump --replace")
    machine.succeed("ntfy user del fixture")
    machine.succeed("systemctl restart ntfy-sh")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:2586/v1/health")
    machine.succeed("test $(curl -s -o /dev/null -w '%{http_code}' -u fixture:disposable-password -d missing http://127.0.0.1:2586/homelab-health) = 401")
    machine.succeed("systemctl stop fixture ntfy-sh gatus")
    machine.succeed("ntfy_state=$(realpath /var/lib/ntfy-sh); rm -rf \"$ntfy_state\"; cp -a /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/services/ntfy/0 \"$ntfy_state\"")
    machine.succeed("homelab-restore-postgresql fixture /var/lib/restore-fixture/var/lib/homelab-recovery/snapshot/databases/fixture.dump --replace")
    machine.succeed("runuser -u postgres -- psql -d fixture -Atc 'SELECT title FROM requests' | grep -Fx 'database fixture'")
    machine.succeed("systemctl start fixture ntfy-sh gatus")
    machine.wait_until_succeeds("curl -fsS -u fixture:disposable-password 'http://127.0.0.1:2586/homelab-health/json?poll=1' | grep -F 'native application fixture'")
    # An export failure must fail the backup and resume originally active writers.
    machine.succeed("touch /run/fixture-export-failure")
    machine.fail("systemctl start restic-backups-fixture.service")
    machine.succeed("systemctl is-active fixture.service")
  '';
}
