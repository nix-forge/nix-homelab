{ evaluate, lib }:
let
  configured =
    (evaluate {
      homelab.optional.apps = {
        scrutiny.enable = true;
        syncthing.enable = true;
        adguardhome.enable = true;
      };
      homelab.operations = {
        enable = true;
        monitoring.enable = true;
        dashboard.enable = true;
        endpoints.manual-api = {
          url = "http://127.0.0.1:19000";
          monitor = false;
        };
      };
      services.scrutiny = {
        settings.web.listen.port = 18083;
        collector.enable = false;
      };
    }).config;
  adguardEndpoint =
    service: override:
    (evaluate {
      homelab.optional.apps.adguardhome.enable = true;
      homelab.operations = {
        enable = true;
      }
      // lib.optionalAttrs (override != { }) { endpoints.adguardhome = override; };
      # Explicit native addresses must not also activate the deprecated host adapter.
      services.adguardhome = {
        host = null;
      }
      // service;
    }).config.homelab.operations.endpoints.adguardhome;
in
{
  scrutinyPortDerived =
    configured.homelab.operations.endpoints.scrutiny.url == "http://127.0.0.1:18083";
  scrutinyDatabaseStopped = builtins.elem "influxdb2.service" configured.homelab.operations.state.scrutiny.units;
  syncthingIdentityPreserved = builtins.elem configured.services.syncthing.configDir configured.homelab.operations.state.syncthing.paths;
  adguardDefaultEndpoint =
    configured.services.adguardhome.settings.http.address == "127.0.0.1:3000"
    && configured.homelab.operations.endpoints.adguardhome.url == "http://127.0.0.1:3000";
  adguardConfiguredIPv4Endpoint =
    (adguardEndpoint { settings.http.address = "127.0.0.2:13000"; } { }).url
    == "http://127.0.0.2:13000";
  adguardConfiguredHostnameEndpoint =
    (adguardEndpoint { settings.http.address = "dns.example.invalid:13001"; } { }).url
    == "http://dns.example.invalid:13001";
  adguardConfiguredIPv6Endpoint =
    (adguardEndpoint { settings.http.address = "[::1]:13002"; } { }).url == "http://[::1]:13002";
  adguardWildcardIPv6IsReachable =
    (adguardEndpoint { settings.http.address = "[::]:13003"; } { }).url == "http://[::1]:13003";
  adguardProxyEndpointOverridePreserved =
    (adguardEndpoint { settings.http.address = "127.0.0.1:13004"; } {
      url = "https://dns.example.invalid";
    }).url == "https://dns.example.invalid";
  adguardAvailabilityPolicyPreserved =
    configured.homelab.operations.endpoints.adguardhome.conditions
    == [ "[STATUS] == any(200, 302, 303, 307, 308, 401, 403)" ];
  adguardStatePreserved =
    configured.homelab.operations.state.adguardhome.paths == [ "/var/lib/AdGuardHome" ];
  dashboardOnlyEndpoint =
    !(lib.any (endpoint: endpoint.name == "manual-api") configured.services.gatus.settings.endpoints)
    &&
      lib.any (entry: lib.any (card: card.href == "http://127.0.0.1:19000") (builtins.attrValues entry))
        (builtins.head (
          lib.filter (
            section: builtins.hasAttr "Homelab" section
          ) configured.services.homepage-dashboard.services
        )).Homelab;
  assertionsPass = lib.all (entry: entry.assertion) configured.assertions;
}
