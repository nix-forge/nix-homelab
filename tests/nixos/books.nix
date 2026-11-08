{ homelabModule }: {
  name = "homelab-komga-reader";
  nodes.machine = { pkgs, ... }: {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    virtualisation = {
      memorySize = 3072;
      cores = 2;
    };
    homelab.optional.apps.komga.enable = true;
    services.komga.settings.server.port = 25600;
    environment.systemPackages = [ (pkgs.python3.withPackages (p: [ p.pillow ])) ];
    environment.etc."books_runtime.py".source = ../fixtures/books_runtime.py;
  };
  testScript = builtins.readFile ./scripts/books_test.py;
}
