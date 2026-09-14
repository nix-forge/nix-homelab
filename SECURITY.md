# Security policy

## Reporting a vulnerability

Do not open a public issue. Submit a report through
[GitHub private vulnerability reporting](https://github.com/nix-forge/nix-homelab/security/advisories/new).
If that form is unavailable, ask the maintainer for a private reporting channel
without including exploit details or credentials.

## Security model

The host kernel, root administrators, Nix inputs and VPN provider are trusted.
VPN confinement limits selected services' network egress. It does not make a
compromised application harmless, conceal traffic from the VPN provider, or
replace application authentication. Services sharing a namespace share its
network policy. This project has not had an independent security audit.

Defaults keep firewall ports closed, bind local interfaces where upstream
supports it, retain distinct service users and use restrictive media
permissions. Applications needing media playback receive a read-only library
mount. A root compromise can bypass these controls. Hosts with trusted firewall
interfaces or other broad ingress rules must review their effective exposure.

User secrets are supplied through nix-seal at runtime. The nix-seal project
currently describes itself as pre-release and unaudited for production secrets;
its maturity is a deployment limitation, not something this adapter resolves.
The user owns its target identity, encrypted sources and signed provisioning.
Never copy a complete VPN profile or plaintext application settings into Nix.

The supported dependency set is the checked-in lockfile on nixos-unstable.
Review updates, run tests and back up state before activation. No automatic
merge or production activation is configured by this repository. See
[testing](docs/testing.md) for the security failure cases and coverage limits.
