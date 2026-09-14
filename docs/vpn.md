# Selective VPN privacy

For the distinction between configuring the dependency, changing its source and
choosing security tradeoffs, read [integration ownership](vpn-ownership.md).

The default confines qBittorrent. Sonarr, Radarr, Lidarr, Bazarr, Seerr and
media players keep ordinary host networking. This preserves discovery, playback
and local application connections. Servarr recommends restricting VPN use to the
torrent client and using an indexer proxy when selected indexers need it.
[Servarr VPN guidance](https://wiki.servarr.com/sonarr/faq#vpns-jackett-and-the-arrs)

| Traffic                         | Default            | Reason                                                                                                 |
| ------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------ |
| BitTorrent peers and trackers   | Confined           | Hide direct peer/tracker connections from the ISP and use the VPN address                              |
| SABnzbd/NZBGet                  | Host, VPN optional | Properly verified NNTPS encrypts content; VPN additionally hides the provider destination from the ISP |
| Prowlarr                        | Host               | It initiates local app sync; use a tagged indexer proxy for selected outbound searches                 |
| Arr managers and request portal | Host               | Local app access and metadata calls do not require the download client's route                         |
| Jellyfin/Plex/music/books       | Host               | Local playback and discovery need ordinary host networking                                             |
| Backups, monitoring and desktop | Host               | Use their own TLS/SSH and host access policy                                                           |

TLS protects payload contents. An ISP may still see destination IPs, timing and
volume, and DNS unless separately encrypted. A VPN shifts that visibility and
trust to its provider; it does not establish anonymity.
[Mullvad's VPN explanation](https://mullvad.net/en/help/why-mullvad-vpn)

Mullvad does not provide inbound port forwarding. Keep
`homelab.apps.qbittorrent.vpn.allowInbound = false`. Outbound peers can work,
but inbound reachability and seeding performance are limited. Opening a local
port does not restore provider forwarding.
[Mullvad port-forwarding removal](https://mullvad.net/en/blog/removing-the-support-for-forwarded-ports)

## The namespace interface

The module uses strict resolver policy and a tunnel-only route through
vpn-confinement. IPv6 is disabled inside the namespace unless a tunnel IPv6
address is supplied. Literal endpoints avoid dependence on host DNS. Runtime
keys remain outside the store.

`homelab.vpn.namespace.bindAddress` is the derived namespace address. A
downloader UI listens there; `publishToHost` allows the host to connect. It is
not a localhost proxy or LAN listener. Obtain the address through Nix evaluation
or inspect `ip -n vpnapps address`. Use that address and the configured port
when adding qBittorrent to Sonarr/Radarr. API credentials remain required.

Confined Prowlarr cannot initiate host/LAN app-sync connections. The optional
`homelab.apps.prowlarr.vpn.enable` is for a deliberately co-located namespace
stack, not the standard profile. Never widen host egress just to make a sync
button pass. Enable `homelab.indexerProxy` with a runtime `passwordFile` for an
authenticated SOCKS5 proxy. In Prowlarr, declare a SOCKS5 indexer proxy at the
namespace address and configured port, then apply its tag only to indexers that
need it. Use `socks5h` in clients that expose a proxy URL so hostname resolution
also stays inside the confined namespace. The service never publishes to the
LAN and disables request logging because destinations can contain indexer keys.
The VPN VM verifies authentication, tunnel-side DNS, LAN refusal, outage
failure and recovery.

For advanced namespaces use upstream `services.vpnConfinement` and
`systemd.services.<name>.vpn` options directly. The homelab adapter keeps the
common single-provider setup small.
[Upstream options and threat model](https://github.com/nix-forge/vpn-confinement)
