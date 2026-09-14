{
  perSystem = { pkgs, config, ... }: {
    devShells.default = pkgs.mkShellNoCC {
      inherit (config.pre-commit) shellHook;
      packages =
        config.pre-commit.settings.enabledPackages
        ++ [ config.pre-commit.settings.package ]
        ++ (with pkgs; [
          bashInteractive
          direnv
          editorconfig-checker
          gitleaks
          just
          nh
          nixd
          nixf-diagnose
          pinact
          prek
          (python3.withPackages (
            ps: with ps; [
              pillow
              pytest
              pyyaml
            ]
          ))
          rumdl
          taplo
          treefmt
          ty
          typos
          yamllint
          zizmor
        ]);
    };
  };
}
