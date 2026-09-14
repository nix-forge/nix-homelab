{ evaluate, lib }:
let
  missingQbittorrentCredentials =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.qbittorrent = {
          enable = true;
          vpn.enable = false;
        };
      };
    }).config;
  storeQbittorrentCredentials =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.qbittorrent = {
          enable = true;
          vpn.enable = false;
          credentialsFile = "/nix/store/public-qbittorrent-credentials";
        };
      };
    }).config;
  missingSonarrIntegration =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.sonarr.enable = true;
      };
    }).config;
  incompleteSonarrIntegration =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.sonarr.enable = true;
        integration = {
          enable = true;
          services.sonarr = {
            url = "http://127.0.0.1:8989";
            apiKeyFile = "/run/secrets/sonarr-api";
          };
        };
      };
    }).config;
  incompleteManagerIntegration = lib.genAttrs [ "radarr" "lidarr" "prowlarr" "bazarr" ] (
    name:
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.${name}.enable = true;
        integration = {
          enable = true;
          services.${name} = {
            url = "http://127.0.0.1:9999";
            apiKeyFile = "/run/secrets/${name}-api";
          };
        };
      };
    }).config
  );
  incompleteApplicationIntegration =
    lib.genAttrs [ "jellyfin" "seerr" "navidrome" "audiobookshelf" ]
      (
        name:
        (evaluate {
          homelab = {
            readiness.enable = true;
            apps.${name}.enable = true;
            integration = {
              enable = true;
              services.${name} = {
                url = "http://127.0.0.1:9999";
                settings.login = {
                  username = "admin";
                  password._secret = "/run/secrets/${name}-admin";
                };
              };
            };
          };
        }).config
      );
  passwordOnlyJellyfin =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.jellyfin.enable = true;
        integration = {
          enable = true;
          services.jellyfin = {
            url = "http://127.0.0.1:8096";
            mode = "managed";
            settings = {
              login = {
                username = "admin";
                password._secret = "/run/secrets/jellyfin-admin";
              };
              libraries.Movies = {
                collectionType = "movies";
                paths = [ "/srv/media/library/movies" ];
              };
              users.viewer.password._secret = "/run/secrets/jellyfin-viewer";
            };
          };
        };
      };
    }).config;
  missingOperations =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.plex.enable = true;
      };
    }).config;
  missingMediaMount =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.plex.enable = true;
        storage.requiredMounts = [ ];
      };
    }).config;
  missingDownloaderCredentials = lib.genAttrs [ "sabnzbd" "nzbget" ] (
    name:
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.${name}.enable = true;
      };
    }).config
  );
  missingAutobrrIntegration =
    (evaluate {
      homelab = {
        readiness.enable = true;
        optional.apps.autobrr.enable = true;
      };
    }).config;
  incompleteAutobrrIntegration =
    (evaluate {
      homelab = {
        readiness.enable = true;
        optional.apps.autobrr.enable = true;
        integration = {
          enable = true;
          services.autobrr = {
            url = "http://127.0.0.1:7474";
            apiKeyFile = "/run/secrets/autobrr-api";
          };
        };
      };
    }).config;
  unboundedAutobrrIntegration =
    (evaluate {
      homelab = {
        readiness.enable = true;
        optional.apps.autobrr.enable = true;
        integration = {
          enable = true;
          services.autobrr = {
            url = "http://127.0.0.1:7474";
            apiKeyFile = "/run/secrets/autobrr-api";
            settings = {
              downloadClients.fixture = { };
              filters.fixture = {
                values.enabled = true;
                indexers = [ "fixture" ];
                actions.fixture.paused = false;
              };
            };
          };
        };
      };
      services.autobrr.secretFile = "/run/secrets/autobrr-session";
    }).config;
  missingPlexAcknowledgement =
    (evaluate {
      homelab = {
        readiness.enable = true;
        apps.plex.enable = true;
      };
    }).config;
  incompleteSyncthing =
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = [ "syncthing" ];
        };
        optional.apps.syncthing.enable = true;
      };
    }).config;
  unversionedSyncthing =
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = [ "syncthing" ];
        };
        optional.apps.syncthing.enable = true;
      };
      services.syncthing = {
        guiPasswordFile = "/run/secrets/syncthing-gui";
        settings = {
          devices.fixture.id = "fixture";
          folders.fixture = {
            path = "/var/lib/syncthing/fixture";
            devices = [ "fixture" ];
          };
        };
      };
    }).config;
  incompleteAdguard =
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = [ "adguardhome" ];
        };
        optional.apps.adguardhome.enable = true;
      };
    }).config;
  plaintextAdguard =
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = [ "adguardhome" ];
        };
        optional.apps.adguardhome.enable = true;
      };
      services.adguardhome = {
        mutableSettings = false;
        settings = {
          dns = {
            bootstrap_dns = [ "9.9.9.9" ];
            upstream_dns = [ "https://dns.quad9.net/dns-query" ];
          };
          users = [
            {
              name = "admin";
              password = "plaintext";
            }
          ];
        };
      };
    }).config;
  incompleteScrutiny =
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = [ "scrutiny" ];
        };
        optional.apps.scrutiny.enable = true;
      };
    }).config;
  incompletePaperless =
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = [ "paperless" ];
        };
        optional.apps.paperless.enable = true;
      };
      services.paperless.environmentFile = "/run/secrets/paperless.env";
    }).config;
  incompleteAcquisition = lib.genAttrs [ "unpackerr" "shelfmark" ] (
    name:
    (evaluate {
      homelab = {
        readiness = {
          enable = true;
          hostManaged = lib.optional (name == "shelfmark") "shelfmark";
        };
        optional.apps.${name}.enable = true;
      };
    }).config
  );
  complete =
    (evaluate {
      imports = [
        ../../examples/integrated-media.nix
        ../../examples/audio.nix
        ../../examples/usenet.nix
        ../../examples/optional-services.nix
        ../../examples/autobrr.nix
        ../../examples/operations.nix
        ../fixtures/readiness-host.nix
      ];
      homelab = {
        readiness.enable = true;
        apps =
          lib.genAttrs
            [
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
            ]
            (_: {
              enable = true;
            })
          // {
            qbittorrent.vpn.enable = false;
          };
        optional.apps =
          lib.genAttrs
            [
              "autobrr"
              "cross-seed"
              "unpackerr"
              "flaresolverr"
              "komga"
              "kavita"
              "shelfmark"
              "pinchflat"
              "immich"
              "paperless"
              "syncthing"
              "adguardhome"
              "scrutiny"
              "maintainerr"
            ]
            (_: {
              enable = true;
            });
      };
    }).config;
