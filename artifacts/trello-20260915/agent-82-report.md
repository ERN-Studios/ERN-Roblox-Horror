# Agent A82 — Trello #82: Level 1 instructions, team prompts and cable current

Phase 1 (offline) complete. No Studio tools were used, no git operations were run,
nothing outside the files listed below was touched.

---

## 1. What the owner asked for, and where each part landed

| Owner's requirement | Where it is implemented |
|---|---|
| Team-wide prompts naming WHO picked up a fuse / powered a box / pulled a lever | `PuzzleManager.announceTeam` + three call sites; rendered by `PuzzleUI.teamPrompt` |
| …explaining WHAT changed, with remaining counts | Prompt detail carries the running count (`POWERED A BOX 2/3`, `PULLED LEVER 1/3`); the persistent `RESTORE FUSE BOXES n / m` row keeps it on screen |
| …and the NEXT concrete action | `PuzzleUI.refreshNextStep` — the carry row is now a standing instruction line for the whole round |
| Current flows along the cables TOWARD the fuse box before power | New `Level 1 Cable Current` LocalScript, unpowered path = elevator witness point → fuse box |
| …REVERSES toward the lever once powered | Server sets `Powered` on the circuit model; the client switches to the reversed box half concatenated with the lever half |
| …with a prompt to follow the current and pull the lever | The `levers` event puts `FOLLOW THE CURRENT TO A LEVER` in the persistent next-step row |
| Fit the existing UI design | Reuses the existing transient message surface and the existing carry row. **No new HUD rows, no new rectangles, no layout code touched** |
| Respect `ReduceFlashing` | The current never blinks at any setting; `ReduceFlashing` halves the speed and drops to one pulse per circuit |
| Server-authoritative state, validated interactions | Every prompt fires from inside the handler that already passed `canUsePrompt` and already mutated the state |
| Preserve ordinary puzzle flow | No rule, count or timing changed. Every pre-existing `PuzzleStatus` event and consumer is intact |
| Spectator privacy | Prompts go only to players with `InRound == true`, the same filter `fireEscapeStatus` already uses |
| Desktop/touch verification matters | Copy is budgeted to the desktop strip; touch wraps and is measured by the existing walk. Device QA is phase 2 |

---

## 2. Design decisions (and what was deliberately not built)

### The prompt is split between a transient line and a standing line

The owner's example was one long sentence: *"MIKKELCZAR POWERED A FUSE BOX // 2 BOXES
REMAIN"* then *"FOLLOW THE CURRENT TO THE LEVER AND PULL IT"*. On desktop the transient
message is a **fixed, unwrapped 300px strip at 15px Code** (`PuzzleUI` line ~1280) — about
33 characters — and its rectangle is asserted by `UIRegression`'s Level 1 fit matrix
(`outside(message, panel)` on desktop, "last row of the stack" on touch), and by the
stacked-desktop detector clearance, which is computed from `LAYOUT.MessageHeight`.
Growing that rectangle would have put three separate shipped contracts in play.

So the information is split the way the two surfaces already work:

- **transient** (`showMessage`) — who did what, with the count: `MIKKELCZAR POWERED A BOX 2/3`
- **standing** (the carry row) — the next concrete action, on screen for the whole round

That is strictly more visible than a three-second toast carrying the instruction, and it
is why no new row was added.

### The next-step row replaces the carry row rather than joining it

`FUSES CARRIED   0` was the one line on screen for the whole round that never said what
to do. It now reads:

| State | Copy | chars |
|---|---|---|
| fuse phase, carrying none | `FUSES CARRIED   0  •  FIND A FUSE` | 33 |
| fuse phase, carrying n | `FUSES CARRIED   1  •  FILL A FUSE BOX` | 37 |
| lever phase | `FOLLOW THE CURRENT TO A LEVER` | 29 |
| exit open | `REACH THE LIT EXIT DOOR` | 23 |

37 characters is exactly the width the shipped lever row already proves fits
(`SYNC LEVERS   0 / 3  •  NO TIME LIMIT`), so no column has to grow and the fit matrix
sees a row it has already measured at that length. Carried fuses stop being useful once
every box is full, which is why the row is taken over rather than extended.

