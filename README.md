# BACKROOMS: STAY QUIET [CO-OP HORROR]

A round-based **Backrooms-inspired multiplayer horror game** for Roblox, by
**ERN Roblox Studios**.

You spawn in a road-tunnel lobby, queue up a party at a launch station, and get
teleported into a level. Go down and you spectate through a teammate — unless
somebody spends a Zyntra **Emergency Re-entry**, which puts you back on your
feet in the SAME round. Solve the level's objective while something hunts you —
escape together, or watch your friends try.

**Last published build: place version v1641 (2026-08-30)**, live on Roblox under
the exact title `BACKROOMS: STAY QUIET [CO-OP HORROR]` with the approved
spoiler-free description, and mirrored on GitHub. The place has moved a long way
since — Level 2's hostile roster, Level 1's script layout, the Zyntra store and
Level 3's hiding mechanics all changed after it — so read v1641 as *the last
thing published*, not as a description of what is in Studio today. Every dated
result in this file is accurate for the date it names and has not been re-run
since.

**Level 2 has exactly one hostile: Pool Foam.** Two others came and went. The
Slidemouth was retired on 2026-08-31; the Pool Slide that replaced it was
measured on 2026-09-02 never once to spawn successfully on a generated map — its
failing spawn retried forever and cost 78% of the server's frame budget (13 FPS,
59 with it paused) — and was deleted, backups included. The Slidemouth's code
and its 391-check suite are preserved in
`ServerStorage.Archive.Level2RetiredSlidemouth_20260831`. **Pool Foam has no
suite of its own**, which is the largest open test gap in the project: the Pool
Slide was built without one and failed in every round for days before a
frame-time measurement found it.

Level 3 — the **Mall Backrooms Party** — has its core systems in place (layout
generator, Mall Manager AI, under-table hiding, music/blackout cycle, CD
collection into a five-slot Signal Hall disc player, districts, and a final-hall
chase) and is still being built out. It is the campaign endpoint: there is no
Level 4.

### Finishing a level

One **full-screen result overlay** for every outcome, on every level — there is
no second overlay shape. (The PARTY DOWN card at the bottom of this list is not
an outcome; it is the window *before* one.) Levels 1 and 2 offer exactly two
actions, **CONTINUE**
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
- **A wipe opens a 15-second PARTY DOWN window before the loss overlay.** When
  the last living player goes down, GameManager fires `"partydown"` on the
  `RoundStatus` remote with the window length and the name of whoever fell last
  (nil if the party emptied by a *leave*), and RoundUI draws a card offering a
  Zyntra **Emergency Re-entry** — a held credit, or the re-entry product — next
  to NO THANKS, both inert for the first 0.6 s so a panicking player cannot
  mis-tap. A re-entry raises the alive count and fires `"partydownclear"`, which
  is also what a teardown under the window sends; if nobody re-enters, the window
  ends in the normal `"lose"` and its overlay.

## 🚇 The lobby ("Zyntra Transit — Powering the Future.")

- A persistent tunnel lobby built at server start (`TunnelLobbyBuilder`). You walk
  around in your **own Roblox avatar** (third person, jumping allowed, dance emote
  on `G`).
- Six **level bays**; bays **1–3 are active**, 4–6 are sealed behind a red
  DiamondPlate door reading **COMING SOON — NEW LEVEL IN DEVELOPMENT**.
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

## 🩵 Level 2 — Sunken Leisure Complex (world built, hostile live)

A bright, sunlit liminal poolrooms **water park** with its **own** generator —
it shares only the tile texture and the water look with Level 1. Nothing in the
level is hand-placed: it is all generated from a seed, so every change is a value
in a file. (The earlier hand-authored Flooded Poolrooms level was deleted on
2026-09-02 by explicit decision; it is recoverable from git history at `c2b7527`.)

- **Binary space partition** of a 1400-stud region, joined by flooded
  **arch-tunnel corridors**. A plan is rejected unless it yields at least
  `MinimumHallCount` (16) halls; no leaf exceeds `MaximumLeafSize` (310), so
  halls top out around 250 studs a side, with a rare 270 from an unsplittable
  leaf. A **fresh random seed every round**. Water covers the floor
  **wall-to-wall** in every pool hall at **wading depth only** — nobody ever
  swims.
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
- **The hostile is Pool Foam, and it is the only one.** The stack is a
  controller, a navigator with roof-safe floor probing, an observer, a proxy
  factory, an animation adapter and a client effects script, all in
  `ServerScriptService."Level 2 Systems"`. Dens, per-hall patrol nodes,
  hall-centre navigation nodes and spawn markers are generated with the world and
  reachable from its manifest.
- **It stalks whether or not you look, and looking is what arms it.** One
  server-owned clone stands in each generated Kids Area room (five with the
  current layout). An active clone walks toward the nearest eligible player the
  whole time, accelerating as it goes; being seen does not stop it. What a
  validated look does is *latch the chase* — `ChaseTriggered`, one way, never
  released — which freezes the earned speed bonus, raises the floor to
  `SpeedRamp.ChaseMinimumSpeed` (13) and is the precondition for the creature
  ever being allowed to kill.
- **Contact is lethal only once four things hold.** `instantKill` needs the
  chase latched, `AllowAttacks` for the current phase (pump 2 onward), a
  distance inside `Movement.KillDistance` (5.5 studs), the one-shot
  `ChaseGraceSeconds` (0.45) window already past, and a server line-of-sight
  re-check at the instant of contact — then it is instant death, no wind-up.
  The server owns movement, observation, lethal contact, targeting and cleanup;
  the client only reports its camera.
