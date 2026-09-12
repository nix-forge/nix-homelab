# Storage and recovery

Put downloads and libraries under one filesystem, for example
`/mnt/homelab/media/downloads` and `/mnt/homelab/media/library`. Separate
datasets, subvolumes or mounts can prevent hardlinks even when they share one
disk. An import then becomes a copy, consuming extra I/O and space while
torrents seed.
[TRaSH hardlink guidance](https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/)

Declare the existing disk in the consuming host and set
`homelab.storage.requiredMounts = [ "/mnt/homelab" ];`. The storage preparation
unit checks the actual mount before creating directories. Service dependencies
order startup behind it. The project does not partition or format disks. A
disappearing or failing disk still requires operator recovery; startup guards
are not a substitute for monitoring or a hot-unplug guarantee.

Media directories use mode 2770 and the shared media group. Services retain
their own primary identities for state. Downloads default to group-writable
files; players receive a read-only library mount. Existing files may need an
attended permission migration. No recursive ownership or permission rewrite is
performed.

A 4 TB drive shared between media and backups needs a capacity budget before
automatic downloads begin. Use sibling directories with separate ownership. Do
not place a backup repository under its own source tree. Directory separation is
not a quota. Leave headroom for download/unpack/import and backup retention;
SABnzbd's initial free-space guard is 20 GB and must be tuned to the workload. A
drive that is normally online for media is not an offline backup copy.

Keep SQLite databases and service state on the system SSD. Schedule library
scans, subtitle jobs, Usenet repair and backups away from interactive use.
`homelab.profiles.desktop.enable` gives downloads and library managers lower CPU
and I/O priority. Benchmark before selecting worker counts, cache sizes or GPU
transcoding. Enable the actual GPU through native Jellyfin and host driver
options after testing codec support and power use.

## Recovery procedure

Inventory the evaluated paths before defining the host's backup job. These are
the defaults at the checked-in package revision; host overrides take precedence.
Application state can contain API credentials even when the original credentials
came from nix-seal. Use encrypted backups with restricted access.

| Application    | Persistent state to include                                               | Native option                                             |
| -------------- | ------------------------------------------------------------------------- | --------------------------------------------------------- |
| Sonarr         | `/var/lib/sonarr/.config/NzbDrone`                                        | `services.sonarr.dataDir`                                 |
| Radarr         | `/var/lib/radarr/.config/Radarr`                                          | `services.radarr.dataDir`                                 |
| Lidarr         | `/var/lib/lidarr/.config/Lidarr`                                          | `services.lidarr.dataDir`                                 |
| Bazarr         | `/var/lib/bazarr`                                                         | `services.bazarr.dataDir`                                 |
| Prowlarr       | `/var/lib/prowlarr`                                                       | `services.prowlarr.dataDir`                               |
| Seerr          | `/var/lib/seerr`, backed by `/var/lib/private/seerr` for its dynamic user | `services.seerr.configDir` and `stateRevision`            |
| qBittorrent    | `/var/lib/qBittorrent`, including torrent resume data                     | `services.qbittorrent.profileDir`                         |
| SABnzbd        | `/var/lib/sabnzbd`, plus separately configured queue paths                | `services.sabnzbd.stateDir`, relative to `/var/lib`       |
| NZBGet         | `/var/lib/nzbget`, plus queue and NZB directories under downloads         | `services.nzbget.settings`                                |
| Jellyfin       | `/var/lib/jellyfin`, including its `config` directory                     | `services.jellyfin.dataDir` and `configDir`               |
| Plex           | `/var/lib/plex`                                                           | `services.plex.dataDir`                                   |
| Navidrome      | `/var/lib/navidrome`, excluding replaceable cache if desired              | `services.navidrome.settings.DataFolder`                  |
| Audiobookshelf | `/var/lib/audiobookshelf`                                                 | `services.audiobookshelf.dataDir`, relative to `/var/lib` |

Older Seerr state revisions use `/var/lib/private/jellyseerr/config`. Resolve
dynamic-user symlinks when selecting backup sources; copying only the symlink
does not preserve the database. Back up the host's encrypted nix-seal catalog
and its recovery material through its existing procedure, not disposable `/run`
outputs. Library files are a separate backup decision from application state.
These paths come from the
[pinned NixOS modules](https://github.com/NixOS/nixpkgs/tree/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services).

1. Export application settings or stop writers during a maintenance window. A
   live copy of a database directory does not establish consistency.
2. Back up state, metadata and user-provided secret recovery material to an
   independent destination. Exclude disposable downloads and transcode caches.
3. Keep media according to its replacement cost. Backups on the same media disk
   do not protect against that disk failing.
4. Restore into a separate directory or VM, check ownership and application
   startup, then record the restore date and the recovered data.
5. Before package upgrades, retain both a usable state backup and the previous
   lockfile. Roll back data and software together when a schema migration
   prevents an ordinary NixOS generation rollback.

During a restore, establish mounts and service identities first, restore data
with the expected ownership, and provision nix-seal outputs. Start the VPN and
downloaders, library managers and Prowlarr, then players and Seerr. Pause
automatic acquisition until API connections, library paths and sample playback
have been checked. A restored download queue without its matching payload may
restart downloads or require a client recheck.

The consuming nix-conf host owns Restic destinations and existing backup checks.
This flake does not silently create a second backup scheduler or prune policy.
