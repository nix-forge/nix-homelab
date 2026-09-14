# Maintainerr 3.28.0 native Nix package research

Research question: can the rootless Podman deployment in
`modules/optional/maintainerr.nix` be replaced by a reproducible native Nix
package and a comparably safe NixOS service? Reviewed 2026-09-12. The affected
upstream release is Maintainerr 3.28.0; the selected nixpkgs input is
[`8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe`](https://github.com/NixOS/nixpkgs/tree/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe).

## Answer

**Inference:** a native package is feasible, but it is not a simple conversion
of the current OCI image or a ready-made upstream standalone distribution.
Upstream builds a Node monorepo and starts `node dist/main`; its released
artifacts and documented installation are OCI images only. A Nix derivation
would need to build the whole Yarn 4 workspace offline, retain its production
Node modules, install the UI, server, contracts, and font assets in a coherent
layout, and patch two container-specific absolute paths. It should initially
support only Linux `x86_64` and `aarch64`, use Node 26, and be accepted only
after a build and NixOS runtime test on each architecture.

The current container is not merely packaging: it supplies an application
layout at `/opt/app`, an unprivileged UID, a read-only root, an explicitly
writable data directory, and a health command. A native service can match most
of those protections with an unprivileged system user and systemd sandboxing,
but the user-namespace boundary disappears. Do not replace it until the native
unit proves persistent-state upgrades, the authenticated readiness endpoint,
and the existing access control behaviour.

## Facts from primary sources

### Release, licensing, and supported platforms

- The source identity for this investigation is the upstream tag
  [`v3.28.0`](https://github.com/Maintainerr/Maintainerr/tree/v3.28.0), commit
  [`276ec9dd9cb7608b8577190a14b03e9a8f831510`](https://github.com/Maintainerr/Maintainerr/commit/276ec9dd9cb7608b8577190a14b03e9a8f831510),
  whose commit timestamp is 2026-09-11T23:07:41Z. The root
  [`package.json`](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/package.json)
  also says `3.28.0`.
- The upstream
  [`LICENSE`](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/LICENSE)
  is MIT.
- Upstream documents released images for `amd64` and `arm64`, and its release
  workflow builds `linux/amd64` and `linux/arm64` separately
  ([README](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/README.md#installation),
  [workflow](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/.github/workflows/release_5_publish.yml)).
  This establishes upstream container coverage, not that a Nix build passes on
  either platform.
- On x86-64, `sharp` prebuilt image features require x86-64-v2; Maintainerr can
  start on older CPUs but disables overlays and collection posters. The upstream
  README says this limitation does not apply to arm64. This is a runtime feature
  constraint, not an Nix platform declaration.

### Exact upstream build inputs and sequence

- This is a private Yarn workspace, not pnpm or npm: root `package.json` pins
  `packageManager: yarn@4.17.1`, requires `node >=26.0.0`, and lists the UI,
  server, and contracts workspaces. `.yarnrc.yml` names the vendored
  `.yarn/releases/yarn-4.17.1.cjs`, selects `node-modules`, and enables package
  scripts ([manifest](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/package.json),
  [Yarn configuration](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/.yarnrc.yml)).
- `yarn.lock` is a Yarn lockfile (metadata version 10). CI installs Node 26,
  activates Corepack, installs the native canvas prerequisites, then runs
  `yarn --immutable`; that mode makes lockfile change a failure
  ([test workflow](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/.github/workflows/run_tests.yml)).
  The Dockerfile instead installs Corepack and runs `yarn install` without the
  immutable flag before copying the full tree; a native package should use the
  stricter CI invocation.
- The release Docker build is the exact available production recipe:

  1. Install `build-base`, Python 3, pkg-config, cairo, Pango, JPEG, giflib,
     pixman, and librsvg development inputs; enable Corepack.
  2. Copy the root manifest, lockfile, Yarn configuration/release, Turbo config,
     and workspace manifests; run `yarn install`.
  3. Copy the source; write `VITE_BASE_PATH=/__PATH_PREFIX__` to the UI `.env`;
     run `yarn turbo build`.
  4. Run `yarn workspaces focus --all --production`; retain root production
     `node_modules`, server `dist`, server manifest/node_modules, contracts
     `dist`/manifest/node_modules, UI `dist` under `apps/server/dist/ui`, and
     server assets.

  These steps and the copied files are specified in the
  [Dockerfile](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/Dockerfile).
  `turbo build` builds contracts first through its `^build` dependency; the
  server invokes `nest build`, while the UI invokes `vite build`
  ([Turbo graph](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/turbo.json),
  [server manifest](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/package.json),
  [UI manifest](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/ui/package.json)).
- `better-sqlite3`, `canvas`, and `sharp` are runtime dependencies. Upstream's
  Docker build comments name cairo/Pango/JPEG/giflib/pixman/librsvg as the
  node-canvas inputs and cairo/Pango/JPEG/giflib/pixman/librsvg plus `curl` as
  runtime packages. On Nix, derive the exact `nativeBuildInputs`/`buildInputs`
  by testing the source build; do not assume Alpine package names map 1:1 to
  nixpkgs.

### Runtime contract

- The production entry point is `node dist/main`. Upstream's
  [`start.sh`](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/docker/start.sh)
  stages the bundled UI from `/opt/app/apps/server/dist/ui` into
  `$DATA_DIR/ui`, replacing the `__PATH_PREFIX__` placeholder every boot, then
  starts it from `/opt/app/apps/server`. A native package with no `BASE_PATH`
  can build the UI with an empty base path and let the server use its bundled
  UI fallback; supporting dynamic `BASE_PATH` needs an equivalent writable UI
  staging step.
- In production, `DATA_DIR` defaults to `/opt/data`; the main process creates
  `logs`, `overlays/fonts`, and `overlays/images`, and needs read/write access
  to `maintainerr.sqlite` when it exists. TypeORM uses `better-sqlite3`, runs
  migrations on startup, and creates/uses `maintainerr.sqlite`
  ([data paths](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/app/config/dataDir.ts),
  [database config](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/app/config/typeOrmConfig.ts),
  [startup checks](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/main.ts)).
- **Packaging blocker (fact):** migration discovery is hard-coded to
  `/opt/app/apps/server/dist/database/migrations`, and logging is separately
  hard-coded to `/opt/data/logs`, ignoring `DATA_DIR`
  ([database config](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/app/config/typeOrmConfig.ts),
  [logging module](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/modules/logging/logs.module.ts)).
  **Inference:** a conventional immutable `/nix/store` installation therefore
  needs a small source patch to use the installed migration directory and
  `DATA_DIR` for logs, rather than attempting to populate `/opt/app`.
- Relevant environment variables documented or read by the source are
  `NODE_ENV=production`, `DATA_DIR`, `UI_HOSTNAME` (default `0.0.0.0`),
  `UI_PORT` (default `6246`), `BASE_PATH`, `DEBUG`, `LOG_LEVEL`, `GITHUB_TOKEN`,
  `TELEMETRY=off`, `TELEMETRY_URL`, `VERSION_TAG`, `GIT_SHA`, and
  `SPORTARR_NET=on`. `GITHUB_TOKEN` raises GitHub API rate limits; it is a
  runtime secret, not a derivation input. `TELEMETRY=off` overrides persisted
  telemetry configuration ([README environment example](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/README.md#docker-compose),
  [server startup](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/main.ts),
  [telemetry override](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/modules/telemetry/telemetry.service.ts)).
- The health endpoints are `GET /api/health/live` (process only),
  `GET /api/health/ready` (runs `SELECT 1`, 503 if unavailable), and
  `GET /api/health` (the readiness alias), all under `BASE_PATH` when set
  ([controller](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/app/health.controller.ts)).
  Upstream's health script calls the ready endpoint at localhost on `UI_PORT`
  ([script](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/docker/healthcheck.sh)).

### Nix-specific evidence and upstream support boundary

- The selected nixpkgs revision has no `maintainerr` package path under
  `pkgs/by-name`; this is a local source-tree observation on 2026-09-12, not a
  claim about later nixpkgs revisions.
- The nixpkgs manual has an explicit Yarn Berry v3/v4 workflow:
  `yarn-berry_4.fetchYarnBerryDeps` and `yarn-berry_4.yarnBerryConfigHook`.
  The fetcher verifies lockfile hashes and requires a generated `missingHashes`
  JSON for optional or platform-specific dependencies
  ([manual](https://nixos.org/manual/nixpkgs/stable/#javascript-yarn-v3-v4)).
  This is the appropriate Nix mechanism for Maintainerr's Yarn 4 lockfile, not
  `buildNpmPackage` or the Yarn 1-oriented helper. **Uncertainty:** the exact
  hash JSON and native-addon build inputs remain to be generated and proven in
  the selected nixpkgs revision; the package must not fall back to a networked
  build or a different package manager.
- Upstream offers no native binary, tarball, systemd unit, or standalone Nix
  installation in this tag's README, Dockerfile, or release workflow. It does
  provide a plain Node entry point, so “not supported as a distribution” does
  not mean “impossible to run natively.”

## Native service design implications

These are engineering inferences from the cited source and the
[current local adapter](../../modules/optional/maintainerr.nix), not claims of
upstream support.

| Concern | Current OCI adapter | Native NixOS service requirement |
| --- | --- | --- |
| Identity and writable state | Rootless Podman maps an unprivileged container user; only the mounted data tree is writable. | Use a dedicated non-login system user and a `StateDirectory`; make only that directory writable and set `DATA_DIR` to it after fixing the log-path bug. |
| Immutable program files | `--read-only`, dropped capabilities, `no-new-privileges`, and a bounded tmpfs are explicit. | `/nix/store` is immutable, but add `ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`, empty `CapabilityBoundingSet`, and narrowly scoped writable paths. Verify the resulting unit rather than assuming equivalent semantics. |
| Network exposure | Podman publishes only loopback; nftables permits the backend only to nginx, root, and the container account. | Bind `UI_HOSTNAME=127.0.0.1` (or a deliberately selected address) and retain the nginx authentication/firewall policy. Test that an unprivileged unrelated account cannot reach it. |
| Failure handling | OCI health check probes readiness, while systemd manages the container process. The current configuration does not itself show a health-status-to-restart action. | Use `Restart=on-failure`, ordering after local networking/state setup, and monitoring that queries `/api/health/ready`; do not restart solely on a transient SQLite readiness failure without an explicitly tested policy. |
| Isolation tradeoff | A compromised process also crosses the rootless container/user-namespace and slirp boundary. | Native operation removes Podman/conmon/slirp attack and update surface, but loses that namespace boundary. systemd sandboxing and a dedicated user are compensating controls, not proof of equivalence. |

## Recommended acceptance path

1. Add a **private package recipe in the package-owning repository**, not this
   homelab integration repository, pinned to commit `276ec9dd…`; use Node 26,
   `yarn-berry_4`'s offline-fetch/config hooks, an immutable install, a fixed
   dependency hash, and generated `missingHashes`. Build from source rather
   than extracting an OCI layer.
2. Patch the two absolute runtime paths, expose a wrapper that executes the
   installed server from a known layout, and install the UI, contracts,
   migrations, assets, and production `node_modules` together. Preserve
   `BASE_PATH` staging only if subpath hosting is required.
3. Add an NixOS module/service with a dedicated state directory, runtime secret
   injection for any `GITHUB_TOKEN`, loopback binding, the existing authenticated
   nginx proxy, and explicit systemd hardening. Keep telemetry disabled only
   when that remains the declared local policy.
4. Test `x86_64-linux` and `aarch64-linux` builds; then run a VM test that
   preserves the SQLite database across restart/upgrade, authenticates through
   nginx, rejects unauthenticated and unrelated-user backend access, and checks
   `/api/health/ready`. Test an x86-64-v2-negative fixture separately if
   overlay/poster capability matters.

## Validation and limits

No package or service was built in this investigation. I inspected the pinned
upstream source tag, its release/build workflows, and the selected nixpkgs
source on 2026-09-12. Consequently, all build viability, exact Nix dependency
names, Node 26 availability in the selected package set, cross-platform build
results, migration compatibility with existing state, and systemd sandbox
equivalence remain unverified. The cited upstream files are primary sources;
the recommendation and security comparison are explicitly marked inference.
