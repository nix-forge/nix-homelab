{ inputs, ... }: {
  perSystem = { pkgs, lib, ... }: {
    checks = {
      lib-tests = pkgs.runCommand "homelab-lib-tests" { nativeBuildInputs = [ pkgs.nix-unit ]; } ''
        export HOME="$TMPDIR"
        nix-unit --eval-store "$TMPDIR/eval-store" --expr 'import ${../../lib}/tests'
        touch "$out"
      '';
      php-semantic-quality =
        let
          source = lib.fileset.toSource {
            root = ../..;
            fileset = lib.fileset.unions [
              ../../phpstan.neon
              (lib.fileset.fileFilter (file: file.hasExt "php") ../../scripts)
            ];
          };
        in
        pkgs.runCommand "homelab-php-semantic-quality" {
          sourcePath = source;
          nativeBuildInputs = [ (import ./php-tools.nix { inherit pkgs; }) ];
        } (builtins.readFile ./scripts/php-semantic-quality.sh);
      php-quality =
        let
          source = lib.fileset.toSource {
            root = ../..;
            fileset = lib.fileset.unions [
              ../../.php-cs-fixer.dist.php
              (lib.fileset.fileFilter (file: file.hasExt "php") ../../scripts)
            ];
          };
        in
        pkgs.runCommand "homelab-php-quality" {
          nativeBuildInputs = [
            pkgs.php
            pkgs.phpPackages.php-cs-fixer
            pkgs.findutils
          ];
        } ((import ../../lib/render-text.nix) ./scripts/php-quality.sh { inherit source; });
      source-secrets =
        pkgs.runCommand "homelab-source-secrets" { nativeBuildInputs = [ pkgs.gitleaks ]; }
          ''
            gitleaks dir --config ${../../.gitleaks.toml} --redact --no-banner ${inputs.self}
            touch "$out"
          '';
    };
  };
}
