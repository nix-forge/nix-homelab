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

## VPN leak regression checks

`vpn-namespace` starts qBittorrent, SABnzbd, NZBGet, Prowlarr and Tinyproxy with
VPN confinement explicitly enabled. The optional clients and Prowlarr retain
their normal defaults outside this fixture. Each running process must occupy the
VPN network namespace, have no effective, permitted, bounding or ambient
capabilities, and use the tunnel resolver. The test also checks that host
resolver sockets are inaccessible from each service's mount namespace.

The test captures all outbound IPv4 and IPv6 packets on the namespace's host
link while attempting direct TCP, UDP, ICMP, DNS over UDP and TCP, TCP ports 443
and 853, QUIC-like UDP traffic, and multicast discovery. No host UI requests run
during these captures because their replies are intentionally permitted. A
successful UDP send is only a stimulus; an empty capture is the delivery
assertion. A temporary, narrowly scoped firewall exception must produce a
visible UDP packet before the negative checks run. Captures must report zero
kernel drops and are retained in the VM test output.

The same probes run with the tunnel healthy, the remote peer unavailable, an
injected cleartext default route after tunnel loss, and the tunnel restored. A
connected UDP socket keeps sending across the tunnel and route changes, with
capture active during the transition and successful replies required after
recovery. Approved resolver traffic is also tested against the injected fallback
route. Stopping WireGuard must stop every consumer. Missing runtime keys must
prevent consumer startup, and restoring the key must restore tunnel
connectivity.

These tests use synthetic traffic from each service's network and mount
namespaces. They do not exercise every application's peer, tracker, indexer or
provider protocol. They cover the default IPv6-disabled namespace; they do not
establish runtime safety for configurations that enable tunnel IPv6. The peer
runs on the same disposable VM, so this is not an observation of a production
WAN interface. Boot and firewall-update races, production routing changes, VPN
provider behavior and a compromised host remain outside this test's guarantees.
An ISP can still observe the VPN endpoint and traffic timing and volume. Host
services that have not opted into confinement retain ordinary networking.
