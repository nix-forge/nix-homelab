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
          "autobrr_runtime.py".source = ../fixtures/autobrr_runtime.py;
        };
      };
    };
  testScript = builtins.readFile ./scripts/autobrr_test.py;
}
