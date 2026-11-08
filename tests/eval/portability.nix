{
  evaluate,
  lib,
  pkgs,
}:
let
  check = config: lib.all (a: a.assertion) config.assertions;
  rejects =
    fragment: config: lib.any (a: !a.assertion && lib.hasInfix fragment a.message) config.assertions;
  fixture = extra: (evaluate extra).config;
  enabledMusic = fixture {
    services.navidrome = {
      enable = true;
      user = "music-index";
      group = "music-index";
      settings = {
        Port = 14533;
        Address = "::1";
      };
    };
    homelab.music = {
      artwork = {
        enable = true;
        libraryDir = "/srv/fixture/music";
      };
      lyrics = {
        enable = true;
        libraryDir = "/srv/fixture/music";
      };
      shuffle = {
        enable = true;
        usernameFile = "/run/credentials/music-user";
        passwordFile = "/run/credentials/music-password%n";
      };
    };
  };
  pg = fixture {
    services.sonarr.enable = true;
    homelab = {
      operations = {
        enable = true;
        arrPostgresql.services = [ "sonarr" ];
      };
    };
    services.postgresql.settings = {
      port = 15432;
      unix_socket_directories = "/run/fixture-postgresql";
    };
  };
  audio = fixture {
    services.audiomuse-ai = {
      enable = true;
      host = "::1";
    };
    services.postgresql = {
      package = pkgs.postgresql_17;
      settings.port = 15432;
    };
  };
  definitions = fixture {
    services.prowlarr = {
      enable = true;
      dataDir = "/var/lib/fixture-indexers";
    };
    homelab.apps.prowlarr.customDefinitions."example.yml" =
      pkgs.writeText "example.yml" "id: example\nname: Example\n";
  };
  fresh = fixture {
    homelab.optional = {
      apps.freshrss.enable = true;
      freshrss = {
        passwordFile = "/run/credentials/news-password";
        port = 28081;
        bindAddress = "::1";
      };
    };
    services.freshrss.pool = "news";
  };
  freshExternal = fixture {
    homelab.optional = {
      apps.freshrss.enable = true;
      freshrss.passwordFile = "/run/credentials/news-password";
    };
    services.freshrss.pool = null;
    services.nginx.virtualHosts.homelab-freshrss-internal.locations."~ \\.php$".extraConfig =
      lib.mkForce "fastcgi_pass unix:/run/external-fpm.sock;";
  };
  homebridge = fixture {
    services.homebridge = {
      enable = true;
      settings.bridge.advertiser = "ciao";
      managedUi = {
        enable = true;
        uiUsernameFile = "/run/credentials/user";
        uiPasswordFile = "/run/credentials/password";
      };
    };
  };
  captions = fixture {
    services.jellyfin.enable = true;
    homelab.optional = {
      jellyfinPlugins.packages.Moonfin_nix = pkgs.writeTextDir "manifest.json" "{}";
      jellyfinCaptions = {
        enable = true;
        adminUsernameFile = "/run/credentials/admin-name";
        adminPasswordFile = "/run/credentials/admin-password%n";
        usernameFiles = [ "/run/credentials/selected-viewer" ];
        profiles.desktop.subtitlesTextSize = 21;
      };
    };
  };
  keycloak = fixture {
    services.postgresql.settings = {
      port = 15432;
      unix_socket_directories = "/run/fixture-postgresql";
    };
    services.keycloak = {
      enable = true;
      settings = {
        http-relative-path = "/auth/";
        hostname = "auth.example.com";
      };
      database.passwordFile = "/run/credentials/database-password";
      bootstrapRealm = {
        enable = true;
        file = "/run/credentials/realm.json";
        environmentFile = "/run/credentials/admin-environment";
      };
    };
  };
  customSlskd = fixture {
    users.groups = {
      downloads = { };
      indexer = { };
    };
    users.users = {
      downloads = {
        isSystemUser = true;
        group = "downloads";
      };
      indexer = {
        isSystemUser = true;
        group = "indexer";
      };
    };
    services = {
      slskd = {
        user = "downloads";
        group = "downloads";
      };
      lidarr = {
        enable = true;
        user = "indexer";
        group = "indexer";
      };
    };
    homelab.apps = {
      lidarr.enable = true;
      slskd = {
        enable = true;
        credentialsFile = "/run/credentials/downloads";
        vpn = {
          enable = false;
          allowUnconfined = true;
        };
      };
    };
  };
  empty = fixture { };
  operations = fixture {
    homelab = {
      apps.navidrome.enable = true;
      operations.enable = true;
    };
    services.navidrome.settings = {
      Address = "::1";
      Port = 14533;
    };
  };
  quality = fixture {
    services.sonarr = {
      enable = true;
      settings.server = {
        bindaddress = "::1";
        port = 18989;
        urlbase = "/shows/";
      };
    };
    homelab.optional.quality = {
      enable = true;
      sonarrApiKeyFile = "/run/credentials/sonarr-key";
    };
  };
