{ config, lib, ... }:
let
  catalog = import ../catalog.nix;
  cfg = config.homelab.readiness;
  runtimePath =
    path:
    builtins.isString path
    && lib.hasPrefix "/" path
    && path != "/nix/store"
    && !(lib.hasPrefix "/nix/store/" path)
    && !(lib.hasInfix "/../" "${path}/")
    && !(lib.hasInfix "\n" path);
  runtimePaths =
    value:
    if builtins.isList value then value != [ ] && lib.all runtimePath value else runtimePath value;
  integrationKinds = lib.filter (name: (catalog.core.${name}.integration or null) != null) (
    builtins.attrNames catalog.core
  );
  hasIntegration =
    kind:
    config.homelab.integration.enable
    && lib.any (job: job.kind == kind) (lib.attrValues config.homelab.integration.services);
  integrationJob =
    kind:
    lib.findFirst (job: job.kind == kind) null (lib.attrValues config.homelab.integration.services);
  integrationSettings =
    kind:
    let
      job = integrationJob kind;
    in
    if job == null then { } else job.settings;
  autobrrFilterReady =
    filter:
    let
      actions = lib.attrByPath [ "actions" ] { } filter;
      values = lib.attrByPath [ "values" ] { } filter;
    in
    lib.attrByPath [ "indexers" ] [ ] filter != [ ]
    && actions != { }
    && (values.max_downloads or 0) > 0
    && (values.max_size or "") != "";
  resourceIntegrationKinds = [
    "sonarr"
    "radarr"
    "lidarr"
    "prowlarr"
  ];
  displayName =
    name:
    {
      sonarr = "Sonarr";
      radarr = "Radarr";
      lidarr = "Lidarr";
      bazarr = "Bazarr";
      prowlarr = "Prowlarr";
      jellyfin = "Jellyfin";
      seerr = "Seerr";
      navidrome = "Navidrome";
      audiobookshelf = "Audiobookshelf";
    }
    .${name};
  coreNames = builtins.attrNames catalog.core;
  optionalNames = builtins.attrNames catalog.optional;
  anyEnabled =
    lib.any (name: config.homelab.apps.${name}.enable) coreNames
    || lib.any (name: config.homelab.optional.apps.${name}.enable) optionalNames;
  backupJob = config.services.restic.backups.${config.homelab.operations.backup.job} or null;
  operationsReady =
    config.homelab.operations.enable
    && config.homelab.operations.monitoring.enable
    && config.homelab.operations.notifications.enable
    && runtimePath config.homelab.operations.notifications.environmentFile
    && backupJob != null
    && (runtimePath backupJob.repositoryFile || runtimePath backupJob.environmentFile)
    && (runtimePath backupJob.passwordFile || runtimePath backupJob.environmentFile);
  hostManagedApps = builtins.attrNames (
    lib.filterAttrs (_: service: service.hostManaged or false) (catalog.core // catalog.optional)
  );
  isEnabled =
    name:
    if builtins.hasAttr name config.homelab.apps then
      config.homelab.apps.${name}.enable
    else
      config.homelab.optional.apps.${name}.enable;
in
{
  options.homelab.readiness = {
    enable = lib.mkEnableOption ''
      strict checks that reject enabled applications without their production
      credentials, configuration ownership, recovery, and monitoring contracts
    '';
    hostManaged = lib.mkOption {
      type = lib.types.listOf (lib.types.enum hostManagedApps);
      default = [ ];
      description = ''
        Applications whose account, provider, hardware, client, or destructive
        policy was configured and tested by the consuming host. Listing a name
        records responsibility; it does not make the setup safe by itself.
      '';
    };
    checks = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            assertion = lib.mkOption {
              type = lib.types.bool;
              description = "Whether this production-readiness condition is satisfied.";
            };
            message = lib.mkOption {
              type = lib.types.str;
              description = "Actionable failure message for an unsatisfied readiness condition.";
            };
          };
        }
      );
      readOnly = true;
      internal = true;
      description = "Evaluated production-readiness assertions exposed for focused validation.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = cfg.checks;
    homelab.readiness.checks =
      lib.optional config.homelab.apps.qbittorrent.enable {
        assertion = runtimePath config.homelab.apps.qbittorrent.credentialsFile;
        message = "Production readiness requires a qBittorrent credentialsFile outside the Nix store.";
      }
      ++ lib.optional config.homelab.apps.sabnzbd.enable {
        assertion = runtimePaths config.services.sabnzbd.secretFiles;
        message = "Production readiness requires SABnzbd secretFiles with Web UI, API, and provider credentials.";
      }
      ++ lib.optional config.homelab.apps.nzbget.enable {
        assertion = runtimePath config.homelab.apps.nzbget.credentialsFile;
        message = "Production readiness requires an NZBGet credentialsFile outside the Nix store.";
      }
      ++ lib.optional config.homelab.optional.apps.autobrr.enable {
        assertion = hasIntegration "autobrr";
        message = "Production readiness requires a declared autobrr integration job.";
      }
      ++ lib.optional config.homelab.optional.apps.autobrr.enable {
        assertion =
          let
            job = integrationJob "autobrr";
          in
          job != null
          && runtimePath job.apiKeyFile
          && lib.attrByPath [ "downloadClients" ] { } job.settings != { }
          && (
            let
              filters = lib.attrValues (lib.attrByPath [ "filters" ] { } job.settings);
            in
            filters != [ ] && lib.all autobrrFilterReady filters
          )
          && runtimePath config.services.autobrr.secretFile;
        message = "Production readiness requires configured autobrr clients, bounded filters, and runtime secrets.";
      }
      ++ lib.optional config.homelab.optional.apps.syncthing.enable {
        assertion =
          config.services.syncthing.settings.devices != { }
          && (
            let
              folders = lib.attrValues config.services.syncthing.settings.folders;
            in
            folders != [ ]
            && lib.all (
              folder: folder.devices != [ ] && lib.attrByPath [ "versioning" "type" ] "" folder != ""
            ) folders
          )
          && runtimePath config.services.syncthing.guiPasswordFile;
        message = "Production readiness requires explicit Syncthing devices, versioned folders, and GUI password.";
      }
      ++ lib.optional config.homelab.optional.apps.adguardhome.enable {
        assertion =
          !config.services.adguardhome.mutableSettings
          && lib.attrByPath [ "dns" "upstream_dns" ] [ ] config.services.adguardhome.settings != [ ]
          && lib.attrByPath [ "dns" "bootstrap_dns" ] [ ] config.services.adguardhome.settings != [ ]
          && (
            let
              users = lib.attrByPath [ "users" ] [ ] config.services.adguardhome.settings;
            in
            users != [ ]
            && lib.all (
              user:
              (user.name or "") != ""
              && builtins.match "\\$2[aby]\\$[0-9][0-9]\\$[./A-Za-z0-9]{53}" (user.password or "") != null
            ) users
          );
        message = "Production readiness requires explicit AdGuard Home upstream, bootstrap, bcrypt users, and immutable settings.";
      }
      ++ lib.optional config.homelab.optional.apps.scrutiny.enable {
        assertion =
          config.services.scrutiny.collector.enable
          && (
            let
              devices = lib.attrByPath [ "allow_listed_devices" ] [ ] config.services.scrutiny.collector.settings;
            in
            devices != [ ] && lib.all (lib.hasPrefix "/dev/disk/by-id/") devices
          );
        message = "Production readiness requires an enabled Scrutiny collector and device allowlist.";
      }
      ++ lib.optional config.homelab.optional.apps.paperless.enable {
        assertion = config.services.paperless.exporter.enable;
        message = "Production readiness requires the Paperless document exporter in addition to state backup.";
      }
      ++ lib.optional config.homelab.optional.apps.unpackerr.enable {
        assertion = lib.any (name: lib.attrByPath [ name ] [ ] config.services.unpackerr.settings != [ ]) [
          "sonarr"
          "radarr"
          "lidarr"
          "readarr"
          "whisparr"
          "folder"
        ];
        message = "Production readiness requires at least one explicit Unpackerr manager or watch-folder.";
      }
      ++ lib.optional config.homelab.optional.apps.shelfmark.enable {
        assertion =
          let
            environmentFile = lib.attrByPath [
              "EnvironmentFile"
            ] null config.systemd.services.shelfmark.serviceConfig;
          in
          runtimePaths environmentFile;
        message = "Production readiness requires a Shelfmark runtime environment file with authentication and provider credentials.";
      }
      ++ map (name: {
        assertion =
          !config.homelab.apps.${name}.enable
          || (
            let
              job = integrationJob name;
            in
            job != null && runtimePath job.apiKeyFile && job.resources != [ ]
          );
        message = "Production readiness requires configured ${displayName name} integration resources and a runtime API key.";
      }) resourceIntegrationKinds
      ++ lib.optional config.homelab.apps.bazarr.enable {
        assertion =
          let
            job = integrationJob "bazarr";
          in
          job != null && runtimePath job.apiKeyFile && job.settings != { };
        message = "Production readiness requires configured Bazarr integration settings and a runtime API key.";
      }
      ++ lib.optional config.homelab.apps.jellyfin.enable {
        assertion =
          let
            job = integrationJob "jellyfin";
          in
          job != null && runtimePath job.apiKeyFile;
        message = "Production readiness requires a dedicated Jellyfin API key for recurring reconciliation after attended bootstrap.";
      }
      ++ lib.optional config.homelab.apps.jellyfin.enable {
        assertion =
          lib.attrByPath [ "login" ] { } (integrationSettings "jellyfin") != { }
          && lib.attrByPath [ "libraries" ] { } (integrationSettings "jellyfin") != { }
          && lib.attrByPath [ "users" ] { } (integrationSettings "jellyfin") != { };
        message = "Production readiness requires configured Jellyfin integration policy for login, libraries, and users.";
      }
      ++ lib.optional config.homelab.apps.seerr.enable {
        assertion =
          lib.attrByPath [ "login" ] { } (integrationSettings "seerr") != { }
          && lib.attrByPath [ "libraries" ] [ ] (integrationSettings "seerr") != [ ]
          && lib.attrByPath [ "main" ] { } (integrationSettings "seerr") != { }
          && (
            lib.attrByPath [ "radarr" ] { } (integrationSettings "seerr") != { }
            || lib.attrByPath [ "sonarr" ] { } (integrationSettings "seerr") != { }
          );
        message = "Production readiness requires configured Seerr integration policy for login, libraries, requests, and a media manager.";
      }
      ++ lib.optional config.homelab.apps.navidrome.enable {
        assertion =
          lib.attrByPath [ "login" ] { } (integrationSettings "navidrome") != { }
          && lib.attrByPath [ "users" ] { } (integrationSettings "navidrome") != { };
        message = "Production readiness requires configured Navidrome integration policy for login and non-admin users.";
      }
      ++ lib.optional config.homelab.apps.audiobookshelf.enable {
        assertion =
          lib.attrByPath [ "login" ] { } (integrationSettings "audiobookshelf") != { }
          && lib.attrByPath [ "libraries" ] { } (integrationSettings "audiobookshelf") != { }
          && lib.attrByPath [ "users" ] { } (integrationSettings "audiobookshelf") != { };
        message = "Production readiness requires configured Audiobookshelf integration policy for login, libraries, and users.";
      }
      ++ map (name: {
        assertion = !config.homelab.apps.${name}.enable || hasIntegration name;
        message = "Production readiness requires a declared ${displayName name} integration job.";
      }) integrationKinds
      ++ map (name: {
        assertion = !isEnabled name || builtins.elem name cfg.hostManaged;
        message = "Production readiness requires acknowledged host-managed setup for ${name}.";
      }) hostManagedApps
      ++ lib.optional config.homelab.storage.enable {
        assertion = config.homelab.storage.requiredMounts != [ ];
        message = "Production readiness requires an explicit media mount in homelab.storage.requiredMounts.";
      }
      ++ lib.optional anyEnabled {
        assertion = operationsReady;
        message = "Production readiness requires operations, backup, monitoring, and notifications with runtime credentials.";
      };
  };
}
