{ inputs, ... }: {
  # Device integrations can be used with a host-specific Nixpkgs pin without
  # importing the media catalog and its unrelated service options.
  flake.nixosModules.iot = ../../modules/iot;
  flake.nixosModules.lanHttps = ../../modules/operations/lan-https.nix;
  flake.nixosModules.default = { lib, ... }: {
    nixpkgs.overlays = lib.mkAfter [
      (_final: prev: {
        bookorbit = (import inputs.nixpkgs-apps { system = prev.stdenv.hostPlatform.system; }).bookorbit;
      })
    ];
    imports = [
      inputs.vpn-confinement.nixosModules.default
      ../../modules
    ];
  };
}
