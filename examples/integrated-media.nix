# Import alongside your mount, VPN and nix-seal configuration. All paths below
# are user-provided runtime secrets; this file contains no encrypted payloads.
{ config, lib, ... }:
let
  secret = name: "/run/nix-seal/system/secrets/${name}";
  api = name: secret "${name}-api-key";
  reference = path: { _secret = path; };
  qbit = config.homelab.apps.qbittorrent;
  arrPort = name: config.services.${name}.settings.server.port;
  arrBase =
    name:
    let
      raw = config.services.${name}.settings.server.urlbase or "";
    in
    if raw == "" || raw == "/" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" raw)}";
  arrUrl = name: "http://127.0.0.1:${toString (arrPort name)}${arrBase name}";
  downloader = category: {
    endpoint = "downloadclient";
    match.name = "qBittorrent";
    values = {
      enable = true;
      removeCompletedDownloads = false;
      removeFailedDownloads = false;
      implementation = "QBittorrent";
      fields = {
        host = qbit.bindAddress;
        port = qbit.webuiPort;
        username = reference (secret "qbittorrent-username");
        password = reference (secret "qbittorrent-password");
        ${
          if category == "sonarr" then
            "tvCategory"
          else if category == "radarr" then
            "movieCategory"
          else
            "musicCategory"
        } =
          category;
      };
    };
  };
  manager = name: folder: {
    kind = name;
    url = arrUrl name;
    apiKeyFile = api name;
    installApiKey = true;
    mode = "managed";
    settings.mediaManagement.copyUsingHardlinks = true;
    settings.downloadHandling = {
      enableCompletedDownloadHandling = true;
      autoRedownloadFailed = false;
      autoRedownloadFailedFromInteractiveSearch = false;
    };
    resources = [
      {
        endpoint = "rootfolder";
        match.path = "${config.homelab.storage.libraryDir}/${folder}";
        values = { };
      }
      (downloader name)
    ];
  };
  prowlarrApp = name: implementation: categories: {
    endpoint = "applications";
    match.name = name;
    values = {
      inherit implementation;
      syncLevel = "fullSync";
      fields = {
        prowlarrUrl = arrUrl "prowlarr";
        baseUrl = arrUrl name;
        apiKey = reference (api name);
        syncCategories = categories;
      };
    };
  };
  destination = name: directory: {
    inherit name;
    port = arrPort name;
    hostname = "127.0.0.1";
    apiKey = reference (api name);
    useSsl = false;
    baseUrl = arrBase name;
    activeProfileName = "Homelab 1080p";
    activeDirectory = "${config.homelab.storage.libraryDir}/${directory}";
    isDefault = true;
    is4k = false;
    externalUrl = "";
    syncEnabled = true;
    preventSearch = false;
  };
