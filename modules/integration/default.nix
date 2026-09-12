{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.integration;
  json = pkgs.formats.json { };
  secretName = path: "secret-${builtins.substring 0 24 (builtins.hashString "sha256" path)}";
  secretPaths =
    value:
    if builtins.isAttrs value then
      if value ? _secret then [ value._secret ] else lib.concatMap secretPaths (lib.attrValues value)
    else if builtins.isList value then
      lib.concatMap secretPaths value
    else
      [ ];
  validSecrets =
    value:
    if builtins.isAttrs value then
      if value ? _secret then
        builtins.attrNames value == [ "_secret" ]
      else
        lib.all (
          key:
          let
            item = value.${key};
          in
          (
            if
              builtins.elem (lib.toLower key) [
                "apikey"
                "password"
                "token"
                "newpw"
                "currentpw"
              ]
            then
              item == "" || (builtins.isAttrs item && item ? _secret)
            else
              true
          )
          && validSecrets item
        ) (builtins.attrNames value)
    else if builtins.isList value then
      lib.all validSecrets value
    else
      true;
  runtime =
    value:
    if builtins.isAttrs value then
      if value ? _secret then
        { _credential = secretName value._secret; }
      else
        lib.mapAttrs (_: runtime) value
    else if builtins.isList value then
      map runtime value
    else
      value;
  keyed = lib.filterAttrs (_: service: service.installApiKey) cfg.services;
  servarrKeys = lib.filterAttrs (_: service: service.kind != "bazarr") keyed;
  bazarrKeys = lib.filterAttrs (_: service: service.kind == "bazarr") keyed;
  definition = service: {
    inherit (service)
      kind
      url
      mode
      resources
      settings
      ;
    apiKey = if service.apiKeyFile == null then "" else { _secret = service.apiKeyFile; };
  };
  paths = service: lib.unique (secretPaths (definition service));
  configFile =
    name: service: json.generate "homelab-${name}-integration.json" (runtime (definition service));
  command =
    name: service:
    "${pkgs.python3}/bin/python3 ${../../scripts/integration}/reconcile.py ${configFile name service}";
in
{
  options.homelab.integration = {
    enable = lib.mkEnableOption "authenticated application reconciliation";
    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Delay between completed reconciliation runs. No overlapping jobs are started.";
    };
    services = lib.mkOption {
      default = { };
      description = "Application API jobs. Settings support {_secret = /absolute/runtime/path;} references; values are loaded through systemd credentials.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              kind = lib.mkOption {
                type = lib.types.enum [
                  "sonarr"
                  "radarr"
                  "lidarr"
                  "prowlarr"
                  "jellyfin"
                  "seerr"
                  "navidrome"
                  "audiobookshelf"
                  "bazarr"
                  "autobrr"
                ];
                default = name;
                description = "Application API adapter.";
              };
              url = lib.mkOption {
                type = lib.types.str;
                description = "Local HTTP or remote HTTPS API base URL. Redirects and credential-bearing URLs are rejected.";
              };
              installApiKey = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Install a user-provided key into a local Servarr runtime environment file or Bazarr configuration. Restart the key unit when present and the application after rotation.";
              };
              apiKeyFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "User-supplied runtime API key file. Jellyfin, Seerr, Navidrome and Audiobookshelf may instead use settings.login.";
              };
              mode = lib.mkOption {
                type = lib.types.enum [
                  "bootstrap"
                  "managed"
                ];
                default = "bootstrap";
                description = "Bootstrap preserves existing objects. Managed updates declared fields. Neither mode deletes undeclared objects.";
              };
              after = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Additional prerequisite systemd units, including user secret activation and other integration jobs.";
              };
              resources = lib.mkOption {
                type = lib.types.listOf json.type;
                default = [ ];
                description = "Declared Arr resources: endpoint, stable match identity and values. Provider fields are an attribute set validated against the API schema.";
              };
              settings = lib.mkOption {
                inherit (json) type;
                default = { };
                description = "Adapter configuration for libraries, accounts, request policies and subtitle settings. See the integration guide.";
              };
            };
          }
        )
      );
    };
  };
  config = lib.mkIf cfg.enable {
    services = lib.mapAttrs' (
      name: service:
      lib.nameValuePair service.kind { environmentFiles = [ "/run/homelab-key-${name}/environment" ]; }
    ) servarrKeys;
    assertions = [
      {
        assertion =
          builtins.length (lib.attrValues keyed)
          == builtins.length (lib.unique (map (service: service.kind) (lib.attrValues keyed)));
        message = "Only one integration job may install each local application's API key.";
      }
    ]
    ++ lib.flatten (
      lib.mapAttrsToList (name: service: [
        {
          assertion = validSecrets (definition service);
          message = "Integration ${name} passwords, API keys and tokens must use runtime _secret references.";
        }
        {
          assertion = lib.all (
            path:
            builtins.isString path
            && lib.hasPrefix "/" path
            && !(lib.hasPrefix "/nix/store" path)
            && !(lib.hasInfix ":" path)
            && !(lib.hasInfix "\n" path)
          ) (paths service);
          message = "Integration ${name} needs absolute runtime secret paths outside the Nix store.";
        }
        {
          assertion = builtins.match "[a-zA-Z0-9_-]+" name != null;
          message = "Integration names must be safe systemd unit names.";
        }
        {
          assertion =
            service.apiKeyFile != null
            || builtins.elem service.kind [
              "jellyfin"
              "seerr"
              "navidrome"
              "audiobookshelf"
            ];
          message = "Integration ${name} requires a user-supplied apiKeyFile.";
        }
        {
          assertion =
            service.installApiKey
            -> (
              builtins.elem service.kind [
                "sonarr"
                "radarr"
                "lidarr"
                "prowlarr"
                "bazarr"
              ]
              && config.services.${service.kind}.enable
              && service.apiKeyFile != null
            );
          message = "API key installation supports local Servarr and Bazarr services only.";
        }
      ]) cfg.services
    );
    systemd.services =
      (lib.mapAttrs' (
        name: service:
        lib.nameValuePair "homelab-integrate-${name}" {
          description = "Reconcile ${name} application configuration";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "${service.kind}.service"
          ]
          ++ service.after;
          requires = service.after;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = command name service;
            LoadCredential = map (path: "${secretName path}:${path}") (paths service);
            DynamicUser = true;
            StateDirectory = "homelab-integrate-${name}";
            StateDirectoryMode = "0700";
            UMask = "0077";
            NoNewPrivileges = true;
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
              "AF_UNIX"
            ];
            CapabilityBoundingSet = "";
            MemoryMax = "192M";
            CPUQuota = "25%";
            TimeoutStartSec = "5min";
          };
        }
      ) cfg.services)
      // (lib.mapAttrs' (
        name: service:
        lib.nameValuePair "homelab-key-${name}" {
          before = [ "${service.kind}.service" ];
          requiredBy = [ "${service.kind}.service" ];
          inherit (service) after;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "homelab-key-${name}";
            RuntimeDirectoryMode = "0700";
            LoadCredential = [ "api-key:${service.apiKeyFile}" ];
            ExecStart = "${pkgs.python3}/bin/python3 ${../../scripts/integration/api-key.py} ${lib.toUpper service.kind} /run/homelab-key-${name}/environment";
            UMask = "0077";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateNetwork = true;
          };
        }
      ) servarrKeys)
      // (lib.mapAttrs' (
        _: service:
        lib.nameValuePair "bazarr" {
          serviceConfig.LoadCredential = [ "homelab-api-key:${service.apiKeyFile}" ];
          serviceConfig.ExecStartPre = [
            "${
              pkgs.python3.withPackages (ps: [ ps.pyyaml ])
            }/bin/python3 ${../../scripts/integration/bazarr-key.py} ${lib.escapeShellArg config.services.bazarr.dataDir}"
          ];
        }
      ) bazarrKeys);
    systemd.timers = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "homelab-integrate-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitInactiveSec = cfg.interval;
          RandomizedDelaySec = "30s";
        };
      }
    ) cfg.services;
  };
}
