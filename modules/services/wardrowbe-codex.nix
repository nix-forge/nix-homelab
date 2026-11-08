{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.wardrowbe;
  inherit (cfg) ai;
  enabled = cfg.enable && ai.enable && ai.codex.enable;
  adapter = pkgs.writers.writePython3Bin "wardrowbe-codex" {
    libraries = with pkgs.python3Packages; [
      fastapi
      uvicorn
      pillow
    ];
    doCheck = false; # Runtime behavior is covered by the adapter check.
  } (builtins.readFile ./scripts/wardrowbe_codex.py);
  login = pkgs.writeShellApplication {
    name = "wardrowbe-codex-login";
    runtimeInputs = [ pkgs.sudo ];
    text = (import ../../lib/render-text.nix) ./scripts/wardrowbe-codex-login.sh {
      lib_getExe_pkgs_coreutils_env = lib.getExe' pkgs.coreutils "env";
      lib_getExe_ai_codex_package = lib.getExe ai.codex.package;
    };
  };
in
{
  options.services.wardrowbe.ai.codex = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = ai.provider == "codex";
      description = "Offer a Codex OAuth endpoint, also usable alongside an Ollama or API default.";
    };
    package = lib.mkPackageOption pkgs "codex" { };
    port = lib.mkOption {
      type = lib.types.port;
      default = 18182;
      description = "Private loopback port for the Codex OAuth adapter.";
    };
    allowedModels = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_.:-]+");
      default = [ ];
      description = "Optional restriction on discovered Codex models. Empty offers every visible account catalog model. Automatic value selection uses compatible discovered models.";
    };
  };
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion =
          (
            ai.provider != "codex"
            || ai.codex.allowedModels == [ ]
            || (
              builtins.elem ai.textModel ai.codex.allowedModels
              && builtins.elem ai.visionModel ai.codex.allowedModels
            )
          )
          && ai.codex.port != cfg.backendPort
          && ai.codex.port != cfg.frontendPort
          && (!config.services.ollama.enable || ai.codex.port != config.services.ollama.port)
          && ai.timeout > 15;
        message = "Wardrowbe Codex needs allowed text/vision models, a separate port and timeout above 15 seconds.";
      }
    ];
    systemd.services.wardrowbe-backend.environment.WARDROWBE_CODEX_SOCKET =
      "/run/wardrowbe-codex/control.sock";
    systemd.services.wardrowbe-backend.environment.WARDROWBE_CODEX_URL =
      "http://127.0.0.1:${toString ai.codex.port}/v1";
    systemd.services.wardrowbe-backend.environment.WARDROWBE_CODEX_TOKEN_FILE =
      "/run/wardrowbe-codex/api-key";
    systemd.services.wardrowbe-backend.requires = [ "wardrowbe-codex.service" ];
    systemd.services.wardrowbe-backend.after = [ "wardrowbe-codex.service" ];
    users.groups.wardrowbe-codex = { };
    users.users.wardrowbe-codex = {
      isSystemUser = true;
      group = "wardrowbe-codex";
      home = "/var/lib/wardrowbe-codex";
    };
    environment.systemPackages = [ login ];
    systemd.services.wardrowbe-codex = {
      description = "Private Wardrowbe Codex OAuth adapter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        CODEX_CONTROL_SOCKET = "/run/wardrowbe-codex/control.sock";
        CODEX_API_KEY_FILE = "/run/wardrowbe-codex/api-key";
        CODEX_EXECUTABLE = lib.getExe ai.codex.package;
        CODEX_HOME = "/var/lib/wardrowbe-codex";
        CODEX_MODELS = builtins.toJSON ai.codex.allowedModels;
        CODEX_TIMEOUT = toString (ai.timeout - 10);
        CODEX_CONCURRENCY = toString ai.concurrency;
        PORT = toString ai.codex.port;
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
      serviceConfig = {
        ExecStartPre = "${lib.getExe adapter} --prepare-key";
        ExecStart = lib.getExe adapter;
        User = "wardrowbe-codex";
        Group = "wardrowbe";
        RuntimeDirectory = "wardrowbe-codex";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "wardrowbe-codex";
        StateDirectoryMode = "0700";
        UMask = "0077";
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        InaccessiblePaths = [
          "-/var/lib/wardrowbe"
          "-/var/lib/redis-wardrowbe"
        ];
        MemoryMax = lib.mkDefault "1G";
        TasksMax = lib.mkDefault 128;
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
      };
    };
  };
}
