{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    let
      checkPython = pkgs.python3.withPackages (
        ps: with ps; [
          pillow
          pytest
          pyyaml
        ]
      );
      pythonCompile = pkgs.writeShellApplication {
        name = "homelab-python-compile";
        text = ''
          cache="$(${lib.getExe' pkgs.coreutils "mktemp"} -d)"
          trap '${lib.getExe' pkgs.coreutils "rm"} -rf -- "$cache"' EXIT
          PYTHONPYCACHEPREFIX="$cache" ${lib.getExe pkgs.python3} -m compileall -q scripts tests
        '';
      };
    in
    {
      pre-commit = {
        check.enable = true;
        settings = {
          package = pkgs.prek;
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
              entry = "${lib.getExe pkgs.pinact} run --fix=false --no-api";
              language = "system";
              files = "^\\.github/workflows/.*\\.ya?ml$";
              after = [ "treefmt" ];
            };
            ruff = {
              enable = true;
              entry = "${lib.getExe pkgs.ruff} check --no-fix --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff-format = {
              enable = true;
              name = "ruff format";
              entry = "${lib.getExe pkgs.ruff} format --check --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff" ];
            };
            ty = {
              enable = true;
              name = "ty";
              entry = "${lib.getExe pkgs.ty} check --project . --python ${lib.getExe checkPython}";
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
              entry = "${lib.getExe pkgs.gitleaks} git --pre-commit --staged --redact --no-banner";
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
              entry = "${lib.getExe pkgs.typos} --config .typos.toml --force-exclude";
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
              entry = "${lib.getExe pkgs.bash} scripts/checks.sh evaluate";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
      };
    };

}
