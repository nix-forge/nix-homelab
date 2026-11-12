# Native, VPN-confined BookOrbit with vetted release search and optional
# request fulfillment. Hosts supply identities, paths, and runtime secrets.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.homelab.apps.bookorbit;
  inherit (cfg) acquisition;
  vpn = config.homelab.vpn.namespace;
  qbit = config.homelab.apps.qbittorrent;
  siteHost = "${cfg.https.siteName}.${config.homelab.operations.lanHttps.domain}";
  inherit (cfg) storage;
  runtimePath = import ../lib/runtime-path.nix lib;
  home = cfg.stateDir;
  bindRoot = "/run/bookorbitmedia";
  bindIntake = "${bindRoot}/intake";
  libraryBinds = lib.imap0 (index: path: {
    source = path;
    target = "${bindRoot}/library${toString index}";
    applicationPath = "/books/${lib.removePrefix "${storage.libraryDir}/" path}";
  }) acquisition.writableMediaDirs;
  bindSpecs = [
    {
      source = dirOf acquisition.downloadDir;
      target = bindIntake;
    }
  ]
  ++ libraryBinds;
  bindUnits = map (item: "${utils.escapeSystemdPath item.target}.mount") bindSpecs;
  secretRuntime = "/run/bookorbit-secrets";
  appSecretNames = [
    "jwt-secret"
    "setup-token"
    "request-key"
    "podcast-key"
  ];
  names = appSecretNames ++ [
    "admin-username"
    "admin-email"
    "admin-password"
  ];
  secret = name: cfg.credentials.${name};
  runtimeSecret = name: "${secretRuntime}/${name}";
  inherit (cfg) port;
  prowlarrBridgePort = cfg.prowlarr.bridgePort;
  prowlarrSocket = "/run/bookorbit-prowlarr/bridge.sock";
  namespaceUnit = "vpn-confinement-netns@${vpn.name}.service";
  appUnit = "bookorbit.service";
  dbUnit = "bookorbit-native-db.service";
  nativeDbDir = "${home}/postgres/native";
  nativeDbSocket = "/run/bookorbit-postgres";
  nativeDbUrl = "postgresql:///bookorbit?host=${nativeDbSocket}&user=bookorbit";
  nativePostgres = (pkgs.postgresql_18.override { systemdSupport = true; }).withPackages (packages: [
    packages.pgvector
  ]);
  nativeAppLauncher = pkgs.writeShellScript "bookorbit-native-start" (
    (import ../../lib/render-text.nix) ./scripts/bookorbit-native-start.sh {
      pkgs_coreutils = pkgs.coreutils;
      runtimeSecret_jwt_secret = runtimeSecret "jwt-secret";
      runtimeSecret_setup_token = runtimeSecret "setup-token";
      runtimeSecret_request_key = runtimeSecret "request-key";
      runtimeSecret_podcast_key = runtimeSecret "podcast-key";
      lib_getExe_config_services_bookorbit_package = lib.getExe config.services.bookorbit.package;
    }
  );
  metadataPsqlInput = "${lib.getExe' nativePostgres "psql"} -X -q -v ON_ERROR_STOP=1 -h ${nativeDbSocket} -U bookorbit -d bookorbit";
  resolver = pkgs.writeText "bookorbit-vpn-resolv.conf" (
    lib.concatMapStringsSep "" (server: "nameserver ${server}\n") config.homelab.vpn.interface.dns
  );
  nsswitch = pkgs.writeText "bookorbit-vpn-nsswitch.conf" "hosts: files dns\n";
  networkPolicy = {
    NetworkNamespacePath = "/run/netns/${vpn.name}";
    BindReadOnlyPaths = [
      "${resolver}:/etc/resolv.conf"
      "${nsswitch}:/etc/nsswitch.conf"
    ];
    InaccessiblePaths = [
      "-/run/systemd/resolve/io.systemd.Resolve"
      "-/run/systemd/resolve/io.systemd.Resolve.Monitor"
      "-/run/nscd"
      "-/run/dbus/system_bus_socket"
    ];
  };
  bootstrap = pkgs.writers.writePython3Bin "bootstrap-bookorbit" {
    # The repository formats with Ruff's current operator wrapping style.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/services/bootstrap_bookorbit.py);
  bootstrapSettings = pkgs.writeText "bookorbit-bootstrap-settings.json" (
    builtins.toJSON {
      vpnTag = cfg.prowlarr.vpnTag;
      proxy = {
        name = cfg.prowlarr.proxyName;
        host = cfg.prowlarr.proxyHost;
        port = cfg.prowlarr.proxyPort;
      };
      bookCategories = cfg.prowlarr.bookCategories;
      managerName = cfg.prowlarr.managerName;
      acquisition = {
        enabled = acquisition.enable;
      }
      // lib.optionalAttrs acquisition.enable {
        name = "qBittorrent books";
        url = "http://${qbit.bindAddress}:${toString qbit.webuiPort}";
        inherit (acquisition) category;
        inherit (acquisition) downloadDir;
        localDownloadDir = "/intake/downloads";
        inherit (acquisition) minReleaseScore;
        inherit (acquisition) minImportScore;
        inherit (acquisition) destinations;
      };
      libraries = map (item: {
        inherit (item) name icon organizationMode;
        folders = [ item.folder ];
        allowedFormats = item.formats;
      }) cfg.libraries;
    }
  );
  stageSecrets = pkgs.writeShellApplication {
    name = "bookorbit-stage-secrets";
    runtimeInputs = [ pkgs.coreutils ];
    text = (import ../../lib/render-text.nix) ./scripts/bookorbit-stage-secrets.sh {
      appSecrets = lib.escapeShellArgs appSecretNames;
      inherit secretRuntime;
    };
  };
  grantMediaAccess = pkgs.writeShellApplication {
    name = "bookorbit-grant-media-access";
    runtimeInputs = [
      pkgs.acl
      pkgs.coreutils
      pkgs.findutils
    ];
    text = (import ../../lib/render-text.nix) ./scripts/bookorbit-grant-media-access.sh {
      lib_escapeShellArg_storage_rootDir = lib.escapeShellArg storage.rootDir;
      lib_escapeShellArg_storage_libraryDir = lib.escapeShellArg storage.libraryDir;
      lib_escapeShellArgs_storage_mediaDirs = lib.escapeShellArgs storage.mediaDirs;
      lib_optionalString_acquisition_enable_old_dock_lib_escapeShe =
        lib.optionalString acquisition.enable
          (
            (import ../../lib/render-text.nix) ./scripts/bookorbit-prepare-acquisition-storage.sh {
              lib_escapeShellArg_home_data_book_dock = lib.escapeShellArg "${home}/data/book-dock";
              lib_escapeShellArg_storage_group = lib.escapeShellArg storage.group;
              lib_escapeShellArg_builtins_dirOf_acquisition_downloadDir = lib.escapeShellArg (
                dirOf acquisition.downloadDir
              );
              lib_escapeShellArg_acquisition_dockDir = lib.escapeShellArg acquisition.dockDir;
              lib_escapeShellArg_acquisition_downloadDir = lib.escapeShellArg acquisition.downloadDir;
              lib_escapeShellArgs_acquisition_writableMediaDirs = lib.escapeShellArgs acquisition.writableMediaDirs;
            }
          );
    };
  };
  initializeMetadata = pkgs.writeShellApplication {
    name = "bookorbit-initialize-metadata";
    runtimeInputs = [ pkgs.coreutils ];
    text = (import ../../lib/render-text.nix) ./scripts/bookorbit-initialize-metadata.sh {
      inherit metadataPsqlInput;
      metadataSql = pkgs.replaceVars ./scripts/bookorbit-initialize-metadata.sql {
        lib_replaceStrings_builtins_toJSON_cfg_metadataProviders = lib.replaceStrings [ "'" ] [ "''" ] (
          builtins.toJSON cfg.metadataProviders
        );
      };

    };
  };
