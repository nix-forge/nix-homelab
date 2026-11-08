# Portable service contracts

Reviewed 2026-10-14. Question: which deployment assumptions prevent reusable
homelab features from working independently with valid native NixOS overrides?

## Findings and decisions

Native NixOS options own application packages, users, pools and listeners. The
homelab layer derives dependent connections from those options and asserts
unsupported combinations. Importing the default module enables no applications.
Host mounts, credential providers, account selection, source pins and historical
migrations remain in consuming configuration.

The source audit used nixpkgs revision
`c59305bab2065cfecc4944690d9eedbb56f3a9fa`. Consumers can follow a different
revision. The findings below describe the inspected interfaces and the changes
made here, rather than guarantees about every future upstream version.

### Shared PostgreSQL

A Unix socket does not eliminate port selection. PostgreSQL uses the port in
its socket filename. Local Arr, AudioMuse, Wardrowbe and recovery jobs now use
the native PostgreSQL port and filesystem socket. The native setup unit calls
`psql` without an explicit host, so this integration supplies `PGHOST` there too.
An explicit operator environment override remains authoritative.
[PostgreSQL connection parameters](https://www.postgresql.org/docs/current/libpq-connect.html),
[pinned native module](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/nixos/modules/services/databases/postgresql.nix).

AudioMuse no longer implicitly selects PostgreSQL 15 for the shared server.
Its optional package override defaults to null. This avoids conflicting package
ownership; it does not perform an upgrade or prove that existing databases are
compatible with another major version. Consuming hosts retain intentional pins.

Keycloak's native JDBC Unix socket URL also includes its configured database
port. Local realm bootstrap now follows the shared server and asserts protocol,
port and socket compatibility. External database provisioning is explicitly
selected and retains native TLS defaults.
[Pinned Keycloak module](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/nixos/modules/services/web-apps/keycloak.nix).

### Effective application topology

FreshRSS exposes a pool, account, virtual host and webserver choice. Its homelab
Nginx integration now has an explicit private listener and follows the selected
pool. An absent local pool creates no dummy PHP-FPM unit. The upstream pool
uses a fixed account despite the public account option, so this integration
asserts matching accounts instead of claiming arbitrary user changes work.
Caddy is unsupported by this listener integration and produces an assertion.
[Pinned FreshRSS module](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/nixos/modules/services/web-apps/freshrss.nix).

Recyclarr needs a reachable base URL and API key for each target. Selecting its
Sonarr or Radarr policy requires the corresponding native service. URLs follow
effective bind addresses, ports and prefixes, including IPv6. Wildcard addresses
are converted to reachable loopback addresses for local clients.
[Recyclarr configuration](https://recyclarr.dev/reference/configuration/basic/).

Homebridge supports several discovery providers. Its managed UI requires Avahi
only when the configured bridge advertiser selects Avahi. Other providers can
run without that daemon.
[Homebridge advertiser documentation](https://github.com/homebridge/homebridge/wiki/mDNS-Options).

### Mutable state and feature extraction

Public Prowlarr custom definitions, private Navidrome shuffle and selected-user
Moonfin caption presets now have reusable options. The definition installer
retains systemd's filesystem sandbox, anchors destination writes to directory
descriptors, rejects linked parent directories and atomically replaces declared
files. It accepts regular files whose original and resolved paths stay in the
immutable Nix store. This avoids copying mutable service-owned sources with
root privileges.
[Pinned Prowlarr module](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/nixos/modules/services/misc/servarr/prowlarr.nix),
[systemd command prefixes](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#ExecStart=).

Source selection, credentials
and preferred preset values remain consuming policy. Caption revisions support
migration snapshots and preserve later GUI edits. Shuffle preserves ordinary
playlists and editable override playlists. API helpers reject credential-bearing
URLs and redirects, and systemd credential paths escape literal percent signs.
[systemd credential semantics](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#LoadCredential=).

Slskd directory preparation moved behind required mount checks. Both evaluation
and the runtime preparer reject sensitive system directories. Runtime traversal
uses directory descriptors and refuses symlinks. Music jobs follow native
accounts and packages; lyrics can use an explicit library without shared storage.

Shared library helpers contain repeated production behavior: canonical runtime
paths, safe media directories, local HTTP URL construction and PostgreSQL socket
selection. One-off application routines remain beside their feature or in its
domain script directory. The [configuration guide](../portable-features.md)
describes the new interfaces and their ownership.

## Verification and limits

Configuration fixtures cover independent native service enablement, disabled
features, custom accounts, listeners, pools, packages, socket topology, credential
paths and compatibility failures. Python tests exercise real temporary files and
disposable HTTP APIs, including retry, migration, ownership and failure behavior.
The missing-storage and Arr PostgreSQL VM fixtures test lifecycle and database
behavior.

Recorded checks on 2026-10-14:

- All 80 declared configuration checks evaluated on ARM and x86 Linux.
- Focused portability and operations contracts built successfully. The owning
  formatter and repository hooks passed, including Python types and Gitleaks.
- All 104 media, indexer and storage Python tests passed on Darwin. Linux behavior
  checks passed for media, storage, definitions, operations, integration, Keycloak,
  device helpers and credential preflight.
- The missing-mount VM passed on native ARM Linux, including Slskd startup,
  ownership and symlink protection.
- The Arr PostgreSQL VM passed on ARM Linux with an image-backed Nix store and
  the classic initrd. Real Sonarr and Prowlarr instances used the custom socket
  and port; restricted database roles, startup migration guards and custom
  Prowlarr data-directory definition installation passed.
- The consuming NixOS configuration evaluated successfully. This is derivation
  evaluation, not a full system build or activation.

The hooks check disables colored execution in its sandbox because the selected
runner otherwise attempts to open a PTY. Interactive developer commands keep
their normal behavior.
[Prek environment variables](https://prek.j178.dev/reference/environment-variables/).

The default shared-store run on the remote builder exceeded its filesystem
daemon's file-descriptor limit before service checks. The image-backed run avoids
that limit. Its systemd initrd build also encountered missing terminal data in the
pinned package, so that run used the classic initrd. These are validation-builder
limitations; the service modules received no host-specific workaround. The
standard x86 VM remains the declared CI check, with no x86 runtime result claimed
here.

Source inspection and configuration evaluation do not establish successful live
authentication, device discovery or database upgrades. No deployment or
activation is part of this audit. Full application startup for every catalog
entry and every upstream package remains outside the runtime evidence.
