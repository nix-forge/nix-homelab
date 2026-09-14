{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.integrations;
  inherit (cfg) seerr;
  jellyfin =
    if cfg.jellyfin == null then
      {
        administrator = {
          name = "";
          passwordFile = "/invalid";
        };
      }
    else
      cfg.jellyfin;
  json = pkgs.formats.json { };
  pathType = types.strMatching "/[A-Za-z0-9_./-]+";
  permissionValues = {
    request = 32;
    vote = 64;
    request4k = 1024;
    requestAdvanced = 8192;
    requestView = 16384;
    requestMovie = 262144;
    requestTv = 524288;
    viewIssues = 2097152;
    createIssues = 4194304;
    recentView = 67108864;
    watchlistView = 134217728;
    viewBlocklist = 1073741824;
    autoApprove = 128;
    autoApproveMovie = 256;
    autoApproveTv = 512;
    autoApprove4k = 32768;
    autoApprove4kMovie = 65536;
    autoApprove4kTv = 131072;
    autoRequest = 8388608;
    autoRequestMovie = 16777216;
    autoRequestTv = 33554432;
  };
  automaticPermissions = lib.filter (name: lib.hasPrefix "auto" name) (
    builtins.attrNames permissionValues
  );
  quotaType = types.submodule {
    options = {
      limit = mkOption {
        type = types.ints.unsigned;
        description = "Maximum requests during the quota window; zero disables requests of this type.";
      };
      days = mkOption {
        type = types.ints.positive;
        description = "Rolling quota window in days.";
      };
    };
  };
  destinationType = types.submodule (
    { name, ... }: {
      options = {
        manager = mkOption {
          type = types.str;
          default = name;
          description = "Named Sonarr or Radarr instance from homelab.integrations.servarr.";
        };
        name = mkOption {
          type = types.str;
          default = name;
          description = "Stable Seerr destination name.";
        };
        rootFolder = mkOption {
          type = types.str;
          description = "Named root folder in the referenced manager declaration.";
        };
        qualityProfile = mkOption {
          type = types.str;
          description = "Exact quality profile name exposed by the referenced manager.";
        };
        isDefault = mkOption {
          type = types.bool;
          default = false;
          description = "Use this as Seerr's default destination for its media type.";
        };
        is4k = mkOption {
          type = types.bool;
          default = false;
          description = "Mark this as a 4K destination.";
        };
        syncEnabled = mkOption {
          type = types.bool;
          default = true;
          description = "Synchronize manager state into Seerr.";
        };
        preventSearch = mkOption {
          type = types.bool;
          default = false;
          description = "Add requests without starting an automatic search.";
        };
        minimumAvailability = mkOption {
          type = types.enum [
            "announced"
            "inCinemas"
            "released"
            "preDB"
          ];
          default = "released";
          description = "Radarr minimum availability for new requests.";
        };
        enableSeasonFolders = mkOption {
          type = types.bool;
          default = true;
          description = "Create Sonarr season folders.";
        };
        extraSettings = mkOption {
          inherit (json) type;
          default = { };
          description = "Version-specific destination settings outside the stable typed interface.";
        };
      };
    }
  );
  seerrType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "Seerr API base URL.";
      };
      apiKeyFile = mkOption {
        type = types.nullOr pathType;
        default = null;
        description = "Optional runtime Seerr API-key file; login is used when absent.";
      };
      mode = mkOption {
        type = types.enum [
          "bootstrap"
          "managed"
        ];
        default = "bootstrap";
        description = "Bootstrap preserves existing destinations; managed updates declared fields.";
      };
      jellyfin = {
        hostname = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Jellyfin host reachable from Seerr.";
        };
        port = mkOption {
          type = types.port;
          default = 8096;
          description = "Jellyfin port reachable from Seerr.";
        };
        useSsl = mkOption {
          type = types.bool;
          default = false;
          description = "Use TLS for Seerr's Jellyfin connection.";
        };
        urlBase = mkOption {
          type = types.str;
          default = "";
          description = "Jellyfin URL base.";
        };
        email = mkOption {
          type = types.str;
          description = "Initial Seerr administrator email.";
        };
        libraries = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Declared Jellyfin library names enabled in Seerr.";
        };
      };
      destinations = mkOption {
        type = types.attrsOf destinationType;
        default = { };
        description = "Named Sonarr and Radarr request destinations.";
      };
      defaultPermissions = mkOption {
        type = types.listOf (types.enum (builtins.attrNames permissionValues));
        default = [ "request" ];
        description = "Permissions granted to new media-server users.";
      };
      allowAutomaticRequests = mkOption {
        type = types.bool;
        default = false;
        description = "Explicit safety gate for auto-approval or automatic-request permissions.";
      };
      quotas = {
        movie = mkOption {
          type = types.nullOr quotaType;
          default = null;
          description = "Default movie request quota.";
        };
        tv = mkOption {
          type = types.nullOr quotaType;
          default = null;
          description = "Default television request quota.";
        };
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional prerequisite units for Seerr reconciliation.";
      };
      extraMainSettings = mkOption {
        inherit (json) type;
        default = { };
        description = "Version-specific Seerr main settings outside the stable typed interface.";
      };
      extraNotificationSettings = mkOption {
        inherit (json) type;
        default = { };
        description = "Version-specific Seerr notification settings.";
      };
    };
  };
  knownDestinations = lib.filterAttrs (
    _: destination: cfg.servarr ? ${destination.manager}
  ) seerr.destinations;
  parseUrl =
    url:
    let
      match = builtins.match "(https?)://([^/:]+)(:([0-9]+))?(/.*)?" url;
    in
    if match == null then
      null
    else
      let
        baseUrl = builtins.elemAt match 4;
      in
      {
        useSsl = builtins.elemAt match 0 == "https";
        hostname = builtins.elemAt match 1;
        port =
          if builtins.elemAt match 3 == null then
            (if builtins.elemAt match 0 == "https" then 443 else 80)
          else
            builtins.fromJSON (builtins.elemAt match 3);
        baseUrl = if baseUrl == null then "" else baseUrl;
      };
  destination =
    item:
    let
      manager = cfg.servarr.${item.manager};
      address = parseUrl manager.url;
      root = manager.rootFolders.${item.rootFolder};
    in
    {
      inherit (item)
        name
        isDefault
        is4k
        syncEnabled
        preventSearch
        ;
      inherit (address)
        hostname
        port
        useSsl
        baseUrl
        ;
      apiKey = {
        _secret = manager.apiKeyFile;
      };
      activeProfileName = item.qualityProfile;
      activeDirectory = root.path;
      externalUrl = "";
    }
    // lib.optionalAttrs (manager.kind == "radarr") { inherit (item) minimumAvailability; }
    // lib.optionalAttrs (manager.kind == "sonarr") { inherit (item) enableSeasonFolders; }
    // item.extraSettings;
  byKind =
    kind:
    builtins.listToAttrs (
      map
        (item: {
          inherit (item) name;
          value = destination item;
        })
        (
          lib.attrValues (
            lib.filterAttrs (_: item: cfg.servarr.${item.manager}.kind == kind) knownDestinations
          )
        )
    );
  destinationNames = map (item: item.name) (lib.attrValues seerr.destinations);
  permissionMask = lib.foldl' (
    total: name: total + permissionValues.${name}
  ) 0 seerr.defaultPermissions;
  quota = item: {
    quotaLimit = item.limit;
    quotaDays = item.days;
  };
  defaultQuotas = lib.filterAttrs (_: value: value != null) {
    movie = if seerr.quotas.movie == null then null else quota seerr.quotas.movie;
    tv = if seerr.quotas.tv == null then null else quota seerr.quotas.tv;
  };
