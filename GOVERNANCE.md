# Governance

`nix-homelab` is a maintainer-led open source project. The current maintainer
is [@IanHollow](https://github.com/IanHollow).

The project provides reusable NixOS modules for self-hosted services. A host
owner supplies hardware, storage, credentials, backups, and final network
policy. Changes should keep those deployment decisions explicit rather than
silently choosing them for consumers.

Issues and pull requests are the public record for technical decisions. The
protected `main` branch, required checks, review rules, and merge queue apply to
all accepted changes. Security-sensitive behavior needs a clear threat-model
impact and tests for the failure path.

Code collaborators are reviewed before receiving escalated permissions for
protected-branch approval, repository administration, Pages, Actions secrets,
or release automation. The review considers sustained contribution quality,
identity or organizational affiliation where relevant, and the narrowest role
needed. Access is revisited when responsibility changes and removed promptly
when it ends.

The maintainer makes release and compatibility decisions. New maintainers may
be invited after sustained, constructive contributions and agreement on the
project's security and support expectations.

Report security issues through [SECURITY.md](SECURITY.md), not through public
issues or pull requests.
