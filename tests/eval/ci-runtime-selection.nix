{ lib }:
let
  declaredChecks = {
    x86_64-linux = {
      autobrr = "native-autobrr-vm";
      pressure = "native-pressure-vm";
      private-archives = "full-validation-only-vm";
      configuration-autobrr = "native-autobrr-configuration";
    };
    aarch64-linux = {
      configuration-autobrr = "native-autobrr-configuration";
      storage-missing = "native-arm-storage-vm";
    };
  };
  selected =
    (import ../../flake/ci.nix {
      inputs.nixpkgs.lib = lib;
      self.checks = declaredChecks;
    }).flake.ciChecks;
in
{
  autobrrRequiredOnX86 = selected.x86_64-linux.autobrr == declaredChecks.x86_64-linux.autobrr;
  existingRuntimeGatePreserved =
    selected.x86_64-linux.pressure == declaredChecks.x86_64-linux.pressure;
  fullOnlyRuntimeRemainsSeparate = !(selected.x86_64-linux ? private-archives);
  armConfigurationPreserved =
    selected.aarch64-linux.configuration-autobrr == declaredChecks.aarch64-linux.configuration-autobrr;
  unavailableArmRuntimeNotInvented = !(selected.aarch64-linux ? autobrr);
}
