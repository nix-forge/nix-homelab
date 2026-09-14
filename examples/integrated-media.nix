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
  mediaPolicy =
    name:
    {
      recycleBin = "${config.homelab.storage.libraryDir}/.recycle/${name}";
      recycleBinCleanupDays = 30;
      downloadPropersAndRepacks = "doNotPrefer";
      deleteEmptyFolders = true;
      fileDate = "none";
      rescanAfterRefresh = "afterManual";
      setPermissionsLinux = false;
      skipFreeSpaceCheckWhenImporting = false;
      minimumFreeSpaceWhenImporting = 20480;
      copyUsingHardlinks = true;
      useScriptImport = false;
      importExtraFiles = false;
      enableMediaInfo = true;
    }
    // {
      sonarr = {
        autoUnmonitorPreviouslyDownloadedEpisodes = false;
        createEmptySeriesFolders = false;
        episodeTitleRequired = "bulkSeasonReleases";
      };
      radarr = {
        autoUnmonitorPreviouslyDownloadedMovies = false;
        createEmptyMovieFolders = false;
      };
      lidarr = {
        autoUnmonitorPreviouslyDownloadedTracks = false;
        createEmptyArtistFolders = false;
        watchLibraryForChanges = true;
        allowFingerprinting = "newFiles";
      };
    }
    .${name};
  namingPolicy = {
    sonarr = {
      renameEpisodes = true;
      replaceIllegalCharacters = true;
      standardEpisodeFormat = "{Series CleanTitleWithoutYear} {(Series Year)} - S{season:00}E{episode:00} - {Episode CleanTitle:90} {[Custom Formats]}{[Quality Full]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}";
      dailyEpisodeFormat = "{Series CleanTitleWithoutYear} {(Series Year)} - {Air-Date} - {Episode CleanTitle:90} {[Custom Formats]}{[Quality Full]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}";
      animeEpisodeFormat = "{Series CleanTitleWithoutYear} {(Series Year)} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle:90} {[Custom Formats]}{[Quality Full]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}";
      seriesFolderFormat = "{Series CleanTitleWithoutYear} {(Series Year)}";
      seasonFolderFormat = "Season {season:00}";
      specialsFolderFormat = "Specials";
    };
    radarr = {
      renameMovies = true;
      replaceIllegalCharacters = true;
      standardMovieFormat = "{Movie CleanTitle} {(Release Year)} {edition-{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}";
      movieFolderFormat = "{Movie CleanTitle} ({Release Year})";
    };
    lidarr = {
      renameTracks = true;
      replaceIllegalCharacters = true;
      standardTrackFormat = "{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}";
      multiDiscTrackFormat = "{Album Title} ({Release Year})/{Medium Format} {medium:00}/{Artist Name} - {Album Title} - {track:00} - {Track Title}";
      artistFolderFormat = "{Artist Name}";
    };
  };
  clientDeclarations = {
    qbittorrent = {
      type = "qbittorrent";
      name = "qBittorrent";
      host = qbit.bindAddress;
      port = qbit.webuiPort;
      usernameFile = secret "qbittorrent-username";
      passwordFile = secret "qbittorrent-password";
      manageCategories = true;
    };
  }
  // lib.optionalAttrs config.homelab.apps.sabnzbd.enable {
    sabnzbd = {
      type = "sabnzbd";
      name = "SABnzbd";
      host =
        if config.homelab.apps.sabnzbd.vpn.enable then
          config.homelab.vpn.namespace.bindAddress
        else
          "127.0.0.1";
      port = config.homelab.apps.sabnzbd.port;
      apiKeyFile = secret "sabnzbd-api-key";
      after = [ "sabnzbd.service" ];
    };
  }
  // lib.optionalAttrs config.homelab.apps.nzbget.enable {
    nzbget = {
      type = "nzbget";
      name = "NZBGet";
      host = config.homelab.apps.nzbget.bindAddress;
      port = config.homelab.apps.nzbget.controlPort;
      usernameFile = secret "nzbget-username";
      passwordFile = secret "nzbget-password";
      after = [ "nzbget.service" ];
    };
  };
  clientReferences =
    category:
    {
      qbittorrent = { inherit category; };
    }
    // lib.optionalAttrs config.homelab.apps.sabnzbd.enable { sabnzbd = { inherit category; }; }
    // lib.optionalAttrs config.homelab.apps.nzbget.enable { nzbget = { inherit category; }; };
  manager = name: folder: {
    kind = name;
    url = arrUrl name;
    apiKeyFile = api name;
    installApiKey = true;
    mode = "managed";
    settings = {
      mediaManagement = mediaPolicy name;
      naming = namingPolicy.${name};
      downloadHandling = {
        enableCompletedDownloadHandling = true;
        autoRedownloadFailed = false;
        autoRedownloadFailedFromInteractiveSearch = false;
      };
    };
    rootFolders.main.path = "${config.homelab.storage.libraryDir}/${folder}";
    downloadClients = clientReferences name;
  };
