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
        config.allowUnfreePredicate = pkg: lib.getName pkg == "unrar";
      };
      evaluate =
        extra:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            homelabModule
            {
              boot.isContainer = true;
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
        sabnzbdDeclarative =
          (evaluate {
            homelab.apps.sabnzbd.enable = true;
            system.stateVersion = lib.mkForce "25.11";
          }).config.services.sabnzbd.configFile == null;
        sharedGroup = builtins.elem media.homelab.storage.group media.systemd.services.sonarr.serviceConfig.SupplementaryGroups;
        privateUmask = media.systemd.services.sonarr.serviceConfig.UMask == "0007";
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
            homelab.indexerProxy.enable = true;
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
          storage-missing = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/storage-missing.nix { inherit homelabModule; }
          );
        };
    };
}
