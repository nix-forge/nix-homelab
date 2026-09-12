{ inputs, self, ... }: {
  flake.nixosConfigurations.vm-test-vpn = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.default
      ../../hosts/vm-test-vpn
    ];
  };
}
