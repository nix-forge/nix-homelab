{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional;
  storage = config.homelab.storage;
  names = [
    "autobrr"
    "cross-seed"
    "unpackerr"
    "flaresolverr"
    "komga"
    "kavita"
    "shelfmark"
    "pinchflat"
    "immich"
    "paperless"
    "syncthing"
    "adguardhome"
    "scrutiny"
  ];
  enabled = name: cfg.apps.${name}.enable;
  selected = lib.filter enabled names;
  readers = lib.filter enabled [
    "komga"
    "kavita"
  ];
  writers = lib.filter enabled [
    "cross-seed"
    "unpackerr"
    "shelfmark"
    "pinchflat"
  ];
  media = readers ++ writers;
  units = lib.concatMap (
    name:
    if name == "immich" then
      [ "immich-server" ]
      ++ lib.optional config.services.immich.machine-learning.enable "immich-machine-learning"
    else if name == "paperless" then
      [
        "paperless-web"
        "paperless-consumer"
        "paperless-task-queue"
        "paperless-scheduler"
      ]
    else if name == "scrutiny" then
      [ "scrutiny" ]
    else
      [ name ]
  ) selected;
  guardedDirs =
    lib.optionals (enabled "cross-seed") config.services.cross-seed.settings.linkDirs
    ++ lib.optionals (enabled "shelfmark") [ config.services.shelfmark.environment.INGEST_DIR ]
    ++ lib.optionals (enabled "pinchflat") [ config.services.pinchflat.mediaDir ];
  profile = {
    name = "Homelab 1080p";
    reset_unmatched_scores.enabled = false;
    upgrade = {
      allowed = false;
      until_quality = "WEB 1080p";
      until_score = 0;
    };
    min_format_score = 0;
    qualities = [
      {
        name = "WEB 1080p";
        qualities = [
          "WEBDL-1080p"
          "WEBRip-1080p"
        ];
      }
    ];
  };
  quality = app: definition: key: {
    quality_definition = {
      type = definition;
      qualities =
        map
          (name: {
            inherit name;
            min = 5;
            preferred = 40;
            max = 80;
          })
          [
            "WEBDL-1080p"
            "WEBRip-1080p"
          ];
    };
    base_url =
      let
        raw = config.services.${app}.settings.server.urlbase or "";
        base =
          if raw == "" || raw == "/" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" raw)}";
      in
      "http://127.0.0.1:${toString config.services.${app}.settings.server.port}${base}";
    api_key._secret = key;
    custom_formats = import ./quality-formats.nix app "Homelab 1080p";
    delete_old_custom_formats = false;
    quality_profiles = [ profile ];
  };
  guideSettings = pkgs.writeText "recyclarr-settings.yml" (
    builtins.toJSON { resource_providers = import ./quality-resources.nix { inherit pkgs; }; }
  );
  runtimePath = lib.types.nullOr (lib.types.strMatching "/[^\n]+");
in
{
  imports = [ ./maintainerr.nix ];
  options.homelab.optional = {
    apps = lib.genAttrs names (name: {
      enable = lib.mkEnableOption "${name} with private homelab defaults";
    });
    quality = {
      enable = lib.mkEnableOption "a conservative, locally declared Recyclarr 1080p profile";
      sonarrApiKeyFile = lib.mkOption {
        type = runtimePath;
        default = null;
        description = "User-provided runtime Sonarr API key. Null leaves Sonarr unmanaged.";
      };
      radarrApiKeyFile = lib.mkOption {
        type = runtimePath;
        default = null;
        description = "User-provided runtime Radarr API key. Null leaves Radarr unmanaged.";
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf (selected != [ ]) {
      networking.firewall.enable = lib.mkDefault true;
      services = lib.genAttrs selected (_: {
        enable = true;
      });
      # Preserve upstream sandbox exceptions, including browser and JIT runtimes.
      systemd.services = lib.genAttrs units (name: {
        serviceConfig = {
          CPUWeight = lib.mkDefault 25;
          IOWeight = lib.mkDefault 25;
          Nice = lib.mkDefault 10;
          NoNewPrivileges = lib.mkDefault true;
          ProtectHome = lib.mkDefault (name != "syncthing");
          PrivateTmp = lib.mkDefault true;
          ProtectSystem = lib.mkDefault (if name == "syncthing" then "full" else "strict");
          RestrictSUIDSGID = lib.mkDefault true;
        };
      });
    })
    (lib.mkIf (media != [ ]) {
      homelab.storage.enable = true;
      assertions = map (path: {
        assertion =
          lib.hasPrefix "${storage.rootDir}/" path
          && !(lib.hasInfix "/../" "${path}/")
          && !(lib.hasInfix "\n" path);
        message = "Optional media output directories must be descendants of homelab.storage.rootDir without parent traversal.";
      }) guardedDirs;
      systemd.services = {
        homelab-optional-storage = {
          description = "Prepare optional media outputs after the required mount checks";
          requires = [ "homelab-storage.service" ];
          after = [ "homelab-storage.service" ];
          before = map (name: "${name}.service") media;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0007";
          };
          script = ''
            ${pkgs.python3}/bin/python3 ${../../scripts/storage/prepare.py} ${lib.escapeShellArg storage.group} ${lib.escapeShellArgs guardedDirs}
          '';
        };
      }
      // lib.genAttrs media (name: {
        after = [ "homelab-optional-storage.service" ];
        requires = [ "homelab-optional-storage.service" ];
        unitConfig.RequiresMountsFor = storage.requiredMounts ++ [ storage.rootDir ];
        serviceConfig = {
          SupplementaryGroups = [ storage.group ];
          UMask = lib.mkForce "0007";
        }
        // lib.optionalAttrs (builtins.elem name readers) { BindReadOnlyPaths = [ storage.libraryDir ]; }
        // lib.optionalAttrs (name == "cross-seed") {
          # One bind mount preserves hardlinks across data and link directories.
          ReadWritePaths = [
            storage.rootDir
            config.services.cross-seed.configDir
          ];
        }
        // lib.optionalAttrs (name == "unpackerr") {
          ReadWritePaths = [ storage.downloadsDir ];
          BindReadOnlyPaths = [ storage.libraryDir ];
        }
        // lib.optionalAttrs (name == "shelfmark") {
          ReadWritePaths = [ config.services.shelfmark.environment.INGEST_DIR ];
          BindReadOnlyPaths = [ storage.downloadsDir ];
        }
        // lib.optionalAttrs (name == "pinchflat") {
          ReadWritePaths = [ config.services.pinchflat.mediaDir ];
        };
      });
    })
    (lib.mkIf cfg.quality.enable {
      assertions = [
        {
          assertion = cfg.quality.sonarrApiKeyFile != null || cfg.quality.radarrApiKeyFile != null;
          message = "Recyclarr quality policy requires at least one user-provided API key file.";
        }
        {
          assertion =
            let
              names = map lib.toLower (
                lib.concatMap (app: builtins.attrNames (config.services.recyclarr.configuration.${app} or { })) [
                  "sonarr"
                  "radarr"
                ]
              );
            in
            builtins.length names == builtins.length (lib.unique names);
          message = "Recyclarr instance names must be unique across Sonarr and Radarr (case-insensitive); duplicate names are skipped upstream.";
        }
      ]
      ++
        map
          (path: {
            assertion = path == null || !(lib.hasPrefix "/nix/store/" path);
            message = "Recyclarr API keys must be runtime files outside the Nix store.";
          })
          [
            cfg.quality.sonarrApiKeyFile
            cfg.quality.radarrApiKeyFile
          ];
      services.recyclarr = {
        enable = true;
        schedule = lib.mkDefault "Sun *-*-* 04:10:00";
        configuration =
          lib.optionalAttrs (cfg.quality.sonarrApiKeyFile != null) {
            sonarr.homelab-sonarr = quality "sonarr" "series" cfg.quality.sonarrApiKeyFile;
          }
          // lib.optionalAttrs (cfg.quality.radarrApiKeyFile != null) {
            radarr.homelab-radarr = quality "radarr" "movie" cfg.quality.radarrApiKeyFile;
          };
      };
      systemd.services.recyclarr = {
        # JSON is valid YAML. Append to the native runtime secret substitution.
        preStart = lib.mkAfter ''
          ${pkgs.coreutils}/bin/install -m 0600 ${guideSettings} /var/lib/recyclarr/settings.yml
        '';
        serviceConfig = {
          CPUWeight = 25;
          IOWeight = 25;
          Nice = 10;
        };
      };
    })
    (lib.mkIf (enabled "autobrr") {
      services.autobrr = {
        openFirewall = lib.mkDefault false;
        settings.host = lib.mkDefault "127.0.0.1";
      };
      systemd.services.autobrr.serviceConfig.ReadWritePaths = [ "/var/lib/autobrr" ];
    })
    (lib.mkIf (enabled "cross-seed") {
      services.cross-seed = {
        useGenConfigDefaults = lib.mkDefault true;
        settings = {
          host = lib.mkDefault "127.0.0.1";
          linkDirs = lib.mkDefault [ "${storage.downloadsDir}/cross-seed" ];
          dataDirs = lib.mkDefault [ ];
          linkType = lib.mkDefault "hardlink";
          action = lib.mkDefault "inject";
          matchMode = lib.mkDefault "strict";
          skipRecheck = lib.mkDefault false;
          delay = lib.mkDefault 60;
          searchCadence = lib.mkDefault "1 day";
          rssCadence = lib.mkDefault "1 hour";
        };
      };
      assertions = [
        {
          assertion = config.services.cross-seed.settingsFile != null;
          message = "cross-seed requires a runtime settingsFile containing authenticated torrentClients and Torznab URLs.";
        }
      ];
    })
    (lib.mkIf (enabled "unpackerr") {
      services.unpackerr.settings = {
        parallel = lib.mkDefault 1;
        max_retries = lib.mkDefault 3;
        file_mode = lib.mkDefault "0660";
        dir_mode = lib.mkDefault "0770";
      };
    })
    (lib.mkIf (enabled "flaresolverr") {
      services.flaresolverr.openFirewall = lib.mkDefault false;
      systemd.services.flaresolverr = {
        environment.HOST = lib.mkDefault "127.0.0.1";
        serviceConfig = {
          MemoryHigh = lib.mkDefault "1G";
          MemoryMax = lib.mkDefault "2G";
          TasksMax = lib.mkDefault 128;
        };
      };
    })
    (lib.mkIf (enabled "komga") {
      services.komga = {
        openFirewall = lib.mkDefault false;
        settings.server = {
          address = lib.mkDefault "127.0.0.1";
          port = lib.mkDefault 25600;
        };
      };
      systemd.services.komga.serviceConfig.ReadWritePaths = [ config.services.komga.stateDir ];
    })
    (lib.mkIf (enabled "kavita") {
      services.kavita.settings.IpAddresses = lib.mkDefault "127.0.0.1";
      systemd.services.kavita.serviceConfig.ReadWritePaths = [ config.services.kavita.dataDir ];
    })
    (lib.mkIf (enabled "shelfmark") {
      services.shelfmark = {
        openFirewall = lib.mkDefault false;
        environment = {
          FLASK_HOST = lib.mkDefault "127.0.0.1";
          AUTH_METHOD = lib.mkDefault "builtin";
          INGEST_DIR = lib.mkDefault "${storage.libraryDir}/books";
          HARDLINK_TORRENTS = lib.mkDefault "false";
        };
      };
    })
    (lib.mkIf (enabled "pinchflat") {
      services.pinchflat = {
        openFirewall = lib.mkDefault false;
        selfhosted = lib.mkDefault false;
        mediaDir = lib.mkDefault "${storage.libraryDir}/videos";
        extraConfig = {
          YT_DLP_WORKER_CONCURRENCY = lib.mkDefault 1;
        };
      };
    })
    (lib.mkIf (enabled "immich") {
      services.immich = {
        host = lib.mkDefault "127.0.0.1";
        openFirewall = lib.mkDefault false;
        settings.job =
          lib.genAttrs
            [
              "backgroundTask"
              "smartSearch"
              "metadataExtraction"
              "faceDetection"
              "search"
              "sidecar"
              "library"
              "migration"
              "thumbnailGeneration"
              "videoConversion"
              "notifications"
              "ocr"
              "workflow"
              "editor"
              "integrityCheck"
            ]
            (_: {
              concurrency = lib.mkDefault 1;
            });
      };
    })
    (lib.mkIf (enabled "paperless") {
      assertions = [
        {
          assertion = config.services.paperless.environmentFile != null;
          message = "Paperless requires a user-provided runtime environmentFile containing PAPERLESS_SECRET_KEY.";
        }
      ];
      services.paperless = {
        address = lib.mkDefault "127.0.0.1";
        settings = {
          PAPERLESS_TASK_WORKERS = lib.mkDefault 1;
          PAPERLESS_THREADS_PER_WORKER = lib.mkDefault 1;
          PAPERLESS_OCR_LANGUAGE = lib.mkDefault "eng";
          PAPERLESS_OCR_MODE = lib.mkDefault "auto";
          PAPERLESS_CONSUMER_RECURSIVE = lib.mkDefault false;
          PAPERLESS_AI_ENABLED = lib.mkDefault false;
        };
      };
    })
    (lib.mkIf (enabled "syncthing") {
      # Syncthing creates declared folders at runtime. A blanket read-only root
      # would prevent both its config bootstrap and new folder creation.
      systemd.services.syncthing.unitConfig.RequiresMountsFor = [
        config.services.syncthing.configDir
        config.services.syncthing.databaseDir
      ]
      ++ map (folder: folder.path) (
        lib.attrValues (
          lib.filterAttrs (_: folder: folder.enable) config.services.syncthing.settings.folders
        )
      );
      services.syncthing = {
        openDefaultPorts = lib.mkDefault false;
        guiAddress = lib.mkDefault "127.0.0.1:8384";
        settings.options = {
          globalAnnounceEnabled = lib.mkDefault false;
          localAnnounceEnabled = lib.mkDefault false;
          relaysEnabled = lib.mkDefault false;
          urAccepted = lib.mkDefault (-1);
        };
      };
    })
    (lib.mkIf (enabled "adguardhome") {
      services.adguardhome = {
        host = lib.mkDefault "127.0.0.1";
        openFirewall = lib.mkDefault false;
        allowDHCP = lib.mkDefault false;
        settings.dns = {
          bind_hosts = lib.mkDefault [ "127.0.0.1" ];
          port = lib.mkDefault 5353;
        };
      };
    })
    (lib.mkIf (enabled "scrutiny") {
      services.scrutiny = {
        openFirewall = lib.mkDefault false;
        settings.web = {
          listen = {
            host = lib.mkDefault "127.0.0.1";
            port = lib.mkDefault 8083;
          };
          influxdb.host = lib.mkDefault "127.0.0.1";
        };
        collector = {
          enable = lib.mkDefault false;
          schedule = lib.mkDefault "daily";
        };
      };
      services.influxdb2.settings.http-bind-address = lib.mkIf config.services.scrutiny.influxdb.enable (
        lib.mkDefault "127.0.0.1:8086"
      );
    })
  ];
}
