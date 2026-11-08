{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.integration.webAuth;
  helper = pkgs.writers.writePython3Bin "homelab-web-auth" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/integration/web_auth.py);
  runtimePath = import ../lib/runtime-path.nix lib;
  credentials = account: [
    account.usernameFile
    account.passwordFile
    account.apiKeyFile
  ];
in
{
  options.homelab.integration.webAuth = lib.mkOption {
    default = { };
    description = ''
      Named native-API website login jobs for Servarr and Bazarr. Empty by
      default. Credentials are supplied as runtime files and never evaluated.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }: {
          options = {
            kind = lib.mkOption {
              type = lib.types.enum [
                "sonarr"
                "radarr"
                "lidarr"
                "prowlarr"
                "bazarr"
              ];
              default = name;
              defaultText = lib.literalExpression "name";
              description = "Application API to use. Set explicitly for a named second instance.";
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = "Loopback or link-local HTTP API base URL; the helper rejects redirects and credential-bearing URLs.";
            };
            apiVersion = lib.mkOption {
              type = lib.types.enum [
                "v1"
                "v3"
              ];
              default =
                if
                  builtins.elem config.kind [
                    "sonarr"
                    "radarr"
                  ]
                then
                  "v3"
                else
                  "v1";
              defaultText = lib.literalExpression ''if builtins.elem config.kind [ "sonarr" "radarr" ] then "v3" else "v1"'';
              description = "Native host-configuration API version. Ignored by Bazarr.";
            };
            serviceUnit = lib.mkOption {
              type = lib.types.strMatching "[A-Za-z0-9@_.-]+\\.service";
              default = "${config.kind}.service";
              defaultText = lib.literalExpression ''"''${config.kind}.service"'';
              description = "Local application unit that must start before credential reconciliation.";
            };
            requestTimeoutSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 10;
              description = "Socket inactivity timeout for one native API request, further capped by the remaining read retry budget while opening a read response.";
            };
            readRetryBudgetSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 60;
              description = "Deadline for retrying connection and response-header reads while the application starts. Response transfer uses the request's socket timeout and the overall service deadline. Writes and authentication failures are never retried.";
            };
            readAttempts = lib.mkOption {
              type = lib.types.ints.positive;
              default = 10;
              description = "Maximum attempts for a safe API read, with bounded exponential backoff.";
            };
            usernameFile = lib.mkOption {
              type = lib.types.str;
              description = "Runtime file containing the desired website login name.";
            };
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = "Runtime file containing the desired website password.";
            };
            apiKeyFile = lib.mkOption {
              type = lib.types.str;
              description = "Runtime file containing the application's API key.";
            };
            after = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional units to order after, such as secret activation and API integration.";
            };
            requires = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional units required for the native API and runtime credentials.";
            };
            allowedCIDRs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "127.0.0.0/8"
                "::1/128"
              ];
              description = "Addresses the credential job may contact. Extend only for a local API bound outside loopback.";
            };
          };
        }
      )
    );
  };

  config = lib.mkIf (cfg != { }) {
    assertions = lib.mapAttrsToList (name: account: {
      assertion =
        builtins.match "[A-Za-z0-9_-]+" name != null
        && lib.all runtimePath (credentials account)
        && account.allowedCIDRs != [ ];
      message = "Website login job ${name} needs a safe name, runtime credential paths outside the store, and an allowed local address.";
    }) cfg;

    systemd.services = lib.mapAttrs' (
      name: account:
      lib.nameValuePair "homelab-web-auth-${name}" {
        description = "Apply ${name} website login through its native API";
        wantedBy = [ "multi-user.target" ];
        after = [ account.serviceUnit ] ++ account.after;
        requires = [ account.serviceUnit ] ++ account.requires;
        environment = {
          HTTP_TIMEOUT_SECONDS = toString account.requestTimeoutSeconds;
          HTTP_READ_RETRY_BUDGET_SECONDS = toString account.readRetryBudgetSeconds;
          HTTP_READ_ATTEMPTS = toString account.readAttempts;
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe helper} ${
            lib.escapeShellArgs [
              name
              account.kind
              account.url
              account.apiVersion
            ]
          }";
          LoadCredential = [
            "username:${account.usernameFile}"
            "password:${account.passwordFile}"
            "api-key:${account.apiKeyFile}"
          ];
          StateDirectory = "homelab-web-auth";
          StateDirectoryMode = "0700";
          UMask = "0077";
          Restart = "on-failure";
          RestartSec = "30s";
          TimeoutStartSec = toString (
            lib.max 480 (3 * account.readRetryBudgetSeconds + 5 * account.requestTimeoutSeconds + 30)
          );
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          IPAddressDeny = [ "any" ];
          IPAddressAllow = account.allowedCIDRs;
          MemoryMax = "96M";
          TasksMax = 16;
        };
      }
    ) cfg;
  };
}
