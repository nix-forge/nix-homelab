# Contributing

This flake provides reusable NixOS defaults. Host configuration owns disks,
hardware drivers, access rules, secret catalogs and backup destinations. Keep
those choices out of the default module. Read [the glossary](GLOSSARY.md) when
changing terminology.

## Module conventions

Importing `nixosModules.default` enables no applications. New applications must
be opt-in. Prefer native nixpkgs modules and package overrides through their
existing options. Add a homelab option only for shared media policy or a real
variation between deployments. Keep application-specific settings under
`services.<name>` so upstream options remain available.

Keep credentials in user-provided nix-seal files. Decrypted values must not
enter Nix expressions, the store, logs or fixtures. Review configuration generators for persistence across
restarts and changes made through application UIs.

Keep every network exception narrow. A shared namespace is one network trust
domain. Preserve upstream systemd hardening and explain application-specific exceptions. JIT runtimes and GPU access need application-specific
choices.

Keep media paths consistent between clients and managers. Preserve permission
and missing-mount safety checks. Changing a database version needs a restore
plan; `system.stateVersion` is a data-compatibility setting, not an update knob.

For generated programs, use `writeShellApplication` with `runtimeInputs` for
installed Bash commands and `writers.writePython3Bin` for a single Python
executable. Keep `writeShellScript` for module-owned snippets whose dependencies
use explicit store paths, and `writeShellScriptBin` for small test doubles. Use
`replaceVars` or `replaceVarsWith` for complete `@name@` file templates,
`builtins.replaceStrings` for small evaluation-time strings, and
`substituteInPlace --replace-fail` only while patching unpacked package source.

## Validation

Use `nix develop` for pinned tools and `just --list` for commands. Follow
[the testing guide](docs/testing.md). New Nix source must be included in the Git
source before evaluation, for example with `git add -N <path>`.

Pull requests and merge groups run static formatting, lint, syntax, type,
schema, documentation and security checks, plus nix-unit tests for functions in
`lib/`. Keep library cases focused on the public function contract, with named
expected values and explicit expected errors. Do not add module snapshots,
behavioral scripts, VM tests or fuzz suites.

Put assertions in the owning module only when they reject invalid settings.
Preserve production input validation and runtime safety checks, and retain
upstream package test defaults. Static checks and library tests cannot establish
application runtime behavior or successful recovery. State manual build,
activation and restore evidence separately. Security and dependency findings
follow the [dependency-management policy](docs/dependency-management.md).

Before a review, capture `git diff HEAD --binary` and inspect untracked files.
Use an exact base and the user request or linked issue as requirements. Report
standards findings separately from unmet requirements. Include remaining runtime
or hardware checks. See [security reporting](SECURITY.md) for vulnerabilities.

## Source filenames

Use lowercase snake_case for Python sources, including executable helpers and
test fixtures. Use lowercase kebab-case for shell helpers and ordinary assets.
Name scripts by their behavior or package phase, such as `post-install.sh`,
rather than extraction ordinals, line numbers or interpolation fragments. Keep
native manifests, language entry points, public package/module identities, real
version numbers and discovery-test filenames stable. An installed command can
keep its hyphenated name when its Python source uses underscores.

Update callers, imports, fixture loaders, source filters and per-file lint
selections when moving a source. Check derived filenames as well as literal
paths, and preserve file permissions.
