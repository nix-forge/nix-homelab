# Merge into the consuming host alongside its real mounts and nix-seal catalog.
{ config, lib, ... }: {
  homelab.operations = {
    enable = true;
    backup.job = "homelab";
    # Native local Immich PostgreSQL can be exported without another credential.
    # Remote databases still require an explicit matching export and pgpass file.
    postgresql.immich =
      lib.mkIf
        (
          config.services.immich.enable
          && config.services.immich.database.enable
          && lib.hasPrefix "/" config.services.immich.database.host
        )
        {
          inherit (config.services.immich.database) host port;
          database = config.services.immich.database.name;
        };
    pressure = {
      enable = true;
      # Reserve working space on the actual download filesystem, including
      # unpacking and the host's backup budget. These are initial policy values.
      pauseBytes = 80 * 1024 * 1024 * 1024;
      resumeBytes = 120 * 1024 * 1024 * 1024;
      clients.qbittorrent = {
        url = "http://${config.homelab.apps.qbittorrent.bindAddress}:${toString config.homelab.apps.qbittorrent.webuiPort}";
        credentialsFile = "/run/nix-seal/system/secrets/qbittorrent-api-json";
      };
    };
    monitoring = {
      enable = true;
      alerts = [ "ntfy" ];
    };
    notifications = {
      enable = true;
      environmentFile = "/run/nix-seal/system/secrets/ntfy-environment";
    };
    dashboard.enable = true;
    # Change the host domain/address and provide a matching certificate chain.
    access = {
      enable = true;
      domain = "homelab.home.arpa";
      bindAddress = "127.0.0.1";
      certificateFile = "/run/nix-seal/system/secrets/homelab-certificate";
      keyFile = "/run/nix-seal/system/secrets/homelab-tls-key";
      usersFile = "/run/nix-seal/system/secrets/authelia-users";
      jwtSecretFile = "/run/nix-seal/system/secrets/authelia-jwt";
      sessionSecretFile = "/run/nix-seal/system/secrets/authelia-session";
      storageEncryptionKeyFile = "/run/nix-seal/system/secrets/authelia-storage";
      backends = {
        dashboard.port = 8082;
        health.port = 8085;
      };
    };
    endpoints = {
      jellyfin = {
        url = "http://127.0.0.1:8096";
        healthUrl = "http://127.0.0.1:8096/health";
        conditions = [
          "[STATUS] == 200"
          "[BODY] == Healthy"
        ];
      };
      seerr = {
        url = "http://127.0.0.1:5055";
        healthUrl = "http://127.0.0.1:5055/api/v1/status";
      };
    };
  };
  services.restic.backups.homelab = {
    # Supply an independent destination in the host; the media HDD alone does
    # not protect against its own failure. No repository is initialized here.
    repositoryFile = "/run/nix-seal/system/secrets/homelab-restic-repository";
    passwordFile = "/run/nix-seal/system/secrets/homelab-restic-password";
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
    checkOpts = [ "--read-data-subset=5%" ];
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };
  services.gatus = {
    environmentFile = "/run/nix-seal/system/secrets/gatus-environment";
    settings.alerting.ntfy = {
      url = "http://127.0.0.1:2586";
      topic = "homelab-health";
      token = "\${NTFY_PUBLISH_TOKEN}";
      default-alert = {
        enabled = true;
        send-on-resolved = true;
        failure-threshold = 3;
        success-threshold = 2;
      };
    };
    # Alert rules are explicit so local failure details stay private.
    settings.endpoints = [
      {
        name = "notification-delivery";
        url = "http://127.0.0.1:2586/v1/health";
        interval = "1m";
        conditions = [ "[STATUS] == 200" ];
        alerts = [ { type = "ntfy"; } ];
      }
    ];
  };
}
