# nix-homelab

Composable NixOS modules for a home media server, with private network defaults,
shared media storage and selected services confined through
[nix-forge/vpn-confinement](https://github.com/nix-forge/vpn-confinement).

The consuming host owns its disks, hardware, user-provided
[nix-seal](https://github.com/nix-forge/nix-seal) secrets and backup
destinations. Importing this flake enables no applications.

## Start here

Add this flake to your existing system configuration and import
`inputs.nix-homelab.nixosModules.default`. Follow [setup](docs/setup.md) for the
input, runtime secrets, VPN profile and application connections. The remote is
`github:nix-forge/nix-homelab`.

```nix
{
  homelab.profiles.media.enable = true;
  homelab.profiles.desktop.enable = true;
  homelab.storage = {
    rootDir = "/mnt/homelab/media";
    requiredMounts = [ "/mnt/homelab" ];
  };
  # Supply the user's VPN profile and nix-seal paths as described in setup.
}
```

The media profile selects Jellyfin, Seerr, Sonarr, Radarr, Bazarr, Prowlarr and
qBittorrent. Only qBittorrent uses the VPN by default. An optional confined
proxy can route selected Prowlarr indexer searches. It refuses configuration
without VPN settings unless direct networking is explicitly selected. Every
application can be enabled or disabled individually under `homelab.apps`.

| Optional application | Purpose                                                               |
| -------------------- | --------------------------------------------------------------------- |
| Lidarr               | Music library management                                              |
| SABnzbd or NZBGet    | Usenet downloads; optional VPN in addition to provider TLS            |
| Navidrome            | Music playback                                                        |
| Audiobookshelf       | Audiobooks and podcasts                                               |
| Plex                 | Alternative media player, requires explicit unfree-package permission |

[Native examples](examples/extras.nix) cover Recyclarr, autobrr, a node exporter
and SMART monitoring. The [service research](docs/research/media-services.md)
compares additional tools, including books, photos, monitoring and backups.
Readarr is retired and is no longer part of the supported catalog.

## Safety and operation

Service firewall ports stay closed. Some upstream applications listen on all
addresses, so the host firewall remains part of the security model. Use local
access or a host-managed authenticated reverse proxy. VPN namespace web ports
are accessible from the host, not automatically published on the LAN.

Downloads and libraries share a filesystem for hardlink imports. Players get a
read-only library mount. Missing required media mounts prevent service startup.
Application state stays under each upstream service's state directory, normally
on the system SSD. The desktop profile lowers background CPU and I/O priority.
It does not select GPU drivers or impose an unmeasured memory budget.

Read [storage and recovery](docs/storage.md), [VPN privacy](docs/vpn.md),
[security](SECURITY.md), and [migration](docs/migration.md) before using real
data. A database upgrade may require restoring a backup to roll back.

## Development and project direction

```sh
nix develop
just check
just test
```

[Testing](docs/testing.md) distinguishes configuration, package builds, VM
behavior and real hardware validation. Checks use pinned inputs and nix-forge
shared CI actions. [Contribution guidance](CONTRIBUTING.md) and
[agent workflows](docs/agents/workflows.md) define the maintenance process.

The [public project comparison](docs/research/project-comparison.md) records
what strong peers do well. The [roadmap](docs/roadmap.md) turns those findings
into acceptance work. This project does not claim to outrank every public
homelab; recovery evidence, integration tests and measured behavior are the
standard.

Build the generated module option reference with `nix build .#options`.
