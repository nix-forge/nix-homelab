{ lib, evaluate }:
let
  names = [
    "autobrr"
    "cross-seed"
    "unpackerr"
    "flaresolverr"
    "komga"
    "kavita"
    "shelfmark"
    "pinchflat"
    "immich"
    "paperless"
    "syncthing"
    "adguardhome"
    "scrutiny"
    "karakeep"
    "miniflux"
  ];
  empty = (evaluate { }).config;
  configured =
    (evaluate {
      imports = [ ../../examples/optional-services.nix ];
      services = {
        sonarr.enable = true;
        radarr.enable = true;
        sonarr.settings.server.port = 18989;
        radarr.settings.server.port = 17878;
      };
      homelab = {
        optional = {
          apps = lib.genAttrs (names ++ [ "maintainerr" ]) (_: {
            enable = true;
          });
          quality = {
            enable = true;
            sonarrApiKeyFile = "/run/keys/sonarr";
            radarrApiKeyFile = "/run/keys/radarr";
          };
        };
        apps.qbittorrent = {
          bindAddress = "192.0.2.2";
          webuiPort = 18081;
        };
      };
    }).config;
  audioConfigured = (evaluate { homelab.apps.navidrome.enable = true; }).config;
  minifluxConfigured =
    (evaluate {
      homelab.optional.apps.miniflux.enable = true;
      homelab.operations.enable = true;
    }).config;
  minifluxSealed =
    (evaluate {
      homelab.optional.apps.miniflux.enable = true;
      homelab.optional.miniflux.adminCredentialsFile = "/run/secrets/miniflux-admin.env";
    }).config;
  minifluxStoreCredential =
    (evaluate {
      homelab.optional.apps.miniflux.enable = true;
      homelab.optional.miniflux.adminCredentialsFile = "/nix/store/public-credential";
    }).config;
  freshrssConfigured =
    (evaluate {
      homelab.operations.enable = true;
      homelab.optional.apps.freshrss.enable = true;
      homelab.optional.freshrss.passwordFile = "/run/secrets/news-password";
      homelab.optional.freshrss.initialFeeds = [
        {
          url = "https://example.org/feed.xml";
          category = "Reporting";
        }
      ];
    }).config;
  freshrssListeners = freshrssConfigured.services.nginx.virtualHosts.homelab-freshrss-internal.listen;
  audiomuseConfigured =
    (evaluate {
      services.audiomuse-ai = {
        enable = true;
        environmentFile = "/run/secrets/audiomuse.env";
      };
    }).config;
  invalidAudiomuseIdentity =
    (evaluate {
      services.audiomuse-ai = {
        enable = true;
        user = "root";
      };
    }).config;
  invalidAudiomuseEnvironmentFile =
    (evaluate {
      services.audiomuse-ai = {
        enable = true;
        environmentFile = "/nix/store/public-invalid";
      };
    }).config;
  invalidAudiomuseEnvironmentPath =
    (evaluate {
      services.audiomuse-ai = {
        enable = true;
        environmentFile = "/run/secrets/../audiomuse.env";
      };
    }).config;
  fourK = (evaluate { imports = [ ../../examples/quality-4k.nix ]; }).config;
  fourKTarget =
    (evaluate {
      homelab.optional.quality = {
        enable = true;
        enable2160p = true;
        sonarrApiKeyFile = "/run/keys/sonarr";
        radarrApiKeyFile = "/run/keys/radarr";
      };
    }).config;
  dualAudio =
    (evaluate {
      homelab.optional.quality = {
        enable = true;
        sonarrApiKeyFile = "/run/keys/sonarr";
        preferAnimeDualAudio = true;
      };
    }).config;
  invalid = (evaluate { homelab.optional.quality.enable = true; }).config;
  duplicateQuality =
    (evaluate {
      homelab.optional.quality = {
        enable = true;
        sonarrApiKeyFile = "/run/keys/sonarr";
      };
      services.recyclarr.configuration.radarr.HOMELAB-SONARR = { };
    }).config;
  escaped =
    (evaluate {
      homelab.optional.apps.pinchflat.enable = true;
      services.pinchflat = {
        mediaDir = "/srv/elsewhere";
        secretsFile = "/run/keys/pinchflat";
      };
    }).config;
  pinchflatOverride = evaluate (
    { pkgs, ... }: {
      homelab.optional.apps.pinchflat.enable = true;
      services.pinchflat = {
        secretsFile = "/run/keys/pinchflat";
        package = pkgs.writeShellScriptBin "pinchflat" "exit 0";
      };
    }
  );
  invalidKarakeep =
    (evaluate {
      homelab.optional = {
        apps.karakeep.enable = true;
        karakeep.extraEnvironment.MEILI_ADDR = "http://example.invalid";
      };
    }).config;
  anime =
    (evaluate {
      homelab.optional.apps.sonarr-anime.enable = true;
      homelab.operations.enable = true;
    }).config;
  animePortCollision =
    (evaluate {
      homelab.apps.sonarr.enable = true;
      homelab.optional.apps.sonarr-anime.enable = true;
      services.sonarr.settings.server.port = 8990;
    }).config;
  animeWithoutStorage = (evaluate { services.sonarr-anime.enable = true; }).config;
  jellyfinPlugins =
    (evaluate (
      { pkgs, ... }: {
        services.jellyfin.enable = true;
        homelab.optional.jellyfinPlugins.packages.Demo = pkgs.writeTextDir "plugin.dll" "fixture";
      }
    )).config;
  jellyfinPluginsWithoutServer =
    (evaluate (
      { pkgs, ... }: {
        homelab.optional.jellyfinPlugins.packages.Demo = pkgs.writeTextDir "plugin.dll" "fixture";
      }
    )).config;
  maintainerrPolicy =
    (evaluate {
      homelab.optional.apps.maintainerr.enable = true;
      homelab.optional.maintainerr = {
        htpasswdFile = "/run/keys/maintainerr-htpasswd";
        policyFile = "/run/keys/maintainerr-policy.json";
      };
    }).config;
  ignoreMarkers =
    (evaluate {
      homelab.optional.jellyfinIgnore = {
        enable = true;
        user = "nobody";
        mountPoint = "/srv/media";
        roots = [ "/srv/media/shows" ];
      };
    }).config;
  unsafePolicyPath =
    (evaluate {
      homelab.optional.apps.maintainerr.enable = true;
      homelab.optional.maintainerr = {
        htpasswdFile = "/run/keys/maintainerr-htpasswd";
        policyFile = "/nix/store/exposed-policy.json";
      };
    }).config;
  rootIgnoreUser =
    (evaluate {
      homelab.optional.jellyfinIgnore = {
        enable = true;
        user = "root";
        mountPoint = "/srv/media";
        roots = [ "/srv/media/shows" ];
      };
    }).config;
