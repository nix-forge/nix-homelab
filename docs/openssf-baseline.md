# OpenSSF baseline policy

This repository uses the [OSPS Baseline](https://baseline.openssf.org/versions/2026-08-28)
version 2026.08.28 as its security policy reference. The policy covers the NixOS services, deployment examples,
documentation, CI, and source history.

## Current assessed status

The [current self-assessment](https://www.bestpractices.dev/en/projects/14638/baseline-2)
records OSPS Baseline Level 2 for version 2026.08.28. The project does
**not** claim Level 3. OSPS-QA-07.01 at Level 3 requires every change to receive
approval from at least one human reviewer who did not author it. The project
currently has one maintainer, and the protected `main` branch requires zero
approving reviews. This control is **unmet** in the published assessment, so the Baseline badge
displays Level 2. A future Level 3 claim needs both the independent
review process and an evidence-backed assessment of all other Level 3 controls.

## Project scope and releases

nix-homelab is a reusable NixOS service configuration with deployment examples.
It does not currently publish compiled release assets or official GitHub
releases. [docs/releases.md](releases.md) records the conditions for a future
source release, including an immutable tag, a change log, integrity evidence,
security review, and a support window.
The SLSA scope and future builder contract are documented in
[docs/slsa.md](slsa.md).

This repository is part of the related projects listed in the
[nix-forge project security contract](https://github.com/nix-forge/.github/blob/main/PROJECTS.md).
Related repositories enforce the same minimum security contract or a stricter
one for their own code and release surfaces.

## Change and build controls

Every commit must carry a matching Signed-off-by trailer. The DCO file defines
the certificate and .github/workflows/dco.yml checks proposed non-merge commits
on pull requests and merge-group refs.

All workflows start with empty default permissions. Jobs grant only the scopes
they need, checkout does not persist credentials, and actions use full commit
SHAs. Pull requests and merge groups run flake checks, dependency review,
CodeQL, documentation checks, and the repository test suite before protected
main can advance.

Use [docs/testing.md](testing.md), normally:

    nix flake check --show-trace
    python3 -m unittest discover -s tests

Changes to service defaults, credentials, network access, or lifecycle behavior
include an observable test and a migration note. Never commit credentials,
private host data, or plaintext fixtures.

## Release and dependency controls

Flake inputs and generated references are reviewed with their security and
compatibility impact. Dependency review blocks new low-or-higher severity
vulnerabilities. CodeQL and SCA findings must be fixed before a future release
unless a reviewed suppression records why the finding is not exploitable.

The future release process in [docs/releases.md](releases.md) requires a
reviewed main commit, a unique tag, a scoped change log, checksums and a
signed manifest, release identity and verification instructions, a
threat-model review, and an end-of-support date. No release may contain
credentials or machine-specific deployment state.

## Governance and vulnerability response

The maintainers listed in [GOVERNANCE.md](../GOVERNANCE.md) own repository
administration, Actions secrets, Pages, dependency policy, and future releases.
Sensitive access is granted after review of the contributor's history and
intended responsibility. New maintainers receive the narrowest role needed.

Report vulnerabilities through [SECURITY.md](../SECURITY.md) or GitHub private
vulnerability reporting. The maintainer acknowledges reports within three
business days and provides an initial assessment within seven days. Public
disclosure follows a fix or documented mitigation. [security/vex.json](../security/vex.json)
records reviewed non-affectability statements. Support rules are in
[SUPPORT.md](../SUPPORT.md).

The operating procedures for [dependency management](dependency-management.md)
and [secret management](secret-management.md) are part of this policy. They
define the review, release-gate, storage, access, and rotation requirements
used to support the controls below.

## Control evidence

| Control area | Evidence |
| --- | --- |
| Least-privilege CI and trusted inputs | Empty default permissions, job scopes, pinned actions, quoted inputs, and no fork secrets |
| Releases and change logs | [docs/releases.md](releases.md) |
| Dependencies | flake.lock, dependency review, and CodeQL |
| Build and test instructions | [CONTRIBUTING.md](../CONTRIBUTING.md) and [docs/testing.md](testing.md) |
| Governance | [GOVERNANCE.md](../GOVERNANCE.md) |
| Contributor legal agreement | [DCO](../DCO) and .github/workflows/dco.yml |
| Security assessment | [THREAT_MODEL.md](../THREAT_MODEL.md) |
| Vulnerability response | [SECURITY.md](../SECURITY.md), private reporting, advisories, and [security/vex.json](../security/vex.json) |
| Public interfaces and release identity | Service documentation, reviewed commits, and the future signed manifest |
| Support lifecycle | [SUPPORT.md](../SUPPORT.md) and [docs/releases.md](releases.md) |

Review this policy when a service changes its trust boundary, CI changes, or a
release process is introduced.
