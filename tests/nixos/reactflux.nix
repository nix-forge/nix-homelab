{ homelabModule, ... }:
let
  backend = import ./miniflux.nix { inherit homelabModule; };
in
{
  name = "homelab-reactflux-runtime";
  nodes.machine = { pkgs, ... }: {
    imports = [ backend.nodes.machine ];
    homelab.optional.reactflux.enable = true;
    systemd.services.fixture-unsafe-feed = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${
        pkgs.writers.writePython3 "unsafe_feed.py" {
          flakeIgnore = [
            "E501"
            "W503"
          ];
        } (builtins.readFile ./scripts/unsafe_feed.py)
      }";
    };
  };
  testScript = backend.testScript + (builtins.readFile ./scripts/reactflux_test.py);
}
