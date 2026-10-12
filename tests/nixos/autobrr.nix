{ homelabModule }: {
  name = "homelab-autobrr";
  nodes.machine =
    {
      pkgs,
      lib,
      options,
      ...
    }:
    {
      imports = [ homelabModule ];
      system.stateVersion = "26.05";
      homelab.optional.apps.autobrr.enable = true;
      services.autobrr = {
        settings.checkForUpdates = false;
      }
      // lib.optionalAttrs (
        options.services.autobrr ? secretFile && (options.services.autobrr.secretFile.visible or true)
      ) { secretFile = "/etc/autobrr-session"; };
      environment = {
        systemPackages = [
          pkgs.python3
          pkgs.curl
        ];
        etc = {
          "autobrr-session".text = "disposable-vm-session-secret-0123456789";
          "common.py".source = ../../scripts/integration/common.py;
          "autobrr-adapter.py".source = ../../scripts/integration/autobrr.py;
          "autobrr-runtime.py".source = ../fixtures/autobrr-runtime.py;
        };
      };
    };
  testScript = ''
    machine.start()
    machine.wait_for_unit("autobrr.service")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:7474/api/healthz/readiness")
    machine.succeed("python /etc/autobrr-runtime.py")
    machine.succeed("systemctl restart autobrr")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:7474/api/healthz/readiness")
    machine.succeed("python /etc/autobrr-runtime.py verify-persistence")
  '';
}
