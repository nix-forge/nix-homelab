{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.homelab.storage;
  pathType = lib.types.strMatching "/[A-Za-z0-9_./-]+";
  enabled = names: lib.filter (name: config.homelab.apps.${name}.enable) names;
  downloaders = enabled [
    "qbittorrent"
    "sabnzbd"
    "nzbget"
  ];
  managers = enabled [
    "sonarr"
    "radarr"
    "lidarr"
  ];
  subtitleWriters = enabled [ "bazarr" ];
  readers = enabled [
    "jellyfin"
    "plex"
    "navidrome"
    "audiobookshelf"
  ];
  consumers = downloaders ++ managers ++ subtitleWriters ++ readers;
  directories = [
    cfg.rootDir
    cfg.downloadsDir
    cfg.libraryDir
  ]
  ++ map (name: "${cfg.downloadsDir}/${name}") [
    "torrents"
    "usenet"
    "incomplete"
  ]
  ++ map (name: "${cfg.libraryDir}/${name}") [
    "movies"
    "tv"
    "music"
    "books"
    "audiobooks"
  ]
  ++ map (name: "${cfg.libraryDir}/.recycle/${name}") [
    "sonarr"
    "radarr"
    "lidarr"
  ];
in
{
  options.homelab.storage = {
    enable = lib.mkEnableOption "shared media storage";
    rootDir = lib.mkOption {
      type = pathType;
      default = "/srv/media";
      description = "Media root on one filesystem. State databases remain on the system disk.";
    };
    downloadsDir = lib.mkOption {
      type = pathType;
      default = "${cfg.rootDir}/downloads";
      defaultText = lib.literalExpression ''"''${config.homelab.storage.rootDir}/downloads"'';
      description = "Downloads root, on the same filesystem as the library for hardlinks.";
    };
    libraryDir = lib.mkOption {
      type = pathType;
      default = "${cfg.rootDir}/library";
      defaultText = lib.literalExpression ''"''${config.homelab.storage.rootDir}/library"'';
      description = "Library root. Avoid separate mounts for downloads and libraries.";
    };
    group = lib.mkOption {
      type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
      default = "media";
      description = "Supplementary group shared by media services; state keeps each service's own group.";
    };
    requiredMounts = lib.mkOption {
      type = lib.types.listOf pathType;
      default = [ ];
      example = [ "/mnt/homelab" ];
      description = "Actual media mount points. Start fails when absent, preventing fallback writes onto the root disk.";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf (consumers != [ ]) {
      homelab.storage.enable = lib.mkDefault true;
      assertions = [
        {
          assertion = cfg.enable;
          message = "Enabled media applications require homelab.storage.enable.";
        }
      ];
    })
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = lib.all (
            path:
            path != "/"
            && !(lib.hasPrefix "/nix/store" path)
            && !(lib.hasInfix "/../" "${path}/")
            && !(lib.hasInfix "/./" "${path}/")
            && !(lib.hasInfix "//" path)
          ) directories;
          message = "Media directories must be dedicated absolute paths outside /nix/store without parent traversal.";
        }
        {
          assertion =
            lib.all (path: lib.hasPrefix "${cfg.rootDir}/" path) [
              cfg.downloadsDir
              cfg.libraryDir
            ]
            && cfg.downloadsDir != cfg.libraryDir
            && !(lib.hasPrefix "${cfg.downloadsDir}/" cfg.libraryDir)
            && !(lib.hasPrefix "${cfg.libraryDir}/" cfg.downloadsDir);
          message = "Downloads and libraries must be separate descendants of a dedicated media root.";
        }
      ];
      users.groups.${cfg.group} = { };
      # Global tmpfiles can create fallback directories before an external mount.
      systemd.services = {
        homelab-storage = {
          description = "Prepare shared media directories on the required mounts";
          wantedBy = [ "multi-user.target" ];
          before = map (name: "${name}.service") consumers;
          unitConfig.RequiresMountsFor = cfg.requiredMounts ++ [ cfg.rootDir ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0007";
          };
          script =
            lib.concatMapStringsSep "\n" (
              path: "${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg path}"
            ) cfg.requiredMounts
            + "\n"
            + "${pkgs.python3}/bin/python3 ${../../scripts/storage/prepare.py} ${lib.escapeShellArg cfg.group} ${lib.escapeShellArgs directories}";
        };
      }
      // lib.genAttrs consumers (name: {
        after = [ "homelab-storage.service" ];
        requires = [ "homelab-storage.service" ];
        unitConfig.RequiresMountsFor = cfg.requiredMounts ++ [
          cfg.downloadsDir
          cfg.libraryDir
        ];
        serviceConfig = {
          SupplementaryGroups = [ cfg.group ];
          # Only media writers need group-write creation permissions. Players
          # retain media read access through the supplementary group.
          UMask = lib.mkForce (if builtins.elem name readers then "0077" else "0007");
        }
        // lib.optionalAttrs (builtins.elem name downloaders) {
          ReadWritePaths = [ cfg.downloadsDir ];
          BindReadOnlyPaths = [ cfg.libraryDir ];
        }
        // lib.optionalAttrs (builtins.elem name managers) {
          # Separate writable bind mounts cause EXDEV even on the same disk.
          ReadWritePaths = [ cfg.rootDir ];
        }
        // lib.optionalAttrs (builtins.elem name subtitleWriters) {
          ReadWritePaths = [ cfg.libraryDir ];
          BindReadOnlyPaths = [ cfg.downloadsDir ];
        }
        // lib.optionalAttrs (builtins.elem name readers) { BindReadOnlyPaths = [ cfg.libraryDir ]; };
      });
    })
  ];
}
