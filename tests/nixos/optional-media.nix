{ homelabModule }: {
  name = "homelab-optional-media";
  nodes.machine = { pkgs, lib, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    services = {
      cross-seed = {
        package = pkgs.writeShellScriptBin "cross-seed" "exit 0";
        settings.linkDirs = [ "/mnt/media/data/cross-seed" ];
        settingsFile = "/etc/cross-seed-test.json";
      };
      syncthing.settings.folders.fixture = {
        path = "/var/lib/syncthing/shared";
        devices = [ ];
      };
      unpackerr.settings = {
        start_delay = "1s";
        retry_delay = "1s";
        folders.interval = "1s";
        folder = [
          {
            path = "/mnt/media/data/downloads/torrents";
            move_back = true;
            delete_after = "0s";
            delete_original = false;
            disable_recursion = true;
          }
        ];
      };
    };
    environment = {
      systemPackages = [
        pkgs.python3
        pkgs.curl
      ];
      etc."cross-seed-test.json".text = "{}";
      etc."maintainerr-test.htpasswd".text = "viewer:{SHA}qUqP5cyxm6YcTAhz05Hph5gvu9M=\n";
    };
    systemd = {
      services.cross-seed.wantedBy = lib.mkForce [ ];
      services.maintainerr-fixture = {
        after = [ "nftables.service" ];
        requires = [ "nftables.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "homelab-maintainerr";
          ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "maintainerr-fixture.py" ''
            from http.server import BaseHTTPRequestHandler, HTTPServer
            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(self.headers.get("Authorization", "cleared").encode())
            HTTPServer(("127.0.0.1", 6247), Handler).serve_forever()
          ''}";
        };
      };
    };
    homelab = {
      optional = {
        apps = {
          unpackerr.enable = true;
          cross-seed.enable = true;
          syncthing.enable = true;
          maintainerr.enable = true;
        };
        maintainerr.htpasswdFile = "/etc/maintainerr-test.htpasswd";
      };
      storage = {
        rootDir = "/mnt/media/data";
        requiredMounts = [ "/mnt/media" ];
      };
    };
    # This fixture supplies its own backend and tests only the proxy boundary.
    systemd.services.homelab-maintainerr.wantedBy = lib.mkForce [ ];
  };
  testScript = ''
    from datetime import timedelta

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("syncthing.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("maintainerr-fixture.service")
    machine.succeed("test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6246/api/health/ready) = 401")
    machine.succeed("test $(curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready) = cleared")
    machine.fail("runuser -u nobody -- curl -fsS --max-time 3 http://127.0.0.1:6247/api/health/ready")
    machine.wait_until_succeeds("test -f /var/lib/syncthing/.config/syncthing/config.xml")
    machine.wait_until_succeeds("test -d /var/lib/syncthing/shared/.stfolder")
    machine.wait_until_succeeds("systemctl is-failed homelab-storage.service")
    machine.fail("systemctl is-active unpackerr.service")
    machine.fail("test -e /mnt/media/data")
    machine.succeed("mkdir -p /mnt/media; mount -t tmpfs tmpfs /mnt/media")
    machine.succeed("systemctl reset-failed; systemctl start unpackerr.service")
    machine.wait_for_unit("unpackerr.service")
    machine.succeed("python -c 'import pathlib, zipfile; p=pathlib.Path(\"/mnt/media/data/downloads/torrents/fixture\"); p.mkdir(); z=zipfile.ZipFile(p/\"fixture.zip\", \"w\"); info=zipfile.ZipInfo(\"fixture.txt\"); info.external_attr=0o660 << 16; z.writestr(info, \"permitted fixture media\"); z.close()'")
    machine.succeed("chown -R unpackerr:media /mnt/media/data/downloads/torrents/fixture; chmod 2770 /mnt/media/data/downloads/torrents/fixture")
    machine.wait_until_succeeds("test -f /mnt/media/data/downloads/torrents/fixture/fixture.txt", timeout=timedelta(minutes=2))
    print(machine.succeed("stat -c %a:%U:%G /mnt/media/data/downloads/torrents/fixture/fixture.txt"))
    machine.succeed("test $(stat -c %a:%G /mnt/media/data/downloads/torrents/fixture/fixture.txt) = 660:media")
    machine.succeed("test -f /mnt/media/data/downloads/torrents/fixture/fixture.zip")
    machine.succeed("grep -q 'permitted fixture media' /mnt/media/data/downloads/torrents/fixture/fixture.txt")
    # Check the live service mount namespace, not only the host user's DAC rights.
    pid = machine.succeed("systemctl show unpackerr.service -p MainPID --value").strip()
    machine.fail(f"nsenter -t {pid} -m touch /mnt/media/data/library/forbidden")
    machine.succeed("systemctl restart unpackerr.service")
    machine.wait_for_unit("unpackerr.service")
    machine.succeed("test -f /mnt/media/data/downloads/torrents/fixture/fixture.zip")
    machine.succeed("mkdir -m 0700 /var/lib/guard-victim; rmdir /mnt/media/data/cross-seed; ln -s /var/lib/guard-victim /mnt/media/data/cross-seed")
    machine.fail("systemctl restart homelab-optional-storage.service")
    machine.succeed("test $(stat -c %a:%U:%G /var/lib/guard-victim) = 700:root:root")
  '';
}
