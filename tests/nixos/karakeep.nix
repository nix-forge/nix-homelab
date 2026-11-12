{ homelabModule, ... }: {
  name = "homelab-karakeep-runtime";

  nodes.machine =
    { pkgs, ... }:
    let
      webServer = pkgs.writers.writePython3 "karakeep-test-web.py" {
        flakeIgnore = [
          "E501"
          "W503"
        ];
      } (builtins.readFile ./scripts/karakeep_fixture_server.py);
      web = pkgs.writeShellScript "karakeep-test-web" (
        (import ../../lib/render-text.nix) ./scripts/karakeep-test-web.sh {
          pkgs_python3 = pkgs.python3;
          inherit webServer;
        }
      );
      workers = pkgs.writeShellScript "karakeep-test-workers" (
        (import ../../lib/render-text.nix) ./scripts/karakeep-test-workers.sh {
          pkgs_coreutils = pkgs.coreutils;
        }
      );
      migrate = pkgs.writeShellScript "karakeep-test-migrate" (
        builtins.readFile ./scripts/karakeep-test-migrate.sh
      );
      package = pkgs.runCommand "karakeep-test-package" { } (
        (import ../../lib/render-text.nix) ./scripts/build-karakeep-fixture-package.sh {
          inherit web;
          inherit workers;
          inherit migrate;
        }
      );
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

  testScript = builtins.readFile ./scripts/karakeep_test.py;
}
