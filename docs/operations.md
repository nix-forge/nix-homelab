# Operations and recovery

Enable `homelab.operations.enable` to publish
`/etc/homelab/state-inventory.json`. The inventory derives enabled applications'
state directories from native NixOS options. It does not enable a backup
scheduler or any network service.
[The operations example](../examples/operations.nix) connects the optional
features to host-provided nix-seal files and an existing native Restic job.

## Consistent recovery copies

Set `homelab.operations.backup.job` to a root-owned `services.restic.backups`
job. The consuming host supplies its destination, password file, schedule,
maintenance policy and independent recovery material. Existing host paths and
prepare/cleanup hooks are retained.

Before Restic reads files, the integration records active writer units, stops
those writers, resolves DynamicUser state symlinks, and copies directories with
ownership, modes and timestamps into private staging. It restarts only the
previously active writers before the network backup begins. A manifest records
original paths and the copies' relative paths. Systemd cleanup also resumes
writers after an interrupted staging command. Failure to copy a required state
directory fails the backup; a partial copy is not presented as successful.

Staging defaults to `/var/lib/homelab-recovery`, mode 0700. It needs enough free
space for application state; reflinks reduce copies where the filesystem
supports them but are not assumed. Cleanup removes staging after the job. Keep
this path outside all source trees and beneath trusted, non-writable ancestors;
a private leaf inside a media-group-writable directory is insufficient. Do not
manually restart writers during their short maintenance window. A machine power
loss still needs ordinary host recovery; the integration cannot run cleanup
while the host is offline.

Review the generated inventory before enabling backups. Add every writer and all
separately configured queue or metadata directories through
`homelab.operations.state.<name>.paths` and `.units`. Inventory defaults cover
the original media services and the optional autobrr, cross-seed, Komga, Kavita,
Shelfmark and Pinchflat state, plus enabled Recyclarr, ntfy and Gatus state.
Integration ownership directories are included automatically, and their service
and timer units stop alongside application writers to prevent API mutations
during staging. Recyclarr’s timer is stopped for the same reason. Media
payloads, host secret catalogs, external databases, and caches are separate
decisions. Immich and Paperless include their native media/document directories
and writers. Immich requires a matching logical PostgreSQL export when backup
integration is enabled. Paperless's default SQLite database is included with its
state; declare `paperlessDatabase = "postgresql"` when a private environment
file selects an external database. Public native DBHOST settings are detected
automatically.

Configure explicit database destinations in the host:

```nix
homelab.operations.postgresql.immich = {
  database = "immich";
  local = true;
};
# For a remote database instead: local = false; host = "database.example";
# user = "backup_operator"; passwordFile = "/run/nix-seal/system/secrets/pgpass";
# caFile = "/run/nix-seal/system/secrets/database-ca";
```

The dump runs after stopping application writers and before copying their state.
Local exports use the postgres operating-system account and peer authentication;
remote exports use a systemd credential containing a pgpass file and verified
TLS against the configured CA. A failed dump aborts the backup and resumes
writers. The database server stays running. Host-owned database names, roles and
extensions must exist already. Restoration preserves archived ownership and
permissions; use an administrative restore login capable of creating those
objects, including the application’s extensions.
`/etc/homelab/database-exports.json` records the non-secret export contract;
credentials never enter dumps' filenames or process arguments. A database shared
with other writers needs those writers in the inventory too. Matching a database
name does not prove the selected server is correct; validate the host connection
before depending on it.

A `state.<name>.prepareCommand` can create a host-specific export or filesystem
snapshot after all writers stop. Failed prepare commands fail staging. Keep the
result under declared state paths and read any credentials from runtime files.
The built-in copy includes configured media originals: budget capacity and
maintenance time for them, or use an explicitly reviewed filesystem snapshot
strategy through the host hook. Reflinks help only on supporting filesystems.

After extracting a trusted backup into an empty directory, stop every inventory
writer and timer and restore the database into its existing host-created target:

```sh
homelab-restore-postgresql immich /srv/restore-drill/path/databases/immich.dump --replace
```