### The current is a moving bead, not an animated cable

A full maze lays **several hundred** `ObjectiveCable` parts per circuit. A travelling
colour band would be a property write per segment in the band per frame plus a restore,
for a visual that a moving point renders exactly. One small Neon ball per pulse gives:

- **≤ 12 Parts total** (2 pulses × 6 circuits, the six-colour palette cap)
- **≤ 12 `Position` writes per frame**, *independent of how many cable segments exist*
- **≤ 6 writes per frame under `ReduceFlashing`**
- path rebuild: one `table.sort` per branch per circuit, rate-limited to one rebuild per
  0.4 s and driven only by `DescendantAdded`, so it stops entirely when the build ends
- one `Heartbeat` connection for the whole feature; no tweens, no per-segment loops

I could not measure frame time offline — that is a phase 2 number. What is provable
offline is the invariant above: the per-frame cost does not scale with the cable.

### Why the server had to change to make the client possible

The cable was already laid as two halves from one shared elevator witness point
(`layWire(witnessCF, box.cf, …)` and `layWire(witnessCF, lever.cf, …)`), but nothing
recorded the order a route is travelled, and the pieces were **not emitted in that order**:
`layWire`/`layWireDirect` laid the routed runs before the source connector, and
`layPiece`'s detour emitted its main run before its two joiners. Three small reorderings
fix that — **no geometry moved**, only the order parts are created in — and each part now
carries `SegmentIndex`. Risers additionally carry `Vertical`, because the shortest bevel
joiners and the shortest risers are close enough in `Size` to be told apart wrongly.

---

## 3. Files changed

### `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua`

| Change | Why |
|---|---|
| new `announceTeam(actorName, kind, detail)` near `fireEscapeStatus` | one place that fires the team event, to `InRound` players only |
| fuse pickup (`makeDroppedFuses`) — private `msg` replaced by `announceTeam(..., "fuse", "TOOK A FUSE" / "TOOK n FUSES")` | one prompt per action; the picker still sees their count on the carry row |
| fuse extraction (`finishFuseExtraction`) — private `msg` replaced by the same announce | same |
| fuse box handler — `announceTeam(..., "box", "POWERED A BOX d/d")` in the complete branch, `"FED A BOX d/d"` in the partial branch | the partial branch is unreachable while `FUSES_PER_BOX = 1`; it is one line and stops a partial deposit being the only silent action |
| fuse box handler — `session.circuits[boxIndex]:SetAttribute("Powered", true)` | the one authoritative fact the client current reads |
| lever handler — `wasOn` captured before the pull; `announceTeam(..., "lever", "PULLED LEVER d/d")` only on an OFF → ON transition | re-triggering a lever inside its own window is legal but changes nothing; without this, holding E is a stream of identical prompts for the whole party |
| cable pass — `currentSegmentIndex`, `SegmentIndex` on every piece, `Vertical` on risers, `BoxBranchEnd` and `SegmentCount` on the circuit model | lets a client walk a circuit end to end |
| cable pass — source connector emitted before the routed runs in `layWire` and `layWireDirect`; `layPiece`'s detour emitted a → mainA → mainB → b | makes `SegmentIndex` the order the route is travelled. Geometry unchanged |

### `StarterPlayer/StarterPlayerScripts/PuzzleUI.LocalScript.lua`

| Change | Why |
|---|---|
| new `carriedFuses` / `exitOpen` state and `refreshNextStep()` | the standing instruction line |
| new `TEAM_NAME_MAX` / `TEAM_COLOURS` / `teamPrompt()` | assembles the sentence client-side (it is the side that knows the column width), cuts the name to 12 characters, coalesces bursts, colours by kind |
| `"begin"` — resets the new state and calls `refreshNextStep()` | |
| `"carry"` — stores the count and calls `refreshNextStep()` | |
| `"msg"` — restores the surface's own colour first | a team prompt may have left it green or blue |
| `"team"` — new branch → `teamPrompt(a, b, c)` | |
| `"levers"` / `"exit"` — call `refreshNextStep()` | |
| `RoundActive` off — resets the new state | |

