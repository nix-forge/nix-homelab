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
  invalidTypedResource =
    (evaluate {
      homelab.integration = {
        enable = true;
        services.radarr = {
          url = "http://127.0.0.1:7878";
          apiKeyFile = "/run/test-key";
          resources = [
            {
              endpoint = "rootfolder";
              match = { };
              values = { };
            }
          ];
        };
      };
    }).config;
  rawResourceEscapeHatch =
    builtins.tryEval
      (evaluate {
        homelab.integration = {
          enable = true;
          services.radarr = {
            url = "http://127.0.0.1:7878";
            apiKeyFile = "/run/test-key";
            extraResources = [
              {
                endpoint = "indexer";
                match.name = "Future provider";
                values = {
                  implementation = "FutureProvider";
                  futureProviderField = true;
                };
              }
            ];
          };
        };
      }).config.system.build.toplevel.drvPath;
  invalidTypedSettings =
    (evaluate {
      homelab.integration = {
        enable = true;
        services.jellyfin = {
          url = "http://127.0.0.1:8096";
          apiKeyFile = "/run/test-key";
          settings.libraries.Movies = {
            collectionType = "movies";
            paths = "/srv/media/library/movies";
          };
        };
      };
    }).config;
  rawSettingsEscapeHatch =
    builtins.tryEval
      (evaluate {
        homelab.integration = {
          enable = true;
          services.jellyfin = {
            url = "http://127.0.0.1:8096";
            apiKeyFile = "/run/test-key";
            extraSettings.FutureUpstreamOption = true;
          };
        };
      }).config.system.build.toplevel.drvPath;
  typedProwlarrProxy =
    builtins.tryEval
      (evaluate {
        homelab.integration = {
          enable = true;
          services.prowlarr = {
            url = "http://127.0.0.1:9696";
            apiKeyFile = "/run/test-key";
            resources = [
              {
                endpoint = "indexerproxy";
                match.name = "local proxy";
                values.implementation = "Http";
              }
            ];
          };
        };
      }).config.system.build.toplevel.drvPath;
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
    typedResourceRequiresStableMatch = lib.any (
      assertion: !assertion.assertion && lib.hasInfix "stable name, path, or label" assertion.message
    ) invalidTypedResource.assertions;
    rawResourceEscapeHatchAvailable = rawResourceEscapeHatch.success;
    adapterSettingsAreTyped = lib.any (
      assertion: !assertion.assertion && lib.hasInfix "typed settings contract" assertion.message
    ) invalidTypedSettings.assertions;
    rawSettingsEscapeHatchAvailable = rawSettingsEscapeHatch.success;
    typedProwlarrProxyAvailable = typedProwlarrProxy.success;
  };
in
assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts))
  "Failed integration contracts: ${
    lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: value: !value) contracts))
  }";
pkgs.writeText "integration-contracts.json" (
  builtins.toJSON {
    inherit contracts;
    evaluatedSystem = builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath;
  }
)
