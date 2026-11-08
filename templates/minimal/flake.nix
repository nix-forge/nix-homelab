{
  description = "Minimal nix-homelab host";

  inputs = {
    nix-homelab.url = "github:nix-forge/nix-homelab";
    # Maintain Nixpkgs directly so updating homelab cannot downgrade this pin.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-homelab.inputs.nixpkgs.follows = "nixpkgs";
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
