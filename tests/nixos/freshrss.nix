{ homelabModule, ... }: {
  name = "homelab-freshrss-runtime";
  nodes.machine = { pkgs, config, ... }: {
    imports = [ homelabModule ];
    homelab = {
      optional.apps.freshrss.enable = true;
      optional.freshrss = {
        username = "ignored-static-name";
        usernameFile = "/etc/news-test-username";
        passwordFile = "/etc/news-test-password";
        initialFeeds = [
          {
            url = "http://127.0.0.1:18999/feed.xml";
            category = "Reporting";
          }
        ];
      };
      operations.enable = true;
    };
    environment.etc."news-test-username".text = "runtime-reader";
    environment.etc."news-test-password".text = "vm-fixture-password";
    environment.etc."verify-freshrss-login.php".source = ./scripts/verify-freshrss-login.php;
    environment.etc."fresh-package".text = toString config.services.freshrss.package;
    environment.systemPackages = [
      pkgs.curl
      pkgs.php
    ];
    virtualisation = {
      cores = 2;
      memorySize = 2048;
    };
  };

  testScript = builtins.readFile ./scripts/freshrss_test.py;
}
