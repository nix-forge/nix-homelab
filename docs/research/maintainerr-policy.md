# Maintainerr policy research

Reviewed: 2026-09-24. Scope: NixFLIX commit
[`122f2330e9b5fd3a0d963957fe4ac5f40df85773`](https://github.com/kiriwalawren/nixflix/tree/122f2330e9b5fd3a0d963957fe4ac5f40df85773)
and Maintainerr v3.28.0, whose tag resolves to
[`276ec9dd9cb7608b8577190a14b03e9a8f831510`](https://github.com/Maintainerr/Maintainerr/tree/276ec9dd9cb7608b8577190a14b03e9a8f831510).

## Answer

NixFLIX's commit tree implements full ownership of Maintainerr configuration
through API-driven systemd oneshots. It creates or updates declared rules and
overlay templates, then deletes undeclared rules and non-preset templates. It
also runs a separate timer which places a `.ignore` marker in each configured
Sonarr directory that has no recognized video file, and removes the marker
when a video appears. The current local module only runs and protects the
Maintainerr service. It has no media-library write access, rule reconciler,
overlay reconciler, or ignore-marker job.

The first local phase should be narrow: take a Maintainerr state backup,
configure a small set of rules with `arrAction = "DO_NOTHING"`, set an explicit
positive `deleteAfterDays`, preview individual rule matches, and inspect the
resulting collection membership and logs. Do not adopt NixFLIX's
delete-undeclared reconciliation in that phase. Do not use an absent or null
timer as the safety control. A live restore drill is not needed to design this
policy or test one item's rule predicate. Keep file-deleting actions disabled
until recovery has been proved.

Maintainerr's v3.28.0 documentation says that a null timer is due immediately,
but the tagged collection worker skips a collection with no timer. The tag
also contains a helper that treats null as zero. This is a real source/docs
contradiction. Explicitly setting a positive window and `DO_NOTHING` avoids it
in the first phase. A later deletion policy must keep the explicit window and
requires a tested recovery plan.

## Findings and sources

### NixFLIX implementation at the named commit

The named NixFLIX commit itself only adds an Arr nginx WebSocket line. The
Maintainerr implementation is the surrounding tree at that revision. Its
package has already moved to v3.29.0, so it is evidence for NixFLIX's design,
not evidence that the same API behavior holds for Maintainerr v3.28.0.

- [`modules/maintainerr/default.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/modules/maintainerr/default.nix)
  runs the native package under a dedicated account, passes `DATA_DIR`, and
  grants `ReadWritePaths` for both application state and the media directory.
  The local [`nix-homelab/modules/optional/maintainerr/default.nix`](../../modules/optional/maintainerr/default.nix)
  instead exposes a hardened loopback service whose writable state is only
  `/var/lib/homelab-maintainerr/data`. That is why it cannot implement an
  on-disk `.ignore` job today.

- [`rules/default.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/modules/maintainerr/rules/default.nix)
  waits for settings, resolves library and Arr server names to runtime IDs,
  then `POST`s or `PUT`s each declared rule at `/api/rules`. It finally deletes
  every rule whose name is absent from the declaration. The matching option
  warns that a change of type, library, or manual-collection fields clears
  current collection media
  ([`rules/options.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/modules/maintainerr/rules/options.nix)).
  This is a full desired-state controller, not a bootstrap tool.

- [`overlays/settings/default.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/modules/maintainerr/overlays/settings/default.nix)
  overwrites overlay settings. [`overlays/templates/default.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/modules/maintainerr/overlays/templates/default.nix)
  creates or updates templates by name, chooses defaults, and deletes every
  undeclared non-preset template. Presets remain untouched. Overlays can
  change media-server poster and title-card artwork, so they should be their
  own later opt-in phase.

- [`forceJellyfinIgnore.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/modules/maintainerr/forceJellyfinIgnore.nix)
  is independent of Maintainerr rules. When enabled, it scans each immediate
  show directory under selected Sonarr and Sonarr Anime media roots every 30
  minutes after a five-minute boot delay. It writes `.ignore` when no file has
  one of its listed video extensions and removes it once such a file exists.
  Its VM test checks both transitions
  ([`maintainerr-basic.nix`](https://github.com/kiriwalawren/nixflix/blob/122f2330e9b5fd3a0d963957fe4ac5f40df85773/tests/vm-tests/maintainerr-basic.nix)).
  This changes filesystem metadata and library visibility. It does not delete
  a media file, but it must have explicit media-root ownership and a rule for
  what counts as a video before local adoption.
  The NixFLIX script removes any existing `.ignore` file when it finds a video,
  without checking who created the file. Jellyfin also uses nonempty `.ignore`
  files for selective exclusion, so this could erase a manually maintained
  exclusion list. Any local job would need its own marker and must leave other
  `.ignore` files alone
  ([Jellyfin exclusion documentation](https://jellyfin.org/docs/general/server/media/excluding-directory/)).

### Maintainerr v3.28.0 lifecycle and actions

Maintainerr's own versioned Collections API distinguishes removing membership,
handling an item, deactivating a collection, and removing a collection.
Handling is the operation that can delete media files. Deactivation and
collection removal erase membership and collections but do not delete the
media files. Collection deletion also removes its rules, logs, media-server
collection, applied overlays, and stored custom poster, which is not
recoverable ([v3.28.0 Collections API](https://docs.maintainerr.info/3.28.0/api/collections/)).

`arrAction` controls what handling does. The versioned API lists delete,
unmonitor-and-delete variants, unmonitor, `DO_NOTHING`, empty-show actions,
and a quality-profile change. The tagged handler falls back to
`mediaServer.deleteFromDisk` for a disk-freeing action with no associated Arr
server, so merely leaving an Arr ID unset does not make delete policy safe
([handler source](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/modules/collections/collection-handler.ts)).

The rule test route is `POST /api/rules/test`; it calls
`testRuleGroupWithData` for one media ID
([controller source](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/modules/rules/rules.controller.ts),
[v3.28.0 Rules API](https://docs.maintainerr.info/3.28.0/api/rules/)). This
tests the rule predicate for a selected item. It is useful evidence before a
rule run, but it is not a system-wide dry run of collection membership or an
action simulation. I found no tagged v3.28.0 global dry-run switch for the
collection handler. A manual `POST /api/collections/media/handle` is expressly
destructive for delete actions in the versioned API and must not be used as a
preview.

The `deleteAfterDays` evidence conflicts within the same release:

- The versioned v3.28.0 Collections API says null and an omitted
  `deleteAfterDays` are treated as zero and are immediately due. It warns that
  this can arm deletion on the next collection-handler run.
- The tagged helper agrees: `getCollectionDangerDate` maps a null window to
  zero ([source](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/modules/collections/collections.service.ts)).
- Yet the tagged worker defines a null window as "never" and filters such a
  collection before querying due media ([source](https://github.com/Maintainerr/Maintainerr/blob/276ec9dd9cb7608b8577190a14b03e9a8f831510/apps/server/src/modules/collections/collection-worker.service.ts)).

The v3.29.0 unversioned collections page carries the immediate-due wording,
but it is not authority for a v3.28.0 install. The v3.28.0 versioned page is
the relevant documentation, and the tag's contradictory code makes null an
unsafe configuration value even if the current worker happens to skip it.

Overlays are a separate configuration plane. The v3.28.0 overlay documentation
describes templates and scheduled rendering to posters/title cards
([v3.28.0 overlays](https://docs.maintainerr.info/3.28.0/overlays/)). NixFLIX
reconciles settings before templates and assigns at most one default per mode.
Treat an overlay as a visible media-server mutation, not as a preview feature.

### Local operations and recovery

[`nix-homelab/docs/operations.md`](../../docs/operations.md)
lists Maintainerr state among the state to preserve and says a restore needs
the original dedicated service UID, database-integrity verification,
application-user and settings checks, and permitted sample playback. The
operations module inventories `/var/lib/homelab-maintainerr/data` for this
purpose ([`modules/operations/default.nix`](../../modules/operations/default.nix)).

A restore drill means restoring a captured Maintainerr state snapshot into an
isolated or otherwise controlled service instance, using the original service
UID, then checking SQLite integrity, application settings and users, and an
authorized sample playback. It proves the backup can be used. It does not mean
asking Maintainerr to put deleted media back. Deleted media needs a separate
media backup and a recovery procedure for the Arr, Jellyfin, and filesystem
state it affected.

Neither local operations guidance nor the first-party Maintainerr sources make
a restore drill a prerequisite for nondeleting rule management. It becomes a
release gate before a delete action because that action can permanently remove
media. Even in the nondeleting phase, capture a state backup before changing
rules because the controller changes SQLite-managed configuration and
collections.

## Implementation status

The reusable repository now has an explicitly started, managed-subset policy
controller in `scripts/media/maintainerr_policy.py` and
`modules/optional/maintainerr/policy.nix`. Planning sends GET requests only;
Maintainerr itself may seed overlay defaults on the first settings GET. It records
ownership of created rule groups and templates, rejects unowned name collisions
and rule identity changes, and never deletes undeclared objects. It only
accepts the `DO_NOTHING` action, an explicit positive collection window, and
disabled collection overlays. Template definitions and the global disabled
overlay setting can be managed without selecting a default or rendering
artwork. The backend service has no automatic policy trigger.

The separate `jellyfinIgnore` timer tracks the inode and change time of each
empty marker it creates and leaves manual `.ignore` files alone. The recovery
helper checks an isolated restored Maintainerr data directory for the expected
UID and SQLite integrity. These are reusable tools; the consuming host still
supplies actual library IDs, media roots, backup destination, credentials, and
a decision to activate each option. No live collection, media file, or artwork
was changed.

## Staged adoption plan

1. Record the owner, library titles, intended data types, and one collection
   policy for each rule. Read-only rule tests can happen first. Before writing
   settings or collections, take a Maintainerr state snapshot and confirm the
   existing operations inventory covers it. Do not grant the service media
   write access merely to configure rules.

2. Add a bootstrap or managed-subset reconciler, not NixFLIX's global
   delete-undeclared loop. It should fetch and report existing rules/templates,
   create or update only names explicitly marked managed, and fail on an
   ownership collision. Preserve all other upstream state. Add a focused
   runtime test for the request sequence and state persistence.

3. Start with one or two active rules whose `arrAction` is `DO_NOTHING` and
   whose `deleteAfterDays` is explicit and positive. Use the rule test API on
   representative media, run the rule scheduler, and inspect membership,
   exclusions, and logs. Do not invoke the manual handle endpoint. This phase
   can populate collections but cannot run a configured deletion action.

4. Make overlays a separate opt-in declaration. First observe template and
   collection behavior without overlays, then decide whether Maintainerr owns
   the selected posters/title cards. Do not delete unlisted templates in the
   initial reconciler.

5. Treat `.ignore` as a separate host storage feature. Define the exact roots,
   extension list, scan depth and marker ownership; require the mounted media
   path and write permission; test both marker creation and removal. Its
   behavior should remain independent of rule reconciliation.

6. Before enabling an action that frees disk, run the restore drill and test a
   contained deletion-recovery path with an expendable fixture. Only then set
   an explicit finite window and a delete-style `arrAction`. Keep the rule
   declaration, action choice, and activation in separately reviewed changes.

### Collection policy choices that need an owner decision

- Which libraries and media types may enter each collection, and whether a
  manual Jellyfin collection is reused or Maintainerr creates one.
- Whether collections appear on home/recommended views and whether they remain
  inside Maintainerr only.
- The explicit grace period, the retention period for collection logs, and
  whether membership may be manually added, removed, excluded, or postponed.
- The action after the grace period. `DO_NOTHING`, unmonitor, and each delete
  variant have materially different recovery consequences.
- Which Arr or Seerr instance owns an action, whether list exclusions and
  forced Seerr behavior are allowed, and who can alter the collection.
- Whether overlays and `.ignore` markers are allowed to alter library
  presentation, and which component owns rollback of those changes.

## Validation and limits

At the original research stage, no build, activation, API mutation, backup,
restore, or live media scan ran. I inspected the current local module and operations documentation, the
specified NixFLIX commit tree, the first-party Maintainerr v3.28.0 docs, and
the v3.28.0 tag source. The v3.28.0 `deleteAfterDays` contradiction remains
unresolved upstream. The staged plan avoids relying on its result until a
version-specific runtime test proves the behavior of the packaged service.
