# Migration from the original skeleton

Back up service state before changing the consuming host. This change updates
nixpkgs from the April pin to the September 2026 unstable pin. Upstream database
migrations are not reversible through a NixOS generation rollback alone.

Import the exported `nixosModules.default`; it imports vpn-confinement.
Importing individual old files was never a supported flake interface. Arr and
player files are now grouped behind opt-in `homelab.apps.<name>.enable` options.
The old `homelab.services.prowlarr` name remains a renamed-option alias.

qBittorrent now requires VPN by default. Direct networking requires an explicit
`homelab.apps.qbittorrent.vpn.enable = false`. Its namespace configuration now
uses native vpn-confinement lifecycle wiring. Old private resolver, veth,
namespace-path and hardening options report migration errors. Configure advanced
namespace policy through `services.vpnConfinement` instead.

Namespace host-link addresses are derived by upstream; update host-side download
client URLs. Only declared UI ports are reachable from the host. API passwords
and tokens still belong in applications or runtime files. Readarr is retired and
removed; retain its database before considering a separate replacement.

The agenix input and the personal encrypted provider fixture have been removed.
Use the consuming host's nix-seal catalog and the runtime path adapter in
`examples/nix-seal.nix`. This repository provides no identities or credentials.
The disposable demo VM contains no personal SSH keys or reusable password.

qBittorrent's upstream module rewrites declarative settings at service startup.
Use `credentialsFile` for persistent Web UI credentials; UI-only settings may be
replaced on restart. Configure durable settings in
`services.qbittorrent.serverConfig`. NZBGet keeps provider credentials in its
private mutable state. SABnzbd uses the native declarative settings and runtime
secret file interface.

Nixpkgs and developer tools now share one root lockfile. The broken nested
partition was removed. Consumers no longer inherit global permission for all
unfree software; Plex requires a narrow explicit exception in the host.
