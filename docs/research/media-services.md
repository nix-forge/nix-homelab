# Media and home services research

Research date: 2026-09-11. This report recommends services for a desktop that
will initially host the homelab, with Mullvad WireGuard used only for selected
traffic. Recommendations prioritize maintained upstreams, native NixOS
integration, recoverable upgrades, private management interfaces, and measured
resource use. They are not a ranking of every public project.

The selected nixpkgs revision is
[`8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe`](https://github.com/NixOS/nixpkgs/tree/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe),
dated September 10. Package and module facts below come from that source tree.
Upstream release versions come from each project's public GitHub releases API
and linked release page, checked on the research date. A recent upstream release
does not establish compatibility with the selected NixOS module or an existing
database.

## Recommended service choices

Use Sonarr for television, Radarr for films, Prowlarr for indexer management,
and Bazarr when subtitle automation is useful. Add Seerr for discovery and
requests. Start with Jellyfin as the fully open media server and retain Plex as
an explicit alternative for households that prefer its clients and accept its
licensing. Choose qBittorrent for torrents and SABnzbd or the maintained NZBGet
fork for Usenet. This division matches the projects' documented
responsibilities. [Servarr](https://wiki.servarr.com/),
[Bazarr](https://www.bazarr.media/), [Seerr](https://seerr.dev/),
[SABnzbd](https://sabnzbd.org/), [NZBGet](https://github.com/nzbgetcom/nzbget).

Every service should remain opt-in. On a desktop, avoid enabling several
overlapping readers, two video servers, image machine learning, subtitle
extraction, and bulk transcodes together before measuring idle and peak usage.
The recommendations below are deployment choices, not claims that every listed
service is implemented by this repository.

| Need                          | Recommended choice                   | Scope and tradeoff                                                                                                                                                                                        |
| ----------------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Television and films          | Sonarr and Radarr                    | Core media automation. Configure quality, download categories, root folders, and API connections after service startup.                                                                                   |
| Indexers                      | Prowlarr                             | One place to maintain indexers and synchronize them into supported apps. Actual providers and credentials remain user choices.                                                                            |
| Subtitles                     | Bazarr                               | Useful alongside Sonarr/Radarr. It needs write access where subtitles are stored, and subtitle generation or synchronization adds work.                                                                   |
| Requests                      | Seerr                                | Supports Jellyfin, Plex, and Emby in one project. Do not start separate Overseerr and Jellyseerr installations for a new deployment.                                                                      |
| Torrent downloads             | qBittorrent-nox                      | Put this service in the VPN namespace by default for the stated privacy requirement. Keep its Web UI authenticated.                                                                                       |
| Usenet downloads              | SABnzbd                              | Strong first choice for its documented settings and native NixOS secret-file support. Require NNTPS with certificate verification.                                                                        |
| Alternative Usenet downloader | NZBGet from `nzbgetcom`              | Keep as an alternative. The original repository is archived, but this maintained continuation is already the nixpkgs source. Benchmark against SABnzbd on the actual machine.                             |
| Quality policy                | Recyclarr                            | Useful scheduled companion for Sonarr/Radarr. Preview its changes before enabling unattended sync; configuration changes can affect future downloads and upgrades.                                        |
| Music acquisition             | Lidarr                               | Opt-in for a music library. Navidrome can serve that library; it does not replace acquisition or metadata management.                                                                                     |
| Torrent automation            | autobrr and cross-seed               | Advanced opt-ins. Add them only when their release filtering and cross-seeding workflows are wanted. They add credentials, API connections, indexer load, and storage permissions.                        |
| Audiobooks and podcasts       | Audiobookshelf                       | Prefer this when audiobook progress and podcast workflows matter.                                                                                                                                         |
| Music playback                | Navidrome                            | A focused OpenSubsonic-compatible music service, useful when music clients are more important than a single video-and-music UI.                                                                           |
| Books and comics              | Choose Kavita, Komga, or Calibre-Web | Kavita covers EPUB/PDF/comics with built-in readers; Komga emphasizes comic libraries and reader integrations; Calibre-Web expects a Calibre database. Avoid three competing library managers by default. |
| Book discovery                | Shelfmark, experimental opt-in       | A current book/audiobook search and download UI with Prowlarr integration. It is not a proven drop-in replacement for Readarr's entire automated author-monitoring workflow.                              |
| Personal photos               | Immich, separate opt-in              | Useful mobile photo backup and search, with its own database, storage, memory, and upgrade requirements. Keep its data separate from download automation.                                                 |

The specialized choices above follow
[Recyclarr's feature list](https://recyclarr.dev/guide/features/),
[autobrr's introduction](https://autobrr.com/introduction),
[cross-seed's setup guide](https://www.cross-seed.org/docs/basics/getting-started),
[Audiobookshelf](https://audiobookshelf.org/),
[Navidrome](https://www.navidrome.org/),
[Kavita](https://www.kavitareader.com/), [Komga](https://komga.org/),
[Calibre-Web](https://github.com/janeczku/calibre-web), and
[Shelfmark](https://github.com/calibrain/shelfmark). Reader and acquisition
workflows need a sample-library trial before a production migration.

## Package freshness

All entries below have native NixOS modules and packages in the selected nixpkgs
tree. The package column records the selected pin, not an assertion that
upstream is fully current. Each package definition is under
`pkgs/by-name/<first-two-letters>/<name>/package.nix` in the
[selected source tree](https://github.com/NixOS/nixpkgs/tree/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/by-name).
These values were read from those files. The release links provide independent
upstream checks.

| Package        | Selected pin               | Latest upstream release checked                                                | Release date |
| -------------- | -------------------------- | ------------------------------------------------------------------------------ | ------------ |
| sonarr         | 4.0.19.2979                | [4.0.19.2979](https://github.com/Sonarr/Sonarr/releases/tag/v4.0.19.2979)      | 2026-06-26   |
| radarr         | 6.3.0.10514                | [6.3.0.10514](https://github.com/Radarr/Radarr/releases/tag/v6.3.0.10514)      | 2026-07-12   |
| lidarr         | 3.1.0.4875                 | [3.1.0.4875](https://github.com/Lidarr/Lidarr/releases/tag/v3.1.0.4875)        | 2025-11-16   |
| bazarr         | 1.6.0                      | [1.6.0](https://github.com/morpheus65535/bazarr/releases/tag/v1.6.0)           | 2026-07-04   |
| prowlarr       | 2.5.2.5491                 | [2.5.2.5491](https://github.com/Prowlarr/Prowlarr/releases/tag/v2.5.2.5491)    | 2026-07-22   |
| seerr          | 3.4.1                      | [3.4.1](https://github.com/seerr-team/seerr/releases/tag/v3.4.1)               | 2026-07-30   |
| qbittorrent    | 5.2.3                      | [5.2.3](https://github.com/qbittorrent/qBittorrent/releases/tag/release-5.2.3) | 2026-07-07   |
| sabnzbd        | 5.1.2                      | [5.1.3](https://github.com/sabnzbd/sabnzbd/releases/tag/5.1.3)                 | 2026-09-08   |
| nzbget         | 26.2                       | [26.3](https://github.com/nzbgetcom/nzbget/releases/tag/v26.3)                 | 2026-08-27   |
| recyclarr      | 8.7.1                      | [8.7.2](https://github.com/recyclarr/recyclarr/releases/tag/v8.7.2)            | 2026-09-03   |
| autobrr        | 1.84.0                     | [1.86.0](https://github.com/autobrr/autobrr/releases/tag/v1.86.0)              | 2026-09-10   |
| cross-seed     | 6.13.7                     | [6.13.7](https://github.com/cross-seed/cross-seed/releases/tag/v6.13.7)        | 2026-05-04   |
| jellyfin       | 12.0                       | [12.0](https://github.com/jellyfin/jellyfin/releases/tag/v12.0)                | 2026-09-08   |
| audiobookshelf | 2.36.0                     | [2.36.0](https://github.com/advplyr/audiobookshelf/releases/tag/v2.36.0)       | 2026-07-27   |
| navidrome      | 0.63.2                     | [0.63.2](https://github.com/navidrome/navidrome/releases/tag/v0.63.2)          | 2026-07-11   |
| kavita         | 0.9.0.2                    | [0.9.1.4](https://github.com/Kareadita/Kavita/releases/tag/v0.9.1.4)           | 2026-09-02   |
| komga          | 1.26.3                     | [1.26.3](https://github.com/gotson/komga/releases/tag/1.26.3)                  | 2026-08-12   |
| calibre-web    | 0.6.26-unstable-2026-03-01 | [0.6.27](https://github.com/janeczku/calibre-web/releases/tag/0.6.27)          | 2026-08-08   |
| immich         | 3.1.0                      | [3.2.0](https://github.com/immich-app/immich/releases/tag/v3.2.0)              | 2026-09-10   |
| shelfmark      | 1.3.15                     | [1.3.15](https://github.com/calibrain/shelfmark/releases/tag/v1.3.15)          | 2026-09-02   |

Readarr remains packaged at 0.4.18.2805, but its presence in nixpkgs does not
imply upstream support. Its [retirement announcement](https://readarr.com/) says
its metadata became unusable and development stopped. Preserve an existing
database for migration, then select a supported reader and acquisition workflow.
Third-party metadata mirrors and forks require separate evaluation; this report
does not certify any as an equivalent replacement.

Seerr's teams
[merged Overseerr and Jellyseerr on February 10, 2026](https://docs.seerr.dev/blog/seerr-release/).
Its [migration guide](https://docs.seerr.dev/migration-guide/) describes
automatic data migration and requires a backup first. The selected NixOS module
has `services.seerr.stateRevision`, which controls the legacy Jellyseerr versus
Seerr state-directory defaults. Do not change that revision or directory without
moving the existing data.
[Selected Seerr module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/misc/seerr.nix).

NZBGet needs precise naming. [`nzbget/nzbget`](https://github.com/nzbget/nzbget)
is the archived original.
[`nzbgetcom/nzbget`](https://github.com/nzbgetcom/nzbget) is the maintained
continuation used by the selected Nix package. Removing NZBGet merely because
the original retired would discard a current option.

## Selective VPN policy for the desktop

The target is to hide selected outbound traffic from the ISP while keeping
normal desktop and home-server routing. Put qBittorrent in
`nix-forge/vpn-confinement`. Leave application management, media playback, and
normal desktop traffic outside it. Treat indexer and Usenet privacy as explicit
choices about hiding destinations in addition to encrypting contents.

| Service or traffic                                        | Recommended route                                          | Reason and remaining exposure                                                                                                                                                                                                        |
| --------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| qBittorrent peer, tracker, DHT, and DNS traffic           | VPN by default                                             | The torrent client communicates with changing peers. Route its entire service network through the confined namespace, including name resolution. Peers see the VPN exit address; the ISP still sees the tunnel and traffic patterns. |
| Prowlarr                                                  | Host by default                                            | Preserve calls to host Sonarr/Radarr and avoid shared VPN exit blocks. HTTPS protects query contents, but destination IPs and any unencrypted DNS remain visible to the ISP.                                                         |
| Selected Prowlarr indexer requests                        | Optional proxy inside VPN namespace                        | Use Prowlarr's tagged indexer proxy support for indexers whose destination traffic should be hidden. Ensure proxy-side name resolution also stays inside the tunnel. Test redirects and download requests for those indexers.        |
| SABnzbd and NZBGet                                        | Host with NNTPS and certificate checks by default          | TLS protects credentials and articles. The ISP still sees the news server IP, timing, and volume. Opt into VPN confinement if hiding the provider destination is required as well.                                                   |
| Sonarr, Radarr, Lidarr, Bazarr, Recyclarr                 | Host                                                       | Metadata, subtitle, quality-policy, and local API work do not need torrent-client routing. HTTPS is still required for external APIs. Services can infer library interests from authenticated requests regardless of VPN use.        |
| autobrr                                                   | Host by default; review configured IRC/indexer connections | This service may contact trackers independently. Use TLS where supported. If hiding those destinations is required, its egress needs a separate proxy or confinement design that preserves its local API calls.                      |
| cross-seed                                                | Host by default with explicit provider review              | It may make indexer requests independently of Prowlarr. A proxied Prowlarr does not prove all cross-seed traffic is hidden. Route selected requests or the service only after checking its complete API path.                        |
| Jellyfin, Plex, Seerr, Navidrome, Audiobookshelf, readers | Host                                                       | LAN playback does not traverse the ISP. Remote playback and metadata requests have their own privacy considerations. Use TLS and authentication for remote access.                                                                   |
| Immich, backups, DNS, monitoring, home automation         | Host                                                       | Give each a separate authentication, TLS, and access policy. They should not inherit torrent routing or become unavailable when Mullvad is down.                                                                                     |
| Desktop browser, games, updates, ordinary applications    | Existing desktop routing                                   | Per-service confinement leaves their routes unchanged. Browser privacy is outside this service configuration's guarantee.                                                                                                            |

The matrix is an engineering recommendation based on
[Servarr's VPN guidance](https://github.com/Servarr/Wiki/blob/master/vpn.md),
[SABnzbd's TLS explanation](https://sabnzbd.org/wiki/advanced/certificate-errors.html),
[Mullvad's description of VPN trust and limits](https://mullvad.net/en/vpn/what-is-vpn),
and the
[vpn-confinement threat model](https://github.com/nix-forge/vpn-confinement/blob/0317379905359bc32204e05548e6a658b45d0ccd/site/src/content/docs/threat-model.md).
An opt-in recommendation is not an implemented or tested proxy integration.

Servarr advises keeping ordinary Arr applications outside the VPN and using an
indexer proxy selectively. Its guide also makes broader claims about encrypted
DNS being sufficient and port forwarding being mandatory. Those are not
guarantees for this deployment. Encrypted DNS hides queries from an observer on
the path to the resolver; it does not hide subsequent destination IPs. A lack of
inbound forwarding limits reachable peers, but does not prohibit a torrent
client from making outbound peer connections.
[Mullvad encrypted DNS documentation](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls),
[BitTorrent peer protocol](https://www.bittorrent.org/beps/bep_0003.html).

Mullvad
[removed port forwarding in 2023](https://mullvad.net/en/blog/removing-the-support-for-forwarded-ports).
Do not advertise full inbound torrent connectivity, set up a fictional forwarded
port, or expect opening a home-router port to solve it. Outbound transfers and
seeding over established connections can work, but reachable peers and seeding
opportunities can be reduced. `publishToHost.tcp` is a local host-to-namespace
path, not provider port forwarding.
[vpn-confinement architecture](https://github.com/nix-forge/vpn-confinement/blob/0317379905359bc32204e05548e6a658b45d0ccd/site/src/content/docs/architecture.md).

With direct HTTPS or NNTPS, TLS protects application contents when certificate
validation succeeds. Destination IPs and traffic timing remain observable, and
domain names may be exposed by plaintext DNS or connection metadata. With
selected traffic inside WireGuard, the ISP sees the VPN endpoint and traffic
patterns. Mullvad handles the onward connection, so trust shifts to the VPN
provider. Accounts, API keys, application telemetry, compromised hosts, and
remote services can still identify activity. There is no absolute anonymity
guarantee.
[TLS documentation](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Transport_Layer_Security),
[Mullvad's privacy explanation](https://mullvad.net/en/vpn/what-is-vpn).

### Why Prowlarr should usually stay on the host

Prowlarr synchronizes indexers by making API calls to its configured
applications. A fully confined Prowlarr cannot reach host Sonarr/Radarr merely
because its own UI port was published. The selected confinement firewall permits
established replies over the host link; it does not permit new namespace-to-host
connections. This follows from
[Prowlarr's Sonarr integration](https://github.com/Prowlarr/Prowlarr/blob/v2.5.2.5491/src/NzbDrone.Core/Applications/Sonarr/Sonarr.cs)
and
[the selected namespace firewall](https://github.com/nix-forge/vpn-confinement/blob/0317379905359bc32204e05548e6a658b45d0ccd/modules/vpn-confinement/firewall.nix#L171).

For destination privacy, keep Prowlarr on the host and place an authenticated
SOCKS5 proxy in the namespace. Expose only the proxy listener over the private
host link, resolve names through the proxy, and tag only the indexers that need it. This preserves
local synchronization. Prove the behavior with tests for proxy authentication,
DNS containment, VPN outage, and unproxied API connectivity before documenting
it as ready to use. A general proxy must not be reachable from the LAN or
Internet by default.

## Native NixOS integration details

Use existing `services.*` modules for package installation, users, state
directories, and upstream unit changes. Homelab wrappers should add useful
storage, exposure, confinement, and validation policy while preserving those
module interfaces.

| Service        | Verified selected-pin detail                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Seerr          | `systemd.services.seerr.environment.HOST = "127.0.0.1"` sets the actual bind host. Version 3.4.1 reads `process.env.HOST` and passes it to `server.listen`; `HOSTNAME` is not this control. Preserve `DynamicUser` unless there is a documented storage requirement. [Upstream source](https://github.com/seerr-team/seerr/blob/v3.4.1/server/index.ts#L269), [module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/misc/seerr.nix). |
| SABnzbd        | Use `settings`, `secretFiles` or `secretValues`, and explicitly set `configFile = null` for declarative settings on older `stateVersion` deployments. A non-null legacy config file bypasses generated settings. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/networking/sabnzbd/default.nix).                                                                                                                              |
| Recyclarr      | `configuration` supports runtime `_secret` substitution through systemd credentials. The module uses the v8 environment directory controls. Use the matching [v8 upgrade guide](https://recyclarr.dev/guide/upgrade-guide/v8.0/) and a preview before scheduled sync. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/misc/recyclarr.nix).                                                                                     |
| autobrr        | `secretFile` is required for the session secret; settings must not contain `sessionSecret`. The module supplies a private credential and binds to loopback by default. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/misc/autobrr.nix).                                                                                                                                                                                      |
| cross-seed     | `settingsFile` supplies private JSON settings. Hardlink `linkDirs` must share the source filesystem. Its credentials may include URLs containing secrets, which must not go in ordinary Nix settings. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/torrent/cross-seed.nix), [linking guide](https://www.cross-seed.org/docs/tutorials/linking).                                                                             |
| Jellyfin       | Native `hardwareAcceleration` and `transcoding` options already exist. Device, backend, supported codecs, and actual playback tests must agree. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/misc/jellyfin.nix).                                                                                                                                                                                                            |
| Navidrome      | Uses `settings.Address`, `settings.Port`, and `settings.MusicFolder`; telemetry collection defaults off. Keep media read-only and choose plugins explicitly. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/audio/navidrome.nix).                                                                                                                                                                                             |
| Audiobookshelf | Has native `host`, `port`, `dataDir`, `user`, and `group` options. Select library folders in the application, then restrict the service to those paths. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/web-apps/audiobookshelf.nix).                                                                                                                                                                                          |
| Kavita         | Requires a runtime `tokenKeyFile`; `settings.IpAddresses` defaults to all addresses and needs an explicit private binding. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/web-apps/kavita.nix).                                                                                                                                                                                                                               |
| Calibre-Web    | Its configured library must contain `metadata.db`. Conversion and uploads are separate options; grant writes only for wanted workflows. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/web-apps/calibre-web.nix).                                                                                                                                                                                                             |
| Immich         | Includes PostgreSQL, cache, machine learning, and device options. `secretsFile` avoids literal credentials in Nix. Native packaging is a NixOS integration; upstream's main recommended deployment remains Docker Compose. [Module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/web-apps/immich.nix), [upstream requirements](https://docs.immich.app/install/requirements/).                                                       |

## Performance, storage, and upgrades

Keep completed downloads and their media libraries on the same filesystem when
hardlinks are wanted. A common directory prefix alone is insufficient when
separate datasets or mounts are underneath it. Confirm device and inode identity
on a test import. Hardlinks let the downloader keep seeding without a second
full data copy. They also mean modifications to the shared file affect both
paths, so do not rewrite the contents of actively seeded files.
[Sonarr FAQ](https://wiki.servarr.com/sonarr/faq#seeding-torrents-arent-deleted-automatically),
[cross-seed linking](https://www.cross-seed.org/docs/tutorials/linking).

Keep application databases and caches on local storage with appropriate
ownership. Prefer direct playback of client-compatible formats. When transcoding
is necessary, select hardware acceleration from the actual GPU and codec
capabilities, then verify its use during playback. Jellyfin's hardware guide
explains why CPU-only HDR conversion can be expensive and recommends SSD space
for state and transcode cache. It does not justify selecting a driver or a
RAM-backed transcode directory without hardware and workload evidence.
[Jellyfin hardware selection](https://jellyfin.org/docs/general/administration/hardware-selection/),
[transcoding](https://jellyfin.org/docs/general/post-install/transcoding/).

Jellyfin 12.0 is a database migration, not a routine package-only change. Its
release notes require a backup, advise removing repository plugins before
migration, and require a full library scan afterward. A Nix generation rollback
alone cannot undo the database changes. Validate the household's clients and
Seerr integration before activation.
[Jellyfin 12.0 release notes](https://github.com/jellyfin/jellyfin/releases/tag/v12.0).

Immich's current requirements specify 6 GB minimum RAM and recommend 8 GB with
four CPU cores. Its amd64 machine-learning component needs x86-64-v2 from v3.
PostgreSQL should use local SSD storage, not a network share. Current
documentation suggests 10-20% extra storage for thumbnails and transcoded video.
These are upstream planning figures, not measurements of this desktop.
[Immich requirements](https://docs.immich.app/install/requirements/). Back up
uploaded media and the database; automatic database backups do not contain the
photos. Test a matched-version restore before relying on it.
[Immich backup guide](https://docs.immich.app/administration/backup-and-restore/).

Recyclarr v8 changes configuration and directory handling. Preview configuration
changes and keep its cache/state in backups. Track changes to remotely fetched
quality definitions separately from `flake.lock`, because a scheduled sync can
change application policy without a Nix rebuild.
[Recyclarr v8 migration](https://recyclarr.dev/guide/upgrade-guide/v8.0/),
[features and preview mode](https://recyclarr.dev/guide/features/).

Limit concurrent extraction, repair, scanning, thumbnail generation, and
transcoding rather than maximizing every worker count. SABnzbd's speed guide
identifies network, disk, CPU, and server connections as separate bottlenecks.
Compare download throughput while media is playing and the desktop is in use.
[SABnzbd performance guide](https://sabnzbd.org/wiki/advanced/highspeed-downloading).
Shelfmark's browser-assisted direct-download mode has a separate Chromium memory
cost; its Prowlarr workflow does not require starting that browser.
[Shelfmark requirements](https://github.com/calibrain/shelfmark#readme).

## Licensing and support boundaries

The selected nixpkgs metadata identifies the main Arr applications as GPL
software, Seerr and Recyclarr as MIT, cross-seed as Apache-2.0, Komga and
Shelfmark as MIT, and Immich's application as AGPL-3.0. qBittorrent has
GPL-2.0-or-later code and GPL-3.0-or-later assets. Check each package's full
license list when redistributing a combined artifact; these labels describe the
main projects, not every dependency.
[Selected package metadata](https://github.com/NixOS/nixpkgs/tree/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/by-name),
[qBittorrent definition](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/by-name/qb/qbittorrent/package.nix),
[Immich definition](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/by-name/im/immich/package.nix).

Plex is an explicit proprietary alternative. Hardware-accelerated streaming
generally requires Plex Pass, and remote playback has subscription conditions.
Choose it for tested client needs, not because it is presumed to offer the same
cost and account model as Jellyfin.
[Plex hardware acceleration](https://support.plex.tv/articles/115002178853-using-hardware-accelerated-streaming/),
[Plex Pass](https://support.plex.tv/articles/201751006-plex-pass-feature-overview/).
Kavita's optional Kavita+ service also has a subscription for added metadata and
synchronization functions. Its base reader and the premium service should be
described separately. [Kavita](https://www.kavitareader.com/).

## Complementary home services

| Service area      | Candidate and deployment advice                                                                                                                                                                                                                                               | Primary source                                                                                                                                                                                                                             |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Backups           | Restic with an independent destination, retention, integrity checks, and a restore drill. Back up databases consistently and keep recovery credentials available outside this host.                                                                                           | [Restic documentation](https://restic.readthedocs.io/en/stable/)                                                                                                                                                                           |
| Disk health       | `smartd` for basic health alerts; Scrutiny when historical disk-health charts are worth the extra service. Validate disk passthrough and supported attributes on the actual controller.                                                                                       | [Scrutiny](https://github.com/AnalogJ/scrutiny), [selected NixOS monitoring modules](https://github.com/NixOS/nixpkgs/tree/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/monitoring)                                     |
| Availability      | Gatus for checks described in configuration, or Uptime Kuma for UI-managed monitors. Choose one first. Export host metrics when needed and keep monitoring endpoints private.                                                                                                 | [Gatus](https://github.com/TwiN/gatus), [Uptime Kuma](https://github.com/louislam/uptime-kuma)                                                                                                                                             |
| Service dashboard | Homepage for links and widgets. Protect it because widgets can expose private application data. Current v2 documentation includes a password/OIDC gate, so old claims that it has no authentication are stale.                                                                | [Homepage installation and security](https://gethomepage.dev/installation/)                                                                                                                                                                |
| DNS filtering     | AdGuard Home when a management UI is preferred, or Blocky when a configured DNS proxy fits better. Do not replace desktop DNS until fallback and local-name resolution are tested.                                                                                            | [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome), [Blocky](https://0xerr0r.github.io/blocky/latest/)                                                                                                                             |
| Documents         | Paperless-ngx for searchable household documents. Keep this private archive outside the media/download group and give OCR its own resource budget.                                                                                                                            | [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx)                                                                                                                                                                            |
| Home automation   | Home Assistant when actual devices justify it. Upstream recommends Home Assistant OS and supports Container; the native NixOS service has different operational ownership and does not provide Home Assistant OS app management. Consider a dedicated VM for that experience. | [Home Assistant installation types](https://www.home-assistant.io/installation/), [NixOS module](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/home-automation/home-assistant.nix) |
| Power loss        | Network UPS Tools when supported UPS hardware exists. Test shutdown ordering without cutting power to a live filesystem.                                                                                                                                                      | [Network UPS Tools](https://networkupstools.org/)                                                                                                                                                                                          |

These services should follow the media stack only when there is a household need
and an owner for updates and recovery. Running a DNS resolver or home automation
on a desktop also means that desktop shutdowns become service outages.

## Evidence still needed before deployment

The reviewed source supports the package and interface choices. It does not
establish working provider credentials, useful indexers, successful media
imports, sufficient storage, GPU acceleration, restore reliability, or
compatibility of every client with the newest server. Verify those on the
selected desktop with representative media and temporary test data.

For the VPN path, test startup without a usable tunnel, a running tunnel outage,
unit stop/restart, DNS and IPv6 behavior, and successful host API access.
Confirm that unrelated desktop traffic keeps its normal route. A synthetic
namespace test and Mullvad exit-IP check answer different questions; both are
useful, and neither proves anonymity.

The remaining package lag in the freshness table should become reviewed update
work. Use a package override only after checking its source hashes, build,
module behavior, and migration notes. Avoid nightly branches solely to make the
version column newer.
