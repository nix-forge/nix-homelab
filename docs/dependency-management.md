# Dependency management policy

This policy applies to Nix flake inputs, generated documentation references,
GitHub Actions, and test tooling in nix-homelab. Dependency changes are
reviewed as changes to the service and deployment trust boundary.

## Inventory and provenance

The authoritative dependency record is `flake.lock`, including the nested
lockfile used by the minimal template, together with package and action
references in `.github/workflows/`. Each update identifies its upstream source,
revision, and material transitive changes. Generated documentation is rebuilt
from the reviewed inputs rather than edited as an opaque artifact.

Dependabot keeps supported ecosystems visible. Dependency-review, CodeQL,
flake-lock health, and the NixOS/Python checks run in CI. These checks cover
known vulnerable dependencies, supported source languages, lockfile freshness,
and the service behavior exercised by the repository.

## Selection and review

Maintainers review upstream provenance, maintenance status, security
advisories, licensing, platform compatibility, and service behavior. Lockfiles
are updated with their flake declarations. Action updates use immutable commit
SHAs. Changes that affect service defaults, network access, credentials, or
lifecycle behavior include a focused test and migration guidance.

## Release gate and exceptions

Before a future release, applicable dependency-review, CodeQL, lock-health,
flake, documentation, and test checks must pass. A high- or critical-severity
finding, an unreviewed license problem, or a failed provenance check blocks the
release. The only exception is a reviewed, time-bounded pull-request record
that names the component, explains why it is not exploitable here, assigns an
owner, and gives a remediation date. `security/vex.json` records reviewed
non-affectability statements in OpenVEX form; it does not waive an affectable
finding.

## Update and rollback

Updates are evaluated on the supported systems and representative service
configurations. A regression is rolled back by reverting the lockfile and
declaration change, then tracked with a follow-up issue. Emergency security
updates use the smallest safe change and receive normal review retrospectively
if immediate action is required.
