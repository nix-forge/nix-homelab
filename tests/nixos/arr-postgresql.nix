{ homelabModule }: {
  name = "homelab-arr-postgresql";
  nodes.machine = {
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
    # Public, disposable fixture keys, never deployment credentials.
    services.sonarr.settings.auth.apikey = "11111111111111111111111111111111";
    services.prowlarr.settings.auth.apikey = "22222222222222222222222222222222";
  };
  testScript = ''
    import json
    machine.wait_for_unit("homelab-arr-postgresql.service")
    machine.wait_for_unit("sonarr.service")
    machine.wait_for_unit("prowlarr.service")
    for name, port, version, key in [("sonarr", 8989, "v3", "1" * 32), ("prowlarr", 9696, "v1", "2" * 32)]:
        command = f"curl -fsS -H 'X-Api-Key: {key}' http://127.0.0.1:{port}/api/{version}/system/status"
        machine.wait_until_succeeds(command)
        assert json.loads(machine.succeed(command))["databaseType"].lower() == "postgresql"
        # Each application must own both databases and have no cluster privileges.
        owned = machine.succeed(f"runuser -u postgres -- psql -Atc \"SELECT datname FROM pg_database WHERE datname IN ('{name}', '{name}-logs') AND pg_get_userbyid(datdba) = '{name}'\"")
        assert set(owned.split()) == {name, name + "-logs"}
        machine.succeed(f"test $(runuser -u postgres -- psql -Atc \"SELECT rolsuper OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname = '{name}'\") = f")
    for name, path in [("sonarr", "/var/lib/sonarr/.config/NzbDrone"), ("prowlarr", "/var/lib/prowlarr")]:
        machine.succeed(f"systemctl stop {name}; touch {path}/previous.db")
        machine.fail(f"systemctl start {name}")
        machine.succeed(f"test -f {path}/previous.db")
        machine.succeed(f"rm {path}/previous.db; systemctl reset-failed {name}; systemctl start {name}")
        machine.wait_for_unit(name + ".service")
  '';
}
