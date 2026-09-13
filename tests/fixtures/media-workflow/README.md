# Local media workflow fixture

The VM uses real Seerr, Radarr, qBittorrent and Jellyfin services. Only external
TMDB/SkyHook metadata, Torznab search and the torrent's HTTP webseed are
fixtures. The content is an FFmpeg-generated blue video with a silent audio
track. Credentials and the local CA are public disposable test material. The VM
trusts the fixture CA for the overridden metadata hosts. It does not disable TLS
verification.

The test submits a Seerr request, checks Radarr creates the movie, requires
Radarr to search the fixture indexer and send the torrent to qBittorrent, waits
for the client to verify its downloaded pieces, triggers Radarr's normal
completed-download poll, and verifies that Radarr creates a hardlink. Jellyfin
must then scan the imported file and serve its exact first kilobyte through an
authenticated range request by a non-admin viewer.

No fixture writes application database rows, copies media into the library or
creates the import hardlink. The synthetic video's quality minimum is explicitly
zero in the VM because its uniform content compresses much smaller than normal
films. This is not the production quality policy. The public command API
triggers scheduled work to shorten the test; provider accounts, remote network
behavior, GPU encoding and a browser client remain separate acceptance checks.

The recovery phase snapshots application state with the configured Restic job,
checks the repository's stored data, and restores into a separate directory. It
then stops application writers and replaces their state from that restored
snapshot inside the disposable VM. Reconcilers remain stopped while public APIs
must return the same request, movie, viewer, library item and torrent
identities. The restored viewer must retain restricted permissions and receive
the original media bytes. Downloaded media stays in place; this tests
application-state recovery, not a backup of the media library or a failed
physical disk.
