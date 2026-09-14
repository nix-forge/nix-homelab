{ self, ... }: {
  perSystem =
    { pkgs, system, ... }:
    let
      mkdocs = pkgs.python3.withPackages (python: [ python.mkdocs ]);
      site = pkgs.runCommand "nix-homelab-documentation-site" { nativeBuildInputs = [ mkdocs ]; } ''
        mkdir -p source/docs/generated source/examples
        cp ${../site/mkdocs.yml} mkdocs.yml
        cp ${../site/rewrite_source_links.py} rewrite_source_links.py
        cp ${../README.md} source/index.md
        cp ${../SECURITY.md} source/SECURITY.md
        cp ${../CONTRIBUTING.md} source/CONTRIBUTING.md
        cp -r ${../docs}/. source/docs/
        cp -r ${../examples}/. source/examples/
        cp ${self.packages.${system}.options-markdown} source/docs/generated/options.md
        cp ${self.packages.${system}.support-matrix} source/docs/generated/support-matrix.md
        mkdocs build --config-file mkdocs.yml --site-dir "$out" --strict
        test -s "$out/index.html"
        test -s "$out/search/search_index.json"
      '';
    in
    {
      packages.documentation-site = site;
      checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") { documentation-site = site; };
      devShells.docs = pkgs.mkShellNoCC { packages = [ mkdocs ]; };
    };
}
