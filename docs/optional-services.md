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

Komga uses the shared media group as its primary group so its private user
namespace can read the library. Override `services.komga.group` when using a
different access arrangement. Recyclarr waits for enabled local Sonarr/Radarr
key-installing integration jobs that share its API key files before applying
quality policy, including jobs with custom names. Deployments without those
jobs gain no integration dependencies.

The example enables nothing by itself. Native `services.<name>` options remain
available for package overrides, application settings and secret-file paths.
User-provided files under `/run/nix-seal/system/secrets` must exist before the
corresponding application starts. This project creates no provider credentials.
Keep secret values out of Nix expressions, shell arguments and the store.

## Jellyfin plugins

Set `homelab.optional.jellyfinPlugins.packages` to named, pinned package
directories when `services.jellyfin.enable` is true. The installer runs before
Jellyfin starts and replaces a declared plugin directory only when it has a
`.nix-managed` marker. It copies a changed package into a new directory before
replacing the old one, removes stale files from the old package, and leaves UI
installed plugins alone. Removing a declaration leaves the installed directory;
remove it during attended maintenance after checking its state and backup.
Jellyfin must restart to load changed plugins. Check each package against the
selected Jellyfin version and test the plugin's actual startup before deployment.
The consuming desktop configuration selects packaged plugins and checks its
Jellyfin version before installing them.

For Moonbase, set `homelab.optional.jellyfinPlugins.moonbase.enable = true` and
provide `seerrUrl`. The declared `pluginName` must also be present in
`jellyfinPlugins.packages`. Before Jellyfin starts, the module updates only its
managed Seerr and web isolation fields in the Moonbase settings file. Other
saved plugin fields remain intact. The host still chooses the package, Seerr
endpoint, and compatible Jellyfin version.

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
The browser requires that firewall service and stops before its rules are
removed. Restarting nftables also restarts the browser; an atomic rules reload
keeps the browser running.

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

## Miniflux

Enable the native RSS and Atom reader with:

```nix
homelab.optional.apps.miniflux.enable = true;
```

The service uses the Nixpkgs Miniflux module, its local PostgreSQL database,
systemd sandbox and AppArmor policy. It listens only on `127.0.0.1:18080` by
default. Put an authenticated reverse proxy with TLS in front of it for other
devices; the consuming host owns DNS, certificate and firewall policy. Set
`services.miniflux.config.BASE_URL` to that HTTPS URL and
`services.miniflux.config.HTTPS = 1`. The module caps Miniflux at 512 MiB and
four feed workers, with two simultaneous requests per publisher host. These
are starting bounds, not measured capacity promises. The native database
setup uses a local PostgreSQL socket and no database password.
The service denies outbound connections to private network ranges while
allowing loopback for its database-independent local integrations and DNS stub.
Publisher feeds should use public HTTPS endpoints.

By default, `homelab-miniflux-credentials.service` generates a random first-run
administrator password in `/var/lib/homelab-miniflux/admin.env`. Hosts that
manage the account separately can set
`homelab.optional.miniflux.adminCredentialsFile` to a private runtime
EnvironmentFile with `ADMIN_USERNAME` and `ADMIN_PASSWORD`. The desktop host
uses a nix-seal template for this file. Miniflux does not reset an existing
user's password on later starts, so a migration must preserve the live login.
Back up PostgreSQL and the state directory together. The recovery inventory
records both, but the host still needs a backup job and a tested restore.

To start with a small source list, set
`homelab.optional.miniflux.initialFeeds = [ { url = "https://example.org/feed.xml"; category = "Reporting"; } ];`.
The bootstrapping service creates these subscriptions once and writes a marker
under `/var/lib/homelab-miniflux`. Later feed additions, deletions, filters and
category edits remain user-owned. A failed publisher request retries hourly
without blocking the reader. Export an OPML copy from Miniflux after changing
subscriptions. Use narrow per-feed rules after observing real noise; global
block rules can hide important reporting.

