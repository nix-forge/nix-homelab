{ homelabModule, ... }: {
  name = "homelab-karakeep-runtime";

  nodes.machine =
    { pkgs, ... }:
    let
      webServer = pkgs.writeText "karakeep-test-web.py" ''
        import json
        import os
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from pathlib import Path

        state = Path("/var/lib/karakeep")
        assert os.environ["MEILI_MASTER_KEY"] == state.joinpath("meili-master-key").read_text().strip()
        assert os.environ["NEXTAUTH_SECRET"] == state.joinpath("nextauth-secret").read_text().strip()
        assert os.environ["MEILI_ADDR"] == "http://127.0.0.1:7700"
        assert os.environ["BROWSER_WEB_URL"] == "http://127.0.0.1:19222"

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != "/api/health":
                    self.send_error(404)
                    return
                body = json.dumps({"status": "ok"}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args):
                pass

        HTTPServer((os.environ["HOST"], int(os.environ["PORT"])), Handler).serve_forever()
      '';
      web = pkgs.writeShellScript "karakeep-test-web" ''
        exec ${pkgs.python3}/bin/python3 ${webServer}
      '';
      workers = pkgs.writeShellScript "karakeep-test-workers" ''
        test "$MEILI_MASTER_KEY" = "$(cat /var/lib/karakeep/meili-master-key)"
        test "$NEXTAUTH_SECRET" = "$(cat /var/lib/karakeep/nextauth-secret)"
        exec ${pkgs.coreutils}/bin/sleep infinity
      '';
      migrate = pkgs.writeShellScript "karakeep-test-migrate" ''
        test "$DATA_DIR" = /var/lib/karakeep
      '';
      package = pkgs.runCommand "karakeep-test-package" { } ''
        mkdir -p "$out/lib/karakeep"
        ln -s ${web} "$out/lib/karakeep/start-web"
        ln -s ${workers} "$out/lib/karakeep/start-workers"
        ln -s ${migrate} "$out/lib/karakeep/migrate"
      '';
    in
    {
      imports = [ homelabModule ];
      homelab.optional = {
        apps.karakeep.enable = true;
        karakeep = {
          inherit package;
          port = 15337;
          browserPort = 19222;
          extraEnvironment.DISABLE_SIGNUPS = "true";
        };
      };
      environment.systemPackages = [ pkgs.netcat-openbsd ];
      virtualisation = {
        cores = 2;
        memorySize = 3072;
      };
    };

  testScript = ''
    import json

    machine.start()
    machine.wait_for_unit("homelab-karakeep-secrets.service")
    machine.wait_for_unit("meilisearch.service")
    machine.wait_for_unit("karakeep-browser.service")
    machine.wait_for_unit("karakeep-workers.service")
    machine.wait_for_unit("karakeep-web.service")
    machine.wait_for_open_port(15337)
    machine.wait_for_open_port(19222)

    health = json.loads(machine.succeed("curl --fail --silent http://127.0.0.1:15337/api/health"))
    assert health == {"status": "ok"}
    machine.succeed("ss --listening --tcp --numeric | grep -q '127.0.0.1:15337'")
    machine.succeed("ss --listening --tcp --numeric | grep -q '127.0.0.1:19222'")
    machine.succeed("nc -z -w 1 127.0.0.1 19222")
    machine.fail("runuser -u nobody -- nc -z -w 1 127.0.0.1 19222")
    machine.fail("systemctl cat karakeep-browser.service | grep -q -- --no-sandbox")
    browser_properties = machine.succeed(
        "systemctl show karakeep-browser.service -p User -p NoNewPrivileges -p PrivateUsers -p RestrictNamespaces"
    )
    assert "User=karakeep-browser" in browser_properties
    assert "NoNewPrivileges=yes" in browser_properties
    assert "PrivateUsers=no" in browser_properties
    assert "RestrictNamespaces=no" in browser_properties
    machine.fail("curl --fail --silent http://127.0.0.1:7700/keys")
    machine.succeed(
        "curl --fail --silent --header \"Authorization: Bearer $(cat /var/lib/karakeep/meili-master-key)\" "
        "http://127.0.0.1:7700/keys >/dev/null"
    )

    machine.succeed("test $(stat --format=%a /var/lib/karakeep/settings.env) = 400")
    machine.succeed("test $(stat --format=%a /var/lib/karakeep/meili-master-key) = 400")
    machine.succeed("test $(stat --format=%a /var/lib/karakeep/nextauth-secret) = 400")
    original = machine.succeed("cat /var/lib/karakeep/nextauth-secret")

    properties = machine.succeed(
        "systemctl show karakeep-web.service "
        "-p User -p NoNewPrivileges -p ProtectSystem -p ProtectHome "
        "-p MemoryMax -p TasksMax"
    )
    assert "User=karakeep" in properties
    assert "NoNewPrivileges=yes" in properties
    assert "ProtectSystem=strict" in properties
    assert "ProtectHome=yes" in properties
    assert "MemoryMax=2147483648" in properties
    assert "TasksMax=512" in properties

    machine.succeed("systemctl restart karakeep-web.service")
    machine.wait_for_open_port(15337)
    assert machine.succeed("cat /var/lib/karakeep/nextauth-secret") == original
  '';
}
