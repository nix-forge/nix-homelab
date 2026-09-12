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
        script = ''
          mkdir -p /run/access-fixture
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
            -keyout /run/access-fixture/key -out /run/access-fixture/certificate \
            -subj '/CN=auth.homelab.home.arpa' -addext 'subjectAltName=DNS:auth.homelab.home.arpa,DNS:dashboard.homelab.home.arpa' >/dev/null 2>&1
          for name in jwt session storage; do printf '%s' disposable-fixture-secret-with-at-least-32-bytes > /run/access-fixture/"$name"; done
          ${(pkgs.python3.withPackages (ps: [ ps.argon2-cffi ]))}/bin/python3 - <<'PY'
          import json
          from argon2 import PasswordHasher
          password = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1).hash("disposable-password")
          # JSON is valid YAML and avoids interpolating hash metacharacters.
          with open('/run/access-fixture/users', 'w') as users:
              json.dump({'users': {'fixture': {'displayname': 'Fixture', 'password': password, 'email': 'fixture@example.invalid', 'groups': ['media']}}}, users)
          PY
        '';
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
  testScript = ''
    start_all()
    server.wait_for_unit("authelia-homelab.service")
    server.wait_for_unit("caddy.service")
    server.wait_for_unit("dashboard-fixture.service")
    client.wait_until_succeeds("curl -kfsS https://auth.homelab.home.arpa/api/health")
    client.succeed("test $(curl -ks -o /dev/null -w '%{http_code}' https://dashboard.homelab.home.arpa/) = 302")
    client.succeed("test $(curl -ks -H 'Remote-User: fixture' -H 'Remote-Groups: media' -H 'X-Forwarded-User: fixture' -o /dev/null -w '%{http_code}' https://dashboard.homelab.home.arpa/) = 302")
    client.fail("curl -fsS --connect-timeout 2 http://192.168.1.10:8082/")
    client.fail("curl -fsS --connect-timeout 2 http://192.168.1.10:9091/api/health")
    server.fail("curl -fsS --connect-timeout 2 http://127.0.0.1:2019/config/")
    client.succeed("curl -kfSs -c /tmp/session -H 'Content-Type: application/json' -d '{\"username\":\"fixture\",\"password\":\"disposable-password\",\"keepMeLoggedIn\":false,\"targetURL\":\"https://dashboard.homelab.home.arpa/\",\"requestMethod\":\"GET\"}' https://auth.homelab.home.arpa/api/firstfactor")
    client.succeed("curl -kfSs -b /tmp/session https://dashboard.homelab.home.arpa/ | grep -F 'protected fixture'")
    server.succeed("systemctl stop nftables")
    server.fail("systemctl is-active dashboard-fixture")
    client.fail("curl -fsS --connect-timeout 2 http://192.168.1.10:8082/")
    server.succeed("systemctl start nftables; systemctl start authelia-homelab dashboard-fixture caddy")
    # Memory-backed sessions must not survive an identity service restart.
    server.succeed("systemctl restart authelia-homelab")
    server.wait_for_unit("authelia-homelab.service")
    client.wait_until_succeeds("test $(curl -ks -b /tmp/session -o /dev/null -w '%{http_code}' https://dashboard.homelab.home.arpa/) = 302")
  '';
}
