{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3.withPackages (_: [ pkgs.notification-process ]);
  cfg = config.homelab.operations;
  health = cfg.monitoring.health;
  integrations = lib.attrByPath [ "homelab" "integration" "services" ] { } config;
  vpn = lib.attrByPath [ "homelab" "vpn" ] { enable = false; } config;
  backupConfiguration =
    if cfg.backup.job == null then { } else config.services.restic.backups.${cfg.backup.job};
  localRepository =
    if
      backupConfiguration ? repository
      && builtins.isString backupConfiguration.repository
      && lib.hasPrefix "/" backupConfiguration.repository
    then
      backupConfiguration.repository
    else
      null;
  loopbackPort =
    endpoint:
    let
      matched = builtins.match "https?://(127[.][0-9]+[.][0-9]+[.][0-9]+|localhost|[[]::1[]]):([0-9]+).*" endpoint.url;
    in
    if matched == null then null else lib.toInt (builtins.elemAt matched 1);
  privateTcpPorts = lib.unique (
    lib.filter (port: port != null && !builtins.elem port health.firewallProtectedTcpPorts) (
      map loopbackPort (lib.attrValues cfg.endpoints)
    )
  );
  specificationData = {
    inherit (health) port;
    pressureMaxAge = health.pressureMaxAgeSeconds;
    pressureFile = if cfg.pressure.enable then "/var/lib/homelab-monitoring/pressure" else null;
    backup = cfg.backup.job != null;
    stamp = "/var/lib/homelab-monitoring/last-backup";
    maxAge = health.backupMaxAgeSeconds;
    path = cfg.pressure.path;
    mounts = cfg.pressure.requiredMounts;
    minimumFree = cfg.pressure.pauseBytes;
    units =
      (lib.optionals (lib.attrByPath [ "homelab" "integration" "enable" ] false config) (
        map (name: "homelab-integrate-${name}.service") (builtins.attrNames integrations)
      ))
      ++ lib.optional cfg.pressure.enable "homelab-storage-pressure.service"
      ++ lib.optional (cfg.backup.job != null) "restic-backups-${cfg.backup.job}.service";
  };
  specification = pkgs.writeText "homelab-operational-health.json" (
    builtins.toJSON specificationData
  );
  doctorSpecification = pkgs.writeText "homelab-doctor.json" (
    builtins.toJSON (
      specificationData
      // {
        hardlinkPaths = lib.optionals config.homelab.storage.enable [
          config.homelab.storage.downloadsDir
          config.homelab.storage.libraryDir
        ];
        inherit privateTcpPorts;
        backupRepositoryPath = localRepository;
        backupStagingPath = if localRepository == null then null else cfg.backup.stagingDir;
        vpn = lib.optionalAttrs vpn.enable {
          namespace = vpn.namespace.name;
          interface = vpn.interface.name;
          maxHandshakeAge = health.vpnMaxHandshakeAgeSeconds;
          dnsProbeHost = health.vpnDnsProbeHost;
        };
      }
    )
  );
  doctor = pkgs.writeShellApplication {
    name = "homelab-doctor";
    runtimeInputs = [
      pkgs.glibc.bin
      pkgs.iproute2
      python
      pkgs.systemd
      pkgs.wireguard-tools
    ];
    text = (import ../../lib/render-text.nix) ./scripts/homelab-doctor.sh {
      scripts_operations_health_py = ../../scripts/operations/health.py;
      inherit doctorSpecification;
    };
  };
in
{
  options.homelab.operations.monitoring.health = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Publish private backup, storage and job health when monitoring is enabled.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9086;
      description = "Loopback-only operational health port.";
    };
    firewallProtectedTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports whose non-loopback listeners are protected by host firewall rules, excluded from loopback listener checks.";
    };
    pressureMaxAgeSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Maximum pressure-marker age; increase when overriding the native pressure timer interval.";
    };
    backupMaxAgeSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 36 * 60 * 60;
      description = "Maximum age of a fully successful Restic unit before health fails.";
    };
    vpnMaxHandshakeAgeSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Maximum age of the newest WireGuard peer handshake accepted by homelab-doctor.";
    };
    vpnDnsProbeHost = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9.-]+";
      default = "example.com";
      description = "Public hostname resolved inside the VPN namespace by homelab-doctor.";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable { environment.systemPackages = [ doctor ]; })
    (lib.mkIf (cfg.enable && cfg.monitoring.enable && health.enable) (
      lib.mkMerge [
        {
          users.groups.${config.homelab.storage.group} = { };
          users.groups.homelab-monitoring = { };
          systemd.tmpfiles.rules = [ "d /var/lib/homelab-monitoring 2770 root homelab-monitoring -" ];
          systemd.services.homelab-operational-health = {
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.systemd ];
            serviceConfig = {
              ExecStart = "${lib.getExe python} ${../../scripts/operations/health.py} ${specification}";
              DynamicUser = true;
              SupplementaryGroups = [
                config.homelab.storage.group
                "homelab-monitoring"
              ];
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              RestrictAddressFamilies = [
                "AF_UNIX"
                "AF_INET"
              ];
              MemoryMax = "96M";
              TasksMax = 16;
            };
          };
          services.gatus.settings.endpoints = [
            {
              name = "operational-health";
              url = "http://127.0.0.1:${toString health.port}/health";
              interval = "1m";
              conditions = [ "[STATUS] == 200" ];
              alerts = map (type: { inherit type; }) cfg.monitoring.alerts;
            }
          ];
        }
        (lib.mkIf cfg.pressure.enable {
          systemd.services.homelab-storage-pressure = {
            serviceConfig.SupplementaryGroups = [ "homelab-monitoring" ];
            serviceConfig.ReadWritePaths = [ "/var/lib/homelab-monitoring" ];
            postStart = "${lib.getExe python} ${../../scripts/operations/health.py} --publish-pressure /var/lib/homelab-storage-pressure/state.json /var/lib/homelab-monitoring/pressure";
          };
        })
        (lib.mkIf (cfg.backup.job != null) {
          systemd.services."restic-backups-${cfg.backup.job}".onSuccess = [
            "homelab-backup-success.service"
          ];
          systemd.services.homelab-backup-success = {
            serviceConfig.Type = "oneshot";
            script = "${pkgs.coreutils}/bin/touch /var/lib/homelab-monitoring/last-backup";
          };
        })
      ]
    ))
  ];
}
