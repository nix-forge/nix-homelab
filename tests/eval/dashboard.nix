{ evaluate, lib }:
let
  fixture = {
    security.acme = {
      acceptTerms = true;
      certs."example.test" = {
        webroot = "/var/lib/acme/acme-challenge";
        extraDomainNames = [ "*.example.test" ];
        group = "nginx";
      };
    };
    homelab.operations = {
      enable = true;
      monitoring.enable = true;
      lanHttps = {
        enable = true;
        domain = "example.test";
        certificateHost = "example.test";
        listenAddresses = [ "192.168.1.10" ];
        allowedCIDRs = [ "192.168.1.0/24" ];
        sites = {
          media.upstream = "http://127.0.0.1:8096";
          private = {
            upstream = "http://127.0.0.1:3000";
            allowedCIDRs = [ "127.0.0.0/8" ];
          };
        };
      };
      dashboard = {
        enable = true;
        exposeViaLanHttps = true;
        authEnvironmentFile = "/run/secrets/homepage";
        catalog.media = {
          title = "Media";
          group = "Watch";
          icon = "jellyfin";
        };
        catalog.private.allowRestricted = true;
        catalog.remote = {
          url = "https://remote.example.test";
          group = "Remote";
        };
        groupOrder = [
          "Watch"
          "Remote"
        ];
      };
    };
  };
  configured = (evaluate fixture).config;
  customListeners =
    (evaluate (
      lib.recursiveUpdate fixture {
        services.homepage-dashboard.listenPort = 18082;
        services.gatus.settings.web = {
          address = "::1";
          port = 18083;
        };
      }
    )).config;
  ipv6Homepage =
    (evaluate (
      lib.recursiveUpdate fixture { systemd.services.homepage-dashboard.environment.HOSTNAME = "::"; }
    )).config;
  invalidIPv6 =
    (evaluate (
      lib.recursiveUpdate fixture { homelab.operations.lanHttps.listenAddresses = [ "2001:db8:::1" ]; }
    )).config;
  explicitUpstream =
    (evaluate (
      lib.recursiveUpdate fixture {
        services.homepage-dashboard.listenPort = 18082;
        homelab.operations.dashboard.upstream = "http://127.0.0.1:19000";
      }
    )).config;
  invalidAuth =
    (evaluate (
      lib.recursiveUpdate fixture { homelab.operations.dashboard.authEnvironmentFile = null; }
    )).config;
  invalidUrl =
    (evaluate (
      lib.recursiveUpdate fixture {
        homelab.operations.dashboard.catalog.remote.url = "http://127.0.0.1:9090";
      }
    )).config;
  invalidRestricted =
    (evaluate (
      lib.recursiveUpdate fixture {
        homelab.operations.dashboard.catalog.private.allowRestricted = false;
      }
    )).config;
  filtered =
    (evaluate (
      lib.recursiveUpdate fixture {
        homelab.operations.dashboard.catalog.remote.visible = false;
        homelab.operations.dashboard.catalog.private.monitor = false;
      }
    )).config;
  sections = configured.services.homepage-dashboard.services;
  section = name: builtins.head (lib.filter (item: builtins.hasAttr name item) sections);
  httpsProbes = lib.filter (
    item: item.group or null == "HTTPS"
  ) configured.services.gatus.settings.endpoints;
in
{
  followsNativeListeners =
    customListeners.homelab.operations.lanHttps.sites.dashboard.upstream == "http://127.0.0.1:18082"
    &&
      customListeners.services.nginx.virtualHosts."dashboard.example.test".locations."= /api/auth/callback/credentials".proxyPass
      == "http://127.0.0.1:18082"
    &&
      (builtins.head (builtins.head customListeners.services.homepage-dashboard.services).Status)
      .Gatus.widget.url == "http://[::1]:18083";
  ipv6LoopbackProxy =
    ipv6Homepage.homelab.operations.lanHttps.sites.dashboard.upstream == "http://[::1]:8082"
    && lib.all (entry: entry.assertion) ipv6Homepage.assertions;
  rejectsMalformedIpv6 = lib.any (entry: !entry.assertion) invalidIPv6.assertions;
  retainsExplicitUpstream =
    explicitUpstream.homelab.operations.lanHttps.sites.dashboard.upstream == "http://127.0.0.1:19000";
  discoversSites =
    configured.homelab.operations.dashboard.catalog.media.url == "https://media.example.test"
    && configured.homelab.operations.dashboard.catalog.private.url == "https://private.example.test"
    && configured.homelab.operations.dashboard.catalog.remote.url == "https://remote.example.test";
  groupsCardsAndStatus =
    (section "Watch").Watch == [
      {
        Media = {
          href = "https://media.example.test";
          description = "Open media";
          icon = "jellyfin";
        };
      }
    ]
    && (builtins.head sections).Status != [ ]
    && ((builtins.head (section "Desktop only")."Desktop only").Private.description == "Desktop only");
  probesAreHttps =
    builtins.length httpsProbes == 4
    && lib.all (item: lib.hasPrefix "https://" item.url) httpsProbes
    && lib.all (item: builtins.elem "[CERTIFICATE_EXPIRATION] > 168h" item.conditions) httpsProbes
    && lib.all (
      item: builtins.elem "[STATUS] == any(200, 301, 302, 303, 307, 308, 401)" item.conditions
    ) httpsProbes;
  cardAndProbeControls =
    !(lib.any (item: builtins.hasAttr "Remote" item) filtered.services.homepage-dashboard.services)
    && lib.any (
      item: item.url == "https://remote.example.test"
    ) filtered.services.gatus.settings.endpoints
    && !(lib.any (
      item: item.url == "https://private.example.test"
    ) filtered.services.gatus.settings.endpoints);
  privateIngress =
    configured.services.homepage-dashboard.allowedHosts == "dashboard.example.test"
    && configured.systemd.services.homepage-dashboard.environment.HOMEPAGE_AUTH_ENABLED == "true"
    && configured.services.homepage-dashboard.environmentFiles == [ "/run/secrets/homepage" ]
    &&
      lib.hasInfix "limit_req zone=homepage_login"
        configured.services.nginx.virtualHosts."dashboard.example.test".locations."= /api/auth/callback/credentials".extraConfig;
  rejectsUnsafeExposure =
    lib.any (assertion: !assertion.assertion) invalidAuth.assertions
    && lib.any (assertion: !assertion.assertion) invalidUrl.assertions
    && lib.any (assertion: !assertion.assertion) invalidRestricted.assertions;
  dashboardAssertionsPass =
    lib.assertMsg (lib.all (assertion: assertion.assertion) configured.assertions)
      (
        "Dashboard fixture assertions failed: "
        + builtins.toJSON (
          map (assertion: assertion.message) (
            lib.filter (assertion: !assertion.assertion) configured.assertions
          )
        )
      );
}
