{ config, lib, ... }:
let
  cfg = config.homelab.apps.nzbget;
  vpn = config.homelab.vpn;
in
{
  options.homelab.apps.nzbget = {
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
      description = "Control interface address.";
    };
    controlPort = lib.mkOption {
      type = lib.types.port;
      default = 6789;
      description = "Control interface TCP port.";
    };
    vpn.enable = lib.mkEnableOption "VPN egress for NZBGet";
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> vpn.enable;
        message = "NZBGet VPN requires homelab.vpn.enable.";
      }
    ];
    services.nzbget.settings = {
      CertCheck = true;
      CertStore = config.security.pki.caBundle;
      ControlIP = cfg.bindAddress;
      ControlPort = cfg.controlPort;
      MainDir = "/var/lib/nzbget";
      DestDir = "${config.homelab.storage.downloadsDir}/usenet";
      InterDir = "${config.homelab.storage.downloadsDir}/incomplete/nzbget";
      UMask = "0007";
    };
    systemd.services.nzbget = {
      vpn = {
        inherit (cfg.vpn) enable;
        namespace = vpn.namespace.name;
      };
      serviceConfig.ReadWritePaths = [ "/var/lib/nzbget" ];
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = lib.mkIf cfg.vpn.enable [ cfg.controlPort ];
  };
}
