{ homelabModule }: {
  name = "homelab-autobrr";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    homelab.optional.apps.autobrr.enable = true;
    services.autobrr = {
      secretFile = "/etc/autobrr-session";
      settings.checkForUpdates = false;
    };
    environment = {
      systemPackages = [
        pkgs.python3
        pkgs.curl
      ];
      etc = {
        "autobrr-session".text = "disposable-vm-session-secret-0123456789";
        "autobrr-adapter.py".source = ../../scripts/integration/autobrr.py;
        "autobrr-runtime.py".source = ../fixtures/autobrr-runtime.py;
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("autobrr.service")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:7474/api/healthz/readiness")
    machine.succeed("test $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:7474/api/download_clients) = 403")
    machine.succeed("test $(curl -s -H X-API-Token:invalid -o /dev/null -w '%{http_code}' http://127.0.0.1:7474/api/download_clients) = 401")
    machine.succeed("python /etc/autobrr-runtime.py")
    machine.succeed("systemctl restart autobrr")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:7474/api/healthz/readiness")
    machine.succeed("python /etc/autobrr-runtime.py verify-persistence")
  '';
}
