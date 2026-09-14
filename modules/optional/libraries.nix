{ config, lib, ... }:
let
  enabled = name: config.homelab.optional.apps.${name}.enable;
  storage = config.homelab.storage;
in
{
  config = lib.mkMerge [
    (lib.mkIf (enabled "komga") {
      services.komga = {
        openFirewall = lib.mkDefault false;
        settings.server = {
          address = lib.mkDefault "127.0.0.1";
          port = lib.mkDefault 25600;
        };
      };
      systemd.services.komga.serviceConfig.ReadWritePaths = [ config.services.komga.stateDir ];
    })
    (lib.mkIf (enabled "kavita") {
      services.kavita.settings.IpAddresses = lib.mkDefault "127.0.0.1";
      systemd.services.kavita.serviceConfig.ReadWritePaths = [ config.services.kavita.dataDir ];
    })
    (lib.mkIf (enabled "shelfmark") {
      services.shelfmark = {
        openFirewall = lib.mkDefault false;
        environment = {
          FLASK_HOST = lib.mkDefault "127.0.0.1";
          AUTH_METHOD = lib.mkDefault "builtin";
          INGEST_DIR = lib.mkDefault "${storage.libraryDir}/books";
          HARDLINK_TORRENTS = lib.mkDefault "false";
          CERTIFICATE_VALIDATION = lib.mkDefault "enabled";
          PROWLARR_AUTO_EXPAND = lib.mkDefault "false";
          PROWLARR_TORRENT_ACTION = lib.mkDefault "keep";
          # Shelfmark's upstream default removes a completed Usenet job after
          # import. Preserve it unless the host explicitly accepts deletion.
          PROWLARR_USENET_ACTION = lib.mkDefault "copy";
        };
      };
    })
    (lib.mkIf (enabled "pinchflat") {
      services.pinchflat = {
        openFirewall = lib.mkDefault false;
        selfhosted = lib.mkDefault false;
        mediaDir = lib.mkDefault "${storage.libraryDir}/videos";
        extraConfig.YT_DLP_WORKER_CONCURRENCY = lib.mkDefault 1;
      };
    })
  ];
}
