_: {
  perSystem =
    { pkgs, lib, ... }:
    let
      catalog = import ../modules/catalog.nix;
      evidence = import ../support/evidence.nix;
      classes = [
        "core"
        "optional"
      ];
      catalogNames = class: builtins.attrNames catalog.${class};
      evidenceNames = class: builtins.attrNames evidence.${class};
      complete = lib.all (class: catalogNames class == evidenceNames class) classes;
      records = lib.concatMap (
        class:
        map (
          name:
          evidence.${class}.${name}
          // {
            inherit class name;
            integrationAdapter = catalog.${class}.${name}.integration or null;
          }
        ) (catalogNames class)
      ) classes;
      showTests = tests: if tests == [ ] then "none" else lib.concatStringsSep ", " tests;
      markdown = ''
        # Service support and evidence

        This file is generated from `modules/catalog.nix` and `support/evidence.nix`.
        A test name records the checked-in evidence source. It does not claim a
        hosted run, real provider, real hardware, or production restore.

        | Service | Class | Tier | Integration | Runtime | Workflow | Recovery | VPN | aarch64 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        ${lib.concatMapStringsSep "\n" (
          item:
          "| ${item.name} | ${item.class} | ${item.tier} | ${
            if item.integrationAdapter == null then "none" else item.integrationAdapter
          } | ${showTests item.runtimeTests} | ${showTests item.workflowTests} | ${showTests item.recoveryTests} | ${showTests item.vpnTests} | ${
            if item.aarch64RuntimeTests == [ ] then
              "evaluation only"
            else
              "${showTests item.aarch64RuntimeTests} declared"
          } |"
        ) records}
      '';
      json = builtins.toJSON {
        schemaVersion = 1;
        services = records;
      };
    in
    {
      packages.support-matrix = pkgs.writeText "nix-homelab-support-matrix.md" markdown;
      packages.support-matrix-json = pkgs.writeText "nix-homelab-support-matrix.json" json;
      checks.support-matrix =
        assert lib.assertMsg complete "Every catalog service must have exactly one evidence record.";
        pkgs.writeText "nix-homelab-support-matrix-check.json" json;
    };
}
