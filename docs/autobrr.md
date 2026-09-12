# Autobrr connections and filters

Import [the native service example](../examples/optional-services.nix) and
[the API recipe](../examples/autobrr.nix). Supply the session secret, API token
and downloader credentials through your host's nix-seal catalog. Create the
provider's indexer and IRC connection in autobrr using your own account. Replace
the recipe's exact indexer name and selected release expression before running
its preview. The example filter starts disabled and its action adds downloads
paused; review a permitted announcement and downloader destination before
enabling unattended downloads. A VPN does not replace provider account
requirements.

The adapter resolves downloader names into action client IDs and indexer names
into filter associations. It supports qBittorrent, SABnzbd, NZBGet, Sonarr,
Radarr and Lidarr clients. Enabled filters require explicit indexers, a release
selector, maximum size and a bounded download count. It disables a changing
filter until its declared actions finish updating; a failed operation leaves the
filter disabled. Check the integration status before enabling it manually.

Every filter declaration must set `values.enabled` explicitly. This keeps the
intended activation state stable if a failed action update is retried.

For a qBittorrent HTTPS URL, explicitly set `tls = true`. Autobrr derives the
connection scheme from that separate field. The adapter rejects contradictory
URL and TLS settings and refuses disabled certificate verification.

Managed updates preserve undeclared filters, actions, indexer associations and
filter fields. Native PATCH semantics avoid replacing unrelated external filters
or notifications. Bootstrap mode preserves an existing filter completely; an
interrupted first bootstrap may therefore need managed mode to finish its
actions. There are no delete calls. Provider announcements and torrent injection
still need an attended test against your own provider; HTTP fixture tests cover
API reconciliation, preservation, dry runs and failure handling.

Autobrr redacts downloader passwords and API keys. Its native update handler
preserves those redacted fields when they are undeclared. Declared credentials
use salted scrypt fingerprints in the integration's private state directory so
unchanged credentials are not replayed on every run. A credential changed only
through the UI cannot be compared with the declaration through this API; rotate
the declared value or clear that integration's fingerprint state to reapply it.

The implementation targets pinned autobrr 1.84.0's
[download client updates](https://github.com/autobrr/autobrr/blob/v1.84.0/internal/download_client/service.go),
[filter updates](https://github.com/autobrr/autobrr/blob/v1.84.0/internal/filter/service.go)
and
[HTTP routes](https://github.com/autobrr/autobrr/blob/v1.84.0/internal/http/server.go).
