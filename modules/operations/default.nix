{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.operations;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mkDefault
    types
    ;
  postgresPackage =
    if options.services.postgresql.package.isDefined then
      config.services.postgresql.package
    else
      pkgs.postgresql;
  caBundle = config.security.pki.caBundle;
  runtimeFile = types.strMatching "/[A-Za-z0-9_./-]+";
  enabled =
    name:
    (config.homelab.apps.${name}.enable or false)
    || (lib.attrByPath [ "homelab" "optional" "apps" name "enable" ] false config);
  entry = name: paths: {
    inherit paths;
    units = [ "${name}.service" ] ++ integrationUnits;
  };
  relativeState = path: if lib.hasPrefix "/" path then path else "/var/lib/${path}";
  integrationNames =
    lib.optionals (lib.attrByPath [ "homelab" "integration" "enable" ] false config)
      (builtins.attrNames (lib.attrByPath [ "homelab" "integration" "services" ] { } config));
  integrationUnits = lib.concatMap (name: [
    "homelab-integrate-${name}.service"
    "homelab-integrate-${name}.timer"
  ]) integrationNames;
  integrationState = lib.listToAttrs (
    map (
      name:
      lib.nameValuePair "integration-${name}" {
        paths = [ "/var/lib/homelab-integrate-${name}" ];
        units = [
          "homelab-integrate-${name}.service"
          "homelab-integrate-${name}.timer"
        ];
      }
    ) integrationNames
  );
  native = {
    syncthing = {
      paths = lib.unique [
        config.services.syncthing.configDir
        config.services.syncthing.databaseDir
      ];
      units = [
        "syncthing.service"
      ]
      ++ lib.optional (builtins.hasAttr "syncthing-init" config.systemd.services) "syncthing-init.service"
      ++ integrationUnits;
    };
    adguardhome = entry "adguardhome" [ "/var/lib/AdGuardHome" ];
    scrutiny = {
      paths = [
        "/var/lib/scrutiny"
      ]
      ++ lib.optional config.services.scrutiny.influxdb.enable "/var/lib/influxdb2";
      units = [
        "scrutiny.service"
      ]
      ++ lib.optional config.services.scrutiny.influxdb.enable "influxdb2.service"
      ++ lib.optionals config.services.scrutiny.collector.enable [
        "scrutiny-collector.service"
        "scrutiny-collector.timer"
      ]
      ++ integrationUnits;
    };
    autobrr = entry "autobrr" [ "/var/lib/autobrr" ];
    cross-seed = entry "cross-seed" [ config.services.cross-seed.configDir ];
    komga = entry "komga" [ config.services.komga.stateDir ];
    kavita = entry "kavita" [ config.services.kavita.dataDir ];
    shelfmark = entry "shelfmark" [ config.services.shelfmark.environment.CONFIG_DIR ];
    pinchflat = entry "pinchflat" [ "/var/lib/pinchflat" ];
    maintainerr = {
      paths = [ "/var/lib/homelab-maintainerr/data" ];
      units = [ "homelab-maintainerr.service" ] ++ integrationUnits;
    };
    immich = {
      paths = lib.unique [
        "/var/lib/immich"
        config.services.immich.mediaLocation
      ];
      units = [
        "immich-server.service"
      ]
      ++ lib.optional config.services.immich.machine-learning.enable "immich-machine-learning.service"
      ++ integrationUnits;
    };
    paperless = {
      paths = lib.unique [
        config.services.paperless.dataDir
        config.services.paperless.mediaDir
        config.services.paperless.consumptionDir
      ];
      units = [
        "paperless-web.service"
        "paperless-consumer.service"
        "paperless-task-queue.service"
        "paperless-scheduler.service"
      ]
      ++ integrationUnits;
    };
    sonarr = entry "sonarr" [ config.services.sonarr.dataDir ];
    radarr = entry "radarr" [ config.services.radarr.dataDir ];
    lidarr = entry "lidarr" [ config.services.lidarr.dataDir ];
    bazarr = entry "bazarr" [ config.services.bazarr.dataDir ];
    prowlarr = entry "prowlarr" [ config.services.prowlarr.dataDir ];
    seerr = entry "seerr" [ config.services.seerr.configDir ];
    qbittorrent = entry "qbittorrent" [ config.services.qbittorrent.profileDir ];
    sabnzbd = entry "sabnzbd" [ (relativeState config.services.sabnzbd.stateDir) ];
    nzbget = entry "nzbget" [ "/var/lib/nzbget" ];
    jellyfin = entry "jellyfin" (
      lib.unique [
        config.services.jellyfin.dataDir
        config.services.jellyfin.configDir
      ]
    );
    plex = entry "plex" [ config.services.plex.dataDir ];
    navidrome = entry "navidrome" [
      (config.services.navidrome.settings.DataFolder or "/var/lib/navidrome")
    ];
    audiobookshelf = entry "audiobookshelf" [ (relativeState config.services.audiobookshelf.dataDir) ];
  };
  url = host: port: "http://${host}:${toString port}";
  endpoint = address: { url = address; };
  arrEndpoint =
    name: host:
    let
      server = config.services.${name}.settings.server;
      segments = lib.filter (segment: segment != "") (lib.splitString "/" (server.urlbase or ""));
      base = lib.optionalString (segments != [ ]) "/${lib.concatStringsSep "/" segments}";
    in
    endpoint "${url host server.port}${base}";
  webAvailability = address: {
    url = address;
    conditions = [ "[STATUS] == any(200, 302, 303, 307, 308, 401, 403)" ];
    description = "Web listener availability; authenticated application checks are host-owned";
  };
  nativeEndpoints = {
    autobrr = {
      url = url "127.0.0.1" config.services.autobrr.settings.port;
      healthUrl = "${url "127.0.0.1" config.services.autobrr.settings.port}/api/healthz/readiness";
    };
    cross-seed = {
      url = url "127.0.0.1" config.services.cross-seed.settings.port;
      monitor = false;
      description = "cross-seed API; configure an authenticated health probe on the host";
    };
    flaresolverr = endpoint (url "127.0.0.1" config.services.flaresolverr.port);
    komga = webAvailability (url "127.0.0.1" config.services.komga.settings.server.port);
    kavita = webAvailability (url "127.0.0.1" config.services.kavita.settings.Port);
    shelfmark = webAvailability (url "127.0.0.1" config.services.shelfmark.environment.FLASK_PORT);
    pinchflat = webAvailability (url "127.0.0.1" config.services.pinchflat.port);
    immich = {
      url = url "127.0.0.1" config.services.immich.port;
      healthUrl = "${url "127.0.0.1" config.services.immich.port}/api/server/ping";
    };
    paperless = webAvailability (url "127.0.0.1" config.services.paperless.port);
    syncthing = webAvailability "http://${config.services.syncthing.guiAddress}";
    adguardhome = webAvailability (url "127.0.0.1" config.services.adguardhome.port);
    scrutiny = endpoint "${url "127.0.0.1" config.services.scrutiny.settings.web.listen.port}${config.services.scrutiny.settings.web.listen.basepath}";
    maintainerr = {
      url = url "127.0.0.1" (lib.attrByPath [ "homelab" "optional" "maintainerr" "port" ] 6246 config);
      conditions = [ "[STATUS] == 401" ];
      description = "Maintainerr authenticated gateway; authenticated backend checks are host-owned";
    };
    sonarr = arrEndpoint "sonarr" "127.0.0.1";
    radarr = arrEndpoint "radarr" "127.0.0.1";
    lidarr = arrEndpoint "lidarr" "127.0.0.1";
    bazarr = endpoint (url "127.0.0.1" config.services.bazarr.listenPort);
    prowlarr = arrEndpoint "prowlarr" config.homelab.apps.prowlarr.bindAddress;
    qbittorrent = endpoint (
      url config.homelab.apps.qbittorrent.bindAddress config.homelab.apps.qbittorrent.webuiPort
    );
    sabnzbd = endpoint (
      url config.services.sabnzbd.settings.misc.host config.homelab.apps.sabnzbd.port
    );
    nzbget = endpoint (
      url config.homelab.apps.nzbget.bindAddress config.homelab.apps.nzbget.controlPort
    );
    jellyfin = {
      url = "http://127.0.0.1:8096";
      healthUrl = "http://127.0.0.1:8096/health";
      conditions = [
        "[STATUS] == 200"
        "[BODY] == Healthy"
      ];
    };
    seerr = {
      url = url "127.0.0.1" config.services.seerr.port;
      healthUrl = "${url "127.0.0.1" config.services.seerr.port}/api/v1/status";
    };
    plex = endpoint "http://127.0.0.1:32400/web";
    navidrome = endpoint (url "127.0.0.1" config.services.navidrome.settings.Port);
    audiobookshelf = endpoint (url "127.0.0.1" config.services.audiobookshelf.port);
  };
  renderedState = lib.mapAttrs (
    name: state:
    state
    // {
      prepareCommand =
        if state.prepareCommand == null then
          null
        else
          pkgs.writeShellScript "homelab-prepare-${name}" state.prepareCommand;
    }
  ) cfg.state;
  inventory = pkgs.writeText "homelab-state-inventory.json" (builtins.toJSON renderedState);
  databaseConfig = pkgs.writeText "homelab-database-exports.json" (
    builtins.toJSON (lib.mapAttrs (_: database: removeAttrs database [ "passwordFile" ]) cfg.postgresql)
  );
  restoreConfig = pkgs.writeText "homelab-database-restore.json" (builtins.toJSON cfg.postgresql);
  recovery = "${pkgs.python3}/bin/python3 ${../../scripts/operations/recovery.py}";
  staging = "${cfg.backup.stagingDir}/snapshot";
  pressureConfig = pkgs.writeText "homelab-pressure.json" (
    builtins.toJSON {
      inherit (cfg.pressure)
        path
        requiredMounts
        pauseBytes
        resumeBytes
        ;
      clients = lib.mapAttrs (_: client: { inherit (client) url; }) cfg.pressure.clients;
    }
  );
  endpoints = lib.filterAttrs (_: endpoint: endpoint.enable) cfg.endpoints;
  safeRuntime = file: file == null || (lib.hasPrefix "/" file && !(lib.hasPrefix "/nix/store" file));
  pathSafe =
    path: path != "/" && !(lib.hasPrefix "/nix/store" path) && !(lib.hasInfix "/../" "${path}/");
