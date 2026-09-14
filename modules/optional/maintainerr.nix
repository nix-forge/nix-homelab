{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.maintainerr;
  enabled = config.homelab.optional.apps.maintainerr.enable;
  user = "homelab-maintainerr";
  stateDir = "/var/lib/homelab-maintainerr";
  credential = "/run/credentials/nginx.service/homelab-maintainerr-auth";
  readiness = pkgs.writeShellApplication {
    name = "maintainerr-wait-ready";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      for attempt in $(seq 1 60); do
        if curl --fail --silent --max-time 5 \
          http://127.0.0.1:${toString cfg.backendPort}/api/health/ready >/dev/null; then
          exit 0
        fi
        if [ "$attempt" -lt 60 ]; then
          sleep 1
        fi
      done
      printf '%s\n' 'Maintainerr did not become ready within 60 seconds.' >&2
      exit 1
    '';
  };
in
{
  options.homelab.optional = {
    maintainerr = {
      uid = lib.mkOption {
        type = lib.types.ints.positive;
        default = 62460;
        description = "Dedicated service UID; choose an unused host UID. Used numerically in the firewall ruleset.";
      };
      package = lib.mkPackageOption pkgs "maintainerr" { };
      htpasswdFile = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
        default = null;
        description = "User-provided nix-seal htpasswd file for HTTP Basic authentication. Use TLS when exposing the proxy beyond loopback.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 6246;
        description = "Authenticated loopback proxy port.";
      };
      backendPort = lib.mkOption {
        type = lib.types.port;
        default = 6247;
        description = "Loopback service port, restricted to nginx, root and the Maintainerr account by nftables.";
      };
    };
  };
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = cfg.htpasswdFile != null && !(lib.hasPrefix "/nix/store/" cfg.htpasswdFile);
        message = "Maintainerr requires a user-provided runtime htpasswdFile outside the Nix store.";
      }
      {
        assertion = cfg.port != cfg.backendPort;
        message = "Maintainerr authenticated and backend ports must differ.";
      }
    ];
    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      inherit (cfg) uid;
      group = user;
      home = stateDir;
      homeMode = "0700";
      createHome = true;
    };
    networking.nftables = {
      enable = true;
      tables.homelab-maintainerr = {
        family = "inet";
        content = ''
          chain backend_access {
            type filter hook output priority 0; policy accept;
            ip daddr 127.0.0.1 tcp dport ${toString cfg.backendPort} meta skuid != { 0, ${
              toString config.users.users.${config.services.nginx.user}.uid
            }, ${toString cfg.uid} } reject
          }
        '';
      };
    };
    # Preserve URLs saved while the service used rootless Podman's host alias.
    networking.hosts."127.0.0.1" = [ "host.containers.internal" ];
    services.nginx = {
      enable = true;
      virtualHosts.homelab-maintainerr = {
        listen = [
          {
            addr = "127.0.0.1";
            inherit (cfg) port;
          }
        ];
        basicAuthFile = credential;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
          extraConfig = ''
            proxy_buffering off;
            proxy_set_header Authorization "";
            proxy_set_header Host $host:$server_port;
            proxy_set_header X-Forwarded-Host $host:$server_port;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For $remote_addr;
          '';
        };
      };
    };
    systemd = {
      services = {
        homelab-maintainerr = {
          description = "Maintainerr media-library maintenance";
          wantedBy = [ "multi-user.target" ];
          after = [ "nftables.service" ];
          requires = [ "nftables.service" ];
          bindsTo = [ "nftables.service" ];
          partOf = [ "nftables.service" ];
          environment = {
            DATA_DIR = "${stateDir}/data";
            NODE_ENV = "production";
            UI_HOSTNAME = "127.0.0.1";
            UI_PORT = toString cfg.backendPort;
            TELEMETRY = "off";
            UV_USE_IO_URING = "0";
            VERSION_TAG = "stable";
          };
          serviceConfig = {
            Type = "simple";
            User = user;
            Group = user;
            ExecStart = lib.getExe cfg.package;
            ExecStartPost = lib.getExe readiness;
            Restart = "on-failure";
            RestartSec = "5s";
            TimeoutStartSec = "90s";
            TimeoutStopSec = "30s";

            StateDirectory = "homelab-maintainerr";
            StateDirectoryMode = "0700";
            UMask = "0077";

            AmbientCapabilities = "";
            CapabilityBoundingSet = "";
            DevicePolicy = "closed";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RemoveIPC = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";

            CPUQuota = "100%";
            CPUWeight = 25;
            IOWeight = 25;
            MemoryMax = "1G";
            Nice = 10;
            TasksMax = 256;
          };
        };
        nginx.serviceConfig.LoadCredential = lib.optional (
          cfg.htpasswdFile != null
        ) "homelab-maintainerr-auth:${cfg.htpasswdFile}";
      };
    };
  };
}
