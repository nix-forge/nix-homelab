# Quality roadmap

The objective is a reliable, reusable media and home-server project suitable for
nix-forge. No finite repository survey can prove it is the best on every forge.
Compare concrete behavior and maintain the source-backed gap matrix.

## Current implementation

- One pinned package set and an exported opt-in NixOS module.
- Native vpn-confinement integration, selected VPN clients and private UI
  policy.
- Core media profile, Usenet alternatives, music and audiobook players.
- User-provided nix-seal path integration, with no bundled credentials.
- Shared media storage, mount checks and desktop background priorities.
- Per-app configuration checks, storage/media/VPN VMs and shared nix-forge CI.
- Public setup, migration, security and contributor documentation.

## Acceptance work for a real deployment

1. Supply the consuming host's secret catalog and provider values. Preserve the
   existing disk, inspect capacity and select media versus backup budgets.
2. Connect applications through their authenticated APIs. Confirm indexer
   search, download, import, request fulfillment and playback with permitted
   test media.
3. Test the real tunnel and reconnect behavior. Keep ISP-sensitive traffic in
   the tunnel without routing desktop or playback traffic through it.
4. Exercise state backup and an isolated restore. Measure recovery time and
   identify media that needs a second independent copy.
5. Measure idle memory, CPU, disk wakeups, download/import I/O and direct-play
   versus transcoding power. Tune only against those measurements.
6. Run CI on the actual repository and verify required statuses, private
   reporting, branch protections and documentation links after the organization
   transfer.

## Further work justified by the comparison

Declarative API integration and end-to-end request/download/import tests are the
next gap against nixarr and nixflix. Add browser tests for real onboarding,
reverse-proxy and authentication tests, service-aware backup/export modules,
native ARM runtime validation as coverage grows. The optional tagged indexer
proxy keeps host app-sync traffic outside the VPN.

Use native modules for Recyclarr, autobrr, cross-seed, photo and book services,
monitoring, DNS, synchronization and backups. Each addition needs a demonstrated
user need, ownership of its state, a recovery procedure and resource evidence.
Avoid enabling competing players, downloaders or photo ML workers by default.
The [service catalog](research/media-services.md) records current candidates.