in
{
  ipv4MappedEndpoint =
    let
      mapped = fixture {
        services.navidrome = {
          enable = true;
          settings.Address = "::ffff:127.0.0.1";
        };
        homelab.apps.navidrome.enable = true;
        homelab.operations.enable = true;
      };
    in
    check mapped
    && mapped.homelab.operations.endpoints.navidrome.url == "http://[::ffff:127.0.0.1]:4533";
  customPostgresSetupSocket =
    pg.systemd.services.postgresql-setup.environment.PGHOST == "/run/fixture-postgresql";
  keycloakExternalDatabaseKeepsTls =
    let
      external = fixture {
        services.keycloak = {
          enable = true;
          settings.hostname = "auth.example.com";
          database = {
            host = "database.example.com";
            caCert = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            passwordFile = "/run/secrets/database-password";
          };
          bootstrapRealm = {
            enable = true;
            localDatabase = false;
            file = "/run/secrets/realm.json";
            environmentFile = "/run/secrets/bootstrap.env";
          };
        };
      };
    in
    check external
    && external.services.keycloak.database.useSSL
    && !external.services.postgresql.enable;
  keycloakRejectsDifferentLocalPort = rejects "native server socket/port" (fixture {
    services.keycloak = {
      enable = true;
      settings.hostname = "auth.example.com";
      database.port = 15432;
      bootstrapRealm = {
        enable = true;
        file = "/run/secrets/realm.json";
        environmentFile = "/run/secrets/bootstrap.env";
      };
    };
  });
  keycloakUsesNativeDatabase =
    check keycloak
    && keycloak.services.keycloak.database.host == "/run/fixture-postgresql"
    && keycloak.services.keycloak.database.port == 15432;
  credentialPercentIsLiteral =
    lib.elem "password:/run/credentials/music-password%%n" enabledMusic.systemd.services.music-shuffle-configuration.serviceConfig.LoadCredential
    && lib.elem "admin-password:/run/credentials/admin-password%%n" captions.systemd.services.homelab-caption-setup.serviceConfig.LoadCredential;
  rejectsUnsupportedFreshServer = rejects "webserver = nginx" (fixture {
    homelab.optional.apps.freshrss.enable = true;
    homelab.optional.freshrss.passwordFile = "/run/credentials/news-password";
    services.freshrss.webserver = "caddy";
  });
  qualityUsesNativeListener =
    check quality
    &&
      quality.services.recyclarr.configuration.sonarr.homelab-sonarr.base_url
      == "http://[::1]:18989/shows";
  captionsNeedNoSeerrOrAccountIntegration =
    check captions
    && !captions.homelab.optional.jellyfinPlugins.moonbase.enable
    && !captions.homelab.integration.enable
    && !captions.services.seerr.enable;
  captionsPreserveExplicitUserSelection = builtins.elem "user-0:/run/credentials/selected-viewer" captions.systemd.services.homelab-caption-setup.serviceConfig.LoadCredential;
  keycloakUsesNativePrefix = lib.hasSuffix "/auth" keycloak.systemd.services.keycloak.environment.HOMELAB_KEYCLOAK_URL;
  slskdUsesNativeOwnerAndReader =
    check customSlskd
    && customSlskd.homelab.apps.slskd.downloadGroup == "downloads"
    && lib.elem "downloads" customSlskd.users.users.indexer.extraGroups;
  disabledFeaturesHaveNoUnits =
    !(empty.systemd.services ? music-shuffle-configuration)
    && !(empty.systemd.services ? homelab-caption-setup)
    && !(empty.systemd.services ? homelab-slskd-directories);
  musicUsesNativeAccounts =
    check enabledMusic
    && enabledMusic.systemd.services.music-artwork.serviceConfig.User == "music-index"
    && enabledMusic.systemd.services.music-lyrics.serviceConfig.User == "music-index"
    && enabledMusic.systemd.services.music-shuffle-configuration.serviceConfig.User == "music-index";
  lyricsDoNotRequireSharedStorage =
    !enabledMusic.homelab.storage.enable
    && !lib.elem "homelab-storage.service" enabledMusic.systemd.services.music-lyrics.requires;
  shuffleUsesNativeIpv6Port = enabledMusic.homelab.music.shuffle.serverUrl == "http://[::1]:14533";
  artworkUsesEffectivePackage = lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe enabledMusic.services.navidrome.finalPackage)) enabledMusic.systemd.services.music-artwork.serviceConfig.ExecStart;
  postgresTopologyIsConsistent =
    check pg
    && !pg.homelab.apps.sonarr.enable
    && pg.services.sonarr.settings.postgres.port == 15432
    && pg.services.sonarr.settings.postgres.host == "/run/fixture-postgresql"
    && pg.homelab.operations.postgresql.sonarr-main.port == 15432
    && lib.hasInfix "--port 15432" pg.systemd.services.homelab-arr-postgresql.script
    && lib.hasInfix "/run/fixture-postgresql" pg.systemd.services.homelab-arr-postgresql.script;
  audioSharesNativePostgres =
    check audio
    && audio.services.postgresql.package.outPath == pkgs.postgresql_17.outPath
    && lib.any (
      package: package.outPath == pkgs.postgresql_17.outPath
    ) audio.systemd.services.audiomuse-ai.path;
  runtimeDefinitionsReportCompatibility = rejects "mutable runtime files" (fixture {
    services.prowlarr.enable = true;
    homelab.apps.prowlarr.customDefinitions."example.yml" = "/run/secrets/private.yml";
  });
  publicDefinitionsNeedNoWrapper =
    check definitions
    && !definitions.homelab.apps.prowlarr.enable
    && definitions.systemd.services.prowlarr.serviceConfig.ExecStartPre != [ ];
  freshUsesSelectedPool =
    check fresh
    && fresh.services.phpfpm.pools ? news
    && !(fresh.services.phpfpm.pools ? freshrss)
    && !(fresh.systemd.services ? phpfpm-freshrss)
    && fresh.services.freshrss.baseUrl == "http://[::1]:28081";
  freshDoesNotCreateExternalPool =
    check freshExternal
    && !(freshExternal.services.phpfpm.pools ? unconfigured)
    && !(freshExternal.systemd.services ? phpfpm-unconfigured);
  homebridgeAdvertiserIsIndependent =
    check homebridge
    && !homebridge.services.avahi.enable
    && !lib.elem "avahi-daemon.service" homebridge.systemd.services.homebridge.requires;
  rejectsUnsafeStorage = rejects "system directories" (fixture {
    homelab.storage = {
      enable = true;
      rootDir = "/etc";
    };
  });
  requiresNativeQualityTargets = rejects "requires services.sonarr.enable" (fixture {
    homelab.optional.quality = {
      enable = true;
      sonarrApiKeyFile = "/run/credentials/sonarr-key";
    };
  });
  missingBackupReportsCompatibility = rejects "operations" (fixture {
    homelab.apps.navidrome.enable = true;
    homelab.readiness.enable = true;
    homelab.operations = {
      enable = true;
      monitoring.enable = true;
      notifications = {
        enable = true;
        environmentFile = "/run/credentials/notifications";
      };
    };
  });
  nativeIpv6Endpoint =
    check operations && operations.homelab.operations.endpoints.navidrome.url == "http://[::1]:14533";
}
