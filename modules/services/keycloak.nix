{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.keycloak;
  bootstrap = cfg.bootstrapRealm;
  postgres = config.services.postgresql;
  socket = (import ../lib/postgresql-socket.nix lib) postgres.settings;
  inherit (bootstrap) localDatabase;
  provisionAdmin = pkgs.writers.writePython3Bin "keycloak-provision-admin" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/keycloak_admin.py);
  address =
    if lib.hasInfix ":" cfg.settings.http-host then
      "[${cfg.settings.http-host}]"
    else
      cfg.settings.http-host;
  destination = "/run/keycloak-bootstrap/${bootstrap.name}-realm.json";
in
{
  options.services.keycloak.bootstrapRealm = {
    enable = lib.mkEnableOption "a private first-start realm import (existing realms are preserved)";
    localDatabase = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Provision the native local PostgreSQL database and follow its socket/port. Disable when using an externally managed database.";
    };
    name = lib.mkOption {
      type = lib.types.strMatching "[a-zA-Z0-9_-]+";
      default = "homelab";
      description = "Realm name in the encrypted import document.";
    };
    file = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime path to the decrypted realm JSON. Never a Nix store file.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.str;
      description = "Private runtime environment file with KC_BOOTSTRAP_ADMIN_USERNAME/PASSWORD and HOMELAB_ADMIN_USERNAME/PASSWORD. The permanent administrator replaces the temporary account.";
    };
  };
  config = lib.mkIf (cfg.enable && bootstrap.enable) {
    users.users.keycloak = {
      isSystemUser = true;
      group = "keycloak";
    };
    users.groups.keycloak = { };
    assertions =
      map
        (path: {
          assertion = lib.hasPrefix "/" path && !(lib.hasPrefix builtins.storeDir path);
          message = "Keycloak bootstrap credentials must use absolute runtime paths outside the Nix store.";
        })
        [
          bootstrap.file
          bootstrap.environmentFile
        ]
      ++ [
        {
          assertion =
            !localDatabase
            || (
              socket != null
              && cfg.database.host == socket
              && cfg.database.type == "postgresql"
              && cfg.database.port == postgres.settings.port
            );
          message = "Local Keycloak bootstrap requires PostgreSQL and the native server socket/port selected by services.postgresql.settings.";
        }
        {
          assertion =
            !localDatabase
            || (cfg.database.name == cfg.database.username && cfg.database.username == "keycloak");
          message = "The local Keycloak peer database and role must be named keycloak.";
        }
        {
          assertion = builtins.elem cfg.settings.http-host [
            "127.0.0.1"
            "::1"
          ];
          message = "Private Keycloak bootstrap requires a loopback HTTP listener behind HTTPS.";
        }
      ];
    services.keycloak = {
      database = {
        host = lib.mkIf localDatabase (
          lib.mkDefault (if socket == null then "/run/postgresql" else socket)
        );
        port = lib.mkIf localDatabase (lib.mkDefault postgres.settings.port);
        createLocally = lib.mkDefault false;
        useSSL = lib.mkIf localDatabase (lib.mkDefault false);
      };
      plugins = lib.mkAfter (
        with cfg.package.plugins;
        [
          junixsocket-common
          junixsocket-native-common
        ]
      );
      realmFiles = [ destination ];
      settings = {
        cache = lib.mkDefault "local";
        log-level = lib.mkDefault "info,org.keycloak.services:error";
        http-host = lib.mkDefault "127.0.0.1";
        http-port = lib.mkDefault 1411;
        http-enabled = lib.mkDefault true;
        proxy-headers = lib.mkDefault "xforwarded";
        proxy-trusted-addresses = lib.mkDefault "127.0.0.1/32,::1/128";
      };
    };
    services.postgresql = lib.mkIf localDatabase {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.username;
          ensureDBOwnership = true;
        }
      ];
    };
    systemd.services.keycloak = {
      after = lib.optionals localDatabase [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = lib.optionals localDatabase [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      environment.HOMELAB_KEYCLOAK_URL = "http://${address}:${toString cfg.settings.http-port}${
        let
          path = cfg.settings.http-relative-path or "/";
        in
        if path == "/" || path == "" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" path)}"
      }";
      postStart = lib.getExe provisionAdmin;
      environment.JAVA_OPTS_KC_HEAP = lib.mkDefault "-Xms64m -Xmx512m";
      preStart = (import ../../lib/render-text.nix) ./scripts/keycloak-stage-realm.sh {
        lib_escapeShellArg_destination = lib.escapeShellArg destination;
        bootstrap_name = bootstrap.name;
      };
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        EnvironmentFile = bootstrap.environmentFile;
        LoadCredential = [ "realm:${bootstrap.file}" ];
        RuntimeDirectory = lib.mkAfter [ "keycloak-bootstrap" ];
        StateDirectory = "keycloak-bootstrap";
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "180s";
        MemoryHigh = lib.mkDefault "768M";
        MemoryMax = lib.mkDefault "1G";
      };
    };
    homelab.operations = lib.mkIf localDatabase {
      postgresql.keycloak.database = cfg.database.name;
      state.keycloak = {
        paths = [ "/var/lib/keycloak-bootstrap" ];
        units = [ "keycloak.service" ];
      };
    };
  };
}
