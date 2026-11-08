{ evaluate, lib }:
let
  base = {
    services.keycloak = {
      enable = true;
      settings.hostname = "https://identity.example.org";
      bootstrapRealm = {
        enable = true;
        file = "/run/keys/realm";
        environmentFile = "/run/keys/admin";
      };
    };
  };
  c = (evaluate base).config;
  rejected =
    extra:
    lib.any (item: !item.assertion)
      (evaluate {
        imports = [
          base
          extra
        ];
      }).config.assertions;
in
{
  privateCredentials =
    builtins.elem "realm:/run/keys/realm" c.systemd.services.keycloak.serviceConfig.LoadCredential
    && c.systemd.services.keycloak.serviceConfig.EnvironmentFile == "/run/keys/admin"
    && c.systemd.services.keycloak.serviceConfig.RuntimeDirectoryMode == "0700"
    && c.services.keycloak.initialAdminPassword == null;
  peerDatabase =
    c.services.keycloak.database.passwordFile == null
    && c.services.keycloak.database.host == "/run/postgresql"
    && !c.systemd.services.keycloak.serviceConfig.DynamicUser
    && c.services.postgresql.ensureDatabases == [ "keycloak" ];
  importPreservesExisting =
    c.services.keycloak.realmFiles == [ "/run/keycloak-bootstrap/homelab-realm.json" ];
  rejectStoreSecrets = rejected {
    services.keycloak.bootstrapRealm.file = lib.mkForce "/nix/store/disposable-secret";
  };
  rejectMismatchedOwner = rejected { services.keycloak.database.username = "different"; };
  ipv6Loopback =
    let
      c =
        (evaluate {
          imports = [ base ];
          services.keycloak.settings.http-host = "::1";
        }).config;
    in
    c.systemd.services.keycloak.environment.HOMELAB_KEYCLOAK_URL == "http://[::1]:1411"
    && c.services.keycloak.settings.proxy-trusted-addresses == "127.0.0.1/32,::1/128";
  recoveryStopsWriter =
    c.homelab.operations.state.keycloak.units == [ "keycloak.service" ]
    && c.homelab.operations.state.keycloak.paths == [ "/var/lib/keycloak-bootstrap" ];
  noPublicPort =
    c.networking.firewall.allowedTCPPorts == [ ]
    && c.services.keycloak.settings.http-host == "127.0.0.1";
}
