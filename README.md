# BACKROOMS: STAY QUIET [CO-OP HORROR]

A round-based **Backrooms-inspired multiplayer horror game** for Roblox, by
**ERN Roblox Studios**.

You spawn in a road-tunnel lobby, queue up a party at a launch station, and get
teleported into a level. Go down and you spectate through a teammate — unless
somebody spends a Zyntra **Emergency Re-entry**, which puts you back on your
feet in the SAME round. Solve the level's objective while something hunts you —
escape together, or watch your friends try.

**Release status (2026-08-30): the verified Roblox release is live; GitHub
mirror finalization is the only remaining gate.** Studio place version
**v1641** was published, and the public experience page now shows the exact
title `BACKROOMS: STAY QUIET [CO-OP HORROR]` plus the approved spoiler-free
description. The full Slidemouth suite
passes **391 checks with 0 failures** at the authored model scale, the round-
completion suite passes **397/0**, the UI suite passes **200/0**, and the touch-
target matrix passes **262/0**. Level 2's invisible exit sensors have also passed
an authoritative **105-stud/s** ragdoll crossing and a separate **75-second**
recycle ride, while the Level 3 navigation/furniture regression is green. The
Studio mirror compiled and matched **114/114 scripts both before and after** the
repository-history integration, with no gameplay residue left in Edit. The
remaining release-record step is committing this publication state and
verifying `origin/main` on GitHub.

Level 3 — the **Mall Backrooms Party** — has its core systems in place (layout
generator, Mall Manager AI, hiding, music/blackout cycle) and is still being
built out. It is the current campaign endpoint: there is no Level 4.

### Finishing a level

One **full-screen result overlay** for every outcome, on every level — there is
no second "card" shape. Levels 1 and 2 offer exactly two actions, **CONTINUE**
and **BACK TO LOBBY**; Level 3 is the campaign's last level and offers **BACK TO
LOBBY** alone, with no route to a Level 4.

- **CONTINUE moves that player immediately**, including in multiplayer. It never
  waits for the rest of the party.
- **What "immediately" means, precisely** — this has been misread twice, so it
  is written out here. Pressing Continue takes that player off the COMPLETED
  SERVER at once; nothing holds them there. The next-level server then *stages*
  them, as it stages every continuer, until the source's decision deadline plus
  a bounded transport grace, because until that deadline passes it cannot know
  whether anybody else is still coming. Staging is not waiting: they are a full
  participant the whole time, never a spectator, and they are admitted no later
  than deadline + grace even when they were the only person in the round and no
  final packet is ever sent. `Round Completion Test Suite` asserts exactly that
  case. A destination that admitted the first arrival on its own is the bug this
  replaced, not the behaviour to restore.
- The **15-second countdown is the auto-continue deadline** for anyone who has
  not chosen, not a barrier the early presser sits behind.
- One result window is **one session** with a **frozen roster**: membership is
  fixed when the window opens and never removed from, only the decisions move.
  That is what keeps the head count honest when a player presses Continue,
  departs, and leaves this server mid-window — erasing them on `PlayerRemoving`
  used to tell the destination to expect one fewer than was actually coming, and
  the destination could start on that undercount with a later continuer still in
  transit. The session reserves the next-level server once; every continuer
  travels under its id, deadline and cohort; the destination **stages arrivals
  until that deadline** (plus a bounded transport grace) and then admits the
  whole cohort into one round. `Round Completion Test Suite` replays that
  sequence including the `PlayerRemoving` step; **the cross-server transfer that
  carries it is still not tested** and cannot be from Studio.
- Every transfer is **claimed before it starts**, and the claim is explicit —
  pending until something resolves it, never "succeeded" merely because
  `TeleportAsync` did not throw. Every outbound attempt carries its own **id**,
  which rides in the teleport data, so `TeleportInitFailed` is matched to the
  attempt that produced it: one attempt earns at most one failure however many
  times Roblox reports it, and a late next-level report cannot charge the fresh
  lobby claim that replaced it or resurrect its dead options. A retry rebuilds
  the request from the recorded descriptor under a new id. A player is moved
  exactly once, a rejected transfer earns one authoritative retry and then a
  lobby fallback, and a failed claim releases its player back to the settlement
  sweep instead of leaving nobody responsible for them.
- **One watchdog owns every unfinished transfer.** Roblox can accept a request
  and then report nothing at all — no `PlayerRemoving`, no `TeleportInitFailed`.
  A single sweep on the module's own schedule expires such a claim into the
  normal retry/fallback policy, and all four endpoints (the continuation, the
  Level 3 Back, a loss, and a refused next-level fallback) wait for settlement
  before letting go. The sweep interval, the stale threshold and the endpoint
  wait are one policy, checked against each other by the suite; they used to be
  three independent numbers, which is how the expiry pass came to run five
  seconds before anything could possibly be stale and how the Level 3 and loss
  endpoints returned after 1.6 seconds without settling at all.
- The **completed world stays up** through the result window and is then held
  until every transfer claim that window opened has resolved (hazards stop with
  `RoundActive`; the map and its solved lighting do not). A single rule decides
  what happens next — `Routing.TeardownPlan` — and it says the same thing at the
  Level 3 endpoint, after a loss and on a refused next-level fallback: in a
  reserved server a refused transfer **keeps the map** under the players it
  could not move and hands them to the per-player retry, and only a public or
  Studio server, which really does own a lobby, tears the world down. Level 2's
  exit-tube handoff into Level 3's continuation bore is unchanged.
