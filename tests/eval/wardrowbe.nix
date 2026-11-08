{ evaluate, lib }:
let
  base = { pkgs, ... }: {
    services.wardrowbe = {
      enable = true;
      backendPackage = pkgs.writeShellScriptBin "wardrowbe-backend" "exit 0";
      frontendPackage = pkgs.writeShellScriptBin "wardrowbe-frontend" "exit 0";
      publicUrl = "https://wardrobe.example.org";
      environmentFile = "/run/keys/wardrowbe.env";
      oidc = {
        issuerUrl = "https://identity.example.org";
        clientId = "public-client-id";
      };
    };
  };
  configured = (evaluate base).config;
  customDatabase =
    (evaluate {
      imports = [ base ];
      services.wardrowbe.databaseName = "wardrobe_custom";
    }).config;
  postConfigured =
    (evaluate {
      imports = [ base ];
      services.wardrowbe.oidc.tokenEndpointAuthMethod = "client_secret_post";
    }).config;
  provider =
    name:
    (evaluate {
      imports = [ base ];
      services.wardrowbe.ai = {
        enable = true;
        provider = name;
        textModel = "fixture-text";
        visionModel = "fixture-vision";
      };
    }).config;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate {
        imports = [
          base
          extra
        ];
      }).config.assertions;
