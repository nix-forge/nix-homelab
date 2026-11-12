{ homelabModule }: {
  name = "homelab-actual-runtime";
  nodes = {
    server = { pkgs, ... }: {
      imports = [ homelabModule ];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];
      services.actual.enable = true;
      homelab.operations.enable = true;
    };
    client = { pkgs, ... }: {
      system.stateVersion = "26.05";
      environment.systemPackages = [ pkgs.curl ];
    };
  };
  testScript = builtins.readFile ./scripts/actual_test.py;
}
