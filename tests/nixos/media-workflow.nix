{ homelabModule }: {
  name = "homelab-media-workflow";
  nodes.machine =
    { pkgs, ... }:
    let
      fixture = pkgs.runCommand "public-media-workflow-fixture" {
        nativeBuildInputs = [
          pkgs.openssl
          pkgs.ffmpeg
        ];
      } (builtins.readFile ./scripts/public-media-workflow-fixture.sh);
    in
    {
      imports = [
        homelabModule
        ../fixtures/qbittorrent-offline.nix
        ../../modules/operations
      ];
      system.stateVersion = "26.05";
      virtualisation = {
        memorySize = 4096;
        diskSize = 8192;
        cores = 2;
      };
      networking.hosts."127.0.0.1" = [
        "api.radarr.video"
        "api.themoviedb.org"
      ];
      security.pki.certificateFiles = [ "${fixture}/cert.pem" ];
      systemd.services.seerr.environment.NODE_EXTRA_CA_CERTS = "${fixture}/cert.pem";
      environment.systemPackages = [
        (pkgs.python3.withPackages (_: [ pkgs.notification-process ]))
        pkgs.curl
      ];
      environment.etc."workflow/fixture.py".source = ../fixtures/media-workflow/provider.py;
      environment.etc."workflow/acceptance.py".source = ../fixtures/media-workflow/acceptance.py;
      environment.etc."workflow/integration".source = ../../scripts/integration;
      environment.etc."workflow/library_paths.py".source = ../fixtures/media-workflow/library_paths.py;
      environment.etc."workflow/restore.py".source = ../fixtures/media-workflow/restore.py;

      services.restic.backups.workflow = {
        repository = "/var/lib/restic-workflow";
        passwordFile = "/run/workflow-password";
        initialize = true;
        timerConfig = null;
      };
      systemd.services.workflow-provider = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python /etc/workflow/fixture.py ${fixture}";
      };
      systemd.services.workflow-credentials = {
        before = [
          "qbittorrent.service"
          "homelab-key-radarr.service"
        ];
        requiredBy = [
          "qbittorrent.service"
          "homelab-key-radarr.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = (import ../../lib/render-text.nix) ./scripts/prepare-media-workflow-credentials.sh {
          pkgs_python3 = pkgs.python3;
          pythonCheck1 = ./scripts/prepare_media_workflow_credentials.py;

        };
      };
      homelab = {
        optional.quality = {
          enable = true;
          radarrApiKeyFile = "/run/workflow-api-key";
        };
        operations = {
          enable = true;
          backup.job = "workflow";
        };
        apps = {
          radarr.enable = true;
          jellyfin.enable = true;
          seerr.enable = true;
          qbittorrent = {
            enable = true;
            vpn.enable = false;
            credentialsFile = "/run/workflow-qbit.ini";
          };
        };
        integration = {
          enable = true;
          interval = "1h";
          services = {
            radarr = {
              url = "http://127.0.0.1:7878";
              apiKeyFile = "/run/workflow-api-key";
              installApiKey = true;
              after = [ "workflow-credentials.service" ];
              mode = "managed";
              settings = {
                mediaManagement = {
                  copyUsingHardlinks = true;
                  recycleBin = "/srv/media/library/.recycle/radarr";
                  recycleBinCleanupDays = 30;
                  minimumFreeSpaceWhenImporting = 2048;
                  rescanAfterRefresh = "afterManual";
                };
                naming = {
                  renameMovies = true;
                  replaceIllegalCharacters = true;
                  standardMovieFormat = "{Movie CleanTitle} {(Release Year)} {[Quality Full]}{[Mediainfo VideoCodec]}{-Release Group}";
                  movieFolderFormat = "{Movie CleanTitle} ({Release Year})";
                };
              };
              resources = [
                {
                  endpoint = "rootfolder";
                  match.path = "/srv/media/library/movies";
                  values = { };
                }
              ];
            };
            jellyfin = {
              url = "http://127.0.0.1:8096";
              after = [ "workflow-credentials.service" ];
              mode = "managed";
              settings = {
                login = {
                  username = "admin";
                  password._secret = "/run/workflow-password";
                };
                libraries.Movies = {
                  collectionType = "movies";
                  paths = [ "/srv/media/library/movies" ];
                  options = {
                    EnableInternetProviders = false;
                    EnableRealtimeMonitor = false;
                  };
                };
                users.viewer = {
                  password._secret = "/run/workflow-password";
                  policy = {
                    IsAdministrator = false;
                    EnableContentDeletion = false;
                  };
                };
              };
            };
            seerr = {
              url = "http://127.0.0.1:5055";
              after = [
                "homelab-integrate-jellyfin.service"
                "homelab-integrate-radarr.service"
                "recyclarr.service"
              ];
              mode = "managed";
              settings = {
                login = {
                  username = "admin";
                  password._secret = "/run/workflow-password";
                  hostname = "127.0.0.1";
                  port = 8096;
                  useSsl = false;
                  email = "admin@example.test";
                  serverType = 2;
                  urlBase = "";
                };
                libraries = [ "Movies" ];
                radarr.movies = {
                  hostname = "127.0.0.1";
                  port = 7878;
                  apiKey._secret = "/run/workflow-api-key";
                  useSsl = false;
                  activeProfileName = "Homelab 1080p";
                  activeDirectory = "/srv/media/library/movies";
                  isDefault = true;
                  is4k = false;
                  minimumAvailability = "released";
                };
              };
            };
          };
        };
      };
      systemd.services.recyclarr = {
        after = [ "homelab-integrate-radarr.service" ];
        requires = [ "homelab-integrate-radarr.service" ];
      };
    };
  testScript = builtins.readFile ./scripts/media_workflow_test.py;
}
