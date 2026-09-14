{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.audiomuse-ai;
  stateDir = "/var/lib/${cfg.stateDirectory}";
  cacheDir = "/var/cache/${cfg.cacheDirectory}";
  roles = [
    {
      name = "flask";
      command = "audiomuse-ai-web";
    }
    {
      name = "queue-worker-high";
      command = "audiomuse-ai-worker-high";
      priority = 20;
    }
    {
      name = "queue-worker-default";
      command = "audiomuse-ai-worker-default";
      priority = 20;
    }
    {
      name = "queue-maintenance";
      command = "audiomuse-ai-maintenance";
      priority = 30;
    }
    {
      name = "config-restart-listener";
      command = "audiomuse-ai-control";
      priority = 40;
    }
  ];
  renderRole = role: ''
    [program:${role.name}]
    command=${cfg.package}/bin/${role.command}
    ${lib.optionalString (role ? priority) "priority=${toString role.priority}"}
    autostart=true
    autorestart=true
    stopsignal=TERM
    stopasgroup=true
    killasgroup=true
    stopwaitsecs=30
    stdout_logfile=NONE
    stdout_syslog=true
    stderr_logfile=NONE
    stderr_syslog=true
  '';
  supervisorConfig = pkgs.writeText "audiomuse-ai-supervisord.conf" ''
    [supervisord]
    nodaemon=true
    logfile=/dev/null
    logfile_maxbytes=0
    pidfile=/run/audiomuse-ai/supervisord.pid
    childlogdir=/run/audiomuse-ai

    [unix_http_server]
    file=/run/audiomuse-ai/supervisor.sock
    chmod=0600

    [supervisorctl]
    serverurl=unix:///run/audiomuse-ai/supervisor.sock

    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

    ${lib.concatMapStringsSep "\n" renderRole roles}
  '';
  readiness = pkgs.writeShellApplication {
    name = "audiomuse-ai-wait-ready";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      for attempt in $(seq 1 120); do
        if curl --fail --silent --max-time 5 \
          http://${cfg.host}:${toString cfg.port}/api/health/ready >/dev/null; then
          exit 0
        fi
        if [ "$attempt" -lt 120 ]; then
          sleep 1
        fi
      done
      printf '%s\n' 'AudioMuse-AI did not become ready within 120 seconds.' >&2
      exit 1
    '';
  };
  protectedEnvironment = {
    APP_DATA_DIR = stateDir;
    AUDIO_MUSE_LISTENER_ID = config.networking.hostName;
    AUDIOMUSE_HOST = cfg.host;
    AUDIOMUSE_PORT = toString cfg.port;
    BACKUP_DIR = "${stateDir}/backups";
    DATABASE_TYPE = "postgres";
    DISABLE_FLASK_RESTART = "false";
    IVF_DISK_CACHE_DIR = "${cacheDir}/ivf";
    NUMBA_CACHE_DIR = "${cacheDir}/numba";
    ORT_DISABLE_AVX512 = "1";
    ORT_DISABLE_MEMORY_PATTERN_OPTIMIZATION = "1";
    ORT_FORCE_SHARED_PROVIDER = "1";
    PLUGIN_ALLOW_PIP = "false";
    PLUGINS_DIR = "${stateDir}/plugins";
    POSTGRES_DB = cfg.database.name;
    POSTGRES_HOST = "/run/postgresql";
    POSTGRES_PASSWORD = "";
    POSTGRES_PORT = "5432";
    POSTGRES_USER = cfg.database.name;
    RESTORE_LOG_DIR = "${stateDir}/backups";
    SUPERVISOR_CONF = supervisorConfig;
    SUPERVISORCTL_CMD = "${pkgs.python3Packages.supervisor}/bin/supervisorctl";
    TEMP_DIR = "${cacheDir}/temp-audio";
  };
  overriddenProtectedEnvironment = lib.intersectLists (builtins.attrNames protectedEnvironment) (
    builtins.attrNames cfg.extraEnvironment
  );
  serviceLauncher = pkgs.writeShellScript "audiomuse-ai-start" ''
    ${lib.concatMapStringsSep "\n" (
      name: "export ${name}=${lib.escapeShellArg protectedEnvironment.${name}}"
    ) (builtins.attrNames protectedEnvironment)}
    exec ${pkgs.python3Packages.supervisor}/bin/supervisord -c ${supervisorConfig}
  '';
in
{
  options.services.audiomuse-ai = {
    enable = lib.mkEnableOption "native AudioMuse-AI music discovery";
    package = lib.mkPackageOption pkgs "audiomuse-ai" { };
    user = lib.mkOption {
      type = lib.types.str;
      default = "audiomuse";
      description = "System user and PostgreSQL role used by AudioMuse-AI.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "audiomuse";
      description = "Primary group used by AudioMuse-AI.";
    };
    host = lib.mkOption {
      type = lib.types.enum [
        "127.0.0.1"
        "::1"
        "localhost"
      ];
      default = "127.0.0.1";
      description = "Address for the unauthenticated AudioMuse-AI backend listener.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port for the AudioMuse-AI backend listener.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Runtime environment file containing AudioMuse-AI secrets.";
    };
    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret environment variables passed to every AudioMuse-AI role.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_.-]+";
      default = "audiomuse-ai";
      description = "Name below /var/lib used for persistent application and plugin data.";
    };
    cacheDirectory = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_.-]+";
      default = "audiomuse-ai";
      description = "Name below /var/cache used for replaceable analysis data.";
    };
    database = {
      name = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_-]+";
        default = "audiomusedb";
        description = "Local PostgreSQL database name.";
      };
      package = lib.mkPackageOption pkgs "postgresql_15" { };
    };
    resources = {
      cpuQuota = lib.mkOption {
        type = lib.types.str;
        default = "800%";
        description = "systemd CPUQuota for the complete AudioMuse-AI process group.";
      };
      memoryMax = lib.mkOption {
        type = lib.types.str;
        default = "12G";
        description = "systemd MemoryMax for the complete AudioMuse-AI process group.";
      };
      tasksMax = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1024;
        description = "Maximum process and thread count for AudioMuse-AI.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.environmentFile == null || !lib.hasPrefix "/nix/store/" cfg.environmentFile;
        message = "services.audiomuse-ai.environmentFile must stay outside the Nix store.";
      }
      {
        assertion = overriddenProtectedEnvironment == [ ];
        message = "services.audiomuse-ai.extraEnvironment cannot override protected settings: ${lib.concatStringsSep ", " overriddenProtectedEnvironment}";
      }
    ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = stateDir;
      createHome = false;
    };

    services.postgresql = {
      enable = true;
      package = cfg.database.package;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.name;
          ensureDBOwnership = true;
        }
      ];
      identMap = ''
        audiomuse-ai ${cfg.user} ${cfg.database.name}
      '';
      authentication = lib.mkBefore ''
        local ${cfg.database.name} ${cfg.database.name} peer map=audiomuse-ai
      '';
    };

    systemd.services.audiomuse-ai = {
      description = "AudioMuse-AI music discovery";
      wantedBy = [ "multi-user.target" ];
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
      environment = cfg.extraEnvironment;
      path = [ cfg.database.package ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        # Set module-owned safety and topology values after EnvironmentFile is
        # loaded so runtime secret files cannot weaken these invariants.
        ExecStart = serviceLauncher;
        ExecStartPost = lib.getExe readiness;
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "150s";
        TimeoutStopSec = "90s";

        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        CacheDirectory = cfg.cacheDirectory;
        CacheDirectoryMode = "0700";
        RuntimeDirectory = "audiomuse-ai";
        RuntimeDirectoryMode = "0700";
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

        CPUQuota = cfg.resources.cpuQuota;
        CPUWeight = 25;
        IOWeight = 25;
        MemoryMax = cfg.resources.memoryMax;
        Nice = 10;
        TasksMax = cfg.resources.tasksMax;
      };
    };
  };
}
