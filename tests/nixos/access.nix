{ homelabModule }: {
  name = "homelab-private-access";
  nodes.server = { pkgs, ... }: {
    imports = [
      homelabModule
      ../../modules/operations
    ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1536;
    networking.interfaces.eth1.ipv4.addresses = [
      {
        address = "192.168.1.10";
        prefixLength = 24;
      }
    ];
    # Deliberately open backend ports to prove the separate protection rule.
    networking.firewall.allowedTCPPorts = [
      8082
      9091
    ];
    homelab.operations = {
      enable = true;
      access = {
        enable = true;
        bindAddress = "192.168.1.10";
        allowedInterfaces = [ "eth1" ];
        certificateFile = "/run/access-fixture/certificate";
        keyFile = "/run/access-fixture/key";
        usersFile = "/run/access-fixture/users";
        jwtSecretFile = "/run/access-fixture/jwt";
        sessionSecretFile = "/run/access-fixture/session";
        storageEncryptionKeyFile = "/run/access-fixture/storage";
        backends.dashboard = {
          port = 8082;
          unit = "dashboard-fixture";
          policy = "one_factor";
        };
      };
    };
    systemd.services = {
      access-fixture = {
        before = [
          "caddy.service"
          "authelia-homelab.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = (import ../../lib/render-text.nix) ./scripts/prepare-access-fixture.sh {
          pkgs_openssl = pkgs.openssl;
          pkgs_python3_withPackages_ps_ps_argon2_cffi = pkgs.python3.withPackages (ps: [ ps.argon2-cffi ]);
          pythonCheck1 = ./scripts/prepare_access_users.py;

        };
      };
      caddy = {
        requires = [ "access-fixture.service" ];
        after = [ "access-fixture.service" ];
      };
      authelia-homelab = {
        requires = [ "access-fixture.service" ];
        after = [ "access-fixture.service" ];
      };
      dashboard-fixture = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8082 --bind 0.0.0.0 --directory ${pkgs.writeTextDir "index.html" "protected fixture"}";
        };
      };
    };
  };
  nodes.client = {
    system.stateVersion = "26.05";
    networking.hosts."192.168.1.10" = [
      "auth.homelab.home.arpa"
      "dashboard.homelab.home.arpa"
    ];
  };
  testScript = builtins.readFile ./scripts/access_test.py;
}
