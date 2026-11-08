{ inputs, ... }: {
  perSystem = { pkgs, config, ... }: {
    devShells.default = pkgs.buildPackages.mkShellNoCC {
      inherit (config.pre-commit) shellHook;
      packages =
        config.pre-commit.settings.enabledPackages
        ++ [ config.pre-commit.settings.package ]
        ++ (with pkgs.buildPackages; [
          bashInteractive
          direnv
          editorconfig-checker
          gitleaks
          just
          nh
          nixd
          nixf-diagnose
          nodejs_24
          pinact
          prek
          (python3.withPackages (
            ps: with ps; [
              inputs.nixpkgs-personal.packages.${pkgs.buildPackages.stdenv.hostPlatform.system}.notification-process
              fastapi
              httpx
              uvicorn
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
