{ evaluate, lib }:
let
  configured =
    (evaluate {
      homelab.apps.qbittorrent = {
        enable = true;
        vpn.enable = false;
        credentialsFile = "/run/secrets/qbittorrent.ini";
        apiKeyFile = "/run/secrets/qbittorrent-api-key";
        configuration = {
          mode = "managed";
          categories = {
            sonarr = { };
            radarr.savePath = "/srv/media/downloads/torrents/movies";
          };
          tags = [
            "homelab"
            "automation"
          ];
        };
      };
    }).config;
  rejected =
    value:
    lib.any (assertion: !assertion.assertion)
      (evaluate { homelab.apps.qbittorrent = value; }).config.assertions;
  service = configured.systemd.services.homelab-configure-qbittorrent;
in
{
  categoryDefaultsBelowDownloadRoot =
    configured.homelab.apps.qbittorrent.configuration.categories.sonarr.savePath
    == "/srv/media/downloads/torrents/sonarr";
  explicitCategoryPathPreserved =
    configured.homelab.apps.qbittorrent.configuration.categories.radarr.savePath
    == "/srv/media/downloads/torrents/movies";
  runtimeCredential =
    service.serviceConfig.LoadCredential == [ "api-key:/run/secrets/qbittorrent-api-key" ];
  webUiCredential =
    configured.systemd.services.qbittorrent.serviceConfig.LoadCredential
    == [ "webui:/run/secrets/qbittorrent.ini" ];
  privateCredentialScratch =
    configured.systemd.services.qbittorrent.serviceConfig.RuntimeDirectory == "qbittorrent-credentials"
    && configured.systemd.services.qbittorrent.serviceConfig.RuntimeDirectoryMode == "0700";
  orderedAfterApplicationAndStorage =
    builtins.elem "qbittorrent.service" service.requires
    && builtins.elem "homelab-storage.service" service.requires;
  boundedAndPrivate =
    service.serviceConfig.DynamicUser
    && service.serviceConfig.NoNewPrivileges
    && service.serviceConfig.ProtectSystem == "strict"
    && service.serviceConfig.MemoryMax == "96M";
  timerUsesDeclaredInterval =
    configured.systemd.timers.homelab-configure-qbittorrent.timerConfig.OnUnitInactiveSec == "15min";
  missingApiKeyRejected = rejected {
    enable = true;
    vpn.enable = false;
    configuration.categories.sonarr = { };
  };
  storeApiKeyRejected = rejected {
    enable = true;
    vpn.enable = false;
    apiKeyFile = "/nix/store/public-invalid-key";
    configuration.tags = [ "homelab" ];
  };
  escapedCategoryPathRejected = rejected {
    enable = true;
    vpn.enable = false;
    apiKeyFile = "/run/secrets/qbittorrent-api-key";
    configuration.categories.sonarr.savePath = "/srv/media/downloads/torrents/../escape";
  };
  duplicateTagsRejected = rejected {
    enable = true;
    vpn.enable = false;
    apiKeyFile = "/run/secrets/qbittorrent-api-key";
    configuration.tags = [
      "homelab"
      "homelab"
    ];
  };
}
