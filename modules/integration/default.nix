{
  config,
  lib,
  pkgs,
  ...
}:
let
  catalog = import ../catalog.nix;
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
  keysOnly =
    allowed: value:
    builtins.isAttrs value && lib.all (key: builtins.elem key allowed) (builtins.attrNames value);
  typedFields =
    schema: value:
    keysOnly (builtins.attrNames schema) value
    && lib.all (key: schema.${key} value.${key}) (builtins.attrNames value);
  strings = value: builtins.isList value && lib.all builtins.isString value;
  secretValue =
    value:
    builtins.isString value
    || (
      builtins.isAttrs value
      && builtins.attrNames value == [ "_secret" ]
      && builtins.isString value._secret
    );
  managerSettings =
    settings:
    let
      downloadHandling = {
        enableCompletedDownloadHandling = builtins.isBool;
        autoRedownloadFailed = builtins.isBool;
        autoRedownloadFailedFromInteractiveSearch = builtins.isBool;
      };
      mediaManagement = {
        recycleBin = builtins.isString;
        recycleBinCleanupDays = builtins.isInt;
        downloadPropersAndRepacks = builtins.isString;
        deleteEmptyFolders = builtins.isBool;
        fileDate = builtins.isString;
        rescanAfterRefresh = builtins.isString;
        setPermissionsLinux = builtins.isBool;
        chmodFolder = builtins.isString;
        chownGroup = builtins.isString;
        skipFreeSpaceCheckWhenImporting = builtins.isBool;
        minimumFreeSpaceWhenImporting = builtins.isInt;
        copyUsingHardlinks = builtins.isBool;
        useScriptImport = builtins.isBool;
        scriptImportPath = builtins.isString;
        importExtraFiles = builtins.isBool;
        extraFileExtensions = builtins.isString;
        enableMediaInfo = builtins.isBool;
        autoUnmonitorPreviouslyDownloadedEpisodes = builtins.isBool;
        createEmptySeriesFolders = builtins.isBool;
        episodeTitleRequired = builtins.isString;
        autoUnmonitorPreviouslyDownloadedMovies = builtins.isBool;
        createEmptyMovieFolders = builtins.isBool;
        autoRenameFolders = builtins.isBool;
        pathsDefaultStatic = builtins.isBool;
        autoUnmonitorPreviouslyDownloadedTracks = builtins.isBool;
        createEmptyArtistFolders = builtins.isBool;
        watchLibraryForChanges = builtins.isBool;
        allowFingerprinting = builtins.isString;
      };
      naming = {
        renameEpisodes = builtins.isBool;
        renameMovies = builtins.isBool;
        renameTracks = builtins.isBool;
        replaceIllegalCharacters = builtins.isBool;
        colonReplacementFormat = builtins.isInt;
        customColonReplacementFormat = builtins.isString;
        multiEpisodeStyle = builtins.isInt;
        standardEpisodeFormat = builtins.isString;
        dailyEpisodeFormat = builtins.isString;
        animeEpisodeFormat = builtins.isString;
        seriesFolderFormat = builtins.isString;
        seasonFolderFormat = builtins.isString;
        specialsFolderFormat = builtins.isString;
        standardMovieFormat = builtins.isString;
        movieFolderFormat = builtins.isString;
        standardTrackFormat = builtins.isString;
        multiDiscTrackFormat = builtins.isString;
        artistFolderFormat = builtins.isString;
      };
      schemas = { inherit downloadHandling mediaManagement naming; };
    in
    keysOnly (builtins.attrNames schemas) settings
    && lib.all (name: typedFields schemas.${name} settings.${name}) (builtins.attrNames settings);
  loginSettings =
    value:
    typedFields {
      username = builtins.isString;
      password = secretValue;
      hostname = builtins.isString;
      port = builtins.isInt;
      useSsl = builtins.isBool;
      urlBase = builtins.isString;
      email = builtins.isString;
      serverType = builtins.isInt;
    } value;
  jellyfinLibrary =
    value:
    typedFields {
      collectionType = builtins.isString;
      paths = strings;
      options = builtins.isAttrs;
    } value
    && value ? collectionType
    && value ? paths;
  jellyfinUser =
    value:
    typedFields {
      password = secretValue;
      policy = builtins.isAttrs;
    } value;
  seerrDestination =
    value:
    typedFields {
      name = builtins.isString;
      hostname = builtins.isString;
      port = builtins.isInt;
      apiKey = secretValue;
      useSsl = builtins.isBool;
      baseUrl = builtins.isString;
      activeProfileName = builtins.isString;
      activeDirectory = builtins.isString;
      isDefault = builtins.isBool;
      is4k = builtins.isBool;
      externalUrl = builtins.isString;
      syncEnabled = builtins.isBool;
      preventSearch = builtins.isBool;
      minimumAvailability = builtins.isString;
      enableSeasonFolders = builtins.isBool;
    } value;
  audiobookLibrary =
    value:
    typedFields {
      folders =
        items:
        builtins.isList items && lib.all (item: typedFields { fullPath = builtins.isString; } item) items;
      mediaType = builtins.isString;
      icon = builtins.isString;
    } value
    && value ? folders
    && value ? mediaType;
  accountSettings =
    value:
    typedFields {
      name = builtins.isString;
      password = secretValue;
      isAdmin = builtins.isBool;
      type = builtins.isString;
      isActive = builtins.isBool;
      permissions = builtins.isAttrs;
    } value;
  typedSettings =
    kind: settings:
    if
      builtins.elem kind [
        "sonarr"
        "radarr"
        "lidarr"
        "prowlarr"
      ]
    then
      managerSettings settings
    else if kind == "jellyfin" then
      keysOnly [ "login" "startup" "encoding" "libraries" "users" ] settings
      && (!(settings ? login) || loginSettings settings.login)
      && (!(settings ? startup) || builtins.isAttrs settings.startup)
      && (!(settings ? encoding) || builtins.isAttrs settings.encoding)
      && (
        !(settings ? libraries)
        ||
          builtins.isAttrs settings.libraries && lib.all jellyfinLibrary (lib.attrValues settings.libraries)
      )
      && (
        !(settings ? users)
        || builtins.isAttrs settings.users && lib.all jellyfinUser (lib.attrValues settings.users)
      )
    else if kind == "seerr" then
      keysOnly [ "login" "libraries" "radarr" "sonarr" "main" "notifications" ] settings
      && (!(settings ? login) || loginSettings settings.login)
      && (!(settings ? libraries) || strings settings.libraries)
      &&
        lib.all
          (
            name:
            !(builtins.hasAttr name settings)
            || builtins.isAttrs settings.${name} && lib.all seerrDestination (lib.attrValues settings.${name})
          )
          [
            "radarr"
            "sonarr"
          ]
      && lib.all (name: !(builtins.hasAttr name settings) || builtins.isAttrs settings.${name}) [
        "main"
        "notifications"
      ]
    else if kind == "bazarr" then
      keysOnly [
        "general"
        "sonarr"
        "radarr"
        "providers"
        "languageProfiles"
        "enabledLanguages"
        "defaultProfiles"
      ] settings
      && lib.all (name: !(builtins.hasAttr name settings) || builtins.isAttrs settings.${name}) [
        "general"
        "sonarr"
        "radarr"
        "providers"
        "languageProfiles"
        "defaultProfiles"
      ]
      && (!(settings ? enabledLanguages) || strings settings.enabledLanguages)
    else if kind == "navidrome" then
      keysOnly [ "login" "users" ] settings
      && (!(settings ? login) || loginSettings settings.login)
      && (
        !(settings ? users)
        || builtins.isAttrs settings.users && lib.all accountSettings (lib.attrValues settings.users)
      )
    else if kind == "audiobookshelf" then
      keysOnly [ "login" "libraries" "users" ] settings
      && (!(settings ? login) || loginSettings settings.login)
      && (
        !(settings ? libraries)
        ||
          builtins.isAttrs settings.libraries && lib.all audiobookLibrary (lib.attrValues settings.libraries)
      )
      && (
        !(settings ? users)
        || builtins.isAttrs settings.users && lib.all accountSettings (lib.attrValues settings.users)
      )
    else if kind == "autobrr" then
      keysOnly [ "downloadClients" "filters" ] settings
      && lib.all (name: !(builtins.hasAttr name settings) || builtins.isAttrs settings.${name}) [
        "downloadClients"
        "filters"
      ]
    else
      settings == { };
  keyed = lib.filterAttrs (_: service: service.installApiKey) cfg.services;
  servarrKeys = lib.filterAttrs (_: service: service.kind != "bazarr") keyed;
  bazarrKeys = lib.filterAttrs (_: service: service.kind == "bazarr") keyed;
  definition = service: {
    inherit (service) kind url mode;
    settings = lib.recursiveUpdate service.settings service.extraSettings;
    resources = service.resources ++ service.extraResources;
    apiKey = if service.apiKeyFile == null then "" else { _secret = service.apiKeyFile; };
  };
  paths = service: lib.unique (secretPaths (definition service));
  configFile =
    name: service: json.generate "homelab-${name}-integration.json" (runtime (definition service));
  command =
    name: service:
    "${pkgs.python3}/bin/python3 ${../../scripts/integration}/reconcile.py ${configFile name service}";
  integrationKinds = lib.unique (
    lib.filter (kind: kind != null) (
      map (service: service.integration or null) (lib.attrValues (catalog.core // catalog.optional))
    )
  );
  resourceType = lib.types.submodule {
    options = {
      endpoint = lib.mkOption {
        type = lib.types.enum [
          "rootfolder"
          "downloadclient"
          "indexer"
          "indexerproxy"
          "applications"
          "tag"
          "qualityprofile"
          "delayprofile"
          "notification"
          "remotepathmapping"
        ];
        description = "Supported Arr collection endpoint.";
      };
      match = lib.mkOption {
        type = lib.types.attrsOf json.type;
        description = "Stable name, path, or label used to find exactly one owned object.";
      };
      values = lib.mkOption {
        inherit (json) type;
        default = { };
        description = "Declared provider fields, validated against the running application's schema.";
      };
    };
  };
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
                type = lib.types.enum integrationKinds;
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
                type = lib.types.listOf resourceType;
                default = [ ];
                description = "Typed Arr resource envelopes. Provider-specific values remain schema-validated by the running application.";
              };
              extraResources = lib.mkOption {
                type = lib.types.listOf json.type;
                default = [ ];
                description = "Unsupported raw Arr resources for forward compatibility. They retain runtime secret validation but carry no versioned compatibility promise.";
              };
              settings = lib.mkOption {
                inherit (json) type;
                default = { };
                description = "Typed adapter configuration for supported libraries, accounts, request policies and subtitle settings. See the integration guide.";
              };
              extraSettings = lib.mkOption {
                inherit (json) type;
                default = { };
                description = "Unsupported raw adapter settings recursively merged over typed settings for forward compatibility. These fields carry no versioned compatibility promise.";
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
          assertion = typedSettings service.kind service.settings;
          message = "Integration ${name} does not satisfy the ${service.kind} typed settings contract. Move unsupported upstream fields to extraSettings.";
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
          assertion = lib.all (
            resource:
            resource.match != { }
            && lib.all (
              key:
              builtins.elem key [
                "name"
                "path"
                "label"
              ]
            ) (builtins.attrNames resource.match)
          ) service.resources;
          message = "Integration ${name} resources require a stable name, path, or label match.";
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
