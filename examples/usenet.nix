# Optional alternatives. Enable the chosen downloader in the consuming host.
{ config, lib, ... }:
let
  secret = name: "/run/nix-seal/system/secrets/${name}";
  categoryNames = [
    "sonarr"
    "radarr"
    "lidarr"
  ];
  downloads = config.homelab.storage.downloadsDir;
in
{
  config = lib.mkMerge [
    (lib.mkIf config.homelab.apps.sabnzbd.enable {
      systemd.services.sabnzbd.serviceConfig.LoadCredential = [
        "homelab-settings:${secret "sabnzbd.ini"}"
      ];
      services.sabnzbd = {
        secretFiles = [ "/run/credentials/sabnzbd.service/homelab-settings" ];
        settings = {
          misc = {
            pause_on_post_processing = true;
            direct_unpack = false;
            cache_limit = "128M";
          };
          categories = lib.genAttrs categoryNames (name: {
            inherit name;
            dir = name;
            priority = 0;
            pp = 3;
            script = "None";
          });
          # Supply servers.provider.host/name/displayname and provider credentials
          # in the runtime INI. These public settings retain verified TLS.
          servers.provider = {
            name = "Provider";
            displayname = "Provider";
            host = "news.example.invalid";
            enable = false;
            ssl = true;
            ssl_verify = "strict";
            port = 563;
            connections = 4;
          };
        };
      };
    })
    (lib.mkIf config.homelab.apps.nzbget.enable {
      homelab.apps.nzbget.credentialsFile = secret "nzbget-credentials.conf";
      services.nzbget.settings = {
        "Server1.Active" = false;
        "Server1.Host" = "news.example.invalid";
        "Server1.Port" = 563;
        "Server1.Encryption" = true;
        "Server1.CertVerification" = "Strict";
        "Server1.Connections" = 4;
        ArticleCache = 128;
        ParThreads = 2;
        PostStrategy = "sequential";
        DirectUnpack = false;
        DiskSpace = 20480;
        KeepHistory = 30;
      }
      // lib.listToAttrs (
        lib.imap1 (number: name: {
          name = "Category${toString number}.Name";
          value = name;
        }) categoryNames
      )
      // lib.listToAttrs (
        lib.imap1 (number: name: {
          name = "Category${toString number}.DestDir";
          value = "${downloads}/usenet/${name}";
        }) categoryNames
      );
    })
  ];
}
