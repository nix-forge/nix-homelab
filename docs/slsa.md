# SLSA build scope

This repository provides reusable NixOS service configuration and deployment
examples. It does not currently publish a compiled or repackaged release
artifact. Consumers use reviewed source and locked flake inputs directly.

Because there is no distributed build subject, this repository makes no SLSA
Build Level 3 claim for routine CI outputs, documentation, or the flake itself.
Artifact attestations belong on software or archives that consumers download,
not on transient test results.

If a source archive or package becomes a supported release artifact, its
release workflow must call the pinned
`nix-forge/ci/.github/workflows/slsa-source-release.yml` reusable builder. The
builder must create the exact bytes and provenance, while a protected publisher
verifies the signer workflow before release. The builder commit and consumer
verification command must be recorded in the release documentation.

See the [SLSA Build specification](https://slsa.dev/spec/v1.2/) and
[GitHub's artifact-attestation guidance](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
for the distinction between source inputs and distributed build artifacts.
