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
      script = ''
        umask 077
        printf '%s' 0123456789abcdef0123456789abcdef > /run/arr-fixture-api
      '';
    };
  };
  testScript = ''
    import json
    import shlex
    for name in ("lidarr", "bazarr"):
        machine.wait_for_unit(name + ".service")
        machine.succeed("systemctl start homelab-integrate-" + name)
    roots = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:8686/api/v1/rootfolder"))
    assert len(roots) == 1 and roots[0]["name"] == "Music", roots
    assert roots[0]["defaultQualityProfileId"] > 0, roots
    profiles = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/languages/profiles"))
    assert len(profiles) == 1 and profiles[0]["name"] == "English", profiles
    settings = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/settings"))
    assert settings["general"]["serie_default_enabled"] and settings["general"]["movie_default_enabled"], settings["general"]
    assert int(settings["general"]["serie_default_profile"]) == profiles[0]["profileId"], settings["general"]
    languages = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/languages"))
    assert any(item["code2"] == "en" and item["enabled"] for item in languages), languages
    media_url = "http://127.0.0.1:8686/api/v1/config/mediamanagement"
    media_settings = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' " + media_url))
    assert media_settings["copyUsingHardlinks"], media_settings
    assert media_settings["minimumFreeSpaceWhenImporting"] == 20480, media_settings
    assert media_settings["rescanAfterRefresh"] == "afterManual", media_settings
    naming_url = "http://127.0.0.1:8686/api/v1/config/naming"
    naming = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' " + naming_url))
    assert naming["renameTracks"], naming
    assert "{track:00}" in naming["standardTrackFormat"], naming
    handling_url = "http://127.0.0.1:8686/api/v1/config/downloadclient"
    curl = "curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
    handling = json.loads(machine.succeed(curl + handling_url))
    assert handling["enableCompletedDownloadHandling"] and not handling["autoRedownloadFailed"], handling
    handling["enableCompletedDownloadHandling"] = False
    handling["downloadClientWorkingFolders"] = "_manual_fixture"
    machine.succeed(curl + "-X PUT -H 'Content-Type: application/json' --data " + shlex.quote(json.dumps(handling)) + " " + handling_url)
    machine.succeed("systemctl restart homelab-integrate-lidarr homelab-integrate-bazarr")
    machine.succeed("systemctl restart lidarr bazarr")
    machine.succeed("systemctl restart homelab-integrate-lidarr homelab-integrate-bazarr")
    repeated = json.loads(machine.succeed("curl -sf -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' http://127.0.0.1:6767/api/system/languages/profiles"))
    assert repeated == profiles, repeated
    handling = json.loads(machine.succeed(curl + handling_url))
    assert handling["enableCompletedDownloadHandling"] and not handling["autoRedownloadFailed"], handling
    assert handling["downloadClientWorkingFolders"] == "_manual_fixture", handling
  '';
}
