# Testing

Use the pinned development shell. On a desktop with `workstation-task`, prefix
heavy commands with that runner to share its build budget. CI runs every
declared native check with bounded jobs; production host activation is separate.

| Layer                | Evidence                                                                                      | Limit                                              |
| -------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Formatter and hooks  | Nix, shell, Python, YAML/Actions and documentation checks; credential scanning                | No runtime behavior                                |
| Configuration checks | Every supported application, all-disabled import, core profile, extras and security contracts | Evaluation does not build the application          |
| Media VM             | HTTP startup, hardlinks across users, private permissions, read-only player view and restarts | Disposable state, no real providers or GPU         |
| Missing-storage VM   | Refuse fallback writes when the required disk is absent, then recover after mount             | Does not simulate physical disk failure            |
| VPN VM               | Real local WireGuard traffic, host UI, DNS policy, LAN rejection and tunnel failure           | No commercial VPN availability or throughput claim |

```sh
just format
just lint
just check
just test
```

The checks are registered in `flake/dev/checks.nix`. Linux ARM and x86_64 both
receive configuration checks. The missing-storage VM is also declared for the
native ARM runner; other runtime VMs remain x86_64-only until their cost and
dependencies are demonstrated on hosted ARM.
Run a focused check with `nix build --no-link .#checks.x86_64-linux.<name>`. The
local runner evaluates or builds each check in a separate Nix process so large
system evaluations release memory between checks. `just check` evaluates both
Linux architectures; `just test` builds checks for the current machine. NixOS VM
outputs contain logs; failed derivations can be inspected with `nix log`.

Every qBittorrent VM imports
[`qbittorrent-offline.nix`](../tests/fixtures/qbittorrent-offline.nix). It
disables DHT, peer exchange and local peer discovery before startup, then checks
the installed configuration after credential merging. API assertions cover
initial startup and restart or restoration. Local download fixtures use explicit
local webseeds and indexers. The setting names follow the
[pinned application's session configuration](https://github.com/qbittorrent/qBittorrent/blob/release-5.2.3/src/base/bittorrent/sessionimpl.cpp).

CI uses the same nix-forge shared action release as the comparison projects,
pinned by full commit. It checks discovered lockfiles, repository hooks,
workflow policy and Linux checks. CodeQL analyzes Python and GitHub Actions on
pull requests, merge groups, main and a weekly schedule. Actions receive read
permissions except SARIF uploads and the guarded queue completion callback. No
shared action receives deployment secrets.

Pull requests, merge groups, and pushes to `main` run `ciChecks`: configuration
checks and the pressure, missing-storage, and VPN runtime tests. Manual runs and
the weekly schedule run the full `checks` output, including the remaining service
VM tests. The shared CI action partitions x86_64 checks across four Linux jobs;
each job builds only its assigned checks. The Pages workflow separately builds
the generated mdBook and deploys only from `main`, with job-scoped permissions
and immutable action pins. A declared schedule or Pages workflow is not evidence
of a hosted success until the repository run has completed.

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

qBittorrent fixtures disable DHT, peer exchange and local peer discovery in the
native configuration before startup. A pre-start assertion checks the generated
file on every launch. The media runtime test also checks the authenticated API
after restart and credential rotation. Fixtures use explicit local peers.

## Application integration and recovery checks

The service additions register focused checks alongside the existing media and
VPN tests. Their intended assertions are listed here so maintainers can select a
check after a change. A registered test is not evidence of a successful run;
record the result against the exact source revision.

| Check                                                | Assertions                                                                                                                                                             |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `configuration-integration`, `integration-behavior`  | Secret references, schema validation, bootstrap/managed ownership, repeated reconciliation, password rotation and mutation-free previews                               |
| `configuration-readiness`                            | Missing production declarations for every service and a positive all-services composition using public evaluation fixtures                                             |
| `configuration-complete`                             | Composition of all examples and opt-in services, including generated native units; evaluation only                                                                     |
| `configuration-optional`, `configuration-operations` | Resource defaults, private endpoints, host-owned hardware, backup inventory and monitored versus dashboard-only endpoints                                              |
| `media-workflow`                                     | Native Seerr request, Radarr search/grab, qBittorrent piece verification, actual hardlink import, restricted Jellyfin range playback and application-state restoration |
| `cross-seed`                                         | Native authenticated search, strict matching, hardlink injection, required client recheck and resumed seeding without a second transfer                                |
| `pressure`                                           | Native qBittorrent authentication, pressure-owned pause/resume and preservation of a manually stopped torrent                                                          |
| `arr-integration`                                    | Native Lidarr profile lookup and Bazarr key/settings installation, persistence and repeat application                                                                  |
| `quality`                                            | Native Sonarr/Radarr profiles and size limits from immutable local guide data, mutation-free preview, repeat application and preservation of undeclared profiles       |
| `audio-runtime`                                      | Native Navidrome and Audiobookshelf accounts, library discovery, playback, audiobook progress, restarts and effective filesystem permissions                           |
| `usenet-credentials`                                 | Native SABnzbd categories/authentication and NZBGet credential rotation without the default password                                                                   |
| `books`                                              | Native Komga claim, restricted reader, CBZ scan/page retrieval, read progress and restart; service namespace prevents library writes                                   |
| `autobrr`                                            | Native administrator/API-token onboarding, named client/filter/action persistence, repeat application and credential rotation; no provider announcement                |
| `optional-media`                                     | Archive extraction, original-file preservation, writable Syncthing state, guarded storage and private Maintainerr access                                               |
| `maintainerr`                                        | Source-built native startup, Node addon loading, persistent state, systemd hardening, authenticated access and direct-backend denial                                   |
| `operations`                                         | Encrypted Restic staging/restoration, SQLite and PostgreSQL data, writer recovery after failure, notification access and operational health                            |
| `access`                                             | Native Authelia/Caddy authentication, spoofed headers, direct backend access and firewall lifecycle                                                                    |
| `arr-postgresql`                                     | Native Arr database selection, isolated roles and refusal to discard existing SQLite state                                                                             |
| `private-archives`                                   | Native Paperless SQLite/PostgreSQL and Immich upload, backup and isolated restore with original-file verification                                                      |

`source-secrets` scans the complete Nix source snapshot with Gitleaks; the local
`gitleaks-staged` hook scans staged changes. The allowlist names only known
public fixture credentials under test paths. Other values in tests and the same
values outside those paths remain subject to scanning. The private-key hook
remains enabled separately.

The Python behavior checks use controlled HTTP responses to cover failure paths.
The NixOS checks run the packaged applications with public disposable
credentials. Neither substitutes for real indexer/provider accounts,
DNS/certificate setup, GPU tests, mobile clients or measured desktop resource
use. Fixtures never need the consuming host's nix-seal secrets.
