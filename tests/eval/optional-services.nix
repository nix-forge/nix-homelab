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
  ];
  empty = (evaluate { }).config;
  configured =
    (evaluate {
      imports = [ ../../examples/optional-services.nix ];
      services = {
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
  audiomuseConfigured = (evaluate { services.audiomuse-ai.enable = true; }).config;
  invalidAudiomuseIdentity =
    (evaluate {
      services.audiomuse-ai = {
        enable = true;
        user = "root";
      };
    }).config;
  fourK = (evaluate { imports = [ ../../examples/quality-4k.nix ]; }).config;
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
  invalidKarakeep =
    (evaluate {
      homelab.optional = {
        apps.karakeep.enable = true;
        karakeep.extraEnvironment.MEILI_ADDR = "http://example.invalid";
      };
    }).config;
in
{
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
    && audiomuseConfigured.systemd.services.audiomuse-ai.serviceConfig.Group == "audiomuse";
  audiomuseRootIdentityRejected = lib.any (a: !a.assertion) invalidAudiomuseIdentity.assertions;
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
  qualityExclusionsPreserveManualScores =
    lib.all
      (
        app:
        let
          policy = fourK.services.recyclarr.configuration.${app}."homelab-${app}";
        in
        builtins.length policy.custom_formats == 2
        && lib.all (
          entry:
          builtins.length entry.trash_ids == 3
          && lib.all (target: target.score == -10000) entry.assign_scores_to
        ) policy.custom_formats
        && lib.all (
          profile: profile.min_format_score == 0 && !profile.reset_unmatched_scores.enabled
        ) policy.quality_profiles
        && !policy.delete_old_custom_formats
      )
      [
        "sonarr"
        "radarr"
      ];
  fourKRetains1080p =
    map (
      profile: profile.name
    ) fourK.services.recyclarr.configuration.radarr.homelab-radarr.quality_profiles == [
      "Homelab 1080p"
      "Homelab 4K WEB"
    ];
  fourKBoundedNoUpgrade =
    lib.all
      (
        app:
        let
          policy = fourK.services.recyclarr.configuration.${app}."homelab-${app}";
        in
        !(builtins.elemAt policy.quality_profiles 1).upgrade.allowed
        && !policy.delete_old_custom_formats
        && lib.all (quality: quality.max == 160) (
          lib.filter (quality: lib.hasSuffix "2160p" quality.name) policy.quality_definition.qualities
        )
      )
      [
        "radarr"
        "sonarr"
      ];
  maintainerrPinnedPackage =
    configured.homelab.optional.maintainerr.package.pname == "maintainerr"
    && configured.homelab.optional.maintainerr.package.version == "3.28.0";
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
  qualityUpgradeBounded =
    !(builtins.head configured.services.recyclarr.configuration.radarr.homelab-radarr.quality_profiles)
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
