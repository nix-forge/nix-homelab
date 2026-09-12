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
    import json
    from datetime import timedelta

    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("podman-homelab-maintainerr.service")
    machine.wait_until_succeeds("curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready >/dev/null", timeout=timedelta(minutes=3))
    machine.succeed("test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:6246/api/health/ready) = 401")
    machine.fail("runuser -u nobody -- curl -fsS --max-time 3 http://127.0.0.1:6247/api/health/ready")
    machine.fail("runuser -u nobody -- test -r /var/lib/homelab-maintainerr/data")
    podman = "runuser -u homelab-maintainerr -- podman"
    inspected = json.loads(machine.succeed(f"{podman} inspect homelab-maintainerr"))[0]
    assert inspected["Config"]["User"] == "1000:1000"
    assert inspected["HostConfig"]["ReadonlyRootfs"]
    assert not inspected["HostConfig"]["Privileged"]
    pid = inspected["State"]["Pid"]
    status = machine.succeed(f"cat /proc/{pid}/status")
    fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
    assert fields["Uid"].split()[1] != "0"
    assert int(fields["CapEff"].strip(), 16) == 0
    assert fields["NoNewPrivs"].strip() == "1"
    machine.succeed(f"{podman} exec homelab-maintainerr sh -c 'echo fixture > /opt/data/restart-fixture'")
    machine.succeed("systemctl restart podman-homelab-maintainerr.service")
    machine.wait_until_succeeds("curl -fsS -u viewer:test http://127.0.0.1:6246/api/health/ready >/dev/null", timeout=timedelta(minutes=3))
    machine.succeed(f"{podman} exec homelab-maintainerr grep -q fixture /opt/data/restart-fixture")
  '';
}
