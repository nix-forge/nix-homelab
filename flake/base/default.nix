{ inputs, ... }: {
  flake.nixosModules.default = {
    imports = [
      inputs.vpn-confinement.nixosModules.default
      ../../modules
    ];
  };
}
