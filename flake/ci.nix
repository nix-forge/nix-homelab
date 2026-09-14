{ inputs, self, ... }:
let
  # These NixOS VM tests remain part of `checks` for weekly and explicitly
  # requested full validation. Pull requests use `ciChecks` so routine changes
  # do not rebuild the entire homelab runtime fleet on one hosted runner.
  runtimeChecks = [
    "access"
    "arr-integration"
    "arr-postgresql"
    "audio-runtime"
    "audiomuse-ai"
    "autobrr"
    "books"
    "cross-seed"
    "karakeep"
    "maintainerr"
    "media-runtime"
    "media-workflow"
    "operations"
    "optional-media"
    "pressure"
    "private-archives"
    "quality"
    "storage-missing"
    "usenet-credentials"
    "vpn-namespace"
  ];
  pullRequestRuntimeChecks = [
    "pressure"
    "storage-missing"
    "vpn-namespace"
  ];
in
{
  flake.ciChecks = inputs.nixpkgs.lib.mapAttrs (
    _: checks:
    removeAttrs checks (inputs.nixpkgs.lib.subtractLists runtimeChecks pullRequestRuntimeChecks)
  ) self.checks;
}
