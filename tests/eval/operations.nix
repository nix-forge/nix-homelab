{ evaluate, lib }:
let
  basedArr =
    (evaluate {
      imports = [ ../../modules/operations ];
      homelab = {
        operations = {
          enable = true;
          monitoring.enable = true;
        };
        apps = lib.genAttrs [ "sonarr" "radarr" "lidarr" "prowlarr" ] (_: {
          enable = true;
        });
      };
      services = {
        sonarr.settings.server = {
          port = 18989;
          urlbase = "/tv/";
        };
        radarr.settings.server.urlbase = "movies";
        lidarr.settings.server.urlbase = "/";
        prowlarr.settings.server = {
          port = 19696;
          urlbase = "/indexers/";
        };
      };
    }).config;
  configured =
    (evaluate {
      imports = [ ../../modules/operations ];
      homelab = {
        apps.navidrome.enable = true;
        operations = {
          enable = true;
          monitoring.enable = true;
          notifications.enable = true;
          dashboard.enable = true;
          endpoints.navidrome.url = "http://127.0.0.1:4533/ping";
          backup.job = "existing";
          pressure = {
            enable = true;
            clients.qbittorrent = {
              url = "http://127.0.0.1:8081";
              credentialsFile = "/run/nix-seal/qbit-api";
            };
          };
        };
      };
      services.restic.backups.existing = {
        repository = "/srv/backup/restic";
        passwordFile = "/run/nix-seal/restic";
        paths = [ "/srv/host-state" ];
        backupPrepareCommand = "echo host-prepare";
        backupCleanupCommand = "echo host-cleanup";
      };
    }).config;
  access =
    (evaluate {
      imports = [ ../../modules/operations ];
      homelab.operations = {
        enable = true;
        dashboard.enable = true;
        access = {
          enable = true;
          certificateFile = "/run/nix-seal/certificate";
          keyFile = "/run/nix-seal/key";
          usersFile = "/run/nix-seal/users";
          jwtSecretFile = "/run/nix-seal/jwt";
          sessionSecretFile = "/run/nix-seal/session";
          storageEncryptionKeyFile = "/run/nix-seal/storage";
          backends.dashboard.port = 8082;
        };
      };
    }).config;
  postgres =
    (evaluate {
      imports = [ ../../modules/operations ];
      homelab = {
        apps.sonarr.enable = true;
        apps.prowlarr.enable = true;
        operations = {
          enable = true;
          arrPostgresql.services = [
            "sonarr"
            "prowlarr"
          ];
        };
      };
    }).config;
  customPostgresClient =
    (evaluate (
      { pkgs, ... }: {
        imports = [ ../../modules/operations ];
        homelab.operations = {
          enable = true;
          backup.job = "custom";
          state.fixture = {
            paths = [ "/var/lib/fixture" ];
            units = [ "fixture.service" ];
          };
        };
        services.postgresql.package = pkgs.postgresql_16;
        services.restic.backups.custom = {
          repository = "/srv/backup/restic";
          passwordFile = "/run/nix-seal/restic";
        };
      }
    )).config;
  standaloneMonitoring =
    (evaluate {
      imports = [ ../../modules/operations ];
      homelab.operations = {
        enable = true;
        monitoring.enable = true;
      };
    }).config;
  disabled = (evaluate { imports = [ ../../modules/operations ]; }).config;
in
{
  arrDatabaseInventory =
    lib.all (name: builtins.hasAttr name postgres.homelab.operations.postgresql)
      [
        "sonarr-main"
        "sonarr-logs"
        "prowlarr-main"
        "prowlarr-logs"
      ];
  arrUsesLocalSockets =
    postgres.services.sonarr.settings.postgres.host == "/run/postgresql"
    && postgres.services.prowlarr.settings.postgres.host == "/run/postgresql";
  arrAssertionsPass = lib.all (a: a.assertion) postgres.assertions;
  healthAvoidsInfluxDB = configured.homelab.operations.monitoring.health.port != 8086;
  standaloneMonitoringGroup = builtins.hasAttr standaloneMonitoring.homelab.storage.group standaloneMonitoring.users.groups;
  accessDefaultsToTwoFactors =
    (builtins.head access.services.authelia.instances.homelab.settings.access_control.rules).policy
    == "two_factor"
    && access.services.authelia.instances.homelab.settings.access_control.default_policy == "deny";
  accessHasNoAdminAPI =
    lib.hasInfix "admin off" access.services.caddy.globalConfig && !access.services.caddy.enableReload;
  accessProtectsBackends = lib.hasInfix "tcp dport" access.networking.nftables.tables.homelab-private-backends.content;
  accessStateIncluded =
    access.homelab.operations.state.authelia.paths == [ "/var/lib/authelia-homelab" ];
  accessAssertionsPass = lib.all (a: a.assertion) access.assertions;
  arrNativeBaseAndPort =
    basedArr.homelab.operations.endpoints.sonarr.url == "http://127.0.0.1:18989/tv"
    && basedArr.homelab.operations.endpoints.radarr.url == "http://127.0.0.1:7878/movies"
    && basedArr.homelab.operations.endpoints.lidarr.url == "http://127.0.0.1:8686"
    && basedArr.homelab.operations.endpoints.prowlarr.url == "http://127.0.0.1:19696/indexers"
    && builtins.any (
      entry: entry.url == "http://127.0.0.1:18989/tv"
    ) basedArr.services.gatus.settings.endpoints;
  disabledIsEmpty = disabled.homelab.operations.state == { } && !disabled.services.gatus.enable;
  nativeStateDerived =
    configured.homelab.operations.state.navidrome.paths == [ "/var/lib/navidrome" ];
  hostBackupPreserved =
    builtins.elem "/srv/host-state" configured.services.restic.backups.existing.paths
    && configured.services.restic.backups.existing.backupPrepareCommand == "echo host-prepare"
    && configured.services.restic.backups.existing.backupCleanupCommand == "echo host-cleanup";
  privateNotifications =
    configured.services.ntfy-sh.settings.auth-default-access == "deny-all"
    && configured.services.ntfy-sh.settings.listen-http == "127.0.0.1:2586";
  privateViews =
    configured.services.gatus.settings.web.address == "127.0.0.1"
    && configured.systemd.services.homepage-dashboard.environment.HOSTNAME == "127.0.0.1"
    && configured.networking.firewall.allowedTCPPorts == [ ];
  runtimeCredentials =
    configured.systemd.services.homelab-storage-pressure.serviceConfig.LoadCredential
    == [ "qbittorrent:/run/nix-seal/qbit-api" ];
  explicitPostgresClientPreserved =
    !customPostgresClient.services.postgresql.enable
    && builtins.elem customPostgresClient.services.postgresql.package customPostgresClient.systemd.services.restic-backups-custom.path;
  backupWithoutNativePostgres =
    !configured.services.postgresql.enable
    && builtins.isString configured.systemd.services.restic-backups-existing.environment.PATH;
  assertionsPass = lib.all (a: a.assertion) configured.assertions;
}
