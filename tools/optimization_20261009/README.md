# Optimization implementation preparation — 2026-10-09

Status: **prepared changes, not deployed**. The owner explicitly instructed us to
preserve the running Level 4 playtest until further notice. No optimization Studio
write, Play stop/start or publication has occurred. A user-reported native backup
exists; its path/hash have not yet been recorded. We will take/verify a fresh native
place backup after Edit is released, before applying non-script changes.

Studio is authoritative: place `131311258779917`, universe `10559217407`. Current
concurrent cleanup already parks Levels 4–6 in ServerStorage via LevelWorldStorage;
the proposals preserve that work. Repository state and fresh origin history were
inspected before this task. The initial dirty checkout was checkpointed without
reset/stash removal at `refs/checkpoints/optimization-20261009-before`, commit
`cc8bf9546d16ccd0b209eb06269c25243cf533d1`. The original dirty/untracked files also
remain in `_local/optimization-20261009/before-working-files.zip` with a hash listing.
Later concurrent cleanup changes are separate work and must not enter our commit.

## Scope and prepared changes

| Requested area | Prepared change | Remaining before deployment |
|---|---|---|
| ReplicatedStorage | Reparent the two unused UI Imports folders to a named ServerStorage archive. Originals and runtime Templates remain intact. | Fresh full reference/source/editor scan, native backup, exact identity guards and UI regression check. The earlier census counted 12,057 descendants; this is not a fresh applied result. |
| Loading priority | Arrival-world assets within 128 studs and visible UI form the critical gate; one background worker warms the remaining streamed lobby for at most 20 seconds. | Fresh Source/editor CAS, native contracts, cold join and level transition tests. |
| Streaming/stream-out | Review native Workspace settings and a tentative 384-stud target with Opportunistic stream-out. Preserve the current minimum pending inspection. Add bounded spectate focus handling before reducing distance. | Native property baseline, spectator/teleport/slide testing with separated participants. Improved model behavior needs a separate compatibility decision after the fresh baseline. |
| Poolrooms collision | Archive only anonymous transparent rectangular colliders entirely covered by an untouched collider with identical physical/query/Area properties. No resizing, epsilon or removed occupied volume. | Fresh exact plan and count, reference/CAS validation, actual map movement, hazards, exits and navigation tests. |
| Level 6 geometry | Change scoped deck/deck-pad unions from Precise to Automatic render fidelity; preserve collision and native union data. | Fresh plan, native visual/geometry checks and actual frame measurements. Earlier Edit observations found 6,605 eligible unions. |
| Room lights/effects | Explicitly marked decorative effects receive a client sector budget; the server carries the authoritative desired Enabled state, including L4 blackouts. | Fresh authored selections, additive Light Director patch, native contracts and gameplay lighting checks. Emergency/objective lights and gameplay beams are excluded. |
| LOD and asset reuse | Union Automatic LOD above; preserve existing shared MeshIds and TextureIDs. | Native visual verification. Existing L6 meshes already share seven MeshIds and three texture IDs and already use Automatic. Changing asset IDs without a demonstrated duplicate would add risk without a verified saving. |

Subfolder runbooks describe exact inputs, tests and apply/rollback contracts.
All source proposals are task-owned files, not exported runtime changes.

## Verification and deployment sequence

1. Wait for the owner to release Play. Re-read Studio mode/identity, git status and
   fresh remote history; preserve any further unrelated changes.
2. Save a full native place backup and record its absolute path, byte length and
   SHA256. A source mirror does not protect native geometry, UI and service settings.
3. Re-read relevant live instances and exact Source/editor pairs. Reconcile any
   changed proposal baseline against Studio before writing; never import an older
   repository source over new Studio work.
4. Stage contract probes only in fresh Instance.new("ModuleScript") objects with
   exact empty Source/editor pins. Verify originals during staging and after success
   and failure. Always clean up test-owned objects, connections and borrowed state.
5. Apply reviewed source/property plans in bounded chunks with fresh guards inside
   each write. Record exact paths, classes, hashes, archived original identities,
   asset IDs and changed properties. Keep native data in before/after place backups.
6. Test actual UI, join handover, room lighting and level routes. Poolrooms requires
   safe spawn distances from all living participants, second distinct pump spawn,
   third distinct pump escalation, active-round CPU/memory and navigation/retry
   observation plus round-reset task/connection cleanup. Spectate needs separated
   participants and target death/respawn/selection changes.
7. Measure the same route/settings/device before and after: join-to-control, client
   instances/memory, frame-time distribution and server CPU/memory. Synthetic
   contracts and containment proof do not establish multiplayer, streaming, actual
   asset visual quality or performance improvement. Mobile remains unverified until
   tested on appropriate hardware.
8. Export only freshly verified Studio changes. Inspect the exact scoped staged
   diff, commit task work without including the concurrent cleanup, then publish the
   current Studio place to the existing experience. Record successful Roblox publish
   output and the resulting version; do not publish with a material blocker.

`install_sources.py` is a narrowly scoped source-CAS helper, **not run**. It requires
an explicitly reviewed task-owned manifest, SHA256 pins, a native backup path and
`--apply`. It refuses Play and the wrong place. New sources are fresh objects with
empty editor pins; existing sources compare both live forms before/inside/after
writes. Unrelated source/editor originals are rechecked after success/failure. It
records partial receipts, performs no bulk synchronization, exports no mirrors and
does not publish. After applying, verify actual Studio state before exporting it.
`proposed-source-manifest.json` records the five scoped proposals. Rebuild its pins
only after reconciling changed live baselines and reviewing the resulting patches.

## Research references

The engine streams Workspace rather than ReplicatedStorage. Its target radius is a
desired streaming region rather than a strict memory cap; persistent/atomic models
and additional foci affect the retained world. See Roblox's
[instance streaming guide](https://create.roblox.com/docs/workspace/streaming).
Preloading should focus on required assets and preserve actual fetch status rather
than treating the global request queue as asset-count progress. See
[ContentProvider](https://create.roblox.com/docs/reference/engine/classes/ContentProvider).
The complete project research remains in
[`docs/PERFORMANCE_RESEARCH_2026-10-09.md`](../../../docs/PERFORMANCE_RESEARCH_2026-10-09.md).
