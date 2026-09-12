# Repository instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing code. For Matt Pocock
workflows, use [the workflow guide](docs/agents/workflows.md). For requirements
and reviews, read [the tracker guide](docs/agents/issue-tracker.md). For domain
terms, read [CONTEXT.md](CONTEXT.md).

Reusable services belong here. Host hardware, mounts, nix-seal catalogs and
backup destinations belong in the consuming system repository. VPN policy
implementation belongs in `nix-forge/vpn-confinement`; this repository owns its
consumer integration and tests.

For substantial work or parallel writers, use `agent-workflow`. Keep private
briefs and raw output outside tracked files. Pass an exact base and captured
patch to independent reviewers. Preserve staged and unstaged user work.

Before writing public documentation, follow
[the publication rules](docs/agents/publication.md). State evaluation, build and
runtime results separately. On a desktop configured with `workstation-task`, run
heavy checks through that runner.
