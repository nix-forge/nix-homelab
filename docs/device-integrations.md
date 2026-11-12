# Device integrations

`nixosModules.iot` supplies opt-in Homebridge and Scrypted modules. A host can
import it without importing media services. The regular `nixosModules.default`
includes the same modules. `nixosModules.lanHttps` separately supplies the
private HTTPS proxy, so a device host can use it without the media stack.

| Owner | Configuration |
| --- | --- |
| `nix-homelab` | Homebridge pairing initialization, managed UI login, declarative plugin links, optional VeSync credential references, Scrypted login and plugin reconciliation, private service defaults, shared HTTPS proxy policy |
| Consuming host | Package pin, network interface and address, HomeKit firewall ports, encrypted credential catalog and activation order, application plugin selection, ACME certificate, client CIDRs, backup destination and restore procedure |

Scrypted supplies the compiler runtime library search path for native Python
plugin wheels such as Arlo's `curl_cffi`. The dependency belongs to the service
module, so consumers do not need a host-specific `LD_LIBRARY_PATH` repair.

Importing these modules starts neither application. Set
`services.homebridge.enable` with `managedUi.enable`, or
`services.scrypted.enable` explicitly.
The NixOS module options require the Homebridge bridge interface, Scrypted
package and Node.js runtime, and runtime credential file paths. Pass paths such
as `config.nixSeal.secrets.<name>.path`; never interpolate credential contents
into Nix. A Scrypted plugin may be pinned to an npm version or provided as a
local Nix package artifact. Plugin and account state remains writable under the
native service state directory. The Homebridge UI binds to loopback and its
browser terminal is disabled. The host must open only its intended HomeKit
ports and decide whether to publish the admin site.

Homebridge plugin links are reconciled from the declared packages. Removing a
package removes only a link previously installed by Nix; plugins installed
through the UI remain untouched. The link helper runs as the Homebridge user
and refuses a changed link or symlinked plugin scope. Scrypted plugin
declarations install and update plugins. Removing a declaration leaves its
devices and stored plugin in place. Inspect those devices and uninstall the
plugin through Scrypted's UI before removing its runtime data. When a declared
plugin is removed or changed in the UI, the next Scrypted start compares its
database with the managed marker and reinstalls the declared version.

`homelab.operations.lanHttps` requires a host-owned certificate, literal HTTPS
listener addresses, and client CIDRs. Each named site declares a literal private
HTTP upstream. Scrypted's self-signed HTTPS API is accepted only on
`127.0.0.1`; certificate verification is disabled for that loopback hop. The
proxy rejects unknown TLS names and validates per-site CIDR overrides as well
as the default list. A host firewall should enforce the same client policy.
The certificate, DNS challenge and source-scoped firewall rule stay in the host.

Homebridge UI password reconciliation currently matches Config UI X 5.29.0.
The consuming host must pin or assert that UI version and review the hashing
code when it changes. Scrypted's database helpers are checked against the
selected server package during a build. After package updates, build the host
and verify login, plugin installation, HomeKit discovery and restart behavior
before activation. Preserve `/var/lib/homebridge` and `/var/lib/scrypted` in an
off-device backup and test a restore separately. Configuration evaluation does
not prove a camera, television or cloud account can pair on the real LAN.
