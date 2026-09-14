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
      nzbget = (evaluate { homelab.apps.nzbget.enable = true; }).config;
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
            homelab.apps = lib.recursiveUpdate { qbittorrent.vpn.enable = false; } { ${name}.enable = true; };
          }
        )
        // {
          configuration-operations =
            let
              contracts =
                (import ../../tests/eval/operations.nix { inherit evaluate lib; })
                // (import ../../tests/eval/operations-optional.nix { inherit evaluate lib; });
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "operations-contracts.json" (builtins.toJSON contracts);
          source-secrets =
            pkgs.runCommand "homelab-source-secrets" { nativeBuildInputs = [ pkgs.gitleaks ]; }
              ''
                gitleaks dir --config ${../../.gitleaks.toml} --redact --no-banner ${self}
                touch $out
              '';
          native-application-services =
            pkgs.runCommand "homelab-native-application-services" { nativeBuildInputs = [ pkgs.ripgrep ]; }
              ''
                if rg --line-number \
                  '(oci-containers|docker-compose|docker[[:space:]]+(compose|run)|podman[[:space:]]+(compose|run)|\bimage[[:space:]]*=[[:space:]]*")' \
                  ${runtimeConfiguration}; then
                  echo 'Homelab modules and examples must use native packages and NixOS services.' >&2
                  exit 1
                fi
                touch "$out"
              '';
          operations-behavior =
            pkgs.runCommand "operations-behavior" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                mkdir -p project/scripts project/tests
                cp -r ${../../scripts/operations} project/scripts/operations
                cp -r ${../../tests/operations} project/tests/operations
                chmod -R u+w project
                python3 -B -m unittest discover -s project/tests/operations -v
                touch $out
              '';
          workflow-behavior =
            pkgs.runCommand "workflow-behavior"
              { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ]; }
              ''
                mkdir -p project/.github/workflows project/tests/workflows
                cp ${../../.github/workflows/ci.yml} project/.github/workflows/ci.yml
                cp ${../../.github/workflows/pages.yml} project/.github/workflows/pages.yml
                cp ${../../tests/workflows/test_ci.py} project/tests/workflows/test_ci.py
                chmod -R u+w project
                cd project
                python3 -B -m unittest discover -s tests/workflows -v
                touch $out
              '';
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
            pkgs.runCommand "downloader-credentials" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                mkdir -p project/scripts project/tests
                cp -r ${../../scripts/downloaders} project/scripts/downloaders
                cp -r ${../../scripts/integration} project/scripts/integration
                cp -r ${../../tests/downloaders} project/tests/downloaders
                chmod -R u+w project
                python3 -B -m unittest discover -s project/tests/downloaders -v
                touch $out
              '';
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
              apps =
                lib.genAttrs names (_: {
                  enable = true;
                })
                // {
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
            homelab.apps.nzbget.enable = true;
          };
          configuration-audio = configCheck "audio" (import ../../examples/audio.nix);
          configuration-integration-ports = import ../../tests/eval/integration-ports.nix {
            inherit evaluate lib pkgs;
          };
          configuration-integration = import ../../tests/eval/integration.nix { inherit evaluate lib pkgs; };
          configuration-qbittorrent-resources =
            let
              contracts = import ../../tests/eval/qbittorrent.nix { inherit evaluate lib; };
            in
            assert lib.all (value: value) (lib.attrValues contracts);
            pkgs.writeText "qbittorrent-resource-contracts.json" (builtins.toJSON contracts);
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
          integration-behavior =
            pkgs.runCommand "integration-behavior"
              { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ]; }
              ''
                mkdir -p project/scripts project/tests
                cp -r ${../../scripts/integration} project/scripts/integration
                cp -r ${../../tests/integration} project/tests/integration
                chmod -R u+w project
                python3 -m unittest discover -s project/tests/integration -v
                touch $out
              '';
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
          configuration-vpn-policy = import ../../tests/eval/vpn-policy.nix { inherit evaluate lib pkgs; };
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
          autobrr = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/autobrr.nix { inherit homelabModule; }
          );
          optional-media = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/optional-media.nix { inherit homelabModule; }
          );
          maintainerr = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/maintainerr.nix { inherit homelabModule; }
          );
          audiomuse-ai = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/audiomuse-ai.nix { inherit homelabModule; }
          );
          karakeep = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/karakeep.nix { inherit homelabModule; }
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
