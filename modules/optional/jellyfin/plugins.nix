{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.jellyfinPlugins;
  packages = lib.mapAttrs (_: toString) cfg.packages;
  manifest = pkgs.writeText "homelab-jellyfin-plugin-manifest.json" (builtins.toJSON packages);
  installer = pkgs.writers.writePython3Bin "homelab-install-jellyfin-plugins" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../../scripts/media/install_jellyfin_plugins.py);
  configureMoonbase = pkgs.writers.writePython3Bin "configure-moonbase" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../../scripts/media/configure_moonbase.py);
in
{
  options.homelab.optional.jellyfinPlugins = {
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = ''
        Pinned Jellyfin plugin package directories, keyed by their installation
        directory names. Only marked plugin directories are replaced. Removing a
        declaration leaves its installed directory for attended cleanup.
      '';
    };
    moonbase = {
      enable = lib.mkEnableOption "Moonbase's Seerr connection and web isolation";
      pluginName = lib.mkOption {
        type = lib.types.str;
        default = "Moonfin_nix";
        description = "Key of the installed Moonbase package in jellyfinPlugins.packages.";
      };
      seerrUrl = lib.mkOption {
        type = lib.types.str;
        description = "HTTP or HTTPS Seerr API URL written into Moonbase's existing configuration.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.packages != { }) {
      assertions = [
        {
          assertion = config.services.jellyfin.enable;
          message = "Jellyfin plugin packages require services.jellyfin.enable.";
        }
        {
          assertion = lib.all (name: builtins.match "[A-Za-z0-9][A-Za-z0-9 _.-]*" name != null) (
            builtins.attrNames cfg.packages
          );
          message = "Jellyfin plugin names must be single safe directory names.";
        }
      ];
      systemd.services.jellyfin = {
        preStart = lib.mkAfter (
          (import ../../../lib/render-text.nix) ./scripts/install-jellyfin-plugins.sh {
            lib_getExe_installer = lib.getExe installer;
            inherit manifest;
            lib_escapeShellArg_config_services_jellyfin_dataDir_plugins = lib.escapeShellArg "${config.services.jellyfin.dataDir}/plugins";
          }
        );
        restartTriggers = builtins.attrValues cfg.packages;
      };
    })
    (lib.mkIf cfg.moonbase.enable {
      assertions = [
        {
          assertion =
            config.services.jellyfin.enable && builtins.hasAttr cfg.moonbase.pluginName cfg.packages;
          message = "Moonbase configuration requires Jellyfin and its declared plugin package.";
        }
        {
          assertion =
            (lib.hasPrefix "http://" cfg.moonbase.seerrUrl || lib.hasPrefix "https://" cfg.moonbase.seerrUrl)
            && !lib.hasInfix "@" cfg.moonbase.seerrUrl
            && !lib.hasInfix "?" cfg.moonbase.seerrUrl
            && !lib.hasInfix "#" cfg.moonbase.seerrUrl
            && !lib.hasInfix "\n" cfg.moonbase.seerrUrl;
          message = "Moonbase Seerr URL must be HTTP(S) without embedded credentials or query parameters.";
        }
      ];
      systemd.services.jellyfin.preStart = lib.mkOrder 1600 (
        (import ../../../lib/render-text.nix) ./scripts/configure-moonbase.sh {
          lib_getExe_configureMoonbase = lib.getExe configureMoonbase;
          lib_escapeShellArg_config_services_jellyfin_dataDir_plugins_ = lib.escapeShellArg "${config.services.jellyfin.dataDir}/plugins/configurations/Moonfin.Server.xml";
          lib_escapeShellArg_cfg_moonbase_seerrUrl = lib.escapeShellArg cfg.moonbase.seerrUrl;
        }
      );
    })
  ];
}
