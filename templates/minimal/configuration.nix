{ modulesPath, ... }: {
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  networking.hostName = "homelab";
  system.stateVersion = "26.05";

  homelab = {
    profiles.media.enable = true;
    storage = {
      rootDir = "/srv/media";
      requiredMounts = [ "/srv/media" ];
    };
    apps.qbittorrent.vpn.enable = false;
  };

  # Add runtime credentials, a real media mount, VPN policy, integrations,
  # operations and the readiness gate before using this with production data.
}
