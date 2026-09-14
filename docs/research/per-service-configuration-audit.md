# Per-service configuration audit

Reviewed: 2026-09-12; second pass: 2026-09-13. Scope: `nix-homelab` at
`59d6cb9a4a0038a671f5d9115e7bd902f1ff197e`, with the current working tree
read-only inspected. This is design and source research, not an activation,
security assessment, benchmark, or proof that an upstream API remains stable.

## Answer

A high-quality deployment treats every application as an opt-in, privately
reachable component of a workflow rather than as an independently exposed web
UI. It must give each writer a deliberately scoped, mounted storage path;
install credentials only at runtime; reconcile only declared API resources;
bound background work; and recover its state in an isolated restore drill.
The service modules already make a useful start: loopback defaults, shared
media storage with mount checks, runtime credential inputs, an optional
reconciler, VPN confinement, and an operations inventory are present. The main
remaining work is split between reusable configuration still missing for some
optional services and deployment evidence that cannot be fabricated in a
module. The former includes safer acquisition defaults, stronger service API
authentication, and declarative library/account adapters where upstream APIs
are stable. The latter includes real provider connections, identities,
certificates, hardware, retention, restore and whole-workflow tests.

The recommendations below deliberately do **not** authorize public admin UIs,
plaintext secrets, broad device or filesystem access, automatic deletion, or
unbounded automation. Hostnames, identities, provider accounts, certificates,
GPU selection, mount points, backup targets, and retention are host policy and
must remain outside this reusable module.

## Implementation follow-up

Implemented on 2026-09-13 in the working tree that followed this audit. The
audit tables below remain the source-review snapshot; this section records what
was subsequently made observable. “Host” means the reusable repository now
requires an explicit production-readiness acknowledgment and documents the
live acceptance work. It does not claim that a real provider, GPU, disk, client,
certificate or backup destination was tested.

| Area | Reusable implementation and disposable evidence | Remaining host evidence |
| --- | --- | --- |
| Sonarr, Radarr, Lidarr and Prowlarr | Authenticated schema-checked reconciliation supports roots, distinct torrent and optional Usenet clients, safe media-management policy, metadata-preserving naming, named profile lookups and Prowlarr application links. Bootstrap/managed drift, idempotence, unknown fields, retries and secret rotation are tested. Recyclarr supplies reviewed 1080p and optional 4K policies without deleting unmanaged formats. | Real indexers and provider accounts; an episode and album import; provider rate limits; measured refresh cadence. |
| Bazarr | Form-encoded settings, manager keys, language profiles, monitored-only scheduling and bounded concurrency are reconciled. Its service can write beside library media but cannot write downloads; both settings and mount behavior are tested. | Real subtitle provider credentials and a permitted subtitle search. |
| Seerr, Jellyfin, Navidrome and Audiobookshelf | Reconciliation covers onboarding, libraries, restricted users, password rotation, Seerr roots/profiles/quotas, bounded Jellyfin encoding intent, Navidrome scans/cache/transcoding and separate podcast writes. VMs exercise a Seerr-to-Radarr-to-qBittorrent-to-Jellyfin request/playback path and independent audio playback/progress. | Real client compatibility, Jellyfin hardware transcode/fallback/cache measurements and household account policy. |
| qBittorrent | Runtime WebUI credentials, VPN binding, DNS/IPv6 fail-closed behavior, v5 queue/peer/upload limits, private storage, low-space hysteresis and restart/rotation are tested in VMs. | Real provider handshake/throughput, tracker-specific seeding ratios and optional port forwarding. |
| SABnzbd and NZBGet | Runtime credentials, strict provider certificate verification, categories, 20 GiB reserve, bounded cache/PAR/retry/post-processing policy, safe unhealthy-job behavior and restart rotation are configured and tested without a provider. | A permitted NNTPS account or local protocol-faithful TLS fixture, article repair/import and provider connection limits. |
| Recyclarr, autobrr, cross-seed and Unpackerr | Non-destructive quality sync, bounded filters, authenticated named clients, strict cross-seed matching/recheck/hardlinks and single-worker extraction are covered by API or VM tests. | Actual announcement/indexer accounts and provider rules; confirm each selected workflow with permitted content. |
| FlareSolverr, Shelfmark and Pinchflat | Private listeners, scoped media paths and browser/download worker limits are configured; readiness makes provider and retention ownership explicit. | Demonstrated need, egress route, administrator/provider onboarding, archive formats and retention choice. |
| Komga and Kavita | Both receive private listeners, state-only writes and read-only libraries; Komga has a restricted-reader scan/page/progress VM. Readiness requires the host to choose and validate its reader. | Selected real formats/client for the chosen reader; Kavita token/account workflow and isolated state restore. |
| Maintainerr | A pinned native package, dedicated identity, resource limits, no media mount, authenticated nginx gateway and backend-bypass firewall are VM-tested. No deletion rules are configured. | Reviewed collections, exclusions/grace periods and restore-before-delete proof with disposable media. |
| Immich and Paperless-ngx | Private listeners, one-worker background/OCR policy, separate state, explicit database exports and original-plus-database restore VMs cover Immich and both Paperless database modes. | Real storage mount/capacity, accounts/mobile clients, ML hardware budget and upgrade rehearsal using representative host state. |
| Syncthing, AdGuard Home and Scrutiny | Private control planes, no default discovery/relay/DHCP/firewall exposure, mount dependencies, versioned-folder/upstream/auth/device readiness checks and conservative collector defaults are present. | Real peer/device identities, two-device conflict/deletion recovery, reliable LAN DNS design and verified SMART bridge/alert behavior. |
| Tinyproxy, PostgreSQL, InfluxDB, Restic, Gatus, ntfy and Homepage | VPN-confined CONNECT-only proxying, local least-privilege PostgreSQL, state inventory, stopped-writer staging, logical exports, Restic restore, private health/notification/dashboard defaults and pressure monitoring are implemented. | Tagged real-indexer proxy route; chosen backup destination/retention; Influx retention/restore; authenticated alert delivery and dashboard entry-point policy. |
| Caddy, Authelia and Maintainerr nginx | Runtime TLS/auth credentials, disabled Caddy admin API, stripped identity headers, deny-by-default access and direct-backend rejection are covered by access VMs. | Real DNS/cert lifecycle, enrollment/recovery, client compatibility and remote-network bypass testing. |

