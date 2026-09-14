{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.apps.qbittorrent;
  vpn = config.homelab.vpn;
  pathType = lib.types.strMatching "/[A-Za-z0-9_./-]+";
  configured = cfg.configuration.categories != { } || cfg.configuration.tags != [ ];
  configurationFile = (pkgs.formats.json { }).generate "qbittorrent-resources.json" {
    url = "http://${cfg.bindAddress}:${toString cfg.webuiPort}";
    inherit (cfg.configuration) mode categories tags;
  };
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
      type = lib.types.nullOr pathType;
      default = null;
      description = "Runtime INI file with WebUI username and Password_PBKDF2 under [Preferences]. Merged after public settings on every start.";
    };
    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr pathType;
      default = null;
      description = "Runtime qBittorrent 5.2 API-key file used only to reconcile declared categories and tags.";
    };
    configuration = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "bootstrap"
          "managed"
        ];
        default = "bootstrap";
        description = "Bootstrap creates absent resources; managed also updates declared category paths. Neither mode deletes resources.";
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "15min";
        description = "Delay between completed qBittorrent resource reconciliation runs.";
      };
      categories = lib.mkOption {
        default = { };
        description = "Named qBittorrent categories. Paths must stay under the homelab downloads directory.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }: {
              options.savePath = lib.mkOption {
                type = pathType;
                default = "${config.homelab.storage.downloadsDir}/torrents/${name}";
                defaultText = lib.literalExpression ''"''${config.homelab.storage.downloadsDir}/torrents/''${name}"'';
                description = "Absolute category save path. The default isolates each workflow below the torrent download root.";
              };
            }
          )
        );
      };
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tags to create if absent. Existing and undeclared tags are preserved.";
      };
    };
    resourcePolicy = {
      maxActiveDownloads = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "Maximum number of torrents downloading concurrently.";
      };
      maxActiveUploads = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = "Maximum number of torrents seeding concurrently.";
      };
      maxActiveTorrents = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "Maximum combined number of active downloading and seeding torrents.";
      };
      maxConnections = lib.mkOption {
        type = lib.types.ints.positive;
        default = 200;
        description = "Maximum global peer connections.";
      };
      maxConnectionsPerTorrent = lib.mkOption {
        type = lib.types.ints.positive;
        default = 50;
        description = "Maximum peer connections for one torrent.";
      };
      maxUploads = lib.mkOption {
        type = lib.types.ints.positive;
        default = 20;
        description = "Maximum global upload slots.";
      };
      maxUploadsPerTorrent = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "Maximum upload slots for one torrent.";
      };
      ignoreSlowTorrents = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether slow torrents may exceed the active queue limits.";
      };
      localPeerDiscovery = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable local peer discovery. Disabled by default to avoid LAN discovery traffic from the VPN namespace.";
      };
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
      {
        assertion =
          cfg.apiKeyFile == null
          || (lib.hasPrefix "/" cfg.apiKeyFile && !(lib.hasPrefix "/nix/store" cfg.apiKeyFile));
        message = "qBittorrent apiKeyFile must be an absolute runtime path outside the Nix store.";
      }
      {
        assertion = !configured || cfg.apiKeyFile != null;
        message = "qBittorrent categories and tags require a qBittorrent 5.2 apiKeyFile.";
      }
      {
        assertion = lib.all (
          category:
          lib.hasPrefix "${config.homelab.storage.downloadsDir}/" category.savePath
          && !(lib.hasInfix "/../" "${category.savePath}/")
          && !(lib.hasInfix "/./" "${category.savePath}/")
        ) (lib.attrValues cfg.configuration.categories);
        message = "qBittorrent category save paths must be canonical descendants of homelab.storage.downloadsDir.";
      }
      {
        assertion =
          builtins.length cfg.configuration.tags == builtins.length (lib.unique cfg.configuration.tags)
          && lib.all (
            tag: tag != "" && !(lib.hasInfix "," tag) && !(lib.hasInfix "\n" tag) && !(lib.hasInfix "\r" tag)
          ) cfg.configuration.tags;
        message = "qBittorrent tags must be nonempty, unique and contain no commas or newlines.";
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
          IgnoreSlowTorrentsForQueueing = cfg.resourcePolicy.ignoreSlowTorrents;
          LSDEnabled = cfg.resourcePolicy.localPeerDiscovery;
          MaxActiveDownloads = cfg.resourcePolicy.maxActiveDownloads;
          MaxActiveTorrents = cfg.resourcePolicy.maxActiveTorrents;
          MaxActiveUploads = cfg.resourcePolicy.maxActiveUploads;
          MaxConnections = cfg.resourcePolicy.maxConnections;
          MaxConnectionsPerTorrent = cfg.resourcePolicy.maxConnectionsPerTorrent;
          MaxUploads = cfg.resourcePolicy.maxUploads;
          MaxUploadsPerTorrent = cfg.resourcePolicy.maxUploadsPerTorrent;
          QueueingSystemEnabled = true;
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
              fragment="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${config.services.qbittorrent.profileDir}/.webui-credentials.XXXXXX"})"
              trap '${pkgs.coreutils}/bin/rm -f "$fragment"' EXIT
              ${pkgs.python3}/bin/python3 ${../../scripts/downloaders/qbittorrent-credentials.py} \
                "$CREDENTIALS_DIRECTORY/webui" "$fragment"
              ${pkgs.crudini}/bin/crudini --merge ${lib.escapeShellArg "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"} < "$fragment"
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
    systemd.services.homelab-configure-qbittorrent = lib.mkIf configured {
      description = "Reconcile qBittorrent categories and tags";
      wantedBy = [ "multi-user.target" ];
      after = [
        "qbittorrent.service"
        "homelab-storage.service"
      ];
      requires = [
        "qbittorrent.service"
        "homelab-storage.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${../../scripts/downloaders/qbittorrent-config.py} ${configurationFile}";
        LoadCredential = [ "api-key:${cfg.apiKeyFile}" ];
        DynamicUser = true;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        CapabilityBoundingSet = "";
        MemoryMax = "96M";
        CPUQuota = "20%";
        TimeoutStartSec = "2min";
      };
    };
    systemd.timers.homelab-configure-qbittorrent = lib.mkIf configured {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitInactiveSec = cfg.configuration.interval;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
