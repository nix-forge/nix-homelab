{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.quality;
  # Only local key-installing jobs can establish the API credentials used by
  # this policy. Remote jobs and the independent anime instance do not gate it.
  integrationUnits = lib.mapAttrsToList (name: _: "homelab-integrate-${name}.service") (
    lib.filterAttrs (
      _: service:
      service.installApiKey
      && service.localService == null
      && (
        (
          service.kind == "sonarr"
          && cfg.sonarrApiKeyFile != null
          && service.apiKeyFile == cfg.sonarrApiKeyFile
        )
        || (
          service.kind == "radarr"
          && cfg.radarrApiKeyFile != null
          && service.apiKeyFile == cfg.radarrApiKeyFile
        )
      )
    ) (lib.optionalAttrs config.homelab.integration.enable config.homelab.integration.services)
  );
  remux =
    app: resolution: if app == "radarr" then "Remux-${resolution}" else "Bluray-${resolution} Remux";
  qualities = app: resolution: [
    { name = remux app resolution; }
    { name = "Bluray-${resolution}"; }
    {
      name = "WEB ${resolution}";
      qualities = [
        "WEBDL-${resolution}"
        "WEBRip-${resolution}"
      ];
    }
  ];
  profile = app: {
    name = "Homelab 1080p";
    reset_unmatched_scores.enabled = false;
    upgrade = {
      allowed = true;
      until_quality = remux app "1080p";
      until_score = 10000;
    };
    min_format_score = 0;
    qualities = qualities app "1080p";
  };
  profile2160p = app: {
    name = "Homelab 2160p";
    reset_unmatched_scores.enabled = false;
    upgrade = {
      allowed = true;
      until_quality = remux app "2160p";
      # Keep accepting better formats after reaching the resolution cutoff.
      until_score = 10000;
    };
    # SDR is a valid source. Reject known upscales with explicit CF penalties.
    min_format_score = 0;
    qualities = qualities app "2160p" ++ qualities app "1080p";
  };
  hdrFormats =
    app:
    map
      (format: {
        trash_ids = [ format.${app} ];
        assign_scores_to = map (name: {
          inherit name;
          inherit (format) score;
        }) ([ (profile app).name ] ++ lib.optionals cfg.enable2160p [ (profile2160p app).name ]);
      })
      [
        {
          # Clear the former 1080p admission bonus without resetting manual CFs.
          radarr = "820b09bb9acbfde9c35c71e0e565dad8";
          sonarr = "290078c8b266272a5cc8e251b5e2eb0b";
          score = 0;
        }
        {
          radarr = "493b6d1dbec3c3364c59d7607f7e3405";
          sonarr = "505d871304820ba7106b693be6fe4a9e";
          score = 1500;
        }
        {
          # DV with an HDR10 base layer remains usable on mixed clients.
          radarr = "b337d6812e06c200ec9a2d3cfa9d20a7";
          sonarr = "7c3a61a9c6cb04f52f1544be6d44a026";
          score = 600;
        }
        {
          radarr = "caa37d0df9c348912df1fb1d88f9273a";
          sonarr = "0c4b99df9206d2cfac3c05ab897dd62a";
          score = 100;
        }
        {
          radarr = "923b6abef9b17f937fab56cfcf89e1f1";
          sonarr = "9b27ab6498ec0f31a3353992e19434ca";
          score = -10000;
        }
      ];
  quality = app: definition: key: {
    # Use the pinned guide's source-specific sizes, including remux limits.
    # Definitions affect all profiles in an Arr instance.
    quality_definition.type = definition;
    base_url =
      let
        raw = config.services.${app}.settings.server.urlbase or "";
        base =
          if raw == "" || raw == "/" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" raw)}";
      in
      "${
        (import ../../lib/http-url.nix lib) (config.services.${app}.settings.server.bindaddress or "0.0.0.0"
        ) config.services.${app}.settings.server.port
      }${base}";
    api_key._secret = key;
    custom_formats =
      import ./formats.nix app (
        [ (profile app).name ] ++ lib.optionals cfg.enable2160p [ (profile2160p app).name ]
      ) cfg.preferAnimeDualAudio cfg.preferSubtitleLabeledReleases
      ++ hdrFormats app
      ++ lib.optionals (app == "sonarr" && cfg.enableAnimeProfile) [
        {
          trash_ids = [
            "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
            "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
            "9b27ab6498ec0f31a3353992e19434ca" # DV without HDR fallback
          ];
          assign_scores_to = [
            {
              name = "Homelab Anime";
              score = -10000;
            }
          ];
        }
      ]
      ++ lib.optionals (app == "sonarr" && cfg.enableAnimeProfile && cfg.preferAnimeDualAudio) [
        {
          trash_ids = [ "418f50b10f1907201b6cfdf881f467b7" ];
          assign_scores_to = [
            {
              name = "Homelab Anime";
              score = 10;
            }
          ];
        }
      ];
    delete_old_custom_formats = false;
    quality_profiles = [
      (profile app)
    ]
    ++ lib.optionals cfg.enable2160p [ (profile2160p app) ]
    ++ lib.optionals (app == "sonarr" && cfg.enableAnimeProfile) [
      {
        trash_id = "20e0fc959f1f1704bed501f23bdae76f";
        name = "Homelab Anime";
        # Keep unranked groups eligible, with known bad groups still excluded.
        min_format_score = 0;
        reset_unmatched_scores.enabled = true;
      }
    ];
  };
  guideSettings = pkgs.writeText "recyclarr-settings.yml" (
    builtins.toJSON { resource_providers = import ./resources.nix { inherit pkgs; }; }
  );
  runtimePath = lib.types.nullOr (lib.types.strMatching "/[^\n]+");
