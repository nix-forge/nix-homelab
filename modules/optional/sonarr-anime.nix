{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.sonarr-anime;
  stateDir = "/var/lib/homelab-sonarr-anime";
  user = "homelab-sonarr-anime";
in
{
  options.services.sonarr-anime = {
    enable = lib.mkEnableOption "an independent Sonarr instance for anime";
    package = lib.mkPackageOption pkgs "sonarr" { };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8990;
      description = "Loopback API port for the independent anime instance.";
    };
    environmentFiles = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "/[A-Za-z0-9_./-]+");
      default = [ ];
      description = "Runtime environment files for secret Sonarr settings, installed before service start.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.optional.apps.sonarr-anime.enable;
        message = "Enable Sonarr Anime through homelab.optional.apps.sonarr-anime so storage and recovery policy apply.";
      }
      {
        assertion =
          !config.services.sonarr.enable || cfg.port != config.services.sonarr.settings.server.port;
        message = "Sonarr Anime and Sonarr require distinct API ports.";
      }
      {
        assertion = lib.all (
          path: !(lib.hasPrefix "/nix/store/" path) && !(lib.hasInfix "/../" "${path}/")
        ) cfg.environmentFiles;
        message = "Sonarr Anime environment files must be runtime paths outside the Nix store.";
      }
    ];
    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      home = stateDir;
    };
    systemd.services.sonarr-anime = {
      description = "Sonarr Anime";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        SONARR__APP__INSTANCENAME = "Sonarr Anime";
        SONARR__SERVER__BINDADDRESS = "127.0.0.1";
        SONARR__SERVER__PORT = toString cfg.port;
        SONARR__UPDATE__MECHANISM = "external";
        SONARR__UPDATE__AUTOMATICALLY = "false";
        SONARR__LOG__ANALYTICSENABLED = "false";
      };
      unitConfig.RequiresMountsFor = [ stateDir ];
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = user;
        StateDirectory = "homelab-sonarr-anime";
        StateDirectoryMode = "0700";
        EnvironmentFile = cfg.environmentFiles;
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe cfg.package)
          "-nobrowser"
          "-data=${stateDir}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@debug"
          "~@mount"
          "@chown"
        ];
        ReadWritePaths = [ stateDir ];
        UMask = lib.mkDefault "0007";
      };
    };
  };
}
