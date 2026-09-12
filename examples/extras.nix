# Select the services you need in the consuming host. These defaults keep local
# endpoints private; application configuration and runtime credentials stay native.
{
  services = {
    recyclarr = {
      enable = true;
      configuration = {
        sonarr.main = {
          base_url = "http://127.0.0.1:8989";
          api_key._secret = "/run/nix-seal/system/secrets/sonarr-api-key";
          delete_old_custom_formats = false;
        };
        radarr.main = {
          base_url = "http://127.0.0.1:7878";
          api_key._secret = "/run/nix-seal/system/secrets/radarr-api-key";
          delete_old_custom_formats = false;
        };
      };
    };
    autobrr = {
      enable = true;
      secretFile = "/run/nix-seal/system/secrets/autobrr-session";
      settings = {
        host = "127.0.0.1";
        port = 7474;
      };
    };
    prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      openFirewall = false;
    };
    smartd.enable = true;
  };
}
