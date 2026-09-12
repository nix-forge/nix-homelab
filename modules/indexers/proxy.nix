{ config, lib, ... }:
let
  cfg = config.homelab.indexerProxy;
  vpn = config.homelab.vpn;
  ns = config.services.vpnConfinement.namespaces.${vpn.namespace.name};
in
{
  options.homelab.indexerProxy = {
    enable = lib.mkEnableOption "a host-only confined HTTP proxy for selected Prowlarr indexers";

  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = vpn.enable;
        message = "The indexer proxy requires homelab.vpn.enable.";
      }
    ];
    services.tinyproxy = {
      enable = true;
      settings = {
        Listen = vpn.namespace.bindAddress;
        Allow = [ ns.derived.hostLink.hostAddressIPv4 ];
        ConnectPort = [ 443 ];
        Timeout = 60;
        # Request URLs may carry indexer API keys or passkeys.
        LogLevel = "Warning";
      };
    };
    systemd.services.tinyproxy.vpn = {
      enable = true;
      namespace = vpn.namespace.name;
      hardeningProfile = "strict";
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = [ config.services.tinyproxy.settings.Port ];
  };
}