in
{
  imports = [
    ./health.nix
    ./access.nix
    ./arr-postgresql.nix
  ];
  options.homelab.operations = {
    enable = mkEnableOption "an inventory of application state and optional operational integrations";
    state = mkOption {
      default = { };
      description = "State directories and every writer to stop for a consistent copy. Override entries when external databases or queue paths are used. Media and secret catalogs are separate host backup decisions.";
      type = types.attrsOf (
        types.submodule {
          options = {
            paths = mkOption {
              type = types.listOf runtimeFile;
              description = "Persistent directories; DynamicUser symlinks are resolved during staging.";
            };
            prepareCommand = mkOption {
              type = types.nullOr types.lines;
              default = null;
              description = "Host export command run after all writers stop and before state copies. A failure aborts staging and restarts writers. Read secrets from runtime files.";
            };
            units = mkOption {
              type = types.listOf (types.strMatching "[A-Za-z0-9_@.:-]+\\.(service|timer)");
              description = "All systemd writers and timer triggers for these directories.";
            };
          };
        }
      );
    };
    paperlessDatabase = mkOption {
      type = types.enum [
        "sqlite"
        "postgresql"
      ];
      default =
        if (config.services.paperless.settings.PAPERLESS_DBHOST or "") != "" then
          "postgresql"
        else
          "sqlite";
      description = "Declare PostgreSQL explicitly when Paperless selects its database through a private environment file; native public DBHOST is detected.";
    };
    postgresql = mkOption {
      default = { };
      description = "Explicit logical database exports included in the stopped-writer recovery copy. Local exports use PostgreSQL peer authentication; remote exports require a runtime pgpass file.";
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }: {
            options = {
              database = mkOption {
                type = types.strMatching "[A-Za-z0-9_-]+";
                default = name;
                description = "Existing database to export.";
              };
              local = mkOption {
                type = types.bool;
                default = true;
                description = "Use the local postgres operating-system account and peer authentication.";
              };
              host = mkOption {
                type = types.strMatching "[A-Za-z0-9_./:-]+";
                default = "/run/postgresql";
                description = "Socket directory or trusted PostgreSQL hostname.";
              };
              port = mkOption {
                type = types.port;
                default = 5432;
                description = "PostgreSQL port.";
              };
              user = mkOption {
                type = types.strMatching "[A-Za-z0-9_-]+";
                default = if config.local then "postgres" else config.database;
                description = "Export/restore database login.";
              };
              caFile = mkOption {
                type = runtimeFile;
                default = caBundle;
                description = "Trusted CA bundle for remote PostgreSQL verify-full TLS. Override with the host's private CA when needed.";
              };
              passwordFile = mkOption {
                type = types.nullOr runtimeFile;
                default = null;
                description = "nix-seal pgpass file for a remote database, loaded through systemd credentials during backup.";
              };
            };
          }
        )
      );
    };
    endpoints = mkOption {
      default = { };
      description = "Host-visible health and dashboard endpoints. Keep credentials in Gatus environment files, never URLs.";
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }: {
            options = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Include this endpoint in generated operations views.";
              };
              url = mkOption {
                type = types.strMatching "https?://[A-Za-z0-9:._/-]+";
                description = "Credential-free URL reachable from the host.";
              };
              monitor = mkOption {
                type = types.bool;
                default = true;
                description = "Create a Gatus probe as well as a dashboard link. Disable when authentication or API semantics require a host-owned check.";
              };
              healthUrl = mkOption {
                type = types.strMatching "https?://[A-Za-z0-9:._/-]+";
                default = config.url;
                defaultText = lib.literalExpression "config.url";
                description = "Health probe URL, separate from the browser dashboard link.";
              };
              description = mkOption {
                type = types.str;
                default = name;
                description = "Dashboard description.";
              };
              conditions = mkOption {
                type = types.listOf types.str;
                default = [ "[STATUS] == 200" ];
                description = "Gatus health conditions; select an application health API where available.";
              };
            };
          }
        )
      );
    };
    backup = {
      job = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9_-]+");
        default = null;
        description = "Existing root-owned native Restic job to extend; host supplies repository, password, schedule and retention.";
      };
      stagingDir = mkOption {
        type = runtimeFile;
        default = "/var/lib/homelab-recovery";
        description = "Private staging on a filesystem with room for application state. Writers stop only during this local copy.";
      };
    };
    pressure = {
      enable = mkEnableOption "download pausing with filesystem headroom and hysteresis";
      path = mkOption {
        type = runtimeFile;
        default = config.homelab.storage.downloadsDir;
        description = "Existing directory on the filesystem whose available space is measured.";
      };
      requiredMounts = mkOption {
        type = types.listOf runtimeFile;
        default = config.homelab.storage.requiredMounts;
        description = "Mountpoints that must exist; absence forces the pause policy.";
      };
      pauseBytes = mkOption {
        type = types.ints.positive;
        default = 40 * 1024 * 1024 * 1024;
        description = "Pause below these available bytes; tune for unpacking and backup headroom.";
      };
      resumeBytes = mkOption {
        type = types.ints.positive;
        default = 60 * 1024 * 1024 * 1024;
        description = "Resume owned pauses only above this free-space threshold.";
      };
      clients = mkOption {
        default = { };
        description = "qBittorrent v5 and/or SABnzbd APIs. qBittorrent credentials are a JSON username/password object; SABnzbd uses a raw API key file.";
        type = types.attrsOf (
          types.submodule {
            options = {
              url = mkOption {
                type = types.strMatching "https?://[A-Za-z0-9:._/-]+";
                description = "Trusted private API origin, including an optional base path.";
              };
              credentialsFile = mkOption {
                type = runtimeFile;
                description = "User-provided nix-seal runtime file, loaded with systemd credentials.";
              };
            };
          }
        );
      };
    };
    monitoring = {
      enable = mkEnableOption "Gatus checks generated from the endpoint inventory";
      alerts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Native Gatus alert types for generated endpoints; configure their providers under services.gatus.settings.alerting.";
      };
    };
    notifications = {
      enable = mkEnableOption "private deny-by-default ntfy notifications";
      environmentFile = mkOption {
        type = types.nullOr runtimeFile;
        default = null;
        description = "nix-seal EnvironmentFile containing NTFY_AUTH_USERS and NTFY_AUTH_ACCESS declarations and optional tokens.";
      };
    };
    dashboard.enable = mkEnableOption "a private Homepage view of inventory endpoints";
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        homelab.operations.state = lib.mapAttrs (_: mkDefault) (
          (lib.filterAttrs (name: _: enabled name) native)
          // integrationState
          // lib.optionalAttrs config.services.recyclarr.enable {
            recyclarr = (entry "recyclarr" [ "/var/lib/recyclarr" ]) // {
              units = [
                "recyclarr.service"
                "recyclarr.timer"
              ]
              ++ integrationUnits;
            };
          }
          // lib.optionalAttrs cfg.notifications.enable { ntfy = entry "ntfy-sh" [ "/var/lib/ntfy-sh" ]; }
          // lib.optionalAttrs cfg.monitoring.enable { gatus = entry "gatus" [ "/var/lib/gatus" ]; }
        );
        homelab.operations.endpoints = lib.mapAttrs (_: mkDefault) (
          lib.filterAttrs (name: _: enabled name) nativeEndpoints
        );
        environment.etc."homelab/state-inventory.json".source = inventory;
        environment.etc."homelab/database-exports.json".source = databaseConfig;
        assertions = [
          {
            assertion = lib.all pathSafe (
              lib.concatMap (entry: entry.paths) (builtins.attrValues cfg.state) ++ [ cfg.backup.stagingDir ]
            );
            message = "Operations state paths must be dedicated paths outside /nix/store without parent traversal.";
          }
          {
            assertion = lib.all (entry: entry.paths != [ ] && entry.units != [ ]) (
              builtins.attrValues cfg.state
            );
            message = "Each recovery state entry needs paths and writer units.";
          }
          {
            assertion = lib.all (name: builtins.match "[A-Za-z0-9_-]+" name != null) (
              builtins.attrNames cfg.state
            );
            message = "Recovery state entry names must be safe directory components.";
          }
        ];
      }
      (mkIf (cfg.backup.job != null) {
        assertions = [
          {
            assertion = cfg.state != { };
            message = "Recovery integration requires a nonempty state inventory.";
          }
          {
            assertion = config.services.restic.backups.${cfg.backup.job}.user == "root";
            message = "Recovery staging requires a root-owned Restic job.";
          }
          {
            assertion = lib.all (
              path:
              !(lib.hasPrefix "${path}/" "${cfg.backup.stagingDir}/")
              && !(lib.hasPrefix "${cfg.backup.stagingDir}/" "${path}/")
            ) (lib.concatMap (entry: entry.paths) (builtins.attrValues cfg.state));
            message = "Recovery staging and source directories must not overlap.";
          }
        ]
        ++ (
          (lib.mapAttrsToList (name: database: {
            assertion =
              builtins.match "[A-Za-z0-9_-]+" name != null
              && (
                if database.local then
                  config.services.postgresql.enable && database.user == "postgres" && lib.hasPrefix "/" database.host
                else
                  database.passwordFile != null && safeRuntime database.passwordFile
              );
            message = "PostgreSQL exports need a safe name and either local PostgreSQL peer authentication or a runtime pgpass file.";
          }) cfg.postgresql)
          ++ [
            {
              assertion =
                !(enabled "immich")
                || lib.any (database: database.database == config.services.immich.database.name) (
                  builtins.attrValues cfg.postgresql
                );
              message = "Immich recovery requires an explicit matching logical PostgreSQL export.";
            }
            {
              assertion =
                !(enabled "paperless")
                || cfg.paperlessDatabase == "sqlite"
                || lib.any (
                  database: database.database == (config.services.paperless.settings.PAPERLESS_DBNAME or "paperless")
                ) (builtins.attrValues cfg.postgresql);
              message = "Paperless using an external database requires an explicit matching logical PostgreSQL export.";
            }
          ]
        );
        environment.systemPackages = lib.optional (cfg.postgresql != { }) (
          pkgs.writeShellApplication {
            name = "homelab-restore-postgresql";
            runtimeInputs = [
              pkgs.python3
              pkgs.systemd
              pkgs.util-linux
              postgresPackage
            ];
            text = ''
              exec python3 ${../../scripts/operations/restore_postgres.py} ${inventory} ${restoreConfig} "$@"
            '';
          }
        );
        services.restic.backups.${cfg.backup.job} = {
          paths = [ staging ];
        };
        systemd.services."restic-backups-${cfg.backup.job}" = {
          path = [
            pkgs.coreutils
            pkgs.systemd
            pkgs.util-linux
            postgresPackage
          ];
          preStart = lib.mkAfter ''
            ${recovery} cleanup ${inventory} ${lib.escapeShellArg staging}
            ${recovery} stage ${inventory} ${lib.escapeShellArg staging} ${databaseConfig}
          '';
          unitConfig.RequiresMountsFor = [
            cfg.backup.stagingDir
          ]
          ++ lib.concatMap (entry: entry.paths) (builtins.attrValues cfg.state);
          serviceConfig = {
            UMask = "0077";
            Nice = mkDefault 10;
            CPUWeight = mkDefault 25;
            IOWeight = mkDefault 25;
            TimeoutStartSec = "infinity";
            LoadCredential = lib.mapAttrsToList (name: database: "postgres-${name}:${database.passwordFile}") (
              lib.filterAttrs (_: database: !database.local) cfg.postgresql
            );
            ExecStopPost = lib.mkBefore [ "${recovery} cleanup ${inventory} ${staging}" ];
          };
        };
        systemd.tmpfiles.rules = [ "d ${cfg.backup.stagingDir} 0700 root root -" ];
      })
      (mkIf cfg.pressure.enable {
        users.groups.${config.homelab.storage.group} = { };
        assertions = [
          {
            assertion = cfg.pressure.resumeBytes > cfg.pressure.pauseBytes;
            message = "Pressure resumeBytes must exceed pauseBytes for hysteresis.";
          }
          {
            assertion =
              cfg.pressure.clients != { }
              && lib.all (
                name:
                builtins.elem name [
                  "qbittorrent"
                  "sabnzbd"
                ]
              ) (builtins.attrNames cfg.pressure.clients);
            message = "Pressure guard supports nonempty qBittorrent v5 and SABnzbd clients.";
          }
          {
            assertion = lib.all (client: safeRuntime client.credentialsFile) (
              builtins.attrValues cfg.pressure.clients
            );
            message = "Pressure credentials must remain in runtime files outside the Nix store.";
          }
        ];
        systemd.services.homelab-storage-pressure = {
          description = "Pause owned downloads while media storage is pressured";
          after = [ "network.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.python3}/bin/python3 ${../../scripts/operations/pressure.py} ${pressureConfig} /var/lib/homelab-storage-pressure/state.json";
            LoadCredential = lib.mapAttrsToList (
              name: client: "${name}:${client.credentialsFile}"
            ) cfg.pressure.clients;
            StateDirectory = "homelab-storage-pressure";
            StateDirectoryMode = "0700";
            DynamicUser = true;
            SupplementaryGroups = [ config.homelab.storage.group ];
            UMask = "0077";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            TimeoutStartSec = "2min";
          };
        };
        systemd.timers.homelab-storage-pressure = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitInactiveSec = "1min";
          };
        };
      })
      (mkIf cfg.monitoring.enable {
        services.gatus = {
          enable = true;
          openFirewall = mkDefault false;
          settings = {
            web = {
              address = mkDefault "127.0.0.1";
              port = mkDefault 8085;
            };
            endpoints = lib.mapAttrsToList (name: endpoint: {
              inherit name;
              inherit (endpoint) conditions;
              url = endpoint.healthUrl;
              interval = "1m";
              alerts = map (type: { inherit type; }) cfg.monitoring.alerts;
            }) (lib.filterAttrs (_: endpoint: endpoint.monitor) endpoints);
          };
        };
      })
      (mkIf cfg.notifications.enable {
        assertions = [
          {
            assertion = safeRuntime cfg.notifications.environmentFile;
            message = "ntfy credentials must be supplied at runtime outside the Nix store.";
          }
        ];
        services.ntfy-sh = {
          enable = true;
          environmentFile = cfg.notifications.environmentFile;
          settings = {
            base-url = mkDefault "http://127.0.0.1:2586";
            listen-http = mkDefault "127.0.0.1:2586";
            auth-default-access = "deny-all";
            enable-signup = false;
            cache-duration = mkDefault "24h";
            attachment-total-size-limit = mkDefault "100M";
            attachment-file-size-limit = mkDefault "5M";
          };
        };
      })
      (mkIf cfg.dashboard.enable {
        services.homepage-dashboard = {
          enable = true;
          openFirewall = mkDefault false;
          services = [
            {
              Homelab = lib.mapAttrsToList (name: endpoint: {
                ${name} = {
                  href = endpoint.url;
                  inherit (endpoint) description;
                };
              }) endpoints;
            }
          ];
        };
        systemd.services.homepage-dashboard.environment.HOSTNAME = mkDefault "127.0.0.1";
      })
    ]
  );
}