No layout function, no `LAYOUT` constant, no row set and no rectangle was touched.

### `StarterPlayer/StarterPlayerScripts/Level 1 Cable Current.LocalScript.lua` — NEW

`MazeGenerator` was **not** changed: the cabin `CableGuidePoster` already says
`FUSE BOX + LEVER AT OPPOSITE ENDS` / `EACH COLOUR LINKS ONE FUSE BOX + ONE LEVER`,
which is consistent with the new guidance. `Level 1 Sound Controller` was read and not
changed — no cue was essential.

---

## 4. What the lead must create in Studio

One new instance, before the push:

```
StarterPlayer
 └─ StarterPlayerScripts
     └─ "Level 1 Cable Current"      class: LocalScript
```

Source: `StarterPlayer/StarterPlayerScripts/Level 1 Cable Current.LocalScript.lua`.

Per CLAUDE.md, new scripts cannot be pushed by the tools: create it in Studio via
`execute_luau` + `ScriptEditorService:UpdateSourceAsync`, then add the manifest item with
`sha256_of` / `canonical_bytes` from `tools/studio_source_contract.py`.

`PuzzleManager` and `PuzzleUI` are existing mirror entries and push normally.

---

## 5. Tests and results

Run with `LUAU_BIN=C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe`.

### New

| Test | Result |
|---|---|
| `tools/tests/test_level1_team_prompts.py` | **PASS** — server ok (21 checks), client ok (21 checks) |
| `tools/tests/test_level1_cable_current.py` | **PASS** — cable current ok (21 checks) |

Both run the **real** source, sliced out by string markers and given a stubbed engine —
`announceTeam` and the three `Triggered` handlers verbatim, `teamPrompt` /
`refreshNextStep` / the whole `PuzzleStatus` handler verbatim, and the entire new
LocalScript executed with a hand-driven Heartbeat.

What they assert:

- one team event per validated action, to each in-round player and **not** to the lobby player
- **no** event when `canUsePrompt` refuses
- the running counts in the payload (`POWERED A BOX 1/3`, `PULLED LEVER 2/3`)
- a no-fuse deposit stays a private `msg`, never a team prompt
- the last box announces **before** the lever phase opens
- re-triggering a lever inside its own window announces nothing
- the pair circuit and only the pair circuit is marked `Powered`
- the rendered line, the 12-character name cut, the per-kind colour, and that it fits 33 characters
- a burst of three within 0.7 s renders `…`, `…  +1`, `…  +2`, and a 1 s gap resets it
- a lobby player renders nothing; a spectator (`InRound` still true, `Spectating` set) renders the same line its party got
- the cable route is built from `SegmentIndex`/`Vertical`/`BoxBranchEnd` even when `GetChildren` returns the parts scrambled, and a riser laid bottom-to-top is walked in the direction the route uses it
- unpowered the pulse moves **toward the box**; on `Powered` it restarts **at the box terminal** and runs back past the witness point and out to the lever
- after the beads exist, the only property the animation ever writes is `Position` — asserted over 40 frames, which is the machine-checkable form of "nothing blinks"
- `ReduceFlashing` → one pulse, 13 studs/s instead of 26, still only `Position` writes
- `SelectedLevel ~= 1`, `RoundActive` off or `InRound` off → nothing is built; round end destroys the holder and writes nothing further

### Existing suites re-run

| Test | Result |
|---|---|
| `test_studio_source_contract.py` | PASS |
| `test_spectate_parity.py` | PASS |
| `test_round_entry_client.py` | PASS |
| `test_controller_input.py` | PASS |
| `test_first_entry_guide.py` | PASS |
| `test_full_sync_contract.py` | FAIL — **pre-existing, and expected here.** The failing check is "every .lua in the mirrored services is listed in the manifest". Its unlisted set is `ReplicatedStorage/UIStyle.ModuleScript.lua`, `ServerScriptService/LobbyShopDisplay.ModuleScript.lua`, `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua` (three files from other agents, already unlisted before this work) plus my new `Level 1 Cable Current.LocalScript.lua`. It clears when the lead creates the scripts in Studio and adds the manifest items. |
| `test_push_repo_to_studio.py` | FAIL — **pre-existing and environmental**, unrelated to this card: "CANNOT EXECUTE — `luau.exe --version` exited 1: Unrecognized option '--version'". The fixture never ran. |

