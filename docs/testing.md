# Testing and static checks

Automated tests cover functions in `lib/` through nix-unit. Other automated
checks perform formatting, lint, syntax, type, schema, documentation and security
analysis. Configuration invariants belong in the owning module's `assertions`
when they reject invalid settings. Project-owned behavioral, configuration
snapshot, VM and fuzz suites are not part of this policy.

```sh
nix develop
just test
just lint
just check
nix build --no-link .#checks.x86_64-linux.lib-tests
```

`just test` runs `nix-unit --flake '.#libTests'`. The suite in
[`lib/tests/default.nix`](../lib/tests/default.nix) exercises strict template
replacement and systemd argument escaping, including rejected renderer inputs.
Use named `expr`/`expected` cases and `expectedError` for intentional failures.
The runner reports failures and returns a failing status; no custom assertion
wrapper is needed. New files must be visible to Nix's Git source filter, for
example with `git add -N <path>` before evaluation.

`just check` evaluates the flake and runs repository hooks. `just lint` runs
hooks, and `nix flake check` builds all retained native checks. Their definitions
live in [`flake/dev/checks.nix`](../flake/dev/checks.nix), the formatter and hook
modules. The development shell supplies the pinned runner and analysis tools.
Keep upstream package test defaults and production safety checks unchanged.

CI uses pinned nix-forge actions to discover lockfiles and execute the retained
checks on x86_64-linux and aarch64-linux. There is one check inventory for local,
pull-request and scheduled execution. No VM or separate runtime fleet is selected.
The Pages workflow builds documentation separately. A declared workflow is not
evidence that a hosted run passed.

Static checks and library tests do not establish application startup, VPN leak
protection, provider compatibility, hardware behavior or successful restoration.
Module assertions validate declarations, not running services. Record any manual
build, activation, recovery or hardware evidence against its exact source and
platform; do not describe unrun checks as successful.
