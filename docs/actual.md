# Actual Budget

Enable the native NixOS service after importing the homelab module:

```nix
{
  services.actual.enable = true;
  homelab.operations.enable = true;
}
```

The [service policy](../modules/services/actual.nix) keeps the listener on
`127.0.0.1:5006` and leaves the firewall closed. The host owns its HTTPS proxy,
access rules and first-user enrollment. Complete enrollment privately before
exposing the frontend, and keep credentials out of Nix expressions and the store.

Password login is the default. OpenID requires `loginMethod = "openid"`,
`allowedLoginMethods = [ "openid" ]` and `enforceOpenId = true` under
`services.actual.settings`. Header authentication is rejected. Proxy trust stays
limited to the loopback proxy; authentication headers from other proxies are
not trusted.

With operations enabled, the state inventory includes the complete
`services.actual.settings.dataDir` and `actual.service`. Server files and budget
files must remain beneath that directory. Quiesce the service before taking a
consistent backup and test restoration in isolation. The `/health` endpoint
reports backend liveness; it does not prove login, browser synchronization or
budget recovery. See [operations](operations.md) for the recovery workflow and
[testing](testing.md) for the distinction between configuration and runtime checks.
