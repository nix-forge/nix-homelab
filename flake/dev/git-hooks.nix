{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    let
      checkPython = pkgs.buildPackages.python3.withPackages (
        ps:
        with ps;
        [
          inputs.nixpkgs-personal.packages.${pkgs.buildPackages.stdenv.hostPlatform.system}.notification-process
          argon2-cffi
          fastapi
          httpx
          uvicorn
          pillow
          pytest
          pyyaml
          psycopg2
        ]
        ++ lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isLinux [
          # Module conversion enables metadata checks that the application's
          # placeholder project version does not satisfy.
          (ps.toPythonModule (
            pkgs.buildPackages.nixos-test-driver.overridePythonAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ ps.pyprojectVersionPatchHook ];
            })
          ))
        ]
      );
      pythonCompile = pkgs.buildPackages.writeShellApplication {
        name = "homelab-python-compile";
        text = (import ../../lib/render-text.nix) ./scripts/homelab-python-compile.sh {
          lib_getExe_pkgs_coreutils_mktemp = lib.getExe' pkgs.buildPackages.coreutils "mktemp";
          lib_getExe_pkgs_coreutils_rm = lib.getExe' pkgs.buildPackages.coreutils "rm";
          lib_getExe_pkgs_python3 = lib.getExe pkgs.buildPackages.python3;
        };
      };
    in
    {
      # Colored prek execution opens a PTY, unavailable in the Nix sandbox.
      # Keep interactive output unchanged and disable color only for the check.
      checks.pre-commit = lib.mkForce (
        config.pre-commit.settings.run.overrideAttrs (_: {
          PREK_COLOR = "never";
        })
      );
      pre-commit = {
        check.enable = true;
        settings = {
          package = pkgs.buildPackages.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              require_serial = true;
              pass_filenames = true;
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
            };
            pinact = {
              enable = true;
              name = "pinact";
              entry = "${lib.getExe pkgs.buildPackages.pinact} run --fix=false --no-api";
              language = "system";
              files = "^\\.github/workflows/.*\\.ya?ml$";
              after = [ "treefmt" ];
            };
            ruff = {
              enable = true;
              entry = "${lib.getExe pkgs.buildPackages.ruff} check --no-fix --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff-format = {
              enable = true;
              name = "ruff format";
              entry = "${lib.getExe pkgs.buildPackages.ruff} format --check --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff" ];
            };
            ty = {
              enable = true;
              name = "ty";
              entry = "${lib.getExe pkgs.buildPackages.ty} check --project . --python ${lib.getExe checkPython}";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff-format" ];
            };
            python-compile = {
              enable = true;
              name = "python compileall";
              entry = lib.getExe pythonCompile;
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ty" ];
            };
            phpstan = {
              enable = true;
              package = pkgs.buildPackages.phpstan;
              name = "PHP semantic analysis";
              entry = lib.getExe (import ./php-tools.nix { pkgs = pkgs.buildPackages; });
              language = "system";
              files = "(\\.php$|^phpstan\\.neon$|^flake/dev/php-tools\\.nix$)";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            end-of-file-fixer = {
              enable = true;
              after = [ "treefmt" ];
            };
            trim-trailing-whitespace = {
              enable = true;
              after = [ "treefmt" ];
            };
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
              after = [ "treefmt" ];
            };

            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;

            detect-private-keys.enable = true;
            gitleaks = {
              enable = true;
              name = "Gitleaks";
              entry = "${lib.getExe pkgs.buildPackages.gitleaks} git --pre-commit --staged --redact --no-banner";
              # The complete entry owns its arguments; do not append hook defaults.
              args = [ ];
              language = "system";
              pass_filenames = false;
              always_run = true;
            };

            check-case-conflicts.enable = true;
            check-added-large-files.enable = true;
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable.enable = true;
            fix-byte-order-marker.enable = true;
            editorconfig-checker.enable = true;
            typos = {
              enable = true;
              entry = "${lib.getExe pkgs.buildPackages.typos} --config .typos.toml --force-exclude";
            };
            zizmor = {
              enable = true;
              args = [ "--persona=pedantic" ];
            };

            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;

            flake-checker.enable = true;
            # A monolithic flake check retains all configurations in one
            # evaluator. Release that memory between declared checks.
            nix-flake-check = {
              enable = true;
              name = "evaluate checks (separate Nix processes)";
              entry = "${lib.getExe pkgs.buildPackages.bash} scripts/checks.sh evaluate";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
      };
    };

}
