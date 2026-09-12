# Import explicitly after reviewing available disk space and client codec support.
{ lib, ... }: {
  homelab.optional.quality = {
    enable = true;
    sonarrApiKeyFile = "/run/nix-seal/system/secrets/sonarr-api-key";
    radarrApiKeyFile = "/run/nix-seal/system/secrets/radarr-api-key";
  };
  services.recyclarr.configuration = lib.genAttrs [ "sonarr" "radarr" ] (app: {
    "homelab-${app}" = {
      custom_formats = lib.mkAfter (import ../modules/optional/quality-formats.nix app "Homelab 4K WEB");
      quality_definition.qualities = lib.mkAfter (
        map
          (name: {
            inherit name;
            min = 10;
            preferred = 80;
            max = 160;
          })
          [
            "WEBDL-2160p"
            "WEBRip-2160p"
          ]
      );
      quality_profiles = lib.mkAfter [
        {
          name = "Homelab 4K WEB";
          reset_unmatched_scores.enabled = false;
          upgrade = {
            allowed = false;
            until_quality = "WEB 2160p";
            until_score = 0;
          };
          min_format_score = 0;
          qualities = [
            {
              name = "WEB 2160p";
              qualities = [
                "WEBDL-2160p"
                "WEBRip-2160p"
              ];
            }
          ];
        }
      ];
    };
  });
}
