{ config, lib }:
let
  names = lib.optionals (config.homelab.integration.enable or false) (
    builtins.attrNames (config.homelab.integration.services or { })
  );
  entries = lib.genAttrs' names (
    name:
    let
      unitName = "homelab-integrate-${name}";
    in
    lib.nameValuePair "integration-${name}" {
      paths = [ "/var/lib/${unitName}" ];
      units = [
        "${unitName}.service"
        "${unitName}.timer"
      ];
    }
  );
in
{
  inherit entries;
  units = lib.concatMap (entry: entry.units) (lib.attrValues entries);
}
