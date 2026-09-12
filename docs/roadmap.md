# Quality roadmap

The objective is a reliable, reusable media and home-server project suitable for
nix-forge. Compare observable behavior against the
[service completeness research](research/service-completeness.md). A repository
survey cannot establish that this project is the best on every forge.

## Implemented configuration

The default module enables no applications. The examples compose these opt-in
features:

- [Authenticated integration](integration.md) for Arr managers, Prowlarr,
  Jellyfin, Seerr, Bazarr, Navidrome and Audiobookshelf. Runtime credentials
  come from user-provided files. Bootstrap mode preserves existing
  configuration; managed mode reconciles the explicitly declared fields.
- [Quality policies and optional services](optional-services.md), including
  pinned Recyclarr guide revisions, release automation, cross-seeding,
  extraction, books, channel archives, photos, documents, synchronization, DNS,
  disk health and authenticated Maintainerr access.
- [Usenet alternatives](usenet.md) with runtime credentials, bounded processing
  and manager-specific categories.
- [Operations](operations.md) with application state inventory, consistent
  Restic staging, database exports, attended restoration, storage-pressure
  handling, private monitoring, a generated dashboard and optional authenticated
  reverse proxy access. Arr PostgreSQL is opt-in and refuses an unacknowledged
  existing SQLite database.
- Shared media paths, guarded mounts, symlink-safe directory preparation,
  read-only player views and background resource limits. The host selects GPU
  devices and disk monitoring.
- Native vpn-confinement integration and user-provided nix-seal credentials.
  Hardware, mounts, secret catalogs and backup destinations remain in the
  consuming system repository.

See [testing](testing.md) for the checks and their limits. Configuration
coverage and disposable fixtures do not establish provider compatibility,
hardware performance or production recovery.

## Acceptance work for a real deployment

1. Supply the consuming host's secret catalog and provider values. Preserve the
   existing disk, inspect capacity and select media versus backup budgets. Keep
   an independent copy of irreplaceable files; a backup on the media disk shares
   its failure modes.
2. Choose services needed on this desktop. Complete provider, account, library
   and device inputs documented by each example. Confirm authenticated search,
   download, import, request fulfillment and playback with permitted media.
3. Test the real tunnel and reconnect behavior. Keep ISP-sensitive traffic in
   the tunnel without routing unrelated desktop or playback traffic through it.
4. Exercise backup and an isolated restore with the deployed application
   versions, secret files and UID mappings. Measure recovery time and verify
   restored media bytes, metadata and user access.
5. Measure idle memory, CPU, disk wakeups, download/import I/O and direct-play
   versus transcoding power. Tune the supplied limits against those
   measurements.
6. Run CI on the actual repository and verify required statuses, private
   reporting, branch protections and documentation links after an organization
   transfer. This flake does not configure forge settings.

## Further validation

Extend native ARM runtime coverage, browser onboarding and authenticated
provider workflows as suitable runners and disposable provider accounts become
available. Add hardware-specific GPU and disk tests in the consuming system.
Keep the source comparison current, but require a useful workflow, state
ownership and recovery evidence before expanding the catalog. Service count is
not a completion criterion.
