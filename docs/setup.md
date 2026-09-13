# Setup in an existing NixOS configuration

This is a reusable module, not a disk installer. Keep the desktop or server host
in its existing configuration repository. Add an input and import the module:

```nix
{
  inputs.nix-homelab.url = "github:nix-forge/nix-homelab";
  # Use the project's tested package set, or consciously validate a follows override.
  outputs = inputs: {
    nixosConfigurations.my-host = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        inputs.nix-homelab.nixosModules.default
        ./configuration.nix
        ./homelab.nix
      ];
    };
  };
}
```

Retain your host's existing nix-seal input and module. Configure its public
administrator catalog, target identity and encrypted sources in the host
repository. No second agenix secret manager is needed. The adapter in
[examples/nix-seal.nix](../examples/nix-seal.nix) declares two user-supplied
secrets and passes their `.path` values to the VPN and qBittorrent. Import it
after configuring nix-seal. Provision the signed target artifacts using the
pinned
[nix-seal preparation workflow](https://github.com/nix-forge/nix-seal#readme)
before activation. The homelab project neither creates nor asks to read them.

## WireGuard profile

Use [the media example](../examples/media-server.nix) as a host module. Replace
its documentation addresses and peer key with the user's Mullvad profile. The
profile's private key is the content of the nix-seal VPN secret, never a Nix
string. Map `Address` to `interface.addressIPv4` and optional `addressIPv6`,
without their prefix lengths. Map `DNS` to `interface.dns`, and the peer's
`PublicKey` and literal `Endpoint` address/port to `peer.publicKey`,
`peer.endpointHost` and `peer.endpointPort`.

Import the nix-seal adapter instead of leaving the example's runtime key path.
The actual path comes from `config.nixSeal.secrets.<name>.path`; do not guess
nix-seal's administrator or target directory layout. If copying the two examples
into one host, remove `privateKeyFile` from the provider example so it has
exactly one definition.

Mullvad has no inbound forwarding, so leave `vpn.allowInbound` disabled. Confirm
the namespace name and network policy in [VPN guidance](vpn.md).

## Application credentials and configuration

The qBittorrent credential secret is an INI fragment generated from a private
qBittorrent configuration:

```ini
[Preferences]
WebUI\Username=YOUR_USER
WebUI\Password_PBKDF2=YOUR_GENERATED_QBITTORRENT_HASH
```

Keep the real values encrypted in nix-seal. The secret is loaded as a systemd
credential and merged after generated public settings on every start. Without
this file, use the upstream first-run temporary password and then configure a
persistent runtime credential before relying on restarts. The public settings
file is declarative; do not rely on UI-only configuration changes surviving.

Configure Sonarr/Radarr/Prowlarr through their setup UIs or their native
`environmentFiles` for API secrets. Enable authentication before allowing remote
access. Sonarr's default port is 8989, Radarr 7878, Lidarr 8686, Prowlarr 9696,
Bazarr 6767 and Seerr 5055. Seerr connects to the selected player and to library
managers; it is a request portal, not a downloader.

Add qBittorrent to the library managers using the evaluated
`homelab.vpn.namespace.bindAddress` and port 8081, plus its credentials. Create
separate movie and TV categories. Set library roots to
`<rootDir>/library/movies` and `<rootDir>/library/tv`. Keep paths identical
across applications. Prowlarr can sync indexers to the host-side managers.
Configure Bazarr to the same managers and library paths. Add those libraries to
Jellyfin and connect Seerr to Jellyfin, Sonarr and Radarr.

For Usenet, choose SABnzbd or NZBGet instead of enabling both without a reason.
The standard Usenet packages depend on unrar. Explicitly allow only `unrar` in
the consuming host's `nixpkgs.config.allowUnfreePredicate` if selecting these
packages. Plex separately requires `plexmediaserver`.

SABnzbd accepts `services.sabnzbd.secretFiles` containing runtime INI settings;
ensure its service user can read the nix-seal output or use systemd credentials
and their credential-directory paths. Its settings are declarative even on older
host state versions. NZBGet keeps provider credentials in its private state and
applies declared path and listener overrides on startup. Use provider TLS with
certificate verification. The [extras example](../examples/extras.nix) shows the
shared Recyclarr policy, private autobrr defaults and a node exporter; replace
illustrative secret paths with actual nix-seal `.path` references.
[Autobrr integration](autobrr.md) supplies the downloader and filter recipe.

## Storage and private access

Declare the existing media mount in the host and set `requiredMounts` to that
mount. Check its contents and free space before enabling downloads. Read
[storage and recovery](storage.md) for the shared 4 TB media/backup arrangement.
Importing this project does not activate a disk migration.

Use a browser on the desktop for localhost services. Namespace UIs use the
host-link address. To access from another computer, configure the host's SSH
tunnel, trusted private access network or authenticated TLS reverse proxy.
Services with no upstream bind-address option remain protected by the host
firewall. This project opens no LAN or public ports for you.

## Validate before activation

Evaluate and build through the consuming repository's ordinary workflow. Back up
application state before its first upgrade. After activation, verify service
health, a real tunnel handshake, blocked traffic with the tunnel down, indexer
search, a permitted download, hardlink import, request fulfillment and playback.
Check resource use and an isolated restore. Keep the previous system generation
and the matching state backup until those checks pass.

## Complete application relationships

After defining native services and host-owned runtime secrets, use the
[integration guide](integration.md) and
[integrated media example](../examples/integrated-media.nix) to register manager
roots, download clients, Prowlarr connections, Jellyfin libraries/accounts and
Seerr destinations. Keep every provider endpoint and account explicit. The
example's secrets are required inputs, not files this flake creates.

Use [audio](../examples/audio.nix), [Usenet](usenet.md), and
[optional services](optional-services.md) for the additional workloads you
select. Import [operations](operations.md) before relying on persistent
application state. Attach its backup preparation to the host's existing Restic
job and practice recovery with a separate restore target.

Choose one tool to own each application field. Review Recyclarr changes before
applying them; avoid concurrent UI edits while a managed API job changes the
same object. Application upgrades still require backup and compatibility review.

Managers receive one writable mount for the dedicated media root. Keep downloads
and libraries in separate directories beneath that root on one filesystem;
separate mounts can force copies even when both paths report the same device.
Keep backup repositories outside this writable media root. Player library views
remain read-only, and downloader access is limited to download staging.
