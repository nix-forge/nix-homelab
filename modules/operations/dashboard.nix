{ config, lib, ... }:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  ops = config.homelab.operations;
  cfg = ops.dashboard;
  lan = ops.lanHttps;
  siteHost = "${cfg.siteName}.${lan.domain}";
  publicUrl = "https://${siteHost}";
  localSites = lib.filterAttrs (name: _: name != cfg.siteName) lan.sites;
  displayName =
    name:
    lib.concatStringsSep " " (
      map (
        word:
        lib.toUpper (builtins.substring 0 1 word)
        + builtins.substring 1 (builtins.stringLength word - 1) word
      ) (lib.filter (word: word != "") (lib.splitString "-" (lib.replaceStrings [ "_" ] [ "-" ] name)))
    );
  isLoopbackCIDR = cidr: lib.hasPrefix "127." cidr || lib.hasPrefix "::1/" cidr;
  clientCIDRs = builtins.filter (cidr: !(isLoopbackCIDR cidr)) lan.allowedCIDRs;
  isRestricted =
    site:
    site.allowedCIDRs != null && !(lib.all (cidr: builtins.elem cidr site.allowedCIDRs) clientCIDRs);
  localCatalog = lib.mapAttrs (
    name: site:
    let
      allowed = if site.allowedCIDRs == null then lan.allowedCIDRs else site.allowedCIDRs;
    in
    {
      url = mkDefault "https://${name}.${lan.domain}";
      group = mkDefault (
        if lib.all isLoopbackCIDR allowed then
          "Desktop only"
        else if isRestricted site then
          "Restricted"
        else
          "Services"
      );
      description = mkDefault (
        if lib.all isLoopbackCIDR allowed then
          "Desktop only"
        else if isRestricted site then
          "Restricted access"
        else
          "Open ${name}"
      );
    }
  ) localSites;
  endpointCatalog = lib.mapAttrs (_name: endpoint: {
    url = mkDefault endpoint.url;
    description = mkDefault endpoint.description;
  }) (lib.filterAttrs (_: endpoint: endpoint.enable) ops.endpoints);
  visible = lib.filterAttrs (_: entry: entry.visible) cfg.catalog;
  groupNames = lib.unique (map (entry: entry.group) (lib.attrValues visible));
  groups =
    builtins.filter (name: builtins.elem name groupNames) cfg.groupOrder
    ++ builtins.filter (name: !(builtins.elem name cfg.groupOrder)) groupNames;
  cards =
    group:
    lib.mapAttrsToList (_: entry: {
      ${entry.title} = {
        href = entry.url;
        inherit (entry) description;
      }
      // lib.optionalAttrs (entry.icon != null) { inherit (entry) icon; };
    }) (lib.filterAttrs (_: entry: entry.group == group) visible);
  localAddress =
    address:
    if address == "0.0.0.0" || address == "" then
      "127.0.0.1"
    else if address == "::" then
      "[::1]"
    else if lib.hasInfix ":" address && !lib.hasPrefix "[" address then
      "[${address}]"
    else
      address;
  homepageAddress = localAddress (
    config.systemd.services.homepage-dashboard.environment.HOSTNAME or "127.0.0.1"
  );
  statusCard = {
    Status = [
      {
        Gatus = {
          description = "Service health and HTTPS checks";
          icon = "gatus";
          widget = {
            type = "gatus";
            url = "http://${
              localAddress (config.services.gatus.settings.web.address or "127.0.0.1")
            }:${toString config.services.gatus.settings.web.port}";
          };
        };
      }
    ];
  };
  statusEnabled = cfg.statusWidget && config.services.gatus.enable;
  statusLayout = {
    Status = {
      style = "row";
      columns = 1;
    };
  };
  tlsEntries = lib.filterAttrs (
    _: entry: entry.monitor && entry.url != null && lib.hasPrefix "https://" entry.url
  ) cfg.catalog;
  probe = name: entry: {
    inherit name;
    group = "HTTPS";
    inherit (entry) url;
    interval = cfg.monitorInterval;
    client.timeout = cfg.monitorTimeout;
    conditions = [
      # A 403 can be nginx's client-CIDR denial, so it cannot establish a
      # usable browser route from this monitor's position.
      "[STATUS] == any(200, 301, 302, 303, 307, 308, 401)"
      "[CERTIFICATE_EXPIRATION] > ${cfg.certificateWarning}"
    ];
  };
