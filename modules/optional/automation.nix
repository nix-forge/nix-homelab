{ config, lib, ... }:
let
  enabled = name: config.homelab.optional.apps.${name}.enable;
  storage = config.homelab.storage;
in
{
  config = lib.mkMerge [
    (lib.mkIf (enabled "autobrr") {
      services.autobrr = {
        openFirewall = lib.mkDefault false;
        settings.host = lib.mkDefault "127.0.0.1";
      };
      systemd.services.autobrr.serviceConfig.ReadWritePaths = [ "/var/lib/autobrr" ];
    })
    (lib.mkIf (enabled "cross-seed") {
      services.cross-seed = {
        useGenConfigDefaults = lib.mkDefault true;
        settings = {
          host = lib.mkDefault "127.0.0.1";
          linkDirs = lib.mkDefault [ "${storage.downloadsDir}/cross-seed" ];
          dataDirs = lib.mkDefault [ ];
          linkType = lib.mkDefault "hardlink";
          action = lib.mkDefault "inject";
          matchMode = lib.mkDefault "strict";
          skipRecheck = lib.mkDefault false;
          delay = lib.mkDefault 60;
          searchCadence = lib.mkDefault "1 day";
          rssCadence = lib.mkDefault "1 hour";
        };
      };
      assertions = [
        {
          assertion = config.services.cross-seed.settingsFile != null;
          message = "cross-seed requires a runtime settingsFile containing authenticated torrentClients and Torznab URLs.";
        }
      ];
    })
    (lib.mkIf (enabled "unpackerr") {
      services.unpackerr.settings = {
        debug = lib.mkDefault false;
        start_delay = lib.mkDefault "1m";
        retry_delay = lib.mkDefault "5m";
        parallel = lib.mkDefault 1;
        max_retries = lib.mkDefault 3;
        file_mode = lib.mkDefault "0660";
        dir_mode = lib.mkDefault "0770";
      };
    })
    (lib.mkIf (enabled "flaresolverr") {
      services.flaresolverr.openFirewall = lib.mkDefault false;
      systemd.services.flaresolverr = {
        environment = {
          HOST = lib.mkDefault "127.0.0.1";
          HEADLESS = lib.mkDefault "true";
          DISABLE_MEDIA = lib.mkDefault "true";
          LOG_LEVEL = lib.mkDefault "warning";
          LOG_HTML = lib.mkDefault "false";
          PROMETHEUS_ENABLED = lib.mkDefault "false";
        };
        serviceConfig = {
          CPUQuota = lib.mkDefault "100%";
          MemoryHigh = lib.mkDefault "1G";
          MemoryMax = lib.mkDefault "2G";
          # Chromium can briefly exceed 128 processes and threads while a
          # challenge browser starts. Keep a finite cgroup limit with room for
          # one browser session.
          TasksMax = lib.mkDefault 512;
        };
      };
    })
  ];
}
