{ homelabModule }: {
  name = "homelab-bookorbit-native-recovery";
  nodes.machine =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      postgres = (pkgs.postgresql_18.override { systemdSupport = true; }).withPackages (ps: [
        ps.pgvector
      ]);
      secrets = [
        "jwt-secret"
        "setup-token"
        "request-key"
        "podcast-key"
        "admin-username"
        "admin-email"
        "admin-password"
      ];
      home = "/var/lib/bookorbit";
      database = "${home}/postgres/native";
    in
    {
      imports = [ homelabModule ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 4096;
      virtualisation.diskSize = 12288;
      virtualisation.cores = 2;
      networking.useDHCP = false;
      networking.interfaces.eth1.useDHCP = false;
      # No external gateway or resolver: the only tunnel peer is inside this VM.
      environment.systemPackages = [
        postgres
        pkgs.python3
        pkgs.acl
        pkgs.util-linux
        pkgs.iproute2
      ];
      environment.etc."native-bookorbit-address".text = config.homelab.vpn.namespace.bindAddress;
      environment.etc."bookorbit_native_runtime.py".source = ../fixtures/bookorbit_native_runtime.py;

      homelab.storage = {
        enable = true;
        rootDir = "/srv/bookorbit-fixture";
      };
      homelab.operations.enable = true;
      homelab.operations.lanHttps = {
        enable = true;
        domain = "example.test";
        certificateHost = "bookorbit.example.test";
      };
      security.acme = {
        acceptTerms = true;
        defaults.email = "fixture@example.invalid";
        certs."bookorbit.example.test" = {
          webroot = "/var/lib/acme/acme-challenge";
          group = "nginx";
        };
      };
      # Satisfy the real option contract without attempting certificates/providers.
      systemd.services.nginx.enable = lib.mkForce false;
      systemd.services."acme-bookorbit.example.test".enable = lib.mkForce false;
      systemd.timers."acme-bookorbit.example.test".enable = lib.mkForce false;
      homelab.apps.prowlarr = {
        enable = true;
        proxyOnly = true;
      };
      homelab.indexerProxy = {
        enable = true;
        passwordFile = "/run/bookorbit-fixture/proxy-password";
      };
      systemd.services.prowlarr.enable = lib.mkForce false;
      systemd.services.microsocks.enable = lib.mkForce false;
      systemd.services.bookorbit-prowlarr-host-bridge.enable = lib.mkForce false;
      systemd.services.bookorbit-prowlarr-namespace-bridge.enable = lib.mkForce false;
      systemd.services.bookorbit-bootstrap.wantedBy = lib.mkForce [ ];

      homelab.vpn = {
        enable = true;
        interface = {
          privateKeyFile = "/run/wg-test/client.key";
          addressIPv4 = "10.71.216.231";
          dns = [ "10.71.216.232" ];
        };
        peer = {
          publicKey = "iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg=";
          endpointHost = "127.0.0.1";
          endpointPort = 51821;
          persistentKeepalive = 1;
        };
      };
      systemd.services.test-wireguard-peer = {
        requiredBy = [ "wireguard-wg0.service" ];
        before = [ "wireguard-wg0.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.coreutils
          pkgs.iproute2
          pkgs.wireguard-tools
        ];
        # Reuse the public local-peer fixture; both addresses stay inside this VM.
        script = builtins.readFile ./scripts/configure-vpn-peer.sh;
        postStop = (import ../../lib/render-text.nix) ./scripts/remove-vpn-peer.sh {
          pkgs_iproute2 = pkgs.iproute2;
        };
      };

      homelab.apps.bookorbit = {
        enable = true;
        uid = 920;
        gid = 920;
        credentials = lib.genAttrs secrets (name: "/run/bookorbit-fixture/${name}");
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
          readyUnit = "homelab-storage.service";
        };
        prowlarr = {
          apiKeyFile = "/run/bookorbit-fixture/prowlarr-api-key";
          readyUnit = "fixture-unused-prowlarr.service";
          proxyHost = config.homelab.vpn.namespace.bindAddress;
          proxyPort = config.homelab.indexerProxy.port;
        };
        acquisition.enable = false;
        metadataProviders = {
          amazon.enabled = false;
          goodreads.enabled = false;
          itunes.enabled = false;
          openLibrary.enabled = false;
        };
        libraries = [
          {
            name = "Native recovery fixture";
            icon = "BookOpen";
            folder = "/books/books";
            formats = [ "epub" ];
            organizationMode = "book_per_file";
          }
        ];
      };
      systemd.services.fixture-secrets = {
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        path = [ pkgs.coreutils ];
        # Disposable public test values only. Hosts use nix-seal instead.
        script = builtins.readFile ./scripts/prepare-bookorbit-secrets.sh;
      };
      systemd.services.fixture-unused-prowlarr = {
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = "true";
      };
      systemd.services.fixture-readers = {
        requires = [ "homelab-storage.service" ];
        after = [ "homelab-storage.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = "true";
      };
      # A host must initialize its PG18 cluster. Keep this fixture provisioner
      # separate from the real generated database unit so PG_VERSION is tested.
      systemd.services.fixture-initdb = {
        serviceConfig = {
          Type = "oneshot";
          User = "bookorbit";
          Group = "bookorbit";
        };
        script = "${postgres}/bin/initdb -D ${database} --username=bookorbit --auth-local=peer --auth-host=reject";
      };
      systemd.services.fixture-database-schema = {
        requires = [ "bookorbit-native-db.service" ];
        after = [ "bookorbit-native-db.service" ];
        requiredBy = [ "bookorbit-migrate.service" ];
        before = [ "bookorbit-migrate.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "bookorbit";
          Group = "bookorbit";
        };
        path = [ postgres ];
        script = builtins.readFile ./scripts/create-bookorbit-database.sh;
      };
      # The driver starts these only after proving uninitialized startup fails.
      # ExecStart, hardening, migration dependencies and identities stay generated.
      systemd.services.bookorbit.wantedBy = lib.mkForce [ ];
      systemd.services.bookorbit-native-db.wantedBy = lib.mkForce [ ];
      systemd.services.bookorbit-metadata-policy.wantedBy = lib.mkForce [ ];
    };
  testScript = builtins.readFile ./scripts/bookorbit_native_test.py;
}