Each initial feed also accepts `crawler`, `scraperRules`, and `rewriteRules`.
Test publisher extraction before enabling it. Creation first imports the feed
without crawling every historical item, then configures future article fetching.
A private pending-feed journal resumes interrupted configuration without
reconciling unrelated subscriptions.

For an existing account, opt into `homelab.optional.miniflux.contentUpgrade`:

```nix
homelab.optional.miniflux.contentUpgrade = {
  revision = "article-quality-v1";
  backfillLimit = 30;
  stylesheet = builtins.readFile ./reader.css;
  disabledFeeds = [ "https://example.org/retired-feed.xml" ];
};
```

The revision applies extraction settings from `initialFeeds` once to matching
subscriptions. Deleted or disabled feeds and custom scraper/rewrite rules remain
untouched. `disabledFeeds` stops polling exact URLs without deleting entries.
The optional native-reader stylesheet installs only if the account has no custom
CSS. Increment the revision deliberately to apply another migration; ordinary
service restarts preserve later UI edits.

Backfill inspects at most `backfillLimit` recent unread entries per crawling feed,
up to 50. It replaces short excerpts only after a non-persisting fetch passes a
minimum-length comparison. It does not change titles, read state or stars.
The comparison protects against empty/short results, but is not proof of article
completeness. Progress is checkpointed; failed fetches retry up to three times,
then appear in aggregate failure counts in the revision's state JSON. Revisit
failed sources before starting another revision. Backfill restores publisher
image URLs before storage to avoid nesting Miniflux's signed image proxy.
Custom media proxies are not supported by this optional migration.

