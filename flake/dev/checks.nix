{ inputs, self, ... }: {
  perSystem =
    {
      pkgs,
      system,
      lib,
      ...
    }:
    let
      homelabModule = self.nixosModules.default;
      testPkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.nixpkgs-personal.overlays.default ];
        config.allowUnfreePredicate = pkg: lib.getName pkg == "unrar";
      };
      runtimeConfiguration = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../examples
          ../../hosts
          ../../modules
        ];
      };
      evaluate =
        extra:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            homelabModule
            {
              boot.isContainer = true;
              nixpkgs.overlays = [ inputs.nixpkgs-personal.overlays.default ];
              system.stateVersion = "26.05";
              nixpkgs.config.allowUnfreePredicate =
                pkg:
                builtins.elem (lib.getName pkg) [
                  "plexmediaserver"
                  "unrar"
                ];
            }
            extra
          ];
        };
      workflowSource = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../.github/workflows/ci.yml
          ../../.github/workflows/pages.yml
          ../../.github/dependabot.yml
          ../../tests/workflows/test_ci.py
          (lib.fileset.fileFilter (file: file.name == "flake.lock") ../..)
        ];
      };
      names = [
        "sonarr"
        "radarr"
        "lidarr"
        "bazarr"
        "prowlarr"
        "seerr"
        "qbittorrent"
        "sabnzbd"
        "nzbget"
        "jellyfin"
        "plex"
        "navidrome"
        "audiobookshelf"
      ];
      credentialFixtures = {
        nzbget.credentialsFile = lib.mkDefault "/run/secrets/nzbget-credentials.conf";
      };
      enabledAppFixture = name: { enable = true; } // (credentialFixtures.${name} or { });
      configCheck =
        name: extra:
        let
          c = (evaluate extra).config;
          endpointUrls = map (endpoint: lib.removeSuffix "/" endpoint.url) (
            lib.attrValues c.homelab.operations.endpoints
          );
        in
        assert lib.assertMsg (
          name != "complete" || builtins.length endpointUrls == builtins.length (lib.unique endpointUrls)
        ) "The complete example contains overlapping advertised HTTP endpoints.";
        pkgs.writeText "configuration-${name}.json" (
          builtins.toJSON {
            evaluatedSystem = builtins.unsafeDiscardStringContext c.system.build.toplevel.drvPath;
            inherit (c.networking.firewall) allowedTCPPorts allowedUDPPorts;
          }
        );
      empty = (evaluate { }).config;
      optionalNames = builtins.attrNames empty.homelab.optional.apps;
      media =
        (evaluate {
          homelab.profiles.media.enable = true;
          homelab.apps.qbittorrent.vpn.enable = false;
        }).config;
      invalid = (evaluate { homelab.apps.qbittorrent.enable = true; }).config;
      sabnzbd =
        (evaluate {
          homelab.apps.sabnzbd.enable = true;
          system.stateVersion = lib.mkForce "25.11";
        }).config;
      nzbget = (evaluate { homelab.apps.nzbget = enabledAppFixture "nzbget"; }).config;
      nzbgetWithoutCredentials = (evaluate { homelab.apps.nzbget.enable = true; }).config;
      contracts = {
        defaultServicesDisabled = lib.all (name: !empty.services.${name}.enable) names;
        defaultOptionalServicesDisabled =
          lib.all (name: !empty.services.${name}.enable) (lib.remove "maintainerr" optionalNames)
          && empty.virtualisation.oci-containers.containers == { }
          && !empty.services.recyclarr.enable;
        privateFirewall =
          media.networking.firewall.allowedTCPPorts == [ ]
          && media.networking.firewall.allowedUDPPorts == [ ];
        hostProwlarr = !media.systemd.services.prowlarr.vpn.enable;
        secureQbitDefault = empty.homelab.apps.qbittorrent.vpn.enable;
        missingVpnRejected = lib.any (a: !a.assertion) invalid.assertions;
        missingNZBGetCredentialsRejected = lib.any (
          a: !a.assertion && lib.hasInfix "NZBGet requires a credentialsFile" a.message
        ) nzbgetWithoutCredentials.assertions;
        downloaderAuth = media.services.qbittorrent.serverConfig.Preferences.WebUI.LocalHostAuth;
        downloaderResourcePolicy =
          media.services.qbittorrent.serverConfig.BitTorrent.Session == {
            DefaultSavePath = "${media.homelab.storage.downloadsDir}/torrents";
            IgnoreSlowTorrentsForQueueing = false;
            LSDEnabled = false;
            MaxActiveDownloads = 3;
            MaxActiveTorrents = 8;
            MaxActiveUploads = 5;
            MaxConnections = 200;
            MaxConnectionsPerTorrent = 50;
            MaxUploads = 20;
            MaxUploadsPerTorrent = 8;
            QueueingSystemEnabled = true;
            TempPath = "${media.homelab.storage.downloadsDir}/incomplete";
            TempPathEnabled = true;
          };
        sabnzbdDeclarative =
          (evaluate {
            homelab.apps.sabnzbd.enable = true;
            system.stateVersion = lib.mkForce "25.11";
          }).config.services.sabnzbd.configFile == null;
        sabnzbdResourcePolicy =
          lib.filterAttrs (
            name: _:
            builtins.elem name [
              "cache_limit"
              "direct_unpack"
              "direct_unpack_threads"
              "enable_https_verification"
              "inet_exposure"
              "max_art_tries"
              "pause_on_post_processing"
            ]
          ) sabnzbd.services.sabnzbd.settings.misc == {
            cache_limit = "256M";
            direct_unpack = false;
            direct_unpack_threads = 1;
            enable_https_verification = true;
            inet_exposure = 0;
            max_art_tries = 3;
            pause_on_post_processing = true;
          };
        nzbgetResourcePolicy =
          lib.filterAttrs (
            name: _:
            builtins.elem name [
              "ArticleCache"
              "AuthorizedIP"
              "DirectUnpack"
              "DiskSpace"
              "HealthCheck"
              "ParBuffer"
              "ParPauseQueue"
              "ParThreads"
              "ParTimeLimit"
              "PostStrategy"
              "ScriptPauseQueue"
              "UnpackCleanupDisk"
              "UnpackPauseQueue"
              "UseTempUnpackDir"
              "WriteBuffer"
            ]
          ) nzbget.services.nzbget.settings == {
            ArticleCache = 256;
            AuthorizedIP = "";
            DirectUnpack = false;
            DiskSpace = 20480;
            HealthCheck = "pause";
            ParBuffer = 256;
            ParPauseQueue = true;
            ParThreads = 2;
            ParTimeLimit = 30;
            PostStrategy = "sequential";
            ScriptPauseQueue = true;
            UnpackCleanupDisk = false;
            UnpackPauseQueue = true;
            UseTempUnpackDir = true;
            WriteBuffer = 1024;
          };
        sharedGroup = builtins.elem media.homelab.storage.group media.systemd.services.sonarr.serviceConfig.SupplementaryGroups;
        privateUmask = media.systemd.services.sonarr.serviceConfig.UMask == "0007";
        bazarrLibraryWriteOnly =
          builtins.elem media.homelab.storage.libraryDir media.systemd.services.bazarr.serviceConfig.ReadWritePaths
          && !(builtins.elem media.homelab.storage.rootDir media.systemd.services.bazarr.serviceConfig.ReadWritePaths)
          && builtins.elem media.homelab.storage.downloadsDir media.systemd.services.bazarr.serviceConfig.BindReadOnlyPaths;
        jellyfinTranscodingPolicy =
          media.services.jellyfin.transcoding.maxConcurrentStreams == 2
          && media.services.jellyfin.transcoding.threadCount == 2
          && media.services.jellyfin.transcoding.throttleTranscoding
          && media.services.jellyfin.transcoding.deleteSegments;
      };
    in
    {
      checks =
        lib.genAttrs (map (name: "configuration-${name}") names) (
          checkName:
          let
            name = lib.removePrefix "configuration-" checkName;
          in
          configCheck name {
            homelab.apps = lib.recursiveUpdate { qbittorrent.vpn.enable = false; } {
              ${name} = enabledAppFixture name;
            };
          }
        )
        // {
          sql-formatting =
            pkgs.runCommand "sql-formatting"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.treefmt
                  pkgs.sql-formatter
                ];
                SQL_FORMATTER_SCRIPT = ./scripts/format-sql.sh;
              }
              ''
                python3 ${../../tests/tooling/test_sql_format.py}
                touch "$out"
              '';
          storage-preparation-behavior =
            let
              source = lib.fileset.toSource {
                root = ../..;
                fileset = lib.fileset.unions [
                  ../../pyproject.toml
                  ../../scripts/storage/prepare.py
                  ../../modules/optional/scripts/prepare-application-storage.sh
                  ../../tests/storage
                  ../../scripts/indexers/install_definitions.py
                  ../../tests/indexers
                ];
              };
            in
            pkgs.runCommand "storage-preparation-behavior"
              {
                nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ];
                BASH_PROGRAM = lib.getExe pkgs.bash;
              }
              ((import ../../lib/render-text.nix) ./scripts/storage-preparation-behavior.sh { inherit source; });
          configuration-portability =
            let
              contracts = import ../../tests/eval/portability.nix {
                inherit evaluate lib;
                pkgs = testPkgs;
              };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts)) (
              "Portability contracts failed: " + builtins.toJSON contracts
            );
            pkgs.writeText "portability-contracts.json" (builtins.toJSON contracts);
          php-read-failures =
            let
              source = lib.fileset.toSource {
                root = ../..;
                fileset = lib.fileset.unions [
                  ../../pyproject.toml
                  ../../tests/optional/test_freshrss_reads.py
                  ../../scripts/optional/bootstrap-freshrss.php
                  ../../scripts/optional/provision-freshrss-user.php
                ];
              };
            in
            pkgs.runCommand "homelab-php-read-failures" {
              sourcePath = source;
              PHP_TEST_EXECUTABLE = lib.getExe pkgs.php;
              nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ];
            } (builtins.readFile ./scripts/php-read-failures.sh);
          php-semantic-quality =
            let
              source = lib.fileset.toSource {
                root = ../..;
                fileset = lib.fileset.unions [
                  ../../phpstan.neon
                  (lib.fileset.fileFilter (file: file.hasExt "php") ../../scripts)
                  (lib.fileset.fileFilter (file: file.hasExt "php") ../../tests)
                ];
              };
            in
            pkgs.runCommand "homelab-php-semantic-quality" {
              sourcePath = source;
              nativeBuildInputs = [ (import ./php-tools.nix { inherit pkgs; }) ];
            } (builtins.readFile ./scripts/php-semantic-quality.sh);
          php-quality =
            let
              source = lib.fileset.toSource {
                root = ../..;
                fileset = lib.fileset.unions [
                  ../../.php-cs-fixer.dist.php
                  (lib.fileset.fileFilter (file: file.hasExt "php") ../../scripts)
                  (lib.fileset.fileFilter (file: file.hasExt "php") ../../tests)
                ];
              };
            in
            pkgs.runCommand "homelab-php-quality" {
              nativeBuildInputs = [
                pkgs.php
                pkgs.phpPackages.php-cs-fixer
                pkgs.findutils
              ];
            } ((import ../../lib/render-text.nix) ./scripts/php-quality.sh { inherit source; });
          iot-typescript = testPkgs.homelab-iot-scripts;
          configuration-operations =
            let
              contracts =
                (import ../../tests/eval/operations.nix { inherit evaluate lib; })
                // (import ../../tests/eval/operations-optional.nix { inherit evaluate lib; })
                // (import ../../tests/eval/dashboard.nix { inherit evaluate lib; });
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts)) (
              "Failed operations contracts: "
              + builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: value: !value) contracts))
            );
            pkgs.writeText "operations-contracts.json" (builtins.toJSON contracts);
          configuration-iot =
            let
              contracts = import ../../tests/eval/iot.nix { inherit evaluate lib pkgs; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts)) (
              "Failed IoT contracts: "
              + builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: value: !value) contracts))
            );
            pkgs.writeText "iot-contracts.json" (builtins.toJSON contracts);
          homebridge-ui-auth-compatibility = import ../../modules/iot/checks/homebridge-ui-auth.nix {
            pkgs = testPkgs;
          };
          iot-python-behavior =
            pkgs.runCommand "iot-python-behavior"
              { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/iot-python-behavior.sh {
                  modules_iot_scripts = ../../modules/iot/scripts;
                  tests_iot = ../../tests/iot;
                }
              );
          configuration-actual =
            let
              contracts = import ../../tests/eval/actual.nix { inherit evaluate lib; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts)) (
              "Failed Actual contracts: "
              + builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: value: !value) contracts))
            );
            pkgs.writeText "actual-contracts.json" (builtins.toJSON contracts);
          configuration-bookorbit =
            let
              contracts = import ../../tests/eval/bookorbit.nix { inherit evaluate lib; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts)) (
              "Failed BookOrbit contracts: "
              + builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: value: !value) contracts))
            );
            pkgs.writeText "bookorbit-contracts.json" (builtins.toJSON contracts);
          bookorbit-bootstrap-behavior =
            pkgs.runCommand "bookorbit-bootstrap-behavior" { nativeBuildInputs = [ pkgs.python3 ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/bookorbit-bootstrap-behavior.sh {
                  scripts_services_bootstrap_bookorbit_py = ../../scripts/services/bootstrap_bookorbit.py;
                  tests_services_test_bookorbit_bootstrap_py = ../../tests/services/test_bookorbit_bootstrap.py;
                }
              );
          wardrowbe-codex-behavior =
            pkgs.runCommand "wardrowbe-codex-behavior"
              {
                CODEX_TEST_EXECUTABLE = lib.getExe pkgs.codex;
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (
                    ps: with ps; [
                      fastapi
                      uvicorn
                      pillow
                      httpx
                      testPkgs.notification-process
                    ]
                  ))
                ];
              }
              (
                (import ../../lib/render-text.nix) ./scripts/wardrowbe-codex-behavior.sh {
                  modules_services_scripts_wardrowbe_codex_py = ../../modules/services/scripts/wardrowbe_codex.py;
                  tests_wardrowbe_test_codex_py = ../../tests/wardrowbe/test_codex.py;
                  wardrowbeFixtures = ../../tests/wardrowbe/fixtures;
                }
              );
          keycloak-bootstrap-behavior =
            pkgs.runCommand "keycloak-bootstrap-behavior" { nativeBuildInputs = [ pkgs.python3 ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/keycloak-bootstrap-behavior.sh {
                  modules_services_scripts_keycloak_admin_py = ../../modules/services/scripts/keycloak_admin.py;
                  tests_keycloak_test_admin_py = ../../tests/keycloak/test_admin.py;
                }
              );
          configuration-keycloak =
            let
              contracts = import ../../tests/eval/keycloak.nix { inherit evaluate lib; };
              c =
                (evaluate {
                  services.keycloak = {
                    enable = true;
                    settings.hostname = "https://identity.example.org";
                    bootstrapRealm = {
                      enable = true;
                      file = "/run/keys/realm";
                      environmentFile = "/run/keys/admin";
                    };
                  };
                }).config;
            in
            assert lib.assertMsg (lib.all (value: value) (
              lib.attrValues contracts
            )) "Keycloak bootstrap contracts failed";
            pkgs.runCommand "keycloak-contracts.json" { } (
              (import ../../lib/render-text.nix) ./scripts/keycloak-contracts-json.sh {
                c_systemd_services_keycloak_postStart = c.systemd.services.keycloak.postStart;
                pkgs_writeText_keycloak_contract_results_json_builtins_toJSO = pkgs.writeText "keycloak-contract-results.json" (
                  builtins.toJSON contracts
                );
              }
            );
          configuration-wardrowbe =
            let
              contracts = import ../../tests/eval/wardrowbe.nix { inherit evaluate lib; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts)) (
              "Failed Wardrowbe contracts: "
              + builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: value: !value) contracts))
            );
            pkgs.writeText "wardrowbe-contracts.json" (builtins.toJSON contracts);
          source-secrets =
            pkgs.runCommand "homelab-source-secrets" { nativeBuildInputs = [ pkgs.gitleaks ]; }
              ''
                gitleaks dir --config ${../../.gitleaks.toml} --redact --no-banner ${self}
                touch $out
              '';
          native-application-services =
            pkgs.runCommand "homelab-native-application-services" { nativeBuildInputs = [ pkgs.ripgrep ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/homelab-native-application-services.sh {
                  inherit runtimeConfiguration;
                }
              );
          operations-behavior =
            pkgs.runCommand "operations-behavior"
              { nativeBuildInputs = [ (pkgs.python3.withPackages (_: [ testPkgs.notification-process ])) ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/operations-behavior.sh {
                  scripts_operations = ../../scripts/operations;
                  tests_operations = ../../tests/operations;
                }
              );
          workflow-behavior = pkgs.runCommand "workflow-behavior" {
            nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
          } ((import ../../lib/render-text.nix) ./scripts/workflow-behavior.sh { inherit workflowSource; });
          ci-runtime-selection =
            let
              contracts = import ../../tests/eval/ci-runtime-selection.nix { inherit lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "homelab-ci-runtime-selection.json" (builtins.toJSON contracts);
          configuration-optional =
            let
              contracts = import ../../tests/eval/optional-services.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            configCheck "optional" {
              imports = [ ../../examples/optional-services.nix ];
              homelab.optional.apps = lib.genAttrs optionalNames (_: {
                enable = true;
              });
            };
          configuration-autobrr = configCheck "autobrr-integration" {
            imports = [
              ../../examples/optional-services.nix
              ../../examples/autobrr.nix
            ];
          };
          configuration-integrated-media = configCheck "integrated-media" {
            imports = [ ../../examples/integrated-media.nix ];
            homelab.apps.qbittorrent.vpn.enable = false;
          };
          downloader-credentials =
            pkgs.runCommand "downloader-credentials"
              { nativeBuildInputs = [ (pkgs.python3.withPackages (_: [ testPkgs.notification-process ])) ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/downloader-credentials.sh {
                  scripts_downloaders = ../../scripts/downloaders;
                  modules_optional_quality_custom_formats_subtitled_release_js = ../../modules/optional/quality/custom-formats/subtitled-release.json;
                  scripts_integration = ../../scripts/integration;
                  tests_downloaders = ../../tests/downloaders;
                  modules_downloaders_scripts_start_qbittorrent_sh = ../../modules/downloaders/scripts/start-qbittorrent.sh;
                }
              );
          configuration-complete = configCheck "complete" {
            imports = [
              ../../examples/integrated-media.nix
              ../../examples/audio.nix
              ../../examples/usenet.nix
              ../../examples/optional-services.nix
              ../../examples/autobrr.nix
              ../../examples/operations.nix
            ];
            homelab = {
              apps = lib.genAttrs names enabledAppFixture // {
                qbittorrent = {
                  enable = true;
                  vpn.enable = false;
                };
              };
              optional.apps = lib.genAttrs optionalNames (_: {
                enable = true;
              });
            };
          };
          configuration-operations-example = configCheck "operations-example" {
            imports = [ ../../examples/operations.nix ];
          };
          configuration-usenet = configCheck "usenet" {
            imports = [ ../../examples/usenet.nix ];
            homelab.apps.sabnzbd.enable = true;
            homelab.apps.nzbget = enabledAppFixture "nzbget";
          };
          configuration-audio = configCheck "audio" (import ../../examples/audio.nix);
          configuration-integration-ports = import ../../tests/eval/integration-ports.nix {
            inherit evaluate lib pkgs;
          };
          configuration-integration = import ../../tests/eval/integration.nix { inherit evaluate lib pkgs; };
          configuration-promoted-services =
            let
              contracts = import ../../tests/eval/promoted-services.nix { inherit evaluate lib pkgs; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts))
              "Failed promoted-service contracts: ${
                lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: value: !value) contracts))
              }";
            pkgs.writeText "promoted-service-contracts.json" (builtins.toJSON contracts);
          configuration-qbittorrent-resources =
            let
              contracts = import ../../tests/eval/qbittorrent.nix { inherit evaluate lib; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts))
              "Failed qBittorrent contracts: ${
                lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: value: !value) contracts))
              }";
            pkgs.writeText "qbittorrent-resource-contracts.json" (builtins.toJSON contracts);
          configuration-slskd =
            let
              contracts = import ../../tests/eval/slskd.nix { inherit evaluate lib; };
            in
            assert lib.assertMsg (lib.all (value: value) (lib.attrValues contracts))
              "Failed slskd contracts: ${
                lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: value: !value) contracts))
              }";
            pkgs.writeText "slskd-contracts.json" (builtins.toJSON contracts);
          slskd-credential-preflight =
            let
              unit =
                (evaluate {
                  imports = [ ../../examples/media-server.nix ];
                  homelab.apps.slskd = {
                    enable = true;
                    credentialsFile = "/run/secrets/slskd.env";
                  };
                }).config.systemd.services.slskd;
              preflight = builtins.head unit.serviceConfig.ExecStartPre;
              fixture = "SLSKD_SLSK_USERNAME=fixture SLSKD_SLSK_PASSWORD=fixture-password-long SLSKD_USERNAME=operator SLSKD_PASSWORD=fixture-web-password-long SLSKD_API_KEY=fixture-api-key-long SLSKD_JWT_KEY=fixture-jwt-signing-key-longer-than-thirty-two-characters";
            in
            pkgs.runCommand "slskd-credential-preflight" { } (
              (import ../../lib/render-text.nix) ./scripts/slskd-credential-preflight.sh {
                pkgs_coreutils = pkgs.coreutils;
                inherit preflight;
                inherit fixture;
              }
            );
          qbittorrent-packaged-reconciler =
            let
              service =
                (evaluate {
                  homelab.apps.qbittorrent = {
                    enable = true;
                    vpn.enable = false;
                    apiKeyFile = "/run/secrets/qbittorrent-api-key";
                    configuration.tags = [ "fixture" ];
                  };
                }).config.systemd.services.homelab-configure-qbittorrent;
              script = builtins.elemAt (lib.splitString " " service.serviceConfig.ExecStart) 1;
            in
            pkgs.runCommand "qbittorrent-packaged-reconciler" { nativeBuildInputs = [ pkgs.python3 ]; } (
              (import ../../lib/render-text.nix) ./scripts/qbittorrent-packaged-reconciler.sh { inherit script; }
            );
          configuration-servarr =
            let
              contracts = import ../../tests/eval/servarr.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "servarr-contracts.json" (builtins.toJSON contracts);
          configuration-prowlarr =
            let
              contracts = import ../../tests/eval/prowlarr.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "prowlarr-contracts.json" (builtins.toJSON contracts);
          configuration-jellyfin =
            let
              contracts = import ../../tests/eval/jellyfin.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "jellyfin-contracts.json" (builtins.toJSON contracts);
          configuration-seerr =
            let
              contracts = import ../../tests/eval/seerr.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "seerr-contracts.json" (builtins.toJSON contracts);
          configuration-readiness =
            let
              readinessContracts = import ../../tests/eval/readiness.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues readinessContracts);
            pkgs.writeText "readiness-contracts.json" (builtins.toJSON readinessContracts);
          media-helpers-behavior =
            pkgs.runCommand "media-helpers-behavior"
              {
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (ps: [
                    ps.pytest
                    ps.pillow
                  ]))
                ];
                PYTEST_DISABLE_PLUGIN_AUTOLOAD = "1";
              }
              (
                (import ../../lib/render-text.nix) ./scripts/media-helpers-behavior.sh {
                  pyproject_toml = ../../pyproject.toml;
                  scripts_media_configure_captions_py = ../../scripts/media/configure_captions.py;
                  scripts_media_configure_music_shuffle_py = ../../scripts/media/configure_music_shuffle.py;
                  tests_media_test_captions_py = ../../tests/media/test_captions.py;
                  tests_media_test_music_shuffle_py = ../../tests/media/test_music_shuffle.py;
                  scripts_media_lyrics_py = ../../scripts/media/lyrics.py;
                  tests_media_test_lyrics_py = ../../tests/media/test_lyrics.py;
                  scripts_media_artwork_py = ../../scripts/media/artwork.py;
                  scripts_media_configure_moonbase_py = ../../scripts/media/configure_moonbase.py;
                  tests_media_test_artwork_py = ../../tests/media/test_artwork.py;
                  tests_media_fixtures = ../../tests/media/fixtures;
                  tests_media_test_configure_moonbase_py = ../../tests/media/test_configure_moonbase.py;
                }
              );
          integration-behavior =
            pkgs.runCommand "integration-behavior"
              {
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (ps: [
                    ps.pyyaml
                    testPkgs.notification-process
                  ]))
                ];
              }
              (
                (import ../../lib/render-text.nix) ./scripts/integration-behavior.sh {
                  modules_optional_quality_custom_formats_subtitled_release_js = ../../modules/optional/quality/custom-formats/subtitled-release.json;
                  scripts_integration = ../../scripts/integration;
                  tests_integration = ../../tests/integration;
                  tests_fixtures_autobrr_runtime_py = ../../tests/fixtures/autobrr_runtime.py;
                }
              );
          jellyfin-plugin-behavior =
            pkgs.runCommand "jellyfin-plugin-behavior" { nativeBuildInputs = [ pkgs.python3 ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/jellyfin-plugin-behavior.sh {
                  scripts_media_install_jellyfin_plugins_py = ../../scripts/media/install_jellyfin_plugins.py;
                  scripts_media_maintainerr_policy_py = ../../scripts/media/maintainerr_policy.py;
                  scripts_media_jellyfin_ignore_py = ../../scripts/media/jellyfin_ignore.py;
                  tests_media_test_jellyfin_plugins_py = ../../tests/media/test_jellyfin_plugins.py;
                  tests_media_test_maintainerr_policy_py = ../../tests/media/test_maintainerr_policy.py;
                  tests_media_test_jellyfin_ignore_py = ../../tests/media/test_jellyfin_ignore.py;
                }
              );
          configuration-default = configCheck "default" { };
          configuration-vpn = configCheck "vpn" {
            imports = [ ../../examples/media-server.nix ];
            homelab.indexerProxy = {
              enable = true;
              username = "indexers";
              passwordFile = "/run/secrets/indexer-proxy-password";
            };
          };
          configuration-media = configCheck "media" {
            homelab = {
              profiles.media.enable = true;
              profiles.desktop.enable = true;
              apps.qbittorrent.vpn.enable = false;
            };
          };
          configuration-extras = configCheck "extras" (import ../../examples/extras.nix);
          configuration-vpn-policy = import ../../tests/eval/vpn-policy.nix {
            inherit
              evaluate
              lib
              pkgs
              credentialFixtures
              ;
          };
          configuration-contracts =
            assert lib.assertMsg (lib.all (x: x) (lib.attrValues contracts))
              "Failed homelab contracts: ${
                lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: v: !v) contracts))
              }";
            pkgs.writeText "homelab-contracts.json" (builtins.toJSON contracts);
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          storage-missing = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/storage-missing.nix { inherit homelabModule; }
          );
          vpn-namespace = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/vpn-namespace.nix { inherit pkgs homelabModule; }
          );
          media-workflow = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/media-workflow.nix { inherit homelabModule; }
          );
          sonarr-anime = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/sonarr-anime.nix { inherit homelabModule; }
          );
          cross-seed = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/cross-seed.nix { inherit homelabModule; }
          );
          pressure = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/pressure.nix { inherit homelabModule; }
          );
          quality = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/quality.nix { inherit homelabModule; }
          );
          books = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/books.nix { inherit homelabModule; }
          );
          bookorbit-native-recovery = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/bookorbit.nix { inherit homelabModule; }
          );
          autobrr = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/autobrr.nix { inherit homelabModule; }
          );
          optional-media = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/optional-media.nix { inherit homelabModule; }
          );
          pinchflat = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/pinchflat.nix { inherit homelabModule; }
          );
          maintainerr = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/maintainerr.nix { inherit homelabModule; }
          );
          actual = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/actual.nix { inherit homelabModule; }
          );
          audiomuse-ai = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/audiomuse-ai.nix { inherit homelabModule; }
          );
          karakeep = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/karakeep.nix { inherit homelabModule; }
          );
          miniflux-upgrade-behavior =
            pkgs.runCommand "miniflux-upgrade-behavior" { nativeBuildInputs = [ pkgs.python3 ]; }
              (
                (import ../../lib/render-text.nix) ./scripts/miniflux-upgrade-behavior.sh {
                  scripts_optional_bootstrap_miniflux_py = ../../scripts/optional/bootstrap_miniflux.py;
                  tests_optional_test_miniflux_upgrade_py = ../../tests/optional/test_miniflux_upgrade.py;
                }
              );
          miniflux = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/miniflux.nix { inherit homelabModule; }
          );
          freshrss = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/freshrss.nix { inherit homelabModule; }
          );
          reactflux = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/reactflux.nix { inherit homelabModule; }
          );
          private-archives = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/private-archives.nix { inherit homelabModule; }
          );
          arr-integration = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/arr-integration.nix { inherit homelabModule; }
          );
          access = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/access.nix { inherit homelabModule; }
          );
          arr-postgresql = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/arr-postgresql.nix { inherit homelabModule; }
          );
          usenet-credentials = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/usenet-credentials.nix { inherit homelabModule; }
          );
          audio-runtime = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/audio-runtime.nix { inherit homelabModule; }
          );
          operations = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/operations.nix { inherit homelabModule; }
          );
          media-runtime = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/media-runtime.nix { inherit homelabModule; }
          );
        };
    };
}
