# Native cross-seed fixture

The real qBittorrent client downloads a generated video from a local webseed.
The local Torznab fixture then offers the same file tree and content with a
different piece size, producing a different torrent info hash. An authenticated
native cross-seed webhook must search, match in strict mode, create a hardlink
under the configured link directory and inject the candidate into qBittorrent.
The client must finish its required recheck with no additional webseed transfer.

Credentials and video are public disposable fixtures. The test does not create
the matching link, modify application databases or disable native rechecking. It
also checks that an unauthenticated webhook fails. Remote tracker accounts,
provider rate limits and VPN behavior have separate acceptance checks.
