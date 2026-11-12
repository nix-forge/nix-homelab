{
  description = "Composable NixOS media and homelab services with VPN confinement";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Use maintained application recipes without changing the system package set.
    nixpkgs-apps = {
      url = "github:NixOS/nixpkgs/b3cff76391a4867236cc135b69a928d873b9f6d0";
      flake = false;
    };
    nixpkgs-personal = {
      url = "github:nix-forge/nixpkgs-personal";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default-linux";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    vpn-confinement = {
      url = "github:nix-forge/vpn-confinement";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      # Documentation and support metadata run natively on the selected builder.
      flake.lib.packagesFor = platform: inputs.self.packages.${platform.buildSystem};
      imports = [
        ./flake/build-platform.nix
        ./flake
      ];
    };
}