in
{
  options.homelab.integrations.seerr = mkOption {
    type = types.nullOr seerrType;
    default = null;
    description = "Typed Seerr onboarding, destination and conservative request policy reconciliation.";
  };

  config = lib.mkIf (seerr != null) {
    homelab.integration.enable = lib.mkDefault true;
    homelab.integration.services.seerr = {
      kind = "seerr";
      inherit (seerr) url apiKeyFile mode;
      after = lib.unique (
        seerr.after
        ++ [ "homelab-integrate-jellyfin.service" ]
        ++ map (item: "homelab-integrate-${item.manager}.service") (lib.attrValues knownDestinations)
      );
      settings = {
        login = {
          username = jellyfin.administrator.name;
          password = {
            _secret = jellyfin.administrator.passwordFile;
          };
          inherit (seerr.jellyfin)
            hostname
            port
            useSsl
            urlBase
            email
            ;
          serverType = 2;
        };
        libraries = seerr.jellyfin.libraries;
        radarr = byKind "radarr";
        sonarr = byKind "sonarr";
        main = lib.recursiveUpdate (
          {
            defaultPermissions = permissionMask;
          }
          // lib.optionalAttrs (defaultQuotas != { }) { inherit defaultQuotas; }
        ) seerr.extraMainSettings;
      }
      // lib.optionalAttrs (seerr.extraNotificationSettings != { }) {
        notifications = seerr.extraNotificationSettings;
      };
    };
    assertions = [
      {
        assertion = cfg.jellyfin != null;
        message = "Typed Seerr integration requires homelab.integrations.jellyfin.";
      }
      {
        assertion =
          seerr.allowAutomaticRequests
          || lib.intersectLists automaticPermissions seerr.defaultPermissions == [ ];
        message = "Seerr auto-approval and automatic-request permissions require allowAutomaticRequests.";
      }
      {
        assertion =
          builtins.length seerr.defaultPermissions == builtins.length (lib.unique seerr.defaultPermissions);
        message = "Seerr defaultPermissions must not contain duplicates.";
      }
      {
        assertion = builtins.length destinationNames == builtins.length (lib.unique destinationNames);
        message = "Seerr destination display names must be unique.";
      }
    ]
    ++ lib.mapAttrsToList (name: item: {
      assertion =
        cfg.servarr ? ${item.manager}
        && builtins.elem cfg.servarr.${item.manager}.kind [
          "sonarr"
          "radarr"
        ]
        && cfg.servarr.${item.manager}.rootFolders ? ${item.rootFolder}
        && parseUrl cfg.servarr.${item.manager}.url != null;
      message = "Seerr destination ${name} must reference a parseable Sonarr/Radarr instance and one of its roots.";
    }) seerr.destinations;
  };
}
