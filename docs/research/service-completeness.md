# Service completeness and recommended additions

Research date: 2026-09-12. Baseline revision:
`f229e5076238fa88d87dad14a363174f1c858299`. Fresh GitHub commits API requests
and shallow clones confirmed nixarr HEAD
`282ce99b31d52d72cca281e3d26d3dd267946800` and nixflix HEAD
`d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b`. These happen to match the prior
report; this is refreshed source inspection, not an assumption that the older
report remains current. No upstream tests were executed and no performance
measurements were collected.

This report extends the [cross-project comparison](project-comparison.md) and
[service catalog](media-services.md). The deeper source inspection concentrates
on nixarr and nixflix because their application integration directly addresses
this project's gaps. SelfHostBlocks supplies another useful comparison for
shared service capabilities. This is a bounded survey, not a ranking of every
public repository. Recommendations below describe gaps at the baseline revision.
The [implementation roadmap](../roadmap.md) and linked setup guides track the
subsequent implementation; this research is not runtime or benchmark evidence.

The next priority should be completed workflows. The current repository starts
and hardens applications, but its Arr module primarily binds addresses and
permits state writes. Its Seerr module only sets HOST and UMask, and the media
module sets Navidrome's music path and Audiobookshelf's host. That does not yet
configure relationships inside application databases.

## Gaps demonstrated by peer implementations

1. **Prowlarr indexer and application reconciliation.** Declare indexers, tags,
   categories, enabled capabilities and Sonarr/Radarr/Lidarr connections with
   user-supplied nix-seal API keys. Nixarr actually queries schemas and current
   objects, matches by name, validates implementation identity, merges declared
   fields and creates or updates objects. It leaves undeclared objects alone.
   Its module still has TODOs for overwrite control and a sync interval. Adopt
   schema validation and declare an explicit create-only versus managed mode.
   Test the API state after two runs, a UI edit, a secret rotation and a service
   restart.
   [Nixarr synchronizer](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/nixarr/prowlarr/settings-sync/sync_settings.py),
   [module](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/nixarr/prowlarr/settings-sync/default.nix).

2. **Arr root folders and download clients.** Configure
   qBittorrent/SABnzbd/NZBGet connections, credentials, per-manager categories,
   completed download handling and consistent library roots. The current shared
   filesystem paths alone do not register these objects with the applications.
   Nixarr implements download-client upserts; nixflix's full-stack fixture
   asserts Arr roots and generated SABnzbd categories, including a restart race.
   Add an actual permitted local download, application import and hardlink
   assertion, rather than only creating a link as the manager user.
   [Nixarr Radarr sync](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/nixarr/radarr/settings-sync/sync_settings.py),
   [nixflix full-stack test](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/tests/vm-tests/full-stack.nix).

3. **Complete Bazarr configuration.** Connect Sonarr/Radarr, set language
   profiles, providers, credentials, monitored-only scope and an explicit
   bounded schedule. Nixarr implements the connections through the settings API,
   including monitored flags; it hardcodes 60-minute synchronization in its
   script. Language/provider policy is a further recommendation, not
   functionality established by that source. Verify subtitles are discovered and
   written beside fixture media while unrelated directories remain unwritable.
   Its current Bazarr VM test waits for the sync unit but does not assert
   returned settings or a subtitle workflow.
   [Nixarr Bazarr sync](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/nixarr/bazarr/settings-sync/sync_settings.py),
   [Bazarr test](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/tests/bazarr-sync-test.nix).

