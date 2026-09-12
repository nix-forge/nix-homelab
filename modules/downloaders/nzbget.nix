{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.apps.nzbget;
  vpn = config.homelab.vpn;
in
{
  options.homelab.apps.nzbget = {
    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User-provided runtime credential fragment. Merged before each start; values never enter command arguments or the Nix store.";
    };
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
        assertion =
          cfg.credentialsFile == null
          || (
            lib.hasPrefix "/" cfg.credentialsFile
            && !(lib.hasPrefix "/nix/store" cfg.credentialsFile)
            && !(lib.hasInfix ":" cfg.credentialsFile)
            && !(lib.hasInfix "\n" cfg.credentialsFile)
          );
        message = "NZBGet credentialsFile must be an absolute runtime path outside the Nix store.";
      }
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
      preStart = lib.mkIf (cfg.credentialsFile != null) (
        lib.mkAfter ''
          ${pkgs.python3}/bin/python3 ${../../scripts/downloaders/nzbget-credentials.py} /var/lib/nzbget/nzbget.conf
        ''
      );
      serviceConfig = {
        ReadWritePaths = [ "/var/lib/nzbget" ];
        LoadCredential = lib.mkIf (cfg.credentialsFile != null) [
          "nzbget-credentials:${cfg.credentialsFile}"
        ];
      };
    };
    homelab.vpn.namespace.hostIngressPorts.tcp = lib.mkIf cfg.vpn.enable [ cfg.controlPort ];
  };
}
