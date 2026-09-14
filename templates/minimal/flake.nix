{
  description = "Minimal nix-homelab host";

  inputs = {
    nix-homelab.url = "github:nix-forge/nix-homelab";
    nixpkgs.follows = "nix-homelab/nixpkgs";
  };

  outputs = { nixpkgs, nix-homelab, ... }: {
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-homelab.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
