{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.scrypted;
  scripts = pkgs.homelab-iot-scripts;
  stateDir = "/var/lib/scrypted";
  serverRoot = "${cfg.package}/lib/node_modules/@scrypted/server";
  # The pure-Python charset-normalizer avoids compiling mypy as a build input.
  # This reduces peak builder memory while preserving the Python API.
  python312 =
    (pkgs.python312.override {
      packageOverrides = _: prev: {
        charset-normalizer = prev.charset-normalizer.override { withMypyc = false; };
      };
    }).withPackages
      (ps: [ ps.pip ]);
  runtimeFile = path: lib.hasPrefix "/" path && !lib.hasPrefix "/nix/store/" path;
  compatibilityCheck =
    name: source: test:
    pkgs.runCommand name { } (
      (import ../../lib/render-text.nix) ./scripts/scrypted-check-compatibility.sh {
        inherit scripts source;
        builtins_baseNameOf_source = baseNameOf source;
        inherit test;
        builtins_baseNameOf_test = baseNameOf test;
        cfg_package = cfg.package;
        inherit serverRoot;
      }
    );
  authCheck =
    compatibilityCheck "scrypted-auth-compat" "${scripts}/scrypted-auth.cjs"
      "${scripts}/scrypted-auth.test.cjs";
  settingsCheck =
    compatibilityCheck "scrypted-managed-settings-compat" "${scripts}/scrypted-managed-settings.cjs"
      "${scripts}/scrypted-managed-settings.test.cjs";
  markerCheck = pkgs.runCommand "scrypted-plugin-marker-compat" { } (
    (import ../../lib/render-text.nix) ./scripts/scrypted-check-plugin-markers.sh {
      inherit scripts;
      cfg_package = cfg.package;
      inherit serverRoot;
    }
  );
  pluginType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.strMatching "@scrypted/[a-z0-9-]+";
        description = "Scrypted npm plugin name.";
      };
      version = lib.mkOption {
        type = lib.types.strMatching "[0-9]+\\.[0-9]+\\.[0-9]+";
        description = "Pinned plugin version.";
      };
      source = lib.mkOption {
        type = lib.types.enum [
          "npm"
          "local"
        ];
        description = "Install from npm or a local Nix package artifact.";
      };
      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Nix store path to a packaged Scrypted plugin for local sources.";
      };
    };
  };
  manifest = pkgs.writeText "scrypted-managed-plugins.json" (
    builtins.toJSON (
      map (
        plugin:
        {
          inherit (plugin) name version source;
        }
        // lib.optionalAttrs (plugin.path != null) { inherit (plugin) path; }
      ) cfg.plugins
    )
  );
