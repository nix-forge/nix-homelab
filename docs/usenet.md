# Usenet integration

Import [the example](../examples/usenet.nix) and enable the downloader you use.
The example enables neither application and leaves its example provider
disabled. Supply your real server hostname and account before enabling that
provider. Both downloaders verify TLS and limit the example to four provider
connections, with restrained unpacking work and a 20 GiB free-space floor.
Adjust connection counts against provider limits and measured disk throughput.
SABnzbd pauses downloads during post-processing, uses one direct-unpack worker,
limits its article cache to 256 MiB and verifies HTTPS certificates. NZBGet uses
sequential post-processing, two PAR threads, bounded PAR/article buffers and a
30-minute repair ceiling. It pauses downloads during repair, unpack and scripts,
and pauses rather than deleting an unhealthy job. Both policies are native
service settings and remain overridable by the consuming host. Neither module
chooses a retention rule or deletes downloaded archives automatically.

The example loads a user-provided `sabnzbd.ini` with systemd `LoadCredential`
and passes its private per-unit copy to native `services.sabnzbd.secretFiles`.
The original nix-seal file can remain root-readable only. SABnzbd's native
startup merger runs as its service user, so pointing it directly at an
inaccessible root-only source would fail. Restart SABnzbd after secret rotation.
The file supplies `[misc]` values `api_key`, `nzb_key`, `username`, and
`password`, and a `[servers]` / `[[provider]]` section containing the real
`host`, `enable = 1`, `username`, and `password`. Secret settings override
public settings at runtime; retain `ssl = 1` and `ssl_verify = 3`. The operator
owns the entire secret file. Do not put provider passwords into
`services.sabnzbd.settings`.

NZBGet's `homelab.apps.nzbget.credentialsFile` accepts a runtime fragment with
`ControlUsername`, `ControlPassword` and `Server1.Username`/`Server1.Password`.
Restricted and add-only account credentials are also accepted. The installer
merges only credential keys into the private native configuration before each
start, preserving other settings and rotating declared credentials. It rejects
noncredential options, duplicate keys and empty values before replacing the
file. Put server host, activation and TLS policy in native
`services.nzbget.settings`. Native settings become command arguments, so they
must never contain secret values. Restart the native unit after nix-seal changes
the fragment. Keep an administrative password set even for loopback access.

The integrated media example registers each enabled client automatically. Its
SABnzbd connection reads `sabnzbd-api-key`; its NZBGet connection reads
`nzbget-username` and `nzbget-password`. These small integration credentials
are deliberately separate from the downloader's complete runtime file so a
manager job cannot read provider credentials. If you are not using that
example, register either client through
`homelab.integration.services.<manager>.resources`:

```nix
{
  endpoint = "downloadclient";
  match.name = "SABnzbd";
  values = {
    enable = true;
    implementation = "Sabnzbd";
    fields = {
      host = "127.0.0.1";
      port = 8080;
      apiKey._secret = "/run/nix-seal/system/secrets/sabnzbd-api-key";
      movieCategory = "radarr";
    };
  };
}
```

Use `implementation = "Nzbget"`, port 6789, and runtime `username`/`password`
fields for NZBGet. Keep those values synchronized with `ControlUsername` and
`ControlPassword` in the native NZBGet credential fragment. Use `tvCategory`
for Sonarr, `movieCategory` for Radarr and
`musicCategory` for Lidarr, with the matching category name. If the downloader
is confined, use its configured namespace address and host ingress port. Enable
completed-download handling through `settings.downloadHandling` as in the
[integrated recipe](../examples/integrated-media.nix), and retain failed jobs
for diagnosis. Avoid remote path mappings when both applications see the same
shared paths.

Provider TLS hides article contents from the ISP but reveals the provider
connection. Select the optional VPN when that destination also needs
concealment. The provider still knows your account and requested articles.
Follow the [VPN routing contract](vpn.md) and test tunnel failure if confinement
is enabled.

The runtime credential test verifies NZBGet rotation, preservation of UI
settings, private file permissions and rejection of configuration injection.
Real provider TLS, article download, repair and manager import need a permitted
provider fixture or your own account; the example's disabled placeholder cannot
establish those results.
[NZBGet configuration](https://github.com/nzbgetcom/nzbget/blob/develop/nzbget.conf),
[SABnzbd configuration](https://sabnzbd.org/wiki/configuration/4.5/configure).