in
{
  options.homelab.optional.quality = {
    enable = lib.mkEnableOption "locally declared Recyclarr quality profiles";
    sonarrApiKeyFile = lib.mkOption {
      type = runtimePath;
      default = null;
      description = "User-provided runtime Sonarr API key. Null leaves Sonarr unmanaged.";
    };
    radarrApiKeyFile = lib.mkOption {
      type = runtimePath;
      default = null;
      description = "User-provided runtime Radarr API key. Null leaves Radarr unmanaged.";
    };
    preferAnimeDualAudio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Prefer Sonarr anime releases labeled with dual audio, while allowing single-audio releases.";
    };
    preferSubtitleLabeledReleases = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Prefer Sonarr 1080p releases explicitly labeled with subtitles.";
    };
    enableAnimeProfile = lib.mkEnableOption "the pinned guide's anime source/group profile with a 1080p ceiling";
    enable2160p = lib.mkEnableOption "a 2160p WEB, Blu-ray and remux profile with 1080p fallback and HDR10-compatible releases";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sonarrApiKeyFile == null || config.services.sonarr.enable;
        message = "Recyclarr Sonarr policy requires services.sonarr.enable.";
      }
      {
        assertion = cfg.radarrApiKeyFile == null || config.services.radarr.enable;
        message = "Recyclarr Radarr policy requires services.radarr.enable.";
      }
      {
        assertion = cfg.sonarrApiKeyFile != null || cfg.radarrApiKeyFile != null;
        message = "Recyclarr quality policy requires at least one user-provided API key file.";
      }
      {
        assertion =
          let
            names = map lib.toLower (
              lib.concatMap (app: builtins.attrNames (config.services.recyclarr.configuration.${app} or { })) [
                "sonarr"
                "radarr"
              ]
            );
          in
          builtins.length names == builtins.length (lib.unique names);
        message = "Recyclarr instance names must be unique across Sonarr and Radarr (case-insensitive); duplicate names are skipped upstream.";
      }
    ]
    ++
      map
        (path: {
          assertion = path == null || !(lib.hasPrefix "/nix/store/" path);
          message = "Recyclarr API keys must be runtime files outside the Nix store.";
        })
        [
          cfg.sonarrApiKeyFile
          cfg.radarrApiKeyFile
        ];
    services.recyclarr = {
      enable = true;
      schedule = lib.mkDefault "Sun *-*-* 04:10:00";
      configuration =
        lib.optionalAttrs (cfg.sonarrApiKeyFile != null) {
          sonarr.homelab-sonarr = quality "sonarr" "series" cfg.sonarrApiKeyFile;
        }
        // lib.optionalAttrs (cfg.radarrApiKeyFile != null) {
          radarr.homelab-radarr = quality "radarr" "movie" cfg.radarrApiKeyFile;
        };
    };
    systemd.services.recyclarr = {
      after = integrationUnits;
      requires = integrationUnits;
      preStart = lib.mkAfter (
        (import ../../../lib/render-text.nix) ./scripts/recyclarr-install-settings.sh {
          pkgs_coreutils = pkgs.coreutils;
          inherit guideSettings;
        }
      );
      serviceConfig = {
        StateDirectoryMode = "0700";
        UMask = "0077";
        CPUWeight = 25;
        IOWeight = 25;
        Nice = 10;
      };
    };
  };
}
