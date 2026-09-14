{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    (lib.mkIf config.homelab.apps.jellyfin.enable {
      services.jellyfin.transcoding = {
        # The native module currently exposes maxConcurrentStreams and
        # deleteSegments without serializing them into encoding.xml. The
        # integrated example enforces equivalent values through Jellyfin's API;
        # retaining them here makes the intended native policy explicit.
        maxConcurrentStreams = lib.mkDefault 2;
        threadCount = lib.mkDefault 2;
        throttleTranscoding = lib.mkDefault true;
        deleteSegments = lib.mkDefault true;
      };
    })
    (lib.mkIf config.homelab.apps.plex.enable {
      services.plex.accelerationDevices = lib.mkDefault [ ];
    })
    (lib.mkIf config.homelab.apps.navidrome.enable {
      services.navidrome.settings = {
        MusicFolder = "${config.homelab.storage.libraryDir}/music";
        EnableInsightsCollector = lib.mkDefault false;
        EnableSharing = lib.mkDefault false;
        EnforceNonRootUser = lib.mkDefault true;
        EnableTranscodingConfig = lib.mkDefault false;
        TranscodingCacheSize = lib.mkDefault "512MB";
        Scanner = {
          Schedule = lib.mkDefault "0 */6 * * *";
          WatcherWait = lib.mkDefault "30s";
          FollowSymlinks = lib.mkDefault false;
          PurgeMissing = lib.mkDefault "never";
        };
        Transcoding = {
          MaxConcurrent = lib.mkDefault 2;
          MaxConcurrentPerUser = lib.mkDefault 1;
          EnableCancellation = lib.mkDefault true;
        };
      };
      # Storage preparation owns this path after checking the real mount.
      systemd.tmpfiles.settings.navidromeDirs.${config.services.navidrome.settings.MusicFolder} =
        lib.mkForce
          { };
    })
    (lib.mkIf config.homelab.apps.audiobookshelf.enable {
      services.audiobookshelf.host = lib.mkDefault "127.0.0.1";
      systemd.services.homelab-storage.script = lib.mkAfter ''
        ${pkgs.python3}/bin/python3 ${../../scripts/storage/prepare.py} ${lib.escapeShellArg config.homelab.storage.group} ${lib.escapeShellArg "${config.homelab.storage.downloadsDir}/podcasts"}
      '';
      systemd.services.audiobookshelf.serviceConfig.ReadWritePaths = [
        "${config.homelab.storage.downloadsDir}/podcasts"
      ];
    })
  ];
}
