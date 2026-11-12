# Import explicitly after reviewing storage and client playback support.
_: {
  services.sonarr.enable = true;
  services.radarr.enable = true;
  homelab.optional.quality = {
    enable = true;
    enable2160p = true;
    sonarrApiKeyFile = "/run/nix-seal/system/secrets/sonarr-api-key";
    radarrApiKeyFile = "/run/nix-seal/system/secrets/radarr-api-key";
  };
}
