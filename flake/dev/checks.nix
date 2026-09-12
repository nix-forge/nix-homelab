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
        in
        pkgs.writeText "configuration-${name}.json" (
          builtins.toJSON {
            evaluatedSystem = builtins.unsafeDiscardStringContext c.system.build.toplevel.drvPath;
            inherit (c.networking.firewall) allowedTCPPorts allowedUDPPorts;
          }
        );
      empty = (evaluate { }).config;
      media =
        (evaluate {
          homelab.profiles.media.enable = true;
          homelab.apps.qbittorrent.vpn.enable = false;
        }).config;
      invalid = (evaluate { homelab.apps.qbittorrent.enable = true; }).config;
      contracts = {
        defaultServicesDisabled = lib.all (name: !empty.services.${name}.enable) names;
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
          configuration-default = configCheck "default" { };
          configuration-vpn = configCheck "vpn" {
            imports = [ ../../examples/media-server.nix ];
            homelab.indexerProxy.enable = true;
          };
          configuration-media = configCheck "media" {
            homelab.profiles.media.enable = true;
            homelab.profiles.desktop.enable = true;
            homelab.apps.qbittorrent.vpn.enable = false;
          };
          configuration-extras = configCheck "extras" (import ../../examples/extras.nix);
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
          media-runtime = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/media-runtime.nix { inherit homelabModule; }
          );
          storage-missing = testPkgs.testers.runNixOSTest (
            import ../../tests/nixos/storage-missing.nix { inherit homelabModule; }
          );
        };
    };
}
