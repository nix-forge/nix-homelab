{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.integrations;
  json = pkgs.formats.json { };
  pathType = types.strMatching "/[A-Za-z0-9_./-]+";
  optional =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
  secret = path: { _secret = path; };
  tag = name: {
    _lookup = {
      endpoint = "tag";
      inherit name;
    };
  };
  applicationType = types.submodule (
    { name, ... }: {
      options = {
        manager = mkOption {
          type = types.str;
          default = name;
          description = "Named homelab.integrations.servarr instance to synchronize.";
        };
        name = mkOption {
          type = types.str;
          default = name;
          description = "Stable display name owned in Prowlarr.";
        };
        syncLevel = mkOption {
          type = types.enum [
            "addOnly"
            "fullSync"
          ];
          default = "fullSync";
          description = "Whether Prowlarr only adds indexers or also updates and removes synchronized indexers.";
        };
        syncCategories = optional (types.listOf types.ints.unsigned) "Newznab categories to synchronize; null uses the pinned Prowlarr defaults.";
        animeSyncCategories = mkOption {
          type = types.listOf types.ints.unsigned;
          default = [ 5070 ];
          description = "Sonarr anime categories synchronized in addition to the standard categories.";
        };
        syncAnimeStandardFormatSearch = mkOption {
          type = types.bool;
          default = true;
          description = "Allow Prowlarr to synchronize Sonarr's standard-numbering anime search.";
        };
        syncRejectBlocklistedTorrentHashesWhileGrabbing = mkOption {
          type = types.bool;
          default = false;
          description = "Ask the target manager to reject blocklisted torrent hashes while grabbing.";
        };
        authUsername = optional types.str "Optional application HTTP-auth username.";
        authPasswordFile = optional pathType "Runtime file containing application HTTP-auth password.";
        extraFields = mkOption {
          inherit (json) type;
          default = { };
          description = "Schema-checked application fields not covered by the stable typed interface.";
        };
      };
    }
  );
  proxyType = types.submodule (
    { name, ... }: {
      options = {
        type = mkOption {
          type = types.enum [
            "http"
            "socks5"
            "flaresolverr"
          ];
          description = "Prowlarr indexer-proxy implementation.";
        };
        name = mkOption {
          type = types.str;
          default = name;
          description = "Stable display name owned in Prowlarr.";
        };
        tags = mkOption {
          type = types.nonEmptyListOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9._ -]*");
          description = "Named tags selecting the indexers that use this proxy.";
        };
        host = optional types.str "HTTP or SOCKS5 proxy host name or address.";
        port = optional types.port "HTTP or SOCKS5 proxy port.";
        url = optional types.str "FlareSolverr-compatible service URL.";
        username = optional types.str "Optional HTTP or SOCKS5 proxy username.";
        passwordFile = optional pathType "Runtime file containing proxy password.";
        requestTimeout = mkOption {
          type = types.ints.between 1 180;
          default = 60;
          description = "FlareSolverr request timeout in seconds.";
        };
        extraFields = mkOption {
          inherit (json) type;
          default = { };
          description = "Schema-checked proxy fields not covered by the stable typed interface.";
        };
      };
    }
  );
  indexerType = types.submodule (
    { name, ... }: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Stable display name owned in Prowlarr.";
        };
        implementation = mkOption {
          type = types.str;
          description = "Implementation selected from the running Prowlarr indexer schema.";
        };
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable this indexer in Prowlarr.";
        };
        priority = mkOption {
          type = types.ints.between 1 50;
          default = 25;
          description = "Indexer priority; lower values are preferred.";
        };
        tags = mkOption {
          type = types.listOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9._ -]*");
          default = [ ];
          description = "Named tags used for proxy selection and application filtering.";
        };
        fields = mkOption {
          inherit (json) type;
          default = { };
          description = "Non-secret provider fields validated against the running Prowlarr schema.";
        };
        secretFields = mkOption {
          type = types.attrsOf pathType;
          default = { };
          description = "Provider field names mapped to runtime secret files.";
        };
        extraSettings = mkOption {
          inherit (json) type;
          default = { };
          description = "Schema-checked indexer settings outside the stable typed interface.";
        };
      };
    }
  );
  prowlarrType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "Prowlarr API base URL, including a URL base when configured.";
      };
      apiKeyFile = mkOption {
        type = pathType;
        description = "Runtime file containing the Prowlarr API key.";
      };
      installApiKey = mkOption {
        type = types.bool;
        default = false;
        description = "Install the declared API key into the local native Prowlarr service.";
      };
      mode = mkOption {
        type = types.enum [
          "bootstrap"
          "managed"
        ];
        default = "bootstrap";
        description = "Bootstrap preserves existing matches; managed updates declared fields. Neither mode deletes resources.";
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional prerequisite units for Prowlarr reconciliation.";
      };
      applications = mkOption {
        type = types.attrsOf applicationType;
        default = { };
        description = "Named Servarr instances synchronized by Prowlarr.";
      };
      proxies = mkOption {
        type = types.attrsOf proxyType;
        default = { };
        description = "Tagged per-indexer proxies managed in Prowlarr.";
      };
      indexers = mkOption {
        type = types.attrsOf indexerType;
        default = { };
        description = "Opt-in provider indexers; provider-specific fields remain runtime-schema validated.";
      };
      extraResources = mkOption {
        type = types.listOf json.type;
        default = [ ];
        description = "Unsupported schema-checked Prowlarr resources for forward compatibility.";
      };
    };
  };
  inherit (cfg) prowlarr;
  managers = cfg.servarr;
  knownApplications = lib.filterAttrs (_: app: managers ? ${app.manager}) prowlarr.applications;
  categoryDefaults = {
    sonarr = [
      5000
      5010
      5020
      5030
      5040
      5045
      5050
      5090
    ];
    radarr = [
      2000
      2010
      2020
      2030
      2040
      2045
      2050
      2060
      2070
      2080
      2090
    ];
    lidarr = [
      3000
      3010
      3030
      3040
      3050
      3060
    ];
  };
  applicationResource =
    app:
    let
      manager = managers.${app.manager};
      categories =
        if app.syncCategories == null then categoryDefaults.${manager.kind} else app.syncCategories;
      authFields =
        lib.optionalAttrs (app.authUsername != null) { inherit (app) authUsername; }
        // lib.optionalAttrs (app.authPasswordFile != null) { authPassword = secret app.authPasswordFile; };
      kindFields = lib.optionalAttrs (manager.kind == "sonarr") {
        inherit (app) animeSyncCategories syncAnimeStandardFormatSearch;
      };
    in
    {
      endpoint = "applications";
      match.name = app.name;
      values = {
        implementation = lib.toSentenceCase manager.kind;
        inherit (app) syncLevel;
        fields = {
          prowlarrUrl = prowlarr.url;
          baseUrl = manager.url;
          apiKey = secret manager.apiKeyFile;
          syncCategories = categories;
          inherit (app) syncRejectBlocklistedTorrentHashesWhileGrabbing;
        }
        // kindFields
        // authFields
        // app.extraFields;
      };
    };
  tagResources = map (label: {
    endpoint = "tag";
    match = { inherit label; };
    values = { };
  });
  proxyFields =
    proxy:
    if proxy.type == "flaresolverr" then
      {
        host = proxy.url;
        inherit (proxy) requestTimeout;
      }
      // proxy.extraFields
    else
      {
        inherit (proxy) host port;
      }
      // lib.optionalAttrs (proxy.username != null) { inherit (proxy) username; }
      // lib.optionalAttrs (proxy.passwordFile != null) { password = secret proxy.passwordFile; }
      // proxy.extraFields;
  proxyResource = proxy: {
    endpoint = "indexerproxy";
    match.name = proxy.name;
    values = {
      implementation =
        {
          http = "Http";
          socks5 = "Socks5";
          flaresolverr = "FlareSolverr";
        }
        .${proxy.type};
      tags = map tag proxy.tags;
      fields = proxyFields proxy;
    };
  };
  indexerResource = indexer: {
    endpoint = "indexer";
    match.name = indexer.name;
    values = {
      inherit (indexer) implementation enable priority;
      tags = map tag indexer.tags;
      fields = indexer.fields // lib.mapAttrs (_: secret) indexer.secretFields;
    }
    // indexer.extraSettings;
  };
  allTags = lib.unique (
    lib.concatMap (proxy: proxy.tags) (lib.attrValues prowlarr.proxies)
    ++ lib.concatMap (indexer: indexer.tags) (lib.attrValues prowlarr.indexers)
  );
  secretPaths = [
    prowlarr.apiKeyFile
  ]
  ++ lib.filter (value: value != null) (
    map (app: app.authPasswordFile) (lib.attrValues prowlarr.applications)
  )
  ++ lib.filter (value: value != null) (
    map (proxy: proxy.passwordFile) (lib.attrValues prowlarr.proxies)
  )
  ++ lib.concatMap (indexer: lib.attrValues indexer.secretFields) (lib.attrValues prowlarr.indexers);
  runtimePath = path: lib.hasPrefix "/" path && !(lib.hasPrefix "/nix/store" path);
  sensitiveField =
    name:
    lib.any (fragment: lib.hasInfix fragment (lib.toLower name)) [
      "apikey"
      "cookie"
      "passkey"
      "password"
      "secret"
      "token"
    ];
