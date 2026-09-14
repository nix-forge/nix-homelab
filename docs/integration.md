# Application integration

Import `nixosModules.default`, choose the applications, and start with the typed
`homelab.integrations` declarations. Keep `homelab.integration.services` as the
schema-checked compatibility layer for applications without a focused module. The
[integrated media example](../examples/integrated-media.nix) connects Sonarr,
Radarr, Lidarr, Prowlarr, qBittorrent, Jellyfin, Seerr and Bazarr. It also
selects a Recyclarr quality profile. Host configuration must supply the VPN,
existing mounts and nix-seal secret files before enabling it.

An enabled daemon does not imply a configured workflow. Integration jobs call
application APIs after startup and repeat on a bounded timer. Their journals
contain operation counts and sanitized errors, never response bodies or secrets.
A failed job leaves its failure visible; a later run retries from the current
API state. Writes are not automatically retried after an ambiguous network
failure.

## Ownership and safe updates

Every job chooses a mode:

- `bootstrap` creates missing collection objects and preserves existing objects.
  It does not continually overwrite changes made in the application UI.
- `managed` updates the fields explicitly declared for matching objects. Other
  fields and undeclared objects remain intact.

Neither mode deletes libraries, users, indexers, profiles or manager connections
when declarations disappear. Remove those objects explicitly in the application
only after reviewing their data and dependent settings. Provider implementation
changes and ambiguous names fail rather than replacing an existing object.

Singleton settings need special care. Seerr applies bootstrap singleton settings
only during initial onboarding. Bazarr has no equivalent onboarding state;
bootstrap leaves its existing settings untouched. Use managed mode for declared
Bazarr settings.

The CLI accepts a generated JSON configuration and `--dry-run`. Run previews
with an isolated systemd credential directory and the same endpoint access as
the real job. Dry runs can authenticate and validate connections, but do not
write application configuration. An uninitialized player or portal reports that
bootstrap is required before a full preview is possible.

## User-provided credentials

Use `apiKeyFile` for an API key and `{ _secret = "/run/..."; }` for secret
values inside settings or resource fields. The module transforms these into
systemd `LoadCredential` references. Never use `builtins.readFile` on a secret
or put a password directly in a Nix value. API keys, passwords and token fields
reject literal nonempty values during evaluation.

For local Sonarr, Radarr, Lidarr and Prowlarr, `installApiKey = true` installs
the same key into a private runtime environment file for the native service.
Supply a 32-character alphanumeric API key. Remote services should leave this
option disabled. Keep native browser authentication enabled.

In nix-conf, order key installation and integration after the consuming nix-seal
activation unit. Configure the secret's restart units to include its
`homelab-key-NAME.service`, the application and
`homelab-integrate-NAME.service`. The runtime key installation unit must rerun
before the application restart after a rotation. A timer refreshes API client
credentials; it does not independently replace an application's own key.

qBittorrent uses its existing runtime INI for the login verifier. Client
connections also need the corresponding username and plaintext password as
separate runtime credentials. Bazarr also supports `installApiKey`, merging its
key into private YAML before startup while preserving other settings. Restart
Bazarr after replacing its key. It does not use the Servarr environment
mechanism. Provider registrations, subtitle accounts and Plex account claims
remain user-supplied deployment inputs.

## Managers and indexers

`homelab.integrations.downloadClients` declares each connection once.
`homelab.integrations.servarr.<instance>` then references those clients and owns
typed roots, categories, tags, import policy, naming, and notifications. Instance
names are independent of application kinds, so two Sonarr or Radarr deployments
can coexist when their URLs, roots, and categories are distinct. qBittorrent
categories are created from the same declaration before manager reconciliation;
undeclared categories and tags are never removed.

`homelab.integrations.prowlarr` references those same named Servarr instances.
It supplies the pinned Prowlarr category defaults, creates application links,
and supports typed HTTP, SOCKS5, and FlareSolverr indexer proxies. Indexer
providers remain opt-in because their fields and accounts vary by provider.
Put provider credentials in `secretFields`; literal fields whose names look like
passwords, tokens, cookies, passkeys, or API keys fail evaluation. A dry run can
plan a proxy whose tag is created earlier in the same declaration without
inventing a server-side ID.

For selective VPN egress, enable `homelab.indexerProxy` with a runtime
`passwordFile`. The integrated example automatically exposes it to Prowlarr as
an authenticated SOCKS5 proxy tagged `vpn`. Apply that tag only to indexers that
need it. DNS resolution, authentication, LAN refusal, tunnel loss, and recovery
are covered by the VPN namespace VM test.

Each Arr resource has an `endpoint`, a stable `match` and `values`. Match by
`name`, `path` or `label`. Supported collection endpoints include root folders,
download clients, indexers, Prowlarr applications, quality profiles, tags,
notifications, delay profiles and remote path mappings.

