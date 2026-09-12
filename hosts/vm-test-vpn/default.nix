{ modulesPath, ... }: {
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
  networking.hostName = "homelab-demo";
  system.stateVersion = "26.05";
  homelab.apps.jellyfin.enable = true;
  services.getty.autologinUser = "root";
  networking.firewall.allowedTCPPorts = [ 8096 ];
  virtualisation = {
    graphics = false;
    memorySize = 2048;
    diskSize = 8192;
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8096;
        guest.port = 8096;
      }
    ];
    cores = 2;
  };
  # A local disposable VM; no user credentials or provider profile are included.
}
