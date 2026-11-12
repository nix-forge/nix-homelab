{
  config,
  lib,
  pkgs,
  ...
}:
let
  selectedPostgresSocket = (import ../lib/postgresql-socket.nix) lib config.services.postgresql.settings;
  postgresSocket =
    if selectedPostgresSocket == null then "/run/postgresql" else selectedPostgresSocket;
  cfg = config.services.wardrowbe;
  inherit (lib) mkOption types;
  ollamaHost = config.services.ollama.host;
  ollamaAddress =
    if ollamaHost == "0.0.0.0" then
      "127.0.0.1"
    else if ollamaHost == "::" then
      "[::1]"
    else if lib.hasInfix ":" ollamaHost then
      "[${ollamaHost}]"
    else
      ollamaHost;
  aiBaseUrl =
    if cfg.ai.provider == "codex" then
      "http://127.0.0.1:${toString cfg.ai.codex.port}/v1"
    else if cfg.ai.provider == "ollama" then
      "http://${ollamaAddress}:${toString config.services.ollama.port}/v1"
    else
      lib.removeSuffix "/" cfg.ai.baseUrl;
  backendDirectory = "${cfg.backendPackage}/libexec/wardrowbe-backend";
  protectedEnvironment = {
    APP_URL = cfg.publicUrl;
    DATABASE_URL = "postgresql+asyncpg://${cfg.databaseName}@localhost:${toString config.services.postgresql.settings.port}/${cfg.databaseName}?host=${postgresSocket}";
    REDIS_URL = "unix://${cfg.redisSocket}";
    STORAGE_PATH = "/var/lib/wardrowbe/uploads";
    OIDC_ISSUER_URL = cfg.oidc.issuerUrl;
    AI_INTERNAL_ENABLED = lib.boolToString cfg.ai.enable;
    AI_BASE_URL = aiBaseUrl;
    AI_VISION_MODEL = cfg.ai.visionModel;
    AI_TEXT_MODEL = cfg.ai.textModel;
    AI_TIMEOUT = toString cfg.ai.timeout;
    AI_TAGGING_CONCURRENCY = toString cfg.ai.concurrency;
    IMAGE_WORKER_CONCURRENCY = toString cfg.imageWorkerConcurrency;
    U2NET_HOME = "/var/cache/wardrowbe/rembg";
    NUMBA_CACHE_DIR = "/var/cache/wardrowbe/numba";
  }
  // lib.optionalAttrs (cfg.oidc.clientId != null) { OIDC_CLIENT_ID = cfg.oidc.clientId; };
  sharedEnvironment = protectedEnvironment // cfg.extraEnvironment;
  secretEnvironmentNames = [
    "SECRET_KEY"
    "NEXTAUTH_SECRET"
    "OIDC_CLIENT_SECRET"
    "AI_API_KEY"
    "NTFY_TOKEN"
    "SMTP_PASSWORD"
    "BG_REMOVAL_API_KEY"
  ];
  commonService = {
    User = "wardrowbe";
    Group = "wardrowbe";
    SupplementaryGroups = [ "redis-wardrowbe" ];
    EnvironmentFile = cfg.environmentFile;
    StateDirectory = "wardrowbe";
    CacheDirectory = "wardrowbe";
    WorkingDirectory = backendDirectory;
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    UMask = "0077";
  };
  worker = name: command: memory: {
    description = "Wardrowbe ${name} worker";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "wardrowbe-migrate.service"
      "redis-wardrowbe.service"
    ];
    after = [
      "wardrowbe-migrate.service"
      "redis-wardrowbe.service"
    ];
    environment = sharedEnvironment;
    serviceConfig = commonService // {
      ExecStart = "${cfg.backendPackage}/bin/${command}";
      Restart = "on-failure";
      RestartSec = 5;
      MemoryMax = memory;
    };
  };
  backupScript = pkgs.writeShellScript "wardrowbe-backup" (
    (import ../../lib/render-text.nix) ./scripts/wardrowbe-backup.sh {
      postgresSocket = lib.escapeShellArg postgresSocket;
      postgresPort = toString config.services.postgresql.settings.port;
      lib_getExe_config_services_postgresql_package_pg_dump = lib.getExe' config.services.postgresql.package "pg_dump";
      lib_escapeShellArg_cfg_databaseName = lib.escapeShellArg cfg.databaseName;
    }
  );