This attended command requires the explicit `--replace` argument, refuses active
writers, and performs a transactional `pg_restore` with the archived ownership
and permissions. It replaces objects in the selected database; use an isolated
restore host first. Restore media/state directories from the same recovery copy
before resuming writers. Preserve the matching PostgreSQL/application revisions,
database roles, extensions and nix-seal recovery material. Immich needs its
vector extension and Paperless needs its document originals; a SQL dump alone is
incomplete.

A restore drill should use an empty directory on an isolated machine with the
same package revision, compatible service identities, and user-provided secrets:

```sh
restic-homelab check --read-data-subset=5%
restic-homelab restore latest --target /srv/restore-drill
```

Inspect `manifest.json` under the restored staging path. Stop all listed
writers, restore each copied directory to its recorded original location with
ownership preserved, and restart services in dependency order. Establish
DynamicUser state directories using the matching NixOS generation before
restoring them; old dynamic numeric IDs are not a portable ownership contract.
Maintainerr also requires the original dedicated service UID when restoring its
private state; retain that assignment in the host repository. Verify database integrity, application users and
settings, and a permitted sample playback. A restored torrent queue also needs
its matching download payload or an attended recheck. Keep automatic acquisition
paused during validation. Never overwrite a live directory as a casual
verification step.

The operations VM test performs a real encrypted Restic backup, full data check,
restore and SQLite content/integrity verification. It also tests writer restart
on staging failure, logical PostgreSQL export/restore and recovery of a native
ntfy account with its cached notification. This is a recovery-mechanism fixture;
it does not establish that every application's schema migration or external
database restores.

## Optional Arr PostgreSQL

Native SQLite remains the default. Select PostgreSQL only when the host has a
reason to operate it and a verified recovery path:

```nix
homelab.operations.enable = true;
homelab.operations.arrPostgresql.services = [ "sonarr" "radarr" ];
```

Enable the corresponding applications separately. Each selected application gets
its own unprivileged PostgreSQL role, main database and log database.
Connections use the local Unix socket and peer authentication; no database
password is created or embedded. Database ownership is established before
application start. Logical exports for both databases are added to the
operations backup contract. Native PostgreSQL settings remain available for host
tuning; the profile does not claim a measured improvement over SQLite.

The startup guard refuses existing SQLite database files, including state
reached through a DynamicUser symlink. It neither converts nor deletes them. To
migrate, stop the application and integration timers, retain a verified SQLite
recovery copy and the matching lockfile, and use the application's documented
migration procedure against a separate PostgreSQL target. Verify API settings,
users, managed titles and queue connections before cutover. Only after
validating that migration should the host add that application to
`homelab.operations.arrPostgresql.migratedServices`. This acknowledgement
disables the guard for that application; it does not run a migration. Keep the
old copy until a PostgreSQL backup and isolated restore have passed. Switching a
NixOS generation alone does not reverse database schema or backend changes.

The PostgreSQL VM asserts that native Sonarr and Prowlarr report PostgreSQL
through their authenticated status APIs, checks separate database ownership and
absence of cluster privileges, and tests refusal to silently abandon SQLite
state. PostgreSQL extension compatibility and restored roles remain part of the
host's upgrade drill.

## Storage pressure

`homelab.operations.pressure` checks available bytes on the configured download
directory's filesystem. It verifies required mountpoints on every run; missing
mounts or an absent directory trigger the pause policy instead of measuring a
parent filesystem. Tune `pauseBytes` for simultaneous download, unpack, import
and backup working space. `resumeBytes` must be higher to avoid repeated
toggling. The timer runs a minute after completion of the preceding check.

The guard supports qBittorrent v5 and SABnzbd. qBittorrent's runtime credential
file is a JSON object with `username` and `password`; SABnzbd's file is its raw
API key. These user-provided files are loaded through systemd credentials. API
keys are sent in request bodies, redirects are rejected, and errors omit private
response bodies. Use trusted private endpoints; a VPN-confined qBittorrent URL
must use its host-reachable namespace address.