in
{
  options.homelab.apps.bookorbit = {
    enable = lib.mkEnableOption "private BookOrbit discovery and requests";
    uid = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Dedicated BookOrbit service UID.";
    };
    gid = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Dedicated BookOrbit service GID.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 13006;
      description = "Private BookOrbit listener port.";
    };
    publicUrl = lib.mkOption {
      type = lib.types.strMatching "https://[a-z0-9][a-z0-9.-]+";
      default = "https://${siteHost}";
      defaultText = lib.literalExpression ''"https://''${config.homelab.apps.bookorbit.https.siteName}.''${config.homelab.operations.lanHttps.domain}"'';
      readOnly = true;
      description = "Canonical private HTTPS origin derived from the site name and host domain.";
    };
    https = {
      siteName = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
        default = "bookorbit";
        description = "Private HTTPS site label.";
      };
      allowedCIDRs = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "Site-specific client CIDRs, or null to inherit LAN HTTPS policy.";
      };
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bookorbit";
      description = "Persistent application and database state.";
    };
    credentials = lib.genAttrs names (
      name:
      lib.mkOption {
        type = lib.types.str;
        description = "Runtime file for the ${name} credential.";
      }
    );
    secretReadyUnit = lib.mkOption {
      type = lib.types.str;
      description = "Unit preparing credential files.";
    };
    readerReadyUnit = lib.mkOption {
      type = lib.types.str;
      description = "Unit preparing the shared book library.";
    };
    storage = {
      rootDir = lib.mkOption {
        type = lib.types.str;
        description = "Parent directory requiring traversal ACL.";
      };
      libraryDir = lib.mkOption {
        type = lib.types.str;
        description = "Host media directory mounted read-only at /books.";
      };
      mediaDirs = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Host book directories granted read access.";
      };
      group = lib.mkOption {
        type = lib.types.str;
        description = "Shared media group.";
      };
      requiredMounts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Mounts required before scanning.";
      };
      readyUnit = lib.mkOption {
        type = lib.types.str;
        description = "Unit preparing storage paths.";
      };
    };
    prowlarr = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 9696;
        description = "Host-local Prowlarr port.";
      };
      bridgePort = lib.mkOption {
        type = lib.types.port;
        default = 13007;
        description = "Namespace-local Prowlarr bridge port.";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        description = "Runtime Prowlarr API key file.";
      };
      readyUnit = lib.mkOption {
        type = lib.types.str;
        description = "Unit reconciling Prowlarr indexers and proxy.";
      };
      vpnTag = lib.mkOption {
        type = lib.types.str;
        default = "vpn";
        description = "Prowlarr tag selecting VPN-routed sources.";
      };
      proxyName = lib.mkOption {
        type = lib.types.str;
        default = "vpn";
        description = "Prowlarr SOCKS5 proxy name.";
      };
      proxyHost = lib.mkOption {
        type = lib.types.str;
        description = "VPN-confined SOCKS5 proxy address expected in Prowlarr.";
      };
      proxyPort = lib.mkOption {
        type = lib.types.port;
        description = "VPN-confined SOCKS5 proxy port expected in Prowlarr.";
      };
      bookCategories = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.ints.positive;
        default = [
          3000
          3030
          7000
          7020
          7030
        ];
        description = "Prowlarr categories accepted as book-capable.";
      };
      managerName = lib.mkOption {
        type = lib.types.str;
        default = "Prowlarr VPN books";
        description = "BookOrbit's managed source group.";
      };
    };
    acquisition = {
      enable = lib.mkEnableOption "automatic fulfillment after a book request is approved";
      category = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
        default = "bookorbit";
        description = "Dedicated qBittorrent category owned by BookOrbit.";
      };
      downloadDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host path for the dedicated qBittorrent category, mounted only in BookOrbit.";
      };
      dockDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Book Dock path on the same filesystem as downloads and libraries.";
      };
      writableMediaDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Library directories BookOrbit may write when filing approved requests.";
      };
      usernameFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime qBittorrent Web UI username file.";
      };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime qBittorrent Web UI password file.";
      };
      destinations = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "BookOrbit library names for ebook and audiobook requests. Comic files use the ebook destination.";
      };
      minReleaseScore = lib.mkOption {
        type = lib.types.ints.between 50 100;
        default = 90;
        description = "Minimum release match score for an automatic grab.";
      };
      minImportScore = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 85;
        description = "Minimum downloaded-file match score before filing without review.";
      };
    };
    libraries = lib.mkOption {
      type = lib.types.nonEmptyListOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "BookOrbit library name.";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              description = "BookOrbit icon name.";
            };
            folder = lib.mkOption {
              type = lib.types.str;
              description = "Application folder beneath /books in the service mount namespace.";
            };
            formats = lib.mkOption {
              type = lib.types.nonEmptyListOf lib.types.str;
              description = "Allowed file extensions.";
            };
            organizationMode = lib.mkOption {
              type = lib.types.enum [
                "book_per_folder"
                "book_per_file"
              ];
              description = "BookOrbit grouping mode.";
            };
          };
        }
      );
      description = "Catalog libraries created on first start.";
    };
    metadataProviders = lib.mkOption {
      inherit ((pkgs.formats.json { })) type;
      default = {
        amazon.enabled = false;
        goodreads.enabled = false;
        itunes.enabled = false;
        openLibrary.enabled = true;
      };
      description = "Initial metadata provider policy, applied only if unset.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          config.homelab.vpn.enable
          && config.homelab.operations.lanHttps.enable
          && config.services.vpnConfinement.namespaces.${vpn.name}.servicePolicy == "enforced"
          && config.services.vpnConfinement.namespaces.${vpn.name}.dns.mode == "strict"
          && !config.services.vpnConfinement.namespaces.${vpn.name}.dns.allowHostResolverIPC
          && config.services.vpnConfinement.namespaces.${vpn.name}.wireguard.endpointPinning.enable;
        message = "BookOrbit requires private HTTPS and an enforced VPN namespace with strict DNS and a pinned endpoint.";
      }
      {
        assertion =
          cfg.prowlarr.proxyHost == vpn.bindAddress
          && config.homelab.indexerProxy.enable
          && cfg.prowlarr.proxyPort == config.homelab.indexerProxy.port
          && !config.homelab.apps.prowlarr.vpn.enable
          && config.homelab.apps.prowlarr.proxyOnly;
        message = "BookOrbit requires a proxy-only Prowlarr and the VPN-confined SOCKS endpoint.";
      }
      {
        assertion = lib.all runtimePath ([ cfg.prowlarr.apiKeyFile ] ++ map secret names);
        message = "BookOrbit credential files must be runtime paths outside the Nix store.";
      }
      {
        assertion =
          !acquisition.enable
          || (
            qbit.enable
            && qbit.vpn.enable
            && config.systemd.services.qbittorrent.vpn.namespace == vpn.name
            && acquisition.usernameFile != null
            && acquisition.passwordFile != null
            && runtimePath acquisition.usernameFile
            && runtimePath acquisition.passwordFile
          );
        message = "Automatic BookOrbit requests require VPN-confined qBittorrent and runtime Web UI credentials.";
      }
      {
        assertion =
          !acquisition.enable
          || (
            acquisition.downloadDir != null
            && acquisition.dockDir != null
            && runtimePath acquisition.downloadDir
            && runtimePath acquisition.dockDir
            && lib.hasPrefix "${storage.rootDir}/" acquisition.downloadDir
            && lib.hasPrefix "${storage.rootDir}/" acquisition.dockDir
            && acquisition.downloadDir != acquisition.dockDir
            && dirOf acquisition.downloadDir == dirOf acquisition.dockDir
            && !(lib.hasPrefix "${storage.libraryDir}/" acquisition.downloadDir)
            && !(lib.hasPrefix "${storage.libraryDir}/" acquisition.dockDir)
            &&
              lib.attrByPath [ acquisition.category "savePath" ] null qbit.configuration.categories
              == acquisition.downloadDir
          );
        message = "BookOrbit needs separate, declared Book Dock and qBittorrent category paths on prepared storage.";
      }
      {
        assertion =
          !acquisition.enable
          || (
            acquisition.writableMediaDirs != [ ]
            && lib.all (path: builtins.elem path storage.mediaDirs) acquisition.writableMediaDirs
            &&
              builtins.attrNames acquisition.destinations == [
                "audiobook"
                "ebook"
              ]
            && lib.all (
              name:
              lib.any (
                library:
                library.name == name
                && builtins.elem "${storage.libraryDir}/${lib.removePrefix "/books/" library.folder}" acquisition.writableMediaDirs
              ) cfg.libraries
            ) (builtins.attrValues acquisition.destinations)
          );
        message = "BookOrbit automation destinations must be declared libraries inside the writable media paths.";
      }
      {
        assertion = lib.all (
          item: runtimePath item.folder && lib.hasPrefix "/books/" item.folder
        ) cfg.libraries;
        message = "BookOrbit libraries must stay beneath the /books mount.";
      }
      {
        assertion =
          lib.all runtimePath (
            [
              home
              storage.rootDir
              storage.libraryDir
            ]
            ++ storage.mediaDirs
          )
          && lib.all (path: lib.hasPrefix "${storage.libraryDir}/" path) storage.mediaDirs;
        message = "BookOrbit media ACL targets must stay beneath the library directory.";
      }
      {
        assertion =
          lib.all
            (
              name:
              config.systemd.services.${name}.serviceConfig.NetworkNamespacePath
              == networkPolicy.NetworkNamespacePath
            )
            [
              "bookorbit-metadata-policy"
              "bookorbit-bootstrap"
              "bookorbit-prowlarr-namespace-bridge"
              "bookorbit"
            ];
        message = "BookOrbit network workloads must use the VPN namespace.";
      }
    ];
    services.bookorbit = {
      enable = true;
      createDatabaseLocally = false;
      environment = {
        APP_DATA_PATH = "${home}/data";
        DATABASE_URL = nativeDbUrl;
        HOST = vpn.bindAddress;
        PORT = port;
        APP_URL = cfg.publicUrl;
        CLIENT_URL = cfg.publicUrl;
        TRUST_PROXY = "true";
        LIBRARY_BROWSE_ROOT = "/books";
        BOOK_DOCK_PATH = if acquisition.enable then "/intake/dock" else "${home}/data/book-dock";
        NODE_MAX_OLD_SPACE_SIZE = "1536";
        LOG_LEVEL = "warn";
        CSP_ALLOW_CLOUDFLARE_INSIGHTS = "false";
      };
    };
    users.groups.bookorbit.gid = cfg.gid;
    users.users.bookorbit = {
      isSystemUser = true;
      inherit (cfg) uid;
      group = "bookorbit";
      extraGroups = [ storage.group ];
      inherit home;
      createHome = true;
      linger = false;
      autoSubUidGidRange = false;
    };
    systemd.tmpfiles.rules = [
      "d ${home} 0700 bookorbit bookorbit - -"
      "d ${home}/data 0700 bookorbit bookorbit - -"
      "d ${home}/postgres 0755 bookorbit bookorbit - -"
      "d ${nativeDbDir} 0700 bookorbit bookorbit - -"
    ]
    ++ lib.optionals acquisition.enable (
      [
        "d ${bindRoot} 0750 root bookorbit - -"
        "d ${bindIntake} 0750 root bookorbit - -"
      ]
      ++ map (item: "d ${item.target} 0750 root bookorbit - -") libraryBinds
    );

    systemd.mounts = lib.optionals acquisition.enable (
      map (item: {
        what = item.source;
        where = item.target;
        type = "none";
        options = "bind,rw";
        wantedBy = [ "multi-user.target" ];
        requires = [ "bookorbit-media-access.service" ];
        after = [ "bookorbit-media-access.service" ];
        unitConfig = {
          # These runtime bind mounts depend on a service that starts after
          # basic.target. The mount default would order them before
          # local-fs.target, creating a boot cycle through basic.target.
          DefaultDependencies = false;
          RequiresMountsFor = storage.requiredMounts ++ [ item.source ];
        };
      }) bindSpecs
    );

    systemd.services = {
      bookorbit-prowlarr-host-bridge = {
        description = "Bridge BookOrbit's private Unix socket to local Prowlarr";
        wantedBy = [ "multi-user.target" ];
        requires = [ "prowlarr.service" ];
        after = [ "prowlarr.service" ];
        serviceConfig = {
          Type = "simple";
          User = "bookorbit";
          Group = "bookorbit";
          ExecStart = "${lib.getExe pkgs.socat} UNIX-LISTEN:${prowlarrSocket},fork,mode=0600 TCP:127.0.0.1:${toString cfg.prowlarr.port}";
          RuntimeDirectory = "bookorbit-prowlarr";
          RuntimeDirectoryMode = "0700";
          IPAddressDeny = [ "any" ];
          IPAddressAllow = [ "127.0.0.0/8" ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          Restart = "on-failure";
        };
      };
      bookorbit-prowlarr-namespace-bridge = {
        description = "Expose local Prowlarr socket to BookOrbit's VPN namespace";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "bookorbit-prowlarr-host-bridge.service"
          namespaceUnit
        ];
        after = [
          "bookorbit-prowlarr-host-bridge.service"
          namespaceUnit
        ];
        serviceConfig = networkPolicy // {
          Type = "simple";
          User = "bookorbit";
          Group = "bookorbit";
          ExecStart = "${lib.getExe pkgs.socat} TCP-LISTEN:${toString prowlarrBridgePort},bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:${prowlarrSocket}";
          IPAddressDeny = [ "any" ];
          IPAddressAllow = [ "127.0.0.0/8" ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          Restart = "on-failure";
        };
      };
      bookorbit-media-access = {
        description = "Grant BookOrbit scoped access to book media and its intake";
        wantedBy = [ "multi-user.target" ];
        requires = [ storage.readyUnit ];
        after = [ storage.readyUnit ];
        unitConfig.RequiresMountsFor =
          storage.requiredMounts
          ++ [ storage.libraryDir ]
          ++ lib.optionals acquisition.enable [
            acquisition.dockDir
            acquisition.downloadDir
          ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe grantMediaAccess;
          IPAddressDeny = [ "any" ];
          ProtectSystem = "strict";
          ReadWritePaths = [ storage.rootDir ];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
        };
      };
      bookorbit-secrets = {
        description = "Stage sealed BookOrbit credentials in private runtime storage";
        wantedBy = [ "multi-user.target" ];
        requires = [ cfg.secretReadyUnit ];
        after = [ cfg.secretReadyUnit ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "bookorbit";
          Group = "bookorbit";
          ExecStart = lib.getExe stageSecrets;
          LoadCredential = map (name: "${name}:${secret name}") appSecretNames;
          RuntimeDirectory = "bookorbit-secrets";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [ secretRuntime ];
        };
      };
      bookorbit-metadata-policy = {
        description = "Limit initial BookOrbit metadata providers";
        wantedBy = [ "multi-user.target" ];
        requires = [ appUnit ];
        after = [ appUnit ];
        serviceConfig = networkPolicy // {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "bookorbit";
          Group = "bookorbit";
          ExecStart = lib.getExe initializeMetadata;
          Environment = [ "HOME=${home}" ];
          RuntimeDirectory = "bookorbit-metadata";
          RuntimeDirectoryMode = "0755";
          ProtectSystem = "strict";
          PrivateTmp = true;
          ReadWritePaths = [ home ];
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };
      bookorbit-bootstrap = {
        description = "Claim and verify the sealed BookOrbit administrator";
        wantedBy = [
          "multi-user.target"
          appUnit
        ];
        bindsTo = [ appUnit ];
        requires = [
          appUnit
          "bookorbit-metadata-policy.service"
          "bookorbit-prowlarr-namespace-bridge.service"
          cfg.prowlarr.readyUnit
          cfg.secretReadyUnit
        ]
        ++ lib.optionals acquisition.enable [
          "qbittorrent.service"
          "homelab-configure-qbittorrent.service"
        ];
        after = [
          appUnit
          "bookorbit-metadata-policy.service"
          "bookorbit-prowlarr-namespace-bridge.service"
          cfg.prowlarr.readyUnit
          cfg.secretReadyUnit
        ]
        ++ lib.optionals acquisition.enable [
          "qbittorrent.service"
          "homelab-configure-qbittorrent.service"
        ];
        serviceConfig = networkPolicy // {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "bookorbit";
          Group = "bookorbit";
          ExecStart = "${bootstrap}/bin/bootstrap-bookorbit http://${vpn.bindAddress}:${toString port} http://127.0.0.1:${toString prowlarrBridgePort} ${bootstrapSettings}";
          LoadCredential =
            (map (name: "${name}:${secret name}") [
              "admin-username"
              "admin-email"
              "admin-password"
              "setup-token"
            ])
            ++ [ "prowlarr-api-key:${cfg.prowlarr.apiKeyFile}" ]
            ++ lib.optionals acquisition.enable [
              "qbittorrent-username:${acquisition.usernameFile}"
              "qbittorrent-password:${acquisition.passwordFile}"
            ];
          RuntimeDirectory = "bookorbit-bootstrap";
          RuntimeDirectoryMode = "0755";
          IPAddressDeny = [ "any" ];
          IPAddressAllow = [
            "${vpn.bindAddress}/32"
            "127.0.0.0/8"
          ]
          ++ lib.optionals acquisition.enable [ "${qbit.bindAddress}/32" ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          LimitCORE = 0;
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };
      bookorbit-native-db = {
        description = "BookOrbit PostgreSQL 18 with local socket only";
        wantedBy = [ "multi-user.target" ];
        after = [ storage.readyUnit ];
        requires = [ storage.readyUnit ];
        unitConfig.RequiresMountsFor = [ nativeDbDir ];
        serviceConfig = {
          # PostgreSQL is built with systemd support and announces readiness
          # after recovery, before dependent migrations are allowed to start.
          Type = "notify";
          NotifyAccess = "main";
          TimeoutStartSec = "5min";
          User = "bookorbit";
          Group = "bookorbit";
          ExecStartPre = "${pkgs.coreutils}/bin/test -f ${nativeDbDir}/PG_VERSION";
          ExecStart = "${lib.getExe' nativePostgres "postgres"} -D ${nativeDbDir} -k ${nativeDbSocket} -c listen_addresses= -p 5432";
          RuntimeDirectory = "bookorbit-postgres";
          RuntimeDirectoryMode = "0700";
          WorkingDirectory = home;
          ProtectSystem = "strict";
          ReadWritePaths = [
            nativeDbDir
            nativeDbSocket
          ];
          PrivateTmp = true;
          NoNewPrivileges = true;
          Restart = "on-failure";
          RestartSec = "10s";
          MemoryMax = "1G";
          TasksMax = 128;
        };
      };
      bookorbit-migrate = {
        requires = [ dbUnit ];
        after = [ dbUnit ];
        serviceConfig = {
          ProtectSystem = "strict";
          ReadWritePaths = [ home ];
          NoNewPrivileges = true;
        };
      };
      bookorbit = {
        requires = [
          dbUnit
          "bookorbit-secrets.service"
          "bookorbit-media-access.service"
          cfg.readerReadyUnit
          namespaceUnit
          storage.readyUnit
        ]
        ++ lib.optionals acquisition.enable bindUnits;
        after = [
          dbUnit
          "bookorbit-secrets.service"
          "bookorbit-media-access.service"
          cfg.readerReadyUnit
          namespaceUnit
          storage.readyUnit
        ]
        ++ lib.optionals acquisition.enable bindUnits;
        unitConfig.RequiresMountsFor = storage.requiredMounts ++ [
          home
          storage.libraryDir
        ];
        serviceConfig = networkPolicy // {
          ExecStart = lib.mkForce nativeAppLauncher;
          BindPaths = lib.optionals acquisition.enable (
            [ "${bindIntake}:/intake" ] ++ map (item: "${item.target}:${item.applicationPath}") libraryBinds
          );
          BindReadOnlyPaths =
            networkPolicy.BindReadOnlyPaths
            ++ lib.optionals (!acquisition.enable) [ "${storage.libraryDir}:/books" ];
          ReadWritePaths = [ "${home}/data" ] ++ lib.optionals acquisition.enable [ bindIntake ];
          WorkingDirectory = home;
          PrivateUsers = lib.mkForce false;
          StateDirectoryMode = "0700";
          SystemCallFilter = lib.mkForce [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
          MemoryMax = "3G";
          TasksMax = 256;
        };
      };
    };

    homelab.operations.state.bookorbit = lib.mkIf config.homelab.operations.enable {
      paths = [ home ] ++ lib.optionals acquisition.enable [ acquisition.dockDir ];
      units = [
        appUnit
        dbUnit
      ];
    };
    homelab.operations.endpoints.bookorbit = lib.mkIf config.homelab.operations.enable {
      url = cfg.publicUrl;
      healthUrl = "http://${vpn.bindAddress}:${toString port}/api/v1/health";
      description = "BookOrbit discovery and requests";
    };
    homelab.operations.lanHttps.sites.${cfg.https.siteName} = {
      upstream = "http://${vpn.bindAddress}:${toString port}";
      streaming = true;
      allowedCIDRs = cfg.https.allowedCIDRs;
    };
    services.nginx.virtualHosts.${siteHost}.locations."/".extraConfig = lib.mkAfter ''
      access_log off;
      if (!-f /run/bookorbit-metadata/ready) { return 503; }
      if (!-f /run/bookorbit-bootstrap/ready) { return 503; }
      add_header X-Content-Type-Options nosniff always;
      add_header Strict-Transport-Security "max-age=31536000" always;
      add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; media-src 'self' blob:; worker-src 'self' blob:; connect-src 'self' wss://${siteHost}; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'" always;
      add_header Referrer-Policy "no-referrer" always;
    '';
    homelab.vpn.namespace.hostIngressPorts.tcp = [ port ];
  };
}