in
{
  homelab = {
    profiles.media.enable = true;
    profiles.desktop.enable = true;
    apps.lidarr.enable = true;
    apps.qbittorrent = {
      credentialsFile = secret "qbittorrent-webui-ini";
      apiKeyFile = secret "qbittorrent-api-key";
    };
    optional.quality = {
      enable = true;
      sonarrApiKeyFile = api "sonarr";
      radarrApiKeyFile = api "radarr";
    };
    integrations = {
      downloadClients = clientDeclarations;
      servarr = {
        sonarr = manager "sonarr" "tv";
        radarr = manager "radarr" "movies";
        lidarr = lib.recursiveUpdate (manager "lidarr" "music") {
          rootFolders.main.extraSettings = {
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
        };
      };
      prowlarr = {
        url = arrUrl "prowlarr";
        apiKeyFile = api "prowlarr";
        installApiKey = true;
        mode = "managed";
        applications = {
          sonarr = { };
          radarr = { };
          lidarr = { };
        };
        proxies = lib.optionalAttrs config.homelab.indexerProxy.enable {
          vpn = {
            type = "socks5";
            tags = [ "vpn" ];
            host = config.homelab.vpn.namespace.bindAddress;
            port = config.homelab.indexerProxy.port;
            username = config.homelab.indexerProxy.username;
            passwordFile = config.homelab.indexerProxy.passwordFile;
          };
        };
        # Provider indexers remain opt-in because accounts, categories and
        # credentials are deployment inputs. Use `secretFields` for credentials.
      };
      jellyfin = {
        url = "http://127.0.0.1:8096";
        apiKeyFile = api "jellyfin";
        mode = "managed";
        administrator.passwordFile = secret "jellyfin-admin-password";
        encoding = {
          threadCount = 2;
          enableThrottling = true;
          enableSegmentDeletion = true;
          segmentKeepSeconds = 180;
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
          passwordFile = secret "jellyfin-viewer-password";
          # This broad grant is explicit. The reusable default grants no library.
          enableAllFolders = true;
        };
      };
      seerr = {
        url = "http://127.0.0.1:${toString config.services.seerr.port}";
        mode = "managed";
        after = [ "recyclarr.service" ];
        jellyfin = {
          email = "admin@example.invalid";
          libraries = [
            "Movies"
            "Television"
          ];
        };
        destinations = {
          movies = {
            manager = "radarr";
            rootFolder = "main";
            qualityProfile = "Homelab 1080p";
            isDefault = true;
          };
          television = {
            manager = "sonarr";
            rootFolder = "main";
            qualityProfile = "Homelab 1080p";
            isDefault = true;
          };
        };
        defaultPermissions = [ "request" ];
        quotas = {
          movie = {
            limit = 5;
            days = 7;
          };
          tv = {
            limit = 2;
            days = 7;
          };
        };
      };
    };
    integration = {
      enable = true;
      services = {
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
