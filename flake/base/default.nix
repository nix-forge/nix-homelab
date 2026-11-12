{ inputs, ... }: {
  # Device integrations can be used with a host-specific Nixpkgs pin without
  # importing the media catalog and its unrelated service options.
  flake.nixosModules.iot = ../../modules/iot;
  flake.nixosModules.lanHttps = ../../modules/operations/lan-https.nix;
  flake.nixosModules.default = { lib, pkgs, ... }: {
    services.bookorbit.package =
      lib.mkDefault
        (import inputs.nixpkgs-apps { system = pkgs.stdenv.hostPlatform.system; }).bookorbit;
    imports = [
      inputs.vpn-confinement.nixosModules.default
      ../../modules
    ];
  };
}
