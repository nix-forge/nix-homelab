# Compatibility policy

`nix-homelab` follows one locked nixpkgs revision at a time. The flake lock is
the tested application-version set. A consuming host should pin this flake and
review lock updates before deployment.

## Support levels

The generated service matrix distinguishes evaluation from runtime evidence.
An application is not runtime-tested merely because its NixOS configuration
evaluates. An integration test names the exact checked-in test that exercises
the application or its authenticated interface. ARM remains evaluation-only
until the named VM checks run on aarch64 hardware in CI.

Provider-specific Arr fields use each running application's schema. The typed
resource envelope covers supported endpoints and stable identity. Values under
`extraResources` are an unsupported compatibility escape hatch. They retain
runtime-secret validation but may stop working after an application update.
Adapter `settings` also has a typed, per-kind supported surface. Raw upstream
fields belong in `extraSettings` and have the same unsupported status.

## Updates and breakage

Patch releases must preserve option names and persistent-state locations. Minor
releases may add options and integrations. Before 1.0, a minor release may make
a necessary breaking correction when its changelog supplies the evaluation or
data migration.

A release that changes a database version, state path, service identity, or
reconciliation ownership must include a recovery procedure and a stateful
upgrade test. `system.stateVersion` is not changed as part of a package update.

The project does not promise compatibility with a moving nixpkgs branch, live
third-party provider interfaces, unlisted application overrides, or raw
`extraResources` fields.
