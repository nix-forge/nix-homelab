{ homelabModule }: {
  name = "homelab-media-workflow";
  nodes.machine =
    { pkgs, ... }:
    let
      fixture =
        pkgs.runCommand "public-media-workflow-fixture"
          {
            nativeBuildInputs = [
              pkgs.openssl
              pkgs.ffmpeg
            ];
          }
          ''
            mkdir -p $out
            openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
              -subj /CN=public-workflow-fixture \
              -addext 'subjectAltName=DNS:api.radarr.video,DNS:api.themoviedb.org' \
              -keyout $out/key.pem -out $out/cert.pem
            ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i color=c=blue:s=1920x1080:r=1 \
              -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
              -t 120 -c:v mpeg4 -c:a aac $out/Workflow.Fixture.2026.1080p.WEB-DL.mkv
          '';
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
        pkgs.python3
        pkgs.curl
      ];
      environment.etc."workflow/fixture.py".source = ../fixtures/media-workflow/provider.py;
      environment.etc."workflow/acceptance.py".source = ../fixtures/media-workflow/acceptance.py;
      environment.etc."workflow/integration".source = ../../scripts/integration;
      environment.etc."workflow/library-paths.py".source = ../fixtures/media-workflow/library-paths.py;
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
        script = ''
          umask 077
          printf 0123456789abcdef0123456789abcdef > /run/workflow-api-key
          printf public-workflow-password > /run/workflow-password
          ${pkgs.python3}/bin/python - <<'PY'
          import hashlib, base64
          salt = b'public-fixture-salt'
          digest = hashlib.pbkdf2_hmac('sha512', b'public-workflow-password', salt, 100000)
          encoded = base64.b64encode(salt).decode() + ':' + base64.b64encode(digest).decode()
          with open('/run/workflow-qbit.ini', 'w') as handle:
              handle.write('[Preferences]\nWebUI\\Username=admin\nWebUI\\Password_PBKDF2="@ByteArray(' + encoded + ')"\n')
          PY
        '';
      };
      homelab = {
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
                  activeProfileName = "HD-1080p";
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
    };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("workflow-provider.service")
    for service in ["radarr", "jellyfin", "seerr"]:
        machine.succeed(f"test $(systemctl show -p Result --value homelab-integrate-{service}.service) = success")
        machine.succeed(f"test $(systemctl show -p ExecMainStartTimestampMonotonic --value homelab-integrate-{service}.service) -gt 0")
        machine.succeed(f"systemctl start homelab-integrate-{service}.service")
    machine.succeed("python -u /etc/workflow/library-paths.py 2>&1", timeout=180)
    machine.succeed("python -u /etc/workflow/acceptance.py 2>&1", timeout=300)
    machine.succeed("python -u /etc/workflow/restore.py 2>&1", timeout=300)
  '';
}
