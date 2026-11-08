{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.jellyfinIgnore;
  command = pkgs.writeShellApplication {
    name = "homelab-jellyfin-ignore";
    runtimeInputs = [ pkgs.python3 ];
    text = (import ../../../lib/render-text.nix) ./scripts/homelab-jellyfin-ignore.sh {
      scripts_media_jellyfin_ignore_py = ../../../scripts/media/jellyfin_ignore.py;
    };
  };
in
{
  options.homelab.optional.jellyfinIgnore = {
    enable = lib.mkEnableOption "owned Jellyfin .ignore markers for empty shows";
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Existing non-root account with write access to the selected media roots.";
    };
    mountPoint = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = null;
      description = "Required mounted filesystem containing the media roots.";
    };
    roots = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = [ ];
      description = "Show-library roots; the timer scans immediate subdirectories.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != null && cfg.user != "root";
        message = "jellyfinIgnore needs an existing non-root write-capable user.";
      }
      {
        assertion =
          cfg.mountPoint != null
          && lib.hasPrefix "/" cfg.mountPoint
          && cfg.roots != [ ]
          && lib.all (lib.hasPrefix "${cfg.mountPoint}/") cfg.roots;
        message = "jellyfinIgnore needs a mountPoint and show roots beneath it.";
      }
    ];
    systemd.services.homelab-jellyfin-ignore = {
      description = "Manage owned Jellyfin empty-show markers";
      unitConfig.RequiresMountsFor = [ cfg.mountPoint ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        StateDirectory = "homelab-jellyfin-ignore";
        StateDirectoryMode = "0700";
        ExecStart = "${lib.getExe command} --mount ${cfg.mountPoint} ${
          lib.concatMapStringsSep " " (root: "--root ${root}") cfg.roots
        } --ledger /var/lib/homelab-jellyfin-ignore/ledger.json";
        AmbientCapabilities = "";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadWritePaths = cfg.roots ++ [ "/var/lib/homelab-jellyfin-ignore" ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };
    systemd.timers.homelab-jellyfin-ignore = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "30m";
        Persistent = false;
      };
    };
  };
}
