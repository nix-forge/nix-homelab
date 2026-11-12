{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.apps.slskd;
  vpn = config.homelab.vpn;
  pathType = lib.types.strMatching "/[A-Za-z0-9_./-]+";
  dedicatedPath = import ../lib/media-directory.nix lib;
  native = config.services.slskd;
  sharedStorage =
    config.homelab.storage.enable
    && lib.all (path: lib.hasPrefix "${config.homelab.storage.rootDir}/" path) [
      cfg.downloadsDir
      cfg.incompleteDir
    ];
  downloads = cfg.downloadsDir;
  incomplete = cfg.incompleteDir;
  webAddress = if cfg.vpn.enable then vpn.namespace.bindAddress else "127.0.0.1";
  checkCredentials = pkgs.writeShellApplication {
    name = "homelab-slskd-check-credentials";
    text = (import ../../lib/render-text.nix) ./scripts/homelab-slskd-check-credentials.sh {
      lib_escapeShellArg_webAddress = lib.escapeShellArg webAddress;
    };
  };
in
{
  options.homelab.apps.slskd = {
    downloadGroup = lib.mkOption {
      type = lib.types.str;
      default = native.group;
      description = "Group for managed download directories.";
    };
    downloadDirectoryMode = lib.mkOption {
      type = lib.types.strMatching "[0-7]{4}";
      default = "0770";
      description = "Mode for managed download directories; use 2770 with a shared media group.";
    };
    downloadsDir = lib.mkOption {
      type = pathType;
      default = "/var/lib/slskd/downloads";
      description = "Completed downloads visible at the same path to importing applications.";
    };
    incompleteDir = lib.mkOption {
      type = pathType;
      default = "/var/lib/slskd/incomplete";
      description = "Incomplete transfers; place alongside downloads on the media filesystem.";
    };
    requiredMounts = lib.mkOption {
      type = lib.types.listOf pathType;
      default = lib.optionals sharedStorage config.homelab.storage.requiredMounts;
      description = "Actual download mount points. Missing mounts prevent directory preparation and fallback writes.";
    };
    preparationUnit = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9_.-]*";
      default = "homelab-slskd-directories";
      description = "Directory preparation service name, without .service.";
    };
    credentialsFile = lib.mkOption {
      type = lib.types.nullOr pathType;
      default = null;
      description = ''
        Runtime environment file containing Soulseek, web and API credentials.
        Required when enabled. Supply it through a secret manager; never use a
        Nix store path.
      '';
    };
    webPort = lib.mkOption {
      type = lib.types.port;
      default = 5030;
      description = "Private slskd web and API port on the namespace host link.";
    };
    peerPort = lib.mkOption {
      type = lib.types.port;
      default = 50300;
      description = "Soulseek peer port inside the VPN namespace.";
    };
    vpn = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Confine all Soulseek traffic and DNS in the homelab VPN namespace.";
      };
      allowUnconfined = lib.mkEnableOption "an explicit direct-network slskd deployment";
      allowInbound = lib.mkEnableOption "a peer port forwarded by the VPN provider";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.preparationUnit != "slskd" && (!sharedStorage || cfg.preparationUnit != "homelab-storage");
        message = "slskd preparationUnit must not create a service dependency cycle.";
      }
      {
        assertion = builtins.match "[0-3]7[0-7]0" cfg.downloadDirectoryMode != null;
        message = "slskd downloadDirectoryMode requires owner access and no world permissions.";
      }
      {
        assertion = cfg.credentialsFile != null && !(lib.hasPrefix "/nix/store" cfg.credentialsFile);
        message = "slskd needs an absolute runtime credentialsFile outside the Nix store.";
      }
      {
        assertion = cfg.vpn.enable || cfg.vpn.allowUnconfined;
        message = "slskd requires VPN confinement unless homelab.apps.slskd.vpn.allowUnconfined is explicitly enabled.";
      }
      {
        assertion = !cfg.vpn.enable || vpn.enable;
        message = "VPN-confined slskd requires homelab.vpn.enable.";
      }
      {
        assertion = !cfg.vpn.allowInbound || cfg.vpn.enable;
        message = "slskd peer ingress requires VPN confinement and provider port forwarding.";
      }
      {
        assertion =
          !cfg.vpn.enable
          || (
            config.systemd.services.slskd.vpn.enable
            && config.systemd.services.slskd.vpn.namespace == vpn.namespace.name
            && config.services.vpnConfinement.namespaces.${vpn.namespace.name}.servicePolicy == "enforced"
            && config.services.vpnConfinement.namespaces.${vpn.namespace.name}.dns.mode == "strict"
            && !config.services.vpnConfinement.namespaces.${vpn.namespace.name}.dns.allowHostResolverIPC
            && config.services.vpnConfinement.namespaces.${vpn.namespace.name}.wireguard.endpointPinning.enable
          );
        message = "slskd requires the enforced VPN service policy, strict tunnel DNS and a pinned WireGuard endpoint.";
      }
      {
        assertion =
          config.services.slskd.settings.web.ip_address == webAddress && !config.services.slskd.openFirewall;
        message = "slskd must bind its web API to the private host link and keep the host firewall closed.";
      }
      {
        assertion =
          config.services.slskd.settings.directories.downloads == downloads
          && config.services.slskd.settings.directories.incomplete == incomplete;
        message = "slskd directory settings must match the managed download paths.";
      }
      {
        assertion =
          lib.all dedicatedPath [
            downloads
            incomplete
          ]
          && downloads != incomplete
          &&
            lib.all
              (
                path:
                !(lib.hasPrefix "/nix/store" path)
                && !(lib.hasInfix "/../" "${path}/")
                && !(lib.hasInfix "/./" "${path}/")
              )
              [
                downloads
                incomplete
              ];
        message = "slskd needs distinct canonical writable download and incomplete paths outside the store.";
      }
    ];

    services.slskd = {
      environmentFile =
        if cfg.credentialsFile == null then "/run/missing-slskd-credentials" else cfg.credentialsFile;
      openFirewall = false;
      settings = {
        remote_configuration = false;
        directories = { inherit downloads incomplete; };
        shares.directories = lib.mkDefault [ ];
        web = {
          ip_address = webAddress;
          port = cfg.webPort;
          https.disabled = true;
          authentication.disabled = false;
        };
        soulseek.listen_port = cfg.peerPort;
      };
    };

    # Prepare paths after checking actual mounts, before systemd constructs the
    # application's ReadWritePaths namespace. Global tmpfiles run too early.
    systemd.services.${cfg.preparationUnit} = {
      description = "Prepare protected Soulseek downloads on their required mounts";
      requires = lib.optional sharedStorage "homelab-storage.service";
      after = lib.optional sharedStorage "homelab-storage.service";
      before = [ "slskd.service" ];
      unitConfig.RequiresMountsFor = cfg.requiredMounts ++ [
        downloads
        incomplete
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0007";
      };
      script =
        lib.concatMapStringsSep "\n" (
          path: "${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg path}"
        ) cfg.requiredMounts
        + "\n"
        + lib.escapeShellArgs [
          "${pkgs.python3}/bin/python3"
          "${../../scripts/storage/prepare.py}"
          "--owner"
          native.user
          "--mode"
          cfg.downloadDirectoryMode
          cfg.downloadGroup
          downloads
          incomplete
        ];
    };
    systemd.services.slskd = {
      requires = [ "${cfg.preparationUnit}.service" ];
      after = [ "${cfg.preparationUnit}.service" ];
      unitConfig.RequiresMountsFor = [
        downloads
        incomplete
      ];
      vpn = {
        inherit (cfg.vpn) enable;
        namespace = vpn.namespace.name;
      };
      serviceConfig = {
        ExecStartPre = [ "${checkCredentials}/bin/homelab-slskd-check-credentials" ];
        SupplementaryGroups = [ cfg.downloadGroup ];
        StateDirectoryMode = "0770";
        UMask = "0007";
      };
    };
    # Lidarr may read completed downloads without granting slskd access to
    # the media library or sharing that library with Soulseek peers.
    users.users = lib.mkIf config.homelab.apps.lidarr.enable {
      ${config.services.lidarr.user}.extraGroups = [ cfg.downloadGroup ];
    };
    homelab.vpn = lib.mkIf cfg.vpn.enable {
      namespace.hostIngressPorts.tcp = [ cfg.webPort ];
      inboundPorts.tcp = lib.mkIf cfg.vpn.allowInbound [ cfg.peerPort ];
    };
  };
}