- The overlay is **responsive**: the two actions share a row on desktop, tablet
  and landscape phones and stack on portrait, always at least 44px tall on
  touch, always clear of the countdown, with no keyboard glyphs on touch
  devices.

## 🚇 The lobby ("Zyntra Transit — Powering the Future.")

- A persistent tunnel lobby built at server start (`TunnelLobbyBuilder`). You walk
  around in your **own Roblox avatar** (third person, jumping allowed, dance emote
  on `G`).
- Six **level bays**; bays **1–3 are active**, 4–6 are sealed ("ACCESS UNSTABLE").
  Each bay is themed after its level (yellow office, poolrooms tile, mall party)
  and has four **launch stations** — wall-mounted monitors on articulated arms
  over circular launch pads. Step onto a pad to host, pick **party size (1–6)**
  and **public / friends-only**, and a countdown starts as the party fills.
  Station monitors are depth-tested (no more screens showing through walls) and
  the bays' floor furniture is **solid** — only the deliberately wall-glitched
  "geometry error" props stay intangible.
- Launching teleports the party to a **reserved server** that generates exactly one
  world for that party (in Studio it falls back to an in-place test round).
- Entering a round swaps everyone into the **hazmat gameplay rig**
  (`StarterCharacter`) with normalized avatar size (hitbox parity), locked
  first-person camera, and the full horror HUD. Back in the lobby you get your
  personal avatar and relaxed camera again — everything is gated on the
  `InRound` attribute.

## 🟨 Level 1 — The Yellow Maze (done)

Procedurally generated 40×40 office maze (corridors, plazas, pit rooms, and a
brushed-aluminum service elevator with its own roof texture), new layout every
round.

**Objective** (scales per player — each player adds 1 fuse box, 1 lever, and one
**coloured circuit**; twice as many wall relays spawn as fuses needed):
1. Extract **fuses** from wall-mounted ZYNTRA relays — nearby ceiling lights
   cluster-glow to hint where they are, and extraction makes noise the entity
   hears.
2. Insert into wall-mounted **fuse boxes** (status plates, carried fuse shows in
   your hand). Every insert raises the danger — flicker, entity speed — and draws
   the entity to that area. All boxes full → continuous red **ALERT**.
3. Pull every **lever** within 10 s of each other (countdown + status HUD; if a
   teammate dies the sync requirement is dropped — levers latch).
4. A radial **POWERDOWN** wave kills the lights, the **exit gate** opens (an
   energy-signal detector in your HUD leads you there), the entity guards it.
5. Escapees spectate; the round ends when everyone alive is out (win) or
   everyone is dead (lose).

**Coloured circuits:** every fuse-box + lever pair gets its own cable colour
(red, blue, green, yellow, magenta, cyan) with physical floor cables routed from
just outside the elevator doors to both ends. The cabin's **maintenance poster
shows the full circuit list — total cable count and one coloured row per
circuit — from the moment the elevator ride starts**, so the party can plan
before the doors open.

**Audio:** the fluorescent **hum is positional, per ceiling panel** — each lit
panel hums on its own (nearest panels only, streaming-safe), and a panel that is
dead, flickering, blacked out or powered down is **silent**, so your ears tell
you which fixtures are live. Death screams, chase music, yells, footsteps and
the grandfather-clock strike are positional and live.

The positional **entity-vocal** system is implemented — server-scheduled so the
whole server hears the same take from the entity's actual direction — but its
distant-scream, lunge and idle-vocal **asset slots are still empty**, so those
particular sounds do not play yet. They are polish slots, not missing code.

**The Entity** (custom skinned Meshy rig, 51 bones, full Blender animation set):
hunts by **sight and sound** — sprinting is loud, sneaking silent, your flashlight
extends its vision range. Grid-navigates the maze it has learned (never clips
walls), remembers your live position 5 s after losing sight, and re-picks a hunt
target every minute. Glowing eyes (amber → **red when hunting**), ballistic
**pounce lunge**, pit-edge **howl** that shoves beam-walkers into the void, and a
**5-second cinematic ground-pin kill** with a first-person kill camera, synced
scream, and fade to spectate.

## 🩵 Level 2 — Sunken Leisure Complex (world built, hostiles live)

A bright, sunlit liminal poolrooms **water park** with its **own** generator —
it shares only the tile texture and the water look with Level 1. (The previous
hand-authored Flooded Poolrooms level is preserved in
`ServerStorage.Level2Backup_20260805`.)

- **Binary space partition** of a 1400-stud region: ~45 halls capped at ~250
  studs a side (`MaximumLeafSize`), joined by flooded **arch-tunnel corridors**.
  A **fresh random seed every round**. Water covers the floor **wall-to-wall**
  in every pool hall at **wading depth only** — nobody ever swims.
- **Real sunlight**: translucent no-shadow glass roof, and per-hall **skylight
  patterns** — full lines, dashes, a punched checkerboard, or a single centre
  band — so no two ceilings read the same. Smooth trumpet-curved columns run
  flush from floor to ceiling; a world-level column registry plus doorway
  keep-out strips guarantee no pillar ever overlaps anything or blocks an exit.
- **Play furniture in every water hall**, randomized per seed and
  collision-verified: slide kits (straight railed stairs → platform on legs →
  chute into the water), **diving towers** with blue/yellow/red/green boards at
  several heights, play towers with tube flumes, railed overlooks, and a swarm
  of **buoyant** noodles, beach balls, rings and rafts that bob and drift when
  players wade into them (each spawned only in verified-open water).