in
{
  issuerPath =
    let
      c =
        (evaluate {
          imports = [ base ];
          services.wardrowbe.oidc.issuerUrl = lib.mkForce "https://identity.example.org/realms/example";
        }).config;
    in
    c.systemd.services.wardrowbe-frontend.environment.OIDC_ISSUER_URL
    == "https://identity.example.org/realms/example";
  codexIsolation =
    let
      c = provider "codex";
    in
    c.systemd.services.wardrowbe-codex.serviceConfig.User == "wardrowbe-codex"
    && c.systemd.services.wardrowbe-codex.serviceConfig.StateDirectoryMode == "0700"
    && c.systemd.services.wardrowbe-codex.serviceConfig.RuntimeDirectoryMode == "0750"
    && c.systemd.services.wardrowbe-codex.serviceConfig.Group == "wardrowbe"
    &&
      c.systemd.services.wardrowbe-backend.environment.WARDROWBE_CODEX_SOCKET
      == "/run/wardrowbe-codex/control.sock"
    &&
      c.systemd.services.wardrowbe-backend.environment.WARDROWBE_CODEX_TOKEN_FILE
      == "/run/wardrowbe-codex/api-key"
    &&
      c.systemd.services.wardrowbe-codex.environment.CODEX_API_KEY_FILE == "/run/wardrowbe-codex/api-key"
    && lib.hasSuffix " --prepare-key" c.systemd.services.wardrowbe-codex.serviceConfig.ExecStartPre
    && builtins.elem "wardrowbe-codex.service" c.systemd.services.wardrowbe-backend.requires
    &&
      c.systemd.services.wardrowbe-backend.environment.WARDROWBE_CODEX_URL == "http://127.0.0.1:18182/v1"
    && !(c.systemd.services.wardrowbe-codex.serviceConfig ? EnvironmentFile)
    && c.systemd.services.wardrowbe-backend.environment.AI_BASE_URL == "http://127.0.0.1:18182/v1"
    && c.networking.firewall.allowedTCPPorts == [ ];
  nativeOllama =
    let
      c = provider "ollama";
    in
    c.services.ollama.enable
    && c.services.ollama.host == "127.0.0.1"
    && builtins.elem "fixture-text" c.services.ollama.loadModels
    && builtins.elem "fixture-vision" c.services.ollama.loadModels;
  nativeOllamaAddress =
    let
      c =
        (evaluate {
          imports = [ base ];
          services.wardrowbe.ai = {
            enable = true;
            provider = "ollama";
          };
          services.ollama = {
            host = "::1";
            port = 11435;
          };
        }).config;
    in
    c.systemd.services.wardrowbe-backend.environment.AI_BASE_URL == "http://[::1]:11435/v1";
  rejectsOllamaPortCollision = rejected {
    services.wardrowbe.ai = {
      enable = true;
      provider = "ollama";
      codex = {
        enable = true;
        allowedModels = [ "fixture-cloud" ];
        port = 11434;
      };
    };
  };
  parallelProviders =
    let
      c =
        (evaluate {
          imports = [ base ];
          services.wardrowbe.ai = {
            enable = true;
            provider = "ollama";
            codex.enable = true;
            codex.allowedModels = [ "fixture-cloud" ];
          };
        }).config;
    in
    c.services.ollama.enable
    && c.systemd.services ? wardrowbe-codex
    && c.systemd.services.wardrowbe-backend.environment.AI_BASE_URL == "http://127.0.0.1:11434/v1";
  rejectsDisabledCodex = rejected {
    services.wardrowbe.ai = {
      enable = true;
      provider = "codex";
      codex.enable = false;
      textModel = "fixture-text";
      visionModel = "fixture-vision";
    };
  };
  openaiEndpoint =
    (provider "openai").systemd.services.wardrowbe-backend.environment.AI_BASE_URL
    == "https://api.openai.com/v1";
  rejectsMissingCloudModels = rejected {
    services.wardrowbe.ai = {
      enable = true;
      provider = "openai";
    };
  };
  rejectsCodexPortCollision = rejected {
    services.wardrowbe.ai = {
      enable = true;
      provider = "codex";
      textModel = "fixture-text";
      visionModel = "fixture-vision";
      codex.port = 18180;
    };
  };
  optIn = !(evaluate { }).config.services.wardrowbe.enable;
  nativeDependencies =
    configured.services.postgresql.enable
    && configured.services.redis.servers.wardrowbe.enable
    && configured.services.redis.servers.wardrowbe.port == 0
    &&
      configured.systemd.services.wardrowbe-backend.environment.REDIS_URL
      == "unix:///run/redis-wardrowbe/redis.sock"
    && builtins.elem "redis-wardrowbe" configured.users.users.wardrowbe.extraGroups
    && configured.systemd.services.wardrowbe-migrate.serviceConfig.Type == "oneshot";
  customDatabasePeerAuthentication =
    customDatabase.systemd.services.wardrowbe-migrate.serviceConfig.User == "wardrowbe"
    && lib.hasInfix "wardrowbe wardrowbe wardrobe_custom" customDatabase.services.postgresql.identMap
    && lib.hasInfix "local wardrobe_custom wardrobe_custom peer map=wardrowbe" customDatabase.services.postgresql.authentication
    && lib.hasInfix "postgresql+asyncpg://wardrobe_custom@localhost:" customDatabase.systemd.services.wardrowbe-backend.environment.DATABASE_URL;
  privateListeners =
    configured.systemd.services.wardrowbe-frontend.environment.HOSTNAME == "127.0.0.1"
    && !(builtins.elem configured.services.wardrowbe.backendPort configured.networking.firewall.allowedTCPPorts)
    && configured.networking.firewall.allowedTCPPorts == [ ];
  productionAuth =
    configured.systemd.services.wardrowbe-backend.environment.OIDC_ISSUER_URL
    == "https://identity.example.org"
    && configured.systemd.services.wardrowbe-frontend.environment.OIDC_CLIENT_ID == "public-client-id"
    &&
      configured.systemd.services.wardrowbe-frontend.environment.OIDC_TOKEN_ENDPOINT_AUTH_METHOD
      == "client_secret_basic"
    &&
      configured.systemd.services.wardrowbe-frontend.serviceConfig.EnvironmentFile
      == "/run/keys/wardrowbe.env";
  supportsPostClientAuth =
    postConfigured.systemd.services.wardrowbe-frontend.environment.OIDC_TOKEN_ENDPOINT_AUTH_METHOD
    == "client_secret_post";
  resourceBounds =
    configured.systemd.services.wardrowbe-worker.serviceConfig.MemoryMax == "2G"
    && configured.systemd.services.wardrowbe-image-worker.serviceConfig.MemoryMax == "3G"
    && configured.systemd.services.wardrowbe-backend.environment.AI_TAGGING_CONCURRENCY == "1";
  backup =
    configured.systemd.timers.wardrowbe-backup.timerConfig.Persistent
    && configured.systemd.services.wardrowbe-backup.serviceConfig.User == "postgres"
    && configured.systemd.services.wardrowbe-backup.serviceConfig.StateDirectory == "wardrowbe-backup";
  recoveryInventory =
    configured.homelab.operations.postgresql.wardrowbe.database == "wardrowbe"
    && builtins.elem "/var/lib/wardrowbe" configured.homelab.operations.state.wardrowbe.paths
    && builtins.elem "redis-wardrowbe.service" configured.homelab.operations.state.wardrowbe.units
    &&
      configured.homelab.operations.endpoints.wardrowbe.healthUrl
      == "http://127.0.0.1:18180/api/v1/health";
  rejectsSecretInStore = rejected {
    services.wardrowbe.environmentFile = lib.mkForce "/nix/store/secret.env";
  };
  rejectsSecretInSettings = rejected {
    services.wardrowbe.extraEnvironment.SECRET_KEY = "disallowed";
  };
  rejectsAiWithoutEndpoint = rejected { services.wardrowbe.ai.enable = true; };
}
