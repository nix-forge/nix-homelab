# Testing

Use the pinned development shell. On a desktop with `workstation-task`, prefix
heavy commands with that runner to share its build budget. CI runs every
declared native check with bounded jobs; production host activation is separate.

| Layer                | Evidence                                                                                      | Limit                                              |
| -------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Formatter and hooks  | Nix, shell, YAML/Actions and documentation checks; credential scanning                        | No runtime behavior                                |
| Configuration checks | Every supported application, all-disabled import, core profile, extras and security contracts | Evaluation does not build the application          |
| Media VM             | HTTP startup, hardlinks across users, private permissions, read-only player view and restarts | Disposable state, no real providers or GPU         |
| Missing-storage VM   | Refuse fallback writes when the required disk is absent, then recover after mount             | Does not simulate physical disk failure            |
| VPN VM               | Real local WireGuard traffic, host UI, DNS policy, LAN rejection and tunnel failure           | No commercial VPN availability or throughput claim |

```sh
just format
just check
just test
```

The checks are registered in `flake/dev/checks.nix`. Linux ARM and x86_64 both
receive configuration checks. Runtime VMs are registered on x86_64-linux only.
Run a focused check with `nix build --no-link .#checks.x86_64-linux.<name>`. The
local runner evaluates or builds each check in a separate Nix process so large
system evaluations release memory between checks. `just check` evaluates both
Linux architectures; `just test` builds checks for the current machine. NixOS VM
outputs contain logs; failed derivations can be inspected with `nix log`.

CI uses the same nix-forge shared action release as the comparison projects,
pinned by full commit. It checks discovered lockfiles, repository hooks,
workflow policy and Linux checks. Actions receive read permissions except the
guarded queue completion callback. No shared action receives deployment secrets.

Before reporting completion, record which commands passed and which remain
unrun. First deployment must verify real Mullvad routing, application
credentials, indexer/provider connectivity, a restore, hardware acceleration if
selected and idle/load resource use. A green disposable VM is not proof of
production recovery.
