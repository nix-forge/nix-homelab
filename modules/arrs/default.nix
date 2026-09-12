{ config, lib, ... }:
let
  enabled = lib.filter (name: config.homelab.apps.${name}.enable) [
    "sonarr"
    "radarr"
    "lidarr"
  ];
in
{
  services = lib.genAttrs enabled (_: {
    settings = {
      server.bindaddress = lib.mkDefault "127.0.0.1";
    };
  });
  systemd.tmpfiles.settings.homelab-sonarr = lib.mkIf config.homelab.apps.sonarr.enable {
    ${config.services.sonarr.dataDir}.d = {
      mode = "0700";
      inherit (config.services.sonarr) user group;
    };
  };
  # nixpkgs has no Bazarr bind option. Keep its host firewall port closed.
  systemd.services =
    lib.genAttrs (enabled ++ lib.optional config.homelab.apps.bazarr.enable "bazarr")
      (name: {
        serviceConfig.ReadWritePaths = [ config.services.${name}.dataDir ];
      });
}
