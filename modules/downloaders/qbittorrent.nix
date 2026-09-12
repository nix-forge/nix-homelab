{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.apps.qbittorrent;
  vpn = config.homelab.vpn;
in
{
  options.homelab.apps.qbittorrent = {
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
      description = "Web UI listen address. Confined traffic is reachable only from the host link.";
    };
    webuiPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Web UI TCP port.";
    };
    torrentingPort = lib.mkOption {
      type = lib.types.port;
      default = 51413;
      description = "Peer TCP/UDP port.";
    };
    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime INI file with WebUI username and Password_PBKDF2 under [Preferences]. Merged after public settings on every start.";
    };
    vpn = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Confine BitTorrent traffic. Disable explicitly only if direct ISP-visible peer traffic is intended.";
      };
      allowInbound = lib.mkEnableOption "inbound peer traffic from a provider that supports port forwarding";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> vpn.enable;
        message = "qBittorrent requires homelab.vpn.enable or an explicit homelab.apps.qbittorrent.vpn.enable = false.";
      }
      {
        assertion =
          cfg.credentialsFile == null
          || (lib.hasPrefix "/" cfg.credentialsFile && !(lib.hasPrefix "/nix/store" cfg.credentialsFile));
        message = "qBittorrent credentialsFile must be an absolute runtime path outside the Nix store.";
      }
    ];
    services.qbittorrent = {
      inherit (cfg) webuiPort torrentingPort;
      serverConfig = {
        Preferences.WebUI = {
          Address = cfg.bindAddress;
          LocalHostAuth = true;
          AuthSubnetWhitelistEnabled = false;
          CSRFProtection = true;
          ClickjackingProtection = true;
          HostHeaderValidation = true;
        };
        BitTorrent.Session = {
          DefaultSavePath = "${config.homelab.storage.downloadsDir}/torrents";
          TempPath = "${config.homelab.storage.downloadsDir}/incomplete";
          TempPathEnabled = true;
        }
        // lib.optionalAttrs cfg.vpn.enable {
          Interface = vpn.interface.name;
          InterfaceName = vpn.interface.name;
        };
        Network.PortForwardingEnabled = false;
      };
    };
    systemd.services.qbittorrent = {
      vpn = {
        inherit (cfg.vpn) enable;
        namespace = vpn.namespace.name;
      };
      serviceConfig = {
        ReadWritePaths = [ config.services.qbittorrent.profileDir ];
        LoadCredential = lib.mkIf (cfg.credentialsFile != null) [ "webui:${cfg.credentialsFile}" ];
        ExecStartPre = lib.mkIf (cfg.credentialsFile != null) (
          lib.mkAfter [
            (pkgs.writeShellScript "qbittorrent-credentials" ''
              set -eu
              ${pkgs.crudini}/bin/crudini --merge ${lib.escapeShellArg "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"} < "$CREDENTIALS_DIRECTORY/webui"
            '')
          ]
        );
      };
    };
    homelab.vpn = lib.mkIf cfg.vpn.enable {
      namespace.hostIngressPorts.tcp = [ cfg.webuiPort ];
      inboundPorts = lib.mkIf cfg.vpn.allowInbound {
        tcp = [ cfg.torrentingPort ];
        udp = [ cfg.torrentingPort ];
      };
    };
  };
}