The reader can save selected entries to a separately enabled Karakeep service.
Miniflux documents the [Karakeep endpoint and API-key setup](https://miniflux.app/docs/karakeep.html).
The homelab does not start Karakeep's Chromium and Meilisearch stack merely to
run Miniflux. Private-network integrations need an explicit Miniflux setting
and should only be enabled with a reviewed local destination.

### FreshRSS visual reader

Enable `homelab.optional.apps.freshrss.enable` and supply a private
`homelab.optional.freshrss.passwordFile`, a valid `username`, and a small
`initialFeeds` list. The reusable module uses SQLite, a loopback-only nginx
listener on port 18081 and a four-worker PHP-FPM pool. It accepts a `package`
option and defaults to Nixpkgs FreshRSS. Consumers can select the reusable
`freshrss-visual` package from nixpkgs-personal, which pins FreshRSS 1.30.0
and bundles the official Grid View extension. Set
`requireGridView` so a missing extension stops first-run setup. The bootstrap
enables the grid when installed, lazy image loading, and an all-articles first
view, newest publication first, automatic light/dark mode, visible summaries,
and publisher titles. It creates private saved views for Today, This week,
Science and technology, and Space, plus Read later, Verify and Deep dive labels.
Grid View uses three columns on desktop, mobile navigation and sticky controls.
A versioned migration applies these defaults to existing accounts once; later
preferences remain user-owned. The starter OPML is imported once. Subsequent feed and viewing choices belong to the user.
A consuming host can add a separate LAN/VPN-only HTTPS site. The module does
not open a public firewall port. The desktop configuration now serves Miniflux directly and no longer enables
FreshRSS or an alternate frontend.

Grid View uses publisher-supplied feed images or content images when available.
Some articles have only a placeholder. Its optional Open Graph image fetch is
disabled in the visual package because the upstream fetcher does not validate
private addresses and redirects. The AJAX fetch endpoint also returns 403. The
site sends a no-referrer policy, but loading publisher-hosted images still
reveals the reader's IP address to those image hosts. The
application state under `/var/lib/freshrss` is included in the homelab state
inventory. Back up and restore that directory, including the SQLite database,
before major upgrades. An OPML export preserves subscriptions but not all read
state and preferences. [FreshRSS Grid View](https://github.com/FreshRSS/Extensions/tree/main/xExtension-GridView),
[FreshRSS backup guidance](https://freshrss.github.io/FreshRSS/en/admins/05_Backup.html).

FreshRSS accepts usernames without spaces. If a host runs this alongside
Miniflux, the two readers have independent reading state. Assign each reader a
separate password when promoting both to long-term use.

### Reading on an iPhone

For the visual reader, open its configured FreshRSS HTTPS URL in Safari while
on the home Wi-Fi or approved WireGuard connection. The responsive Grid View
uses one image card per row on narrow screens. Safari can add the site to the
Home Screen. For an app, FreshRSS supports the Google Reader API; API access
is enabled by the module by default (`apiEnabled`); set a separate API password
in the user profile, then connect a
compatible client such as NetNewsWire. Use the browser first to test the grid
and source mix. [FreshRSS mobile guide](https://freshrss.github.io/FreshRSS/en/users/06_Mobile_access.html),
[NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire).

Miniflux has a responsive web interface that can be added to the iPhone Home
Screen from Safari. On the desktop host, open its configured HTTPS URL while
connected to the home Wi-Fi, sign in, then use Safari's Share menu and **Add to
Home Screen**. This uses the same subscriptions and reading state as the desktop
browser and needs no separate client account.

For a native app, [NetNewsWire](https://netnewswire.com/) is a free and open
source option. Miniflux supports it through the Google Reader API: set a
separate username and password under **Settings → Integrations → Google Reader
API**, then add a FreshRSS account in NetNewsWire using the Miniflux endpoint
shown on that integration page. Keep these credentials distinct from the
administrator password. [Flux News](https://github.com/KevinCFechtel/FluxNews)
is another open source iPhone client; it uses a per-app Miniflux API key and
supports offline article reading, though it has a shorter track record.

The desktop host's HTTPS ingress currently accepts home-LAN traffic only.
Neither the web interface nor an app can synchronize from cellular networks
without an additional private route, such as a reviewed home VPN with matching
DNS, firewall and proxy access rules. A client can read only content it has
already cached while disconnected.

## Quality policy

```nix
homelab.optional.quality = {
  enable = true;
  sonarrApiKeyFile = "/run/nix-seal/system/secrets/sonarr-api-key";
  radarrApiKeyFile = "/run/nix-seal/system/secrets/radarr-api-key";
};
```

Recyclarr creates `Homelab 1080p`, allowing remux, Blu-ray and WEB sources.
Set `enable2160p = true` to add `Homelab 2160p`, which ranks all admitted 2160p
sources above their 1080p fallbacks. Within each resolution, remux ranks above
Blu-ray encodes, then WEB-DL/WEBRip. Both profiles allow upgrades through their
highest quality and use a format cutoff of 10000, so HDR or audio improvements
remain eligible. Keep native Proper/Repack behavior at `Do Not Prefer`; the
profile scores corrected releases at 5, 6 and 7.

Sizes follow the pinned TRaSH movie or series definitions, including remux limits.
These definitions affect every profile in the manager. They do not impose a small
file-size cap; storage monitoring and import free-space checks remain necessary.
The weekly sync runs on Sunday at 04:10.

HDR scores 1500, compatible Dolby Vision adds 600, and HDR10+ adds 100. Audio
preferences range from 50 for Dolby Digital to 500 for TrueHD Atmos. DD+ Atmos
scores 400. Audio is optional and stays below HDR preference. Quality rank is
compared before format scores, so an SDR remux can outrank an HDR WEB release.
Dolby Vision WEB releases without HDR fallback are rejected for mixed clients.
Legitimate SDR releases remain eligible with minimum format score zero.

See the TRaSH Guides [Radarr size limits](https://trash-guides.info/Radarr/Radarr-Quality-Settings-File-Size/),
[Sonarr size limits](https://trash-guides.info/Sonarr/Sonarr-Quality-Settings-File-Size/),
and [Radarr](https://trash-guides.info/Radarr/radarr-setup-quality-profiles/)
and [Sonarr](https://trash-guides.info/Sonarr/sonarr-setup-quality-profiles/)
profile guidance.

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
[`quality/resources.nix`](../modules/optional/quality/resources.nix), run
configuration checks and preview the sync against a disposable manager before
applying it. Review package compatibility separately and preserve Recyclarr
state with backups.
[Resource provider settings](https://recyclarr.dev/reference/settings/resource-providers/configuration/).
[Profile behavior](https://recyclarr.dev/reference/configuration/quality-profiles/),
[size definitions](https://recyclarr.dev/reference/configuration/quality-definition/).

The [4K example](../examples/quality-4k.nix) selects `enable2160p`; it does not
create a second, competing set of profile rules. New request destinations and
existing media still need an explicit profile selection. Set `enableAnimeProfile`
to add `Homelab Anime`, using the pinned guide's anime source grouping and
release-group scores with a 1080p ceiling and lower-resolution fallbacks. Its
minimum score is zero to permit unranked groups; known bad groups remain
excluded. Only this new profile resets undeclared scores. Dual audio remains an
optional preference. Series size limits are shared across the instance; a
dedicated anime instance can use anime-specific limits.

For a Seerr Sonarr destination, `extraSettings.activeAnimeProfileName` resolves
the anime profile by name, and `extraSettings.activeAnimeDirectory` selects a
registered root folder. Missing or ambiguous profiles fail before updating that
destination. This keeps anime requests separate from the ordinary TV default.

Both managers reject the pinned LQ, LQ release-title, BR-DISK, Upscaled, and
Generated Dynamic HDR patterns with -10000 scores. Sonarr consumes the pinned
Radarr generated-HDR group/title rules through a separate resource provider.
These patterns cannot prove native production resolution, detect every unlabelled
upscale, or distinguish all studio masters derived from a 2K intermediate.
The rules do not delete existing media.

Existing custom formats and undeclared scores in the two general profiles remain operator-owned
with `delete_old_custom_formats = false` and
`reset_unmatched_scores.enabled = false`. Large manually added positive scores
can offset rejection penalties. Review combined scores when customizing profiles.
See the consuming repository's media quality research for the reasoning behind
its mixed-device policy.

## Acquisition and indexer tools

| Application  | Supplied configuration                                                                                                                                      | Deployment input and workflow check                                                                                                                                                                                                                            |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| autobrr      | Loopback listener, runtime API credentials, lower background priority                                                                                        | Create an administrator, add the actual announcement network/indexers and downloader credentials, then a filter with explicit categories, size limit and daily download limit. Use a permitted test announcement to verify its action and duplicate rejection. |
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

Pinchflat uses the maintained Pinchflat-NGX package. The original Pinchflat
package is marked insecure by Nixpkgs. Existing `services.pinchflat` settings,
port, media directory and `/var/lib/pinchflat` state paths remain in use;
`services.pinchflat.package` remains overridable.

Before the first upgrade, stop `pinchflat.service` and make a private backup
of the complete `/var/lib/pinchflat` directory, including any SQLite WAL and
SHM files. Pinchflat-NGX applies database migrations before starting the UI.
To roll back, stop the service, restore that stopped-service backup, then select
the previous package; changing the package alone does not undo a database
migration. Keep the media archive backed up separately. See the
[Pinchflat-NGX migration guide](https://github.com/TheBadFella/Pinchflat-NGX/blob/b9e828a7402c38f3901ed34014cf8ec881c2f324/docs/legacy-pinchflat-migration.md).

Pinchflat requires `SECRET_KEY_BASE` with at least 64 bytes. Include
`BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` in its runtime environment file.
Its native package binds all interfaces, so keep the firewall closed and use a
private authenticated entry point. Add a media profile with an explicit maximum
resolution and download format, then a source with a bounded date range and
polling schedule. Keep automatic retention disabled until its deletion behavior
has been tested against disposable files. Its media directory defaults to
`<library>/videos`; state and temporary processing stay on the system disk.
[Pinchflat-NGX configuration](https://github.com/TheBadFella/Pinchflat-NGX/tree/b9e828a7402c38f3901ed34014cf8ec881c2f324).

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

### Managed collection policy and overlays

Set `homelab.optional.maintainerr.policyFile` to a host-managed absolute JSON
path outside the Nix store. The file is read by the `homelab-maintainerr`
account. Its optional top-level keys are `rules`, `templates`, and
`overlaySettings`. Rule and template entries use the Maintainerr v3.28 API
payload fields. Copy the `libraryId` value from
`GET /api/media-server/libraries`, and enter the same rule predicates you
reviewed in Maintainerr. A minimal manual collection policy is:

```json
{
  "rules": [{
    "name": "Reviewed Movies",
    "description": "Review only; no removal action",
    "isActive": false,
    "libraryId": "1",
    "dataType": "movie",
    "useRules": false,
    "rules": [],
    "arrAction": 4,
    "collection": {
      "deleteAfterDays": 30,
      "manualCollection": false,
      "manualCollectionName": "",
      "overlayEnabled": false
    }
  }],
  "overlaySettings": {"enabled": false}
}
```

The controller only accepts `DO_NOTHING` (`arrAction = 4`), a positive
`deleteAfterDays`, and disabled collection overlays. This handles the
version-specific ambiguity of null grace periods. The example rule is
inactive until a maintainer has inspected the library ID and collection
behavior. Templates can be declared separately with `name`, `mode` (`poster`
or `titlecard`), `canvasWidth`, `canvasHeight`, and `elements`; the controller
does not choose defaults or enable rendering. No undeclared rules or templates
are deleted.

Use `homelab-maintainerr-policy plan --config PATH --ledger
/var/lib/homelab-maintainerr/data/policy-ledger.json` as the Maintainerr account to
review the proposed create/update actions. The command prints names and
actions, never API responses. It sends only GET requests; Maintainerr may
initialize default overlay settings on the first settings GET. Take a state
backup, then explicitly run
`systemctl start homelab-maintainerr-policy.service` to apply. No boot target
starts this service. The ledger records the IDs the controller created;
preserve it with Maintainerr state. An existing UI object with the same name
causes a collision error, and changing library, data type or manual collection
identity of an owned rule is rejected. Adopt or rename the UI object manually
after reviewing its collection and exclusions. Changing the JSON file alone
does not apply it. The API permits other administrators to edit objects between
planning and applying, so review the live UI before each apply.

### Empty-show visibility

`homelab.optional.jellyfinIgnore` is independent of Maintainerr. It requires
an explicit mounted filesystem, one or more show-library roots beneath it,
and an existing non-root account that can write those roots:

```nix
homelab.optional.jellyfinIgnore = {
  enable = true;
  user = "jellyfin";
  mountPoint = "/srv/media";
  roots = [ "/srv/media/shows" ];
};
```

Check the host's actual mount and directory permissions before enabling this
example. The timer starts five minutes after boot and repeats every 30 minutes.
It scans the immediate show directories and their files recursively for common
video extensions. Only when the required mount is present does it create an
empty `.ignore` in a show without a video. It records each created file's inode
and change time in `/var/lib/homelab-jellyfin-ignore/ledger.json`. When a video
appears, it removes only that same empty file. Existing `.ignore` files, including selective
exclusion lists, are left alone. Review the [Jellyfin exclusion
rules](https://jellyfin.org/docs/general/server/media/excluding-directory/)
before choosing roots; refresh the Jellyfin library after marker changes for
them to take effect. This changes library visibility, not media contents.

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
