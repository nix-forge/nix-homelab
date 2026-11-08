# Nixflix changes since the September comparison

Reviewed: 2026-10-06. Scope: [Nixflix `78fe4493` (2026-09-19) to
`7ccd5d5` (2026-10-06)](https://github.com/kiriwalawren/nixflix/compare/78fe4493e39f3f4099eea678a0ca572ece6039b5...7ccd5d5c79e52032be1c44cb9c5d9bc195e938df),
with the preceding month checked back to 2026-09-06. The [September parity
review](nixflix-parity-2026-09.md) is the baseline. Nixflix tagged
[`v3.2.0`](https://github.com/kiriwalawren/nixflix/releases/tag/v3.2.0) on
October 5; the October 6 secret-type change is newer than that tag.
The September 6–19 changes, including notification setup, Radarr's default
minimum score, Jellyfin empty-folder ignore, and group setup, were already in
the pinned baseline.

## Answer

No wholesale Nixflix import is indicated. Its recent fixes suggested two useful
local regression checks: a real qBittorrent-to-Arr hardlink import across the
configured mount and a fresh Seerr setup when Recyclarr owns the chosen quality
profiles. Both now run in the `media-workflow` VM described below. The local tree
already has opt-in slskd, explicit private listener policy, and an attended [Maintainerr safe-policy
controller](../../modules/optional/maintainerr/policy.nix).

## Findings and sources

| Upstream change | Local implication and limit |
| --- | --- |
| [2026-09-23 `122f2330`](https://github.com/kiriwalawren/nixflix/commit/122f2330e9b5fd3a0d963957fe4ac5f40df85773) enables WebSockets for Arr nginx hosts. | Already recorded in the September review. The local [LAN HTTPS module](../../modules/operations/lan-https.nix) enables WebSockets for declared sites; this is configuration evidence, not a live proxy check. |
| [2026-09-25 `f52a7653`](https://github.com/kiriwalawren/nixflix/commit/f52a7653d6a7d8271fbc96305d47438fd51e8114) generates Jellyfin plugin package defaults from a checked-in manifest, selects by server ABI, removes the default Universal Plugin Repository, and allows a deliberate compatibility override. [2026-09-30 `abe295fb`](https://github.com/kiriwalawren/nixflix/commit/abe295fbcab45a0c06530595bc63d94317c6b665) repairs the manifest updater and pins a test repository. | The local [plugin module](../../modules/optional/jellyfin/plugins.nix) accepts pinned packages and leaves removal attended. Continue pinning artifact hashes and testing loading against the selected Jellyfin version. Nixflix's default selection is useful as a compatibility cross-check, not proof that a plugin loads. [Issue #369](https://github.com/kiriwalawren/nixflix/issues/369), closed October 5 after a user workaround, reports a missing default for Subbuzz when package inputs select a different Jellyfin; it did not land a code fix. |
| [2026-09-25 `2f6f62b3`](https://github.com/kiriwalawren/nixflix/commit/2f6f62b35845d55d2018212119b5587d52bbc5bd) separates Prowlarr display `name` from `schemaName`, rejects duplicate names without case sensitivity, and resolves `_secret` references in arbitrary indexer fields. | The local [Prowlarr integration](../../modules/integration/services/prowlarr.nix) already separates `name` from `implementation` and maps `secretFields` to runtime paths; its [evaluation check](../../tests/eval/prowlarr.nix) covers a secret field. A runtime check with two differently named indexers of one implementation would establish whether the API reconciliation handles that case. |
| [2026-09-25 `11774fcb`](https://github.com/kiriwalawren/nixflix/commit/11774fcba6cf3533756891e86df3a9c414951e21) preserves Arr `allowedHosts` in the host-config API payload, fixing Radarr 6.4.4 configuration. | The local [Arr adapter](../../scripts/integration/adapters/arr.py) merges proxy changes into the fetched host object, preserving fields such as `allowedHosts` in source. A Radarr 6.4.4 fixture would verify the API accepts that full payload; the upstream failure does not establish a local regression. |
| [2026-09-25 `5c55d998`](https://github.com/kiriwalawren/nixflix/commit/5c55d998cd130164bb111c06211c2dacb1c29bd1) adds slskd and configurable VPN namespace names. Its slskd default shares Lidarr media directories and maps the Soulseek peer port when VPN confined. | The local [slskd module](../../modules/downloaders/slskd.nix) already supplies opt-in confinement, runtime credentials, an empty default share list, a private web bind and explicit peer ingress. Retain the empty sharing default. The local [VPN module](../../modules/vpn/wireguard.nix) already owns the namespace policy; a second generic namespace option has no demonstrated need. |
| [2026-09-28 `1d6bd02f`](https://github.com/kiriwalawren/nixflix/commit/1d6bd02feb780ca73a5db407f4ea1afa9fc053a2) removes per-directory Arr `ReadWritePaths` and sets qBittorrent `UMask=0002` after hardlink failures. | The local [storage module](../../modules/storage/default.nix) gives Arr managers one writable media root and uses `UMask=0007` for media writers. The [media workflow VM](../../tests/nixos/media-workflow.nix) now passes a real import and hardlink check. A production mount still needs its own verification before changing permissions. |
| [2026-10-05 `da8200c3`](https://github.com/kiriwalawren/nixflix/commit/da8200c37d5712349bbb704a55943252697b8880) orders Seerr's Radarr/Sonarr configuration after Recyclarr when it supplies quality profiles; cleanup, if enabled, is also ordered first. | The inspected consuming desktop declaration already requires `recyclarr.service` before Seerr integration. The local [Seerr adapter](../../scripts/integration/adapters/seerr.py) rejects missing or ambiguous selected profiles. The media workflow VM now verifies this order on fresh state. Keep unmanaged-profile deletion disabled by default. |
| [2026-10-06 `7ccd5d5`](https://github.com/kiriwalawren/nixflix/commit/7ccd5d5c79e52032be1c44cb9c5d9bc195e938df) rejects empty strings for `_secret` paths. | The local typed credential paths already require a leading slash. The generic [integration validator](../../modules/integration/default.nix) checks `_secret` shape, so review its handling of an empty path supplied through generic `extraSettings`. Runtime checks still need to catch missing or empty secret contents. |

[Issue #364](https://github.com/kiriwalawren/nixflix/issues/364), opened
September 27 and still open at review, reports services binding to `0.0.0.0`
by default. This is a user report, not a merged Nixflix fix or an independent
runtime finding here. It reinforces the local [private bind and ingress
policy](../../modules/operations/lan-https.nix), especially for a deployment
using its own reverse proxy. The local listener assertions should still be
checked in a running deployment.

## Validation and limits

Read upstream commit metadata, diffs, the `v3.2.0` release notes and the two
issues through 2026-10-06. Compared them with the current local source tree.
The local tree had pre-existing staged and unstaged work, so these observations
describe that working tree rather than a published release.

## Follow-up verification

The existing [media workflow VM](../../tests/nixos/media-workflow.nix) already
downloads a local torrent through qBittorrent and has Radarr import it. Its
[acceptance check](../../tests/fixtures/media-workflow/acceptance.py) compares
the device and inode of the downloaded and imported files and checks that the
download still has at least two links. The VM now also starts Recyclarr on a
fresh machine, waits for its profile before Seerr integration, and verifies
that both Radarr and Seerr expose `Homelab 1080p`.

On `desktop`, `workstation-task nix build --no-link --max-jobs 1 --cores 2
.#checks.x86_64-linux.media-workflow` passed after the VM change. The test first
failed as expected when Seerr required `recyclarr.service` but the fixture had
not yet enabled Recyclarr. The passing disposable VM does not establish that a
production media mount, provider, or existing application state behaves the
same way.
