{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.optional.maintainerr;
  enabled = config.homelab.optional.apps.maintainerr.enable;
  command = pkgs.writeShellApplication {
    name = "homelab-maintainerr-policy";
    runtimeInputs = [ pkgs.python3 ];
    text = (import ../../../lib/render-text.nix) ./scripts/homelab-maintainerr-policy.sh {
      scripts_media_maintainerr_policy_py = ../../../scripts/media/maintainerr_policy.py;
    };
  };
in
{
  options.homelab.optional.maintainerr.policyFile = lib.mkOption {
    type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9_./-]+");
    default = null;
    description = "Runtime JSON policy file. Apply only by explicitly starting homelab-maintainerr-policy.service; never put secrets in the Nix store.";
  };
  config = lib.mkIf (enabled && cfg.policyFile != null) {
    assertions = [
      {
        assertion = !lib.hasPrefix "/nix/store/" cfg.policyFile;
        message = "Maintainerr policyFile must be outside the Nix store.";
      }
    ];
    environment.systemPackages = [ command ];
    systemd.services.homelab-maintainerr-policy = {
      description = "Explicit Maintainerr safe-policy reconciliation";
      after = [ "homelab-maintainerr.service" ];
      requires = [ "homelab-maintainerr.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "homelab-maintainerr";
        Group = "homelab-maintainerr";
        ExecStart = "${lib.getExe command} apply --config ${cfg.policyFile} --ledger /var/lib/homelab-maintainerr/data/policy-ledger.json --url http://127.0.0.1:${toString cfg.backendPort}";
        AmbientCapabilities = "";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/homelab-maintainerr/data" ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };
  };
}
