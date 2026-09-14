{ homelabModule }: {
  name = "homelab-maintainerr-runtime";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 3072;
    virtualisation.diskSize = 8192;
    environment.systemPackages = [ pkgs.curl ];
    homelab.optional = {
      apps.maintainerr.enable = true;
      maintainerr.htpasswdFile = "/etc/maintainerr-test.htpasswd";
    };
    environment.etc."maintainerr-test.htpasswd".text = "viewer:{SHA}qUqP5cyxm6YcTAhz05Hph5gvu9M=\n";
  };
  testScript = ''
    from datetime import timedelta

    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("homelab-maintainerr.service")
    machine.wait_until_succeeds("curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready >/dev/null", timeout=timedelta(minutes=3))
    machine.succeed("curl -fsS -u viewer:test http://127.0.0.1:6246/ >/dev/null")
    machine.succeed("getent ahostsv4 host.containers.internal | grep -q '^127\\.0\\.0\\.1 '")
    machine.succeed("test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6246/api/health/ready) = 401")
    machine.fail("runuser -u nobody -- curl -fsS --max-time 3 http://127.0.0.1:6247/api/health/ready")
    machine.fail("runuser -u nobody -- test -r /var/lib/homelab-maintainerr/data")
    properties = machine.succeed("systemctl show homelab-maintainerr.service -p User -p NoNewPrivileges -p ProtectSystem -p RestrictNamespaces")
    assert "User=homelab-maintainerr" in properties
    assert "NoNewPrivileges=yes" in properties
    assert "ProtectSystem=strict" in properties
    assert "RestrictNamespaces=yes" in properties
    pid = machine.succeed("systemctl show --property MainPID --value homelab-maintainerr.service").strip()
    status = machine.succeed(f"cat /proc/{pid}/status")
    fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
    assert fields["Uid"].split()[1] != "0"
    assert int(fields["CapEff"].strip(), 16) == 0
    assert fields["NoNewPrivs"].strip() == "1"
    machine.succeed("runuser -u homelab-maintainerr -- sh -c 'echo fixture > /var/lib/homelab-maintainerr/data/restart-fixture'")
    machine.succeed("systemctl restart homelab-maintainerr.service")
    machine.wait_until_succeeds("curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready >/dev/null", timeout=timedelta(minutes=3))
    machine.succeed("grep -q fixture /var/lib/homelab-maintainerr/data/restart-fixture")
  '';
}
