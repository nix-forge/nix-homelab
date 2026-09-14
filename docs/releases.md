# Release process

Releases use semantic versions and immutable Git tags. The maintainer performs
the tag and GitHub release steps after the candidate commit passes local and
hosted checks.

## Candidate checklist

1. Update `CHANGELOG.md` with behavior changes, option migrations, state
   migrations, and evidence limits.
2. Build `.#options`, `.#support-matrix`, and `.#documentation-site`.
3. Run `just lint` and `just check`.
4. Build every affected x86_64 VM test through `workstation-task`. Record ARM as
   evaluation-only unless native ARM VM jobs passed.
5. Run the previous-release upgrade and restore fixture for every changed state
   owner.
6. Inspect a clean checkout for generated docs, examples, and leaked credentials.
7. Tag the exact reviewed commit. Do not tag a dirty working tree.

Hosted CI, Pages deployment, real provider access, and real recovery are
separate evidence. A scheduled workflow that has never succeeded does not count
as validation.

There is no previous immutable release before `v0.1.0`. The first release must
record its state owners and restore fixtures as the upgrade baseline. Starting
with `v0.2.0`, release candidates must boot the previous tag's state fixture,
activate the candidate, and complete an isolated restore. Until that evidence
exists, the compatibility matrix says that previous-release upgrades are not
yet demonstrated.

The flake exports `lib.version` and a default starter template. Initialize it
with `nix flake init -t github:nix-forge/nix-homelab`, inspect the generated
configuration, then commit its `flake.lock`. The lock is the deployment pin;
the template's branch URL is only the update source.

## Changelog format

Each release has `Added`, `Changed`, `Fixed`, `Migration`, and `Evidence`
sections as needed. `Migration` says whether evaluation, activation, persistent
state, or secrets change. `Evidence` lists the exact checks that ran and the
important tests that remain unavailable.