- **Slide halls** (3): mezzanine deck, straight parallel flumes with
  colour-moulded tubs and clean bores, a dense whole-turn spiral stair docking
  onto the east catwalk, and a **helix slide on its own dedicated column** fed
  by a catwalk bridge. Riding a slide is a real physics ride (`Level 2 Slide
  Controller` + server-side **slide ragdoll service**). The grand hall carries
  the exit flume east into an **endlessly recycled helix**: a rider who reaches
  the bottom of the drum is put back a full turn above it with the tangent's
  momentum, so the ride never ends on its own and the completion window is what
  takes them out of it. The old gateway room survives only as the sealed
  **emergency recovery chamber** — its west aperture is walled in, no tube
  enters it, and nothing routes a player there except recovery.
- **Kids wing**: cosy painted rooms with whole-room ankle-deep water, kids
  slides in the room's own colour, a hex-packed **ball pit** (~370 balls), and
  round roof skylights.
- **Pump rooms**: raised walkway ring + centre pump island over shallow water,
  with a diagonal three-board jump stand.
- **Objective:** start **3 pump stations** — each drains a flooded corridor
  (terrain water actually removed) — then the pressure doors into the grand
  hall unseal; ride the exit flume from the top deck.
- **Sound**: `Level 2 Sound Controller` + StringValue slots in
  `ReplicatedStorage["Level 2 Sound Library"]` — ambience beds, authored cues
  (the pressure door gets a spatial multi-emitter corridor echo), random
  contextual one-shots anchored to real world geometry, **wading footsteps**
  (the runtime plays **trimmed step windows cut from the source phrases** — not
  the complete phrases — plus a quiet underwater-resistance layer, driven by an
  actual water raycast) and a separate **dry-tile footstep slot**
  (`Level 2 Player Dry Tile Walking Sound`, which ships with a bundled fallback)
  for walking where there's no water underfoot.
- **Hostiles:** the **Pool Foam** stack (controller, navigator with roof-safe
  floor probing, observer, proxy rig, animation adapter, client effects) and the
  **Slidemouth** (its own controller + client, tied to the pump/slide soundscape
  with warning/scream serials and four monster-groan recordings). Dens, per-hall
  patrol nodes, hall-centre navigation nodes and spawn markers are generated,
  and all three anchor kinds are reachable from the world manifest.
- **Slidemouth appearance is measured in ROOM HOPS**, not studs. A hall is
  85–270 studs on a side and one corridor hop spans ~110–330 studs, so a fixed
  stud band meant "two rooms away" on one seed and "same room, far corner" on
  the next. The selector walks the same hall graph the navigator does —
  pressure-door gate included — so a finite hop count also proves the creature
  can reach the party from there. It **never uses a room a living player is
  standing in**, requires 1–2 rooms from the NEAREST living player, and past a
  proximity floor. Those are **hard admissions, not preferences**: an anchor
  outside the window is refused, never demoted into a lower tier that some other
  ranking term can promote back out of. Pump proximity and line of sight rank
  only INSIDE the admitted set and can never reach a room the room rule
  excluded. The same predicate runs again immediately before the commit, against
  live player positions re-read at that moment — so a player who walks into the
  chosen room during the validation yield invalidates it. If nothing is
  admissible the spawn **waits**; it never takes a least-bad room and never
  spawns anyway.
- **Step handling.** The navigator resolves the **highest reachable** surface
  under its feet and treats authored ground within one step height as floor
  rather than as a wall, so stair risers, corridor curbs and deck edges are
  crossed instead of jammed against. A blocked stride steers through an
  authored angle ladder — but only into a placement that CLOSES the distance to
  the current waypoint, so the creature either makes progress or is honestly
  blocked and can never orbit a wall reporting movement. A wedged creature backs
  out along **positions it has already stood on**, each step revalidated — there
  is no teleport recovery.
- **A stride is validated in pieces, not just at its endpoint.** At the fastest
  chase speed one frame asks for 3.6 studs (36 studs/s x the controller's own
  0.1 s clamp), and the authored features the creature has to negotiate are
  1.2 / 1.4 / 0.8-stud pool and stair edges and 0.70–0.80 curbs. A single
  placement straddles all of them: both ends sit on the low slab and the riser
  between was never sampled. The stride is now walked in pieces of at most
  `MaxTravelStep` (0.9), each running the full floor resolve and body-volume
  test, capped at 12 pieces so an absurd delta fails CLOSED rather than falling
  back to one unvalidated leap.
- **Tests:** `Level 2 Slidemouth Test Suite` runs against a real generated
  world. It derives every spawn property (room, hop counts, occupancy, line of
  sight, proximity) **independently** from the anchor's world position rather
  than trusting the controller, drives the real spawn through a real pump
  transition, and includes a movement race and an eligibility drop-out. Its
  ledge probe builds controlled ledges at known rises and samples authored
  edges across every family, and only accepts a refusal when it can confirm
  real geometry in the way or a genuinely missing floor.
- Every change is validated in live play sessions across multiple seeds by
  geometry probes (clip scan, stair connections, swim depth, wedged props, exit
  clearance) before it lands.
- Tweak guide for collaborators: `ServerScriptService."Level 2 Systems".README
  - LEVEL 2 TWEAKS`. Force a layout with the `Level2Seed` workspace attribute,
  set to any number **≥ 1**. Set it to **0** — or clear it — for a fresh random
  map every round; 0, negatives and non-numbers all mean OFF. A round never
  writes its random pick back into the attribute.

## 🟣 Level 3 — Mall Backrooms Party (in development)

