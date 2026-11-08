{ self, ... }: {
  perSystem =
    { pkgs, system, ... }:
    let
      mkdocs = pkgs.python3.withPackages (python: [ python.mkdocs ]);
      site = pkgs.runCommand "nix-homelab-documentation-site" { nativeBuildInputs = [ mkdocs ]; } (
        (import ../lib/render-text.nix) ./scripts/nix-homelab-documentation-site.sh {
          site_mkdocs_yml = ../site/mkdocs.yml;
          site_rewrite_source_links_py = ../site/rewrite_source_links.py;
          rEADME_md = ../README.md;
          sECURITY_md = ../SECURITY.md;
          cONTRIBUTING_md = ../CONTRIBUTING.md;
          docs = ../docs;
          examples = ../examples;
          self_packages_system_options_markdown = self.packages.${system}.options-markdown;
          self_packages_system_support_matrix = self.packages.${system}.support-matrix;
        }
      );
    in
    {
      packages.documentation-site = site;
      checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") { documentation-site = site; };
      devShells.docs = pkgs.mkShellNoCC { packages = [ mkdocs ]; };
    };
}