### Second-pass corrections and design decisions

The second pass checked current upstream documentation against the package
versions in the lock rather than assuming that upstream defaults were safe or
that every missing value belonged to the host.

| Finding | Repository decision |
| --- | --- |
| NixOS already changes Navidrome's upstream insights-collector default from enabled to disabled. [Navidrome documents the upstream option](https://www.navidrome.org/docs/usage/configuration/options/); the locked NixOS module defaults it off. | State the disabled value explicitly in homelab policy and evaluate it, so a future native-module default change cannot silently enable telemetry. |
| [Unpackerr recommends](https://unpackerr.zip/docs/install/configuration/) a one-minute start delay, five-minute retry delay, one parallel extraction and three retries; deleting originals is unsafe for torrents. | Make the cadence and debug policy explicit in the reusable module. Keep original deletion false in declared manager examples and keep each watched path narrow. |
| In locked Shelfmark 1.3.15, [the Usenet completion default is `move`](https://github.com/calibrain/shelfmark/blob/v1.3.15/docs/environment-variables.md), which removes the completed downloader job after import. The same version supports TLS verification, non-expanding Prowlarr search and a non-destructive torrent action. | Default to `copy` for Usenet, `keep` for torrents, verified certificates and no automatic category expansion. Credentials remain in the runtime environment file. |
| [Audiobookshelf API keys](https://audiobookshelf.org/docs/documentation/server-management/api-keys/) are named, revocable, optionally expiring and inherit one user's permissions. They are intended for server-to-server automation. | The reconciler already accepts a bearer API key file. Production hosts should create a dedicated administrative automation identity/key after bootstrap instead of retaining a human password for recurring reconciliation. Bootstrap login remains supported for disposable first-run tests. |
| qBittorrent 5.2 adds [single API-key authentication](https://github.com/qbittorrent/qBittorrent/wiki/API-Key-Authentication-%28%E2%89%A5v5.2.0%29), but not every Servarr/Shelfmark client supports it. | Do not replace the interoperable runtime WebUI credential globally. Prefer the API key for clients that explicitly support it, and keep rotation and least privilege as an integration-specific contract. |
| Komga, Kavita and Immich have useful application APIs, but their schemas and onboarding flows are versioned application state rather than stable NixOS settings. | Add adapters only when they can be pinned, schema-checked, idempotent and non-deleting. Until then, readiness must describe host ownership rather than pretending a listener is a complete deployment. |
| Pinchflat supports Basic authentication through its secret environment file, while Scrutiny has no native authentication. | Keep both loopback-only. Require Pinchflat's production secret file to carry its application secret and Basic-auth credentials; put Scrutiny behind the authenticated access layer before any non-loopback reachability. |

This changes the definition of “complete”: an enabled unit and a successful
HTTP response are necessary but insufficient. A reusable module is complete
only when it owns safe portable policy and exposes explicit inputs for the
remaining site choices. A deployed service is complete only after those inputs,
an authenticated dependency check, recovery evidence and its integration edge
have been exercised.

Internally, one service catalog now owns application identity and integration
metadata. Optional policy is separated into common storage/hardening,
automation, libraries, private archives, infrastructure, quality and Maintainerr
modules. Native `services.*` options still own application configuration; the
catalog does not duplicate their schemas.

## Findings and sources

### Local observations

The public module imports all core and optional modules, but only enabling an
individual `homelab.apps.*` or `homelab.optional.apps.*` option starts a
service ([module imports](../../modules/default.nix), [core options](../../modules/apps.nix),
[optional options](../../modules/optional/default.nix)). Core UIs default to
closed firewalls and most to loopback; qBittorrent, SABnzbd and NZBGet expose a
host-link address only when put in the VPN namespace
([qBittorrent](../../modules/downloaders/qbittorrent.nix),
[SABnzbd](../../modules/downloaders/sabnzbd.nix),
[NZBGet](../../modules/downloaders/nzbget.nix)). This is a configuration
observation, not a runtime penetration-test result.

Storage uses a dedicated root, separate downloads and library descendants, a
shared group, required mount checks, writer-only download access, manager
access to one root (which preserves same-filesystem hardlinks), and read-only
player library binds ([storage module](../../modules/storage/default.nix)).
The optional module applies low CPU/IO weights and tighter limits to selected
services; FlareSolverr and Immich also get explicit memory/concurrency defaults
([optional defaults](../../modules/optional/default.nix)). These are sensible
baselines but do not establish the desktop's actual RAM, I/O, GPU, or thermal
headroom.

The optional reconciler passes `_secret` values by systemd credentials, has
bootstrap and managed modes, validates selected API inputs, limits itself to
declared resources, and says neither mode deletes undeclared objects
([integration module](../../modules/integration/default.nix)). Operations can
inventory state, stop writers, stage recovery data, export PostgreSQL, probe
endpoints, and apply pressure handling ([operations module](../../modules/operations/default.nix)).
Those mechanisms do not, by themselves, prove every application's backup is
consistent or every HTTP check is authenticated.

### Source basis and comparable deployments

Service facts below were retrieved on 2026-09-12 from the linked official
documentation or official source. The selected package set is pinned by this
repository's lock file; package freshness and exact package versions must be
rechecked at the lock revision before a stateful upgrade. The earlier
[media-services research](media-services.md) records the then-selected package
versions and upstream releases, while [service-completeness](service-completeness.md)
records the already-inspected integration evidence.

Two maintained Nix examples are useful implementation references, not
authoritative product requirements: [nixarr at
`282ce99`](https://github.com/nix-media-server/nixarr/tree/282ce99b31d52d72cca281e3d26d3dd267946800)
reconciles Arr/Prowlarr objects, and [nixflix at
`d77a386`](https://github.com/kiriwalawren/nixflix/tree/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b)
has VM fixtures for Arr/download clients, Jellyfin, Seerr and optional
PostgreSQL.

The 2026-09-13 second pass also inspected current nixarr at
[`7e1dab8`](https://github.com/nix-media-server/nixarr/tree/7e1dab87509bee3092a812012a5efa72aaf3963e) and the
pinned nixflix revision's host, naming, media-management, delay-profile,
root-folder and Prowlarr modules. Nixflix usefully makes naming and the full
media-management surface explicit. This repository adopts the portable parts:
metadata-rich names, a free-space floor, hardlinks, recycle retention,
conservative rescans, schema-derived provider defaults and complete downloader
connections. It deliberately does not copy nixflix's removal of undeclared
roots, delay profiles, indexers or applications. Absence from Nix is not enough
evidence to destroy application state. Native NixOS Servarr options already
disable in-app updates and analytics at the selected nixpkgs revision, so those
values remain at their authoritative native-module seam instead of being
duplicated through the API reconciler.

Two bounded non-Nix community comparisons were source-inspected at pinned
revisions. [Saltbox at `7a22a30`](https://github.com/saltyorg/Saltbox/tree/7a22a30c1e6153ae21bdc15f9c13598547455984)
is an Ansible/Docker media-server project with separate application roles. Its
role separation is worth borrowing as a boundary: proxy/authentication, backup,
network and an application should remain independently configurable and tested.
[home-media-server at `ae2b3fc`](https://github.com/william-opie/home-media-server/tree/ae2b3fcc4c4f69985049e3cd4b1b5c98e6dd2515)
is a Compose stack that has per-container health checks and Renovate with digest
pinning ([configuration](https://github.com/william-opie/home-media-server/blob/ae2b3fcc4c4f69985049e3cd4b1b5c98e6dd2515/renovate.json)). Borrow the explicit
health/update-review pattern, not its Compose `ports` publication, long-lived
environment API keys used by dashboard labels, or automatic restart policy as a
substitute for an upgrade/restore test. Official non-Nix deployment material,
such as [Immich's Docker Compose install](https://docs.immich.app/install/docker-compose/)
and [Paperless-ngx's Docker Compose setup](https://docs.paperless-ngx.com/setup/),
remains the authority for their supported environment contracts. This is a
small comparison set, not an endorsement of any deployment or its defaults.

### Core service matrix

"Current" means an observed reusable default, not a promise of configured UI
state. "Gap" is the work required before describing the service as complete.
The [integrated-media example](../../examples/integrated-media.nix) deliberately
declares Arr roots/download clients, Prowlarr links, Bazarr settings, Jellyfin
libraries/users and Seerr destinations; the [audio example](../../examples/audio.nix)
does the same for Navidrome and Audiobookshelf accounts/libraries. They prove
the reconciler can express those host-selected objects, not that the reusable
defaults impose them or that a live deployment has succeeded.

| Service | Secure, feature-rich configuration should provide | Current / remaining gap |
| --- | --- | --- |
| Sonarr | Private API/UI; a TV root; a unique downloader category; Prowlarr connection; quality/upgrade policy; completed-download handling; hardlink import; bounded refreshes. [Servarr](https://wiki.servarr.com/sonarr) documents its role and configuration. | Loopback and state-write confinement exist ([Arr module](../../modules/arrs/default.nix)); the integrated example declares a root/client. The reusable default correctly omits that host policy; real episode import, UI-drift and pressure evidence remain. |
| Radarr | The analogous movie root/category/indexer policy, custom formats, size limits, and explicit upgrade ceiling. [Radarr documentation](https://wiki.servarr.com/radarr) is the primary product reference. | The integrated example declares root/client resources, while the default confines only. A real movie import, preserved manual object and disk-pressure response remain unproven. |
| Lidarr | A music root, metadata and release policy, distinct category, import path, and deliberately paced library refresh. [Lidarr documentation](https://wiki.servarr.com/lidarr) defines the manager's scope. | The integrated example declares a music root/client/profile lookup; no portable default should select metadata or quality policy. Album workflow and refresh-bound evidence remain. |
| Bazarr | Sonarr/Radarr credentials, language profiles, provider credentials, monitored-only policy, bounded searches/retries, and write permission only beside permitted media. [Bazarr](https://wiki.bazarr.media/) documents provider and language configuration. | Data-directory confinement and integrated-example settings exist; no default chooses language/provider policy or proves subtitle writes. The adapter must use Bazarr's supported form settings semantics, not assume JSON works ([handler](https://github.com/morpheus65535/bazarr/blob/master/bazarr/api/system/settings.py)). |
| Prowlarr | Authenticated indexers, tags/capabilities/categories, Arr connections, and optional per-indexer proxy selection; preserve user-created indexers unless explicitly managed. [Prowlarr](https://wiki.servarr.com/prowlarr) documents application synchronization. | Private binding and example Arr links exist. Actual indexers are intentionally host-selected; validate two-run idempotency, preservation and secret rotation. |
| Seerr | Media-server onboarding; chosen libraries, Arr roots/profiles; least-privilege users, quotas and request/approval policy. [Seerr](https://docs.seerr.dev/) documents the supported integrations; its [request API](https://docs.seerr.dev/api/create-new-request/) distinguishes request from auto-approval permission. | Loopback/restrictive umask and example library/destination declarations exist. Runtime library sync, user policy and a request reaching the intended manager remain unproven; never default to approving all requests. |
| qBittorrent | Authenticated WebUI with CSRF/host-header protection; VPN-bound peer traffic and DNS; save/incomplete paths; category/queue/connection/seeding policy; low-space pause; credential rotation. The selected nixpkgs revision records qBittorrent 5.2.3 in [local package research](media-services.md); use the [upstream API version matrix](https://github.com/qbittorrent/qBittorrent/wiki) and the pinned v5 source when validating these controls. [BitTorrent BEP 3](https://www.bittorrent.org/beps/bep_0003.html) is the protocol reference. | Strongest core default: runtime credential merge, restrictive WebUI options, incomplete path, VPN interface binding, and optional explicit inbound ports. The older v4 API page must not be used to claim v5 option semantics. Missing live tunnel-failure/no-leak, resume, low-space and category handoff tests. |
| SABnzbd | NNTPS with certificate verification, runtime server credentials, categories, incomplete/complete paths, repair/unpack policy, retention, and bounded download/unpack concurrency. [SABnzbd configuration](https://sabnzbd.org/wiki/configuration/) is authoritative. | Loopback/host-link choice, paths, group permissions and a 20 GiB free-space reserve exist ([module](../../modules/downloaders/sabnzbd.nix)); provider settings, TLS proof, categories and post-processing limits are host work. |
| NZBGet | The same provider TLS/RPC/category and storage discipline as SABnzbd, but independently tested; only one downloader should own a category. [NZBGet documentation](https://nzbget.com/documentation/) is primary. | Certificate checking, CA bundle, runtime credential merge, paths, umask and optional confinement exist; no provider/category/restart or safe post-processing evidence. |
| Jellyfin | Private administration, libraries and least-privilege accounts/API keys, scan/metadata cadence, read-only library access, a bounded transcode cache, and host-verified hardware encoding/fallback. [Jellyfin hardware acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/) makes acceleration hardware-specific. | State inventory/health endpoint and example libraries/users exist; no portable default selects accounts or a device. Test direct play, constrained user access, supported transcode, fallback and cache growth before selecting hardware. |
| Plex | A documented account claim/administration flow, private listener/proxy, library and sharing policy, and only verified acceleration devices. [Plex installation](https://support.plex.tv/articles/200288586-installation/) and [secure connections](https://support.plex.tv/articles/206225077-how-to-use-secure-server-connections/) govern account-dependent setup. | Opt-in service and empty acceleration-device default exist ([media module](../../modules/media/default.nix)); no unattended claim should be promised and no user/library/playback evidence exists. |
| Navidrome | Read-only music source, non-root operation, accounts and sharing policy, scan cadence, cache cap and bounded per-user transcoding. [Navidrome security guidance](https://www.navidrome.org/docs/usage/admin/security/) is primary. | Music root, no sharing, non-root enforcement, six-hour scan, 512 MB cache and 2/1 concurrency defaults are provided ([media module](../../modules/media/default.nix)); the audio example declares accounts. Client playback and backup/restore remain untested. |
| Audiobookshelf | Private administration; least-privilege listeners; separate writable podcast downloads; library/scan policy; progress/metadata backup and restore. [Audiobookshelf](https://www.audiobookshelf.org/) documents libraries and users. | Loopback host plus writable podcasts and example library/account declarations are supplied; playback-progress restore and policy evidence remain absent. |

### Optional service matrix

| Service | Secure, feature-rich configuration should provide | Current / remaining gap |
| --- | --- | --- |
| Recyclarr | Reviewed quality definitions/custom formats, storage-aware size limits, preview before sync, explicit ownership, and non-destructive behavior. [Recyclarr sync behavior](https://recyclarr.dev/guide/sync-behavior/) defines pipeline failure behavior; its [custom-format reference](https://recyclarr.dev/reference/configuration/custom-formats/) documents the opt-in deletion control. | A conservative 1080p policy, runtime key files, weekly schedule and no old-custom-format deletion are available ([optional module](../../modules/optional/default.nix)). Add an optional reviewed 4K policy and preview/repeat/UI-drift tests. |
| autobrr | Private API, runtime session/API/downloader credentials, named client connection, narrow filters, category/size/daily limits and duplicate rejection. [autobrr](https://autobrr.com/introduction) documents its event/filter model. | Loopback and low-priority service defaults exist; provider/IRC/indexer setup and a permitted announcement test remain deployment work. |
| cross-seed | Runtime client/indexer credentials, strict matching where false matches are unacceptable, same-filesystem hardlinks, delayed/bounded searches, injection with recheck, and preservation of originals. [cross-seed options](https://www.cross-seed.org/docs/basics/options) and [linking guidance](https://www.cross-seed.org/docs/tutorials/linking) are primary. | Runtime settings file is mandatory; this module deliberately overrides cross-seed's upstream flexible matching default to strict, and sets hardlinks, cadence and read/write bounds. Prove inode sharing, no original modification, and authenticated injection. |
| Unpackerr | Limited downloader paths, one/few extractors, temporary-space budget, retry ceiling, safe cleanup and import test. [Unpackerr configuration](https://unpackerr.zip/docs/install/configuration/) is primary. | One parallel worker, three retries and group-safe modes are set; only enable after proving it is necessary and cannot alter seed data or unrelated paths. |
| FlareSolverr | Private endpoint, intentional egress, minimal browser concurrency, memory/task ceiling, and demonstrated indexer need. [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) warns it operates browser instances. | Loopback and 1/2 GiB memory plus task caps exist. No egress/isolation test or provider-need justification; do not expose it or enable by default. |
| Komga | Private UI, account/role policy, read-only library and separate metadata state, import workflow, and backups. [Komga's library guide](https://komga.org/docs/guides/libraries/) documents per-user library restriction, scans and deletion effects. | Loopback listener and state-only write path exist. Library mounts/accounts/import/playback/restore are host responsibilities. |
| Kavita | The same reader controls, with selected format/client policy and no broad library write access. [Kavita](https://wiki.kavitareader.com/) is primary. | Loopback and state-only writes exist; there is no declared library/account/back-up workflow. Choose it *or* Komga based on tested formats instead of enabling both by default. |
| Shelfmark | Private built-in authentication, separately scoped ingest area, explicitly chosen downloader connection, and reviewed import/link policy. [Shelfmark environment variables](https://github.com/calibrain/shelfmark/blob/main/docs/environment-variables.md) are the primary configuration source. | Loopback/built-in auth and an ingest root exist; credentials, admin onboarding, real acquisition and protected-library handoff are not established. |
| Pinchflat | Private UI, explicit channels/formats/retention, one/few workers, dedicated writable archive directory, and disk budget. [Pinchflat](https://github.com/kieraneglin/pinchflat) is primary. | Loopback and one worker with a library-video output default exist. Channel policy, retention, download recovery and backup are absent. |
| Maintainerr | A private authenticated gateway, least-privilege media API credentials, dry-run/review, exclusions, grace periods and restore evidence before deletion. [Maintainerr access limitations](https://docs.maintainerr.info/configuration/) says it has no built-in login. | The local Podman integration is intentionally separately documented ([Maintainerr note](maintainerr-native-package.md)). A health check expecting gateway authentication is inventory only; prove no backend bypass and keep destructive rules off until recovery is tested. |
| Immich | Separate photo and database backups, constrained thumbnail/ML jobs, private access, account policy, storage on suitable media, and version-compatible upgrade/restore procedure. [Immich requirements](https://docs.immich.app/install/requirements/) and [backup/restore](https://docs.immich.app/administration/backup-and-restore/) are primary. | Loopback and concurrency-one jobs exist; database/storage policy, ML device budget, mobile-client test and isolated restore are not complete. |
| Paperless-ngx | A runtime secret key, private access group, explicit ingestion directory, bounded OCR/task workers, document+database backups, and secure restore. [Paperless configuration](https://docs.paperless-ngx.com/configuration/) is primary. | Environment file is required; loopback, single worker/thread, English OCR and nonrecursive consumption are defaults. Database choice, trusted ingestion, document recovery and account policy still need proof. |
| Syncthing | Explicit device/folder allowlists, encrypted transport/identity handling, versioning/conflict policy, mount dependencies, and an independent backup. The [Syncthing FAQ](https://docs.syncthing.net/users/faq.html) explains why synchronized changes/deletions make it unsuitable as the sole backup even with versioning. | Discovery/relays/default ports are disabled and GUI is loopback, with mount dependencies. Device trust, folder policy, versioning and restore are host work. |
| AdGuard Home | A deliberately reachable DNS listener only when the host can provide it, upstream DNS/privacy policy, admin authentication, query-log retention and recovery plan; DHCP remains opt-in. [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) is primary. | Loopback DNS on 5353, closed firewall and DHCP disabled are safe defaults. It is not a household resolver until binding/firewall/upstream/auth/availability are deliberately designed and tested. |
| Scrutiny | Loopback dashboard/database, minimal SMART collector privileges, supported-device verification, alerting and history retention. [Scrutiny collector example](https://github.com/AnalogJ/scrutiny/blob/v0.9.3/example.collector.yaml) documents collector inputs. | Loopback endpoints and a disabled daily collector default exist. Grant device access only after confirming actual SATA/USB bridge support, then test a harmless collection and alert path. |

### Shared support service matrix

These are actual optional services selected by the current modules, rather than
the VPN-confinement and systemd-timer mechanisms that attach or schedule them.

| Support service | Secure, feature-rich configuration should provide | Current / remaining gap |
| --- | --- | --- |
| SOCKS5 indexer proxy | A host-only, VPN-confined proxy with authentication, proxy-side DNS, no request logging, and explicit Prowlarr tag selection. [Prowlarr](https://github.com/Prowlarr/Prowlarr/tree/develop/src/NzbDrone.Core/IndexerProxies/Socks5) supplies the relevant proxy contract. | The optional Microsocks service binds only to the namespace host link and requires a runtime password ([module](../../modules/indexers/proxy.nix)). The VPN VM verifies authentication, proxy-side DNS, LAN refusal, tunnel failure, and recovery. |
| PostgreSQL for Arr, Immich and Paperless | Local Unix-socket access where possible, distinct roles/databases, least privilege, version-aware migrations, logical dumps and an isolated restore. [PostgreSQL backup documentation](https://www.postgresql.org/docs/current/backup.html) defines dump/restore behavior. | Arr PostgreSQL is opt-in with private roles; operations requires explicit logical exports for Immich and external Paperless databases ([Arr database module](../../modules/operations/arr-postgresql.nix), [recovery integration](../../modules/operations/default.nix)). No benchmark proves it improves this desktop or migrates an existing SQLite state. |
| InfluxDB for Scrutiny | Loopback-only storage, retained-history capacity, backup/restore, and credentials/operator access scoped separately from the dashboard. [InfluxDB backup and restore](https://docs.influxdata.com/influxdb/v2/admin/backup-restore/) is primary. | When Scrutiny's InfluxDB is enabled, its HTTP listener defaults to loopback and its state enters the inventory ([optional module](../../modules/optional/default.nix), [operations inventory](../../modules/operations/default.nix)). Retention, database backup and recovery evidence are host gaps. |
| Restic backup job | A root-owned, encrypted independent repository; application-consistent staging; retention/prune/check policy; credential recovery; and an isolated restore drill. [Restic repository maintenance](https://restic.readthedocs.io/en/stable/045_working_with_repos.html) and [restore](https://restic.readthedocs.io/en/stable/050_restore.html) are primary. | Operations stops declared writers, stages inventory/export data, applies low scheduling weights and injects that staging path into a selected native Restic job ([operations module](../../modules/operations/default.nix)). Destination, schedule, retention, repository credential and successful restore remain host-owned and unproven. |
| Gatus | Private endpoint checks, authenticated checks where appropriate, actionable alert routing, stale-backup/storage/job health and alert-delivery tests. [Gatus configuration](https://github.com/TwiN/gatus#configuration) is primary. | Enabled operations generate loopback Gatus checks from the endpoint inventory plus operational health ([operations](../../modules/operations/default.nix), [health module](../../modules/operations/health.nix)). HTTP availability is not authenticated workflow proof; configure providers and test failure/recovery notifications. |
| ntfy | Loopback/private listener, deny-by-default topic ACLs, runtime credentials, disabled signup, bounded cache/attachments and tested authenticated delivery. [ntfy access control](https://docs.ntfy.sh/config/) is primary. | The module selects loopback, deny-all, disabled signup, 24-hour cache and attachment limits when enabled ([operations module](../../modules/operations/default.nix)). Host policy must supply scoped users/tokens and validate that alerts reveal neither private media nor credentials. |
| Homepage | Private dashboard access, generated enabled-service links, least-privilege widget credentials and no exposed container socket. [Homepage services/widgets](https://gethomepage.dev/configs/services/) is primary. | The module generates an inventory-based view with closed firewall and loopback hostname ([operations module](../../modules/operations/default.nix)). It does not configure widget credentials or prove browser authorization; protect it with the access layer when remotely reachable. |
| Caddy | Private HTTPS bind, runtime certificate/key, disabled admin API, sanitized forwarded identity headers, per-backend auth and direct-backend bypass tests. [Caddy reverse-proxy documentation](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) is primary. | The access module uses private bind/firewall policy, runtime credentials, `admin off`, header stripping, and Authelia `forward_auth` ([access module](../../modules/operations/access.nix)). DNS/cert lifecycle, client compatibility and actual TLS/auth tests are host gaps. |
| Authelia | Runtime secrets and Argon2id user data, deny-by-default policies, two-factor where selected, session/cookie controls, recovery material and proxy integration tests. [Authelia Caddy integration](https://www.authelia.com/integration/proxies/caddy/) is primary. | The local instance is loopback-only with deny default, runtime user credential, short sessions and persistent state inventory ([access module](../../modules/operations/access.nix)). Enrollment, notification delivery, group policy and recovery/rotation drills remain unproven. |
| nginx for Maintainerr | A loopback authenticated gateway, runtime htpasswd, HTTPS before wider exposure, stripped backend authorization header, and firewall proof that unrelated local users cannot reach the backend. [nginx basic authentication](https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html) is primary. | The Maintainerr module configures loopback nginx basic auth, credential loading, a distinct backend port and nftables restriction ([module](../../modules/optional/maintainerr.nix)). Verify rejected unauthenticated/bypass paths and keep Maintainerr deletion rules disabled until restore evidence exists. |

## Shared implementation boundaries

1. **Storage and identities.** Keep downloads and final libraries on the same
   mounted filesystem only when hardlinks are intended. Require the mount before
   creating directories; downloader writers get downloads only, managers get
   the one media root, and players/readers get libraries read-only. Do not put
   application databases, transcode cache, temporary unpack space, photos, or
   documents on a presumed media mount without a capacity and recovery choice.
   Missing mounts must fail starts rather than create a root-disk fallback.

2. **Network and proxy.** Keep every administrative/backend listener loopback
   or VPN-host-link-only. A reverse proxy is host-owned and must enforce TLS,
   authentication/authorization, correct forwarded headers, WebSockets and
   byte-range playback. Test that direct backend access cannot bypass it.
   Application API authentication remains required; proxy SSO does not secure
   native media clients automatically. The local VPN module uses strict DNS,
   IPv6 tunnel-or-disable, endpoint pinning and a host link
   ([VPN module](../../modules/vpn/wireguard.nix)); test successful traffic,
   tunnel failure, DNS and IPv6 leakage rather than treating a running unit as
   proof. Provider port forwarding is a separate provider capability.

3. **Secrets and API ownership.** Use sealed user-supplied runtime files and
   systemd credentials. Never interpolate credentials into Nix, URLs, logs,
   fixtures or command arguments. One named reconciling owner must own each API
   object/field. Bootstrap should create missing declared objects without
   rewriting UI settings; managed mode may update declared fields; deletion
   requires a separately named, reviewed ownership ledger and explicit
   confirmation. Reconciliation needs readiness probes, bounded retries,
   structured redacted errors, locking/no overlap, and secret-rotation tests.

4. **Monitoring, backup, restore, upgrade.** Monitor mount availability, free
   space, unit state, authenticated dependency health, failed reconciliation,
   backup freshness, VPN route health and resource saturation. Alerts must omit
   titles, tokens and private URLs. Inventory every state directory, database,
   library policy and writer unit; make a consistent application export, a
   stopped-writer copy, or a supported online backup before snapshotting. Keep
   backup destinations/retention at the host layer and at least one destination
   independent of the protected disk. Restore into an isolated environment and
   verify API-visible state and a real playback/import, not merely that files
   exist. Before upgrades, read upstream release/migration notes, take a
   restorable backup, stage a representative state copy, and preserve the prior
   package generation for rollback; database migrations may make application
   rollback unsafe.

5. **Desktop resource controls.** Measure idle/peak CPU, RAM, I/O, open files,
   transcode/ML GPU use, cache growth and disk wakeups on representative media.
   Then set per-service CPU/IO weights, memory/task maxima where applications
   need them, database/cache/temp-space budgets, download/repair/scan/OCR/ML
   concurrency, and staggered schedules. Low CPU weight alone does not limit
   memory, storage, or network work. Pause supported clients before disk
   exhaustion; never reclaim space by silently deleting media or backups.

## Acceptance evidence before calling a service complete

- Evaluate a minimal profile and each enabled-service profile. Assert private
  bind/firewall settings, runtime-only secret paths, mount dependencies,
  systemd sandbox exceptions, storage write boundaries, and no Nix-store
  credential references.
- In a disposable VM, prove qBittorrent's intended traffic works only through
  the tunnel, fails closed when the peer/DNS/IPv6 path fails, and that host-link
  access is authenticated. Exercise SABnzbd or NZBGet separately with a local
  TLS fixture.
- Reconcile Prowlarr, each enabled Arr, Bazarr, downloader, Jellyfin/Seerr,
  Navidrome/Audiobookshelf and autobrr twice. Assert no duplicates, intended
  categories/roots/libraries/users, preservation of unmanaged objects, retry
  behavior, and credential rotation. Assert a UI edit follows the documented
  bootstrap/managed rule.
- Execute one request-to-download-to-import-to-playback fixture for each chosen
  media path; check the hardlink inode where applicable, subtitle location,
  unprivileged user denial, direct-play/transcode fallback, restart/resume and
  full-disk pause/recovery. One successful Jellyfin/qBittorrent path does not
  validate Plex, NZBGet, book readers, or photo/document workflows.
- Back up a representative state plus database, deliberately alter it, restore
  to an isolated VM, and verify users, API resources, progress/metadata and
  selected content. Repeat on a package/database upgrade fixture. Keep real
  providers, GPUs, device SMART access and remote proxy tests opt-in because
  they require host-specific accounts or hardware.

## Implication for this repository

Do not add another broad application abstraction. Keep native `services.*`
options as the application owner and use `homelab.*` only for shared policy:
storage, confinement, runtime secrets, declared reconciliation, operations and
safe resource defaults. Derive shared behavior from the service catalog instead
of maintaining parallel service lists. The core Prowlarr/Arr/downloader/player
contract now has reusable integration and disposable evidence; the next API
adapters should be limited to version-pinned, schema-checked, idempotent and
non-deleting Komga, Kavita or Immich operations. Require recovery evidence
before retaining valuable state, and add optional services only after their
access, storage, egress, resource and restore contract is demonstrably met.

## Validation and evidence limits

This second research pass did not contact a provider account, access hardware,
activate a host, benchmark, or perform a production backup or restore. It did
evaluate the optional and complete NixOS configurations and run repository
publication checks; the implementation-follow-up table separately records the
disposable VM evidence from the preceding implementation work. Local source
observations are tied to the named revision and current working tree; unrelated
existing modifications were preserved. Official documentation can change after
the retrieval date, and its guidance does not prove compatibility with this
lock revision.

The peer survey is intentionally narrow: nixarr, nixflix, Saltbox,
home-media-server, and the two official container deployment guides above are
maintained examples, not a census or a security endorsement. This note does not establish exact current upstream
versions for every optional package, browser/client interoperability, supported
GPU/device matrices, provider legality/terms, or safe unattended migration of
existing databases. Those are explicit evidence gaps to close with pinned-source
review and the acceptance tests above before implementation or deployment.