Supported `settings` keys are checked against an adapter-specific contract
during Nix evaluation. This catches misspelled sections and wrong structural
types before a timer reaches an application. Fast-moving upstream fields can be
placed under `extraSettings`; those values recursively override `settings`,
retain runtime-secret checks, and carry no compatibility promise. Arr provider
payloads have the equivalent `extraResources` escape hatch. Prefer the typed
surface and move a field back from an escape hatch once the module adopts it.

For managers, `settings.downloadHandling` manages completed-download and retry
policy. `settings.mediaManagement` covers the bounded, storage-relevant Servarr
settings, and `settings.naming` covers the native Sonarr, Radarr and Lidarr
naming models. The integrated recipe enables hardlinks, keeps a 20 GiB import
floor, moves deleted or upgraded media into per-manager recycle directories for
30 days, rescans after manual refreshes, and records quality, codec, custom
format and release-group metadata in video filenames. It retains completed and
failed downloader jobs for attended cleanup and disables automatic failed-job
retry. The adapter validates each field against the selected manager and merges
only declared values. Bootstrap mode preserves singleton settings; managed mode
updates declared fields without replacing unrelated values.
[Radarr download-handling settings](https://github.com/Radarr/Radarr/blob/develop/src/Radarr.Api.V3/Config/DownloadClientConfigResource.cs),
[per-client removal policy](https://github.com/Radarr/Radarr/blob/develop/src/Radarr.Api.V3/DownloadClient/DownloadClientResource.cs).

Provider resources declare an `implementation`. On creation the job obtains the
application's schema and merges declared fields into its defaults. Unknown
provider fields fail. On updates it preserves unspecified fields. For example:

```nix
{
  endpoint = "downloadclient";
  match.name = "qBittorrent";
  values = {
    implementation = "QBittorrent";
    enable = true;
    fields = {
      host = config.homelab.apps.qbittorrent.bindAddress;
      port = config.homelab.apps.qbittorrent.webuiPort;
      movieCategory = "radarr";
      username._secret = "/run/nix-seal/system/secrets/qbit-user";
      password._secret = "/run/nix-seal/system/secrets/qbit-password";
    };
  };
}
```

Use the same filesystem paths in the downloader and manager. Native applications
validate provider connectivity and paths; an invalid integration must fail its
job. Recyclarr should own quality settings where enabled. Do not configure the
same profiles with two competing reconcilers.

The integrated recipe always registers qBittorrent and conditionally registers
SABnzbd or NZBGet when either is enabled. A category must be unique for a given
client; distinct clients may use the same workflow category.
SABnzbd needs `sabnzbd-api-key`; NZBGet needs `nzbget-username` and
`nzbget-password` runtime secrets in addition to its native credential fragment.
This intentional separation lets systemd pass only the fields each integration
job needs. Import the Usenet example to create matching native categories and
provider policy. Do not enable both Usenet clients for the same provider queue
unless the host deliberately wants both choices.

## Jellyfin and Seerr

`homelab.integrations.jellyfin` exposes initial administrator setup, portable
encoding limits, named libraries, and named users. User defaults allow playback
and remuxing but deny administration, deletion, downloads, remote access,
transcoding, and blanket library access. Any broader grant is visible in the
host configuration. Native `services.jellyfin` options still own packages,
devices, hardware acceleration, and process configuration. Version-specific
library, policy, and encoding fields have narrowly named escape hatches.

In managed mode, a library's declared paths replace its actual media path
references. New paths are attached before old references are removed. This
preserves the library ID and the files on disk. Bootstrap mode leaves existing
paths alone, and removing a library declaration does not delete that library.

Managed user passwords update through the API when their runtime value changes.
A private state file records salted scrypt password fingerprints so periodic
runs do not revoke sessions unnecessarily. Include this state in operational
backups. Changing the administrator credential used to authenticate requires
coordination with the server's current credential or a separately supplied
administrator API key.

Jellyfin bootstrap can begin with `settings.login`. After onboarding, create a
dedicated administrator API key, store it in a runtime secret, and set
`apiKeyFile`. Recurring reconciliation then survives attended administrator
password changes. Production readiness rejects password-only recurring
Jellyfin automation. When an API key rotates the administrator password, the
request intentionally omits the stale `CurrentPw` field.

`homelab.integrations.seerr` derives administrator credentials from the typed
Jellyfin declaration and derives each request destination from a named Servarr
instance and root. It resolves quality profiles by name and validates the root
against the live manager. Default permissions grant requests without automatic
approval. Auto-approval and automatic-request permissions fail evaluation until
`allowAutomaticRequests` is explicitly enabled. Movie and television quotas are
typed rolling windows; omitted quotas remain unmanaged. Existing manual
destinations remain intact.

Bazarr settings mirror its nested API settings, such as `general`, `sonarr` and
`radarr`. The adapter validates field names against the running service and
sends form-encoded updates. This differs from the JSON request body in the
inspected peer example: current Bazarr reads `request.form`.
[Bazarr settings implementation](https://github.com/morpheus65535/bazarr/blob/master/bazarr/api/system/settings.py).

## Verification

`integration-behavior` exercises the public CLI with authenticated local HTTP
fixtures. It covers creation, repeated application, manual-field preservation,
credential replacement, dry runs, bootstrap behavior, provider schema errors,
player onboarding, request destination selection and Bazarr form encoding.
`configuration-integration` evaluates the Nix credential, timer, resource and
native key wiring contracts. Real-service VM tests provide separate evidence;
these HTTP fixtures alone do not prove an external-provider download workflow.

## Music, audiobooks and podcasts

The [audio example](../examples/audio.nix) bootstraps Navidrome and
Audiobookshelf accounts from runtime passwords. Managed mode updates declared
user fields and rotates changed passwords; undeclared accounts remain intact.
Audiobookshelf creates explicit audiobook and podcast libraries. Existing media
is read-only to the players; podcast downloads have a separate writable path.

Navidrome uses its authenticated native API with `X-ND-Authorization`. Its first
administrator endpoint independently rejects initialization after any user
exists. Audiobookshelf uses its initialization endpoint only while the server
reports that no root account exists, then authenticates through its login API.
After bootstrap, create a named Audiobookshelf API key for a dedicated
automation administrator and set the integration job's `apiKeyFile` to its
runtime secret path. These keys are revocable, may expire and are intended for
server-to-server automation. When a key is present, the reconciler uses it as a
Bearer credential instead of retaining a human login password. Keep
password-based bootstrap only as long as initialization requires it.
Administrator login-password changes need coordination with the current server
credential. Navidrome rejects the integration administrator in `settings.users`;
change that account through an attended native account update, then update the
login credential. Names match without case distinctions, and duplicate
declarations are rejected before account writes. Do not use the everyday
listener account for configuration.
[Navidrome authentication](https://github.com/navidrome/navidrome/blob/v0.63.2/server/auth.go),
[Audiobookshelf API](https://api.audiobookshelf.org/), and
[Audiobookshelf API keys](https://audiobookshelf.org/docs/documentation/server-management/api-keys/).

The Navidrome defaults bound concurrent transcodes to two overall and one per
user, cancel abandoned transcodes, limit the transcoding cache and delay scans
until file activity settles. Symlink traversal and public sharing are disabled.
Override native settings deliberately if the existing library requires symlinks.
[Jellyfin's encoding settings](https://github.com/jellyfin/jellyfin/blob/master/MediaBrowser.Model/Configuration/EncodingOptions.cs)
can be managed through `settings.encoding`; unknown fields fail. The integrated
example bounds encoding threads and enables throttling and segment deletion
without selecting an unverified GPU. Host-selected hardware remains a native
Jellyfin configuration choice.

Named Arr foreign keys can use
`{ _lookup = { endpoint = "qualityprofile"; name = "Standard"; }; }`. The
adapter resolves exactly one current ID and fails if the name is absent or
ambiguous. The complete media example uses this for Lidarr's metadata and
quality profiles, so fresh databases need no guessed IDs. Its music root
monitors future releases without automatically monitoring every newly discovered
item.

Bazarr's `settings.languageProfiles` maps names to language profile fields. The
adapter retains undeclared profiles because Bazarr's API replaces the entire
collection. Avoid editing language profiles in the UI during a reconciliation
run; that upstream endpoint has no conditional-update mechanism. Provider
selection and credentials remain explicit user inputs under native Bazarr
settings sections. Choose providers before scheduling searches.

The audio example requires a stable `ND_PASSWORDENCRYPTIONKEY` in the Navidrome
runtime environment file. Preserve that key with the host's encrypted secret
catalog and recovery material. Changing it after Navidrome encrypts passwords
can prevent authentication. This key has a different lifecycle from account
passwords. See
[Navidrome's security guidance](https://www.navidrome.org/docs/usage/admin/security/).

Bazarr also accepts `settings.enabledLanguages = [ "en" ]` and
`settings.defaultProfiles = { series = "English"; movies = "English"; }`.
Defaults resolve the declared or existing profile by name and apply to newly
added media. Existing per-title assignments are preserved. Enabled languages are
added to the current selection. The integrated example runs one subtitle job at
a time, searches daily, and checks upgrades weekly without upgrading manually
downloaded subtitles. Provider selection and runtime account credentials remain
explicit operator inputs under the provider's native settings section. These
controls do not guarantee subtitle availability.
[Bazarr configuration](https://github.com/morpheus65535/bazarr/blob/master/bazarr/app/config.py),
[settings API](https://github.com/morpheus65535/bazarr/blob/master/bazarr/api/system/settings.py).

Autobrr has a separate [connection and filter recipe](autobrr.md), including
named client/indexer references, bounded filters and private credential
rotation. It uses the same timers, previews and runtime credential transport.
