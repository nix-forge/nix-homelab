# Import this alongside nix-homelab, then opt in to individual optional apps.
# Every /run/nix-seal path is a user-provided runtime file, not a generated secret.
{ config, lib, ... }:
let
  apps = config.homelab.optional.apps;
  secret = name: "/run/nix-seal/system/secrets/${name}";
  arrUrl =
    name:
    let
      raw = config.services.${name}.settings.server.urlbase or "";
      base =
        if raw == "" || raw == "/" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" raw)}";
    in
    "http://127.0.0.1:${toString config.services.${name}.settings.server.port}${base}";
in
{
  config = lib.mkMerge [
    (lib.mkIf apps.maintainerr.enable {
      homelab.optional.maintainerr.htpasswdFile = secret "maintainerr-htpasswd";
    })
    (lib.mkIf apps.autobrr.enable {
      services.autobrr = {
        secretFile = secret "autobrr-session";
        settings = {
          port = 7474;
          logLevel = "INFO";
          checkForUpdates = false;
        };
      };
    })
    (lib.mkIf apps.cross-seed.enable {
      # JSON contains apiKey, torrentClients and Torznab URLs; see the guide.
      services.cross-seed.settingsFile = secret "cross-seed.json";
    })
    (lib.mkIf apps.unpackerr.enable {
      systemd.services.unpackerr.serviceConfig.LoadCredential = [
        "sonarr-api:${secret "sonarr-api-key"}"
        "radarr-api:${secret "radarr-api-key"}"
      ];
      services.unpackerr.settings = {
        sonarr = [
          {
            url = arrUrl "sonarr";
            api_key = "filepath:/run/credentials/unpackerr.service/sonarr-api";
            paths = [ config.homelab.storage.downloadsDir ];
            protocols = "torrent";
            delete_orig = false;
          }
        ];
        radarr = [
          {
            url = arrUrl "radarr";
            api_key = "filepath:/run/credentials/unpackerr.service/radarr-api";
            paths = [ config.homelab.storage.downloadsDir ];
            protocols = "torrent";
            delete_orig = false;
          }
        ];
      };
    })
    (lib.mkIf apps.kavita.enable { services.kavita.tokenKeyFile = secret "kavita-token"; })
    (lib.mkIf apps.shelfmark.enable {
      systemd.services.shelfmark.serviceConfig.EnvironmentFile = secret "shelfmark.env";
      services.shelfmark.environment = {
        AUTH_METHOD = "builtin";
        SEARCH_MODE = "universal";
        PROWLARR_URL = arrUrl "prowlarr";
        QBITTORRENT_URL = "http://${config.homelab.apps.qbittorrent.bindAddress}:${toString config.homelab.apps.qbittorrent.webuiPort}";
        QBITTORRENT_CATEGORY = "books";
        PROWLARR_TORRENT_CLIENT = "qbittorrent";
        MAX_CONCURRENT_DOWNLOADS = "1";
      };
    })
    (lib.mkIf apps.pinchflat.enable { services.pinchflat.secretsFile = secret "pinchflat.env"; })
    (lib.mkIf apps.immich.enable {
      services.immich.settings = {
        newVersionCheck.enabled = false;
        passwordLogin.enabled = true;
        machineLearning.enabled = true;
        ffmpeg.threads = 2;
      };
    })
    (lib.mkIf apps.paperless.enable {
      services.paperless = {
        passwordFile = secret "paperless-admin-password";
        environmentFile = secret "paperless.env";
        settings.PAPERLESS_ADMIN_USER = "admin";
      };
    })
    (lib.mkIf apps.syncthing.enable {
      # Configure peer IDs and folders explicitly in the host. Discovery is off.
      services.syncthing = {
        dataDir = "/var/lib/syncthing";
        settings.devices = { };
        settings.folders = { };
      };
    })
  ];
}
