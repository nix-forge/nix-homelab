{ homelabModule }: {
  name = "homelab-audiomuse-ai-runtime";
  nodes.machine =
    { pkgs, ... }:
    let
      web = pkgs.writeShellApplication {
        name = "audiomuse-ai-web";
        runtimeInputs = [ pkgs.python3 ];
        text = (import ../../lib/render-text.nix) ./scripts/audiomuse-ai-web.sh {
          pkgs_writeText_audiomuse_test_server_py_builtins_readFile_sc =
            pkgs.writers.writePython3 "audiomuse_test_server.py"
              {
                flakeIgnore = [
                  "E501"
                  "W503"
                ];
              }
              (builtins.readFile ./scripts/audiomuse_test_server.py);
        };
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

  testScript = builtins.readFile ./scripts/audiomuse_ai_test.py;
}
