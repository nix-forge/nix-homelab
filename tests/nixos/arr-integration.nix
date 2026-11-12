{ homelabModule }: {
  name = "homelab-arr-integration";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 2048;
    environment.systemPackages = [ pkgs.python3 ];
    homelab = {
      apps.lidarr.enable = true;
      apps.bazarr.enable = true;
      integration = {
        enable = true;
        services = {
          lidarr = {
            url = "http://127.0.0.1:8686";
            apiKeyFile = "/run/arr-fixture-api";
            installApiKey = true;
            mode = "managed";
            settings.mediaManagement = {
              copyUsingHardlinks = true;
              recycleBin = "/srv/media/library/.recycle/lidarr";
              recycleBinCleanupDays = 30;
              minimumFreeSpaceWhenImporting = 20480;
              rescanAfterRefresh = "afterManual";
              allowFingerprinting = "newFiles";
            };
            settings.naming = {
              renameTracks = true;
              replaceIllegalCharacters = true;
              standardTrackFormat = "{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}";
              multiDiscTrackFormat = "{Album Title} ({Release Year})/{Medium Format} {medium:00}/{Artist Name} - {Album Title} - {track:00} - {Track Title}";
              artistFolderFormat = "{Artist Name}";
            };
            settings.downloadHandling = {
              enableCompletedDownloadHandling = true;
              autoRedownloadFailed = false;
              autoRedownloadFailedFromInteractiveSearch = false;
            };
            after = [ "arr-fixture.service" ];
            resources = [
              {
                endpoint = "rootfolder";
                match.path = "/srv/media/library/music";
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
            ];
          };
          bazarr = {
            url = "http://127.0.0.1:6767";
            apiKeyFile = "/run/arr-fixture-api";
            installApiKey = true;
            mode = "managed";
            after = [ "arr-fixture.service" ];
            settings = {
              general = {
                use_sonarr = false;
                use_radarr = false;
                concurrent_jobs = 1;
                multithreading = false;
                wanted_search_frequency = 24;
                wanted_search_frequency_movie = 24;
                upgrade_frequency = 168;
                upgrade_manual = false;
                use_postprocessing = false;
                disable_all_providers_ssl_verify = false;
              };
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
            };
          };
        };
      };
    };
    systemd.services.arr-fixture = {
      before = [
        "bazarr.service"
        "homelab-key-lidarr.service"
      ];
      requiredBy = [
        "bazarr.service"
        "homelab-key-lidarr.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = builtins.readFile ./scripts/prepare-arr-api-key.sh;
    };
  };
  testScript = builtins.readFile ./scripts/arr_integration_test.py;
}
