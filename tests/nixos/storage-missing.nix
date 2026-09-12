{ homelabModule }: {
  name = "homelab-storage-missing";
  nodes.machine = {
    imports = [ homelabModule ];
    system.stateVersion = "26.05";
    homelab = {
      apps.nzbget.enable = true;
      apps.navidrome.enable = true;
      storage = {
        rootDir = "/mnt/absent/media";
        requiredMounts = [ "/mnt/absent" ];
      };
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("systemctl is-failed homelab-storage.service")
    machine.fail("systemctl is-active nzbget.service")
    machine.fail("systemctl is-active navidrome.service")
    machine.fail("test -d /mnt/absent/media")
    machine.succeed("mkdir -p /mnt/absent; mount -t tmpfs tmpfs /mnt/absent")
    machine.succeed("systemctl reset-failed homelab-storage nzbget; systemctl start nzbget")
    machine.wait_for_unit("nzbget.service")
    machine.succeed("test -d /mnt/absent/media/downloads/usenet")
  '';
}
