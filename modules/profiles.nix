{ config, lib, ... }: {
  options.homelab.profiles = {
    media.enable = lib.mkEnableOption "Jellyfin, Seerr, Sonarr, Radarr, Bazarr, Prowlarr and confined qBittorrent";
    desktop.enable = lib.mkEnableOption "lower media background CPU and I/O priority on a shared desktop";
  };
  config = lib.mkMerge [
    (lib.mkIf config.homelab.profiles.media.enable {
      homelab.apps =
        lib.genAttrs
          [
            "jellyfin"
            "seerr"
            "sonarr"
            "radarr"
            "bazarr"
            "prowlarr"
            "qbittorrent"
          ]
          (_: {
            enable = lib.mkDefault true;
          });
    })
    (lib.mkIf config.homelab.profiles.desktop.enable {
      systemd.slices.homelab-background.sliceConfig = {
        CPUWeight = 25;
        IOWeight = 25;
      };
      systemd.services =
        lib.genAttrs
          (lib.filter (name: config.homelab.apps.${name}.enable) [
            "qbittorrent"
            "sabnzbd"
            "nzbget"
            "sonarr"
            "radarr"
            "lidarr"
            "bazarr"
          ])
          (_: {
            serviceConfig = {
              Slice = "homelab-background.slice";
              Nice = 10;
              IOSchedulingClass = "best-effort";
              IOSchedulingPriority = 7;
            };
          });
    })
  ];
}
