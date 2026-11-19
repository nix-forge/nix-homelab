_: {
  perSystem =
    { pkgs, lib, ... }:
    let
      catalog = import ../modules/catalog.nix;
      records =
        lib.concatMap
          (
            class:
            map (name: {
              inherit class name;
              integrationAdapter = catalog.${class}.${name}.integration or null;
            }) (builtins.attrNames catalog.${class})
          )
          [
            "core"
            "optional"
          ];
      markdown = ''
        # Service catalog

        Generated from `modules/catalog.nix`. Entries describe available modules
        and integration adapters; they do not claim runtime or recovery coverage.

        | Service | Class | Integration adapter |
        | --- | --- | --- |
        ${lib.concatMapStringsSep "\n" (
          item:
          "| ${item.name} | ${item.class} | ${
            if item.integrationAdapter == null then "none" else item.integrationAdapter
          } |"
        ) records}
      '';
    in
    {
      packages.support-matrix = pkgs.writeText "nix-homelab-service-catalog.md" markdown;
      packages.support-matrix-json = pkgs.writeText "nix-homelab-service-catalog.json" (
        builtins.toJSON {
          schemaVersion = 2;
          services = records;
        }
      );
    };
}
