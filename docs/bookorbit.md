# BookOrbit discovery and requests

`homelab.apps.bookorbit.enable` opts into a BookOrbit catalog and a
moderated ebook, audiobook, and comic request queue. The module runs BookOrbit
and its PostgreSQL database as rootless Podman containers in the enforced VPN
namespace. `homelab.apps.bookorbit.acquisition.enable` optionally connects the
host's VPN-confined qBittorrent client and enables automatic grabs only after a
request is approved.
A consuming host supplies digest-pinned images, a dedicated UID/GID, persistent
storage paths, media directories, and runtime credential files. Keep those
files in the host's sealed-secret catalog; do not put credential values in Nix.
Set `databaseMajor` to match the PostgreSQL image. Changing that major version
requires a database migration rather than an image-only update.

The module creates a read-only `/books` mount when acquisition is disabled, a private database listener,
source reconciliation, and a private HTTPS site through
`homelab.operations.lanHttps`. The site returns 503 until the initial metadata
policy, sealed administrator, libraries, and vetted sources pass their startup
checks. Set `homelab.apps.bookorbit.https.allowedCIDRs` on the host when its client
policy differs from the gateway default. Certificate coverage, listeners, and
firewall policy remain host responsibilities.

## Prowlarr route

Use `homelab.indexerProxy.enable` and
`homelab.apps.prowlarr.proxyOnly = true`. The latter gives Prowlarr access to
loopback and the VPN namespace's host-link address while denying direct public
IP connections and host DNS. Configure a Prowlarr SOCKS5 proxy on that host-link address,
using a distinct route tag. Supply the matching name, tag, host, and port under
`homelab.apps.bookorbit.prowlarr`. Startup checks the live Prowlarr proxy and only
enables torrent indexers with that route tag and a book category. A missing or
mismatched proxy keeps the BookOrbit HTTPS site closed on startup. Direct
Prowlarr egress remains denied if the proxy changes later.

The local Unix socket bridge joins the VPN-confined BookOrbit namespace to
host-local Prowlarr. It is owned by the BookOrbit account and does not expose
Prowlarr on the LAN. The Prowlarr API key enters BookOrbit through a systemd
credential and is encrypted by BookOrbit's sealed request key.

## Boundaries and verification

The host provides two media paths: `storage.libraryDir`, mounted read-only at
`/books`, and `storage.mediaDirs`, which receive read and traverse ACLs. Define
`libraries` with matching container paths and format filters. For automated
fulfillment, declare a dedicated qBittorrent category under the downloads tree,
sealed Web UI username and password files, a Book Dock beside that category's
download directory, and the precise library folders BookOrbit may write. The
module prepares host-managed bind mounts under `/run` for only the intake and
declared writable book folders. That is needed on hosts where rootless Podman
inherits an external media mount as read-only. It mounts the common intake
parent once so the download-to-Dock hardlink test is meaningful. It checks the live qBittorrent category path and client
connection, then enables score-gated grabs and import verification. A failed
check keeps the HTTPS site closed. The module
records application and database state in the homelab operations inventory;
select and test an off-device backup destination in the consuming host.

The BookOrbit dashboard reflects scanned, owned files. The Requests form uses
metadata providers to find missing works; moderators can then search releases
through Prowlarr. Acquisition requires the optional qBittorrent configuration;
ordinary requests still need approval. Client devices have their own
DNS and VPN policy: server confinement cannot protect a browser or mobile app
outside the server. Verify HTTPS, source counts, representative searches, and
forced VPN/proxy failure on each deployment before claiming a leak-free path.

The reusable checks cover option invariants, scoped mounts, private
listeners, proxy-only egress policy, and bootstrap rejection of a mismatched
proxy. Runtime packet capture and client-side testing are still needed for a
specific network.
