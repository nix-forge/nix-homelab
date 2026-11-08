{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.freshrss;
  enabled = config.homelab.optional.apps.freshrss.enable;
  native = config.services.freshrss;
  inherit (native) pool;
  localUrl = (import ../lib/http-url.nix) lib cfg.bindAddress cfg.port;
  stateDir = config.services.freshrss.dataDir;
  feedJson = pkgs.writeText "homelab-freshrss-feeds.json" (builtins.toJSON cfg.initialFeeds);
  inherit (cfg) package;
  fileUsername = cfg.usernameFile != null;
  blockedNetworks = [
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
  bootstrap = pkgs.writeShellApplication {
    name = "homelab-freshrss-bootstrap";
    runtimeInputs = [ config.services.phpfpm.phpPackage ];
    text = (import ../../lib/render-text.nix) ./scripts/homelab-freshrss-bootstrap.sh {
      lib_escapeShellArg_stateDir = lib.escapeShellArg stateDir;
      lib_escapeShellArg_toString_package = lib.escapeShellArg (toString package);
      if_cfg_requireGridView_then_1_else_0 = if cfg.requireGridView then "1" else "0";
      lib_escapeShellArg_if_config_time_timeZone_null_then_UTC_els = lib.escapeShellArg (
        if config.time.timeZone == null then "UTC" else config.time.timeZone
      );
      scripts_optional_bootstrap_freshrss_php = ../../scripts/optional/bootstrap-freshrss.php;
      if_fileUsername_then_username_credential_else_lib_escapeShel =
        if fileUsername then "--username-credential" else lib.escapeShellArg cfg.username;
      lib_escapeShellArg_toString_feedJson = lib.escapeShellArg (toString feedJson);
      lib_escapeShellArg_stateDir_news_starter_imported = lib.escapeShellArg "${stateDir}/news-starter-imported";
    };
  };
in
{
  options.homelab.optional.freshrss = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.freshrss;
      defaultText = lib.literalExpression "pkgs.freshrss";
      description = "FreshRSS package to run; select an extension-bearing variant in the host if desired.";
    };
    requireGridView = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Fail the first-run setup if the selected package lacks Grid View.";
    };
    apiEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable mobile client APIs; each reader still needs a separate API password.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 18081;
      description = "Private FreshRSS HTTP listener port.";
    };
    bindAddress = lib.mkOption {
      type = lib.types.enum [
        "127.0.0.1"
        "::1"
      ];
      default = "127.0.0.1";
      description = "Loopback address for the native Nginx listener.";
    };
    username = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_][A-Za-z0-9_.@-]{1,38}";
      default = "reader";
      description = "FreshRSS login name.";
    };
    usernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Private runtime login-name file; when set, username is ignored and never rendered into service scripts. Existing account renames require a state migration before activation.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = "Root-readable runtime file containing the FreshRSS login password. systemd passes it privately to the configuration service.";
    };
    initialFeeds = lib.mkOption {
      default = [ ];
      description = "Publisher feeds imported once; later subscription choices belong to the user.";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption { type = lib.types.str; };
            title = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Publisher display name instead of the raw feed URL.";
            };
            category = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9 &-]*"; };
          };
        }
      );
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = native.webserver == "nginx";
        message = "The homelab FreshRSS integration requires services.freshrss.webserver = nginx for its private listener.";
      }
      {
        assertion = pool == null || config.services.phpfpm.pools.${pool}.user == native.user;
        message = "FreshRSS requires its selected PHP-FPM pool user to match services.freshrss.user; configure the native pool explicitly when overriding the user.";
      }
      {
        assertion =
          !fileUsername
          || (lib.hasPrefix "/" cfg.usernameFile && !lib.hasPrefix "/nix/store/" cfg.usernameFile);
        message = "FreshRSS needs a private runtime username file outside the Nix store.";
      }
      {
        assertion = !fileUsername || config.services.freshrss.database.type == "sqlite";
        message = "FreshRSS runtime username provisioning currently supports SQLite only.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.passwordFile && !lib.hasPrefix "/nix/store/" cfg.passwordFile;
        message = "FreshRSS needs a private runtime password file outside the Nix store.";
      }
      {
        assertion = lib.all (
          feed:
          (lib.hasPrefix "https://" feed.url || lib.hasPrefix "http://127.0.0.1:" feed.url)
          && !lib.hasInfix "@" feed.url
        ) cfg.initialFeeds;
        message = "FreshRSS starter feeds must use HTTPS, except local test fixtures.";
      }
      {
        assertion =
          builtins.length (lib.unique (map (feed: feed.url) cfg.initialFeeds))
          == builtins.length cfg.initialFeeds;
        message = "FreshRSS starter feeds must have unique URLs.";
      }
    ];

    services.freshrss = {
      enable = true;
      inherit package;
      defaultUser = if fileUsername then "" else cfg.username;
      passwordFile = "/run/credentials/freshrss-config.service/news-password";
      database.type = "sqlite";
      baseUrl = lib.mkDefault localUrl;
      virtualHost = lib.mkDefault "homelab-freshrss-internal";
    };
    services.nginx.virtualHosts.${native.virtualHost} = {
      listen = [
        {
          addr = cfg.bindAddress;
          inherit (cfg) port;
        }
      ];
      extraConfig = ''add_header Referrer-Policy "no-referrer" always;'';
    };
    services.phpfpm.pools = lib.mkIf (pool != null) {
      ${if pool == null then "unconfigured" else pool}.settings = {
        "pm.max_children" = lib.mkForce 4;
        "pm.start_servers" = lib.mkForce 1;
        "pm.min_spare_servers" = lib.mkForce 1;
        "pm.max_spare_servers" = lib.mkForce 2;
      };
    };
    systemd.services = {
      "phpfpm-${if pool == null then "unconfigured" else pool}" = lib.mkIf (pool != null) {
        serviceConfig = {
          IPAddressDeny = blockedNetworks;
          IPAddressAllow = [
            "127.0.0.0/8"
            "::1/128"
          ];
          MemoryMax = "512M";
        };
      };
      freshrss-config.serviceConfig = {
        LoadCredential = [
          "news-password:${cfg.passwordFile}"
        ]
        ++ lib.optional fileUsername "news-username:${cfg.usernameFile}";
        MemoryMax = "256M";
      };
      # Runtime provisioning extends upstream's static defaultUser interface.
      # Static-name deployments continue to use the upstream setup script.
      freshrss-config.script = lib.mkIf fileUsername (
        lib.mkForce (
          (import ../../lib/render-text.nix) ./scripts/freshrss-install-and-provision.sh {
            lib_escapeShellArg_toString_package = lib.escapeShellArg (toString package);
            lib_escapeShellArg_config_services_freshrss_baseUrl = lib.escapeShellArg config.services.freshrss.baseUrl;
            lib_escapeShellArg_config_services_freshrss_language = lib.escapeShellArg config.services.freshrss.language;
            lib_escapeShellArg_stateDir_config_php = lib.escapeShellArg "${stateDir}/config.php";
            lib_getExe_config_services_phpfpm_phpPackage = lib.getExe config.services.phpfpm.phpPackage;
            scripts_optional_provision_freshrss_user_php = ../../scripts/optional/provision-freshrss-user.php;
          }
        )
      );
      freshrss-config.postStart = (import ../../lib/render-text.nix) ./scripts/freshrss-configure-api.sh {
        lib_getExe_config_services_phpfpm_phpPackage = lib.getExe config.services.phpfpm.phpPackage;
        inherit package;
        lib_boolToString_cfg_apiEnabled = lib.boolToString cfg.apiEnabled;
      };
      freshrss-updater.serviceConfig = {
        IPAddressDeny = blockedNetworks;
        IPAddressAllow = [
          "127.0.0.0/8"
          "::1/128"
        ];
        MemoryMax = "256M";
      };
      homelab-freshrss-bootstrap = {
        description = "Set FreshRSS reading preferences and curated starter subscriptions";
        wantedBy = [ "multi-user.target" ];
        requires = [ "freshrss-config.service" ];
        after = [ "freshrss-config.service" ];
        serviceConfig = {
          Type = "oneshot";
          LoadCredential = lib.optional fileUsername "news-username:${cfg.usernameFile}";
          ExecStart = lib.getExe bootstrap;
          User = native.user;
          Group = config.users.users.${native.user}.group;
          WorkingDirectory = package;
          Restart = "on-failure";
          RestartSec = "1h";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ stateDir ];
          MemoryMax = "384M";
          TasksMax = 32;
        };
      };
    };
    homelab.operations = lib.mkIf config.homelab.operations.enable {
      state.freshrss = {
        paths = [ stateDir ];
        units = [
          "freshrss-config.service"
          "freshrss-updater.service"
          "freshrss-updater.timer"
          "homelab-freshrss-bootstrap.service"
        ]
        ++ lib.optional (pool != null) "phpfpm-${pool}.service";
      };
      endpoints.freshrss = {
        url = localUrl;
        healthUrl = localUrl;
        description = "Visual curated RSS and Atom reading";
      };
    };
  };
}