A dead-mall party floor behind bay 3. The core systems are in and being built
out (`Level 3 Systems`):

- **Deterministic layout generator** for the mall — straight, axis-aligned
  connections, one centered opening per room side, no diagonal corridors.
- **The Mall Manager**: a server-authoritative kinematic custom-rig enemy with
  multi-ray perception, server-inferred hearing, sticky multiplayer targeting,
  last-known-position memory, authored-room strategic routing, stuck recovery
  and fair line-of-sight attacks (plus a client-side visual smoother).
- **The music cycle**: one authoritative server clock runs the five-second
  warning → a 2:30 **blackout** while the song finishes → a final 30-second
  Mall Manager **hunt** → uneven fluorescent recovery, then the next
  synchronized song cycle.
- **Hiding**: server-validated **under-table hiding** with prompts, occupancy
  and character restoration.
- Its own lighting/sound controllers, reader client, and a large in-Studio
  **test suite** (`Level 3 Test Suite`).

## ⌨️ Controls

| Input | Action |
|---|---|
| `WASD` | Walk (quiet — the entity hears at medium range) |
| `Left Shift` | Sprint — **loud**, limited stamina, 3× stamina while being chased |
| `Left Ctrl` | Sneak — slow and silent |
| `F` | Flashlight — battery-limited (**~90 s** of continuous light on a full charge), flickers as warnings; **visible to teammates** |
| `Q` / `E` | Spectate while dead / escaped — full first-person POV of survivors |
| `G` | **In a round:** drop a glowstick. **In the lobby:** dance emote |
| Touch | On-screen **RUN / JUMP / SNEAK** buttons + flashlight tap target. SNEAK is the touch crouch (toggle, silent movement) — the keyboard's `Ctrl`. The **POV** button is dev-only (`devAllowed`) and is not a general player control |

## 🗂️ Repository layout

**Roblox Studio is the release source of truth.** The repo and the place are
kept in an **audited two-way sync**: edits are made in whichever place is
convenient, pushed the other way byte-for-byte, and then *proved* equal — every
push is verified on landing, and `tools/verify_studio_parity.py` re-derives the
comparison from a fresh fingerprint of the live place rather than trusting the
manifest it is checking. What ships is what is in Studio; the repo is the
reviewable copy of it, not a write-only mirror. Folders mirror the Studio
Explorer 1:1, and `studio-sync-manifest.json` records the canonical sha256 of
every mirrored file. The current manifest contains **114 scripts and 13
RemoteEvents**. Its `studioTrailingNewline` count is transport-derived and can
change after an exact landing, so the manifest's live `counts` field — not a
number copied into this README — is authoritative.

```
ServerScriptService/
  GameManager.Script.lua            lobby queue, reserved servers, round loop
  TunnelLobbyBuilder.ModuleScript   the tunnel lobby + launch stations
  MazeGenerator.Script.lua          Level 1: maze, pits, elevator, lights, decor
  PuzzleManager.Script.lua          Level 1: fuses → boxes → levers → exit
  EntityAI / EntityAnimation / EntityKill      Level 1 entity (AI, clips, kill)
  Level2Generator.ModuleScript      Level 2: doorway into "Level 2 Systems"
  Level 2 Systems/                  Level 2: config, BSP layout, world builder,
                                    pump objective, slides + ragdoll, Pool Foam
                                    + Slidemouth hostiles, Slidemouth test
                                    suite, tweak README
  Round Completion Routing.ModuleScript   post-win routing rules (pure)
  Round Completion Test Suite.ModuleScript  assertions for those rules
  Level3Generator.ModuleScript      Level 3: doorway into "Level 3 Systems"
  Level 3 Systems/                  Level 3: config, layout, world builder, Mall
                                    Manager AI, hiding, music cycle, test suite
  FlashlightSync / AvatarNormalize / NoiseRegistry   shared services
StarterPlayer/
  StarterCharacter/                 hazmat gameplay rig (+ Animate)
  StarterCharacterScripts/          run anim, muted default steps, dance emote
  StarterPlayerScripts/             HUD, audio hub (SoundController), per-level
                                    sound/lighting controllers, flashlight,
                                    spectate, slides, scares…
ReplicatedStorage/Remotes/          RemoteEvents (.txt markers)
ReplicatedStorage/UIDevice          form factor + safe-area layout for the HUD
ReplicatedStorage/UIRegression      the HUD regression matrix (see Testing)
assets/                             source assets: textures · sounds · models ·
                                    banners · animations (FBX + keyframes) · blender
tools/                              Studio/Blender MCP pipeline (see below)
artifacts/                          captured screenshots from automated playtests
```

## 🔧 Tooling (MCP pipeline)

Everything below drives **live Roblox Studio and Blender** over MCP:

- `pull_source_from_studio.py` — audits every mirrored script against Studio's
  live `.Source` (hash comparison) and pulls whatever drifted. This is the
  primary sync path.
- `sync_from_studio.py` — the original full Studio → repo mirror. **Caveat:**
  its `script_read` calls can serve a stale editor buffer after programmatic
  source writes; prefer the pull tool above.