- **A server proximity latch backs up the client reports.** Every payload check
  in the observer validates where the camera *is*, not where it points, so a
  client whose honestly-shaped reports simply never cover a foam model would
  never latch a chase and would be permanently unkillable. Independently of all
  reports, an active clone that keeps one living, eligible player inside
  `Observation.ProximityLatchRadius` (26 studs) with a clear server line of
  sight for `ProximityLatchSeconds` (2.5) latches the chase exactly as a look
  does. It can only *add* a latch — never clear one, never shorten the grace
  window, never touch `entity.Observed`. `ProximityLatchEnabled = false` turns
  it off.
- **The statue mechanic exists in the code but is switched off.**
  `Observation.FreezeWhileObserved = false`, so the freeze-on-observe path —
  continue 0.5 s (`RevealOverrunSeconds`), pause the AnimationTrack at that
  exact `TimePosition`, hold the pose until the watcher looks away — is
  unreachable in the shipped configuration. Every freeze branch in the
  controller is gated on `observationFreezes(session)`. Read that flag before
  believing any "it only moves when unobserved" description of this creature.
- **The pumps pace it.** `PhaseOrder` runs `Dormant → Foreshadow → Pressure →
  Finale`, gated on how many pumps are running: nothing is active until the first
  pump, attacks are off until the second, and the last phase adds a speed
  multiplier. The pre-latch acceleration above is `Movement.SpeedRamp`
  (`AccelerationPerSecond` 0.65, `MaximumBonus` 12, capped at `MaximumSpeed` 22)
  and `FreezeOnChase` is what stops it toggling on camera-edge noise. Dormant
  and inactive clones ramp nothing.
- **It hears the shared `NoiseRegistry`** (`Hearing` in
  `Level 2 Pool Foam Configuration`, range 120 studs). Sprinting players and the
  running pump motors both report; hearing only steers *whom* it targets and
  where it patrols — it never overrides the look-latch.
  `BeingChased` and `Level2_PoolFoamTargeted` are reference-counted across the
  clones and cleared on death, target drop and `Controller.Stop`.
- **Its art is deliberately temporary.** Drop `PoolFoamPrimaryTemplate` and
  `PoolFoamSecondaryTemplate` Models under `ServerStorage.Level2Assets` and they
  are picked up on the next Level 2 load; full instructions live in
  `ServerScriptService."Level 2 Systems"."README - LEVEL 2 POOL FOAM"`.
  `PoolFoamConfiguration.Enabled = false` is the one-switch rollback for a
  playtest.
- **Step handling.** The navigator resolves the **highest reachable** surface
  under its feet and treats authored ground within one step height
  (`MaxStepHeight`, 3.5) as floor rather than as a wall, so stair risers,
  corridor curbs and deck edges are crossed instead of jammed against. A blocked
  stride steers through an authored angle ladder — but only into a placement that
  CLOSES the distance to the current waypoint, so the creature either makes
  progress or is honestly blocked and can never orbit a wall reporting movement.
  A wedged creature backs out along **positions it has already stood on**, each
  step revalidated — there is no teleport recovery.
- **A stride is validated in pieces, not just at its endpoint.** The authored
  features it has to negotiate are 1.2 / 1.4 / 0.8-stud pool and stair edges and
  0.70–0.80 curbs, and at speed a single frame's placement straddles all of them:
  both ends sit on the low slab and the riser between is never sampled. The
  stride is walked in pieces of at most `MaxTravelStep` (0.9), each running the
  full floor resolve and body-volume test, capped at 12 pieces so an absurd delta
  fails CLOSED rather than falling back to one unvalidated leap.
- **Pool Foam has no test suite, and that is the known risk.** Level 2's live
  hostile has no coverage of its look-latch, its phase gating, its hearing or its
  lethal contact. `Level 2 Exit Transition Test Suite` covers the exit geometry
  and nothing else in the level. The only hostile suite this project ever had
  went into the archive with the Slidemouth (391 checks); the encounter built
  after it without one failed in every round for days before anyone noticed.

### How a Level 2 round runs

`Level 2 Round Adapter.Build()` drives it: resolve the seed →
`LayoutGenerator.Generate(seed)` → `World Builder` → `ObjectiveController.Start`
→ `PoolFoamController.Start`. `Cleanup()` stops both and tears the world down.

- **Seeding.** `workspace.Level2Seed` is a manual testing override: Explorer →
  **Workspace** → Properties → **Attributes**. A whole number from **1 to
  2,147,483,646** pins a layout and reproduces it exactly. **0** — which is what
  the attribute holds after a tester zeroes it instead of deleting it — plus
  negatives, NaN, out-of-range values and non-numbers all mean **random**. A
  round never writes its random pick back into the attribute; a previous version
  did, and froze every server on round one's map. `Level3Seed` reads the same
  contract.
- **The generator retries.** Each attempt strides the seed by 104729 within a
  budget of `GenerationAttempts` (300). Roughly 11% of candidate plans are
  accepted, so ~9 attempts is typical and p99 is 42. An **unpinned** round that
  somehow exhausted the budget takes one more independently seeded stride before
  falling back to the checked-in known-good seed `101`. A pinned seed skips the
  fallback, so a pinned failure stays reproducible.
- **The Grand Slide Hall is the exit room and has its own size floor.** All three
  slide halls must clear `SlideHallMinimumWidth`/`Depth` (175×165); the one
  carrying the exit flume must additionally clear `ExitHallMinimumWidth`/`Depth`
  (210×200) and sit within `ExitHallMaximumShellGap` (80) studs of the east
  shell. The shell-gap rule is not decoration: the flume runs *level* from the
  hall's east wall out to the shell before it plunges, so an exit hall further
  west turns the lead-in into a long flat walk inside the tube. Measured over 400
  seeds with both rules live, the exit hall lands between 210×200 and 263×262
  (median 233×226), always within 44 studs of the shell.
