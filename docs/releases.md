# Release process

Releases use semantic versions and immutable Git tags. The maintainer performs
the tag and GitHub release steps after the candidate commit passes local and
hosted checks.

## Candidate checklist

1. Update `CHANGELOG.md` with behavior changes, option migrations, state
   migrations, and evidence limits.
2. Build `.#options`, `.#support-matrix`, and `.#documentation-site`.
3. Run `just lint` and `just check`.
4. Run `just test` for the Nix library suite. Record platforms and checks that
   remain unrun.
5. Review migration and recovery instructions for every changed state owner;
   record manual deployment evidence separately.
6. Inspect a clean checkout for generated docs, examples, and leaked credentials.
7. Tag the exact reviewed commit. Do not tag a dirty working tree.

Hosted CI, Pages deployment, real provider access, and real recovery are
separate evidence. A scheduled workflow that has never succeeded does not count
as validation.

Previous-release upgrades and restores require deployment-specific evidence.
The library suite and static CI do not establish state compatibility. Record
any attended upgrade and isolated restore against the exact source versions.

The flake exports `lib.version` and a default starter template. Initialize it
with `nix flake init -t github:nix-forge/nix-homelab`, inspect the generated
configuration, then commit its `flake.lock`. The lock is the deployment pin;
the template's branch URL is only the update source.

## Changelog format

Each release has `Added`, `Changed`, `Fixed`, `Migration`, and `Evidence`
sections as needed. `Migration` says whether evaluation, activation, persistent
state, or secrets change. `Evidence` lists the exact checks that ran and the
important tests that remain unavailable.