No `UIRegression` row was added, renamed or resized, so the Level 1 fit matrix has nothing
new to measure — but it is a Studio suite and is listed in the phase 2 steps below.

Luau compile check (`luau-compile --binary`) passes on all three changed/new scripts.

---

## 6. Phase 2 — exact Studio QA steps

### Start a Level 1 round

1. Studio → Play. In the **Server** datamodel:
   ```lua
   local p = game:GetService("Players"):GetPlayers()[1]
   p:SetAttribute("DevFastQueue", true)
   p.Character:PivotTo(CFrame.new(-72, 33.5, -853.2))   -- LaunchZone1
   ```
2. On the **client**:
   ```lua
   game:GetService("ReplicatedStorage").Remotes.ConfigureQueue:FireServer(<stationIndex>, 1, "public")
   ```
   (`<stationIndex>` = the station whose LaunchZone you pivoted to.)
3. Wait for the elevator ride to finish and the maze to appear.

### Desktop checks

1. **Standing instruction, from the first frame.** The objectives panel's second row must
   read `FUSES CARRIED   0  •  FIND A FUSE`. It must be there before anything is picked up.
2. **Cable current, unpowered.** Step out of the elevator and look at the coloured cables
   on the floor. A bead of the circuit's colour must travel **away from the elevator, toward
   the fuse box**, two per circuit, evenly spaced. Confirm every circuit has one and they do
   not all sit at the same point.
3. **Fuse pickup.** Trigger a `FuseRelay` (hold E; the prompt needs the camera frustum —
   point a Scriptable camera at it if it will not show). The transient line must read
   `<YOURNAME> TOOK A FUSE` in amber, the carry row must become
   `FUSES CARRIED   1  •  FILL A FUSE BOX`, and the line must clear after ~1.8 s.
4. **Fuse box.** Deposit at a `FuseBox_NN`. The transient line must read
   `<YOURNAME> POWERED A BOX 1/n` in green, `RESTORE FUSE BOXES 1 / n` must tick up, and —
   the key check — **that circuit's bead must jump to the fuse box and start running the
   other way**, back past the elevator and on toward that circuit's lever. The other
   circuits must keep running toward their own boxes.
5. **Lever phase.** With every box powered, the carry row must become
   `FOLLOW THE CURRENT TO A LEVER`, the title `EXIT CIRCUIT`, and every bead must now be
   running out to a lever.
6. **Lever pull.** The transient line must read `<YOURNAME> PULLED LEVER 1/n` in blue.
   **Hold E on the same lever again inside its 10 s window — no second prompt may appear.**
7. **Exit.** After the levers, the carry row must become `REACH THE LIT EXIT DOOR`.
8. **Two clients.** With a second player in the round, confirm both see the same line for
   one action, and that the actor's own client shows their own name (not "you").
9. **Lobby privacy.** With a third player left in the lobby, confirm they see nothing.
10. **Spectator.** Kill one participant (`humanoid.Health = 0`) and confirm the spectating
    client still receives the party's prompts.
11. **Burst.** Have two players power boxes within half a second and confirm the second
    line carries `  +1` rather than the first flashing away.
12. **`ReduceFlashing`.** Zyntra terminal → SETTINGS → Reduce Flashing on (or
    `player:SetAttribute("ReduceFlashing", true)` on the client). Within ~0.5 s each circuit
    must drop to a single, visibly slower bead. Nothing may blink at any point.
13. **Round end.** Let the round end and confirm the beads are gone
    (`workspace.CurrentCamera:FindFirstChild("Level1CableCurrent")` must be nil).
14. **Performance.** With MicroProfiler or `ScriptProfilerService`, record the client frame
    cost of `Level 1 Cable Current` on a six-circuit round. Expected: negligible
    (≤ 12 `Position` writes/frame), but this is the number I could not take offline.

