# Level 2 — Sunken Leisure Complex — working handoff

Scope: **Level 2 only.** Everything below was checked against the code and the
live place on 2026-08-19, after the project-wide audit landed in Studio.

Where it stands: the world, the objective, lighting and the sound scaffolding
are built and probe-validated. Of the two hostiles, **Pool Foam runs every
round; the Slidemouth has never started.** Nothing in the level is hand-placed
— it is all generated from a seed, so every change is a value in a file.

---

## 1. Two things that will confuse you before anything else

**A pinned seed is currently active.** `workspace.Level2Seed = 240814`, so every
Level 2 round builds the *identical* map. It is a manual testing override:
Explorer → **Workspace** → Properties → **Attributes** → `Level2Seed`. Delete
the attribute to get a fresh random layout per round. Confirmed live: the state
folder reports `Level2_ResolvedSeed = 240814`, i.e. it generated on the first
attempt with no fallback.

Never write the random pick back into that attribute — a previous version did,
and it froze the map on round one's seed for every round after it. The comment
at [Level 2 Round Adapter.ModuleScript.lua:205](ServerScriptService/Level%202%20Systems/Level%202%20Round%20Adapter.ModuleScript.lua:205)
says so; leave it there.

**Studio is the source of truth, not the repo.** Make changes *in Studio*, then
mirror them into the repo. Read `CLAUDE.md` before editing — the manifest and
push/pull rules are there, and the sync tools only work from a session running
on the Windows PC.

---

## 2. How a round actually runs

`Level 2 Round Adapter.Build()` drives everything:

1. Reads `Level2Seed` (or picks a random one from the clock).
2. `LayoutGenerator.Generate(seed)` carves a BSP floor plan of a 1400-stud
   region — ~45 halls joined by flooded arch-tunnel corridors. If a seed fails
   all 40 attempts it falls back to the checked-in known-good seed `101`.
3. `World Builder` turns the plan into parts, water, slides and props.
4. `ObjectiveController.Start(manifest, generation)`.
5. `PoolFoamController.Start(manifest, generation)`.

`Cleanup()` stops both and tears the world down. The round's live state is
readable as attributes on `ReplicatedStorage["Level 2 State"]` — `Level2_Phase`,
`Level2_Seed`, `Level2_ResolvedSeed`, `Level2_UsedFallback` and friends. That
folder is the first place to look when a round misbehaves.

**The objective:** start **3 pump stations** → each drains the flooded corridor
beside it (terrain water genuinely removed, so the route physically changes) →
with all three running the **pressure doors** into the Grand Slide Hall unseal →
climb the spiral stair to the top deck and ride the **exit flume** out.

---

## 3. The files

All server modules sit in `ServerScriptService/Level 2 Systems/`.
`ServerScriptService.Level2Generator` is just the doorway GameManager calls and
never needs editing.

| Lines | File | What it owns |
|---|---|---|
| 176 | Level 2 Configuration | **~95% of tweaks live here** |
| 923 | Level 2 Layout Generator | BSP floor plan, seeding, validation |
| 5462 | Level 2 World Builder | plan → parts, water, slides, props |
| 362 | Level 2 Objective Controller | pumps → drains → doors → escape |
| 300 | Level 2 Round Adapter | Build/Cleanup, lobby parking, terrain |
| 66 | README - LEVEL 2 TWEAKS | the tweak guide — read it first |
| 210 | Level 2 Pool Foam Configuration | entity balance, animation/audio slots |
| 1119 | Level 2 Pool Foam Controller | two-entity scare director |
| 658 / 410 / 554 / 300 | Pool Foam Navigator / Observer / Animation Adapter / Proxy Factory | movement, server-validated observation, replaceable art |
| 154 | README - LEVEL 2 POOL FOAM | full art + API instructions |
| 1147 | Level 2 Slidemouth Controller | **complete, and never started — see §4** |
| 414 | Level 2 Slide Ragdoll Service | server side of the physics slide ride |

Client, in `StarterPlayer/StarterPlayerScripts/`:

| Lines | File |
|---|---|
| 674 | Level 2 Sound Controller |
| 591 | Level 2 Slide Controller |
| 447 | Level 2 Pool Foam Client |
| 263 | Level 2 Slidemouth Client |
| 240 | Level2AlertClient |
| 139 | Level 2 Objective UI |
| 136 | Level 2 Lighting Controller |

