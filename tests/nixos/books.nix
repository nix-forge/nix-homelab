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
    environment.etc."books-runtime.py".source = ../fixtures/books-runtime.py;
  };
  testScript = ''
    from datetime import timedelta

    start_all()
    machine.wait_for_unit("komga.service")
    machine.wait_for_open_port(25600)
    machine.succeed("python /etc/books-runtime.py seed")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:25600/api/v1/claim")
    machine.succeed("python /etc/books-runtime.py setup", timeout=timedelta(seconds=180))
    # Exercise the actual service mount namespace, not only Unix mode bits.
    machine.succeed("nsenter --target $(systemctl show -p MainPID --value komga) --mount test -r '/srv/media/library/books/Public series/Public book.cbz'")
    machine.fail("nsenter --target $(systemctl show -p MainPID --value komga) --mount touch /srv/media/library/books/forbidden")
    machine.succeed("systemctl restart komga")
    machine.wait_for_open_port(25600)
    machine.wait_until_succeeds("python /etc/books-runtime.py verify", timeout=timedelta(seconds=90))
  '';
}