- **The state folder is the first place to look.** `ReplicatedStorage["Level 2
  State"]` carries `Level2_Phase`, `Level2_Seed`, `Level2_ResolvedSeed`,
  `Level2_SeedPinned`, `Level2_UsedFallback`, `Level2_RandomRecoverySeed`,
  `Level2_PumpProgress` and `Level2_HallCount` as attributes. To prove randomness,
  build five rounds back to back and compare `Level2_ResolvedSeed` **and** the
  geometry — a differing seed alone does not prove a differing map.
- **Entering the level is held by the loading cover, not by a timer.**
  `StreamingEnabled` is on, so after the server finishes building, each client
  still has ~70,000 instances to stream. Level 1 and Level 3 hide that behind the
  elevator ride; Level 2 uses the shared loading screen in `RoundUI.LocalScript`
  instead, coloured from `LOADING_PALETTES` (Level 2's status line is literally
  `Configuration.Colors.Water`). `poolaccess` does **not** uncover: the client
  waits until there is solid ground under its own root inside `Level 2 Generated
  World`, calls `RequestStreamAroundAsync`, then reports `entryready` on the
  `RoundStatus` remote, and GameManager holds the round until every client has.
  Three independent ways out stop the cover ever trapping anyone — the client's
  15 s readiness timeout, a 35 s absolute backstop armed with the cover, and the
  server's own 16 s cap — and a player who joins mid-load never arms the hold at
  all. Because the cover does not block input, Level 2's placement anchor
  releases on `RoundActive` rather than on a flat delay, so nobody can walk blind
  off an arrival deck ringed by water. **Levels 1 and 3 are unchanged.** Measured
  live against a 70,960-instance world: cover up at 0.0 s, world built at 3.9 s,
  client acked 3.2 s after `poolaccess` — released by genuine readiness, not by
  timeout.
- **Sound slots are content, not code.** `ReplicatedStorage["Level 2 Sound
  Library"]` holds one StringValue per slot; paste an asset id in and it works.
  Several are still empty, and some of the empty ones have **no code reference at
  all** — the swim-stroke pair in particular has nothing left to trigger it now
  that water is wading depth wall-to-wall. Grep the slot name before you go
  looking for audio: filling an unreferenced slot changes nothing.
- **Validate across seeds, not on one.** Changes here have historically been
  landed only after live play sessions on several seeds with geometry probes —
  clip scan, stair connections, swim depth, wedged props, exit clearance. One
  seed proves very little in a procedurally generated level.
- Tweak guide for collaborators: `ServerScriptService."Level 2 Systems"."README
  - LEVEL 2 TWEAKS"` — about 95% of the tunable values live in `Level 2
  Configuration`.

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
  and character restoration. **Two players fit under one table**
  (`Hiding.HideOccupantCap`), on lanes either side of the anchor; a hidden player
  has `ProximityPromptService` switched off so `E` cannot re-fire the prompt they
  are already inside.
- **The Mall Manager checks tables** (`Configuration.TableCheck`): it biases its
  sweep toward occupied tables, enters a `TABLE_CHECK` state with a two-second
  warning on the occupants' hide banner, then flushes them out to the far side
  with a short window of attack immunity. Per-table and global cooldowns stop it
  camping one table, and a mid-hunt detour is only allowed toward a table closer
  than the nearest exposed player.
- **The objective**: collect CDs scattered through the mall and insert them into
  the **five-slot disc player** in the Signal Hall (`Configuration.ModuleGoal`
  is 5). The state folder tracks collected, inserted, carried and dropped counts
  separately, so a CD dropped on a death is not silently lost from the total.
- **The final hall**: a generated exit corridor with a halfway marker that
  triggers the Mall Manager's **finale chase**, and a validated Manager spawn
  marker of its own.
