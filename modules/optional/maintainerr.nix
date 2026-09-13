{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.maintainerr;
  enabled = config.homelab.optional.apps.maintainerr.enable;
  container = "homelab-maintainerr";
  user = "homelab-maintainerr";
  stateDir = "/var/lib/homelab-maintainerr";
  imageName = "ghcr.io/maintainerr/maintainerr";
  imagePins = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-qd4fKtC9lUD5vPg4nzZbEK5DAd2dHX93gJlZZXtRloA=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-CqMk1JLXMgEoIAUrhzaWLRNS9rtYseXo/anriKELSGc=";
    };
  };
  credential = "/run/credentials/nginx.service/homelab-maintainerr-auth";
in
{
  options.homelab.optional = {
    apps.maintainerr.enable = lib.mkEnableOption "Maintainerr behind mandatory authenticated private access";
    maintainerr = {
      uid = lib.mkOption {
        type = lib.types.ints.positive;
        default = 62460;
        description = "Dedicated rootless container UID; choose an unused host UID. Used numerically in the firewall ruleset.";
      };
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
        description = "Loopback container port, restricted to nginx, root and the container account by nftables.";
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
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "The Maintainerr adapter requires rootless Podman.";
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
      autoSubUidGidRange = true;
      linger = true;
    };
    virtualisation.podman.extraPackages = [ pkgs.slirp4netns ];
    virtualisation.oci-containers = {
      backend = lib.mkDefault "podman";
      containers.${container} = {
        # Upstream 3.28.0 multi-architecture release manifest, not a moving tag.
        image = "${imageName}:3.28.0";
        pull = "never";
        imageFile = pkgs.dockerTools.pullImage (
          {
            inherit imageName;
            imageDigest = "sha256:c39df453c05b174a6cb0870b4a50acdc844b179da7518e74a847c3e7aaf7c0e7";
            os = "linux";
            finalImageName = imageName;
            finalImageTag = "3.28.0";
          }
          // imagePins.${pkgs.stdenv.hostPlatform.system}
        );
        user = "1000:1000";
        podman = {
          inherit user;
          sdnotify = "conmon";
        };
        networks = [ "slirp4netns:allow_host_loopback=true" ];
        ports = [ "127.0.0.1:${toString cfg.backendPort}:6246" ];
        # U maps container ownership into this dedicated rootless user's subuids.
        volumes = [ "${stateDir}/data:/opt/data:U" ];
        environment = {
          UI_HOSTNAME = "0.0.0.0";
          UI_PORT = "6246";
          TELEMETRY = "off";
        };
        extraOptions = [
          "--add-host=host.containers.internal:10.0.2.2"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          "--read-only"
          "--tmpfs=/tmp:rw,nosuid,nodev,size=64m"
          "--memory=1g"
          "--cpus=1"
          "--pids-limit=256"
          "--health-cmd=/opt/app/healthcheck.sh"
          "--health-interval=30s"
          "--health-timeout=5s"
          "--health-start-period=60s"
        ];
      };
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
          proxyWebsockets = true;
          extraConfig = ''
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
      tmpfiles.rules = [ "d ${stateDir}/data 0700 ${user} ${user} -" ];
      services = {
        "podman-${container}" = {
          after = [ "nftables.service" ];
          requires = [ "nftables.service" ];
          bindsTo = [ "nftables.service" ];
          partOf = [ "nftables.service" ];
          serviceConfig = {
            CPUWeight = 25;
            IOWeight = 25;
            Nice = 10;
          };
        };
        nginx.serviceConfig.LoadCredential = lib.optional (
          cfg.htpasswdFile != null
        ) "homelab-maintainerr-auth:${cfg.htpasswdFile}";
      };
    };
  };
}
