{ evaluate, lib }:
let
  base = {
    homelab.integrations = {
      notifications.jellyfin = {
        type = "jellyfin";
        host = "127.0.0.1";
        port = 8096;
        apiKeyFile = "/run/secrets/jellyfin-api";
        tags = [ "media" ];
        after = [ "jellyfin.service" ];
      };
      downloadClients.torrents = {
        type = "qbittorrent";
        host = "127.0.0.1";
        port = 8081;
        usernameFile = "/run/secrets/qbit-user";
        passwordFile = "/run/secrets/qbit-password";
        manageCategories = true;
      };
      servarr = {
        television = {
          kind = "sonarr";
          url = "http://127.0.0.1:8989";
          apiKeyFile = "/run/secrets/sonarr-api";
          rootFolders.main.path = "/srv/media/library/tv";
          downloadClients.torrents.category = "sonarr";
          notifications = [ "jellyfin" ];
          tags = [ "video" ];
          settings = {
            downloadHandling.enableCompletedDownloadHandling = true;
            mediaManagement = {
              copyUsingHardlinks = true;
              minimumFreeSpaceWhenImporting = 20480;
            };
            naming = {
              renameEpisodes = true;
              standardEpisodeFormat = "{Series Title} - S{season:00}E{episode:00}";
            };
          };
        };
        anime = {
          kind = "sonarr";
          url = "https://anime.example.invalid";
          apiKeyFile = "/run/secrets/sonarr-anime-api";
          rootFolders.main.path = "/srv/media/library/anime";
          downloadClients.torrents.category = "sonarr-anime";
        };
      };
    };
    homelab.apps.qbittorrent = {
      enable = true;
      vpn.enable = false;
      apiKeyFile = "/run/secrets/qbittorrent-api-key";
    };
  };
  configured = (evaluate base).config;
  television = configured.homelab.integration.services.television;
  anime = configured.homelab.integration.services.anime;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate (lib.recursiveUpdate base extra)).config.assertions;
  downloader = builtins.elemAt television.resources 1;
  notification = lib.findFirst (
    resource: resource.endpoint == "notification"
  ) null television.resources;
in
{
  enablesSharedReconciler = configured.homelab.integration.enable;
  supportsMultipleInstancesOfOneKind =
    television.kind == "sonarr" && anime.kind == "sonarr" && television.url != anime.url;
  typedRootFolder =
    (builtins.head television.resources).endpoint == "rootfolder"
    && (builtins.head television.resources).match.path == "/srv/media/library/tv";
  typedDownloadClient =
    downloader.endpoint == "downloadclient"
    && downloader.match.name == "torrents"
    && downloader.values.implementation == "QBittorrent"
    && downloader.values.fields.tvCategory == "sonarr"
    && downloader.values.fields.username._secret == "/run/secrets/qbit-user"
    && downloader.values.fields.password._secret == "/run/secrets/qbit-password";
  typedSettings =
    television.settings.downloadHandling.enableCompletedDownloadHandling
    && television.settings.mediaManagement.copyUsingHardlinks
    && television.settings.mediaManagement.minimumFreeSpaceWhenImporting == 20480
    && television.settings.naming.renameEpisodes;
  typedNotification =
    notification.match.name == "jellyfin"
    && notification.values.implementation == "MediaBrowser"
    && notification.values.fields.host == "127.0.0.1"
    && notification.values.fields.apiKey._secret == "/run/secrets/jellyfin-api"
    && notification.values.onDownload
    && notification.values.onImportComplete
    && !notification.values.includeHealthWarnings;
  ordersAfterDependencies =
    television.after == [
      "jellyfin.service"
      "homelab-configure-qbittorrent.service"
    ];
  createsDownloaderCategoriesOnce =
    configured.homelab.apps.qbittorrent.configuration.categories.sonarr.savePath
    == "/srv/media/downloads/torrents/sonarr"
    &&
      configured.homelab.apps.qbittorrent.configuration.categories."sonarr-anime".savePath
      == "/srv/media/downloads/torrents/sonarr-anime";
  duplicateCategoryRejected = rejected {
    homelab.integrations.servarr.anime.downloadClients.torrents.category = "sonarr";
  };
  unknownClientRejected = rejected {
    homelab.integrations.servarr.anime.downloadClients = {
      missing = {
        client = "missing";
        category = "sonarr-anime";
      };
    };
  };
  missingClientCredentialRejected = rejected {
    homelab.integrations.downloadClients.torrents.passwordFile = null;
  };
  unknownNotificationRejected = rejected {
    homelab.integrations.servarr.television.notifications = [ "missing" ];
  };
  invalidNotificationCredentialRejected = rejected {
    homelab.integrations.notifications.jellyfin.apiKeyFile = "/nix/store/public-invalid";
  };
  storeSecretRejected = rejected {
    homelab.integrations.downloadClients.torrents.passwordFile = "/nix/store/public-invalid";
  };
  remoteCategoryManagementRejected = rejected {
    homelab.integrations.downloadClients.torrents.host = "download.example.invalid";
  };
}
