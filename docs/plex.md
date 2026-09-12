# Plex account setup

Enable `homelab.apps.plex` and allow the `plexmediaserver` unfree package in the
consuming system. Its library mount is read-only and firewall ports stay closed.
Hardware devices are hidden until the host explicitly sets
`services.plex.accelerationDevices`, for example to one verified render device.
Keep libraries on the shared media filesystem and Plex state on SSD.

Plex account claiming is an attended account flow. On the server, open
`http://127.0.0.1:32400/web`, sign in to your own account, claim this server,
and add the Movies and TV libraries at the corresponding shared library paths.
From another machine, establish an authenticated SSH local forward to the
server's loopback port first. Follow
[Plex's installation instructions](https://support.plex.tv/articles/200288586-installation/).
Never commit a claim token, session token or `Preferences.xml` to Git.

Keep Remote Access disabled for the private deployment. In Network settings,
leave the list of networks allowed without authentication empty. Prefer secure
connections; require them only after checking every intended client. An
unauthenticated network exception grants broad server access, not a restricted
viewer account. Grant library access through individual accounts and verify a
restricted viewer cannot change server settings or delete media.
[Network settings](https://support.plex.tv/articles/200430283-network/),
[secure connections](https://support.plex.tv/articles/206225077-how-to-use-secure-server-connections/).

Start with direct playback. Schedule library scans and expensive preview/image
work outside desktop use. Select hardware acceleration only after checking the
actual GPU, driver, codecs and account entitlement. Verify a real transcode,
software fallback, subtitle behavior and temporary-storage growth. An enabled
service or available device is not evidence of accelerated playback.

The operations inventory includes native Plex state. Back it up with Plex
stopped, preserving account state and library metadata; back up irreplaceable
media separately. Test a restore into an isolated instance before relying on it.
This repository's automated media workflow uses Jellyfin. Plex account claiming,
client playback and restored account authorization remain explicit deployment
checks because they require your account.