Only torrents the guard stopped are resumed; already stopped torrents and
seeding torrents are left alone. SABnzbd's global queue is resumed only if this
guard paused it. The ownership journal survives timer restarts, and API failures
retain ownership for retry. An unavailable API cannot be paused: monitor this
unit's failure and keep the downloader's own free-space limit enabled. A process
crash between a successful pause and journal persistence can leave a download
paused, which requires operator attention rather than an unsafe automatic
resume.

Applications do not expose who last pressed pause. To take manual ownership
while pressure is active, disable the pressure timer first and remove that
client's ownership entry from the private
`/var/lib/homelab-storage-pressure/state.json` before managing its queue. Do not
run a second controller against the same queue. This is a capacity guard, not a
quota, disk-health detector or guarantee against hot-unplug during a write.

## Health, alerts and dashboard

An enabled operations profile installs `homelab-doctor`. Run it as root when
VPN namespace or protected filesystem checks need that access:

```sh
sudo homelab-doctor
sudo homelab-doctor --json
```

Exit status 0 is healthy, 1 degraded, 2 unsafe, and 3 inconclusive. The doctor
checks required mounts and free space, performs a temporary cross-directory
hardlink, reads declared systemd job results, verifies backup-marker freshness,
and rejects a local Restic repository on the staging filesystem. When VPN is
enabled it checks the newest WireGuard handshake and resolves
`monitoring.health.vpnDnsProbeHost` inside the namespace. It also inspects
declared loopback endpoint ports with `ss` and reports a non-loopback listener
as unsafe. Temporary hardlink files are removed even after failure.

The backup marker proves only that the configured systemd backup unit completed
successfully within policy. It does not replace `restic check`, an isolated
restore, or provider-side repository monitoring. A remote repository cannot be
checked for filesystem separation. Missing privileges or unavailable tools are
reported as inconclusive, not healthy. The loopback HTTP health endpoint keeps
its smaller read-only check set and does not run network probes.

Enabled core applications populate endpoint defaults for optional Gatus checks
and Homepage links. Override `healthUrl` independently of the dashboard `url`.
Default root-page probes establish HTTP availability; they do not establish an
authenticated workflow. Declare useful application health APIs and conditions
rather than relying on a login page returning HTTP 200. Both listeners default
to loopback with no firewall opening. Homepage gets no Docker socket or
application API credentials. Set native allowed-host and URL options when a
private reverse proxy is added. Dashboard endpoint URLs must be reachable by the
browser; use the private proxy URL when the viewer is on another machine.