in
{
  imports = [ ./wardrowbe-codex.nix ];
  options.services.wardrowbe = {
    enable = lib.mkEnableOption "native Wardrowbe wardrobe planner";
    backendPackage = lib.mkPackageOption pkgs "wardrowbe-backend" { };
    frontendPackage = lib.mkPackageOption pkgs "wardrowbe-frontend" { };
    publicUrl = mkOption {
      type = types.strMatching "https://[^/?#@[:space:]]+(/[^?#[:space:]]*[^/?#[:space:]])?";
      example = "https://wardrobe.example.org";
      description = "Externally reachable HTTPS URL used for callbacks and links.";
    };
    environmentFile = mkOption {
      type = types.strMatching "/[A-Za-z0-9_./-]+";
      description = "Runtime file containing SECRET_KEY, NEXTAUTH_SECRET and OIDC_CLIENT_SECRET.";
    };
    oidc = {
      issuerUrl = mkOption {
        type = types.strMatching "https://[^/?#@[:space:]]+(/[^?#[:space:]]*[^/?#[:space:]])?";
        example = "https://identity.example.org";
        description = "OIDC discovery issuer; any conforming provider can be used.";
      };
      clientId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Public OIDC client identifier, or null when OIDC_CLIENT_ID is supplied by environmentFile.";
      };
      tokenEndpointAuthMethod = mkOption {
        type = types.enum [
          "client_secret_basic"
          "client_secret_post"
        ];
        default = "client_secret_basic";
        description = "How NextAuth authenticates to the OIDC token endpoint.";
      };
      endSessionUrl = mkOption {
        type = types.nullOr (types.strMatching "https://[^/]+/.*");
        default = null;
        description = "Optional provider logout endpoint for a complete single sign-out.";
      };
    };
    databaseName = mkOption {
      type = types.strMatching "[A-Za-z_][A-Za-z0-9_]*";
      default = "wardrowbe";
      description = "Local PostgreSQL database and peer-authenticated role.";
    };
    backendPort = mkOption {
      type = types.port;
      default = 18180;
      description = "Loopback API port.";
    };
    frontendPort = mkOption {
      type = types.port;
      default = 18181;
      description = "Loopback web port.";
    };
    redisSocket = mkOption {
      type = types.strMatching "/[A-Za-z0-9_./-]+";
      default = "/run/redis-wardrowbe/redis.sock";
      description = "Private Unix socket for the Redis job queue.";
    };
    ai = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable internal AI tagging and suggestions.";
      };
      provider = mkOption {
        type = types.enum [
          "compatible"
          "openai"
          "ollama"
          "codex"
        ];
        default = "compatible";
        description = "AI transport: compatible endpoint, OpenAI API key, native Ollama, or Codex ChatGPT OAuth.";
      };
      baseUrl = mkOption {
        type = types.str;
        default = if cfg.ai.provider == "openai" then "https://api.openai.com/v1" else "";
        example = "http://127.0.0.1:11434/v1";
        description = "OpenAI-compatible AI endpoint.";
      };
      visionModel = mkOption {
        type = types.str;
        default =
          if
            builtins.elem cfg.ai.provider [
              "openai"
              "codex"
            ]
          then
            ""
          else
            "gemma3:4b";
        description = "Vision model for clothing analysis.";
      };
      textModel = mkOption {
        type = types.str;
        default =
          if
            builtins.elem cfg.ai.provider [
              "openai"
              "codex"
            ]
          then
            ""
          else
            "gemma3:4b";
        description = "Text model for outfit suggestions.";
      };
      timeout = mkOption {
        type = types.ints.positive;
        default = 300;
        description = "AI request timeout in seconds.";
      };
      concurrency = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "Maximum simultaneous AI jobs.";
      };
    };
    imageWorkerConcurrency = mkOption {
      type = types.ints.positive;
      default = 1;
      description = "Maximum simultaneous image processing jobs.";
    };
    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional non-secret backend and worker settings.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = selectedPostgresSocket != null;
        message = "Wardrowbe requires a canonical filesystem PostgreSQL socket directory.";
      }
      {
        assertion = !cfg.ai.enable || cfg.ai.provider != "codex" || cfg.ai.codex.enable;
        message = "The Codex default provider requires the Codex adapter.";
      }
      {
        assertion =
          !cfg.ai.enable || (aiBaseUrl != "" && cfg.ai.textModel != "" && cfg.ai.visionModel != "");
        message = "Wardrowbe AI requires an endpoint and explicit text and vision models.";
      }
      {
        assertion =
          lib.intersectLists ((builtins.attrNames protectedEnvironment) ++ secretEnvironmentNames) (
            builtins.attrNames cfg.extraEnvironment
          ) == [ ];
        message = "Wardrowbe extraEnvironment cannot override protected settings or contain credentials.";
      }
      {
        assertion =
          !lib.hasPrefix "/nix/store/" cfg.environmentFile
          && !(lib.hasInfix "/../" cfg.environmentFile)
          && !(lib.hasSuffix "/.." cfg.environmentFile);
        message = "Wardrowbe environmentFile must be a runtime secret path outside the Nix store.";
      }
    ];
    services.ollama = lib.mkIf (cfg.ai.enable && cfg.ai.provider == "ollama") {
      enable = true;
      host = lib.mkDefault "127.0.0.1";
      loadModels = lib.mkAfter (
        lib.unique [
          cfg.ai.textModel
          cfg.ai.visionModel
        ]
      );
    };
    users.groups.wardrowbe = { };
    users.users.wardrowbe = {
      isSystemUser = true;
      group = "wardrowbe";
      home = "/var/lib/wardrowbe";
      createHome = false;
      extraGroups = [ "redis-wardrowbe" ];
    };
    services.postgresql = {
      enable = true;
      ensureDatabases = [ cfg.databaseName ];
      ensureUsers = [
        {
          name = cfg.databaseName;
          ensureDBOwnership = true;
        }
      ];
      identMap = ''
        wardrowbe wardrowbe ${cfg.databaseName}
      '';
      authentication = lib.mkBefore ''
        local ${cfg.databaseName} ${cfg.databaseName} peer map=wardrowbe
      '';
    };
    services.redis.servers.wardrowbe = {
      enable = true;
      port = 0;
      unixSocket = cfg.redisSocket;
      settings = {
        appendonly = "yes";
        maxmemory = "128mb";
        maxmemory-policy = "noeviction";
      };
    };
    homelab.operations = {
      state.wardrowbe = {
        paths = [
          "/var/lib/wardrowbe"
          "/var/lib/redis-wardrowbe"
          "/var/lib/wardrowbe-backup"
        ];
        units = [
          "wardrowbe-backend.service"
          "wardrowbe-worker.service"
          "wardrowbe-image-worker.service"
          "wardrowbe-frontend.service"
          "wardrowbe-backup.service"
          "wardrowbe-backup.timer"
          "redis-wardrowbe.service"
        ];
      };
      postgresql.wardrowbe = {
        database = cfg.databaseName;
        host = postgresSocket;
        port = config.services.postgresql.settings.port;
      };
      endpoints.wardrowbe = {
        url = cfg.publicUrl;
        healthUrl = "http://127.0.0.1:${toString cfg.backendPort}/api/v1/health";
        description = "Wardrowbe wardrobe planner";
      };
    };
    systemd.services = {
      wardrowbe-migrate = {
        description = "Apply Wardrowbe PostgreSQL migrations";
        requires = [ "postgresql.service" ];
        after = [ "postgresql.service" ];
        environment = sharedEnvironment;
        serviceConfig = commonService // {
          Type = "oneshot";
          ExecStart = "${cfg.backendPackage}/bin/wardrowbe-migrate";
          RemainAfterExit = true;
        };
      };
      wardrowbe-backend = {
        description = "Wardrowbe API";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wardrowbe-migrate.service"
          "redis-wardrowbe.service"
        ];
        after = [
          "wardrowbe-migrate.service"
          "redis-wardrowbe.service"
        ];
        environment = sharedEnvironment;
        serviceConfig = commonService // {
          ExecStart = "${cfg.backendPackage}/bin/wardrowbe-backend --port ${toString cfg.backendPort}";
          Restart = "on-failure";
          RestartSec = 5;
          MemoryMax = "1G";
        };
      };
      wardrowbe-worker = worker "AI" "wardrowbe-worker" "2G";
      wardrowbe-image-worker = worker "image" "wardrowbe-image-worker" "3G";
      wardrowbe-frontend = {
        description = "Wardrowbe web frontend";
        wantedBy = [ "multi-user.target" ];
        requires = [ "wardrowbe-backend.service" ];
        after = [ "wardrowbe-backend.service" ];
        environment = {
          NEXTAUTH_URL = cfg.publicUrl;
          BACKEND_URL = "http://127.0.0.1:${toString cfg.backendPort}";
          OIDC_ISSUER_URL = cfg.oidc.issuerUrl;
          OIDC_TOKEN_ENDPOINT_AUTH_METHOD = cfg.oidc.tokenEndpointAuthMethod;
          HOSTNAME = "127.0.0.1";
          PORT = toString cfg.frontendPort;
        }
        // lib.optionalAttrs (cfg.oidc.clientId != null) { OIDC_CLIENT_ID = cfg.oidc.clientId; }
        // lib.optionalAttrs (cfg.oidc.endSessionUrl != null) {
          OIDC_END_SESSION_URL = cfg.oidc.endSessionUrl;
        };
        serviceConfig = commonService // {
          WorkingDirectory = "${cfg.frontendPackage}/libexec/wardrowbe-frontend";
          ExecStart = "${cfg.frontendPackage}/bin/wardrowbe-frontend";
          Restart = "on-failure";
          RestartSec = 5;
          MemoryMax = "1G";
        };
      };
      wardrowbe-backup = {
        description = "Export Wardrowbe PostgreSQL database";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
          StateDirectory = "wardrowbe-backup";
          UMask = "0077";
          ExecStart = backupScript;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };
    };
    systemd.timers.wardrowbe-backup = {
      description = "Daily Wardrowbe database export";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
