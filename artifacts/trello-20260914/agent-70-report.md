# Card #70 — First-login guide to the Level 1 entrance

## What was written

| File | Status |
|---|---|
| `StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua` | new, 291 lines, LF, UTF-8 |
| `tools/tests/test_first_entry_guide.py` | new, offline Luau suite, 37 checks |

Nothing else was touched: no server script, no manifest entry, no Studio write,
no git. The lead creates the Studio instance (see *For Studio* below).

## Eligibility — why this needs no new persistence

The card's "only on their first login" is exactly the fact the profile already
stores for the Command Center welcome, so the guide reads it instead of adding
a field:

- `ZyntraProfileLoaded` (player attribute, set false at load start and true
  after `applyAttributes`, `ZyntraMonetization.Script.lua:1466` / `:1592`).
- `ZyntraLobbyBriefingPlayed` (player attribute, published from
  `data.Settings.LobbyBriefingPlayed`, `ZyntraMonetization.Script.lua:558`).
  A legacy profile is migrated to **true** at `:325-330` — only a genuinely new
  profile arrives false.

The latch:

```lua
if player:GetAttribute("ZyntraProfileLoaded") ~= true then return end   -- wait
latched = true                                                          -- once
if player:GetAttribute("ZyntraLobbyBriefingPlayed") == true
    or workspace:GetAttribute("ReservedRoundServer") == true
    or player:GetAttribute("InRound") == true then return end
```

Taken **once**, at load, and never re-read — the welcome flips the same flag
true a few seconds into that first session (and persists it through the claim
protocol), so a re-read would delete the guide from under a player mid-walk.
`applyAttributes` writes the briefing flag *before* `ZyntraProfileLoaded` goes
true, so the value is already correct at the moment the latch fires. If the
profile never loads, nothing happens at all: one idle attribute connection,
no instances, no warning.

Two small deviations from the brief, both deliberate:

- **`workspace.ServerLobby` is not part of the latch.** It is resolved fresh on
  every frame instead (`level1Room()`), because a client can reach profile-load
  before the lobby model has replicated — `LobbyMusicController` already guards
  against exactly that with a `workspace.ChildAdded` listener. Requiring it at
  latch time would have made a first-time player silently miss the guide on a
  slow join. The practical requirement is unchanged: no lobby, nothing drawn.
- **The Level 1 bay must also report `LevelEnabled == true`.** A closed bay is
  not somewhere to send anyone.

## Visual

One anchored, invisible, `CanCollide`/`CanQuery`/`CanTouch = false` Part named
`FirstEntryGuide` parented to `workspace` — client-only, since a LocalScript
made it. Everything else is its child, so teardown is one `Destroy()`.

- **Trail:** `PathfindingService:CreatePath{AgentRadius = 2, AgentHeight = 5,
  AgentCanJump = false}`, one Path object reused for the life of the guide.
  Waypoints become Attachments 0.35 studs above the floor, joined by Beams in
  Zyntra cyan `Color3.fromRGB(73, 245, 204)`, `Width0/1 = 0.5`,
  `LightEmission = 1`, `Transparency = 0.25`, `FaceCamera`. Attachments and
  beams are **pooled** — a recompute moves them and enables/disables the tail,
  it never rebuilds them.
- **No beam texture by default.** The brief's out was taken: an asset id that
  turns out to be unusable renders as a broken stripe, and this is the first
  thing a new player ever sees. Set a **`BeamTexture` string attribute on the
  script** in Studio to audition one; `TextureLength = 4` and `TextureSpeed = 2`
  then scroll from the player towards the pad. No animation otherwise.
- **Marker:** BillboardGui adorned to the current target pad, 7 studs up,
  `AlwaysOnTop`, `MaxDistance = 250`, sized in **offset pixels** (240 x 96) so
  it reads on a phone. "LEVEL 1 START HERE" in GothamBold cyan over a "▼" that
  bobs +/- 6 px at ~0.64 Hz. (U+25BC; the project already ships ■ □ → ↑ in UI
  strings, and `canonical_bytes` is UTF-8, so the glyph survives the sync.)
