{
  config,
  lib,
  pkgs,
  ...
}:
let
  selectedPostgresSocket = (import ../lib/postgresql-socket.nix) lib config.services.postgresql.settings;
  postgresSocket =
    if selectedPostgresSocket == null then "/run/postgresql" else selectedPostgresSocket;
  cfg = config.homelab.operations.arrPostgresql;
  apps = cfg.services;
  names = [
    "sonarr"
    "radarr"
    "lidarr"
    "prowlarr"
  ];
  account = name: if name == "prowlarr" then "prowlarr" else config.services.${name}.user;
  accounts = map account apps;
  dbs = lib.concatMap (name: [
    (account name)
    "${account name}-logs"
  ]) apps;
in
{
  options.homelab.operations.arrPostgresql = {
    services = lib.mkOption {
      type = lib.types.listOf (lib.types.enum names);
      default = [ ];
      description = "Explicitly selected Arr services using local PostgreSQL over peer-authenticated Unix sockets. Empty keeps native SQLite defaults.";
    };
    migratedServices = lib.mkOption {
      type = lib.types.listOf (lib.types.enum names);
      default = [ ];
      description = "Services whose existing SQLite state has been migrated and validated by the operator. This removes the startup guard; it never migrates or deletes data.";
    };
  };
  config = lib.mkIf (apps != [ ]) {
    assertions = [
      {
        assertion = selectedPostgresSocket != null;
        message = "Arr PostgreSQL requires a canonical filesystem Unix socket directory.";
      }
      {
        assertion = config.homelab.operations.enable;
        message = "Arr PostgreSQL requires the operations recovery inventory.";
      }
      {
        assertion = lib.all (name: config.services.${name}.enable) apps;
        message = "Enable each selected native Arr service before selecting its PostgreSQL backend.";
      }
      {
        assertion =
          builtins.length (lib.unique accounts) == builtins.length apps
          && builtins.length (lib.unique dbs) == builtins.length dbs
          && lib.all (
            name:
            builtins.match "[a-z_][a-z0-9_-]*" name != null
            && !(builtins.elem name [
              "root"
              "postgres"
            ])
          ) accounts;
        message = "Arr PostgreSQL requires distinct unprivileged service accounts.";
      }
    ];
    services = {
      postgresql = {
        enable = true;
        enableTCPIP = lib.mkDefault false;
        ensureDatabases = dbs;
        ensureUsers = map (name: {
          inherit name;
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
            superuser = false;
            createdb = false;
            createrole = false;
            replication = false;
          };
        }) accounts;
      };
    }
    // lib.genAttrs apps (name: {
      settings = {
        log.dbEnabled = true;
        postgres = {
          host = postgresSocket;
          port = config.services.postgresql.settings.port;
          user = account name;
          mainDb = account name;
          logDb = "${account name}-logs";
        };
      };
    });
    homelab.operations.postgresql = lib.listToAttrs (
      lib.concatMap (name: [
        (lib.nameValuePair "${name}-main" {
          database = account name;
          local = true;
          host = postgresSocket;
          port = config.services.postgresql.settings.port;
        })
        (lib.nameValuePair "${name}-logs" {
          database = "${account name}-logs";
          local = true;
          host = postgresSocket;
          port = config.services.postgresql.settings.port;
        })
      ]) apps
    );
    systemd.services = {
      homelab-arr-postgresql = {
        description = "Assign each Arr log database to its unprivileged owner";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
        };
        script = lib.concatMapStringsSep "\n" (
          name:
          ((import ../../lib/render-text.nix) ./scripts/arr-postgresql-set-log-owner.sh {
            config_services_postgresql_package = config.services.postgresql.package;
            account_name = account name;
            postgresSocket = lib.escapeShellArg postgresSocket;
            postgresPort = toString config.services.postgresql.settings.port;
          })
        ) apps;
      };
    }
    // lib.genAttrs apps (name: {
      after = [ "homelab-arr-postgresql.service" ];
      requires = [ "homelab-arr-postgresql.service" ];
      serviceConfig.ExecStartPre = lib.mkIf (!(builtins.elem name cfg.migratedServices)) (
        lib.mkBefore [
          (pkgs.writeShellScript "${name}-refuse-implicit-migration" (
            (import ../../lib/render-text.nix) ./scripts/refuse-implicit-sqlite-migration.sh {
              lib_escapeShellArg_config_services_name_dataDir =
                lib.escapeShellArg
                  config.services.${name}.dataDir;
              pkgs_findutils = pkgs.findutils;
              lib_escapeShellArg_config_services_name_dataDir2 =
                lib.escapeShellArg
                  config.services.${name}.dataDir;
              pkgs_gnugrep = pkgs.gnugrep;
            }
          ))
        ]
      );
    });
  };
}
