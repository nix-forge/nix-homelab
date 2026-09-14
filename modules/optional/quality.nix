{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.quality;
  profile = {
    name = "Homelab 1080p";
    reset_unmatched_scores.enabled = false;
    upgrade = {
      allowed = false;
      until_quality = "WEB 1080p";
      until_score = 0;
    };
    min_format_score = 0;
    qualities = [
      {
        name = "WEB 1080p";
        qualities = [
          "WEBDL-1080p"
          "WEBRip-1080p"
        ];
      }
    ];
  };
  quality = app: definition: key: {
    quality_definition = {
      type = definition;
      qualities =
        map
          (name: {
            inherit name;
            min = 5;
            preferred = 40;
            max = 80;
          })
          [
            "WEBDL-1080p"
            "WEBRip-1080p"
          ];
    };
    base_url =
      let
        raw = config.services.${app}.settings.server.urlbase or "";
        base =
          if raw == "" || raw == "/" then "" else "/${lib.removeSuffix "/" (lib.removePrefix "/" raw)}";
      in
      "http://127.0.0.1:${toString config.services.${app}.settings.server.port}${base}";
    api_key._secret = key;
    custom_formats = import ./quality-formats.nix app "Homelab 1080p";
    delete_old_custom_formats = false;
    quality_profiles = [ profile ];
  };
  guideSettings = pkgs.writeText "recyclarr-settings.yml" (
    builtins.toJSON { resource_providers = import ./quality-resources.nix { inherit pkgs; }; }
  );
  runtimePath = lib.types.nullOr (lib.types.strMatching "/[^\n]+");
in
{
  options.homelab.optional.quality = {
    enable = lib.mkEnableOption "a conservative, locally declared Recyclarr 1080p profile";
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
  };

  config = lib.mkIf cfg.enable {
    assertions = [
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
      preStart = lib.mkAfter ''
        ${pkgs.coreutils}/bin/install -m 0600 ${guideSettings} /var/lib/recyclarr/settings.yml
      '';
      serviceConfig = {
        CPUWeight = 25;
        IOWeight = 25;
        Nice = 10;
      };
    };
  };
}
