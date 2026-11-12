{ evaluate, lib }:
let
  configured =
    (evaluate {
      services.actual.enable = true;
      homelab.operations.enable = true;
    }).config;
  encryptedDataDir =
    (evaluate {
      services.actual = {
        enable = true;
        settings.dataDir = "/srv/actual/server";
      };
      homelab.operations.enable = true;
    }).config;
  insecureBind =
    (evaluate {
      services.actual = {
        enable = true;
        settings.hostname = "0.0.0.0";
      };
    }).config;
  insecureAuth =
    (evaluate {
      services.actual = {
        enable = true;
        settings.allowedLoginMethods = [
          "password"
          "header"
        ];
      };
    }).config;
  incompleteRecovery =
    (evaluate {
      services.actual = {
        enable = true;
        settings.userFiles = "/srv/untracked-budgets";
      };
    }).config;
  rejected = cfg: lib.any (assertion: !assertion.assertion) cfg.assertions;
in
{
  nativeService =
    configured.services.actual.enable && configured.services.actual.package.pname == "actual-server";
  loopbackOnly =
    configured.services.actual.settings.hostname == "127.0.0.1"
    && !configured.services.actual.openFirewall
    && !(builtins.elem configured.services.actual.settings.port configured.networking.firewall.allowedTCPPorts);
  passwordOnly =
    configured.services.actual.settings.loginMethod == "password"
    && configured.services.actual.settings.allowedLoginMethods == [ "password" ]
    && configured.services.actual.settings.trustedProxies == [ "127.0.0.1/32" ]
    && configured.services.actual.settings.trustedAuthProxies == [ ];
  sandbox =
    configured.systemd.services.actual.serviceConfig.DynamicUser
    && configured.systemd.services.actual.serviceConfig.NoNewPrivileges
    && configured.systemd.services.actual.serviceConfig.ProtectSystem == "strict"
    && configured.systemd.services.actual.serviceConfig.UMask == "0077"
    && !(configured.systemd.services.actual.serviceConfig ? CPUAccounting)
    && configured.systemd.services.actual.serviceConfig.MemoryAccounting
    && configured.systemd.services.actual.serviceConfig.IOAccounting;
  recoveryInventory =
    configured.homelab.operations.state.actual.paths == [ configured.services.actual.settings.dataDir ]
    && configured.homelab.operations.state.actual.units == [ "actual.service" ];
  customProtectedDataDir =
    !rejected encryptedDataDir
    && encryptedDataDir.services.actual.settings.serverFiles == "/srv/actual/server/server-files"
    && encryptedDataDir.services.actual.settings.userFiles == "/srv/actual/server/user-files"
    && encryptedDataDir.homelab.operations.state.actual.paths == [ "/srv/actual/server" ];
  health = configured.homelab.operations.endpoints.actual.healthUrl == "http://127.0.0.1:5006/health";
  rejectsExternalBind = rejected insecureBind;
  rejectsHeaderLogin = rejected insecureAuth;
  rejectsUntrackedBudgetFiles = rejected incompleteRecovery;
}
