{ config, lib, ... }: {
  systemd.services.seerr = lib.mkIf config.homelab.apps.seerr.enable {
    environment.HOST = "127.0.0.1";
    serviceConfig.UMask = "0077";
  };
}