- **`Level3Seed`** pins the layout for reproduction, on the same contract as
  Level 2: a whole number from **1 to 2,147,483,646** pins, while 0, negatives,
  NaN, out-of-range values and non-numbers all mean "pick a random seed".
  `Level3_SeedPinned` in the state folder shows which mode a round used. (Before
  2026-09-02 the guard was `type(v) ~= "number"`, which accepted 0 and would have
  pinned every round to seed 0's mall.)
- Its own lighting/sound controllers, reader client, and a large in-Studio
  **test suite** (`Level 3 Test Suite`) — see Testing below for its entry points.

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
| Gamepad | **L2** (hold) sprints, **R1** toggles the flashlight. `sprintRequested()` in `NoiseReporter` is the single definition of "asking to sprint", and re-reads the hardware so a stuck trigger cannot pin the lobby to sprint speed. Code-reviewed only — no controller has been on the machine |

### Accessibility

The switches live in the **Zyntra terminal's SETTINGS tab**, reached through the
on-screen `ZYNTRA // EQUIPMENT` opener (`J` is a dev-only shortcut to the same
panel) — the fifth tab, after Upgrades / Shop / Donate / Colors. The rows are
generated from `ReplicatedStorage.ZyntraConfig.AccessibilitySettings`, an
ordered array whose `Key` is *both* the player attribute the client reads and
the `profile.Settings` field it saves under, so a row, the server's allow-list
and the readers cannot drift apart. Toggling one fires
`SetAccessibility {Key, Enabled}` on the Zyntra action remote; the server
persists it and republishes the attribute.

| Key | Default | Honoured by |
|---|---|---|
| `ReduceCameraShake` | off | `EntityShakeController` (proximity tremble, chase rumble, footstep punch — head-bob and crouch are untouched), `Level 2 Pool Foam Client` |
| `ReduceFlashing` | off | `Level 3 Lighting Controller` (the blackout strobe becomes a smooth dim; no snap to black), `Level 2 Pool Foam Client` |
| `CaptionsEnabled` | **on** | Pool Foam's client captions |

`DisableCaptions` is the older half of the caption pair, still read as
`DisableCaptions ~= true and CaptionsEnabled ~= false`. It is marked `Hidden` in
the config and deliberately not drawn — two rows would contradict each other —
but it is still persisted so old saves keep working. Adding a switch is a config
line, not a UI edit; a default must never be flipped to the opposite of what its
readers already assume.

## 🗂️ Repository layout

**Roblox Studio is the release source of truth.** The repo and the place are
kept in an **audited two-way sync**: edits are made in whichever place is
convenient, pushed the other way byte-for-byte, and then *proved* equal — every
push is verified on landing, and `tools/verify_studio_parity.py` re-derives the
comparison from a fresh fingerprint of the live place rather than trusting the
manifest it is checking. What ships is what is in Studio; the repo is the
reviewable copy of it, not a write-only mirror. Folders mirror the Studio
Explorer 1:1, and `studio-sync-manifest.json` records the canonical sha256 of
every mirrored file. Its `counts` field — not a number copied into this
README — is authoritative for how many scripts and RemoteEvents the place
holds, and `studioTrailingNewline` is transport-derived and can change after an
exact landing. A count written into prose here goes stale the first time a
script is added, and has done so repeatedly.

```
ServerScriptService/
  GameManager.Script.lua            lobby queue, reserved servers, round loop
  TunnelLobbyBuilder.ModuleScript   the tunnel lobby + launch stations
  Level 1 Systems/                  Level 1: maze/pits/elevator generator, the
                                    fuse-box-lever puzzle, and the entity's AI,
                                    animation and kill sequence
  Level2Generator.ModuleScript      Level 2: doorway into "Level 2 Systems"
  Level 2 Systems/                  Level 2: config, BSP layout, world builder,
                                    pump objective, slides + ragdoll, the Pool
                                    Foam hostile, exit-transition test suite,
                                    tweak README
  Round Completion Routing.ModuleScript   post-win routing rules (pure)
  Round Completion Test Suite.ModuleScript  assertions for those rules
  Level3Generator.ModuleScript      Level 3: doorway into "Level 3 Systems"
  Level 3 Systems/                  Level 3: config, layout, world builder, Mall
                                    Manager AI, hiding, music cycle, test suite
  ZyntraMonetization.Script.lua     tokens, upgrades, Emergency Re-entry, badges
  LobbyPartyModeController.Script.lua  lobby party mode
  Crouch State Server.Script.lua    server side of sneak
  FlashlightSync / AvatarNormalize / NoiseRegistry   shared services
ServerStorage/                      retired backups (`Archive/`, two
                                    `CodexBackup_20260902_*` folders) plus an
                                    unused third-party asset (`Project Mirror`);
                                    see House rules in CLAUDE.md
Workspace/                          one marker file for the `Entity` rig; the rig
                                    itself is model data, not mirrored source
StarterPlayer/
  StarterCharacter/                 hazmat gameplay rig (+ Animate)
  StarterCharacterScripts/          run anim, muted default steps, dance emote
  StarterPlayerScripts/             HUD, audio hub (SoundController), per-level
                                    sound/lighting controllers, flashlight,
                                    spectate, slides, scares…
ReplicatedStorage/Remotes/          the eight shared RemoteEvents (.txt markers):
                                    RoundStatus, PuzzleStatus, ReportNoise,
                                    ToggleFlashlight, DropGlowstick, Jumpscare,
                                    DevControl, DevTuning. Per-level ones sit in
                                    `Level 2 Remotes/` (Level 2 Alert Event,
                                    Level 2 Sound Event), `Level 2 Pool Foam
                                    Remotes/` and `Level 3 Remotes/`
ReplicatedStorage/UIDevice          form factor + safe-area layout for the HUD
                                    (`Safe`, `ModalViewport`, `TopRightPanel`)
ReplicatedStorage/UIRegression      the HUD regression matrix (see Testing)
RobloxReplicatedStorage/            four Roblox-engine-owned LocalizationService
                                    remotes, mirrored as a record only
assets/                             source assets: textures · sounds · models ·
                                    banners · animations (FBX + keyframes) · blender
tools/                              Studio/Blender MCP pipeline (see below), plus
                                    `discord_trello_bot/` — the #bugs/#feedback
                                    forum-to-Trello bot (own README)
artifacts/                          captured screenshots from automated playtests
docs/                               audits and one-off design docs: the dated
                                    AUDIT-*.md files, Level 3 pathfinding notes,
                                    Zyntra monetization setup
plugin/                             Studio dock plugin
                                    (`MasterTuningPlugin.server.lua`) +
                                    `build_plugin.py` installer; intentionally
                                    outside the mirror/manifest
```

At the repo root, `CLAUDE.md` is the working brief for anyone (or anything)
editing this place — the sync rules, the current state and the house rules live
there, not here. The dated `HANDOVER-*.md` files are per-session records of what
shipped and how it was verified.

Level 1's five runtime scripts were gathered into `Level 1 Systems` on
2026-09-02 so all three levels read the same way. Anything looking them up by
name must use a RECURSIVE `FindFirstChild(name, true)`: the non-recursive form
returns nil from a folder and every one of those call sites fails silently on
nil, which is how a Level 2/3 round once came to start Level 1's fuse puzzle
server-side. `NoiseRegistry` deliberately stayed in the root as a shared
service, so the moved scripts reach it through `ServerScriptService`, never
`script.Parent`.

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

  **A script that does not exist in Studio yet cannot be pushed by these tools.**
  Create it in Studio first (`execute_luau` + `UpdateSourceAsync`), then add its
  manifest item with `sha256_of` / `canonical_bytes` from
  `tools/studio_source_contract.py`.

  While a push is queued, `pull_source_from_studio.py` **skips** those files
  (their repo copies are newer than Studio); pass `--force` to discard the
  unpushed edits instead. (`push_level1_to_studio.py` and
  `push_level2_poolrooms_to_studio.py` predated this path and were removed on
  2026-09-02; they are still in git history if the old behaviour is ever
  wanted.)
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
  World Builder is far past; `UpdateSourceAsync` does not.

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
- **Compile check.** `tools/studio_compile_probe.luau` compiles every script in
  the place without running any of them, by wrapping each source as
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
content and are written to fail rather than pass quietly. Four exist:
`Round Completion Test Suite`, `Level 3 Test Suite`, `Level 2 Exit Transition
Test Suite` and `UIRegression`. **No hostile has one** — Level 1's entity never
did, and Level 2's only hostile suite went into the archive with the Slidemouth.

**Last measured — 2026-09-04**, after that day's ten-change batch and before the
2026-09-05 batch. These are the numbers to re-measure, not to trust:

| Check | Result | Outcome |
|---|---|---|
| `tools/studio_compile_probe.luau` over the whole place | every script compiled | **PASS** |
| `Round Completion Test Suite.RunAll()` | 398 checks, 0 failed | **PASS** |
| `Level 3 Test Suite.ValidateConfiguration()` | passes with the new occupancy and table-check asserts | **PASS** |
| `UIRegression.RunAll()` | 22 scenarios; 23 failures, all pre-existing | **KNOWN FAILURES** |
| Level 2 play: chase, wipe window, pumps, win path | see `HANDOVER-2026-09-04.md` for the per-check record | **PASS** |
| Level 3 play: hiding and table check | as above | **PASS** |
| `tools/tests/test_push_repo_to_studio.py` end-to-end round-trips | not executed — no `luau` binary on this machine | **NOT RUN** |

The 23 UIRegression failures are two known rows, both older than that batch: 22
in the Zyntra terminal's DEV tab, where `ZyntraStore` stands a level-gated row
down with the caption `"LEVEL <n> ONLY"` and the harness's list of recognised
stand-down captions does not contain that string, so it counts the row as
neither reachable nor stood down; and the `objectives-panel` row, which reports
`RoundGui.QueueHostPanel.CreateParty` as a tappable rect while its parent
`QueueHostShade` is hidden. Both were the harness, not gameplay, and both were
fixed in the 2026-09-05 batch: `Fit.ZyntraDisabledCaptions` now carries the
`"LEVEL %d+ ONLY"` family (and `"WAITING"`), and the `objectives-panel` scenario
declares `Forbids = {"QueueHostPanel"}`. **Re-measure rather than trusting the
23** — the number above predates both fixes.

**Historical, for the 2026-08-30 release (v1641):** the Slidemouth suite passed
391/0 at authored scale, `Round Completion` 397/0, the UI suite 200/0 and the
touch-target matrix 262/0; Level 2's exit sensors passed a 105-stud/s
authoritative crossing and a 75-second recycle ride; the Level 3
navigation/furniture regression was green; and the place compiled and matched
the mirror before and after the repository-history integration. Those runs
describe a place that has since changed substantially — the Slidemouth suite in
particular no longer exists outside the archive.

| Suite | Where | What it covers |
|---|---|---|
| `Round Completion Test Suite` | `ServerScriptService` | Seven groups, including **Cohort timing, claim anchors and synchronous failures**: a source party and its destination driven over ONE fake clock so a silent continuer's bounded retry is proved to land before the destination admits; a claim that never reaches a dispatch reaching finite settlement; repeated and concurrent `ForceSettle` proved idempotent; and synchronous dispatch rejections proved to enter the same retry/fallback/surrender policy a `TeleportInitFailed` callback does. Plus the post-win routing rules and the frozen roster; proof that the **running GameManager** loaded, uses the routing module and keeps no completion or transfer state of its own; the source→destination admission handshake replayed with the production `PlayerRemoving` step (early continuer departs mid-window, later manual Continue, timeout continuer, quitters, Back users, duplicate packets, bootstrap); the attempt-correlated failure path with real `TeleportOptions` (duplicate report, stale report after fallback, stale options never retried); and the completed-world teardown rule |
| `UIRegression` | `ReplicatedStorage` | **`ZyntraTerminalFitMatrix()`** — the Zyntra Equipment/Research terminal opened through its OWN production toggle at ten device sizes, every tab including DEV selected through the production `selectTab`: the terminal inside `UIDevice.ModalViewport` (the true safe area, not the HUD band it used to be sized from and collapse in), header/tabs/content/status all positive, non-overlapping and inside the panel, a usable page height, every tab reachable (the bar scrolls when they do not fit) and in its authored order, every card and dev row contained horizontally with a scroll for the overflow, every touch action ≥ 44 × 44, no keyboard glyph, and the opener plus every movement control — the game's cluster AND the engine's own thumbstick — proved to have stood down while the modal is up. The shell is resolved analytically behind the usual calibration gate; grid- and list-laid-out internals are measured live and compared only against other live rectangles. **`ObjectiveCornerMatrix()`** — Level 1, Level 2 and Level 3's objective readouts forced into every state at the same ten sizes, asserting the upper-right anchor itself (top of the true safe area; right-aligned to the screen's safe edge or to the control column, whichever is the highest movement-safe edge for that height), no movement-zone entry, the Level 2 alert reflowing beside it or mutually excluding it, and the Level 3 contract in full: no separate CLOSE control exists, the panel is the control on touch and inert on desktop, the hidden state exposes only a wordless ≥ 44 × 44 restore chip at the same anchor, and restoring brings the panel back. **`DispatchCompactMatrix()`** — the phone briefing's maximum footprint: 560 × 100 absolutely on a 956 × 440 iPhone 16 Pro Max, and elsewhere bounded by the compact target the layout publishes plus the rung it reports climbing, never a quarter of the height, never a fifth of the screen, with both readouts ≥ 44 × 44 and the longest authored cue still fitting its box. Plus `BriefingExclusionMatrix()` — the dispatch briefing, the queue host modal and the Zyntra store opener, which all own the same strip of screen: a seven-state machine driven in BOTH orders (a modal raised over a live briefing, and a briefing raised under a modal already up) at two viewports, asserting the two published flags, the pixels they are derived from, that the opener leaves the INPUT STACK and not merely the screen, that the transmission itself is never torn down by suppressing its panel, and that no rect anywhere under the briefing panel overlaps any rect anywhere under the modal. Plus the developer page's captions against `UIDevice.SuppressesKeyboardGlyphs()` in both modes and back again, so a caption cannot be decided once at build time; `QueueModalMatrix()` — the lobby queue panel resolved arithmetically across thirteen device sizes, behind a calibration gate that first proves the resolver reproduces the engine at the real viewport; `BriefingFitMatrix()` — the dispatch briefing panel measured with `TextService:GetTextBoundsAsync` on portrait and small-landscape phones, proving the longest authored cue neither clips its box nor overlaps the MUTE/STOP row that abuts it; the HUD scenario matrix (including the lobby queue panel's five controls), the completion overlay's actions and routing, a viewport fit matrix across desktop, tablet and phone in both orientations, and `TouchTargetMatrix()` — a tap-size, interactivity and keyboard-glyph sweep across six phone and tablet sizes **including the Galaxy A06's 705×338**, plus a geometry pass at the real viewport with the touch layout applied. The two halves are split on purpose: under the viewport override Studio still renders at its real window size, so position-based assertions only mean something in the real-viewport pass. Four more lanes run from `RunAll` alongside those: `SafeAreaMatrix()`, `ControlZoneMatrix()` (last, because it is the only lane that parents an instance into the live HUD at the real viewport), `ExclusionTimingMatrix()` and `HarnessLockMatrix()` — the last two go last of all, since they stand the run's own harness lock aside to test it and put it back |
| `Level 3 Test Suite` | `ServerScriptService."Level 3 Systems"` | Assert-based, no `RunAll` — call the entry point you want. Static, needing no world: `ValidateConfiguration()` (config values, saved sound prototypes with their muffle effects, vetted furniture templates carrying no scripts), `ValidateGeneratedLayouts()` and `ValidateNavigationLayouts()` across the generator's own seed list. Against a built world: `ValidateWorld(manifest)`, `ValidateMallManagerRuntime()`, `ValidateRuntime(progress)` and `ValidateCleanup(snapshot)`. `RunNavigationRegression(context)` needs more than a world — it asserts a live context table (`DisposableSession = true`, an idempotent `Cleanup` callback, `Manager`, a `Player` with a character, `PatrolRoomId`, `MusicController`, `World`) and throws on its first statement without one, so it cannot be called bare. Plus targeted probes the Mall Manager's movement was written against — `ProbeSlowMovementProgress`, `ProbeBlockedProjection`, `ProbeWallHugAttack`, `ProbeChaseForwardProgress`, `ProbeMovingTargetProgressIsolation` — and `ProbeSharedTableHiding()` (needs three players to prove the cap refuses a third) and `ProbeFurniturePermanence()` |
| `Level 2 Exit Transition Test Suite` | `ServerScriptService."Level 2 Systems"` | The only automated coverage Level 2 has. Geometry against a real manifest: `ValidateCompletionSensors`, `ValidateTransitionGeometry` (every floor from the completion sensor on stays steep enough to keep a one-way rider sliding, overlaps its neighbour so there is no hole, and carries the one-way flag), `ValidateRecycleGeometry`, `ValidateRecoveryChamber`, `ValidateExitGeometry`, `ValidateLevelThreeResume`. Plus live probes needing a player: `ProbeHighSpeedCompletion`, `ProbeTransitionRideDuration`, `ProbeLevelThreeSlideOut`. **It does not touch Pool Foam** |

The three matrices added on 2026-08-30 (`ObjectiveCornerMatrix`,
`DispatchCompactMatrix`, `ZyntraTerminalFitMatrix`) run from `RunAll` like the
rest — they own the `UIRegressionViewport` / `ForceTouchUI` /
`UIRegressionSafeInsets` overrides themselves and restore all three on every
exit path, error included, and each asserts that it did.

### Running them

**Server**, from a Play session's Server context. The two level suites assert
their way through and throw on the first failure, so "it returned" is the pass
signal; `Round Completion` returns a report string and a failure count instead.
Note that a `require` issued from `execute_luau` gets its **own module
instance** — the adapter you build here is not the one GameManager is running,
so read state back from attributes and instances, never from module locals.

```lua
-- Shared post-win routing. Pure: no world, no players needed.
print((require(game.ServerScriptService["Round Completion Test Suite"]).RunAll()))

-- Level 2: build a world, then check the exit geometry against its manifest.
local L2 = require(game.ServerScriptService["Level 2 Systems"]["Level 2 Round Adapter"])
local Exit = require(game.ServerScriptService["Level 2 Systems"]["Level 2 Exit Transition Test Suite"])
L2.Build()
local manifest = L2.GetManifest()
for _, check in ipairs({"ValidateCompletionSensors", "ValidateTransitionGeometry",
        "ValidateRecycleGeometry", "ValidateRecoveryChamber", "ValidateExitGeometry"}) do
    Exit[check](manifest)
end
print("Level 2 exit geometry passed")
L2.Cleanup()

-- Level 3: configuration and layout checks need no world.
local L3 = require(game.ServerScriptService["Level 3 Systems"]["Level 3 Test Suite"])
L3.ValidateConfiguration()      -- config, saved prototypes, vetted furniture
L3.ValidateGeneratedLayouts()   -- the layout generator across its seed list
L3.ValidateNavigationLayouts()
print("Level 3 static checks passed")

-- Level 3 with a world: build first, then the world pass. Cleanup runs even
-- when a check throws, so a failed run does not strand a generated mall.
local L3Adapter = require(game.ServerScriptService["Level 3 Systems"]["Level 3 Round Adapter"])
L3Adapter.Build()
local ok, err = pcall(function()
    L3.ValidateWorld(L3Adapter.GetManifest())
    -- RunNavigationRegression is NOT callable from here: it asserts on a live
    -- context table {DisposableSession=true, Cleanup, Manager, Player,
    -- PatrolRoomId, MusicController, World} and throws on its first statement
    -- without one. See the suite's own header for how to assemble it.
end)
L3Adapter.Cleanup()   -- always, or the generated world is stranded in the session
assert(ok, err)
print("Level 3 world checks passed")
```

**Client**, from a Play session's Client context. `RunAllSummary()` is the one
call to make from `execute_luau`: it is the same run as `RunAll()` with the
passing lines dropped, bounded so it fits back through the MCP boundary, and it
reports whether the harness lock was left clean.

```lua
print((require(game.ReplicatedStorage.UIRegression).RunAllSummary()))

-- One lane at a time, compactly, when a summary points at one:
print((require(game.ReplicatedStorage.UIRegression).Compact("ZyntraTerminalFitMatrix")))
```

**The whole place, without running any of it:** `tools/studio_compile_probe.luau`
compiles every script by wrapping each source as `return function() ... end` and
`require`ing the wrapper. Run it after any RoundUI edit — that file sits exactly
at Luau's 200-local-register limit in its main chunk.

**The mirror:** `python tools/pull_source_from_studio.py --audit` must report 0
drift with every manifest entry `synced` before a session ends, and
`tools/studio_parity_probe.luau` + `python tools/verify_studio_parity.py <dump>`
prove it again from a fresh fingerprint rather than from the manifest.

A multi-seed sweep of a level suite runs for many minutes and `execute_luau`
gives up long before that, so drive it off the caller with a **finite** deadline
and poll the result — never a bare loop, which can wedge the editor:

```lua
_G.Sweep = {Status = "running", Lines = {}}
task.spawn(function()
    -- BEWARE: os.clock() here is PROCESSOR time, not wall time. A four-seed
    -- sweep once finished reporting 343 "seconds" after roughly 25 minutes on
    -- the clock, so a budget expressed this way is far looser than it reads. It
    -- is a runaway backstop, not a schedule. The REAL bound is the fixed list of
    -- seeds: the loop is finite whatever the timer does, which is the property
    -- that matters. Never write the timer as the only thing stopping a loop.
    local deadline = os.clock() + 900
    for _, seed in ipairs({101, 202, 303, 404}) do
        if os.clock() > deadline then break end
        -- ... set Level2Seed, build, run, append to _G.Sweep.Lines ...
    end
    workspace:SetAttribute("Level2Seed", nil)
    _G.Sweep.Status = "done"
end)
```

Poll `_G.Sweep` from a second `execute_luau` call. Expect **20–30 minutes of
wall time** for four seeds; each one is a full world build plus the checks.

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
| `UIRegressionSafeInsets` | workspace | `Rect(left, top, right, bottom)`; UIDevice reports that device safe area instead of its modelled one. Studio on a PC measures no sensor housing, so without this no matrix could prove the layout honours one — the iPhone rows set `(59, 0, 59, 21)` landscape and `(0, 0, 0, 34)` portrait |
| `UIRegressionForceLevel3Reader` / `UIRegressionForceReaderHidden` | player | forces the Level 3 exit reader active, and forces its hidden/visible state, so both halves of the tap-to-hide contract can be driven |

`ZyntraStore` also publishes a Studio-only `BindableFunction`
(`UIRegressionZyntraStoreProbe`) that drives the terminal through its **own**
production entry points — `open`, `close`, `kiosk`, `tabs`, `tab:<name>` and
`relayout` all call `toggleMain` / `openKioskShop` / `selectTab` /
`applyTerminalLayout` rather than re-implementing them, so a matrix cannot pass
against a reimplementation of tab switching that the player never runs.

**A module local is not observable from a matrix.** Studio's `execute_luau`
— which is what drives every device sweep here — runs in a **separate `require`
cache** from the running LocalScripts: a module required from there is a
different table with its own upvalues. Proved directly, by replacing
`UIDevice.Layout` on the harness-side table and invoking the store's own
relayout probe, which called the patched function zero times. Anything a matrix
must assert therefore has to live in shared state (an attribute or an instance
property), which is why `UIDevice.SuppressTouchMovement` publishes
`TouchMovementSuppressed` on the player rather than keeping a boolean.

`UIRegressionSuppressDispatch` was added because clearing the force flag does
**not** reach an idle screen: a Studio session comes up with the first-login
lobby briefing already running, held on screen by `hasSubtitle` even once
`hasActiveTransmission()` answers false, and it is drawn from a file-local table
with no outside handle. Without it the exclusion matrix was asserting against a
briefing it could neither see nor stop, and reported 18 failures that were its
own. It suppresses; it never fabricates — the force flag still wins over it, and
the matrix asserts it reached idle both before and after the sweep.

## 🧪 Testing vs production values

Everything is currently at **production** values. Override locally in Studio for
quick tests (don't sync the overrides). All three read through
`MasterConfiguration`, so the tuning panel can move them without an edit:

| Script | Setting | Testing | Production |
|---|---|---|---|
| `Level 1 Systems`/MazeGenerator | `GRID` (`L1_Grid`) | `10` | `40` — the maze is GRID × GRID cells |
| GameManager | `ELEVATOR_TIME` (`Lobby_ElevatorSeconds`) | `2` | `19` (matches the elevator sound) |
| GameManager | `QUEUE_TIME` (`Lobby_QueueSeconds`) | — | `10` — the lobby countdown once a party fills |

`FAST_QUEUE_TIME` (3 s) is not a testing override: it is what the `B` dev cheat
switches the countdown to, and it is whitelist-gated.

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
immunity · `U` unlimited battery/stamina · `C` third person. `J` opens the
Zyntra developer phone (`ZyntraStore.LocalScript`, same gate). These controls
are restricted by immutable UserId and revalidated server-side; they are not
general-player controls.

`M` (mute/unmute the active dispatch) and `N` / gamepad `B` (stop the current
briefing) are **not** dev cheats: `RoundUI` binds them for everyone, and only
while a transmission is actually playing. `N`'s handler passes `ButtonB` through
untouched while `Level3_Hiding` is set, so the advertised table-exit control
still works.

The Master Tuning panel (`MasterTuningClient.LocalScript`, same whitelist)
opens with `F4`.

The developer page's captions follow `UIDevice.SuppressesKeyboardGlyphs()`, not
`IsTouch()`, and are re-rendered on `UIDevice.Changed`. The difference matters
for a handheld that reports a keyboard — a tablet in a case, a hybrid: it is
`IsTouch() == false` but suppresses glyphs, and was being told to press keys it
has not got. With glyphs suppressed the intro drops its `//  PHONE: J`, every
toggle drops its `//  <key>`, and the noclip row changes from "WASD, Space and
Left Ctrl" to "using the movement stick".

### Developer tuning

`ReplicatedStorage.MasterConfiguration` is a registry of developer-tunable
values (level sizes, entity timings, and more): each entry names a config
module's field, its allowed range, and whether a change is live or needs the
next round build, without holding the value itself. Overrides live as
`ReplicatedStorage.MasterTuning` attributes, refreshed against
`MasterTuning.Defaults` every round build. Whitelisted developers open the
in-game panel with `F4` (`MasterTuningClient.LocalScript`), which sends every
change over the `DevTuning` remote so the server re-checks `DevAccess` and
re-clamps against the registry's range.

## 🚀 Before the next publish

The 2026-08-30 gates were all met for v1641 — the place published, the exact
live title and description saved and verified, the history integrated and `main`
pushed. What that checklist cannot do is carry forward: the place has changed on
most days since. Re-run these before the next publish rather than reading the
old ticks:

- [ ] `tools/studio_compile_probe.luau` over the whole place
- [ ] `pull_source_from_studio.py --audit` reports 0 drift, every entry `synced`
- [ ] `tools/studio_parity_probe.luau` + `verify_studio_parity.py` agree
      independently of the manifest
- [ ] `Round Completion Test Suite.RunAll()` in a Play session
- [ ] `UIRegression.RunAllSummary()` in a Play session, with the two known
      harness rows either fixed or explicitly accepted
- [ ] `Level 3 Test Suite.ValidateConfiguration()` and the layout checks
- [ ] `Level 2 Exit Transition Test Suite` against a freshly built world
- [ ] A multi-seed Level 2 playtest — one seed proves very little here
- [ ] `Level2Seed` and `Level3Seed` cleared (or 0) so no server ships pinned

**There is no Level 4**; Level 3 intentionally offers only the route back to the
lobby. Its systems — generated layout, Mall Manager, hiding, music/blackout
cycle, persistent furniture and reader UI — are in, and the level remains open to
content work.

`ROBLOX_GAME_DESCRIPTION.md` is the canonical spoiler-free Creator Dashboard
copy. `assets/marketing/roblox-experience-description.txt` mirrors it byte for
byte; the `.md` beside it documents that relationship.

### Known verification limits

- **Level 2's hostile has no automated coverage at all.** Pool Foam's look-latch,
  phase gating, hearing and lethal contact are proved only by playing the level.
  The one encounter this project built without a suite failed silently in every
  round for days.
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
- Some optional Level 1/Level 3 audio-polish slots remain content work, and
  **every Pool Foam audio slot is empty** — the encounter is deliberately correct
  without media, but it is currently silent. Level 2 wet footsteps and their
  resistance layer are implemented, and dry-tile footsteps have a bundled
  fallback when no custom asset is configured.
- **Gamepad bindings are code-reviewed only** (no controller on the machine), as
  is Level 1's per-escape announcement with a second player. `ProbeSharedTableHiding`
  needs three players to prove the Level 3 table cap refuses a third.
- **The Emergency Re-entry product exists but is not on sale.** The owner has to
  switch it on in the Creator Dashboard, and the four badge ids in
  `ReplicatedStorage.ZyntraConfig.Badges` are still 0, which means disabled —
  `AwardBadge` returns false for a disabled id rather than throwing, so read the
  return value, never `pcall`'s ok alone.
