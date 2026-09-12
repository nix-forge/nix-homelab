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
in
{
  scrutinyPortDerived =
    configured.homelab.operations.endpoints.scrutiny.url == "http://127.0.0.1:18083";
  scrutinyDatabaseStopped = builtins.elem "influxdb2.service" configured.homelab.operations.state.scrutiny.units;
  syncthingIdentityPreserved = builtins.elem configured.services.syncthing.configDir configured.homelab.operations.state.syncthing.paths;
  adguardStatePreserved =
    configured.homelab.operations.state.adguardhome.paths == [ "/var/lib/AdGuardHome" ];
  dashboardOnlyEndpoint =
    !(lib.any (endpoint: endpoint.name == "manual-api") configured.services.gatus.settings.endpoints)
    && lib.any (
      entry: builtins.hasAttr "manual-api" entry
    ) (builtins.head configured.services.homepage-dashboard.services).Homelab;
  assertionsPass = lib.all (entry: entry.assertion) configured.assertions;
}