- **Repo → Studio pushes**: `record_pending_push.py` marks repo-edited scripts
  as `pending-studio-push` in the manifest (remembering the hash Studio should
  still hold), and `push_repo_to_studio.py` applies exactly those entries
  through `ScriptEditorService:UpdateSourceAsync` — raw `.Source` writes leave
  LocalScripts running stale bytecode. The push is two-phase and refuses to
  half-apply a batch:

  ```
  python tools/push_repo_to_studio.py --list    # offline: what is queued
  python tools/push_repo_to_studio.py --audit   # read live Studio, classify, write nothing
  python tools/push_repo_to_studio.py           # phase 1 check, then phase 2 write
  ```

  Phase 1 reads every queued script's live source and classifies it
  (already-applied / ready / conflict); **any** conflict aborts before a single
  byte is written (`--skip-conflicts` pushes the clean ones,
  `--overwrite-conflicts` accepts Studio's copy as the baseline). Phase 2 stages
  each source in a ServerStorage buffer, verifies its length, then swaps it in
  through a callback that re-checks the baseline *inside* Studio — so a script
  edited between the check and the write is never clobbered. Every pre-push
  source is saved under `.studio-push-backups/<timestamp>/`, and the manifest is
  rewritten atomically after each file.

  While a push is queued, `pull_source_from_studio.py` **skips** those files
  (their repo copies are newer than Studio); pass `--force` to discard the
  unpushed edits instead. (`push_level1_to_studio.py` /
  `push_level2_poolrooms_to_studio.py` are kept for history but predate this.)
- **When the MCP proxy is out of date**, every tool above fails with
  `Client proxy is out of date, restart to update` and cannot reach the place at
  all. The fallback transport keeps the one property that matters — the bytes
  are never retyped through a tool call:

  ```
  python tools/stage_push_payload.py <repo-relative file> [...]   # write an .rbxmx under rbxasset://
  # then in Studio: game:GetObjects("rbxasset://MongoTVPush/payload.rbxmx")
  #                 -> ScriptEditorService:UpdateSourceAsync per target, verified
  python tools/stage_push_payload.py --clean                      # remove the staged file
  ```

  Two things about it are load-bearing. Studio's XML reader hands the source
  back with **CRLF** line endings, so the apply step normalises before writing —
  without that every file lands one byte per line too long. And a raw `.Source`
  write refuses any string of **200,000 characters or more**, which Level 2
  World Builder (248,130) exceeds; `UpdateSourceAsync` does not.

  Afterwards, `tools/record_synced_source.py <dump> <file> ...` writes the
  manifest entry — and refuses unless the parity dump below already shows Studio
  holding that content.
- **Independent parity check.** `tools/studio_parity_probe.luau` prints a
  fingerprint (byte length + FNV-1a-32 + djb2) of every `LuaSourceContainer` in
  the open place; `tools/verify_studio_parity.py <dump>` recomputes the same
  fingerprint from the mirrored files and buckets every entry as
  exact / permitted-newline / drift / missing / extra. It deliberately does
  **not** reuse the manifest's sha256: a check that reads the record it is
  checking only proves the record is self-consistent.
- **Compile check.** `tools/studio_compile_probe.luau` compiles all 114 scripts
  without running any of them, by wrapping each source as
  `return function() ... end` and `require`ing the wrapper — the body is
  compiled, and the function is never called.

### Sync tooling tests

```
python tools/tests/test_studio_source_contract.py     # offline, no Studio, no luau
python tools/tests/test_full_sync_contract.py         # offline, includes a read-only pass over this checkout
python tools/tests/test_push_repo_to_studio.py --fixture-only   # proves the synthesized queue
LUAU_BIN=<path to luau> python tools/tests/test_push_repo_to_studio.py   # the 17 end-to-end push tests
```

`tools/studio_source_contract.py` is the single definition of "the repo file and
Studio's source are the same": line endings are not content, and an entry
flagged `studioTrailingNewline` permits Studio's copy to be the repo text plus
**one** trailing newline and nothing else. The first two suites enforce that
offline and can run with no Studio or Luau runtime; their release result must be
re-recorded after the final manifest reconciliation.

That flag count is **not** a constant. `test_full_sync_contract.py` asserts the
stable invariant instead: the count published by the manifest must equal the
number of entries actually carrying the flag, and the manifest's contract prose
must name that same current count.

`test_push_repo_to_studio.py` runs the push tool's **real generated Luau**
through a real `luau` binary against a fake DataModel, so it needs `LUAU_BIN`
(or `tools/tests/luau`). Without one it reports every test as *not executed* and
exits non-zero rather than reporting green; `--fixture-only` verifies the
synthesized pending queue the suite needs and runs anywhere.
- **Animation pipeline**: author/fix clips in Blender
  (`blender_mcp_client.py`, `build_*` scripts) → export retargeted keyframes
  (`export_entity_keyframes_retargeted.py`) → publish as Roblox animations
  (`publish_entity_animations.py`, versioned manifests in `assets/animations/`).
- **Automated playtests**: `playtest_level1.py` (server/client health, cable
  overlap detector, lunge/run probes), `playtest_entity_kill.py`,
  `playtest_lobby_avatar_transition.py`, `playtest_ui_pit_regressions.py`, plus
  `capture_*.py` screenshot tools (results land in `artifacts/`).
- `publish_elevator_textures.py` — upload texture PNGs through Studio.

## 🧪 In-Studio test suites

The gameplay and UI suites run inside a Play session against real generated
content and are written to fail rather than pass quietly. The same table also
keeps the remaining external release gates visible.

**Verified release-candidate results — 2026-08-30:**

| Suite | Result | Outcome |
|---|---|---|
| `Level 2 Slidemouth Test Suite` | 391 checks, 0 failed, authored scale | **PASS** |
| `Round Completion Test Suite` | 397 checks, 0 failed | **PASS** |
| `UIRegression` | 200 checks, 0 failed | **PASS** |
| `UIRegression.TouchTargetMatrix` | 262 checks, 0 failed | **PASS** |
| Level 2 exit transition | 2 invisible sensors; 105-stud/s authoritative crossing; 75-second recycled ride | **PASS** |
| Level 2 movement audio | 3 wet runs and 1 dry-tile run; no wet gap above 0.480 s | **PASS** |
| Level 3 navigation + furniture | 20 navigation seeds; 9 lanes; 321 furniture parts preserved | **PASS** |
| responsive-device visual sweep | Galaxy A06, iPhone 17 Pro, iPhone 17 portrait, iPad Pro M5 | **PASS** |
| pre-integration whole-place compile + Studio/repo parity | 114/114 compiled and matched; 0 drift or missing | **PASS** |
| post-integration whole-place compile + final Studio/repo parity | 114/114 compiled and matched; 0 drift, missing, extra or residue | **PASS** |
| Roblox Studio publish + live Creator Dashboard title/description | place v1641 published; exact public title and description verified | **PASS** |
| repository integration + GitHub push | remote history integrated locally; push not performed | **PENDING** |
| `tools/tests/test_push_repo_to_studio.py` end-to-end round-trips | not executed — no `luau` binary on this machine | **NOT RUN** |

The Slidemouth result is the full suite, not a reduced cosmetic-size run. The
monster remains at its authored `MODEL_SCALE = 1`; navigation/body clearance is
validated independently from its separate **5.25-stud attack reach**. The suite
keeps the hard 1–2 room-hop spawn admission, multiplayer commit-time
revalidation, production-speed substep mutation proof and strict traversal
criteria intact.

The remaining pending rows are external actions and are deliberately not
inferred from local state. This candidate is not described as published until
the live place, metadata and remote Git commit are each verified.

| Suite | Where | What it covers |
|---|---|---|
| `Level 2 Slidemouth Test Suite` | `ServerScriptService."Level 2 Systems"` | **The spawn contract, enforced at the commit** — "1 to 2 rooms from the nearest player" used to be three different rules in three places and none of them hard: the ranking DEMOTED an out-of-window room instead of refusing it (and two of the demoted tiers outranked a room inside the window), the commit-time re-check re-tested occupancy and studs but never re-measured hops, and the pump-three escalation carried a third paraphrase with no hop bound at all. There is now ONE predicate and the suite runs the very function the commit calls, comparing its answer against a room graph the suite walks itself — including a tie one hop from two players, a saturated map where the only correct answer is to WAIT, and a party that MOVES between the ranking and the commit. **The substep floor resolve at the fastest production stride** — `PumpThree x MaxStepDelta` = 3.6 studs, read from the controller rather than copied, on two constructed lanes sized so one unvalidated leap straddles the feature and .9-stud substeps cannot: a 1.2-stud rise the creature must STAND on, and a 2.0-stud trench six studs above the floor it must REFUSE. The pre-rewrite navigator is kept as an in-suite mutant that calls the same `_placeFoot` with the loop removed, so the two must disagree. **Pause isolation over a loaded incumbent** — a borrowed session is parked, written over, thrown at, and handed back: the true PRE-ARM baseline is restored field for field, the navigator's `Path.Blocked` binding and its in-flight computation are restored under a documented contract, a failed pause leaves the incumbent running and a failed resume leaves the handle unconsumed, parked sessions are visible to the residue checks and stoppable by handle, and a scream pending before the pause fires exactly once afterwards at its PRESERVED REMAINING delay. Plus spawn selection re-derived independently of the controller — room, hop counts, pump hops, distance, sight and **tier**, plus the documented ordering; the production spawn path with the movement race **injected between the ranking and the commit** and eligibility read through the controller's own gate; the repaired failure modes (context-free ranking, bounded retreat, fail-closed sweep); ledge crossing on controlled rises and authored edges, where every attempted probe must end up crossed or verifiably refused |
| `Round Completion Test Suite` | `ServerScriptService` | Seven groups, including **Cohort timing, claim anchors and synchronous failures**: a source party and its destination driven over ONE fake clock so a silent continuer's bounded retry is proved to land before the destination admits; a claim that never reaches a dispatch reaching finite settlement; repeated and concurrent `ForceSettle` proved idempotent; and synchronous dispatch rejections proved to enter the same retry/fallback/surrender policy a `TeleportInitFailed` callback does. Plus the post-win routing rules and the frozen roster; proof that the **running GameManager** loaded, uses the routing module and keeps no completion or transfer state of its own; the source→destination admission handshake replayed with the production `PlayerRemoving` step (early continuer departs mid-window, later manual Continue, timeout continuer, quitters, Back users, duplicate packets, bootstrap); the attempt-correlated failure path with real `TeleportOptions` (duplicate report, stale report after fallback, stale options never retried); and the completed-world teardown rule |
| `UIRegression` | `ReplicatedStorage` | `BriefingExclusionMatrix()` — the dispatch briefing, the queue host modal and the Zyntra store opener, which all own the same strip of screen: a seven-state machine driven in BOTH orders (a modal raised over a live briefing, and a briefing raised under a modal already up) at two viewports, asserting the two published flags, the pixels they are derived from, that the opener leaves the INPUT STACK and not merely the screen, that the transmission itself is never torn down by suppressing its panel, and that no rect anywhere under the briefing panel overlaps any rect anywhere under the modal. Plus the developer page's captions against `UIDevice.SuppressesKeyboardGlyphs()` in both modes and back again, so a caption cannot be decided once at build time; `QueueModalMatrix()` — the lobby queue panel resolved arithmetically across thirteen device sizes, behind a calibration gate that first proves the resolver reproduces the engine at the real viewport; `BriefingFitMatrix()` — the dispatch briefing panel measured with `TextService:GetTextBoundsAsync` on portrait and small-landscape phones, proving the longest authored cue neither clips its box nor overlaps the MUTE/STOP row that abuts it; the HUD scenario matrix (including the lobby queue panel's five controls), the completion overlay's actions and routing, a viewport fit matrix across desktop, tablet and phone in both orientations, and `TouchTargetMatrix()` — a tap-size, interactivity and keyboard-glyph sweep across six phone and tablet sizes **including the Galaxy A06's 705×338**, plus a geometry pass at the real viewport with the touch layout applied. The two halves are split on purpose: under the viewport override Studio still renders at its real window size, so position-based assertions only mean something in the real-viewport pass |

