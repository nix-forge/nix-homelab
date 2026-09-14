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
        cache_limit = lib.mkDefault "256M";
        direct_unpack = lib.mkDefault false;
        direct_unpack_threads = lib.mkDefault 1;
        host = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
        inherit (cfg) port;
        download_dir = "${config.homelab.storage.downloadsDir}/incomplete/sabnzbd";
        complete_dir = "${config.homelab.storage.downloadsDir}/usenet";
        enable_https_verification = lib.mkDefault true;
        inet_exposure = lib.mkDefault 0;
        max_art_tries = lib.mkDefault 3;
        pause_on_post_processing = lib.mkDefault true;
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