4. **Usable quality policy, not just an enabled Recyclarr service.** The
   existing extras example supplies two endpoints and keys but no actual quality
   profiles, custom formats, scores or quality definitions. Add a small reviewed
   1080p policy, an optional 4K policy and size/upgrade limits suited to limited
   storage. Nixflix ships separate Sonarr/Radarr/anime modules plus optional
   unmanaged profile cleanup. Its cleanup code reassigns existing media and
   deletes profiles; do not copy this as a default. One tool must own each field
   to avoid two reconcilers fighting. Test a preview, repeated apply and
   preservation of unmanaged profiles.
   [Nixflix Recyclarr modules](https://github.com/kiriwalawren/nixflix/tree/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/recyclarr),
   [cleanup implementation](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/recyclarr/cleanup-profiles.nix).

5. **Jellyfin onboarding, libraries and least-privilege accounts.** Nixflix has
   actual setup-wizard API calls, library reconciliation, user policy and
   API-key setup. Track resource ownership, preserve manually created libraries
   and make deletion explicit. Its library reconciler tracks previously managed
   libraries in a state file and removes libraries whose declarations disappear.
   Its users default to mutable, so subsequent UI changes win; passwords are
   creation-only even when mutable=false. That is a useful warning that
   'declarative' does not imply rotation works. This project should test
   bootstrap, repeated apply, library disappearance, password rotation and
   non-admin login rights.
   [Wizard](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/jellyfin/setupWizardService.nix),
   [libraries](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/jellyfin/libaries/default.nix),
   [user mutation contract](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/jellyfin/users/options.nix).

6. **Jellyfin performance configuration with hardware verification.** Expose
   native encoding settings for a host-selected render device, only supported
   decoding codecs, a bounded transcode directory, throttling and scan/image
   extraction schedules. Nixflix implements generated encoding XML installed
   before Jellyfin starts, plus options for hardware acceleration, codec
   support, thread count and tone mapping. It also exposes library image
   extraction controls. This is configurable machinery, not proof that a profile
   is faster. Keep driver/device selection in nix-conf; measure real direct play
   and transcode CPU/GPU use and verify software fallback. Do not turn on
   expensive trickplay/chapter extraction indiscriminately on a desktop.
   [Encoding implementation](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/jellyfin/encoding/default.nix),
   [encoding options](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/jellyfin/encoding/options.nix),
   [library options](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/jellyfin/libaries/options.nix).

7. **Seerr setup and request policy.** Nixflix calls the onboarding APIs,
   selects Jellyfin libraries, configures Sonarr/Radarr destinations and adds
   users. Complete this project's links with explicit quality profile/root
   selections, request permissions, quotas and default approval policy.
   Nixflix's setup tolerates an initial Jellyfin sync error as nonfatal; a
   successful setup unit therefore cannot prove the library is populated. Add a
   separate health assertion for synchronized libraries and a request that
   reaches the intended manager. Never silently autoapprove every user's
   requests.
   [Setup](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/seerr/setupService.nix),
   [Seerr integration modules](https://github.com/kiriwalawren/nixflix/tree/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/seerr).

8. **Optional database profile with migration and recovery tests.** Nixflix
   supports Arr PostgreSQL through local Unix sockets, per-service main/log
   databases, ownership and startup dependencies. Its VM test asserts each
   service reports postgreSQL. There is no benchmark in this evidence
   establishing it beats SQLite for this desktop, and enabling it does not
   migrate existing SQLite state. Keep SQLite as the simpler starting point,
   with databases on SSD, then add opt-in PostgreSQL only with measured need,
   backup/restore tests, version upgrade planning and documented migration.
   Avoid a network database listener when only local sockets are needed.
   [Database integration](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/arr-common/postgres.nix),
   [database VM test](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/tests/vm-tests/postgresql-integration.nix).

9. **Application-consistent backups and proven restoration.** Nixflix exposes
   Arr backup folder, interval and retention, but the inspected modules and
   tests do not establish a full media-stack restore. Local documentation
   inventory is also not a restore implementation. Export owned state and backup
   hooks here; keep repository destinations and secrets in nix-conf. Handle
   SQLite databases with an application backup, supported online copy or stopped
   service, and PostgreSQL with logical backups. Restore users, requests, Arr
   objects and credentials into an isolated VM and verify API-visible state. A
   directory on the same media HDD cannot supply disk-failure recovery.
   [Arr host configuration](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/modules/arr-common/hostConfig.nix),
   [nixflix test inventory](https://github.com/kiriwalawren/nixflix/tree/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/tests/vm-tests).

10. **API-level integration and drift tests.** Local tests already establish
    valuable VPN and filesystem boundaries. Add API assertions for all
    configured relationships, repeated reconciliation, partial startup, secret
    rotation, removal policy and real import/playback. Nixflix's full-stack test
    checks applications, category names and root folders after a startup race,
    but its named full-stack fixture contains Arr/SAB services and does not
    establish a Seerr-to-Jellyfin request/download/playback round trip. Borrow
    the assertions and make stronger, clearly scoped claims. Required CI should
    use local fixture services and public disposable credentials, with separate
    opt-in real-provider and hardware tests.
    [Full-stack test](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/tests/vm-tests/full-stack.nix).

## Common implementation rules

Use a shared, small reconciliation helper with bounded retries, readiness
probes, validated schemas, structured errors and redacted logs. Nixarr's helper
rejects unknown configured fields and expands runtime secret-file references.
Its algorithm preserves unspecified fields, a useful model for coexistence with
UI configuration. Credentials should come from nix-seal through systemd
credentials where possible, not shell arguments or derivation text. API
responses and query URLs can contain tokens. Keep read/modify/write operations
explicit and track ownership before supporting deletion.
[Nixarr helper](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/nixarr/lib/nixarr-py/nixarr_py/utils.py).

Implementation order recommendation: 1 and 2 first, then 3, 4, 5 and 7; build 10
alongside each. Add 6 once the consuming host specifies its GPU/device. Add 9
before real state becomes valuable. Keep 8 optional until there is a concrete
reason to accept its extra operational work. An honest 'complete' service needs
bootstrap, daily behavior, rotation, observability, resource controls and
restore evidence, not merely an enable flag or a large option catalog.

## Shared capabilities worth borrowing

SelfHostBlocks combines application modules with backup, reverse proxy,
authentication and monitoring interfaces. Its Restic VM test backs up fixture
files, modifies and deletes them, restores them and checks their contents. That
is useful recovery evidence, though it does not establish application database
recovery. The project also documents browser-based login tests. Borrow these
contracts and assertions while retaining native NixOS modules, nix-seal and
vpn-confinement. Adopting its patched nixpkgs dependency would be a separate
architectural decision.
[SelfHostBlocks](https://github.com/ibizaman/selfhostblocks),
[Restic test](https://raw.githubusercontent.com/ibizaman/selfhostblocks/main/test/blocks/restic.nix).

Derive a small service inventory from enabled native configuration. It should
record units, local endpoints, state directories, disposable caches, secret-file
references, health checks and backup hooks. Reuse that inventory for monitoring,
documentation and host backup integration. Avoid maintaining a second set of
options that duplicates every upstream module.

For this project, a complete service should have:

- Reproducible onboarding and authenticated connections to its dependencies.
- A documented choice between initial setup and continuously managed settings.
- Tested credential replacement, ownership and preservation of manual settings.
- Bounded background work, cache growth and temporary storage.
- Useful health checks and actionable failure notifications.
- A consistent backup and an isolated restore that recovers application state.
- Tests for normal use, missing dependencies, upgrades and denied access.

Provider accounts, user-supplied secrets and hardware choices remain deployment
inputs. They should be explicit inputs with validation, rather than undocumented
steps hidden behind a successful service start.

## Completion plan for the existing service catalog

These are proposed additions to the current configuration. Native upstream
options may already support parts of each row; module availability does not mean
this repository configures or tests the behavior.

| Service        | Configuration to complete                                                                                 | Performance and security acceptance                                                                                                                    |
| -------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sonarr         | Series roots, downloader/category, Prowlarr sync, quality and upgrade policy, completed-download handling | Import a fixture episode through Sonarr, preserve seeding hardlinks, restrict writes to owned roots, cap unwanted upgrades                             |
| Radarr         | Movie roots, downloader/category, Prowlarr sync, quality/custom-format policy                             | Import a fixture movie, verify hardlinks and size policy, preserve manual objects                                                                      |
| Lidarr         | Music roots, metadata and quality choices, downloader/category and indexer capabilities                   | Test album import and permissions; bound refresh work and avoid repeatedly upgrading the whole library                                                 |
| Bazarr         | Manager credentials, languages, providers, monitored scope and schedules                                  | Write a fixture subtitle only to permitted media paths; bound concurrent searches and retries                                                          |
| Prowlarr       | Indexers, categories, app connections, tags and selected indexer proxy assignments                        | Verify search reaches the intended route, app sync stays reachable, and credentials never enter logs                                                   |
| Seerr          | Media-server onboarding, libraries, manager roots/profiles, users, request limits and approval policy     | Verify a request reaches the correct manager and appears available after import; test unprivileged access                                              |
| qBittorrent    | Manager categories, save paths, incomplete paths, queue/connection limits and seeding policy              | Test download and resume across tunnel failure, API credential rotation, low-space pause and recovery                                                  |
| SABnzbd        | Provider endpoints, TLS verification, runtime credentials, categories, repair/unpack policy and retention | Bound download and unpack concurrency; test authenticated manager handoff and disk-pressure behavior                                                   |
| NZBGet         | Equivalent provider/category integration for deployments choosing it                                      | Test verified TLS, authenticated RPC, limited post-processing and restart recovery independently of SABnzbd                                            |
| Jellyfin       | Libraries, accounts, API keys, metadata/scanning policy and host-selected encoding                        | Verify restricted accounts, direct play, supported GPU encoding, fallback and bounded transcode cache                                                  |
| Plex           | Documented account claim flow, library setup, access policy and selected hardware support                 | Keep claim material outside the store, verify permissions and playback; document account-dependent setup rather than promising unattended provisioning |
| Navidrome      | Accounts, library scan schedule, artwork/cache budgets and chosen transcoding profiles                    | Verify music discovery and client playback with read-only media, bounded cache and an unprivileged account                                             |
| Audiobookshelf | Libraries, accounts, scan policy, podcast destinations and metadata backup                                | Separate writable podcast downloads from protected source media; test playback progress recovery and access restrictions                               |

Optional players and alternative downloaders need their own completion tests.
Passing the Jellyfin/qBittorrent path does not establish Plex/NZBGet coverage.
External account flows should have precise human setup instructions where no
supported unattended API exists.

## Services and integrations to add

Priority reflects value for a desktop with shared media and backup storage. It
is a recommendation, not a measured comparison of competing products. The
selected nixpkgs revision contains native NixOS modules for the named candidates
below except Maintainerr. That establishes packaging availability only.

| Priority          | Addition                              | What it contributes                                             | Required configuration before adoption                                                                                |
| ----------------- | ------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| First             | Recyclarr policies                    | Repeatable Sonarr/Radarr quality definitions and custom formats | Reviewed profiles, storage-aware size limits, one owner per setting and non-destructive synchronization               |
| First             | Gatus with ntfy                       | Workflow health checks and failure/recovery notifications       | Authenticated checks where required, private alert topics, deduplication and tested alert delivery                    |
| First             | Service-aware Restic integration      | Recoverable application state                                   | Consistent exports or stopped-service copies, host-owned destinations, retention and isolated restore drills          |
| Next              | Homepage                              | A service dashboard generated from the enabled inventory        | Private access, least-privilege widget credentials and no unnecessary privileged runtime socket                       |
| Next              | autobrr                               | Filtered release-announcement automation                        | Explicit filters, downloader connections, duplicate/size limits and restrained provider activity                      |
| Next              | cross-seed                            | Reuse existing torrent data for compatible additional seeds     | Validated path mappings, hardlinks, private API credentials, bounded searches and tested client injection             |
| Optional          | Komga or Kavita; Shelfmark separately | Book/comic reading and a separate acquisition workflow          | Choose the reader for the actual formats and clients; validate the acquisition-to-library workflow before enabling it |
| If needed         | Unpackerr                             | Extract archived downloads that otherwise block Arr imports     | Restricted download paths, bounded extraction concurrency and temporary space, tested import and cleanup              |
| If needed         | FlareSolverr                          | Browser-based compatibility for selected indexers               | Private endpoint, verified egress route, bounded browser concurrency and demonstrated indexer need                    |
| Optional          | Pinchflat                             | Scheduled channel/video archiving                               | Format and retention policy, disk budget, bounded downloads and runtime provider credentials where needed             |
| Optional          | Maintainerr                           | Rule-based media retention and cleanup                          | Authenticated proxy with private backend; reviewed opt-in deletion, grace periods, exclusions and recovery evidence   |
| Separate workload | Immich                                | Photo library and mobile backup workflow                        | Separate media/database backups, SSD database, bounded thumbnail/ML work and restore tests                            |
| Separate workload | Paperless-ngx                         | Searchable private document archive                             | Separate access group, OCR worker limits, ingestion policy and database/document recovery                             |
| Host choice       | Syncthing, AdGuard Home, Scrutiny     | File synchronization, DNS filtering and disk-health visibility  | Explicit sharing, reliable DNS host availability and minimal device privileges respectively                           |

Recyclarr documents several synchronization stages and their failure behavior.
The current extras example supplies connections without a useful quality policy.
Review policy changes and record the selected templates; locking Nix packages
alone does not freeze independently fetched policy content.
[Recyclarr guide](https://recyclarr.dev/guide/),
[synchronization behavior](https://recyclarr.dev/guide/sync-behavior/).

Gatus supports status, content and latency conditions, plus alert providers. Use
checks for stale backups, storage headroom and failed integration jobs as well
as HTTP availability. ntfy requires explicit access control: its documented
default access is read-write. Configure deny-all defaults, scoped credentials
and bounded retention. Keep private media titles and credentials out of alerts.
[Gatus documentation](https://raw.githubusercontent.com/TwiN/gatus/master/README.md),
[ntfy access configuration](https://docs.ntfy.sh/config/).

Restic provides repository checking and restore operations. Connect these to the
consuming host's existing backup policy instead of adding a competing scheduler.
The reusable module should export what needs preservation and how to make a
consistent copy. The host owns destinations, retention budgets and nix-seal
references. Backup storage on the media disk cannot recover that disk's failure.
[Repository maintenance](https://restic.readthedocs.io/en/stable/045_working_with_repos.html),
[restoring backups](https://restic.readthedocs.io/en/stable/050_restore.html).

Homepage supports configured service widgets. Generate its entries from enabled
services so disabled applications do not leave dead links. autobrr adds filtered
announcement handling, which needs real filter and client configuration beyond
the existing listener example. cross-seed can link existing data; its documented
hardlink workflow needs matching filesystem paths. Test those assumptions before
allowing automated injection into the torrent client.
[Homepage services](https://gethomepage.dev/configs/services/),
[autobrr introduction](https://autobrr.com/introduction),
[cross-seed setup](https://www.cross-seed.org/docs/basics/getting-started),
[cross-seed linking](https://www.cross-seed.org/docs/tutorials/linking).

Komga and Kavita offer reading libraries. Shelfmark addresses acquisition and
should be assessed separately from reader selection. Pinchflat supplies another
media source through channel archiving. These additions need distinct writable
download areas and deliberate import paths into read-only player libraries.
[Komga](https://komga.org/docs/introduction/),
[Kavita](https://www.kavitareader.com/),
[Shelfmark](https://github.com/calibrain/shelfmark),
[Pinchflat](https://github.com/kieraneglin/pinchflat).

Unpackerr addresses archives stuck in an Arr download queue. Add it only where
the chosen workflow needs extraction, with tests that cleanup preserves original
seed data and cannot write outside configured download paths. FlareSolverr uses
browser instances to handle protected indexer pages. Upstream warns about
browser memory use and public exposure. Keep it private and optional; its
outbound browser traffic needs the same deliberate privacy policy as the indexer
requests. [Unpackerr](https://github.com/Unpackerr/unpackerr),
[FlareSolverr](https://github.com/FlareSolverr/FlareSolverr).

Current Maintainerr upstream documents Plex, Jellyfin and Emby support. Older
Plex-only descriptions are no longer a reliable basis for rejecting it. There is
no native Maintainerr service module in the inspected package set, so first
validate a pinned release, packaging and integration tests. The proposed
review-before-deletion policy is an adoption requirement here, not a claim that
all desired safeguards exist as upstream flags. Its documentation states that
there is no built-in login and reachable clients can read configured
credentials. Require a private backend, authenticated browser access and a
bypass test. Its displayed API key is reserved for future use and does not
protect access.
[Maintainerr upstream](https://github.com/Maintainerr/Maintainerr),
[configuration documentation](https://docs.maintainerr.info/configuration/).

Immich brings database, thumbnail and machine-learning workloads. Paperless adds
OCR and stores sensitive documents. Keep both outside the default media profile
and give each independent resource and recovery tests. Syncthing versioning is
useful protection against some file changes, but synchronization does not
replace an independent backup. AdGuard Home should run on a host whose
availability fits the household's DNS needs. Scrutiny adds SMART history and
presentation; isolate device collection privileges and verify the actual
disk/USB bridge supports the needed information. Existing smartd is a reasonable
first step for a single disk.
[Immich requirements](https://docs.immich.app/install/requirements/),
[Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx),
[Syncthing versioning](https://docs.syncthing.net/users/versioning.html),
[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome),
[Scrutiny](https://raw.githubusercontent.com/AnalogJ/scrutiny/master/README.md).

## Access, storage and desktop performance

Add an optional private TLS reverse-proxy integration. Authelia is a candidate
for browser authentication, using supported proxy integrations. Keep application
API authentication and validate media clients separately. Test direct-backend
bypass, trusted headers, WebSockets and byte-range streaming before advertising
single sign-on support for a service. Hostnames, certificates and network access
policy belong to the consuming host.
[Authelia proxy integrations](https://www.authelia.com/integration/proxies/introduction/).

Retain selective VPN routing. Extend the existing privacy policy to any new
service by identifying its external requests and local API dependencies.
Announcement clients, acquisition tools and cross-seed may combine both. Test
proxy or namespace routing without breaking their access to local managers.
Continue using vpn-confinement for enforcement and user-provided nix-seal files
for secrets. The [VPN documentation](../vpn.md) owns the current routing
contract.

Performance work should begin with measurements on the target desktop:

- Measure idle memory, CPU, disk wakeups and background network requests.
- Keep application databases on SSD. Put downloads and their library on the same
  filesystem where hardlink imports are intended.
- Measure direct play before tuning transcoding. Select acceleration for the
  actual GPU and supported codecs, then test fallback and tone mapping.
- Bound transcode and artwork caches. Do not assume a RAM-backed cache is safe
  without a memory budget.
- Stagger scans, subtitle searches, quality synchronization, backup checks and
  thumbnail work. Apply per-service concurrency limits; low CPU/IO weights alone
  do not bound memory or storage use.
- Add free-space monitoring on the actual mounted media filesystem, with
  separate pause and resume thresholds. Pause supported download clients before
  exhaustion and notify the operator. Do not free space by silently deleting
  media or backups.
- Reserve backup capacity on the shared 4 TB drive through the host's storage
  policy. Verify the filesystem and existing data before choosing quotas. Keep
  another independent destination for data requiring disk-failure recovery.

Jellyfin documents hardware-dependent acceleration support. Treat its supported
configuration as the starting point, then record CPU/GPU utilization, startup
latency and cache growth for representative files on the actual host.
[Jellyfin hardware acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/).

## Implementation order and acceptance evidence

1. Complete Prowlarr, Arr and downloader reconciliation, usable Recyclarr
   policies, Jellyfin libraries/accounts and Seerr request policy. Add a local
   request-to-download-to-import-to-playback fixture alongside the modules.
2. Add consistent backup hooks and isolated state restoration before storing
   valuable state. Add disk-pressure handling, Gatus and private ntfy alerts.
3. Add a generated dashboard and optional private access integration. Implement
   host-selected hardware profiles and publish measured results with the test
   hardware and workload stated.
4. Complete optional players, then add autobrr/cross-seed, a selected book
   workflow or channel archiving where needed.
5. Add photos, documents, cleanup and other host services individually. Require
   packaging, access, resource and recovery evidence for each.

Required CI should use local fixtures and disposable test credentials. Cover
repeated application of configuration, partially available dependencies,
credential rotation, denied access, unavailable/full storage, restart, managed
object removal policy and restore. Exercise fresh installation and upgrades from
representative saved state. Browser checks should prove onboarding and account
permissions. Real provider tests and GPU benchmarks should be explicit separate
checks because they depend on user accounts or hardware.

Keep evaluation, builds and runtime results separate. A running daemon, passing
HTTP probe or manual filesystem hardlink does not prove the application
workflow. This research inspected source and documentation; it did not execute
upstream tests, benchmark the desktop or establish new runtime coverage.
Documentation validation for this change should not be reported as service
validation.

## Implementation follow-up

During implementation, inspecting Bazarr's settings handler found that it reads
form-encoded updates. The inspected nixarr script sends JSON, so its successful
HTTP response does not establish that the requested settings were saved. The
homelab adapter uses form data and tests the resulting settings. This corrects
the earlier source-level inference about that peer's connection synchronization.
[Bazarr settings handler](https://github.com/morpheus65535/bazarr/blob/master/bazarr/api/system/settings.py).