in
{
  options.homelab.operations.dashboard = {
    enable = mkEnableOption "a private Homepage directory generated from declared sites";
    siteName = mkOption {
      type = types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "dashboard";
      description = "LAN HTTPS site name for Homepage when exposeViaLanHttps is enabled.";
    };
    exposeViaLanHttps = mkEnableOption "a private HTTPS Homepage route with a rate-limited password login";
    upstream = mkOption {
      type = types.str;
      default = "http://${homepageAddress}:${toString config.services.homepage-dashboard.listenPort}";
      description = "Homepage loopback URL used by the private HTTPS proxy.";
    };
    authEnvironmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime EnvironmentFile containing HOMEPAGE_AUTH_SECRET and HOMEPAGE_AUTH_PASSWORD. Required for HTTPS exposure.";
    };
    title = mkOption {
      type = types.str;
      default = "Homelab";
      description = "Homepage browser title.";
    };
    catalog = mkOption {
      default = { };
      description = "Browser-facing entries. LAN HTTPS sites are discovered automatically; add external hosts and optional presentation overrides here.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              url = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Browser-facing URL, generated for local HTTPS sites or supplied for external hosts.";
              };
              title = mkOption {
                type = types.str;
                default = displayName name;
                description = "Card title.";
              };
              description = mkOption {
                type = types.str;
                default = "Open ${name}";
                description = "Card subtitle. A restricted LAN HTTPS site defaults to Desktop only.";
              };
              group = mkOption {
                type = types.str;
                default = "Homelab";
                description = "Homepage section containing this card.";
              };
              icon = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional Homepage icon identifier.";
              };
              visible = mkOption {
                type = types.bool;
                default = true;
                description = "Show this entry in Homepage. Monitoring can remain enabled when hidden.";
              };
              allowRestricted = mkOption {
                type = types.bool;
                default = false;
                description = "Explicitly show a link that does not admit every dashboard client CIDR. The card will be inaccessible to some viewers.";
              };
              monitor = mkOption {
                type = types.bool;
                default = true;
                description = "Check the HTTPS browser route in Gatus when HTTPS monitoring is enabled.";
              };
            };
          }
        )
      );
    };
    groupOrder = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Preferred section order. Undeclared groups follow in stable name order.";
    };
    groupColumns = mkOption {
      type = types.attrsOf types.ints.positive;
      default = { };
      description = "Number of columns per section; other sections use four.";
    };
    statusWidget = mkOption {
      type = types.bool;
      default = true;
      description = "Show a Gatus summary tile when Gatus is enabled.";
    };
    httpsMonitoring = mkOption {
      type = types.bool;
      default = ops.monitoring.enable;
      description = "Add HTTPS and certificate probes to the existing Gatus monitor.";
    };
    monitorInterval = mkOption {
      type = types.str;
      default = "5m";
      description = "Gatus interval for browser-facing HTTPS probes.";
    };
    monitorTimeout = mkOption {
      type = types.str;
      default = "5s";
      description = "HTTP timeout for browser-facing HTTPS probes.";
    };
    certificateWarning = mkOption {
      type = types.str;
      default = "168h";
      description = "Minimum accepted TLS certificate lifetime for browser-facing probes.";
    };
  };

  config = mkIf (ops.enable && cfg.enable) (
    lib.mkMerge [
      {
        homelab.operations.dashboard.catalog = if lan.enable then localCatalog else endpointCatalog;
        assertions = [
          {
            assertion = lib.all (entry: entry.url != null) (lib.attrValues cfg.catalog);
            message = "Every dashboard catalog entry needs a browser URL.";
          }
          {
            assertion =
              !cfg.exposeViaLanHttps
              || (
                lan.enable
                && cfg.authEnvironmentFile != null
                && lib.hasPrefix "/" cfg.authEnvironmentFile
                && !(lib.hasPrefix "/nix/store/" cfg.authEnvironmentFile)
                && lib.all (
                  entry: entry.url != null && builtins.match "https://[^/@?#]+(/[^?#]*)?" entry.url != null
                ) (lib.attrValues cfg.catalog)
              );
            message = "Exposed Homepage requires LAN HTTPS, a runtime auth file, and credential-free HTTPS card URLs.";
          }
          {
            assertion = !cfg.httpsMonitoring || config.services.gatus.enable;
            message = "HTTPS dashboard probes require Gatus.";
          }
          {
            assertion =
              !cfg.exposeViaLanHttps
              || lib.all (
                name:
                let
                  card = cfg.catalog.${name};
                in
                !card.visible || card.allowRestricted || !(isRestricted localSites.${name})
              ) (builtins.attrNames localSites);
            message = "Exposed dashboard cards must admit every approved client CIDR; hide or explicitly mark restricted sites.";
          }
        ];
        services.homepage-dashboard = {
          enable = true;
          openFirewall = mkDefault false;
          environmentFiles = lib.optional (cfg.authEnvironmentFile != null) cfg.authEnvironmentFile;
          services = lib.optional statusEnabled statusCard ++ map (group: { ${group} = cards group; }) groups;
          settings = {
            title = mkDefault cfg.title;
            description = mkDefault "Private service directory";
            theme = mkDefault "dark";
            color = mkDefault "slate";
            disableIndexing = mkDefault true;
            headerStyle = mkDefault "clean";
            useEqualHeights = mkDefault true;
            layout =
              lib.optional statusEnabled statusLayout
              ++ map (group: {
                ${group} = {
                  style = "row";
                  columns = cfg.groupColumns.${group} or 4;
                };
              }) groups;
          };
          widgets = [
            {
              search = {
                provider = "duckduckgo";
                target = "_blank";
              };
            }
          ];
        };
        systemd.services.homepage-dashboard.environment = {
          HOSTNAME = mkDefault "127.0.0.1";
        }
        // lib.optionalAttrs (cfg.authEnvironmentFile != null) { HOMEPAGE_AUTH_ENABLED = "true"; }
        // lib.optionalAttrs cfg.exposeViaLanHttps { HOMEPAGE_EXTERNAL_URL = publicUrl; };
      }
      (mkIf cfg.exposeViaLanHttps {
        homelab.operations.lanHttps.sites.${cfg.siteName}.upstream = cfg.upstream;
        services.homepage-dashboard.allowedHosts = siteHost;
        services.nginx = {
          appendHttpConfig = ''
            limit_req_zone $binary_remote_addr zone=homepage_login:1m rate=5r/m;
          '';
          # Keep the conditional at the declared option boundary. Constructing
          # a dynamic hostname earlier forces the domain even when disabled.
          virtualHosts = mkIf cfg.exposeViaLanHttps {
            ${siteHost}.locations."= /api/auth/callback/credentials" = {
              proxyPass = cfg.upstream;
              extraConfig = ''
                limit_req zone=homepage_login burst=5 nodelay;
                limit_req_status 429;
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $remote_addr;
                proxy_cookie_flags ~.* secure;
              '';
            };
          };
        };
      })
      (mkIf cfg.httpsMonitoring {
        services.gatus.settings = {
          storage = {
            type = mkDefault "sqlite";
            path = mkDefault "/var/lib/gatus/data.db";
            maximum-number-of-results = mkDefault 720;
            maximum-number-of-events = mkDefault 100;
          };
          endpoints = lib.mkAfter (
            lib.mapAttrsToList probe tlsEntries
            ++ lib.optional cfg.exposeViaLanHttps (probe cfg.siteName { url = publicUrl; })
          );
        };
      })
    ]
  );
}