in
{
  options.services.scrypted = {
    enable = lib.mkEnableOption "managed Scrypted video integration";
    package = lib.mkOption {
      type = lib.types.package;
      description = "Scrypted server package selected by the consuming host.";
    };
    nodePackage = lib.mkOption {
      type = lib.types.package;
      description = "Node.js runtime matching the selected Scrypted package.";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      description = "Host-owned IPv4 address used by Scrypted and HomeKit advertisement.";
    };
    uiUsernameFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime credential file for the Scrypted administrator username.";
    };
    uiPasswordFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime credential file for the Scrypted administrator password.";
    };
    plugins = lib.mkOption {
      type = lib.types.listOf pluginType;
      default = [ ];
      description = "Pinned plugins installed or updated through Scrypted's authenticated API. Removing a declaration does not uninstall a plugin or delete its devices; retire it in the UI after reviewing its state.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = runtimeFile cfg.uiUsernameFile && runtimeFile cfg.uiPasswordFile;
        message = "Scrypted UI credentials must be absolute runtime files outside the Nix store.";
      }
      {
        assertion = builtins.match "[0-9]{1,3}(\\.[0-9]{1,3}){3}" cfg.listenAddress != null;
        message = "Scrypted requires a literal IPv4 listener address.";
      }
      {
        assertion =
          lib.length cfg.plugins == lib.length (lib.unique (map (plugin: plugin.name) cfg.plugins));
        message = "Scrypted plugin names must be unique.";
      }
      {
        assertion = lib.all (
          plugin:
          if plugin.source == "local" then
            plugin.path != null && lib.hasPrefix "/nix/store/" plugin.path
          else
            plugin.path == null
        ) cfg.plugins;
        message = "Local Scrypted plugins need Nix store artifacts; npm plugins cannot declare a local path.";
      }
      {
        assertion = config.services.avahi.enable;
        message = "Scrypted's HomeKit advertiser requires services.avahi.enable.";
      }
    ];

    users.groups.scrypted = { };
    users.users.scrypted = {
      isSystemUser = true;
      group = "scrypted";
      home = stateDir;
    };

    systemd.services.scrypted = {
      description = "Scrypted home video integration server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "avahi-daemon.service"
      ];
      requires = [ "avahi-daemon.service" ];
      path = [
        cfg.nodePackage
        pkgs.python3
        pkgs.ffmpeg-headless
      ];
      environment = {
        # Python plugin wheels (including Arlo's curl_cffi) dynamically load
        # the C++ runtime by soname instead of a Nix store path.
        LD_LIBRARY_PATH = lib.mkDefault (lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]);
        SCRYPTED_VOLUME = stateDir;
        SCRYPTED_PYTHON_PATH = lib.getExe pkgs.python3;
        SCRYPTED_PYTHON312_PATH = lib.getExe' python312 "python3.12";
        SCRYPTED_FFMPEG_PATH = lib.getExe' pkgs.ffmpeg-headless "ffmpeg";
        SCRYPTED_SERVER_LISTEN_HOSTNAMES = cfg.listenAddress;
      };
      preStart = (import ../../lib/render-text.nix) ./scripts/scrypted-initialize-settings.sh {
        inherit authCheck;
        inherit settingsCheck;
        lib_optionalString_cfg_plugins_test_e_markerCheck = lib.optionalString (
          cfg.plugins != [ ]
        ) "test -e ${markerCheck}";
        lib_getExe_cfg_nodePackage_node = lib.getExe' cfg.nodePackage "node";
        inherit scripts;
        inherit serverRoot;
        inherit stateDir;
        lib_escapeShellArg_cfg_listenAddress = lib.escapeShellArg cfg.listenAddress;
        lib_optionalString_cfg_plugins_lib_getExe_cfg_nodePackage_no =
          lib.optionalString (cfg.plugins != [ ])
            ''
              ${lib.getExe' cfg.nodePackage "node"} ${scripts}/scrypted-plugin-marker.cjs \
                ${serverRoot} ${stateDir} ${manifest}
            '';
      };
      serviceConfig = {
        Type = "simple";
        User = "scrypted";
        Group = "scrypted";
        StateDirectory = "scrypted";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;
        ExecStart = "${cfg.package}/bin/scrypted-serve";
        LoadCredential = [
          "ui-username:${cfg.uiUsernameFile}"
          "ui-password:${cfg.uiPasswordFile}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
        TasksMax = 256;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        CapabilityBoundingSet = "";
      };
    };

    systemd.services.scrypted-plugins = lib.mkIf (cfg.plugins != [ ]) {
      description = "Install pinned Scrypted plugins";
      wantedBy = [ "scrypted.service" ];
      partOf = [ "scrypted.service" ];
      after = [ "scrypted.service" ];
      requires = [ "scrypted.service" ];
      script = (import ../../lib/render-text.nix) ./scripts/scrypted-install-plugins.sh {
        lib_getExe_cfg_nodePackage_node = lib.getExe' cfg.nodePackage "node";
        inherit scripts;
        inherit manifest;
        inherit stateDir;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "scrypted";
        Group = "scrypted";
        StateDirectory = "scrypted";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;
        LoadCredential = [
          "ui-username:${cfg.uiUsernameFile}"
          "ui-password:${cfg.uiPasswordFile}"
        ];
        Restart = "on-failure";
        RestartSec = 30;
        TimeoutStartSec = "25min";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        CapabilityBoundingSet = "";
      };
    };
  };
}