in
{
  qbittorrentCredentialsRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "qBittorrent credentialsFile" assertion.message
  ) missingQbittorrentCredentials.homelab.readiness.checks;
  qbittorrentStoreCredentialsRejected = lib.any (
    assertion:
    !assertion.assertion
    && lib.hasInfix "qBittorrent credentialsFile outside the Nix store" assertion.message
  ) storeQbittorrentCredentials.homelab.readiness.checks;
  sonarrIntegrationRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "Sonarr integration" assertion.message
  ) missingSonarrIntegration.homelab.readiness.checks;
  sonarrResourcesRequired = lib.any (
    assertion:
    !assertion.assertion && lib.hasInfix "configured Sonarr integration resources" assertion.message
  ) incompleteSonarrIntegration.homelab.readiness.checks;
  managerConfigurationRequired =
    lib.all
      (
        name:
        lib.any (
          assertion:
          !assertion.assertion
          && lib.hasInfix "configured ${
            {
              radarr = "Radarr";
              lidarr = "Lidarr";
              prowlarr = "Prowlarr";
              bazarr = "Bazarr";
            }
            .${name}
          } integration" assertion.message
        ) incompleteManagerIntegration.${name}.homelab.readiness.checks
      )
      [
        "radarr"
        "lidarr"
        "prowlarr"
        "bazarr"
      ];
  applicationConfigurationRequired =
    lib.all
      (
        name:
        lib.any (
          assertion:
          !assertion.assertion
          && lib.hasInfix "configured ${
            {
              jellyfin = "Jellyfin";
              seerr = "Seerr";
              navidrome = "Navidrome";
              audiobookshelf = "Audiobookshelf";
            }
            .${name}
          } integration policy" assertion.message
        ) incompleteApplicationIntegration.${name}.homelab.readiness.checks
      )
      [
        "jellyfin"
        "seerr"
        "navidrome"
        "audiobookshelf"
      ];
  jellyfinAutomationKeyRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "dedicated Jellyfin API key" assertion.message
  ) passwordOnlyJellyfin.homelab.readiness.checks;
  operationsRequired = lib.any (
    assertion:
    !assertion.assertion
    && lib.hasInfix "operations, backup, monitoring, and notifications" assertion.message
  ) missingOperations.homelab.readiness.checks;
  mediaMountRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "explicit media mount" assertion.message
  ) missingMediaMount.homelab.readiness.checks;
  downloaderCredentialsRequired =
    lib.any (
      assertion: !assertion.assertion && lib.hasInfix "SABnzbd secretFiles" assertion.message
    ) missingDownloaderCredentials.sabnzbd.homelab.readiness.checks
    && lib.any (
      assertion: !assertion.assertion && lib.hasInfix "NZBGet credentialsFile" assertion.message
    ) missingDownloaderCredentials.nzbget.homelab.readiness.checks;
  autobrrIntegrationRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "autobrr integration" assertion.message
  ) missingAutobrrIntegration.homelab.readiness.checks;
  autobrrPolicyRequired =
    lib.all
      (
        evaluated:
        lib.any (
          assertion:
          !assertion.assertion
          && lib.hasInfix "configured autobrr clients, bounded filters, and runtime secrets" assertion.message
        ) evaluated.homelab.readiness.checks
      )
      [
        incompleteAutobrrIntegration
        unboundedAutobrrIntegration
      ];
  hostManagedAcknowledgementRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "host-managed setup for plex" assertion.message
  ) missingPlexAcknowledgement.homelab.readiness.checks;
  syncthingPeersAndAuthenticationRequired = lib.any (
    assertion:
    !assertion.assertion
    && lib.hasInfix "Syncthing devices, versioned folders, and GUI password" assertion.message
  ) incompleteSyncthing.homelab.readiness.checks;
  syncthingVersioningRequired = lib.any (
    assertion:
    !assertion.assertion
    && lib.hasInfix "Syncthing devices, versioned folders, and GUI password" assertion.message
  ) unversionedSyncthing.homelab.readiness.checks;
  adguardPolicyRequired =
    lib.all
      (
        evaluated:
        lib.any (
          assertion:
          !assertion.assertion
          && lib.hasInfix "AdGuard Home upstream, bootstrap, bcrypt users, and immutable settings" assertion.message
        ) evaluated.homelab.readiness.checks
      )
      [
        incompleteAdguard
        plaintextAdguard
      ];
  scrutinyDeviceAllowlistRequired = lib.any (
    assertion:
    !assertion.assertion && lib.hasInfix "Scrutiny collector and device allowlist" assertion.message
  ) incompleteScrutiny.homelab.readiness.checks;
  paperlessExportRequired = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "Paperless document exporter" assertion.message
  ) incompletePaperless.homelab.readiness.checks;
  acquisitionConfigurationRequired =
    lib.any (
      assertion:
      !assertion.assertion && lib.hasInfix "Unpackerr manager or watch-folder" assertion.message
    ) incompleteAcquisition.unpackerr.homelab.readiness.checks
    && lib.any (
      assertion: !assertion.assertion && lib.hasInfix "Shelfmark runtime environment" assertion.message
    ) incompleteAcquisition.shelfmark.homelab.readiness.checks;
  completeConfigurationPasses = lib.all (
    assertion: assertion.assertion
  ) complete.homelab.readiness.checks;
}
