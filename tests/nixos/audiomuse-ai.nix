{ homelabModule }: {
  name = "homelab-audiomuse-ai-runtime";
  nodes.machine =
    { pkgs, ... }:
    let
      web = pkgs.writeShellApplication {
        name = "audiomuse-ai-web";
        runtimeInputs = [ pkgs.python3 ];
        text = ''
          test "$AUDIOMUSE_HOST" = 127.0.0.1
          test "$AUDIOMUSE_PORT" = 18000
          test "$PLUGIN_ALLOW_PIP" = false
          test "$POSTGRES_HOST" = /run/postgresql
          exec python3 ${pkgs.writeText "audiomuse-test-server.py" ''
            from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == "/api/health/ready":
                        self.send_response(200)
                    else:
                        self.send_response(404)
                    self.end_headers()

                def log_message(self, _format, *_args):
                    pass

            ThreadingHTTPServer(("127.0.0.1", 18000), Handler).serve_forever()
          ''}
        '';
      };
      idleRole =
        name:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.coreutils ];
          text = "exec sleep infinity";
        };
      package = pkgs.symlinkJoin {
        name = "audiomuse-ai-test-1";
        paths = [
          web
          (idleRole "audiomuse-ai-worker-high")
          (idleRole "audiomuse-ai-worker-default")
          (idleRole "audiomuse-ai-maintenance")
          (idleRole "audiomuse-ai-control")
        ];
      };
    in
    {
      imports = [ homelabModule ];
      system.stateVersion = "26.05";
      environment.systemPackages = [
        pkgs.curl
        pkgs.python3Packages.supervisor
      ];
      environment.etc."audiomuse-test.env".text = ''
        API_TOKEN=public-test-value
        AUDIOMUSE_HOST=0.0.0.0
        AUDIOMUSE_PORT=1
        PLUGIN_ALLOW_PIP=true
        POSTGRES_HOST=attacker.invalid
      '';
      services.audiomuse-ai = {
        enable = true;
        inherit package;
        port = 18000;
        environmentFile = "/etc/audiomuse-test.env";
        resources = {
          cpuQuota = "200%";
          memoryMax = "1G";
          tasksMax = 128;
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("audiomuse-ai.service")
    machine.succeed("curl -fsS http://127.0.0.1:18000/api/health/ready")
    machine.succeed("runuser -u audiomuse -- psql -U audiomusedb -d audiomusedb -Atc 'select current_user' | grep -qx audiomusedb")
    machine.succeed("test -d /var/lib/audiomuse-ai -a -d /var/cache/audiomuse-ai -a -d /run/audiomuse-ai")
    for role in (
        "flask",
        "queue-worker-high",
        "queue-worker-default",
        "queue-maintenance",
        "config-restart-listener",
    ):
        machine.succeed(
            "supervisorctl -s unix:///run/audiomuse-ai/supervisor.sock "
            f"status {role} | grep -q RUNNING"
        )
    properties = machine.succeed(
        "systemctl show audiomuse-ai.service "
        "-p User -p NoNewPrivileges -p ProtectSystem -p RestrictNamespaces "
        "-p MemoryMax -p TasksMax"
    )
    assert "User=audiomuse" in properties
    assert "NoNewPrivileges=yes" in properties
    assert "ProtectSystem=strict" in properties
    assert "RestrictNamespaces=yes" in properties
    assert "MemoryMax=1073741824" in properties
    assert "TasksMax=128" in properties
    machine.succeed("systemctl restart audiomuse-ai.service")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18000/api/health/ready")
  '';
}
