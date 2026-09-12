{
  perSystem = { pkgs, config, ... }: {
    devShells.default = pkgs.mkShellNoCC {
      inherit (config.pre-commit) shellHook;
      packages = with pkgs; [
        nh
        just
        prek
        gitleaks

        bashInteractive
      ];
    };
  };
}
