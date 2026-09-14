{ config, lib, ... }:
let
  cfg = config.homelab.indexerProxy;
  vpn = config.homelab.vpn;
in
{
  options.homelab.indexerProxy = {
    enable = lib.mkEnableOption "an authenticated VPN-confined SOCKS5 proxy for selected Prowlarr indexers";
    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "SOCKS5 port reachable only over the namespace host link.";
    };
    username = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "prowlarr";
      description = "SOCKS5 username supplied to explicitly configured Prowlarr proxies.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = null;
      description = "Absolute runtime file containing the SOCKS5 password.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = vpn.enable;
        message = "The indexer proxy requires homelab.vpn.enable.";
      }
      {
        assertion =
          cfg.passwordFile != null
          && !(lib.hasPrefix "/nix/store" cfg.passwordFile)
          && !(lib.hasInfix ":" cfg.passwordFile);
        message = "The indexer proxy requires an absolute runtime passwordFile outside the Nix store.";
      }
    ];
    services.microsocks = {
      enable = true;
      ip = vpn.namespace.bindAddress;
      inherit (cfg) port;
      authUsername = cfg.username;
      authPasswordFile = cfg.passwordFile;
      authOnce = false;
      # Request destinations can contain indexer API keys or passkeys.
      disableLogging = true;
    };
    systemd.services.microsocks.vpn = {
      enable = true;
      namespace = vpn.namespace.name;
      hardeningProfile = "strict";
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = [ cfg.port ];
  };
}
