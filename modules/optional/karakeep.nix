{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.karakeep;
  browser = config.services.karakeep.browser;
  enabled = config.homelab.optional.apps.karakeep.enable;
  browserUser = "karakeep-browser";
  stateDir = "/var/lib/karakeep";
  meiliMasterKeyFile = "${stateDir}/meili-master-key";
  nextAuthSecretFile = "${stateDir}/nextauth-secret";
  settingsFile = "${stateDir}/settings.env";
  managedEnvironment = {
    DISABLE_NEW_RELEASE_CHECK = "true";
    HOST = "127.0.0.1";
    HOSTNAME = "127.0.0.1";
    NEXTAUTH_URL = "http://127.0.0.1:${toString cfg.port}";
    NEXT_TELEMETRY_DISABLED = "1";
    PORT = toString cfg.port;
  };
  upstreamManagedNames = [
    "BROWSER_WEB_URL"
    "DATA_DIR"
    "MEILI_ADDR"
    "MEILI_MASTER_KEY"
    "NEXTAUTH_SECRET"
    "NEXTAUTH_URL_INTERNAL"
  ];
  protectedEnvironmentNames = builtins.attrNames managedEnvironment ++ upstreamManagedNames;
  overriddenProtectedEnvironment = lib.intersectLists protectedEnvironmentNames (
    builtins.attrNames cfg.extraEnvironment
  );
  secretSetup = pkgs.writeShellApplication {
    name = "homelab-karakeep-secret-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = ''
      umask 0077

      create_secret() {
        target="$1"
        if [ ! -s "$target" ]; then
          partial="$target.partial.$$"
          trap 'rm -f "$partial"' EXIT
          openssl rand -base64 36 >"$partial"
          chmod 0400 "$partial"
          mv "$partial" "$target"
          trap - EXIT
        fi
      }

      create_secret ${lib.escapeShellArg meiliMasterKeyFile}
      create_secret ${lib.escapeShellArg nextAuthSecretFile}

      settings_partial=${lib.escapeShellArg settingsFile}.partial.$$
      trap 'rm -f "$settings_partial"' EXIT
      printf 'MEILI_MASTER_KEY=%s\nNEXTAUTH_SECRET=%s\n' \
        "$(tr -d '\n' <${lib.escapeShellArg meiliMasterKeyFile})" \
        "$(tr -d '\n' <${lib.escapeShellArg nextAuthSecretFile})" \
        >"$settings_partial"
      chmod 0400 "$settings_partial"
      mv "$settings_partial" ${lib.escapeShellArg settingsFile}
      trap - EXIT
    '';
  };
  runtimeLauncher =
    name: executable:
    pkgs.writeShellScript name ''
      set -eu
      export MEILI_MASTER_KEY="$(${lib.getExe' pkgs.coreutils "cat"} ${lib.escapeShellArg meiliMasterKeyFile})"
      export NEXTAUTH_SECRET="$(${lib.getExe' pkgs.coreutils "cat"} ${lib.escapeShellArg nextAuthSecretFile})"
      exec ${executable}
    '';
  webLauncher = runtimeLauncher "homelab-karakeep-web" "${cfg.package}/lib/karakeep/start-web";
  workersLauncher = runtimeLauncher "homelab-karakeep-workers" "${cfg.package}/lib/karakeep/start-workers";
  commonHardening = lib.mapAttrs (_: lib.mkDefault) {
    AmbientCapabilities = "";
    CapabilityBoundingSet = "";
    DevicePolicy = "closed";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProtectSystem = "strict";
    RemoveIPC = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
in
{
  options.homelab.optional.karakeep = {
    package = lib.mkPackageOption pkgs "karakeep" { };
    uid = lib.mkOption {
      type = lib.types.ints.positive;
      default = 62462;
      description = "Dedicated Karakeep service UID, used numerically by the browser firewall rule.";
    };
    browserUid = lib.mkOption {
      type = lib.types.ints.positive;
      default = 62463;
      description = "Dedicated headless-browser UID, used numerically by the browser firewall rule.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5337;
      description = "Loopback port for the Karakeep web interface.";
    };
    browserPort = lib.mkOption {
      type = lib.types.port;
      default = 9222;
      description = "Loopback Chrome DevTools port used by Karakeep workers.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = null;
      description = "Optional runtime environment file for provider credentials. Karakeep and Meilisearch authentication variables are module-owned.";
    };
    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret Karakeep environment variables that do not change module-owned topology or authentication.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = cfg.environmentFile == null || !lib.hasPrefix "/nix/store/" cfg.environmentFile;
        message = "homelab.optional.karakeep.environmentFile must stay outside the Nix store.";
      }
      {
        assertion = overriddenProtectedEnvironment == [ ];
        message = "homelab.optional.karakeep.extraEnvironment cannot override protected settings: ${lib.concatStringsSep ", " overriddenProtectedEnvironment}";
      }
      {
        assertion = cfg.port != cfg.browserPort;
        message = "Karakeep web and browser ports must differ.";
      }
      {
        assertion = cfg.uid != cfg.browserUid;
        message = "Karakeep and its headless browser must use distinct UIDs.";
      }
    ];

    users.users.karakeep.uid = cfg.uid;
    users.groups.${browserUser} = { };
    users.users.${browserUser} = {
      isSystemUser = true;
      uid = cfg.browserUid;
      group = browserUser;
    };

    networking.nftables = {
      enable = true;
      tables.homelab-karakeep = {
        family = "inet";
        content = ''
          chain browser_access {
            type filter hook output priority 0; policy accept;
            ip daddr 127.0.0.1 tcp dport ${toString cfg.browserPort} meta skuid != { 0, ${toString cfg.uid}, ${toString cfg.browserUid} } reject
          }
        '';
      };
    };

    services.karakeep = {
      inherit (cfg) package environmentFile;
      extraEnvironment = managedEnvironment // cfg.extraEnvironment;
      browser = {
        enable = true;
        port = cfg.browserPort;
        exe = lib.mkDefault (lib.getExe pkgs.chromium);
      };
      meilisearch.enable = true;
    };
    services.meilisearch = {
      listenAddress = "127.0.0.1";
      masterKeyFile = meiliMasterKeyFile;
      settings.no_analytics = true;
    };

    systemd.services = {
      homelab-karakeep-secrets = {
        description = "Create Karakeep runtime authentication secrets";
        before = [
          "karakeep-init.service"
          "meilisearch.service"
        ];
        serviceConfig = commonHardening // {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "karakeep";
          Group = "karakeep";
          ExecStart = lib.getExe secretSetup;
          StateDirectory = "karakeep";
          StateDirectoryMode = "0700";
          RestrictNamespaces = true;
          MemoryMax = "256M";
          TasksMax = 64;
        };
      };
      karakeep-init = {
        requires = [ "homelab-karakeep-secrets.service" ];
        after = [ "homelab-karakeep-secrets.service" ];
        serviceConfig = commonHardening // {
          RestrictNamespaces = true;
          MemoryMax = "1G";
          TasksMax = 256;
        };
      };
      karakeep-web.serviceConfig = commonHardening // {
        ExecStart = lib.mkForce webLauncher;
        RestrictNamespaces = true;
        CPUQuota = "200%";
        MemoryMax = "2G";
        TasksMax = 512;
      };
      karakeep-workers = {
        wants = [
          "karakeep-browser.service"
          "meilisearch.service"
        ];
        after = [
          "karakeep-browser.service"
          "meilisearch.service"
        ];
        serviceConfig = commonHardening // {
          ExecStart = lib.mkForce workersLauncher;
          RestrictNamespaces = true;
          CPUQuota = "400%";
          MemoryMax = "4G";
          TasksMax = 1024;
        };
      };
      karakeep-browser = {
        # Chromium's renderer sandbox creates its own user and process
        # namespaces. Keep it enabled instead of inheriting upstream's
        # --no-sandbox fallback; the dedicated account and systemd filesystem
        # restrictions remain the outer confinement layer.
        script = lib.mkForce ''
          export HOME="$CACHE_DIRECTORY"
          exec ${browser.exe} \
            --headless \
            --disable-gpu \
            --remote-debugging-address=127.0.0.1 \
            --remote-debugging-port=${toString browser.port} \
            --hide-scrollbars \
            --user-data-dir="$STATE_DIRECTORY"
        '';
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = browserUser;
          Group = browserUser;
          PrivateUsers = lib.mkForce false;
          RestrictNamespaces = lib.mkForce false;
          CPUQuota = "200%";
          MemoryMax = "2G";
          TasksMax = 512;
          UMask = "0077";
        };
      };
      meilisearch = {
        requires = [ "homelab-karakeep-secrets.service" ];
        after = [ "homelab-karakeep-secrets.service" ];
        serviceConfig = {
          CPUQuota = "200%";
          MemoryMax = "2G";
          TasksMax = 512;
        };
      };
    };
  };
}
