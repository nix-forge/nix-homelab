# Public Nix homelab project comparison

Researched on September 11, 2026 Pacific time, September 12 UTC. The local
comparison uses commit `56a71fe4f217eb7ab232c43cdef6263b790c76e2`. Findings
about that baseline describe the repository before this improvement work. The
proposed acceptance criteria below are a roadmap, not a claim that they have all
passed.

The strongest opportunity is a media stack that proves safe networking, usable
permissions, and recovery from lost state. Keep native NixOS modules and
flake-parts. Use nix-forge/vpn-confinement for network policy, then test this
project's actual consumers. Borrow service integration and recovery patterns
from the projects below before adding another framework or a longer application
list. This is an engineering recommendation based on the comparison, not a
universal ranking.

## Selection and evidence

The sample includes reusable media stacks, server frameworks, established
personal configurations, and projects hosted outside GitHub. Popularity helped
find candidates; it did not determine their security or suitability. GitHub's
public repository API reported 423 stars for nixarr, 495 for SelfHostBlocks, 568
for Nixflix, 526 for badele/nix-homelab, 1,334 for Misterio77/Foundry, and 779
for Mic92/dotfiles at retrieval time. These counts will change. Sources are the
respective repository links in the table, whose API endpoints follow
`https://api.github.com/repos/<owner>/<repo>`.

Documentation establishes intended behavior. Source files establish what the
configuration and tests implement. This research did not run other projects'
test suites or audit every service. A checked-in test does not establish that
the current revision passes on this project's hardware.