### Touch / phone layout

Emulate a phone with Studio's Device Emulator (F5 → **Device** tab, pick e.g. *Galaxy A06*
or *iPhone SE*, portrait **and** landscape), then repeat steps 1, 3, 4, 5 and 6 and check:

- the objectives column moves to the **upper right**, the toggle sits **inside** the panel as
  a 44×44 square, and the transient message is the **last row of the panel**, below every
  objective row — no overlap with the movement thumbstick or the exit-energy detector
- `FUSES CARRIED   1  •  FILL A FUSE BOX` wraps inside the panel rather than outside it
  (this is the one measured-height path; it is the check most likely to find a problem)
- the prompt is still legible at the compact tier (11px)

Then run `UIRegression` and confirm the Level 1 rows still pass the fit matrix. Per
CLAUDE.md: **restart play before measuring** — configuring a queue over the remote instead
of the CreateParty button leaves the host panel open and fails that row.

Console/controller is out of scope for this card.

---

## 7. Limitations and known ceilings

1. **Desktop transient strip is one unwrapped line.** Budgeted at ~33 characters
   (300px / 15px Code). On a desktop viewport under roughly 506px wide the objectives
   column narrows to 220px and a full-length prompt can overhang to the left, into empty
   space. I did not widen the strip because its rectangle is asserted by `UIRegression` and
   is an input to the stacked-desktop detector clearance. Not measured in Studio.
2. **The name cut is a byte cut at 12.** A display name with non-ASCII characters could be
   cut mid-codepoint. Roblox display names are effectively ASCII in practice; the fix, if it
   ever matters, is `utf8.offset`.
3. **A cable that doubles back reuses a part.** `makeRawPiece` deduplicates identical edges
   within a circuit, so a route that retraces itself reuses the part with the *earlier*
   `SegmentIndex` and the bead can jump there. Rare, and it was already the geometry's
   behaviour — the current just makes it visible.
4. **Pit breaks are crossed in a straight line.** Where `laySeg` deliberately breaks the
   cable over a hole field, the bead crosses the gap. `layOverhead` (the wall-ceiling-wall
   route) is walked properly, so this only affects the subdivided path.
5. **A private `msg` recolours a live team prompt.** "You have no fuses" arriving while a
   team prompt is on screen replaces it and restores the amber. Lifetime 1.8 s; acceptable.
6. **`FED A BOX n/m` is unreachable** while `FUSES_PER_BOX = 1`. It is one line, kept so a
   partial deposit is not the only silent action if that constant ever changes.
7. **No audio cue was added.** `Level 1 Sound Controller` was read and left alone.
8. **Not verified:** anything that needs the engine — real pixel widths, the bead's
   legibility at maze light levels, actual frame cost, and two real clients agreeing. No
   human first-time test was run and no before/after analytics exist; nothing in this
   report claims otherwise.

---

## 8. Recorded only — first-objective clarity in Level 2 and Level 3

**No files were changed for this section.** Evidence from
`Level 2 Objective UI.LocalScript.lua`, `Level 2 Objective Controller.ModuleScript.lua`,
`Level 3 Objective Controller.ModuleScript.lua`, `Level 3 Reader Client.LocalScript.lua`.

### Level 2 — has a first objective, with two gaps

- **First string:** `ACTIVATE 3 STATIONS` — hard-coded initial value at
  `Level 2 Objective UI.LocalScript.lua:140`, re-derived identically by the live path at
  `:258` (`hint.Text = string.format("ACTIVATE %d STATIONS", goal)`). Under the title
  `> PUMP NETWORK` (`:109`, `:253`) and the meter `[□□□]  0/3` (`:125`, `:231`).
- **When:** immediately. `Level 2 Objective Controller.Start()` (`:496-537`) sets
  `Level2Pumps = 0` and `Level2PumpGoal = goal` synchronously with no wait; the client
  refreshes on those attribute signals and on `InRound`, plus an unconditional `refresh()`
  at script load (`:282-291`). **No gap** — it is there from the first frame the player is
  in the round, not only after the first pump.