in
{
  options.homelab.integrations.prowlarr = mkOption {
    type = types.nullOr prowlarrType;
    default = null;
    description = "Typed Prowlarr application, indexer, tag and per-indexer proxy reconciliation.";
  };

  config = lib.mkIf (prowlarr != null) {
    homelab.integration.enable = lib.mkDefault true;
    homelab.integration.services.prowlarr = {
      kind = "prowlarr";
      inherit (prowlarr)
        url
        apiKeyFile
        installApiKey
        mode
        extraResources
        ;
      after = lib.unique (
        prowlarr.after
        ++ map (app: "homelab-integrate-${app.manager}.service") (lib.attrValues knownApplications)
      );
      resources =
        (tagResources allTags)
        ++ (map applicationResource (lib.attrValues knownApplications))
        ++ (map proxyResource (lib.attrValues prowlarr.proxies))
        ++ (map indexerResource (lib.attrValues prowlarr.indexers));
    };
    assertions = [
      {
        assertion = lib.all runtimePath secretPaths;
        message = "Prowlarr integration secrets must be absolute runtime paths outside the Nix store.";
      }
    ]
    ++ lib.mapAttrsToList (name: app: {
      assertion =
        managers ? ${app.manager} && (app.authUsername == null) == (app.authPasswordFile == null);
      message = "Prowlarr application ${name} must reference a known Servarr instance and supply both HTTP-auth values or neither.";
    }) prowlarr.applications
    ++ lib.mapAttrsToList (name: proxy: {
      assertion =
        builtins.length proxy.tags == builtins.length (lib.unique proxy.tags)
        && (
          if proxy.type == "flaresolverr" then
            proxy.url != null
            && proxy.host == null
            && proxy.port == null
            && proxy.username == null
            && proxy.passwordFile == null
          else
            proxy.url == null
            && proxy.host != null
            && proxy.port != null
            && (proxy.username == null) == (proxy.passwordFile == null)
        );
      message = "Prowlarr proxy ${name} has fields that do not match its implementation or has duplicate tags.";
    }) prowlarr.proxies
    ++ lib.mapAttrsToList (name: indexer: {
      assertion =
        builtins.length indexer.tags == builtins.length (lib.unique indexer.tags)
        && lib.all (field: !(sensitiveField field)) (builtins.attrNames indexer.fields)
        && lib.all (field: !(indexer.fields ? ${field})) (builtins.attrNames indexer.secretFields);
      message = "Prowlarr indexer ${name} has duplicate tags, a literal sensitive field, or overlapping public and secret fields.";
    }) prowlarr.indexers;
  };
}
