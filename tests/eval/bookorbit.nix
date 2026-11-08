{ evaluate, lib }:
let
  secretNames = [
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
  configured = (evaluate { imports = [ base ]; }).config;
  automated =
    (evaluate {
      imports = [
        base
        ({ config, ... }: {
          homelab.apps.qbittorrent.apiKeyFile = "/run/secrets/qbittorrent-api-key";
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
          extra
        ];
      }).config.assertions;
  hasReadOnlyMount =
    target: cfg:
    lib.any (
      path: lib.hasSuffix ":${target}" path
    ) cfg.systemd.services.bookorbit.serviceConfig.BindReadOnlyPaths;
in
{
  optIn =
    !disabled.homelab.apps.bookorbit.enable
    && !disabled.services.bookorbit.enable
    && disabled.virtualisation.oci-containers.containers == { };
  nativeOnly =
    lib.all (assertion: assertion.assertion) configured.assertions
    && configured.services.bookorbit.enable
    && !configured.virtualisation.podman.enable
    && configured.virtualisation.oci-containers.containers == { }
    && !(configured.systemd.services ? bookorbit-images)
    && !(configured.systemd.services ? podman-bookorbit)
    && !(configured.systemd.services ? bookorbit-schema-notifications)
    && configured.systemd.services.bookorbit.serviceConfig.User == "bookorbit"
    && configured.systemd.services.bookorbit-native-db.serviceConfig.User == "bookorbit"
    && !configured.users.users.bookorbit.linger
    && builtins.elem "DATABASE_URL=postgresql:///bookorbit?host=/run/bookorbit-postgres&user=bookorbit" configured.systemd.services.bookorbit.serviceConfig.Environment
    && lib.hasInfix " -k /run/bookorbit-postgres -c listen_addresses= " configured.systemd.services.bookorbit-native-db.serviceConfig.ExecStart;
  migrationOrdering =
    builtins.elem "bookorbit-native-db.service" configured.systemd.services.bookorbit-migrate.requires
    && builtins.elem "bookorbit-migrate.service" configured.systemd.services.bookorbit.requires
    && builtins.elem "bookorbit-migrate.service" configured.systemd.services.bookorbit.after
    && builtins.elem "bookorbit-secrets.service" configured.systemd.services.bookorbit.requires;
  readOnlyLibrary =
    !configured.homelab.apps.bookorbit.acquisition.enable
    && hasReadOnlyMount "/books" configured
    && configured.systemd.services.bookorbit.serviceConfig.BindPaths == [ ];
  nativeDnsPolicy =
    lib.all
      (
        cfg:
        cfg.systemd.services.bookorbit.serviceConfig.NetworkNamespacePath == "/run/netns/vpnapps"
        && hasReadOnlyMount "/etc/resolv.conf" cfg
        && hasReadOnlyMount "/etc/nsswitch.conf" cfg
        && builtins.elem "-/run/systemd/resolve/io.systemd.Resolve" cfg.systemd.services.bookorbit.serviceConfig.InaccessiblePaths
      )
      [
        configured
        automated
      ];
  proxyOnlyBoundary =
    configured.homelab.apps.prowlarr.proxyOnly
    && configured.systemd.services.prowlarr.serviceConfig.IPAddressDeny == [ "any" ]
    && builtins.elem "${configured.homelab.vpn.namespace.bindAddress}/32" configured.systemd.services.prowlarr.serviceConfig.IPAddressAllow;
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
    automated.homelab.apps.bookorbit.acquisition.enable
    && lib.all (assertion: assertion.assertion) automated.assertions
    && automated.virtualisation.oci-containers.containers == { }
    && !automated.virtualisation.podman.enable
    && !hasReadOnlyMount "/books" automated
    && builtins.elem "/run/bookorbitmedia/intake:/intake" automated.systemd.services.bookorbit.serviceConfig.BindPaths
    && builtins.elem "/run/bookorbitmedia/library0:/books/books" automated.systemd.services.bookorbit.serviceConfig.BindPaths
    && builtins.elem "run-bookorbitmedia-intake.mount" automated.systemd.services.bookorbit.requires
    && builtins.elem "homelab-configure-qbittorrent.service" automated.systemd.services.bookorbit-bootstrap.requires;
}
