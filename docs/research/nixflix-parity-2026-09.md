# Nixflix comparison and homelab design

Reviewed September 23, 2026 against [Nixflix commit
`78fe4493`](https://github.com/kiriwalawren/nixflix/tree/78fe4493e39f3f4099eea678a0ca572ece6039b5)
and the current, uncommitted `nix-homelab` and desktop configuration. I cloned
Nixflix into ignored local scratch storage and read its modules, scripts, tests,
documentation and workflows. This is source review. It is not a benchmark or a
claim that either complete stack has been deployed successfully.
On September 24, the upstream clone advanced to
[`122f2330`](https://github.com/kiriwalawren/nixflix/commit/122f2330e9b5fd3a0d963957fe4ac5f40df85773).
That commit enables WebSockets for Arr nginx hosts. The local
[LAN HTTPS module](../../modules/operations/lan-https.nix) already enables
WebSockets for declared sites; its [configuration check](../../tests/eval/operations.nix)
asserts this. Neither source check proves live proxy behavior.

## Answer

Nixflix's useful idea is ordered, API-driven setup of a connected media stack.
It starts applications, waits for their APIs, and reconciles settings and
relationships through systemd jobs. Its scope includes separate Sonarr and
Sonarr Anime instances; Radarr, Lidarr, Prowlarr, Jellyfin, Seerr, Navidrome,
SABnzbd, qBittorrent, Recyclarr and Maintainerr. It also offers PostgreSQL,
reverse proxies, WireGuard confinement, notifications, plugins and themes.
[Module entry point](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/default.nix),
[full-stack fixture](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/tests/vm-tests/full-stack.nix).

The local repository already implements most of that behavior through native
NixOS services and a [runtime API reconciler](../../modules/integration/default.nix).
Its main advantage is the surrounding operation: mount-checked shared storage,
selective VPN routing, runtime credentials, capacity controls, private access,
readiness checks, monitoring, backups and restore tests. Those capabilities are
not supplied as one integrated recovery design by Nixflix. The remaining
Nixflix-specific gaps are Jellyfin plugin configuration and runtime
verification, advanced Maintainerr rule and overlay reconciliation, and a proxy
theme. A reusable pinned Jellyfin plugin installer is now available; the desktop
selects three packaged plugins with a host-owned compatibility guard.
An independent Sonarr Anime process is now available as an opt-in module but
has not been selected on the desktop. The remaining features should
be added as opt-in modules with their own tests, without importing Nixflix's
deletion policy or fixed filesystem identities.
[Local storage](../../modules/storage/default.nix),
[VPN](../../modules/vpn/wireguard.nix),
[operations](../../modules/operations/default.nix),
[Nixflix root defaults](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/default.nix).

## Feature map

"Available" means the reusable module exists. "Selected" means the current
desktop configuration declares it. A module or a test definition is not proof
that the live service works.

| Nixflix behavior | Local state | Evidence and decision |
| --- | --- | --- |
| Sonarr, Radarr, Lidarr, Prowlarr settings, roots, clients and indexers | Available and selected | [Typed manager declarations](../../modules/integration/services/servarr.nix), [Prowlarr](../../modules/integration/services/prowlarr.nix), [reconciler](../../scripts/integration/adapters/arr.py). Nixflix has [common Arr jobs](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/arr-common/mkArrServiceModule.nix). Local bootstrap preserves existing objects; managed mode changes declared fields. |
| Independent Sonarr Anime process and library | Available; not selected on desktop | Nixflix has a [second instance and port](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/sonarr-anime.nix). The local [opt-in process](../../modules/optional/sonarr-anime.nix) has its own loopback port, account and state; [integration](../../modules/integration/default.nix) can install a second API key. The [two-instance VM](../../tests/nixos/sonarr-anime.nix) passed with distinct keys and library roots. Downloader category, Prowlarr and Seerr routes remain explicit host choices. |
| qBittorrent and SABnzbd setup and Arr download clients | Available; qBittorrent selected | [Client declarations](../../modules/integration/services/servarr.nix), [qBittorrent](../../modules/downloaders/qbittorrent.nix), [SABnzbd](../../modules/downloaders/sabnzbd.nix). Nixflix's [Downloadarr](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/downloadarr/options.nix) also supports external clients. Local declarations additionally support NZBGet, Transmission and Deluge connections, with installation left to the host. |
| Jellyfin setup, users, libraries, encoding and networking | Available and selected | [Typed options](../../modules/integration/services/jellyfin.nix), [API adapter](../../scripts/integration/adapters/jellyfin.py). Nixflix [adds metadata, plugins and branding](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/jellyfin/default.nix). Local API key onboarding remains attended after first-run login; Nixflix [writes a key into SQLite](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/jellyfin/apiKeyService.nix). |
| Jellyfin plugins and subtitles | Pinned installer available; desktop selects three plugins; runtime unverified | Nixflix [installs pinned or repository-resolved plugins](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/jellyfin/plugins/pluginsService.nix). The local [plugin module](../../modules/optional/jellyfin/plugins.nix) replaces only marked directories and keeps undeclared plugins. The consuming desktop configuration guards Jellyfin's version. Local [Bazarr integration](../../scripts/integration/adapters/bazarr.py) remains separate. Plugin ABI, real startup and removal still need a disposable runtime test. |
| Jellyfin branding and theme.park | Branding fields available; proxy theme absent | [Typed branding](../../modules/integration/services/jellyfin.nix) manages declared CSS, disclaimer and splash-screen switch. Nixflix's [theme helper](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/lib/mkVirtualHosts.nix) rewrites proxy responses and loads a third-party stylesheet. No remote theme is enabled by default locally. |
| Seerr onboarding, users, libraries and manager destinations | Available and selected | [Seerr module](../../modules/integration/services/seerr.nix), [adapter](../../scripts/integration/adapters/seerr.py). Nixflix has [equivalent onboarding jobs](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/seerr/default.nix). Local quotas and approval policy remain explicit host choices. |
| Navidrome users and music playback | Available; separate desktop music owner | [Native policy](../../modules/media/default.nix) and [adapter](../../scripts/integration/adapters/navidrome.py). Nixflix has [Navidrome onboarding](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/navidrome/default.nix). Avoid a second instance owning the same library and port. |
| Recyclarr quality policy | Available and selected | [Quality module](../../modules/optional/quality/default.nix) and [4K example](../../examples/quality-4k.nix). Nixflix supplies [guide-based profiles](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/recyclarr/default.nix) and optional [unmanaged-profile deletion](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/recyclarr/cleanup-profiles.nix). Preserve unmanaged local profiles by default. |
| Maintainerr rules, overlays and `.ignore` maintenance | Hardened service available; rule lifecycle absent | [Local service](../../modules/optional/maintainerr/default.nix) supplies a private authenticated gateway. Nixflix's [rules](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/maintainerr/rules/default.nix) and [`.ignore` timer](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/maintainerr/forceJellyfinIgnore.nix) are absent locally. Do not automate deletion before a reviewed collection policy and restore drill. |
| Notifications and FlareSolverr | Available; selected by host as needed | [Typed Jellyfin/ntfy manager notifications](../../modules/integration/services/servarr.nix) and [optional FlareSolverr](../../modules/optional/automation.nix) cover Nixflix's [notification jobs](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/notif/default.nix) and [FlareSolverr](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/flaresolverr.nix). Provider egress and alert delivery still need live checks. |
| PostgreSQL for Arr | Opt-in, available | [Local database profile](../../modules/operations/arr-postgresql.nix) guards existing SQLite state and adds recovery exports. Nixflix [provides socket-based PostgreSQL](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/arr-common/postgres.nix). No measured local reason requires migrating this desktop from SQLite. |
| WireGuard isolation | Available and selected for downloader | Both use `vpn-confinement`. Local [integration](../../modules/vpn/wireguard.nix) and [VM test](../../tests/nixos/vpn-namespace.nix) cover narrower consumer policy and tunnel failure; Nixflix [exposes per-service VPN switches](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/vpn.nix). Live provider behavior remains unverified here. |
| nginx/Caddy reverse proxy and TLS | Available as host policy | [LAN HTTPS](../../modules/operations/lan-https.nix) and [authenticated access](../../modules/operations/access.nix) are selected by the consuming host. Nixflix [builds per-service vhosts](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/lib/mkVirtualHosts.nix). Keep domain, certificates, allowed CIDRs and firewall rules with the host. |
| Storage, backup and operations | Local additions | [Mount guard](../../modules/storage/default.nix), [backup/recovery](../../modules/operations/default.nix), [health](../../modules/operations/health.nix), and [readiness](../../modules/readiness/default.nix) extend beyond Nixflix's media setup. The host still supplies disks, encrypted secrets and backup destination. |

## Systems design decisions

Keep the existing repository ownership. `nix-homelab` owns reusable services,
typed relationships, safe defaults and tests. The consuming `nix-conf` host owns
actual disks, IDs where required for existing data, providers, credentials,
DNS, ingress addresses, certificates, recovery destinations and hardware. The
[contribution contract](../../CONTRIBUTING.md) already enforces this split.
Importing Nixflix wholesale would create duplicate owners for units, ports,
media paths, proxy configuration and VPN policy. This is an inference from the
two module entry points, not a tested conflict matrix.

The local integration interface should remain the stable seam. Named clients,
managers and destinations compile into one runtime specification per application;
one reconciler validates live schemas and reads systemd credentials. Keep
`bootstrap` and `managed` modes. A deletion mode, if ever needed, must show a
dry-run inventory of exact object IDs, require a current backup, and test
failure halfway through a batch. Nixflix's [root-folder job](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/arr-common/rootFolders.nix)
continues after some failed deletes, so its "source of truth" claim is not a
transaction guarantee. The local [integration guide](../integration.md) defines
the current preservation policy.

The present file layout is mostly sound. Large files now concentrate unrelated
concerns: [manager options and rendering](../../modules/integration/services/servarr.nix),
[integration schema and units](../../modules/integration/default.nix), and
[operations inventory and backup](../../modules/operations/default.nix). Split
each at its existing interface when adding the next substantial behavior:
`integrations/servarr/{options,render}.nix`,
`integration/{schema,units}.nix`, and `operations/{inventory,backup}.nix`.
Keep one public option owner and one service inventory; avoid a second parallel
feature catalog. This is a maintainability recommendation, not a dependency for
the current brand/API change.

Nixflix's [shared group-writable roots and fixed IDs](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/globals.nix)
are convenient on a fresh server. The local [storage module](../../modules/storage/default.nix)
validates real mounts and gives players read-only access. Keep that isolation.
Likewise, do not expand the VPN namespace to all services: indexers, metadata
providers and playback have different network needs. The host's direct,
proxy-only and confined policies should be checked against observed traffic.

For performance, retain [bounded download queues](../../modules/downloaders/qbittorrent.nix),
[background scheduling](../../modules/profiles.nix), and
[storage-pressure control](../../modules/operations/default.nix). Tune them
from measured idle RAM, CPU, disk wakeups and download/import I/O. Neither
repository's VM definitions establish real hardware throughput, GPU support or
power use. A second Sonarr instance and plugin scanning would increase startup,
database and maintenance load; make both opt-in.

Treat plugin updates as code changes. Nixflix has a
[scheduled plugin-manifest update that auto-merges](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/.github/workflows/update-manifest.yml),
and its plugin installer can resolve a repository manifest at runtime. The
local implementation should instead pin plugin artifacts and hashes in the
flake, check compatibility with the selected Jellyfin package, and review a
plugin version change with the same backup and restart test as a server
upgrade. Nixflix's unit check passing below establishes generated options and
units; it does not establish plugin ABI or upgrade safety. The selected local
Jellyfin package is 12.0, and Jellyfin's
[plugin guidance](https://jellyfin.org/docs/general/server/plugins/) says manual
installs require a server restart. Its
[12.0 release guidance](https://jellyfin.org/posts/jellyfin-release-12.0/)
requires a full data/config backup before upgrading. A compatible plugin
artifact and upgrade fixture must therefore be selected before declaring
plugin parity on this host.

## Integration and rollout design

Each new service should cross the same boundaries in order: an opt-in native
unit, a private listener, mount-checked storage, a runtime credential, a named
integration job, an operations inventory entry, and a disposable runtime test.
The host then selects that service and supplies its own secret, address and
media path. This keeps `modules/catalog.nix` as the service inventory and
`modules/integration/default.nix` as the API job interface; neither needs a
second, feature-specific registry.

| Concern | Required behavior before host selection |
| --- | --- |
| State and recovery | Give every additional process its own state path and unit name. Include both in the backup inventory, then restore a fixture into a fresh VM before migrating real data. A successful backup command alone does not prove recovery. |
| Network and secrets | Bind APIs to loopback, keep native ports closed, load credentials at runtime and test that a failed VPN route or missing secret prevents the relevant work. Expose a named HTTPS host only through the consuming host's ingress policy. |
| API ownership | Fetch the live schema, update only declared fields, preserve unnamed UI objects and make a second run produce no writes. Show planned changes before any future deletion mode runs. |
| User experience | Give every enabled job a readiness failure that names its missing prerequisite. Keep initial Jellyfin login and key creation documented as an attended step. Include a short status and rollback procedure with each new service. |
| Resource use | Set application-specific CPU, memory and I/O limits after measuring normal and scan load. Keep optional jobs disabled on the desktop until their capacity and disk-wake cost are observed. |

The sequence is additive: first finish one isolated capability and its tests,
then enable it on the desktop after a backup and restore drill. Validate API
state, inter-service routes and failure behavior after activation. The Nix
evaluation and desktop build below prove configuration construction only;
they cannot substitute for those live checks.

## Remaining acceptance work

1. Select Sonarr Anime on a host only if it needs independently managed anime.
   The opt-in process, recovery entry and two-instance API/root test are in
   place. The consuming host must still declare a distinct downloader category,
   Prowlarr and Seerr relationships, and exercise import, backup and restore
   before using real data.
2. Verify the selected Jellyfin plugins in a disposable VM: startup, ABI,
   upgrade, configuration, restart and attended removal. The pinned installer
   replaces only marked directories and preserves other plugins. Keep runtime
   secret fields out of derivations. Avoid automatic updates from a remote
   manifest.
3. Add Maintainerr rule and overlay support only for an explicitly reviewed
   collection. The proposed starting policy is `isActive = false`,
   `arrAction = "DO_NOTHING"`, an explicit positive `deleteAfterDays`,
   `listExclusions = true` and `forceSeerr = false`, matching the
   [upstream rule controls](https://github.com/kiriwalawren/nixflix/blob/78fe4493e39f3f4099eea678a0ca572ece6039b5/modules/maintainerr/rules/options.nix).
   Preview candidates and exclusions for one library first; enable deletion
   only after a reviewed retention period and restore of a deleted fixture.
   Preserve UI-created rules. Updating a rule's library or data type can clear
   its collection, so that change needs a separate migration path.
   The [Maintainerr policy research](maintainerr-policy.md) explains why a null
   action delay should not be used as a safety control.
4. Validate the actual desktop: evaluate and build on `desktop`, then check
   private HTTPS, API credentials, permitted indexer search, VPN outage,
   hardlink import, request-to-playback, storage pressure, alerts, and an
   isolated restore. Record results separately from source review and VM tests.

## Validation and limits

Source inspection included the uncommitted local tree based on
`108532307c55ad3554b502fcc34fb803612e5ecd` and the pinned upstream clone.
The consuming host tree was based on
`9ec1fafddf29c17aacf48fa37d0112a68af89f99`. Both working trees can change
before this note is committed.

On `desktop`, the current local worktree passed
`configuration-integration`, `configuration-optional`, `integration-behavior`,
the `media-workflow` and `sonarr-anime` VMs, focused repository hooks, and
`just os-build desktop`. The first desktop build stopped at a misspelled
Jellyfin `enableUPnP` option; correcting the option, generated API field and
schema allowed the second build to pass. This is build evidence, not activation
or a test against a running media server. Nixflix's pinned
`checks.x86_64-linux.unit-tests` build passed on `desktop`; evaluation warned
that `system.stateVersion` is unset in some fixtures. No Nixflix VM was built
or activated.
The presence of other local test definitions is evidence of intended coverage,
not of a successful run at this revision.

The September 24 plugin change passed its four focused Python cases, the
`jellyfin-plugin-behavior` build check, `configuration-optional`, and a full
`just os-build desktop` without activation. The generated Jellyfin pre-start
script installs packages before the host's Moonfin configuration command.
These checks do not establish plugin loading or compatibility at runtime.