ntfy defaults to loopback, `auth-default-access = "deny-all"`, disabled signup,
a 24-hour message cache and bounded attachments. Provision its users, topic ACLs
and tokens through a nix-seal environment file (`NTFY_AUTH_USERS`,
`NTFY_AUTH_ACCESS`, `NTFY_AUTH_TOKENS`); provision a separate publish-only token
for Gatus. Use a subscriber identity that cannot publish. An empty credential
configuration intentionally allows nobody. The example passes Gatus's token
through environment substitution and enables failure and recovery notifications.
The host must verify authenticated delivery; ntfy health alone does not prove a
subscriber receives messages. Keep notification text free of sensitive media
names and request details.
[ntfy access configuration](https://docs.ntfy.sh/config/),
[Gatus notification configuration](https://github.com/TwiN/gatus#configuring-ntfy-alerts).

## Private access

`homelab.operations.access` configures native Caddy and Authelia together.
[The complete example](../examples/operations.nix) supplies each required input
through user-owned runtime files: certificate chain and key, the Authelia user
YAML database, JWT/session secrets and storage encryption key. This module never
generates replacement user credentials. Declare the host's private cookie domain
beneath a registrable suffix (for example, `homelab.home.arpa`), address and
allowed interfaces; its DNS and certificate trust remain host/client
responsibilities. Certificates must cover the authentication portal and every
protected backend hostname.

`backends.dashboard.port = 8082` creates `dashboard.<domain>` and protects it
with two-factor authentication by default. The `auth.<domain>` portal is served
without recursive forward authentication. Access defaults to deny; each declared
backend has an explicit policy and optional subject restrictions such as
`subjects = [ "group:media" ];`. The private user YAML contains Argon2id hashes,
display names, email addresses and groups. Provision it through nix-seal, then
restart Authelia for user or password rotation. Password-reset writes are
disabled so the runtime credential remains read-only. A single-host filesystem
notifier records enrollment links under the private identity state directory;
retrieve those through the host administrator when enrolling a second factor.
The native Authelia notifier settings remain available for user-provided SMTP
delivery.

Caddy binds only the declared private address; HTTP redirects and its local
unauthenticated administration API are disabled. NixOS configuration changes
restart Caddy through the native module. The host opens HTTPS only on explicitly
selected interfaces. Generated backend rules drop non-loopback traffic even if
another module accidentally opens the same firewall port. Each backend’s `unit`
selects its existing systemd service; dashboard and health map to Homepage and
Gatus, while other names default to the same service name. Enable the actual
service separately and override `unit` for names such as `immich-server`. These
units, Caddy and Authelia stop when the nftables service stops, so losing the
guard cannot expose an accidentally widened listener. Keep actual backend
listeners on loopback as well. Client-provided identity headers are removed
before authentication. The host itself remains a trusted boundary; internal
application API clients still use native application authentication.

Sessions expire after one hour or five minutes of inactivity, and the in-memory
session provider invalidates them on restart. Persistent identity state is
included automatically in recovery; retain its encryption key and user catalog
through the host's nix-seal backup procedure. Neither this module nor its tests
claim successful client certificate installation or actual second-factor
enrollment on the deployment host.

The access VM uses the real native Authelia and Caddy services with disposable
fixture credentials. Its assertions cover anonymous and forged-header rejection,
authenticated access, direct backend denial even with an accidentally open port,
absence of the Caddy administration API, and session invalidation after restart.
Its one-factor fixture isolates the proxy/session contract; production backends
default to two factors. Native media clients, WebSockets and range requests need
application-specific compatibility checks before placing them behind this gate.
[Authelia Caddy integration](https://www.authelia.com/integration/proxies/caddy/).

### Operational health

Enabling monitoring also enables a loopback-only `/health` endpoint on port 9086
and registers it with Gatus. It returns only boolean backup, storage and job
status. The backup timestamp updates through systemd `OnSuccess` after the full
Restic unit succeeds; missing, future or older-than-36-hour timestamps fail.
Configure `homelab.operations.monitoring.health.backupMaxAgeSeconds` for the
host schedule. Failed backup, integration or pressure units fail job health.
Storage health checks the pressure policy's actual required mounts and available
space. Tune its thresholds for the host disk. This detects failed units and
stale backups; it does not infer successful provider delivery from a running
service. Set `monitoring.health.enable = false` to omit this endpoint.

The optional HTTP applications also populate Homepage using their native ports.
Their generic web checks accept a page, redirect or authentication challenge
(200, 302, 303, 307, 308, 401 or 403), using Gatus's documented
[`any` condition](https://github.com/TwiN/gatus#conditions). These checks
establish listener availability, not successful sign-in or provider access.
Immich uses its read-only server ping; Maintainerr expects an anonymous 401 at
its protected proxy. Cross-seed has a dashboard API link but no automatic HTTP
probe because its authenticated daemon API needs a host-owned check. Set an
endpoint's `monitor = false` to retain its dashboard link while managing its
probe separately, or supply `healthUrl` and `conditions`. Credentials belong in
runtime Gatus configuration, never dashboard links. Override endpoint URLs when
changing the native listener from loopback to a specific host address.

Pressure health remains degraded throughout the guard's pause/resume hysteresis.
A successful guard run publishes only a `paused` or `ready` marker; queue IDs
and credentials stay private. A missing marker or one older than three minutes
also fails health, so a stalled timer cannot leave an old healthy result
indefinitely.

If the host overrides the native one-minute pressure timer interval, adjust
`monitoring.health.pressureMaxAgeSeconds` (default 180) to allow its interval
and execution time.

The operations example includes a logical export when Immich uses its native
local PostgreSQL socket. Remote Immich and Paperless databases need an explicit
matching export and their documented runtime authentication inputs.
