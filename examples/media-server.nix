# Import after nix-homelab.nixosModules.default. Replace public provider values.
# Runtime secrets are supplied by the consuming host, see nix-seal.nix.
{
  homelab = {
    profiles = {
      media.enable = true;
      desktop.enable = true;
    };
    storage = {
      rootDir = "/mnt/homelab/media";
      requiredMounts = [ "/mnt/homelab" ];
    };
    vpn = {
      enable = true;
      interface = {
        addressIPv4 = "10.64.0.2";
        privateKeyFile = "/run/nix-seal/system/secrets/homelab-vpn-private-key";
        dns = [ "10.64.0.1" ];
      };
      peer = {
        # Documentation values, replace from the user's Mullvad profile.
        publicKey = "82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4=";
        endpointHost = "192.0.2.1";
      };
    };
  };
  # Declare the existing media filesystem in the host configuration. This example
  # intentionally cannot provision, repartition or format a disk.
}