---

## 4. Open item — the Slidemouth never starts

The controller is finished. It exposes `Controller.Start(manifest, generation)`,
`Controller.Stop()`, `Controller.IsRunning()` and `Controller.GetDebugSnapshot()`
at lines 1036, 1023, 1113 and 1121. **Nothing in the codebase requires the
module.** The only other reference anywhere is the client script reading its
walk keyframes and sound slots — so the client half is waiting on a server half
that never runs.

To wire it, mirror how Pool Foam is already handled in the Round Adapter:
`PoolFoamController.Start(manifest, generation)` at line 275 and
`PoolFoamController.Stop()` at line 153. The Slidemouth takes the same two
arguments, so it slots in next to those two calls.

Worth deciding before you do: two active hostiles in one round is a real
difficulty change, so give it its own playtest rather than folding it into
another pass. There is no `Enabled` switch on the Slidemouth the way Pool Foam
has `PoolFoamConfiguration.Enabled` — consider adding one first, so a bad
playtest is a one-value rollback.

---

## 5. Open item — the sound library

`ReplicatedStorage["Level 2 Sound Library"]` holds one StringValue per slot;
paste an asset id in and it works. Live count: **14 filled, 12 empty.**

**Only five of the twelve empty slots are wired to anything.** These are the
ones that will change how a round plays:

| Slot | Refs | What it is |
|---|---|---|
| `Level 2 Drain Rush` | 5 | authored cue — a corridor drains |
| `Level 2 Slide Rush` | 6 | authored cue — riding the exit flume |
| `Level 2 Ventilation Hum` | 2 | looping ambience bed |
| `Level 2 Distant Water` | 2 | looping ambience bed |
| `Level 2 Player Dry Tile Walking Sound` | 4 | footsteps where there is no water underfoot |

The other seven have **zero code references** — filling them does nothing today:
`Level 2 Ceramic Knock`, `Level 2 Exit Unlock`, `Level 2 Fluorescent Buzz`,
`Level 2 Swim Stroke 1`, `Level 2 Swim Stroke 2`, `Level 2 Underwater Thump`,
`Level 2 Valve Turn`. Two of those look genuinely obsolete: water is wading
depth wall-to-wall and nobody ever swims, so the swim-stroke pair has nothing to
trigger it. Either delete the orphans or wire them — leaving them looks like
missing content when it isn't.

For reference, the two cue slots that *are* filled are `Level 2 Pump Start` and
`Level 2 Pressure Door` (the latter gets a spatial multi-emitter corridor echo).

---

## 6. Open item — Pool Foam art

Pool Foam runs, but on **deliberately temporary proxies**. Two entities start as
still props in separate Kids Area rooms, move only while unobserved, and
escalate through `Dormant → Foreshadow → Pressure → Finale` alongside the pumps.

To replace the placeholder art, drop `PoolFoamPrimaryTemplate` and
`PoolFoamSecondaryTemplate` Models directly under `ServerStorage.Level2Assets`;
they are picked up on the next Level 2 load. Full instructions are in
`README - LEVEL 2 POOL FOAM`. `PoolFoamConfiguration.Enabled = false` is the
one-switch rollback during playtesting.

---

## 7. Testing

- Force a layout with the `Level2Seed` workspace attribute; clear it for random.
- Dev keys (whitelisted users): **B** esp + fast queue · **V** noclip fly ·
  **M** dev phone.
- Read `ReplicatedStorage["Level 2 State"]` attributes to see the phase, the
  seed actually resolved, and whether the fallback seed was used.
- Changes here have historically been validated across multiple seeds with
  geometry probes — clip scan, stair connections, swim depth, wedged props, exit
  clearance — before landing. Keep doing that; one seed proves very little in a
  procedurally generated level.

The audit that just landed changed Level 2 behaviour in ways that only show up
across several rounds in one server (the puzzle-manager level guard in
particular), so a multi-round playtest is worth more than a single launch.

---

## 8. Guardrails

- Do not remove or move in-game objects — walls, props, world geometry. Code
  only, unless asked.
- `ServerStorage/*Backup*` folders are intentional archives, including
  `ServerStorage.Level2Backup_20260805` (the retired hand-authored Flooded
  Poolrooms level). Never audit or clean them, and never restore retired
  poolrooms/valve/blackout scripts into the active rewrite.
- Clear the `Level2Seed` override before publishing.