- **Target:** the nearest of `Level1QueueRoom`'s `LaunchZone1..4` by horizontal
  distance, re-picked every frame as the player moves. The name match is
  anchored (`^LaunchZone%d+$`) *and* scoped to the Level 1 bay — the other bays
  name their pads LaunchZone5..24.

## Cost

One `Heartbeat` connection. Per frame it reads the root, scans four pads, writes
the bob, and returns. A path compute is `task.spawn`ed at most every 0.75 s, and
only when the player has moved more than 3 studs since the last compute origin
**or** the last compute failed (a failure falls back to a straight
player→pad line and retries on the next tick rather than waiting for movement).
`computing` blocks overlap. No loops, no polling, no `RunService.RenderStepped`.

## End conditions (destroy everything, never return this session)

1. The root is inside any Level 1 pad's `QueueRadius` (horizontal; falls back to
   7.4 if the attribute is missing) — i.e. the player arrived.
2. `InRound` becomes true.
3. `RoundStatus` delivers `queuehost`, `queueconfigured`, `lobbycountdown` or
   `loadinggame`.
4. `script.Destroying`.

A lobby death/respawn does **not** end it: the character is read fresh each
frame, so losing the root just hides the beams and marker, and the new root
resumes them. `finished` is a one-way latch — after an end, a late path compute,
a late profile-load signal and every remaining event are all no-ops.

## Test

```
LUAU_BIN="C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe" \
  python tools/tests/test_first_entry_guide.py
```

```
First Entry Guide: 37 checks passed (entire actual script, offline Luau)
```

`luau-compile --binary` on the LocalScript: clean.

The suite runs the **real source** under a fake DataModel (the
`test_round_entry_client.py` pattern): lobby → `LevelQueueRooms` →
`Level1QueueRoom` with the real attributes and the four pads at
`(-63,30,-840) + (±9, 0.18, ±13.2)` with `QueueRadius = 7.41`, plus a Level 2
pad in its own bay as a decoy; a `PathfindingService` with a scripted waypoint
list and a switchable status; `Players.LocalPlayer` with the profile
attributes and a character; a RoundStatus RemoteEvent; Heartbeat and a fake
clock. It covers all eight required assertions plus: the deferred profile load
still starts the guide, the agent parameters, the nearest pad being LaunchZone2
from the spawn, the straight-line fallback and its retry, a throwing
`ComputeAsync`, pause-and-rebind across a respawn, `InRound`, an unrelated
round status *not* ending it, and `script.Destroying`.

## For Studio (lead)

1. Create `StarterPlayerScripts > First Entry Guide` as a **LocalScript** via
   `execute_luau` + `UpdateSourceAsync` (new scripts cannot be pushed by the
   tools), then add the manifest item with `sha256_of` / `canonical_bytes`.
2. Run the compile probe.
3. Simulate a fresh profile: in a play session set the local player's
   `ZyntraLobbyBriefingPlayed` to `false` *before* the script latches — easiest
   is a Studio session with no saved profile (`RunService:IsStudio()` already
   makes `loadProfile` non-persistent), otherwise clear
   `Settings.LobbyBriefingPlayed` in the session copy and rejoin.

What to look for:

- The trail appears within a second of spawn and follows the tunnel floor and
  the bay doorway (~x = -36, z = -840) — **not** straight through the tunnel
  wall. A straight line through the wall means `ComputeAsync` is failing; check
  the navmesh / that the lobby has replicated.
- The marker sits over the nearer of the two south pads and swaps to the other
  pad as you walk past the doorway.
- The Command Center welcome finishes mid-walk — the guide must **not**
  disappear when it does.
- Stepping onto a pad removes trail and marker instantly; leaving the pad does
  not bring them back.
- Rejoining as the same player shows nothing.
- No `FirstEntryGuide` part is left in workspace after any end condition.

Open, low-cost follow-up if the owner wants the "flowing arrow" look: put a
`BeamTexture` attribute on the script once an arrow/dash asset id is confirmed
usable in this universe.
