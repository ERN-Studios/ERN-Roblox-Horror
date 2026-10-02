# Public Level 3 cold-kit admission candidate

Draft-only handoff. No Studio Source/instance writes, UI/Play actions, index changes,
or publication were performed by this agent. The parent owns final installation,
native backup, engine verification, export, commit and publication.

## Exact authoritative baseline and final artifacts

Native before capture is at
`/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/before`.
The final read-only Edit MCP recheck confirmed place `131311258779917`, universe
`10559217407`, GameManager Source/editor parity and unchanged SHA256
`cd045eee01354ea97fb49b35a78a31a968aab47a8cdd34cb34a3d16318416a11`.
`ServerScriptService.Level 3 Kit Warmup` remains absent at that recheck.
Round Loading Runtime and Round Completion Routing still match their exact fresh
captured sources and editor sources; neither is an installation target.
See `admission/live-recheck-final.json`.

The installer manifest is `admission/candidate-manifest.json` (two changes).

| Target | Class | Operation | Candidate SHA256 |
| --- | --- | --- | --- |
| ServerScriptService.GameManager | Script | Scoped edit | 8e365508c1e42d9b50e28e8faa3d36ba72eb7b3ba667faf47e92d208262f0ef9 |
| ServerScriptService.Level 3 Kit Warmup | ModuleScript | New helper | 870130d1282ed11df29998e286221a6597cc8d9e40e62baad5f957d020dfc72c |

`GameManager.warmup.v3.diff` is the exact final diff against the authoritative
baseline. Earlier v1/v2 files/manifests/receipts are retained historical drafts,
not additional installation targets. The helper source has not changed between
those drafts. `prepare-warmup-candidate.py` generates v3 from the pinned baseline.

## Admission behavior and ownership

The helper begins one server-owned background call to the existing shared
`Level6BlenderRuntimeBake.Ensure()` at GameManager startup. It requires the ready
Folder and revised art SHA. It does not copy the kit, alter the original Level 6
DEV preview/bake, publish RoundActive/InRound, move characters or own a round token.
Its caller wait is bounded to 1200 seconds from startup. The engine operation
cannot be cancelled: a late completion may make future admissions ready, but
cannot restart or teleport a cohort whose waiter already returned. There is no
automatic retry/duplicate worker or extra per-round connection. Error text is
bounded to 500 characters.

Every actual public Level 3 round-entry caller waits before `Loading.Begin`:
Studio station, Studio Level 2 continuation, and reserved-server destination.
Published station launches also wait before teleporting. The helper never
extends an existing loading attempt. `Loading.Begin` creates a fresh 60-second
deadline only once the revised kit is ready. Common prewarm captures the previous
activeEntry identity and checks it before accepting readiness; a replaced waiter
cannot recover or fail a newer entry.

Public station warmup keeps the frozen party, host, epoch and characters. It
checks station cancellation/retirement, host/epoch changes, zone presence, every
member's current Player/character/health/InRound/zone status, access and Studio
world ownership each polling cycle, including immediately before success. Host
Cancel is permitted through the existing busy-queue handler only for the owned
warming queue. The station board displays PREPARING LEVEL 3 / STEP OUT TO CANCEL,
and queueconfigclosed removes the stale queue phone/countdown. Every cancellation
or warm failure clears kitWarming and station.busy. No round/teleport begins.

Studio's existing non-yielding roundBusy check/set remains immediately after
the shared wait; ready-kit Await has no scheduler yield. Two simultaneously
warmed stations therefore produce only one world. Acquiring roundBusy for the
entire 1200-second shared wait would block Level 1/2; this design lets those enter
and causes the waiting Level 3 station to cancel if another Studio round wins.

Studio campaign keeps the completed Level 2 floor throughout warmup and checks
live continuers/access before Begin. Cleanup occurs only in the new attempt
after readiness. When all continuers leave, existing recovery runs without
failing the previous ready attempt. The public tube entry-mode comparison,
placement and continuation pipeline remain unchanged.

Reserved entry first calls `Routing.SelectArrivalSession` on real arrival
entries, never a raw TeleportData.Level. It pins the first trusted Level 3
SessionId+Level through warmup. After readiness, the existing full cohort staging
still owns admission: destinationArrivalEvidence, NewArrivalTracker, final
MemoryStore cohort snapshot and all existing decision math are retained. Early
departures remain evidence and are subtracted exactly once; the first provisional
packet does not admit. A changed session/level is rejected. A temporarily empty
reserved server continues its bounded shared wait so later cohort members can
arrive; it does not confuse source departures with completed cohort cancellation.

The former reserved 60-second boot cutoff is captured before the newly introduced
target-discovery yield. Level 1/2 keep that absolute deadline via attempt.Deadline;
Remaining/IsOpen enforce it although Loading's original delayed watchdog still
fires 60 seconds after Begin. Only a trusted Level 3 target receives a fresh
postwarm entry deadline. No routing IDs, access ceilings, rewards, public campaign
limits, teleport packets or Level 5/6 DEV thresholds are changed.

## Verification and limits

Run `lune run tools/level3_promotion_20261002/admission/test-warmup-admission.luau`
with the available Lune binary. Final receipt is
`admission/warmup-admission-test-receipt-v2.json`: both exact candidate sources
compile, 27 scenarios / 86 semantic checks pass, with 12,142 bounded virtual
scheduler steps. The suite executes the actual helper, fresh Loading/ Routing
modules, and exact GameManager entry/queue/campaign/staging/cancel fragments.
It covers 130-second cold warmup followed by fresh60 entry; unchanged Level1/2;
all nine station invalidations; host Cancel; competing stations; stale ownership;
1200-second timeout and safe late completion; preserved Level2 tube floor/entry;
trusted reserved target, unchanged boot deadline, departed final carrier, session
pinning and provisional-first-packet/full-final-cohort behavior. Original 5/6 DEV
preview launch and Level1 developer launch fragments compare byte-identical.

These are mocked scheduler/player/service checks. Actual 279-chunk engine bake,
server CPU/memory, multiplayer gameplay, world/character streaming and publication
remain unverified. Runtime Bake itself is unchanged. Installing the sources into
Edit does not bake the kit or constitute publication.
