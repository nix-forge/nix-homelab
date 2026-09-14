# Changelog

This file records user-visible changes and required migrations. The project has
not published its first release.

## Unreleased

### Added

- Production-readiness checks for host-owned credentials, integration,
  recovery, monitoring, notifications, and real media mounts.
- A private operational health endpoint and `homelab-doctor` command.
- Generated option documentation and per-service evidence matrices.
- A versioned flake interface and minimal starter template.
- Native application, authenticated integration, VPN-failure, storage,
  workflow, and restore tests.

### Changed

- Arr resources use a typed endpoint and stable-match envelope. Supported
  adapter settings are checked during Nix evaluation; `extraSettings` is the
  unsupported forward-compatibility escape hatch.
- Recurring Jellyfin reconciliation requires a dedicated API key in production
  readiness after attended bootstrap.

### Fixed

- API-key-authenticated Jellyfin administrator password rotation no longer
  sends the desired password as the stale current password.
- Production readiness no longer passes when shared media storage lacks an
  explicit required mount.
- Generated option documentation includes descriptions for internal readiness
  fields.

### Migration

- Hosts enabling `homelab.readiness` with media applications must set
  `homelab.storage.requiredMounts` to the actual host mount point.
- After initial Jellyfin setup, create a dedicated administrator automation key
  and set the integration job's `apiKeyFile` to its runtime secret path.

### Evidence

- Release evidence will be recorded when a clean release candidate runs through
  local and hosted checks. Checked-in test names alone are not run results.
