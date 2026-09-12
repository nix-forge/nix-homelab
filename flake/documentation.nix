{ inputs, self, ... }: {
  perSystem =
    {
      pkgs,
      system,
      lib,
      ...
    }:
    let
      evaluated = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ self.nixosModules.default ];
      };
      documentation = pkgs.nixosOptionsDoc {
        options = { inherit (evaluated.options) homelab; };
        warningsAreErrors = true;
        transformOptions =
          option:
          option
          // {
            declarations = map (path: lib.removePrefix "${self.outPath}/" (toString path)) option.declarations;
          };
      };
    in
    {
      packages.options = documentation.optionsJSON;
      checks.options = documentation.optionsJSON;
    };
}
