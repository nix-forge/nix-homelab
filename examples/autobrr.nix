# Import after optional-services.nix; supply the named indexer through autobrr's UI.
{ config, ... }:
let
  secret = name: "/run/nix-seal/system/secrets/${name}";
  qbit = config.homelab.apps.qbittorrent;
in
{
  homelab = {
    optional.apps.autobrr.enable = true;
    integration = {
      enable = true;
      services.autobrr = {
        kind = "autobrr";
        url = "http://127.0.0.1:${toString config.services.autobrr.settings.port}";
        apiKeyFile = secret "autobrr-api-key";
        mode = "managed";
        settings = {
          downloadClients.qBittorrent = {
            type = "QBITTORRENT";
            enabled = true;
            host = "http://${qbit.bindAddress}:${toString qbit.webuiPort}";
            username._secret = secret "qbittorrent-username";
            password._secret = secret "qbittorrent-password";
          };
          filters."Selected releases" = {
            # Replace provider and release names, then opt in after a paused test.
            values = {
              enabled = false;
              match_releases = "REPLACE_WITH_SELECTED_RELEASE";
              max_size = "5GB";
              max_downloads = 2;
              max_downloads_unit = "DAY";
            };
            indexers = [ "REPLACE_WITH_EXISTING_INDEXER_NAME" ];
            actions."Paused download" = {
              type = "QBITTORRENT";
              client = "qBittorrent";
              enabled = true;
              category = "manual";
              paused = true;
            };
          };
        };
      };
    };
  };
}
