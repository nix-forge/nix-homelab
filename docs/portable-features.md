# Portable feature configuration

Importing the default module enables no applications. Native `services.*`
options own listener addresses, accounts, packages and application settings.
Homelab options add integrations and shared policy. The consuming host owns
mounts, secret providers, public endpoints and deployment-specific presets.

## Public indexer definitions

Custom Prowlarr definitions also work with a native Prowlarr instance, without
selecting the homelab application wrapper:

```nix
{
  services.prowlarr.enable = true;
  homelab.apps.prowlarr.customDefinitions."example.yml" = ./example.yml;
}
```

Definitions must be public YAML files keyed by safe filenames. They enter the
Nix store and are installed under the effective native `dataDir`. Mutable runtime
sources and source links escaping the store are rejected. Installation refuses
symlink parents and atomically replaces declared filenames before startup;
other definitions are preserved.
Removing an option does not delete its old runtime file. Retire definitions
explicitly after reviewing any application references. Source pins and patches
belong to the consuming configuration or maintained packages.

## Private music shuffle

`homelab.music.shuffle` creates private standalone-song smart playlists and
editable override playlists. It uses the native Navidrome listener, account
and group, including custom ports, path prefixes and IPv6 loopback addresses.

```nix
{
  services.navidrome.enable = true;
  homelab.music.shuffle = {
    enable = true;
    usernameFile = "/run/secrets/music-user";
    passwordFile = "/run/secrets/music-password";
    readyUnits = [ "music-account-provisioning.service" ];
    requiredMounts = [ "/srv/media" ];
    onUnitActiveSec = "1d";
  };
}
```

Provision the selected account and mount separately. Credentials stay in runtime
files and are passed through systemd credentials. The API URL must use local
loopback HTTP or HTTPS, with no embedded credentials. `serverUrl` can select a
local TLS proxy. Managed playlists have ownership markers; ordinary playlists
and later edits to the override playlists are preserved.

## Adjustable caption presets

`homelab.optional.jellyfinCaptions` seeds Moonfin caption settings for explicitly
selected accounts. It requires native Jellyfin and a declared Moonbase plugin
package, but works independently of Seerr and the account-integration feature.
Declare the plugin through `homelab.optional.jellyfinPlugins.packages`, matching
`jellyfinCaptions.pluginName`. The host selects its reviewed package and source
pin.

```nix
{
  homelab.optional.jellyfinCaptions = {
    enable = true;
    adminUsernameFile = "/run/secrets/media-admin-user";
    adminPasswordFile = "/run/secrets/media-admin-password";
    usernameFiles = [ "/run/secrets/selected-viewer" ];
    revision = "v1";
    profiles.desktop = {
      subtitlesTextSize = 21;
      subtitlesBackgroundOpacity = 0;
    };
  };
}
```

Only caption fields are accepted. Later GUI changes belong to the user. For a
preset migration, change `revision`, set `previousRevision`, and supply the
previous values through `previousProfiles`. Migration updates missing settings
and settings still matching those old values. It preserves other values and
records completion only after the API update succeeds. Keep the private state
directory when redeploying, and use `readyUnits` for account provisioning.

## Shared PostgreSQL and storage

Native `services.postgresql.package` owns the shared database version.
AudioMuse's `database.package` is nullable and defaults to no version override.
Keep intentional version pins in the consuming host and plan database upgrades
separately. Local Arr, AudioMuse, Wardrowbe and recovery connections follow the
native port and selected filesystem socket. Native database setup uses that
socket too. Abstract-only sockets are unsupported by these local integrations
and produce compatibility assertions.

Keycloak realm bootstrap provisions a local peer-authenticated database by
default. Set `services.keycloak.bootstrapRealm.localDatabase = false` when
using an externally managed database, then configure the native database
connection explicitly. Local provisioning follows the shared socket and port.

Slskd prepares its download directories immediately before startup. Declare
`homelab.apps.slskd.requiredMounts` when those paths require separate media
mounts. Shared-storage defaults derive this requirement when applicable.
`preparationUnit` can preserve an existing unit name used by another service.
The preparer refuses sensitive system directories and symlink traversal;
custom directories use the effective native account and declared private mode.

FreshRSS's private listener integration supports Nginx. Its selected PHP-FPM
pool is configured only when a local pool exists. Custom native accounts require
a matching pool account. Recyclarr requires each selected native Sonarr/Radarr
instance and follows its effective listener. Homebridge requires Avahi only
when the configured bridge advertiser selects Avahi.

See the [portability research](research/portable-service-contracts.md) for
source contracts and verification limits.