```lua
-- server
local Adapter = require(game.ServerScriptService["Level 2 Systems"]["Level 2 Round Adapter"])
Adapter.Build()
print((require(game.ServerScriptService["Level 2 Systems"]["Level 2 Slidemouth Test Suite"])
    .RunAll(Adapter.GetManifest())))
print((require(game.ServerScriptService["Round Completion Test Suite"]).RunAll()))

-- four generated worlds, one seed each
for _, seed in ipairs({101, 202, 303, 404}) do
    workspace:SetAttribute("Level2Seed", seed)
    Adapter.Build()
    print((require(game.ServerScriptService["Level 2 Systems"]["Level 2 Slidemouth Test Suite"])
        .RunAll(Adapter.GetManifest())))
end
workspace:SetAttribute("Level2Seed", nil)

-- client
print((require(game.ReplicatedStorage.UIRegression).RunAll()))
print((require(game.ReplicatedStorage.UIRegression).TouchTargetMatrix()))
print((require(game.ReplicatedStorage.UIRegression).QueueModalMatrix()))
print((require(game.ReplicatedStorage.UIRegression).BriefingFitMatrix()))
print((require(game.ReplicatedStorage.UIRegression).BriefingExclusionMatrix()))
```

A four-seed sweep runs for several minutes. `execute_luau` gives up long before
that, so drive it off the caller with a **finite** deadline and poll the result
— never a bare loop, which can wedge the editor:

