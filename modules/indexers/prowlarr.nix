{ config, lib, ... }:
let
  cfg = config.homelab.apps.prowlarr;
  vpn = config.homelab.vpn;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "homelab" "services" "prowlarr" ] [ "homelab" "apps" "prowlarr" ])
  ];
  options.homelab.apps.prowlarr = {
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
      description = "Prowlarr listen address.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9696;
      description = "Prowlarr TCP port.";
    };
    vpn.enable = lib.mkEnableOption "confinement of all Prowlarr traffic, including app sync";
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> vpn.enable;
        message = "Prowlarr VPN requires homelab.vpn.enable.";
      }
    ];
    services.prowlarr.settings = {
      server = {
        bindaddress = cfg.bindAddress;
        inherit (cfg) port;
      };
    };
    systemd.services.prowlarr.vpn = {
      inherit (cfg.vpn) enable;
      namespace = vpn.namespace.name;
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = lib.mkIf cfg.vpn.enable [ cfg.port ];
    warnings = lib.optional cfg.vpn.enable "Confined Prowlarr cannot initiate host/LAN app-sync connections. Use an indexer proxy for selective privacy or keep target apps in the same namespace.";
  };
}