in
{
  pinchflatMaintainedExecutables =
    lib.hasInfix "pinchflat-ngx" configured.systemd.services.pinchflat.serviceConfig.ExecStart
    && lib.hasInfix "pinchflat-ngx" configured.systemd.services.pinchflat.serviceConfig.ExecStartPre;
  pinchflatPackageOverride =
    pinchflatOverride.config.systemd.services.pinchflat.serviceConfig.ExecStart
    == "${pinchflatOverride.config.services.pinchflat.package}/bin/pinchflat start"
    &&
      pinchflatOverride.config.systemd.services.pinchflat.serviceConfig.ExecStartPre
      == "${pinchflatOverride.config.services.pinchflat.package}/bin/migrate";
  maintainerrStorePolicyRejected = lib.any (entry: !entry.assertion) unsafePolicyPath.assertions;
  jellyfinIgnoreRootRejected = lib.any (entry: !entry.assertion) rootIgnoreUser.assertions;
  maintainerrPolicyManualOnly =
    maintainerrPolicy.systemd.services.homelab-maintainerr-policy.wantedBy == [ ]
    &&
      maintainerrPolicy.systemd.services.homelab-maintainerr-policy.serviceConfig.User
      == "homelab-maintainerr"
    && lib.hasInfix "--config /run/keys/maintainerr-policy.json" maintainerrPolicy.systemd.services.homelab-maintainerr-policy.serviceConfig.ExecStart;
  jellyfinIgnoreIsIndependentAndPrivate =
    ignoreMarkers.systemd.timers.homelab-jellyfin-ignore.wantedBy == [ "timers.target" ]
    && ignoreMarkers.systemd.services.homelab-jellyfin-ignore.serviceConfig.User == "nobody"
    && ignoreMarkers.systemd.services.homelab-jellyfin-ignore.serviceConfig.PrivateNetwork;
  jellyfinPluginInstallerSelected =
    lib.hasInfix "homelab-install-jellyfin-plugins" jellyfinPlugins.systemd.services.jellyfin.preStart
    && jellyfinPlugins.systemd.services.jellyfin.restartTriggers != [ ];
  jellyfinPluginsRequireServer = lib.any (
    item: !item.assertion
  ) jellyfinPluginsWithoutServer.assertions;
  animeIsolated =
    anime.services.sonarr-anime.enable
    && anime.systemd.services.sonarr-anime.environment.SONARR__SERVER__BINDADDRESS == "127.0.0.1"
    && anime.systemd.services.sonarr-anime.environment.SONARR__SERVER__PORT == "8990"
    && anime.systemd.services.sonarr-anime.serviceConfig.User == "homelab-sonarr-anime"
    && builtins.elem "/srv/media" anime.systemd.services.sonarr-anime.serviceConfig.ReadWritePaths
    && anime.homelab.operations.state.sonarr-anime.paths == [ "/var/lib/homelab-sonarr-anime" ]
    && anime.homelab.operations.endpoints.sonarr-anime.url == "http://127.0.0.1:8990"
    && anime.networking.firewall.allowedTCPPorts == [ ];
  animePortCollisionRejected = lib.any (item: !item.assertion) animePortCollision.assertions;
  animeStorageBypassRejected = lib.any (item: !item.assertion) animeWithoutStorage.assertions;
  nativePortOverrides =
    configured.services.recyclarr.configuration.sonarr.homelab-sonarr.base_url
    == "http://127.0.0.1:18989"
    &&
      configured.services.recyclarr.configuration.radarr.homelab-radarr.base_url
      == "http://127.0.0.1:17878"
    && configured.services.shelfmark.environment.QBITTORRENT_URL == "http://192.0.2.2:18081";
  maintainerrPrivate =
    configured.systemd.services.homelab-maintainerr.environment.UI_HOSTNAME == "127.0.0.1"
    && configured.systemd.services.homelab-maintainerr.environment.UI_PORT == "6247"
    &&
      configured.services.nginx.virtualHosts.homelab-maintainerr.basicAuthFile
      == "/run/credentials/nginx.service/homelab-maintainerr-auth";
  audiomuseUsesDedicatedIdentity =
    audiomuseConfigured.systemd.services.audiomuse-ai.serviceConfig.User == "audiomuse"
    && audiomuseConfigured.systemd.services.audiomuse-ai.serviceConfig.Group == "audiomuse"
    &&
      audiomuseConfigured.systemd.services.audiomuse-ai.serviceConfig.EnvironmentFile
      == [ "/run/secrets/audiomuse.env" ];
  audiomuseRootIdentityRejected = lib.any (a: !a.assertion) invalidAudiomuseIdentity.assertions;
  audiomuseStoreEnvironmentFileRejected = lib.any (
    a: !a.assertion
  ) invalidAudiomuseEnvironmentFile.assertions;
  audiomuseTraversalEnvironmentFileRejected = lib.any (
    a: !a.assertion
  ) invalidAudiomuseEnvironmentPath.assertions;
  maintainerrNative =
    configured.systemd.services.homelab-maintainerr.serviceConfig.User == "homelab-maintainerr"
    && configured.systemd.services.homelab-maintainerr.serviceConfig.NoNewPrivileges
    && configured.systemd.services.homelab-maintainerr.serviceConfig.ProtectSystem == "strict";
  karakeepNative =
    configured.services.karakeep.package.pname == "karakeep"
    && configured.services.karakeep.extraEnvironment.HOST == "127.0.0.1"
    && configured.services.meilisearch.listenAddress == "127.0.0.1"
    && configured.services.meilisearch.masterKeyFile == "/var/lib/karakeep/meili-master-key"
    && configured.users.users.karakeep.uid == 62462
    && configured.users.users.karakeep-browser.uid == 62463
    && lib.hasInfix "meta skuid" configured.networking.nftables.tables.homelab-karakeep.content
    && configured.systemd.services.karakeep-web.serviceConfig.NoNewPrivileges
    && configured.systemd.services.karakeep-web.serviceConfig.ProtectSystem == "strict"
    && configured.systemd.services.karakeep-workers.serviceConfig.MemoryMax == "4G";
  karakeepProtectedEnvironment = lib.any (assertion: !assertion.assertion) invalidKarakeep.assertions;
  minifluxPrivateAndRecoverable =
    minifluxConfigured.services.miniflux.enable
    && minifluxConfigured.services.miniflux.config.LISTEN_ADDR == "127.0.0.1:18080"
    && minifluxConfigured.services.miniflux.config.WORKER_POOL_SIZE == 4
    &&
      minifluxConfigured.services.miniflux.adminCredentialsFile == "/var/lib/homelab-miniflux/admin.env"
    && minifluxConfigured.systemd.services.miniflux.serviceConfig.MemoryMax == "512M"
    && minifluxConfigured.systemd.services.miniflux.serviceConfig.NoNewPrivileges
    && minifluxConfigured.services.postgresql.enable
    && builtins.elem "miniflux" minifluxConfigured.services.postgresql.ensureDatabases
    && minifluxConfigured.homelab.operations.postgresql.miniflux.database == "miniflux"
    && minifluxConfigured.homelab.operations.state.miniflux.paths == [ "/var/lib/homelab-miniflux" ]
    &&
      minifluxConfigured.homelab.operations.endpoints.miniflux.healthUrl
      == "http://127.0.0.1:18080/healthcheck";
  minifluxExternalCredentials =
    minifluxSealed.services.miniflux.adminCredentialsFile == "/run/secrets/miniflux-admin.env"
    && !(builtins.elem "homelab-miniflux-credentials.service" minifluxSealed.systemd.services.miniflux.requires)
    && !(minifluxSealed.systemd.services ? homelab-miniflux-credentials)
    && lib.any (a: !a.assertion) minifluxStoreCredential.assertions;
  freshrssPrivateAndVisual =
    freshrssConfigured.services.freshrss.enable
    && freshrssConfigured.services.freshrss.package.pname == "FreshRSS"
    && freshrssConfigured.services.freshrss.database.type == "sqlite"
    &&
      freshrssConfigured.services.freshrss.passwordFile
      == "/run/credentials/freshrss-config.service/news-password"
    &&
      freshrssConfigured.systemd.services.freshrss-config.serviceConfig.LoadCredential
      == [ "news-password:/run/secrets/news-password" ]
    && builtins.length freshrssListeners == 1
    && (builtins.head freshrssListeners).addr == "127.0.0.1"
    && (builtins.head freshrssListeners).port == 18081
    && !(builtins.head freshrssListeners).ssl
    && !(builtins.head freshrssListeners).proxyProtocol
    && freshrssConfigured.services.phpfpm.pools.freshrss.settings."pm.max_children" == 4
    && builtins.elem "192.168.0.0/16" freshrssConfigured.systemd.services.phpfpm-freshrss.serviceConfig.IPAddressDeny
    && builtins.elem "192.168.0.0/16" freshrssConfigured.systemd.services.freshrss-updater.serviceConfig.IPAddressDeny
    && freshrssConfigured.homelab.operations.state.freshrss.paths == [ "/var/lib/freshrss" ];
  qualityExclusionsPreserveManualScores =
    lib.all
      (
        app:
        let
          policy = fourK.services.recyclarr.configuration.${app}."homelab-${app}";
        in
        builtins.length policy.custom_formats >= 20
        && (
          let
            entry = builtins.head policy.custom_formats;
          in
          builtins.length entry.trash_ids == 5
          && (
            app != "radarr"
            || lib.all (id: builtins.elem id entry.trash_ids) [
              "bfd8eb01832d646a0a89c4deb46f8564"
              "e6886871085226c3da1830830146846c"
            ]
          )
          && lib.all (target: target.score == -10000) entry.assign_scores_to
        )
        && lib.all (
          profile: profile.min_format_score == 0 && !profile.reset_unmatched_scores.enabled
        ) policy.quality_profiles
        && !policy.delete_old_custom_formats
      )
      [
        "sonarr"
        "radarr"
      ];
  properFormatsAreScored =
    lib.all
      (
        app:
        let
          policy = fourKTarget.services.recyclarr.configuration.${app}."homelab-${app}";
          ids = {
            radarr = [
              "e7718d7a3ce595f289bfee26adc178f5"
              "ae43b294509409a6a13919dedd4764c4"
              "5caaaa1c08c1742aa4342d8c4cc463f2"
            ];
            sonarr = [
              "ec8fa7296b64e8cd390a1600981f3923"
              "eb3d5cc0a2be0db205fb823640db6a3c"
              "44e7c4de10ae50265753082e5dc76047"
            ];
          };
        in
        lib.all
          (
            index:
            let
              entry = lib.findFirst (
                format: builtins.elem (builtins.elemAt ids.${app} index) format.trash_ids
              ) null policy.custom_formats;
            in
            entry != null
            &&
              entry.assign_scores_to == map (profile: {
                inherit (profile) name;
                score = 5 + index;
              }) policy.quality_profiles
          )
          [
            0
            1
            2
          ]
      )
      [
        "radarr"
        "sonarr"
      ];
  animeDualAudioIsPreferredButOptional =
    let
      policy = dualAudio.services.recyclarr.configuration.sonarr.homelab-sonarr;
      dualAudioFormat = lib.findFirst (
        entry: builtins.elem "418f50b10f1907201b6cfdf881f467b7" entry.trash_ids
      ) null policy.custom_formats;
    in
    dualAudioFormat != null
    &&
      dualAudioFormat.assign_scores_to == [
        {
          name = "Homelab 1080p";
          score = 10;
        }
      ]
    && (builtins.head policy.quality_profiles).min_format_score == 0
    && (builtins.head policy.quality_profiles).upgrade.allowed;
  fourKRetains1080p =
    map (
      profile: profile.name
    ) fourK.services.recyclarr.configuration.radarr.homelab-radarr.quality_profiles == [
      "Homelab 1080p"
      "Homelab 2160p"
    ];
  fourKTargetAllowsHdrAndFallback =
    lib.all
      (
        app:
        let
          policy = fourKTarget.services.recyclarr.configuration.${app}."homelab-${app}";
          target = builtins.elemAt policy.quality_profiles 1;
          dvOnlyId =
            {
              radarr = "923b6abef9b17f937fab56cfcf89e1f1";
              sonarr = "9b27ab6498ec0f31a3353992e19434ca";
            }
            .${app};
          hdrId =
            {
              radarr = "493b6d1dbec3c3364c59d7607f7e3405";
              sonarr = "505d871304820ba7106b693be6fe4a9e";
            }
            .${app};
          fallbackId =
            {
              radarr = "820b09bb9acbfde9c35c71e0e565dad8";
              sonarr = "290078c8b266272a5cc8e251b5e2eb0b";
            }
            .${app};
          dvOnly = lib.findFirst (entry: builtins.elem dvOnlyId entry.trash_ids) null policy.custom_formats;
          hdr = lib.findFirst (entry: builtins.elem hdrId entry.trash_ids) null policy.custom_formats;
          fallback = lib.findFirst (
            entry: builtins.elem fallbackId entry.trash_ids
          ) null policy.custom_formats;
        in
        target.name == "Homelab 2160p"
        && target.min_format_score == 0
        && target.upgrade.allowed
        && target.upgrade.until_quality == (if app == "radarr" then "Remux-2160p" else "Bluray-2160p Remux")
        && target.upgrade.until_score == 10000
        &&
          map (quality: quality.name) target.qualities == [
            (if app == "radarr" then "Remux-2160p" else "Bluray-2160p Remux")
            "Bluray-2160p"
            "WEB 2160p"
            (if app == "radarr" then "Remux-1080p" else "Bluray-1080p Remux")
            "Bluray-1080p"
            "WEB 1080p"
          ]
        && dvOnly != null
        && hdr != null
        && fallback != null
        && lib.all (entry: entry.score == 0) fallback.assign_scores_to
        && lib.all (entry: entry.score == 1500) hdr.assign_scores_to
        && lib.all (entry: entry.score == -10000) dvOnly.assign_scores_to
        && !(policy.quality_definition ? qualities)
      )
      [
        "radarr"
        "sonarr"
      ];
  fourKAllowsFormatUpgrades =
    lib.all
      (
        app:
        let
          policy = fourK.services.recyclarr.configuration.${app}."homelab-${app}";
        in
        (builtins.elemAt policy.quality_profiles 1).upgrade.allowed
        && !policy.delete_old_custom_formats
        && !(policy.quality_definition ? qualities)
      )
      [
        "radarr"
        "sonarr"
      ];
  maintainerrUsesPersonalPackage =
    configured.homelab.optional.maintainerr.package.pname == "maintainerr"
    &&
      configured.homelab.optional.maintainerr.package.outPath == (evaluate { }).pkgs.maintainerr.outPath;
  maintainerrNoMediaBind =
    configured.systemd.services.homelab-maintainerr.environment.DATA_DIR
    == "/var/lib/homelab-maintainerr/data"
    &&
      configured.systemd.services.homelab-maintainerr.serviceConfig.StateDirectory
      == "homelab-maintainerr";
  optionalDefaultDisabled =
    lib.all (name: !empty.services.${name}.enable) names
    && !(empty.systemd.services ? homelab-maintainerr);
  noOptionalFirewallPorts =
    configured.networking.firewall.allowedTCPPorts == [ ]
    && configured.networking.firewall.allowedUDPPorts == [ ];
  flaresolverrPrivateAndBounded =
    configured.systemd.services.flaresolverr.environment.HOST == "127.0.0.1"
    && configured.systemd.services.flaresolverr.environment.HEADLESS == "true"
    && configured.systemd.services.flaresolverr.environment.DISABLE_MEDIA == "true"
    && configured.systemd.services.flaresolverr.environment.LOG_HTML == "false"
    && configured.systemd.services.flaresolverr.environment.PROMETHEUS_ENABLED == "false"
    && configured.systemd.services.flaresolverr.serviceConfig.CPUQuota == "100%"
    && configured.systemd.services.flaresolverr.serviceConfig.MemoryMax == "2G"
    && configured.systemd.services.flaresolverr.serviceConfig.TasksMax == 512;
  uniqueQualityInstanceNames =
    builtins.attrNames configured.services.recyclarr.configuration.sonarr == [ "homelab-sonarr" ]
    && builtins.attrNames configured.services.recyclarr.configuration.radarr == [ "homelab-radarr" ];
  qualityInstallsSettingsAndSecrets =
    lib.hasInfix "settings.yml" configured.systemd.services.recyclarr.preStart
    && lib.hasInfix "config.yml" configured.systemd.services.recyclarr.preStart
    && configured.systemd.services.recyclarr.serviceConfig.LoadCredential != [ ];
  duplicateQualityRejected = lib.any (a: !a.assertion) duplicateQuality.assertions;
  qualityRequiresRuntimeKeys = lib.any (a: !a.assertion) invalid.assertions;
  mediaOutputEscapeRejected = lib.any (a: !a.assertion) escaped.assertions;
  qualityPreservesOtherProfiles =
    !configured.services.recyclarr.configuration.radarr.homelab-radarr.delete_old_custom_formats;
  qualityUpgradesEnabled =
    (builtins.head configured.services.recyclarr.configuration.radarr.homelab-radarr.quality_profiles)
    .upgrade.allowed;
  guardedOptionalWriters =
    lib.all
      (
        name: builtins.elem "homelab-optional-storage.service" configured.systemd.services.${name}.requires
      )
      [
        "cross-seed"
        "unpackerr"
        "shelfmark"
        "pinchflat"
      ];
  bookReadersReadOnly =
    lib.all
      (
        name:
        builtins.elem configured.homelab.storage.libraryDir
          configured.systemd.services.${name}.serviceConfig.BindReadOnlyPaths
      )
      [
        "komga"
        "kavita"
      ];
  boundedExtraction =
    configured.services.unpackerr.settings.parallel == 1
    && configured.services.unpackerr.settings.start_delay == "1m"
    && configured.services.unpackerr.settings.retry_delay == "5m"
    && !configured.services.unpackerr.settings.debug;
  shelfmarkPreservesDownloaderJobs =
    configured.services.shelfmark.environment.PROWLARR_TORRENT_ACTION == "keep"
    && configured.services.shelfmark.environment.PROWLARR_USENET_ACTION == "copy"
    && configured.services.shelfmark.environment.CERTIFICATE_VALIDATION == "enabled"
    && configured.services.shelfmark.environment.PROWLARR_AUTO_EXPAND == "false";
  navidromeDisablesTelemetry = !audioConfigured.services.navidrome.settings.EnableInsightsCollector;
  boundedOcr =
    configured.services.paperless.settings.PAPERLESS_OCR_MODE == "auto"
    && configured.services.paperless.settings.PAPERLESS_AI_ENABLED == false
    && configured.services.paperless.settings.PAPERLESS_TASK_WORKERS == 1
    && configured.services.paperless.settings.PAPERLESS_THREADS_PER_WORKER == 1;
  scrutinyLeavesHardwareToHost =
    !configured.services.scrutiny.collector.enable && !configured.services.smartd.enable;
  komgaUsesPrimaryMediaGroup =
    let
      c =
        (evaluate {
          homelab.optional.apps.komga.enable = true;
          homelab.storage.group = "shared-library";
        }).config;
      overridden =
        (evaluate {
          homelab.optional.apps.komga.enable = true;
          services.komga.group = "custom-library";
        }).config;
    in
    c.services.komga.group == "shared-library"
    && c.systemd.services.komga.serviceConfig.Group == "shared-library"
    && overridden.services.komga.group == "custom-library";
  qualityWaitsOnlyForConfiguredIntegrations =
    let
      c =
        (evaluate {
          services.sonarr.enable = true;
          homelab.optional.quality = {
            enable = true;
            sonarrApiKeyFile = "/run/keys/sonarr";
          };
          homelab.integration = {
            enable = true;
            services = {
              initial-sonarr = {
                kind = "sonarr";
                installApiKey = true;
                url = "http://127.0.0.1:8989";
                apiKeyFile = "/run/keys/sonarr";
              };
              remote-sonarr = {
                kind = "sonarr";
                url = "https://sonarr.example.invalid";
                apiKeyFile = "/run/keys/sonarr";
              };
            };
          };
        }).config;
      withoutIntegration =
        (evaluate {
          services.sonarr.enable = true;
          homelab.optional.quality = {
            enable = true;
            sonarrApiKeyFile = "/run/keys/sonarr";
          };
        }).config;
      unit = "homelab-integrate-initial-sonarr.service";
    in
    builtins.elem unit c.systemd.services.recyclarr.after
    && builtins.elem unit c.systemd.services.recyclarr.requires
    && !(builtins.elem "homelab-integrate-radarr.service" c.systemd.services.recyclarr.requires)
    && !(builtins.elem "homelab-integrate-remote-sonarr.service" c.systemd.services.recyclarr.requires)
    && withoutIntegration.systemd.services.recyclarr.requires == [ ];
  komgaAvoidsDownloaderPort =
    configured.services.komga.settings.server.port == 25600
    && configured.services.komga.settings.server.port != configured.homelab.apps.sabnzbd.port;
  scrutinyAvoidsDownloaderPort =
    configured.services.scrutiny.settings.web.listen.port == 8083
    && configured.services.scrutiny.settings.web.listen.port != configured.homelab.apps.sabnzbd.port;
  privateListeners =
    configured.services.cross-seed.settings.host == "127.0.0.1"
    && configured.services.kavita.settings.IpAddresses == "127.0.0.1"
    && configured.services.immich.host == "127.0.0.1";
  crossSeedVerifiesLinkedContent = !configured.services.cross-seed.settings.skipRecheck;
  privatePhotoAndDocumentGroups =
    !(builtins.elem configured.homelab.storage.group (
      configured.systemd.services.immich-server.serviceConfig.SupplementaryGroups or [ ]
    ))
    && !(builtins.elem configured.homelab.storage.group (
      configured.systemd.services.paperless-web.serviceConfig.SupplementaryGroups or [ ]
    ));
}
