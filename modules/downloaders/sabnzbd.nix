{ config, lib, ... }:
let
  cfg = config.homelab.apps.sabnzbd;
  vpn = config.homelab.vpn;
in
{
  options.homelab.apps.sabnzbd = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "SABnzbd Web UI port.";
    };
    vpn.enable = lib.mkEnableOption "VPN egress for SABnzbd in addition to provider TLS";
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> vpn.enable;
        message = "SABnzbd VPN requires homelab.vpn.enable.";
      }
    ];
    services.sabnzbd = {
      configFile = null;
      settings.misc = {
        host = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
        inherit (cfg) port;
        download_dir = "${config.homelab.storage.downloadsDir}/incomplete/sabnzbd";
        complete_dir = "${config.homelab.storage.downloadsDir}/usenet";
        permissions = "0770";
        download_free = "20G";
      };
    };
    systemd.services.sabnzbd.vpn = {
      inherit (cfg.vpn) enable;
      namespace = vpn.namespace.name;
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = lib.mkIf cfg.vpn.enable [ cfg.port ];
  };
}
