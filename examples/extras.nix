# Small companion to the integrated media example. Host nix-seal supplies files.
{
  imports = [ ./optional-services.nix ];
  homelab.optional = {
    apps.autobrr.enable = true;
    quality = {
      enable = true;
      sonarrApiKeyFile = "/run/nix-seal/system/secrets/sonarr-api-key";
      radarrApiKeyFile = "/run/nix-seal/system/secrets/radarr-api-key";
    };
  };
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    openFirewall = false;
  };
  # Configure smartd devices and polling in the consuming host after checking
  # disk/USB support and the desired standby behavior. Do not scan every disk.
}
