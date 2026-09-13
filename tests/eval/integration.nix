{
  evaluate,
  pkgs,
  lib,
}:
let
  cfg =
    (evaluate {
      homelab.apps.radarr.enable = true;
      homelab.integration = {
        enable = true;
        services.radarr = {
          url = "http://127.0.0.1:7878";
          apiKeyFile = "/run/test-key";
          installApiKey = true;
          resources = [
            {
              endpoint = "rootfolder";
              match.path = "/srv/media/library/movies";
              values = { };
            }
          ];
        };
      };
    }).config;
  service = cfg.systemd.services.homelab-integrate-radarr;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate {
        homelab.integration = {
          enable = true;
          services.radarr = {
            url = "http://127.0.0.1:7878";
            apiKeyFile = "/run/test-key";
          }
          // extra;
        };
      }).config.assertions;
  invalidStorage =
    storage:
    lib.any (a: !a.assertion)
      (evaluate {
        homelab.storage = {
          enable = true;
        }
        // storage;
      }).config.assertions;
  contracts = {
    libraryOutsideRootRejected = invalidStorage { libraryDir = "/srv/unrelated"; };
    overlappingMediaPathsRejected = invalidStorage { libraryDir = "/srv/media/downloads/library"; };
    noncanonicalMediaPathsRejected = invalidStorage { downloadsDir = "/srv/media/./downloads"; };
    managerSingleWritableMediaMount =
      builtins.elem cfg.homelab.storage.rootDir cfg.systemd.services.radarr.serviceConfig.ReadWritePaths
      && !(builtins.elem cfg.homelab.storage.downloadsDir cfg.systemd.services.radarr.serviceConfig.ReadWritePaths)
      && !(builtins.elem cfg.homelab.storage.libraryDir cfg.systemd.services.radarr.serviceConfig.ReadWritePaths);
    literalPasswordRejected = rejected { settings.login.password = "public-invalid-literal"; };
    storeSecretRejected = rejected { apiKeyFile = "/nix/store/public-invalid-key"; };
    credentialDirectiveInjectionRejected = rejected { apiKeyFile = "/run/key:unexpected"; };
    privateCredentials = lib.length service.serviceConfig.LoadCredential == 1;
    noPrivileges = service.serviceConfig.NoNewPrivileges;
    privateState = service.serviceConfig.StateDirectoryMode == "0700";
    boundedRuntime = service.serviceConfig.TimeoutStartSec == "5min";
    nativeKey = builtins.elem "/run/homelab-key-radarr/environment" cfg.services.radarr.environmentFiles;
    timer = cfg.systemd.timers.homelab-integrate-radarr.timerConfig.OnUnitInactiveSec == "15min";
  };
in
assert lib.all (value: value) (lib.attrValues contracts);
pkgs.writeText "integration-contracts.json" (
  builtins.toJSON {
    inherit contracts;
    evaluatedSystem = builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath;
  }
)
