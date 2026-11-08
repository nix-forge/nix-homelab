{ evaluate, lib }:
let
  secretNames = [
    "postgres-password"
    "jwt-secret"
    "setup-token"
    "request-key"
    "podcast-key"
    "admin-username"
    "admin-email"
    "admin-password"
  ];
  base = { config, ... }: {
    imports = [ ../../examples/media-server.nix ];
    security.acme = {
      acceptTerms = true;
      certs."bookorbit.example.test" = {
        webroot = "/var/lib/acme/acme-challenge";
        group = "nginx";
      };
    };
    homelab.operations.lanHttps = {
      enable = true;
      domain = "example.test";
      certificateHost = "bookorbit.example.test";
      listenAddresses = [ "127.0.0.1" ];
      allowedCIDRs = [ "127.0.0.0/8" ];
    };
    homelab.apps.prowlarr = {
      enable = true;
      proxyOnly = true;
    };
    homelab.indexerProxy = {
      enable = true;
      passwordFile = "/run/secrets/indexer-proxy-password";
    };
    homelab.apps.bookorbit = {
      enable = true;
      uid = 920;
      gid = 920;
      credentials = lib.genAttrs secretNames (name: "/run/secrets/bookorbit-${name}");
      secretReadyUnit = "fixture-secrets.service";
      readerReadyUnit = "fixture-readers.service";
      storage = {
        inherit (config.homelab.storage)
          rootDir
          libraryDir
          group
          requiredMounts
          ;
        mediaDirs = [ "${config.homelab.storage.libraryDir}/books" ];
        readyUnit = "fixture-storage.service";
      };
      prowlarr = {
        apiKeyFile = "/run/secrets/prowlarr-api-key";
        readyUnit = "fixture-prowlarr.service";
        proxyHost = config.homelab.vpn.namespace.bindAddress;
        proxyPort = config.homelab.indexerProxy.port;
      };
      libraries = [
        {
          name = "Books";
          icon = "BookOpen";
          folder = "/books/books";
          formats = [
            "epub"
            "cbz"
          ];
          organizationMode = "book_per_file";
        }
      ];
    };
  };
  containerImages.homelab.apps.bookorbit = {
    image = "registry.example.invalid/bookorbit@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    databaseImage = "registry.example.invalid/pgvector@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  };
  configured =
    (evaluate {
      imports = [
        base
        containerImages
      ];
    }).config;
  native =
    (evaluate {
      imports = [ base ];
      homelab.apps.bookorbit.native = true;
    }).config;
  automated =
    (evaluate {
      imports = [
        base
        containerImages
        ({ config, ... }: {
          homelab.apps.qbittorrent.configuration.categories.bookorbit.savePath =
            "${config.homelab.storage.downloadsDir}/torrents/bookorbit/downloads";
          homelab.apps.bookorbit.acquisition = {
            enable = true;
            downloadDir = config.homelab.apps.qbittorrent.configuration.categories.bookorbit.savePath;
            dockDir = "${config.homelab.storage.downloadsDir}/torrents/bookorbit/dock";
            writableMediaDirs = [ "${config.homelab.storage.libraryDir}/books" ];
            usernameFile = "/run/secrets/qbittorrent-username";
            passwordFile = "/run/secrets/qbittorrent-password";
            destinations = {
              audiobook = "Books";
              ebook = "Books";
            };
          };
        })
      ];
    }).config;
  disabled = (evaluate { }).config;
  rejected =
    extra:
    lib.any (assertion: !assertion.assertion)
      (evaluate {
        imports = [
          base
          containerImages
          extra
        ];
      }).config.assertions;