- **Verb + target:** yes. `ACTIVATE` + `3 STATIONS`.
- **Deficiency 1 — jargon, unlinked.** Nothing says what a "station" is, where to find one,
  or that "stations" are the "PUMP NETWORK" named two lines above. The player must infer
  the link between the title and the instruction.
- **Deficiency 2 — progress is anonymous although the actor is known.** `fireStatus`
  (`:167-176`) takes no player. The pump-activation broadcast (`:641-649`) says
  `PUMP STATION %02d ONLINE` / `%d OF %d STATIONS RUNNING` and names nobody, even though
  the server already records `Level2_PumpActivatorUserId` at `:579` for an unrelated
  consumer. This is exactly the deficiency #82 fixes in Level 1, and the data is already
  there.
- **Deficiency 3 — the escalation is on the quietest element.** At `LETHAL_PUMP_COUNT`
  (`:70`) only the small hint line and a stroke colour change (`WATER NO LONGER SAFE`,
  `:249-250`); the title stays `> PUMP NETWORK` (`:246-247`), so the panel's most prominent
  element gives no cue that the water has just become lethal.

### Level 3 — effectively has no first objective

- **First string:** there is none that instructs. The Reader panel shows
  `> EXIT DOOR READER` (`Level 3 Reader Client.LocalScript.lua:79`, **written once and
  never reassigned**), `[□□□□□]  0/5` (`:89`, becoming `DISC RELAY [□□□□□]  0/5` at `:901`)
  and `SIGNAL // NO TRACE` → `SIGNAL // UNSTABLE` (`:135`, `:939-940`). None contains a verb.
- **The one explanatory string is dead code.** `PARTY MUSIC OVERRIDE REQUIRED` /
  `%d PARTY MIX CDS MUST REACH THE RELAY` / `CARRY YOUR CDS TO THE DISC PLAYER BESIDE THE
  FALSE WALL` live in `scheduleIntro` (`Level 3 Objective Controller.ModuleScript.lua:1252-1278`)
  which **is never called** — `Start()` does not call it and there is no other call site.
  The comment at `:1419-1421` shows this is knowingly orphaned, with narration left to
  `RoundUI` (outside the four files reviewed — so whether the spoken briefing actually
  covers it is an open question for the owner, not something these files can answer).
- **The first plain-language instruction a player can receive is
  `CARRY IT TO THE DISC PLAYER`** (`Level 3 Reader Client.LocalScript.lua:811`) — which
  fires only *after* they have already found a CD unaided.
- **Deficiency 1 — a count with no instruction.** `DISC RELAY [□□□□□]  0/5` (`:901`) never
  says what the five slots are or what fills them. Contrast Level 2, which pairs the same
  count with a verb.
- **Deficiency 2 — jargon assuming the mechanic is known.** `> EXIT DOOR READER`, fixed for
  the whole round, presumes the player knows there is a hidden exit door and that a
  "signal" instrument guides them to it.
- **Deficiency 3 — an initialised stage nobody consumes.** `Level3_Phase` is correctly
  published as `"SEARCH"` at round start (`:325`, via `:1418`) but the Reader Client never
  reads it, so it has no effect on what the player sees.
- **Deficiency 4 — one broadcast is anonymous although the name is in the payload.**
  `ModuleCollected` and `CDInserted` do name the player (`%s  //  FOUND %d/%d` at
  Reader Client `:809`; `%s INSERTED %d CD%s` at `:821-823`), but `CDDropped` carries
  `PlayerName` (Controller `:745`) and the toast never reads it, printing
  `A CARRIED CD WAS DROPPED` / `RECOVER IT AT THE PLAYER'S LAST POSITION` (`:827-828`).

**Summary for the owner:** Level 2's first objective is present, immediate and has a verb,
but is anonymous and unexplained. Level 3 has **no** first objective at all in these files —
the string that would have provided one is unreachable code, and the panel shows a count
and a piece of jargon. Level 3 is the one worth a card; Level 2's would be a smaller
copy-and-attribution pass reusing the actor id it already records. Neither was changed.