```lua
_G.Sweep = {Status = "running", Lines = {}}
task.spawn(function()
    -- BEWARE: os.clock() here is PROCESSOR time, not wall time. The four-seed
    -- sweep finished reporting 343 "seconds" after roughly 25 minutes on the
    -- clock, so a budget expressed this way is far looser than it reads. It is
    -- a runaway backstop, not a schedule. The REAL bound is the fixed list of
    -- seeds: the loop is finite whatever the timer does, which is the property
    -- that matters. Never write the timer as the only thing stopping a loop.
    local deadline = os.clock() + 900
    for _, seed in ipairs({101, 202, 303, 404}) do
        if os.clock() > deadline then break end
        -- ... build, RunAll, append to _G.Sweep.Lines ...
    end
    _G.Sweep.Status = "done"
end)
```

Poll `_G.Sweep` from a second `execute_luau` call. Expect the full sweep to take
**20–30 minutes of wall time**; each seed is a world build plus a `RunAll`.

`UIRegression.RunAll()` measures the viewport Studio is actually rendering, so
the full HUD matrix still wants the **Device Simulator**, set before entering
Play — and so does `TouchTargetMatrix()`'s second half, whose geometry pass runs
at the real window size. `QueueModalMatrix()` and `BriefingFitMatrix()` do not:
they drive the `UIRegressionViewport` override and resolve `UDim2` arithmetically
against the simulated size, each behind a calibration gate that fails the matrix
outright if the resolver and the engine disagree by more than a pixel at the real
viewport. `UIRegression.CompletionFit()` does not: it drives UIDevice's Studio-only
`UIRegressionViewport` override and resolves each action's `UDim2` against the
simulated size, which is why the completion overlay has real phone and tablet
coverage from a single run. `RunAll` refuses to run while that override is set,
because its own assertions compare measured pixels against the reported
viewport and would be meaningless.

### Studio-only regression hooks

Three player/workspace attributes exist purely so a matrix can put the screen
into a state it otherwise could not reach. **All three are gated on
`RunService:IsStudio()` and all three default to off**, so none of them can be
reached in a published place.

| Attribute | On | Effect |
|---|---|---|
| `UIRegressionForceDispatchActive` | player | `hasActiveTransmission()` answers true, so the briefing panel can be raised without waiting for a real cue |
| `UIRegressionSuppressDispatch` | player | hides the AMBIENT transmission *and its subtitle*, so a matrix can establish a genuinely idle screen |
| `UIRegressionViewport` / `ForceTouchUI` | workspace | UIDevice reports a simulated size / form factor |

`UIRegressionSuppressDispatch` was added because clearing the force flag does
**not** reach an idle screen: a Studio session comes up with the first-login
lobby briefing already running, held on screen by `hasSubtitle` even once
`hasActiveTransmission()` answers false, and it is drawn from a file-local table
with no outside handle. Without it the exclusion matrix was asserting against a
briefing it could neither see nor stop, and reported 18 failures that were its
own. It suppresses; it never fabricates — the force flag still wins over it, and
the matrix asserts it reached idle both before and after the sweep.

## 🧪 Testing vs production values

