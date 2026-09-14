# Evaluation-only host choices for the complete configuration check. These are
# public fixtures, not credentials or hardware identifiers for deployment.
{
  homelab.storage.requiredMounts = [ "/mnt/homelab" ];

  homelab.readiness.hostManaged = [
    "autobrr"
    "cross-seed"
    "unpackerr"
    "flaresolverr"
    "komga"
    "kavita"
    "shelfmark"
    "pinchflat"
    "maintainerr"
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
    "immich"
    "paperless"
    "syncthing"
    "adguardhome"
    "scrutiny"
  ];

  services = {
    paperless.exporter.enable = true;
    syncthing = {
      guiPasswordFile = "/run/nix-seal/system/secrets/syncthing-gui-password";
      settings = {
        devices.fixture.id = "AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH";
        folders.fixture = {
          path = "/var/lib/syncthing/fixture";
          devices = [ "fixture" ];
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "31536000";
            };
          };
        };
      };
    };
    adguardhome = {
      mutableSettings = false;
      settings = {
        dns = {
          bootstrap_dns = [ "9.9.9.9" ];
          upstream_dns = [ "https://dns.quad9.net/dns-query" ];
        };
        users = [
          {
            name = "fixture-admin";
            # Deliberately unusable bcrypt fixture; a consuming host must use
            # its own strong password hash and keep that source private.
            password = "$2y$10$00000000000000000000000000000000000000000000000000000";
          }
        ];
      };
    };
    scrutiny.collector = {
      enable = true;
      settings.allow_listed_devices = [ "/dev/disk/by-id/fixture-disk" ];
    };
  };
}
