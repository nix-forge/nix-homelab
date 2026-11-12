{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.homelab.optional.apps.miniflux.enable;
  cfg = config.homelab.optional.miniflux;
  service = config.services.miniflux;
  stateDir = "/var/lib/homelab-miniflux";
  generatedCredentialsFile = "${stateDir}/admin.env";
  credentialsFile =
    if cfg.adminCredentialsFile == null then generatedCredentialsFile else cfg.adminCredentialsFile;
  bootstrapMarker = "${stateDir}/initial-feeds-imported";
  listenMatch = builtins.match "127[.]0[.]0[.]1:([0-9]+)" service.config.LISTEN_ADDR;
  port = if listenMatch == null then null else lib.toInt (builtins.head listenMatch);
  upgradeEnabled = cfg.contentUpgrade.revision != null;
  upgradePolicy = pkgs.writeText "homelab-miniflux-content-policy.json" (
    builtins.toJSON {
      feeds = cfg.initialFeeds;
      publicUrl = service.config.BASE_URL or "http://localhost";
      inherit (cfg.contentUpgrade) disabledFeeds backfillLimit stylesheet;
    }
  );
  seed = pkgs.writeText "homelab-miniflux-initial-feeds.json" (builtins.toJSON cfg.initialFeeds);
  credentials = pkgs.writeShellApplication {
    name = "homelab-miniflux-credentials";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = (import ../../lib/render-text.nix) ./scripts/homelab-miniflux-credentials.sh {
      lib_escapeShellArg_generatedCredentialsFile = lib.escapeShellArg generatedCredentialsFile;
    };
  };
  bootstrap = pkgs.writers.writePython3Bin "homelab-miniflux-bootstrap" {
    # The repository formatter uses 88 columns and breaks before operators.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/optional/bootstrap_miniflux.py);
in
{
  options.homelab.optional.miniflux.adminCredentialsFile = lib.mkOption {
    default = null;
    type = lib.types.nullOr lib.types.str;
    description = "Private runtime EnvironmentFile containing ADMIN_USERNAME and ADMIN_PASSWORD. Null generates a first-run credential.";
  };

  options.homelab.optional.miniflux.initialFeeds = lib.mkOption {
    default = [ ];
    description = "Feeds added once to a new Miniflux account. Later user changes are never reconciled or overwritten.";
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          url = lib.mkOption {
            type = lib.types.str;
            description = "Feed URL, preferably the publisher's HTTPS RSS or Atom endpoint.";
          };
          crawler = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Fetch the publisher article body for new entries in this feed.";
          };
          rewriteRules = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Miniflux content rewrite rules, tested for this publisher.";
          };
          scraperRules = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Optional publisher-specific article CSS selector.";
          };
          category = lib.mkOption {
            type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9 &-]*";
            description = "Initial reading category.";
          };
        };
      }
    );
  };

  options.homelab.optional.miniflux.contentUpgrade = {
    revision = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9_-]*");
      default = null;
      description = "Explicit one-time upgrade revision. Null disables upgrades; increment to apply revised initial-feed extraction settings to existing subscriptions.";
    };
    disabledFeeds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Exact feed URLs whose polling is disabled once, preserving entries and read/star state.";
    };
    backfillLimit = lib.mkOption {
      type = lib.types.ints.between 0 50;
      default = 20;
      description = "Maximum recent unread entries inspected per extraction-enabled feed per revision. Zero disables backfill.";
    };
    stylesheet = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Native reader CSS installed once only when the account has no custom stylesheet.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = !upgradeEnabled || (service.config.MEDIA_CUSTOM_PROXY_URL or "") == "";
        message = "Miniflux content upgrades require the built-in media proxy so stored publisher URLs can be restored safely.";
      }
      {
        assertion = port != null && port > 0 && port <= 65535;
        message = "The homelab Miniflux listener must be a single 127.0.0.1 TCP endpoint.";
      }
      {
        assertion = lib.all (
          feed:
          (lib.hasPrefix "https://" feed.url || lib.hasPrefix "http://127.0.0.1:" feed.url)
          && !(lib.hasInfix "@" feed.url)
          && !(lib.hasInfix "\n" feed.url)
        ) cfg.initialFeeds;
        message = "Initial Miniflux feeds must use HTTPS, except local test fixtures on 127.0.0.1.";
      }
      {
        assertion =
          builtins.length (lib.unique (map (feed: feed.url) cfg.initialFeeds))
          == builtins.length cfg.initialFeeds;
        message = "Initial Miniflux feeds must have unique URLs.";
      }
      {
        assertion =
          lib.hasPrefix "/" credentialsFile
          && !(lib.hasPrefix "/nix/store/" credentialsFile)
          && !(lib.hasInfix "\n" credentialsFile)
          && service.adminCredentialsFile == credentialsFile;
        message = "The homelab Miniflux admin credentials file must be a private runtime path outside the Nix store.";
      }
    ];

    services.miniflux = {
      enable = true;
      adminCredentialsFile = credentialsFile;
      config = {
        LISTEN_ADDR = lib.mkDefault "127.0.0.1:18080";
        CREATE_ADMIN = true;
        POLLING_FREQUENCY = lib.mkDefault 60;
        POLLING_LIMIT_PER_HOST = lib.mkDefault 2;
        WORKER_POOL_SIZE = lib.mkDefault 4;
        DATABASE_MAX_CONNS = lib.mkDefault 5;
        CLEANUP_ARCHIVE_READ_DAYS = lib.mkDefault 30;
        CLEANUP_ARCHIVE_UNREAD_DAYS = lib.mkDefault 90;
      };
    };
    services.postgresql.enableTCPIP = lib.mkDefault false;

    systemd.services =
      (lib.optionalAttrs (cfg.adminCredentialsFile == null) {
        homelab-miniflux-credentials = {
          description = "Create the first Miniflux administrator credential";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe credentials;
            StateDirectory = "homelab-miniflux";
            StateDirectoryMode = "0700";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            MemoryMax = "64M";
            TasksMax = 16;
          };
        };
      })
      // {
        miniflux = {
          requires = lib.optional (cfg.adminCredentialsFile == null) "homelab-miniflux-credentials.service";
          after = lib.optional (cfg.adminCredentialsFile == null) "homelab-miniflux-credentials.service";
          serviceConfig = {
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            # Feeds may use the public Internet. Keep private network services
            # inaccessible even if a remote feed redirects or DNS changes.
            IPAddressDeny = [
              "0.0.0.0/8"
              "10.0.0.0/8"
              "100.64.0.0/10"
              "169.254.0.0/16"
              "172.16.0.0/12"
              "192.168.0.0/16"
              "198.18.0.0/15"
              "224.0.0.0/4"
              "240.0.0.0/4"
              "fc00::/7"
              "fe80::/10"
              "ff00::/8"
            ];
            IPAddressAllow = [
              "127.0.0.0/8"
              "::1/128"
            ];
            CPUQuota = "150%";
            MemoryMax = "512M";
            TasksMax = 128;
          };
        };
        homelab-miniflux-content-upgrade = lib.mkIf upgradeEnabled {
          description = "Upgrade Miniflux article fetching and repair recent unread excerpts once";
          wantedBy = [ "multi-user.target" ];
          requires = [
            "miniflux.service"
          ]
          ++ lib.optional (cfg.initialFeeds != [ ]) "homelab-miniflux-bootstrap.service";
          after = [
            "miniflux.service"
            "network-online.target"
          ]
          ++ lib.optional (cfg.initialFeeds != [ ]) "homelab-miniflux-bootstrap.service";
          wants = [ "network-online.target" ];
          environment = {
            MINIFLUX_BOOTSTRAP_URL = "http://127.0.0.1:${toString port}";
            MINIFLUX_UPGRADE_STATE = "${stateDir}/content-upgrade-${cfg.contentUpgrade.revision}.json";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe bootstrap} --upgrade ${upgradePolicy}";
            EnvironmentFile = credentialsFile;
            Restart = "on-failure";
            RestartSec = "30s";
            TimeoutStartSec = "2h";
            StateDirectory = "homelab-miniflux";
            StateDirectoryMode = "0700";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
            ];
            IPAddressDeny = [ "any" ];
            IPAddressAllow = [ "127.0.0.1/32" ];
            MemoryMax = "128M";
            TasksMax = 32;
          };
        };
        homelab-miniflux-bootstrap = lib.mkIf (cfg.initialFeeds != [ ]) {
          description = "Import the initial curated Miniflux feeds once";
          wantedBy = [ "multi-user.target" ];
          requires = [ "miniflux.service" ];
          after = [
            "miniflux.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          environment = {
            MINIFLUX_BOOTSTRAP_URL = "http://127.0.0.1:${toString port}";
            MINIFLUX_BOOTSTRAP_MARKER = bootstrapMarker;
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe bootstrap} ${seed}";
            EnvironmentFile = credentialsFile;
            Restart = "on-failure";
            RestartSec = "1h";
            StateDirectory = "homelab-miniflux";
            StateDirectoryMode = "0700";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
            ];
            MemoryMax = "96M";
            TasksMax = 32;
          };
        };
      };

    homelab.operations = lib.mkIf config.homelab.operations.enable {
      state.miniflux = {
        paths = [ stateDir ];
        units =
          lib.optional upgradeEnabled "homelab-miniflux-content-upgrade.service"
          ++ lib.optional (cfg.initialFeeds != [ ]) "homelab-miniflux-bootstrap.service"
          ++ [ "miniflux.service" ];
      };
      postgresql.miniflux = {
        database = "miniflux";
        local = true;
      };
      endpoints.miniflux = {
        url = "http://127.0.0.1:${toString port}";
        healthUrl = "http://127.0.0.1:${toString port}/healthcheck";
        description = "Curated RSS and Atom reading";
      };
    };
  };
}
