# Threat model

## Scope

This model covers the reusable NixOS service modules, deployment examples,
generated configuration, documentation, and repository automation. It does not
cover a consumer's host, credentials, hardware, or external service provider.

## Assets and actors

Assets include service credentials, generated configuration, network policy,
dependency pins, deployment instructions, and CI access. Contributors and
pull requests are untrusted. Maintainers approve changes and control
repository, Pages, Actions, and future release settings. CI may evaluate
pull-request code but must not receive repository secrets.

## Trust boundaries

The Nix evaluator, generated system configuration, deployed service, and GitHub
Actions runner are separate boundaries. Secrets must enter through the
consumer's secret mechanism, never through public Nix source or CI logs.

## Main threats and controls

| Threat | Control |
| --- | --- |
| A service default exposes a port or credential | Secure defaults, review, integration tests, and documented options |
| A pull request changes deployment behavior unnoticed | Required tests, dependency review, CodeQL, DCO, and protected main |
| CI exposes a repository token to untrusted code | Empty default permissions, job scopes, pinned actions, and no fork secrets |
| A dependency introduces a known flaw | Lockfile review, dependency review, CodeQL, and release gating |
| Documentation causes an unsafe deployment | Reviewed operations guides, testing evidence, and this model |

Review this model before changing network exposure, credentials, service
lifecycle, privilege boundaries, or CI and release automation.
