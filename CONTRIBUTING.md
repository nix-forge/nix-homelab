# Contributing

This flake provides reusable NixOS defaults. Host configuration owns disks,
hardware drivers, access rules, secret catalogs and backup destinations. Keep
those choices out of the default module. Read [the glossary](CONTEXT.md) when
changing terminology.

## Module conventions

Importing `nixosModules.default` enables no applications. New applications must
be opt-in. Prefer native nixpkgs modules and package overrides through their
existing options. Add a homelab option only for shared media policy or a real
variation between deployments. Keep application-specific settings under
`services.<name>` so upstream options remain available.

Keep credentials in user-provided nix-seal files. Decrypted values must not
enter Nix expressions, the store, logs or fixtures. Runtime tests use public
disposable fixture keys. Review configuration generators for persistence across
restarts and changes made through application UIs.

Keep every network exception narrow. A shared namespace is one network trust
domain. Changes to VPN wiring require runtime success and failure tests.
Preserve upstream systemd hardening; explain exceptions and test the application
that requires them. JIT runtimes and GPU access need application-specific
choices.

Keep media paths consistent between clients and managers. Test hardlink imports,
permissions and missing mounts. Changing a database version needs a restore
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

Run focused tests first, then formatting, hooks, configuration checks and the
relevant VM tests. VM tests currently execute on x86_64-linux. ARM checks
validate configuration until native runtime evidence is available. Keep tests
tied to observable behavior and failure modes, not copies of implementation
text.

Before a review, capture `git diff HEAD --binary` and inspect untracked files.
Use an exact base and the user request or linked issue as requirements. Report
standards findings separately from unmet requirements. Include remaining runtime
or hardware checks. See [security reporting](SECURITY.md) for vulnerabilities.
