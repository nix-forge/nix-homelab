{ config, lib, ... }:
let
  cfg = config.services.actual;
in
{
  config = lib.mkIf cfg.enable {
    # The native NixOS module owns the package, state directory, service user,
    # and most of the systemd sandbox. Narrow its network and login defaults.
    services.actual = {
      openFirewall = lib.mkDefault false;
      settings = {
        hostname = lib.mkDefault "127.0.0.1";
        port = lib.mkDefault 5006;
        loginMethod = lib.mkDefault "password";
        allowedLoginMethods = lib.mkDefault [ "password" ];
        trustedProxies = lib.mkDefault [ "127.0.0.1/32" ];
        trustedAuthProxies = lib.mkDefault [ ];
      };
    };

    assertions = [
      {
        assertion = cfg.settings.hostname == "127.0.0.1" && !cfg.openFirewall;
        message = "Actual must listen only on loopback without a direct firewall opening.";
      }
      {
        assertion =
          builtins.elem cfg.settings.loginMethod [
            "password"
            "openid"
          ]
          && cfg.settings.allowedLoginMethods == [ cfg.settings.loginMethod ]
          && (cfg.settings.loginMethod != "openid" || cfg.settings.enforceOpenId)
          && cfg.settings.trustedProxies == [ "127.0.0.1/32" ]
          && cfg.settings.trustedAuthProxies == [ ];
        message = "Actual requires one enforced password or OpenID login method and an exact loopback proxy trust policy.";
      }
      {
        assertion =
          cfg.settings.serverFiles == "${cfg.settings.dataDir}/server-files"
          && cfg.settings.userFiles == "${cfg.settings.dataDir}/user-files";
        message = "Actual server and budget files must stay beneath the configured data directory for complete recovery.";
      }
    ];

    systemd.services.actual.serviceConfig = {
      NoNewPrivileges = lib.mkDefault true;
      RestrictSUIDSGID = lib.mkDefault true;
      MemoryAccounting = lib.mkDefault true;
      IOAccounting = lib.mkDefault true;
      # Budget editing is interactive. Do not put it in the low-priority media
      # download slice or impose an arbitrary memory cap on large imports.
    };

    homelab.operations = lib.mkIf config.homelab.operations.enable {
      state.actual = {
        paths = [ cfg.settings.dataDir ];
        units = [ "actual.service" ];
      };
      endpoints.actual = {
        url = "http://127.0.0.1:${toString cfg.settings.port}";
        healthUrl = "http://127.0.0.1:${toString cfg.settings.port}/health";
        description = "Actual Budget backend liveness; this does not test login or browser sync";
      };
    };
  };
}
