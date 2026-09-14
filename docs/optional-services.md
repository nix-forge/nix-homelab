# Optional services

Import [the example](../examples/optional-services.nix) with the default module,
then enable only the applications you intend to operate:

```nix
{
  imports = [ ./optional-services.nix ];
  homelab.optional.apps = {
    komga.enable = true;
    shelfmark.enable = true;
    unpackerr.enable = true;
  };
}
```

The example enables nothing by itself. Native `services.<name>` options remain
available for package overrides, application settings and secret-file paths.
User-provided files under `/run/nix-seal/system/secrets` must exist before the
corresponding application starts. This project creates no provider credentials.
Keep secret values out of Nix expressions, shell arguments and the store.

Optional media readers and acquisition applications wait for the existing media
mount checks. Additional output paths must stay under `homelab.storage.rootDir`.
Komga and Kavita receive a read-only library; Unpackerr can write downloads but
cannot alter the library. Shelfmark copies completed downloads into its books
output, preserving original seed data. Pinchflat can write its videos output.
Cross-seed needs a writable media mount to create hardlinks; it therefore has
broader media write access than a reader. Keep its API credential private.

Services receive lower CPU and IO weights and Nice 10. These are scheduling
preferences, not guaranteed memory or throughput limits. Unpackerr extracts one
archive at a time, Shelfmark's example permits one simultaneous download,
Pinchflat limits each yt-dlp queue to one worker, and Paperless runs one OCR
worker with one thread. FlareSolverr has a 1 GiB memory pressure threshold and 2
GiB hard limit. Adjust native systemd settings against observed workloads.

## Karakeep

Enable the native stack with:

```nix
homelab.optional.apps.karakeep.enable = true;
```

The module uses Nixpkgs' source-built Karakeep, Meilisearch and Chromium
packages. It creates separate web, worker, browser, search and secret-setup
services instead of running the three upstream container images. Karakeep,
Meilisearch and the Chrome DevTools endpoint listen only on IPv4 loopback. The
module also authenticates Meilisearch and blocks unrelated local users from the
DevTools port with a UID-based nftables rule.

The first start creates the Meilisearch master key and NextAuth secret under
`/var/lib/karakeep` with mode 0400. Subsequent starts retain them. Put provider
credentials in a runtime file outside the Nix store:

```nix
homelab.optional.karakeep = {
  environmentFile = "/run/nix-seal/system/secrets/karakeep.env";
  extraEnvironment = {
    DISABLE_SIGNUPS = "true";
  };
};
```

Do not put `MEILI_MASTER_KEY`, `NEXTAUTH_SECRET`, listener addresses or data
paths in `extraEnvironment`; the module rejects those names. Runtime launchers
restore module-owned authentication values after loading `environmentFile`.
The defaults cap the web process at 2 GiB, workers at 4 GiB, Chromium and
Meilisearch at 2 GiB each. Chromium keeps its renderer sandbox and runs under a
dedicated account. Override the systemd limits only after measuring the actual
bookmark and indexing workload.

## Quality policy

```nix
homelab.optional.quality = {
  enable = true;
  sonarrApiKeyFile = "/run/nix-seal/system/secrets/sonarr-api-key";
  radarrApiKeyFile = "/run/nix-seal/system/secrets/radarr-api-key";
};
```

Recyclarr creates `Homelab 1080p`, allowing WEB-DL and WEBRip 1080p, with
upgrades disabled. Those two qualities use minimum/preferred/maximum sizes of
5/40/80 MB per minute. This is an explicit starting policy for limited storage,
not a measured universal quality recommendation. Size definitions apply to the
whole manager instance, including other profiles. Other quality definitions come
from Recyclarr's guide resources. The profile does not delete custom formats or
reset unmatched scores. It runs weekly on Sunday at 04:10.

Select the new profile in Seerr's manager destinations and for existing managed
titles deliberately. Existing titles are not reassigned. Override the generated
native `services.recyclarr.configuration.<app>.homelab-<app>` settings to choose
upgrades, 4K or custom formats. Review changes with Recyclarr's preview before
applying them. Do not configure another reconciler to own these same profile
fields. Recyclarr's guide data is pinned separately from its package. The module
writes `settings.yml` after native secret substitution and replaces both default
resource providers with Nix-fetched local copies of immutable commits: TRaSH
Guides `a9486f6465d4483993dec638131272b397a4338e` and config templates
`9faf65ff745d74ab906fd73cadaa25f08eb9d981`. Nix verifies the archive hashes when
building the system. Sync does not fetch guide data over the network or select
another revision when a source is unavailable. Settings are module-owned and
rewritten before each run.

