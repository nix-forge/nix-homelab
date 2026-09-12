{ config, lib, ... }:
let
  names = [
    "sonarr"
    "radarr"
    "lidarr"
    "bazarr"
    "prowlarr"
    "seerr"
    "qbittorrent"
    "sabnzbd"
    "nzbget"
    "jellyfin"
    "plex"
    "navidrome"
    "audiobookshelf"
  ];
  enabled = lib.filter (name: config.homelab.apps.${name}.enable) names;
in
{
  options.homelab.apps = lib.genAttrs names (name: {
    enable = lib.mkEnableOption "${name} with homelab defaults";
  });
  config = lib.mkIf (enabled != [ ]) {
    networking.firewall.enable = lib.mkDefault true;
    services = lib.genAttrs enabled (
      name:
      { enable = true; } // lib.optionalAttrs (name != "nzbget") { openFirewall = lib.mkDefault false; }
    );
    # Plex's FHS launcher needs its upstream sandbox choices.
    systemd.services = lib.genAttrs (lib.remove "plex" enabled) (_: {
      serviceConfig = {
        NoNewPrivileges = lib.mkDefault true;
        PrivateTmp = lib.mkDefault true;
        ProtectHome = lib.mkDefault true;
        ProtectSystem = lib.mkDefault "strict";
        ProtectKernelTunables = lib.mkDefault true;
        ProtectKernelModules = lib.mkDefault true;
        ProtectControlGroups = lib.mkDefault true;
        RestrictSUIDSGID = lib.mkDefault true;
      };
    });
  };
}
