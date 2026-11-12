{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.homebridge.managedUi;
  scripts = pkgs.homelab-iot-scripts;
  storage = config.services.homebridge.userStoragePath;
  runtimeFile = path: path != null && lib.hasPrefix "/" path && !lib.hasPrefix "/nix/store/" path;
  vesyncEnabled = cfg.vesync.usernameFile != null || cfg.vesync.passwordFile != null;
  uiAuthCompatibility = import ./checks/homebridge-ui-auth.nix {
    inherit pkgs;
    inherit (cfg) nodePackage;
  };
in
{
  options.services.homebridge.managedUi = {
    enable = lib.mkEnableOption "managed Homebridge pairing and private UI credentials";
    nodePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs;
      description = "Node.js runtime matching the selected Homebridge package.";
    };
    uiUsernameFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime credential file for the Homebridge UI username.";
    };
    uiPasswordFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime credential file for the Homebridge UI password.";
    };
    vesync = {
      usernameFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional VeSync username credential file.";
      };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional VeSync password credential file.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.homebridge.enable;
        message = "Managed Homebridge login requires services.homebridge.enable.";
      }
      {
        assertion = runtimeFile cfg.uiUsernameFile && runtimeFile cfg.uiPasswordFile;
        message = "Homebridge UI credentials must be absolute runtime files outside the Nix store.";
      }
      {
        assertion =
          !vesyncEnabled || (runtimeFile cfg.vesync.usernameFile && runtimeFile cfg.vesync.passwordFile);
        message = "Homebridge VeSync requires both runtime credential files outside the Nix store.";
      }
      {
        assertion =
          (config.services.homebridge.settings.bridge.advertiser or "ciao") != "avahi"
          || config.services.avahi.enable;
        message = "Homebridge's Avahi advertiser requires services.avahi.enable.";
      }
    ];

    services.homebridge = {
      uiSettings = {
        auth = "form";
        host = "127.0.0.1";
        sessionTimeout = 3600;
      };
    };

    systemd.services.homebridge = {
      requires = lib.optional (
        (config.services.homebridge.settings.bridge.advertiser or "ciao") == "avahi"
      ) "avahi-daemon.service";
      after = lib.optional (
        (config.services.homebridge.settings.bridge.advertiser or "ciao") == "avahi"
      ) "avahi-daemon.service";
      path = [ cfg.nodePackage ];
      environment.HOMEBRIDGE_CONFIG_UI_TERMINAL = lib.mkForce "0";
      serviceConfig = {
        MemoryAccounting = true;
        KillMode = lib.mkForce "control-group";
        StateDirectoryMode = "0700";
        UMask = "0077";
        LoadCredential = [
          "ui-username:${cfg.uiUsernameFile}"
          "ui-password:${cfg.uiPasswordFile}"
        ]
        ++ lib.optionals vesyncEnabled [
          "vesync-username:${cfg.vesync.usernameFile}"
          "vesync-password:${cfg.vesync.passwordFile}"
        ];
      };
      preStart = lib.mkBefore (
        (import ../../lib/render-text.nix) ./scripts/homebridge-initialize-auth.sh {
          inherit uiAuthCompatibility;
          inherit storage;
          lib_escapeShellArg_config_services_homebridge_user = lib.escapeShellArg config.services.homebridge.user;
          lib_escapeShellArg_config_services_homebridge_group = lib.escapeShellArg config.services.homebridge.group;
          lib_escapeShellArg_storage = lib.escapeShellArg storage;
          lib_getExe_cfg_nodePackage_node = lib.getExe' cfg.nodePackage "node";
          inherit scripts;
          lib_escapeShellArg_storage_config_json = lib.escapeShellArg "${storage}/config.json";
          lib_getExe_pkgs_python3 = lib.getExe pkgs.python3;
          scripts_homebridge_ui_auth_py = ./scripts/homebridge_ui_auth.py;
          lib_escapeShellArg_storage_auth_json = lib.escapeShellArg "${storage}/auth.json";
          lib_optionalString_vesyncEnabled_lib_getExe_pkgs_python3_scr = lib.optionalString vesyncEnabled ''
            ${lib.getExe pkgs.python3} ${./scripts/homebridge_vesync_config.py} \
              ${lib.escapeShellArg "${storage}/config.json"} \
              "$CREDENTIALS_DIRECTORY/vesync-username" \
              "$CREDENTIALS_DIRECTORY/vesync-password"
          '';
        }
      );
    };
  };
}