To update guide data, review upstream changes, update the commit URLs and
verified archive hashes in
[`quality-resources.nix`](../modules/optional/quality-resources.nix), run
configuration checks and preview the sync against a disposable manager before
applying it. Review package compatibility separately and preserve Recyclarr
state with backups.
[Resource provider settings](https://recyclarr.dev/reference/settings/resource-providers/configuration/).
[Profile behavior](https://recyclarr.dev/reference/configuration/quality-profiles/),
[size definitions](https://recyclarr.dev/reference/configuration/quality-definition/).

For a separate 4K profile, import [quality-4k.nix](../examples/quality-4k.nix).
It retains `Homelab 1080p` and adds `Homelab 4K WEB`, using WEB-DL/WEBRip 2160p.
Minimum/preferred/maximum sizes are 10/80/160 MB per minute. A two-hour release
can reach about 19.2 GB. Upgrades and score resets remain disabled, and existing
titles are not reassigned. Select this profile for chosen titles or a separate
Seerr destination. Size definitions affect every 2160p profile in that manager.
Check client playback support and storage capacity before selecting it.

The generated 1080p and optional 4K profiles also score the pinned guide's
**LQ**, **LQ (Release Title)** and **BR-DISK** custom formats at -10000, with
minimum format score 0. This excludes matching releases under these profiles; it
does not delete existing media. The guide identifies release-group/title
patterns, not measured playback quality. Review those patterns when upgrading
the fixed resources. Existing custom formats and undeclared profile scores
remain owned by the operator (`delete_old_custom_formats = false` and
`reset_unmatched_scores.enabled = false`). Manually added positive scores can
offset a negative score, so review combined scores when customizing profiles.

## Acquisition and indexer tools

| Application  | Supplied configuration                                                                                                                                      | Deployment input and workflow check                                                                                                                                                                                                                            |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| autobrr      | Loopback listener, runtime session secret, lower background priority                                                                                        | Create an administrator, add the actual announcement network/indexers and downloader credentials, then a filter with explicit categories, size limit and daily download limit. Use a permitted test announcement to verify its action and duplicate rejection. |
| cross-seed   | Loopback API, generated package defaults, strict matching, hardlinks, client injection with rechecking, 60-second search delay, daily search and hourly RSS | Supply runtime JSON containing API key, torrent client connection and actual per-indexer Torznab URLs. Confirm an injected fixture shares an inode with its original and leaves the original untouched.                                                        |
| Unpackerr    | One extraction, three retries, one-minute start and five-minute retry delays, shared-group output permissions, runtime Arr credentials and torrent-only polling in the example | Enable only the manager entries you use. Verify archive extraction, Arr import and cleanup with a disposable fixture. Original archives are retained.                                                                                              |
| FlareSolverr | Loopback endpoint, closed firewall, bounded browser memory/tasks                                                                                            | Assign only indexers that require it; verify browser egress follows the intended VPN route. No authentication is supplied by this endpoint.                                                                                                                    |

Use the [autobrr API recipe](autobrr.md) to reconcile named downloader
connections and bounded filters after supplying provider account inputs.

For cross-seed the secret JSON has this shape. Replace every placeholder inside
the user-owned secret catalog, never in a tracked Nix file:

```json
{
  "apiKey": "<random cross-seed API key>",
  "torrentClients": [
    "qbittorrent:http://<user>:<url-encoded-password>@<host-accessible-qbittorrent-address>:8081"
  ],
  "torznab": ["http://127.0.0.1:9696/<indexer-id>/api?apikey=<prowlarr-key>"]
}
```

Use the host-accessible downloader endpoint configured by vpn-confinement; port
`8081` is the module default, not an assertion about your namespace forwarding.
A Prowlarr base API URL without the indexer ID is not a Torznab endpoint. Keep
both original downloads and cross-seed links on the same filesystem. Search
rates must also respect each provider's rules.
[Cross-seed options](https://www.cross-seed.org/docs/basics/options), Unpackerr
preserves permissions stored in an archive. Its `file_mode` applies only when
the archive does not provide a mode. An archive containing owner-only files can
therefore require an attended permission repair before an Arr manager can import
them. The extraction fixture declares group-readable archive modes; it does not
establish automatic normalization of arbitrary archive permissions.

[Unpackerr configuration](https://unpackerr.zip/docs/install/configuration/).

The module does not silently route these tools through a VPN. Their outbound
requests and local API connections differ. Configure the required namespace or
proxy using [the VPN contract](vpn.md), then test success and tunnel failure. Do
not use Shelfmark's container startup scripts to create a second VPN policy.

## Books and channel archives

Choose Komga or Kavita according to your formats and clients. Add a library root
at the configured media library's `books` directory, create a restricted reader
account, and verify reading/download access with that account. Disable library
modification rights for readers. Kavita requires a runtime token-key file of at
least 512 bits. Back up its state directory as well as the books. The module
does not invent a supported API for creating either reader's users or libraries.

Shelfmark's example configures local authentication, Prowlarr discovery,
qBittorrent's `books` category and a books output folder. Supply
`PROWLARR_API_KEY`, `QBITTORRENT_USERNAME` and `QBITTORRENT_PASSWORD` in
`shelfmark.env`. Finish its local administrator onboarding, select qBittorrent
as the torrent client and choose the permitted indexers. Verify a book reaches
the reader and that the source torrent remains seedable. The module keeps
torrents and copies Usenet results instead of accepting Shelfmark 1.3.15's
job-removing `move` default; it also keeps certificate validation enabled and
does not broaden an empty Prowlarr category search automatically. Override
those choices only after an explicit retention and trust decision. Shelfmark settings
persist in its own database; environment configuration and application UI
behavior must be checked after upgrades.
[Shelfmark 1.3.15 variables](https://github.com/calibrain/shelfmark/blob/v1.3.15/docs/environment-variables.md).

Pinchflat requires `SECRET_KEY_BASE` with at least 64 bytes. Include
`BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` in its runtime environment file.
Its native package binds all interfaces, so keep the firewall closed and use a
private authenticated entry point. Add a media profile with an explicit maximum
resolution and download format, then a source with a bounded date range and
polling schedule. Keep automatic retention disabled until its deletion behavior
has been tested against disposable files. Its media directory defaults to
`<library>/videos`; state and temporary processing stay on the system disk.
[Pinchflat configuration](https://github.com/kieraneglin/pinchflat).

Komga uses private port 25600, leaving port 8080 for SABnzbd. Its library is
read-only inside the service; imports belong to the acquisition workflow.

## Photos and private documents

Immich and Paperless use their native private state and media directories,
separate from the shared media group. They are not added to the normal media
profile. Keep their databases on SSD; if moving originals to another mounted
filesystem, define the mount and preparation policy in the consuming host.
Native application tmpfiles must not create fallback directories on the system
disk before an intended mount exists. Verify missing-mount behavior before
moving valuable data.

Immich runs its native PostgreSQL/Redis integration and a loopback server. The
example retains password login and machine learning, while limiting video
encoding to two threads. Configure the first administrator through the private
endpoint, create ordinary accounts for mobile uploads, select storage and
thumbnail policy, and test a photo upload, download and album permissions.
Backup both originals and PostgreSQL, then restore into an isolated instance. A
successful database dump alone does not prove photo recovery.

Paperless's runtime environment must include the deployment's
`PAPERLESS_SECRET_KEY`; its separate password file supplies the administrator
password. OCR defaults to English, skips existing text and uses one worker and
one thread. Configure the document language explicitly if different. Add an
ordinary user with limited document permissions, configure ingestion rules and
verify that consuming a sample PDF produces searchable text without making it
visible to another user. Preserve both its database and document media.
[Immich requirements](https://docs.immich.app/install/requirements/),
[Paperless configuration](https://docs.paperless-ngx.com/configuration/).

## Host services

Syncthing starts with private administration, no discovery or relay service and
no shared folders in the example. Its filesystem sandbox preserves native folder
creation under the service account; it does not use a read-only root or hide
host home directories. Mount dependencies follow declared folders and state.
Declare actual mounts in the host and verify missing-mount failure before
sharing. Declare device IDs, explicit peer addresses, folder paths and
versioning in the host. Open synchronization ports only on the intended
interface. Verify two-device synchronization and deletion recovery. Versioning
does not replace independent backups.

AdGuard Home starts its web UI on loopback and DNS on loopback port 5353,
avoiding an accidental replacement of the host resolver. Configure upstream
resolvers, bootstrap addresses, filters and administrative access before
directing clients to it. A host deployment must deliberately choose port 53 and
the household interface. Do not make an intermittently running desktop the only
DNS server.

Scrutiny keeps its web service on loopback port 8083 and bundled InfluxDB on
loopback port 8086, avoiding SABnzbd's port 8080. Its collector is disabled
until the consuming host explicitly enables it. At this Nixpkgs pin, enabling
the native collector runs it as root and also enables smartd with a 600-second
polling argument. Review the host's existing SMART configuration before making
that choice; enabling the web UI does not select hardware or change SMART
policy.

A host that has verified its device paths can configure:

```nix
services.scrutiny.collector = {
  enable = true;
  schedule = "daily";
  settings = {
    # Replace with actual paths reported by smartctl --scan.
    allow_listed_devices = [ "/dev/sdX" ];
    # Add only if this disk's USB bridge requires and supports this type.
    devices = [ { device = "/dev/sdX"; type = [ "sat" ]; } ];
  };
};
```

The allow-list limits which detected devices Scrutiny collects; a `devices`
entry alone is an override, not an allow-list. It does not configure smartd's
separate device policy. Omit USB type overrides for devices that do not require
them. Confirm the real disk appears and inspect collection failures. For one
drive, smartd alone may meet the monitoring need with fewer processes.
[Collector configuration at the package pin](https://github.com/AnalogJ/scrutiny/blob/v0.9.3/example.collector.yaml).

## Maintainerr

`homelab.optional.apps.maintainerr.enable` runs the source-built Maintainerr
3.28.0 package from nixpkgs-personal. The build uses Node.js 26, the upstream
Yarn lockfile and a fixed offline dependency cache. It compiles native addons
against Nixpkgs libraries instead of unpacking the upstream OCI image.

The native systemd service runs under a dedicated account with no capabilities,
no new privileges, a read-only system, private devices and temporary files, and
restricted kernel and namespace access. It retains the previous limits of 1 GiB
memory, one CPU and 256 tasks. No media directory is available to the process.
Application state lives under `/var/lib/homelab-maintainerr/data`; preserve this
directory and its ownership in recovery planning. The dedicated UID defaults to
62460; set `homelab.optional.maintainerr.uid` to an unused value before first
activation if that UID is already allocated.

The example requires a nix-seal `maintainerr-htpasswd` file. Nginx loads it
using systemd credentials and serves authenticated access on `127.0.0.1:6246`.
The native loopback backend on port 6247 is restricted by nftables to nginx,
root and the dedicated service account. Other local service users cannot bypass
authentication. The proxy strips browser Basic credentials before forwarding
and disables buffering for Maintainerr's live event streams. Add TLS in the
consuming host before exposing this endpoint beyond loopback, and restart nginx
after rotating the runtime htpasswd file.

Configure the actual media-server and Arr/Seerr connections after authenticating
through nginx. Existing `host.containers.internal` URLs keep working through a
loopback compatibility alias; new settings can use `127.0.0.1` and the native
service port. A service in a VPN namespace still needs its configured
host-visible endpoint.
Start with reviewed collections and generous grace periods; verify rules against
disposable media before authorizing removal. Absence of a media bind prevents
filesystem cleanup but does not prevent deletion through supplied Arr or
media-server APIs. This module configures no deletion rules and disables
telemetry. Systemd waits for `/api/health/ready`, including its SQLite check,
before startup succeeds. Starting the service needs no registry or package
network access. Updating the release requires reviewing the source revision,
source hash, Yarn dependency hashes, build requirements and migrations. The
[native package research](research/maintainerr-native-package.md) records the
3.28.0 build and service decisions. Upstream documents the
[installation and health checks](https://docs.maintainerr.info/installation/)
and [access limitations](https://docs.maintainerr.info/configuration/).

## Jellyfin hardware selection

Hardware selection belongs in the consuming host. For a verified VA-API device:

```nix
services.jellyfin = {
  hardwareAcceleration = {
    enable = true;
    type = "vaapi";
    device = "/dev/dri/renderD128";
  };
  forceEncodingConfig = true;
  transcoding = {
    enableHardwareEncoding = true;
    hardwareDecodingCodecs = { h264 = true; hevc = true; };
    threadCount = 2;
    throttleTranscoding = true;
  };
};
```

Verify the render device, driver and codec support first. The native module
configures access to that device. At the inspected pin, `maxConcurrentStreams`
and `deleteSegments` are declared options but are not written by its encoding
XML generator. Do not rely on those options to enforce limits. Configure and
verify the required application behavior before claiming a stream or cache cap.
`forceEncodingConfig` overwrites UI encoding changes on restart. Test direct
play, a real hardware transcode, unsupported-codec fallback, subtitle handling
and HDR behavior. Keep transcode cache on bounded SSD storage, not an unbounded
RAM filesystem. Record CPU/GPU use and cache growth before claiming an
improvement.
[Jellyfin acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/).

## Verification scope

The optional evaluation contracts check opt-in behavior, closed firewall ports,
media mount dependencies, output path rejection, read-only reader mounts,
runtime quality-key requirements and selected worker limits. They do not prove
runtime behavior. Separate [native checks](testing.md) exercise extraction,
cross-seeding, quality reconciliation, book access and photo/document recovery
with disposable data. Real provider integration, hardware acceleration and
recovery of the deployed host remain deployment checks.
