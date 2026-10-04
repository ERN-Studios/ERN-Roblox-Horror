# Agent A80 — Trello #80 "Fix the hide under the table avatar animation in level 3"

Model: Opus 5 (1M context). Studio: `5d01a8db-7930-419a-aa93-ddfdeee7b21d`, PlaceVersion 1894.
Date: 2026-09-15. Final Studio state: **Edit mode, play stopped, no temporary instances or
attributes left in the Edit datamodel, no game settings touched.**

## 1. Reproduction

Exact steps (single Studio player, owner account):

1. `start_stop_play is_start=true`; Server datamodel: `p:SetAttribute("DevFastQueue", true)`,
   `char:PivotTo(CFrame.new(-72, 33.5, -773.2))` (LaunchZone9, Level 3 pad).
2. **`Remotes.ConfigureQueue:FireServer(...)` no longer works from `execute_luau`** — this
   Studio build refuses it: *"The current thread cannot fire 'ConfigureQueue' since
   'ConfigureQueue' has additional values for the Capabilities property: LoadUnownedAsset
   (and 3 more)"*. The remote's own `Capabilities` is empty; it is the assistant thread that
   is sandboxed. Workaround used: click the real UI with `user_mouse_input`,
   `instance_path = LocalPlayer.PlayerGui.RoundGui.QueueHostShade.QueueHostPanel.CreateParty`.
   (The same restriction breaks the push tool's compile probe, see §4.)
3. 3 s countdown → Level 3 round runs locally. Server: find the nearest
   `Level3_HideTableAnchor`, stand the player 6 studs off it.
4. Client: `CurrentCamera.CameraType = Scriptable`, `CFrame.lookAt(root, anchor)`, then
   `prompt:InputHoldBegin()/InputHoldEnd()` on `HideUnderTablePrompt`.
   (`ProximityPromptService.PromptShown` only fires on a transition — if the prompt is already
   on screen it never re-fires; trigger the prompt instance directly.)

### What was observed — the defect

With the round floor at y = 24.0 and the hide anchor at y = 26.2 (floor + 2.20):

| Part | Measured (client) | Where it should be |
|---|---|---|
| HumanoidRootPart | floor **+5.69** | floor +2.20 (`Hiding.HiddenRootHeight`) |
| Head | floor +5.94 | under the tabletop |
| UpperTorso | floor +4.92 | under the tabletop |
| LeftFoot | floor +2.62 | under the tabletop |
| tabletop collider underside | floor +2.76 | — |
| visible tablecloth top | floor +3.42 … +3.54 | — |
| `Level3_HideCameraPosition` | floor +1.75 | correct (computed from the anchor) |

So the avatar was **crouched on top of the table**, torso and head above the cloth, legs
dangling through it, while the owning player's camera was correctly under the table — i.e. the
first-person view looked hidden, every other player saw a body sitting on the table.
The crouch pose itself was fine (the `AnimationConstraint.Transform` writes from
`Level 3 Table Hiding Client` all landed; `Root` read back as `p=0,-0.92,0.12 r=-8,0,0`).

Exit was wrong in the same way: `ExitCFrame` put the **feet** at floor +3.2, so leaving hiding
dropped the player ~3.2 studs.

Evidence (Studio `screen_capture`; the MCP returns images inline only, nothing is written to
disk, so these are capture ids, not files):

- `evidence-80-before-hidden` — HUD reads "HIDDEN UNDER TABLE" while the hazmat avatar sits
  folded **on** the tabletop, head and shoulders above the cloth, legs visible below it.
- `evidence-80-after-simulated-fix` — same table, placement corrected by hand in the live
  session, body entirely under the tabletop.
- `evidence-80-after-pushed-fix` — same, after the real fix was pushed to Studio.

Console during the whole repro: clean (only `[EntityKill] Cinematic ground-pin knockout
sequence active`, `[EntityAnimations] Transition controller active`,
`[TunnelLobbyBuilder] bays open: 1, 2, 3 | launch stations: 12`). **No animation failed to
load**; there is no hide animation asset at all — the pose is procedural.

## 2. Root cause

`ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua`
`tryEnter():262` (pre-fix line numbers) — `character:PivotTo(hiddenCFrame)` — and
`releasePlayer():161` — `character:PivotTo(record.ExitCFrame)`.

`Model:PivotTo` moves the model's **WorldPivot**, not the HumanoidRootPart. The shared
gameplay rig (`StarterPlayer.StarterCharacter`, hazmat R15, `AnimationConstraint` joints) is
authored with its pivot **on the feet, 3.49 studs below the root** — measured in the live
session, and the same offset is on the saved template:

```
PrimaryPart=HumanoidRootPart
pivot=(6292.88, 26.20, -82.61)  root=(6292.87, 29.69, -82.51)  delta = 3.49
StarterCharacter: pivotY - rootY = -3.49
```

Setting `PrimaryPart` does not help: the engine keeps the authored `WorldPivot` and moves it
rigidly with the model. So every `PivotTo(anchorCFrame)` placed the *feet* on the anchor and
lifted the whole body 3.49 studs — precisely the gap between "hidden" and "sitting on the
table". `Hiding.HiddenRootHeight = 2.2` and `Hiding.ExitVerticalOffset = 1.0` are both written
as root heights, which is what the fix restores.

## 3. The fix

One helper plus the two call sites, in the Hiding Controller only (13 added lines, 2 changed):

```lua
-- Model:PivotTo moves the model's WorldPivot, and the gameplay rig is authored
-- with its pivot on the floor, 3.49 studs under the HumanoidRootPart. A raw
-- PivotTo(anchor) therefore parked the whole body ON the tabletop while the hide
-- camera sat under it. Place the ROOT on the target, which is what
-- HiddenRootHeight and ExitVerticalOffset are both measured against.
local function pivotRootTo(character: Model, root: BasePart, target: CFrame)
	character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
end
```

- `tryEnter` → `pivotRootTo(character, root, hiddenCFrame)`
- `releasePlayer` → `pivotRootTo(character, root, record.ExitCFrame)`
  (covers `Controller.FlushAnchor`, which routes through `releasePlayer`)

`PivotTo` is kept rather than writing `root.CFrame` because the rig's limbs are separate
assemblies held by AnimationConstraints — the model move has to stay rigid. Verified live:
the corrected form lands the root with position error 0.0000 and rotation error 0.0000, the
naive form with 3.4875; no part detaches.

Nothing else was touched: no Configuration value changed, occupant cap and lanes
(`HideOccupantCap = 2`, `HideOccupantLateralOffset = 2.0`), the flush/immunity path,
`ProximityPromptService.Enabled`, the camera point and the E/B input handling are all as they
were. **`Level 3 Table Hiding Client.LocalScript.lua` and `Level 3 Configuration` were not
modified.**

> Note for the lead: the same `PivotTo`-vs-pivot mismatch applies to all ~34 character
> `PivotTo` calls in the project (GameManager teleports, level adapters, the lobby builder).
> Everywhere else the character simply falls the 3.49 studs to the floor and nobody notices,
> so they were left alone — only the hide placement needs stud-exact height. Worth a card.

## 4. Studio verification (after the push)

Push: `python tools/record_pending_push.py`, then
`python tools/push_repo_to_studio.py --audit --file "ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua"` → `ready`, no conflicts, then the same without `--audit`
→ **pushed, 23459 bytes**. Backups: `G:\Roblox\MongoTV\.studio-push-backups\20260915-195313`.

- The tool's post-push **compile probe could not run** — same sandbox restriction as §1
  (`cannot reparent '__RepoPushCompileProbe' to 'ServerStorage'`). Compensated by (a) a clean
  Luau parse of the file offline, (b) a full Level 3 round played after the push with the
  module running and the console clean. Studio's own copy was re-read: 23459 bytes, contains
  `pivotRootTo`, contains no bare `character:PivotTo`.
- Fresh play run, fresh Level 3 generation, same recipe:

| Check | Result |
|---|---|
| Root lands on the anchor | `rootY - anchorY = 0.0000` (twice, two separate entries) |
| Lane | horizontal offset 2.00 = `HideOccupantLateralOffset`, slot 1 |
| Body under the table | Head floor +2.45, UpperTorso +1.44, LowerTorso +0.46 (collider underside +2.76) |
| Visual | `evidence-80-after-pushed-fix`: avatar fully under the tabletop |
| Hide camera | `CurrentCamera.CFrame.Position` == `Level3_HideCameraPosition`, error 0.0000 |
| Local body clipping | Head/UpperTorso `LocalTransparencyModifier` = 1 while hidden |
| Prompts while hidden | `ProximityPromptService.Enabled = false`; anchor prompt still `Enabled` (2nd lane free) |
| Exit — button | LEAVE HIDING click released the player (run 1) |
| Exit — key | E released the player (run 2) |
| Exit placement | root steady at floor **+3.60** from the first sample, **no drop** (was a 3.2-stud fall) |
| Exit distance | 6.14 studs from the anchor = `ExitOffsetZ 5.8` + lane 2.0 |
| Restoration | WalkSpeed 16, JumpPower 50, JumpHeight 7.2, AutoRotate true, root un-anchored, DisplayDistanceType Viewer, CanCollide/CanQuery/CanTouch restored, `Level3_Hiding/HideTableIndex/HideGeneration/HideCameraPosition` cleared, hide GUI off, `ProximityPromptService.Enabled = true`, camera back on the head (CameraType Custom, 0.6 studs) |
| Console | clean, no errors or warnings |

**Two occupants was not reachable** — one Studio player only, and `tryEnter` requires real
`Player` objects, so a dummy cannot take the second lane. The fix does not touch
`slotLateral`, the occupancy list or the cap; the lane offset was verified as exactly 2.0 in
anchor space, and the offline test covers the slot-2 lane (yawed anchor + facing flip) since
that is where a naive vertical correction would have gone wrong.

## 5. Offline test

New: `tools/tests/test_level3_hide_animation.py` (marker extraction, fake rig, no Studio).

```
LUAU_BIN="C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe" python tools/tests/test_level3_hide_animation.py
-> level 3 hide placement: 5 checks passed (actual pivotRootTo; fake rig)   exit 0
```

It extracts the real `pivotRootTo` and runs it against a model whose pivot is 3.49 studs under
the root, asserting: the fake reproduces the engine behaviour the bug depended on; the root
lands exactly on the anchor; it stays exact through a yawed anchor with a lane offset and the
180° facing flip; the exit lane is exact; a rig already pivoted on its root is unaffected.
Python-side it asserts both call sites route through the helper, that no bare
`character:PivotTo(` remains, and that `HiddenRootHeight 2.2 / ExitVerticalOffset 1.0 /
HideOccupantCap 2 / HideOccupantLateralOffset 2.0` are unchanged.

Fails on the pre-fix source (verified by running `source_contract()` against
`git show HEAD:...`): *"pivotRootTo is not defined in the Hiding Controller"*.

Neighbours re-run: `test_controller_input.py` 120 checks pass, `test_level3_steering.py` 222
checks pass. `test_level3_hidden_chase.py` still fails — pre-existing and unrelated: it dies in
`livingPlayer` with `attempt to index nil with 'IsActive'`, i.e. the harness has no
`PlayerProtection` stub for the Mall Manager code it extracts; it extracts nothing from the
Hiding Controller. Left alone per the brief.

## 6. Remaining limitations

- Two occupants under one table not exercised live (single Studio player).
- The post-push compile probe in `push_repo_to_studio.py` cannot run under this Studio build's
  sandbox; the module was validated by parse + a live round instead. Same cause blocks
  `ConfigureQueue:FireServer` from `execute_luau` — the playtest recipe in project memory needs
  the `user_mouse_input` CREATE PARTY step added.
- `record_pending_push.py` scans the whole mirror, so it also queued **6 files owned by other
  agents** (Pool Slide Controller/Navigator, TunnelLobbyBuilder, ZyntraMonetization, RoundUI,
  ZyntraStore) as `pending-studio-push`. Nothing of theirs was pushed (`--file` was used) and
  re-recording preserves their `studioSha256Before`, but a bare `push_repo_to_studio.py` run
  would now push all six — the lead should be aware before anyone runs it unfiltered.
- The crouched hood still grazes the invisible tabletop collider by ~0.3 studs and the feet sit
  ~0.87 studs under the floor. Both are properties of the procedural `CROUCH_POSE`, invisible
  in play, and belong to the authored-animation work (card #99) rather than to this placement
  fix. Details and the exact envelope are in `artifacts/trello-20260915/animation-handoff.md`.
- Card #99 handoff for Codex written as requested: `artifacts/trello-20260915/animation-handoff.md`.
