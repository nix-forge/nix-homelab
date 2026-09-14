# Production-readiness checks

`homelab.readiness.enable` turns incomplete service configuration into NixOS
assertion failures. Enable it after importing the application, integration and
operations examples:

```nix
{
  homelab.readiness = {
    enable = true;
    hostManaged = [
      "sonarr"
      "radarr"
      "jellyfin"
      "autobrr"
      "plex"
      "syncthing"
      "scrutiny"
    ];
  };
}
```

The check is opt-in so existing hosts can adopt it without an activation-time
surprise. It never creates accounts, chooses provider credentials, grants disk
access or initializes a backup repository.

## What the check rejects

The module rejects an enabled stack when any of these declarations are absent:

- qBittorrent, SABnzbd and NZBGet runtime credential files
- Arr and Prowlarr API jobs with runtime keys and declared resources
- Bazarr settings, including a runtime API key
- Jellyfin, Seerr, Navidrome and Audiobookshelf account and library policies
- a dedicated Jellyfin automation API key after attended bootstrap
- autobrr runtime secrets, downloader clients and bounded filters
- an Unpackerr manager or watch folder and Shelfmark's runtime environment
- explicit Syncthing devices, versioned folders and GUI authentication
- immutable AdGuard Home upstream, bootstrap and bcrypt administrator settings
- an enabled Scrutiny collector with a device allowlist
- the Paperless exporter as well as its normal state backup
- the operations module, monitoring, authenticated notifications and a Restic
  job with runtime repository and password inputs
- at least one explicit required media mount when shared storage is enabled

Native service assertions still enforce service-specific requirements. These
include cross-seed's runtime settings file, Paperless's environment file,
Maintainerr's runtime htpasswd file and the Recyclarr key and ownership rules.

## Host-managed work

Some choices cannot be made safely in a reusable flake. Every enabled
application must appear in `hostManaged`. Add it only after the consuming host
has configured and tested the relevant work. This includes the ordinary import,
playback, request and credential-rotation workflow for core applications, plus:

- account onboarding for Plex, readers, photo and document applications
- provider selection and authentication for autobrr, Shelfmark and Pinchflat
- Maintainerr review, exclusions, grace periods and restore-before-delete proof
- Syncthing peer identity, folder versioning and independent recovery
- AdGuard Home LAN binding, firewall, upstream privacy and availability
- Scrutiny disk identifiers, device permissions, SMART support and alerts
- Immich database, library, machine-learning and accelerator choices

The acknowledgment records ownership. Nix cannot infer that a disk identifier
matches the installed hardware or that a restore drill succeeded.

AdGuard Home's native declarative configuration places its bcrypt password hash
in the Nix store. Use a long, unique administrator password, do not reuse it for
another service, and keep the source expression private. The hash does not grant
login access, but public copies permit offline password guessing.

The complete readiness check uses
[`tests/fixtures/readiness-host.nix`](../tests/fixtures/readiness-host.nix) to
exercise every branch during evaluation. Its fake device ID, unusable password
hash and fixture paths are test data. Do not import that file into a host.

## Deployment gate

Run `nix build .#checks.<system>.configuration-readiness` in this repository.
Then evaluate the consuming host with readiness enabled. Before activation,
follow the live tests in [testing](testing.md) and the recovery procedure in
[storage](storage.md). The [per-service audit](research/per-service-configuration-audit.md)
lists the remaining provider, hardware and restore evidence for every service.