in
{
  homelab = {
    profiles.media.enable = true;
    profiles.desktop.enable = true;
    apps.lidarr.enable = true;
    apps.qbittorrent.credentialsFile = secret "qbittorrent-webui-ini";
    optional.quality = {
      enable = true;
      sonarrApiKeyFile = api "sonarr";
      radarrApiKeyFile = api "radarr";
    };
    integration = {
      enable = true;
      services = {
        sonarr = manager "sonarr" "tv";
        radarr = manager "radarr" "movies";
        lidarr = (manager "lidarr" "music") // {
          resources = [
            {
              endpoint = "rootfolder";
              match.path = "${config.homelab.storage.libraryDir}/music";
              values = {
                name = "Music";
                defaultMetadataProfileId._lookup = {
                  endpoint = "metadataprofile";
                  name = "Standard";
                };
                defaultQualityProfileId._lookup = {
                  endpoint = "qualityprofile";
                  name = "Standard";
                };
                defaultMonitorOption = "future";
                defaultNewItemMonitorOption = "none";
                defaultTags = [ ];
              };
            }
            (downloader "lidarr")
          ];
        };
        prowlarr = {
          url = arrUrl "prowlarr";
          apiKeyFile = api "prowlarr";
          installApiKey = true;
          mode = "managed";
          after = [
            "homelab-integrate-sonarr.service"
            "homelab-integrate-radarr.service"
            "homelab-integrate-lidarr.service"
          ];
          resources = [
            (prowlarrApp "sonarr" "Sonarr" [ 5000 ])
            (prowlarrApp "radarr" "Radarr" [ 2000 ])
            (prowlarrApp "lidarr" "Lidarr" [ 3000 ])
          ];
          # Append provider-specific indexer resources here. Indexer selection and
          # accounts are operator inputs, validated against Prowlarr's schemas.
        };
        jellyfin = {
          url = "http://127.0.0.1:8096";
          mode = "managed";
          settings = {
            encoding = {
              EncodingThreadCount = 2;
              EnableThrottling = true;
              EnableSegmentDeletion = true;
              SegmentKeepSeconds = 180;
            };
            login = {
              username = "admin";
              password = reference (secret "jellyfin-admin-password");
            };
            libraries = {
              Movies = {
                collectionType = "movies";
                paths = [ "${config.homelab.storage.libraryDir}/movies" ];
              };
              Television = {
                collectionType = "tvshows";
                paths = [ "${config.homelab.storage.libraryDir}/tv" ];
              };
            };
            users.viewer = {
              password = reference (secret "jellyfin-viewer-password");
              policy = {
                IsAdministrator = false;
                IsHidden = true;
                EnableContentDeletion = false;
                EnableContentDownloading = false;
                EnableRemoteAccess = false;
                EnableAllFolders = true;
              };
            };
          };
        };
        seerr = {
          url = "http://127.0.0.1:${toString config.services.seerr.port}";
          mode = "managed";
          after = [
            "homelab-integrate-jellyfin.service"
            "homelab-integrate-radarr.service"
            "homelab-integrate-sonarr.service"
            "recyclarr.service"
          ];
          settings = {
            login = {
              username = "admin";
              password = reference (secret "jellyfin-admin-password");
              hostname = "127.0.0.1";
              port = 8096;
              useSsl = false;
              urlBase = "";
              email = "admin@example.invalid";
              serverType = 2;
            };
            libraries = [
              "Movies"
              "Television"
            ];
            radarr.movies = (destination "radarr" "movies") // {
              minimumAvailability = "released";
            };
            sonarr.television = (destination "sonarr" "tv") // {
              enableSeasonFolders = true;
            };
            main = {
              defaultPermissions = 32;
              # Request permission without automatic approval. Each household can
              # choose its own request limits using the native Seerr settings API.
              defaultQuotas = {
                movie = {
                  quotaLimit = 5;
                  quotaDays = 7;
                };
                tv = {
                  quotaLimit = 2;
                  quotaDays = 7;
                };
              };
            };
          };
        };
        bazarr = {
          url = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
          apiKeyFile = api "bazarr";
          installApiKey = true;
          mode = "managed";
          settings = {
            enabledLanguages = [ "en" ];
            defaultProfiles = {
              series = "English";
              movies = "English";
            };
            languageProfiles.English = {
              cutoff = 1;
              items = [
                {
                  id = 1;
                  language = "en";
                  hi = "False";
                  forced = "False";
                  audio_exclude = "False";
                }
              ];
            };
            general = {
              use_sonarr = true;
              use_radarr = true;
              concurrent_jobs = 1;
              multithreading = false;
              wanted_search_frequency = 24;
              wanted_search_frequency_movie = 24;
              upgrade_frequency = 168;
              upgrade_manual = false;
              use_postprocessing = false;
              disable_all_providers_ssl_verify = false;
            };
            sonarr = {
              ip = "127.0.0.1";
              port = arrPort "sonarr";
              base_url = arrBase "sonarr";
              apikey = reference (api "sonarr");
              only_monitored = true;
              series_sync = 60;
              episodes_sync = 60;
            };
            radarr = {
              ip = "127.0.0.1";
              port = arrPort "radarr";
              base_url = arrBase "radarr";
              apikey = reference (api "radarr");
              only_monitored = true;
              movies_sync = 60;
            };
          };
        };
      };
    };
  };
  # Keep each secret activation dependency in nix-conf, where nix-seal is imported.
  # Set its restartUnits for the affected homelab-key, application and integration
  # units. Start API integration only after those user-supplied files exist.
  systemd.services.recyclarr = {
    after = [
      "homelab-integrate-sonarr.service"
      "homelab-integrate-radarr.service"
    ];
    requires = [
      "homelab-integrate-sonarr.service"
      "homelab-integrate-radarr.service"
    ];
  };
}