Both are currently at **production** values. Override locally in Studio for
quick tests (don't sync the overrides):

| Script | Setting | Testing | Production |
|---|---|---|---|
| MazeGenerator | `GRID` | `10` | `40` |
| GameManager | `ELEVATOR_TIME` | `2` | `19` (matches the elevator sound) |

### Dispatch briefings

The Command Center lobby briefing is claimed **once per account** and is not
replayed on later joins. **MUTE DISPATCH** changes the saved
`Settings.MuteDispatch` preference and survives rounds and reconnects. **STOP
DISPATCH** ends only the transmission currently playing; it does not change the
saved mute preference. Both controls exist only while a briefing is active,
subtitles remain available when its audio is muted, and touch layouts omit
keyboard glyphs.

The briefing panel occupies UIDevice's TopBand, and so do two other things: the
lobby **queue host modal** and the **Zyntra store opener**. All three used to be
able to draw at once. The rule now is one expression in `dispatchAudio.refresh`,
published as the player attribute `DispatchBriefingOpen`:

* **the queue modal always wins**, in both directions — a briefing raised while
  the modal is up never draws, and a modal opened over a live briefing hides it;
* nothing is torn down. The transmission, its cue timer and
  `ZyntraDispatchClientActive` are untouched, so closing the modal brings the
  panel back mid-sentence rather than burning the one-shot first-login claim;
* the store opener stands down through `UIDevice.SetInteractive`, which clears
  `Visible`, `Active` **and** `Selectable` — it leaves the input stack, not just
  the screen. That distinction is the bug: the briefing panel is opaque and
  draws above, but its Frame is not `Active`, so a tap that missed MUTE/STOP
  fell straight through onto a button the player could not see.

Measured at 705x338 before the fix: the opener sat entirely inside the briefing
panel and overlapped its MUTE/STOP row by 172x42 px, and the panel covered the
queue modal's CloseQueue button completely.

### Leaderboard

The in-game top-10 board ranks **donations only**. It is not a skill, speed or
survival ranking, and nothing about round performance affects it.

**Dev cheats** (`DevCheats.LocalScript` — whitelisted accounts only):
`B` ESP + 3 s fast queue (one key, both toggles — this is deliberate, not a
copy-paste in the captions) · `V` noclip fly · `P` pause entity · `I` push
immunity · `U` unlimited battery/stamina · `C` third person · `J` Zyntra
developer phone · `M` mute/unmute the active dispatch · `N` stop the current
dispatch briefing. These controls are restricted by immutable UserId and
revalidated server-side; they are not general-player controls.

The developer page's captions follow `UIDevice.SuppressesKeyboardGlyphs()`, not
`IsTouch()`, and are re-rendered on `UIDevice.Changed`. The difference matters
for a handheld that reports a keyboard — a tablet in a case, a hybrid: it is
`IsTouch() == false` but suppresses glyphs, and was being told to press keys it
has not got. With glyphs suppressed the intro drops its `//  PHONE: J`, every
toggle drops its `//  <key>`, and the noclip row changes from "WASD, Space and
Left Ctrl" to "using the movement stick".

## 🚀 Release-candidate checklist

- [x] Slidemouth full suite at authored scale: **391/0**, with its hard room-hop
      spawn and strict traversal contracts intact
- [x] Shared completion/routing suite: **397/0**
- [x] UI and touch-target suites: **200/0** and **262/0**
- [x] Level 2 invisible exit geometry, authoritative high-speed crossing and
      75-second recycle ride
- [x] Level 2 wet/dry movement-audio cadence and Level 3 navigation/furniture
      regression
- [x] Pre-integration whole-place compile and Studio/repo parity: **114/114**
- [x] Post-integration whole-place compile, Studio/repo parity and residue
      checks: **114/114**, no drift/missing/extra and no live test residue
- [x] Publish verified Roblox Studio place version **v1641**
- [x] Save and verify the exact live title
      `BACKROOMS: STAY QUIET [CO-OP HORROR]` and the approved description
- [ ] Integrate the intended repository history, commit and push `main` to GitHub

The current Level 3 systems — generated layout, Mall Manager, hiding,
music/blackout cycle, persistent furniture and reader UI — are included, but
the level remains open to future content work. **There is no Level 4**; Level 3
intentionally offers only the route back to the lobby.

`ROBLOX_GAME_DESCRIPTION.md` is the canonical spoiler-free Creator Dashboard
copy. `assets/marketing/roblox-experience-description.txt` mirrors it byte for
byte; the `.md` beside it documents that relationship. Roblox publication is
verified; only the GitHub push remains pending in this release record.

### Known verification limits

The earlier monster-size hypothesis and the old traversal-failure report are
superseded. Slidemouth now passes the full **391/0** suite at authored scale;
the navigation/body checks and separate **5.25-stud attack reach** remain
intentional rather than being hidden by cosmetic scaling or weakened tests.

- **Cross-server transfers are untested.** Studio has no TeleportService
  destination, so nothing here has watched a real reserved server take a party.
  What IS tested is every decision either side of that call: the session
  identity and cohort metadata each continuer carries, when the destination
  admits them, and who owns a player after a transfer is rejected. Treat the
  first published multiplayer Continue as the real verification.
- **Production DataStore rejoin behaviour cannot be proved by a local Studio
  session.** Dispatch mute and the one-time lobby-briefing claim are persisted
  by the game, but the first live leave/rejoin remains the external verification
  of account persistence and service availability.
- Some optional Level 1/Level 3 audio-polish slots remain content work. Level 2
  wet footsteps and their resistance layer are implemented, and dry-tile
  footsteps have a bundled fallback when no custom asset is configured.