in
{
  optIn =
    !disabled.homelab.apps.bookorbit.enable
    && !(disabled.virtualisation.oci-containers.containers ? bookorbit);
  nativeWithoutImages =
    lib.all (assertion: assertion.assertion) native.assertions
    && native.services.bookorbit.enable
    && !native.virtualisation.podman.enable
    && native.virtualisation.oci-containers.containers == { }
    && !(native.systemd.services ? bookorbit-images)
    && !(native.systemd.services ? podman-bookorbit)
    && native.systemd.services.bookorbit.serviceConfig.NetworkNamespacePath == "/run/netns/vpnapps"
    && builtins.elem "bookorbit-native-db.service" native.systemd.services.bookorbit.requires
    && builtins.elem "bookorbit-secrets.service" native.systemd.services.bookorbit.requires
    && builtins.elem "DATABASE_URL=postgresql:///bookorbit?host=/run/bookorbit-postgres&user=bookorbit" native.systemd.services.bookorbit.serviceConfig.Environment
    && lib.hasInfix " -k /run/bookorbit-postgres -c listen_addresses= " native.systemd.services.bookorbit-native-db.serviceConfig.ExecStart;
  nativeReadOnlyLibrary =
    !native.homelab.apps.bookorbit.acquisition.enable
    && builtins.elem "${native.homelab.apps.bookorbit.storage.libraryDir}:/books" native.systemd.services.bookorbit.serviceConfig.BindReadOnlyPaths
    && native.systemd.services.bookorbit.serviceConfig.BindPaths == [ ];
  schemaNotificationsOrdered =
    builtins.elem "bookorbit-schema-notifications.service" configured.systemd.services.podman-bookorbit.requires
    && builtins.elem "bookorbit-schema-notifications.service" configured.systemd.services.podman-bookorbit.after
    && builtins.elem "podman-bookorbit-db.service" configured.systemd.services.bookorbit-schema-notifications.requires
    && builtins.elem "podman-bookorbit-db.service" configured.systemd.services.bookorbit-schema-notifications.after
    && !(native.systemd.services ? bookorbit-schema-notifications);
  privateContainers =
    configured.virtualisation.oci-containers.containers.bookorbit.ports == [ ]
    && configured.virtualisation.oci-containers.containers.bookorbit-db.ports == [ ]
    &&
      configured.virtualisation.oci-containers.containers.bookorbit-db.environment.PGDATA
      == "/var/lib/postgresql/18/docker"
    && builtins.elem "${configured.homelab.storage.libraryDir}:/books:ro" configured.virtualisation.oci-containers.containers.bookorbit.volumes;
  namespaceAndRuntimeUid =
    configured.systemd.services.podman-bookorbit.serviceConfig.NetworkNamespacePath
    == "/run/netns/vpnapps"
    && builtins.elem "--cidfile=/run/user/920/bookorbit.ctr-id" configured.virtualisation.oci-containers.containers.bookorbit.extraOptions;
  proxyOnlyBoundary =
    configured.homelab.apps.prowlarr.proxyOnly
    && configured.systemd.services.prowlarr.serviceConfig.IPAddressDeny == [ "any" ]
    && builtins.elem "${configured.homelab.vpn.namespace.bindAddress}/32" configured.systemd.services.prowlarr.serviceConfig.IPAddressAllow;
  digestRequired = rejected { homelab.apps.bookorbit.image = lib.mkForce "bookorbit:latest"; };
  malformedDigestRejected = rejected {
    homelab.apps.bookorbit.image = lib.mkForce "registry.example.invalid/bookorbit@sha256:abc";
  };
  traversalRejected = rejected {
    homelab.apps.bookorbit.libraries = lib.mkForce [
      {
        name = "Bad";
        icon = "BookOpen";
        folder = "/books/../etc";
        formats = [ "epub" ];
        organizationMode = "book_per_file";
      }
    ];
  };
  missingProxyGuardRejected = rejected { homelab.apps.prowlarr.proxyOnly = lib.mkForce false; };
  automationIsOptInAndScoped =
    !configured.homelab.apps.bookorbit.acquisition.enable
    && automated.homelab.apps.bookorbit.acquisition.enable
    && builtins.elem "/run/bookorbitmedia/intake:/intake:rw" automated.virtualisation.oci-containers.containers.bookorbit.volumes
    && builtins.elem "/run/bookorbitmedia/library0:/books/books:rw" automated.virtualisation.oci-containers.containers.bookorbit.volumes
    && builtins.elem "run-bookorbitmedia-intake.mount" automated.systemd.services.podman-bookorbit.requires
    && builtins.elem "homelab-configure-qbittorrent.service" automated.systemd.services.bookorbit-bootstrap.requires;
}