| Project                                                                                                                                                             | Verified strengths relevant here                                                                                                                                                                                                                                                                                                                                                                                                                 | What to adopt, and the cost                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [nix-media-server/nixarr](https://github.com/nix-media-server/nixarr/tree/282ce99b31d52d72cca281e3d26d3dd267946800)                                                 | Media and state directory conventions, automatic service users, optional VPN routing, and declarative Prowlarr, download-client and Bazarr settings synchronization. Its [permission test](https://github.com/nix-media-server/nixarr/blob/282ce99b31d52d72cca281e3d26d3dd267946800/tests/permissions-test.nix) exercises file access under service identities.                                                                                  | Match the working media workflow and permission tests. Reconsider broad library write access for playback services. Its README cautions that routing all arr services through a VPN can cause rate limiting, so keep confinement selectable.                                                                                                         |
| [kiriwalawren/nixflix](https://github.com/kiriwalawren/nixflix/tree/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b)                                                       | API configuration connects Jellyfin, Seerr, arr services and downloaders. Optional PostgreSQL, nginx/Caddy integration, Navidrome and Maintainerr extend the media setup. Its [VM test inventory](https://github.com/kiriwalawren/nixflix/tree/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/tests/vm-tests) covers individual services, proxies, databases, VPN and a full stack.                                                                    | Declarative connections would remove much of this project's manual onboarding. Reconciliation must define whether it overwrites UI changes. The [testing guide](https://github.com/kiriwalawren/nixflix/blob/d77a3861a6a8c1468b38f9f2b81cee2d6ae26c7b/tests/README.md) acknowledges internet-dependent tests. Prefer local fixtures for required CI. |
| [ibizaman/selfhostblocks](https://github.com/ibizaman/selfhostblocks/tree/a252d9165a7d575c3a9408a8e8718303dcfbbd77)                                                 | Common backup, authentication, proxy, certificate, monitoring and storage interfaces apply across services. Its [Restic test](https://github.com/ibizaman/selfhostblocks/blob/a252d9165a7d575c3a9408a8e8718303dcfbbd77/test/blocks/restic.nix) creates data, backs it up, deletes it, and verifies restored content.                                                                                                                             | Adopt explicit state inventories and restore tests. Whole-project adoption adds its [required patched nixpkgs](https://github.com/ibizaman/selfhostblocks/blob/a252d9165a7d575c3a9408a8e8718303dcfbbd77/README.md), so evaluate dependency ownership before mixing it with local service wrappers.                                                   |
| [badele/nix-homelab](https://github.com/badele/nix-homelab)                                                                                                         | A documented multi-host deployment using Clan, generated service documentation, native services, and selected Podman applications. The README explains operational exceptions such as unattended boot for a core home service.                                                                                                                                                                                                                   | Document why each host differs and generate an inventory readers can inspect. A mature personal configuration contains local availability and hardware decisions; copying those decisions is not evidence they fit another home.                                                                                                                     |
| [Misterio77/Foundry](https://github.com/Misterio77/Foundry/tree/e09ecf80d761b92c31a28d00b649e3339a43dabb)                                                           | The former `Misterio77/nix-config` now redirects here. Its [README](https://github.com/Misterio77/Foundry/blob/e09ecf80d761b92c31a28d00b649e3339a43dabb/README.md) separates hosts, shared configuration and reusable modules; documents disko, encrypted Btrfs, opt-in persistence, Secure Boot and sops-nix; and links Hydra builds.                                                                                                           | Adopt clear host/module boundaries and an explicit persistence inventory. Impermanence and Secure Boot need recovery procedures and suitable hardware. They should remain host decisions.                                                                                                                                                            |
| [Mic92/dotfiles](https://github.com/Mic92/dotfiles/tree/d8f53aee3ea2f5a06c31fb75fd180fcaa9dec3b5)                                                                   | Its [ZFS backup module](https://github.com/Mic92/dotfiles/blob/d8f53aee3ea2f5a06c31fb75fd180fcaa9dec3b5/nixosModules/borgbackup-zfs-snapshots.nix) derives backup paths from Clan state declarations and stages read-only snapshots for Borg. The [README](https://github.com/Mic92/dotfiles/blob/d8f53aee3ea2f5a06c31fb75fd180fcaa9dec3b5/Readme.md) supplies Gitea and Radicle locations.                                                      | Define state once and use it for backup/recovery tooling. Snapshot integration introduces mount and cleanup logic that deserves its own failure tests. Do not copy a personal system wholesale.                                                                                                                                                      |
| [Clan 26.05](https://clan.lol/docs/26.05)                                                                                                                           | Fleet inventory, service roles, generated secrets and provisioning build on NixOS. Its [backup guide](https://clan.lol/docs/26.05/guides/backups/intro-to-backups) separates state declarations from backup providers and documents create/list/restore operations.                                                                                                                                                                              | A serious option if this grows into fleet management. It already [integrates with flake-parts](https://clan.lol/docs/26.05/guides/flake-parts). Adopting the whole inventory model is unnecessary merely to expose a reusable media module.                                                                                                          |
| [nixos-anywhere](https://nix-community.github.io/nixos-anywhere/quickstart.html) and [disko](https://github.com/nix-community/disko/blob/master/docs/quickstart.md) | Together they provide a repeatable installation path from SSH access and a declared disk layout. The quickstart explicitly covers target disks, SSH keys and locked flake inputs.                                                                                                                                                                                                                                                                | Add a disposable VM installation example and later a hardware-specific host profile. Disk selection and existing-data migration require the actual disk inventory; installation tooling does not supply that decision.                                                                                                                               |
| [jjhr/homelab.nixos on GitLab](https://gitlab.com/jjhr/homelab.nixos)                                                                                               | Shared host declarations connect internal DNS, certificates, service discovery and Tailscale/Headscale access. The [README](https://gitlab.com/jjhr/homelab.nixos/-/blob/main/README.md) distinguishes several planned features with a "coming soon" footnote.                                                                                                                                                                                   | Reuse the idea of one inventory driving related configuration. Do not count its planned monitoring or backup entries as implemented capability. The sampled project page showed older file updates, so recheck maintenance before importing it.                                                                                                      |
| [hmajid2301/nixicle on GitLab](https://gitlab.com/hmajid2301/nixicle)                                                                                               | Its [README](https://gitlab.com/hmajid2301/nixicle/-/blob/main/README.md) documents nixos-anywhere installation, encrypted Btrfs, persistence, Secure Boot, secrets and a generated nix-topology diagram.                                                                                                                                                                                                                                        | A generated topology is useful once real hosts and networks are known. Its example deployment includes `--skip-checks`; preserve validation in this project's normal deployment path.                                                                                                                                                                |
| [Grazen0/nixos-config on Codeberg](https://codeberg.org/Grazen0/nixos-config)                                                                                       | The [homelab service configuration](https://codeberg.org/Grazen0/nixos-config/src/commit/83a8620bd020854924ced6406e4b315b12bd50f6/hosts/shinmy/services/default.nix) includes Immich, Navidrome, Radicale and private service bindings. [Caddy configuration](https://codeberg.org/Grazen0/nixos-config/src/commit/83a8620bd020854924ced6406e4b315b12bd50f6/hosts/shinmy/services/caddy.nix) uses runtime secret templates for DNS certificates. | This is useful cross-platform coverage, not a security reference. The same source configures a root file browser rooted at `/`. Adopt specific patterns only after checking privilege and exposure. No live service was probed.                                                                                                                      |

## The nix-forge standard to meet

The [organization's public inventory](https://github.com/nix-forge) assigns
configuration discovery, packages, secrets, VPN confinement and shared CI to
separate repositories. Keep this project responsible for homelab policy and
integration instead of duplicating those implementations.

| Reference                                                                                                                                                                                                        | Observed practice                                                                                                                                                                                                                 | Application here                                                                                                                                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [nix-conf contribution guide](https://github.com/nix-forge/nix-conf/blob/7fd38c80a2aabdb16674fba7231496fa4a575bee/CONTRIBUTING.md)                                                                               | Each setting has an owner. Overrides require an explanation. Checks target observable behavior. Evaluation, build and activation results are reported separately.                                                                 | Add a domain glossary, contribution guide, supported-platform statement, and commands that distinguish evaluation from runtime verification. Document wrapper ownership and upstream escape hatches.                                     |
| [nix-config-framework](https://github.com/nix-forge/nix-config-framework/blob/11e4d9dfe816b9855ae9de8318734059d616d3a1/README.md)                                                                                | A flake-parts framework discovers modules while each target explicitly selects features.                                                                                                                                          | Keep ordinary NixOS exports consumable by the framework. Adopt its discovery only if the repository develops enough hosts to benefit; organization membership does not require a layout rewrite.                                         |
| [ci v2.5.0](https://github.com/nix-forge/ci/releases/tag/v2.5.0) and [onboarding template](https://github.com/nix-forge/.github/blob/08b8e390466909553bc498c2a5e0738001ea35b4/workflow-templates/nix-checks.yml) | Shared workflows use immutable pins, discover nested lockfiles, validate workflow policy and run declared checks. The release resolves to `78ee44eba73081183f51c85194c6dd9382feb60f`.                                             | Use one tested shared release. Cover both root and development-partition lockfiles. Keep fork builds read-only and checkout credentials unpersisted. Repository settings and hosted execution still need verification after publication. |
| [VPN confinement architecture](https://github.com/nix-forge/vpn-confinement/blob/0317379905359bc32204e05548e6a658b45d0ccd/site/src/content/docs/architecture.md)                                                 | Default-drop namespace policy, owned systemd attachment, strict DNS and explicit lifecycle behavior. One namespace is a shared network trust domain.                                                                              | Let the dependency own namespace attachment. Separate mutually untrusted groups. Document host publication as an explicit connection into that domain. Do not combine it with the old manual namespace wiring.                           |
| [VPN confinement tests](https://github.com/nix-forge/vpn-confinement/tree/0317379905359bc32204e05548e6a658b45d0ccd/tests/nixos)                                                                                  | Dedicated tests cover real WireGuard traffic, DNS/IP leakage, tunnel lifecycle, IPv6 and an authenticated Transmission example. Architecture documentation limits VM coverage to x86_64 Linux; ARM checks evaluate configuration. | Preserve the upstream evidence and add local application integration tests. An ARM evaluation result must not become an ARM runtime support claim.                                                                                       |

VPN confinement addresses network egress. It does not replace application
authentication, filesystem permissions, backups, or host security. Its
`publishToHost.tcp` option admits traffic on a host link; it does not create a
localhost listener, reverse proxy, NAT rule, or VPN-provider port forward. A
remote peer outage can leave WireGuard and applications active with stalled
traffic. Service liveness alone cannot prove that the tunnel works. These limits
are explicit in the
[upstream architecture](https://github.com/nix-forge/vpn-confinement/blob/0317379905359bc32204e05548e6a658b45d0ccd/site/src/content/docs/architecture.md).

## User-selected secrets and CI integration

The user selected nix-seal for supplied credentials and asked to remove agenix.
The standalone NixOS module requires no configuration framework. Consumers use
`config.nixSeal.secrets.<name>.path` for raw credentials and
`config.nixSeal.templates.<name>.path` for rendered files. Configure public
trust and `repositoryRoot` once; ciphertext sources are repository-relative
strings. Template placeholders are public markers, and substitution occurs at
activation. UTF-8 substitution does not escape INI, JSON or environment-file
syntax. A complete encrypted configuration avoids unsafe interpolation of
arbitrary credential bytes. Identity creation and provisioning remain operator
steps. These recommendations follow the
[authoring guide](https://github.com/nix-forge/nix-seal/blob/main/docs/nix-authoring.md)
and
[nix-conf integration guide](https://github.com/nix-forge/nix-conf/blob/main/docs/secrets.md).

The current local nix-conf testing guide, workflow and check definitions were
inspected read-only. They require tests to force relevant Nix assertions, verify
generated behavior, use disposable restore fixtures, and omit unavailable native
tests rather than report placeholder passes. The local checkout may include work
beyond published `main`. Its public
[testing guide](https://github.com/nix-forge/nix-conf/blob/main/docs/testing.md)
is the publication reference.

Use the shared
[`flake-checks` action](https://github.com/nix-forge/ci/blob/78ee44eba73081183f51c85194c6dd9382feb60f/actions/flake-checks/action.yml)
with its required `system` input. `checks-output` defaults to `checks`; a
separate output such as nix-conf's `ciChecks` is needed only for a real
execution boundary. The action defaults to two build cores, materializes
partitions and runs declared checks individually. Keep x86_64 VM tests and ARM
evaluation checks distinct. The
[`repository-checks` action](https://github.com/nix-forge/ci/blob/78ee44eba73081183f51c85194c6dd9382feb60f/actions/repository-checks/action.yml)
defaults to `hook-runner: prek`; provide that executable or explicitly select
`pre-commit`. Its history scan requires a full-history checkout. Supply the hook
runner and scanners in the selected development shell, then run the
[workflow validator](https://github.com/nix-forge/ci/blob/78ee44eba73081183f51c85194c6dd9382feb60f/actions/validate-workflows/action.yml)
against the actual final workflows before publication.

## Gaps against the starting commit

At the baseline, `modules/default.nix` imports storage, two downloaders,
Prowlarr and the bespoke VPN module. Several arr/media/request files exist
outside that import graph and enable services unconditionally when imported.
Storage creates a shared downloads directory but defines no library layout. The
single VPN test checks unit properties, routes and rules without a working peer
or authenticated application request. No tracked README, license, security
policy or GitHub workflow exists at that commit. These observations come from
the local Git tree, not an external ranking.

| Priority | Gap at baseline                                                                                                     | Proposed acceptance criterion                                                                                                                                                                                                | Relevant comparison                                                                                                                                                             |
| -------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0       | Catalog files and exported behavior differ; option names vary between `apps`, `services` and raw upstream services. | Importing the public module enables no applications. Every documented application can be enabled and evaluated through a consistent interface. Existing option migrations give a clear error or compatibility path.          | nixarr and nix-conf's ownership conventions.                                                                                                                                    |
| P0       | Bespoke VPN code and tests establish configuration shape more than traffic behavior.                                | A local WireGuard peer proves successful application traffic. Peer failure blocks unintended egress, including IPv6 and DNS. Restart restores intended access. Test the host-published Web UI with authentication.           | vpn-confinement's real handshake and application tests.                                                                                                                         |
| P0       | Shared downloads exist without a tested end-to-end library workflow.                                                | Downloaders write only their required paths. Managers import and hardlink a fixture on one filesystem. Playback identities can read it. Missing required mounts prevent writes into an unintended root filesystem directory. | nixarr's permission testing. Hardlink behavior remains a local test requirement.                                                                                                |
| P0       | Network privacy does not prove safe first-run authentication or secret handling.                                    | Runtime credential files remain outside the Nix store. Private application access works before any wider exposure. Tests verify rejected unauthenticated requests where supported.                                           | vpn-confinement's [Transmission example test](https://github.com/nix-forge/vpn-confinement/blob/0317379905359bc32204e05548e6a658b45d0ccd/tests/nixos/runtime-transmission.nix). |
| P1       | No service state inventory or tested recovery procedure.                                                            | Each supported service documents persistent state, credentials, backup consistency and restore ordering. A test restores deleted fixture data and verifies content. A deployment drill measures recovery time.               | SelfHostBlocks restore test and Clan's state/provider separation.                                                                                                               |
| P1       | No public CI gate or support matrix.                                                                                | Checks cover root and nested flakes, disabled/minimal/full configurations and supported native platforms. Required tests use local fixtures. Release notes state what ran, failed or remains untested.                       | nix-forge shared CI and Nixflix integration coverage.                                                                                                                           |
| P1       | No contributor or operator documentation.                                                                           | A new user can build a disposable example, supply secrets, reach private interfaces and follow rollback/recovery instructions. Add license, contribution and security reporting guidance before publication.                 | nix-forge's public repositories and nixos-anywhere onboarding.                                                                                                                  |
| P2       | Service connections require application UI state.                                                                   | An idempotent reconciliation design owns selected API objects, reads credentials at runtime, handles service readiness and documents UI drift behavior. A second run produces no duplicate clients or indexers.              | nixarr settings sync and Nixflix API configuration.                                                                                                                             |
| P2       | No measured performance baseline.                                                                                   | Record idle RAM, import time, storage throughput, transcoding capability, download/unpack contention, and power where measurable. Compare one change at a time on declared hardware and media fixtures.                      | No sampled project supplies a transferable benchmark proving it wins on this hardware.                                                                                          |
| P2       | No repeatable host installation or fleet inventory.                                                                 | A VM installation and recovery example passes before adding physical disk layouts. Real hosts declare hardware, disk IDs, exposure and backup destinations.                                                                  | disko, nixos-anywhere, Clan and nixicle topology.                                                                                                                               |

P0 covers safe usable behavior. P1 makes that behavior maintainable by another
person. P2 expands automation and proves capacity. A service catalog should say
which of these checks each integration has passed.

## Decisions supported by this comparison

1. Retain flake-parts and composable NixOS modules. Neither Clan nor the
   nix-forge framework requires abandoning flake-parts, and the present problem
   is missing integration rather than inadequate host discovery.
2. Replace the local VPN implementation with the requested pinned dependency.
   Keep application-specific integration tests in this repository. Reusing the
   network implementation does not test this project's bind addresses, storage
   paths, permissions or proxy choices.
3. Define library and application state separately. Keep downloads and final
   library files on a layout that permits hardlinks when that is the intended
   workflow. Verify the property with a fixture instead of relying on path
   names.
4. Make backups, restore documentation and private access part of accepting a
   supported service. A checkbox that starts the daemon is a lower standard than
   the strongest sampled projects already meet.
5. Add host tuning only after identifying hardware and workload. PostgreSQL, a
   full metrics stack, media cleanup, transcoding pipelines and container
   orchestration all add operational cost. Enable them for a demonstrated need.
6. Prefer current supported packages at a tested lock revision. An upstream
   project being newer or more popular does not establish compatibility with the
   chosen nixpkgs revision. Review dependency updates and preserve a recovery
   route for stateful upgrades.

## Coverage limits

This is a selected comparison, not a census of all public Git hosts. GitHub and
GitLab public source were accessible. Codeberg pages were blocked by the web
reader, but its public raw-file and repository-tree endpoints worked for the
Grazen0 sample. A direct EmergentMind README request timed out and is not used
as evidence here. Clan's Git host returned HTTP 403; its official versioned
documentation was accessible. Mic92's Gitea and Radicle locations were
discovered through its own README, but their contents were not independently
compared.

No external deployment was activated, benchmarked or security-tested. Repository
source can include unsafe examples, and documentation can describe unfinished
work. Where precise GitHub or Codeberg revisions were obtained, links pin them;
other documentation links identify the sampled upstream page and may change. The
comparison cannot establish that this repository is better than every public
alternative. Passing the stated acceptance criteria would give maintainers a
defensible claim about its actual behavior.
