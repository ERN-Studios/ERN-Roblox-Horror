# Level 3 table-hiding animation — what Codex must produce (card #99)

Written by agent A80 from measurements taken in Studio on 2026-09-15 (PlaceVersion 1894,
Level 3 round running, single player). A80 owns the runtime hiding/camera/restoration fix
(card #80); this file exists so the animation is authored against the real rig and the real
clearances. **A80 does not author animations.**

## 1. The rig, as it actually is at runtime

| Fact | Value |
|---|---|
| Rig | R15, one shared authored rig (`StarterPlayer.StarterCharacter`, hazmat suit) |
| Joints | **`AnimationConstraint`, not `Motor6D`** — standard R15 names: `Root, Waist, Neck, Left/RightHip, Left/RightKnee, Left/RightAnkle, Left/RightShoulder, Left/RightElbow, Left/RightWrist` |
| Scale | `Model:GetScale()` = 1.00, `BodyHeightScale/WidthScale/DepthScale/HeadScale/BodyTypeScale` = 1, `BodyProportionScale` = 0 (AvatarNormalize pins these in round; it is inert today because every in-round character spawns from this one rig) |
| `Humanoid.HipHeight` | 2.605 in round (2.967 on the saved template — use the runtime value) |
| HumanoidRootPart | 2×2×1; standing root sits **3.605 studs** above the floor |
| Model pivot | authored **3.49 studs BELOW the root** (on the feet). This is why `Model:PivotTo` is not the same as placing the root — see §5 |

Animations are keyed by joint *name*, so a normal R15 export retargets onto these
AnimationConstraints. Author in Blender on an R15 skeleton with default proportions.

## 2. What plays today

There is **no animation asset for hiding or crouching anywhere in the project.** The pose is
written procedurally, every frame, by `StarterPlayer/StarterPlayerScripts/Level 3 Table
Hiding Client.LocalScript.lua` (`CROUCH_POSE` + the `RunService.PreSimulation` loop): it
writes `joint.Transform` for the 13 joints listed above, on **every client, for every
crouching/hidden player**, because `AnimationConstraint.Transform` does not replicate.
The same pose serves ordinary crouch (with a gait layered on) and the hidden hold
(`hidden = true` → weight pinned to 1, gait 0).

Tracks measured playing on a hidden character (they are *not* stopped; the pose writer just
overrides them after the animator):

| Track | Asset | Priority | Looped | Length |
|---|---|---|---|---|
| `mood` | `14366558676` | Idle | false | 0.00 |
| default R15 idle | `507766388` | **Core** | true | 3.77 s |

So a real hide track must be **`Enum.AnimationPriority.Action`** (or higher) to win, and it
must be stopped on exit or the crouch will stick.

Animation instances live under `StarterPlayer.StarterCharacter.Animate.<state>.<Name>`
(the project already swaps ids there at runtime — see `StarterCharacterScripts/SetRunAnimation.LocalScript.lua`).
`ServerStorage.RBX_ANIMSAVES` exists (animation-editor saves).

## 3. Geometry the pose has to live inside (measured, floor = 0)

| Object | Extent |
|---|---|
| Hide anchor / hide volume (`Hiding.HideVolumeSize`) | 8.6 × 2.5 × 3.0, centred at **+2.20** (`HiddenRootHeight`) → spans +0.95 … +3.45 |
| Tabletop **collider** underside | **+2.76** (collider +2.76 … +3.24) |
| Visible tablecloth top | +3.42 … +3.54 |
| Sight occluder | 11.1 × 3.35 × 4.3, 0.00 … +3.35 |
| Lanes (2 occupants) | anchor-space X = **−2.0 and +2.0** (`HideOccupantLateralOffset`, `HideOccupantCap` = 2); each body then faces ±Z depending on which side it crawled in from |

**The hidden root lands exactly on the anchor CFrame: floor +2.20, lane X ±2.0, yaw = anchor yaw (+180° for the far side).** Author the pose in that space:

- keep the top of the head below **root +0.5** (the collider underside is root +0.56). The
  current procedural pose puts the head centre at root +0.24 and the hood grazes the
  collider by ~0.3 studs — it reads as fully under the table, but tighter is better.
- keep the body within **±1.5 studs of the lane in X** (two bodies 4.0 apart) and **±1.5 studs
  in Z** (the hide volume is only 3.0 deep; the physical tabletop edge is ±2.3).
- the current pose lets the feet reach root −3.07, i.e. 0.87 below the floor. Invisible in
  practice, but a tucked pose that keeps the feet above root −2.2 would be cleaner.

## 4. The sequence the owner asked for

Simple: the server **teleports** the body into the lane (no walk-in, no crawl-in path), then a
visible hiding pose plays. So:

1. **Entry clip** — optional, ≤ 0.5 s, non-looping, starts from whatever pose the idle left and
   settles into the hold. It is cosmetic only: the server has already anchored the body and
   set WalkSpeed 0 before the client sees `Level3_Hiding`.
2. **Hold loop** — required, looping, 3–6 s, subtle (breathing, a small shift). This is what is
   seen 99% of the time. It must be stable: no root translation drift, no pose that leaves the
   volume in §3.
3. **Exit clip** — optional, **≤ 0.3 s**, non-looping. The server teleports the body out the
   instant EXIT is accepted (and the Mall Manager's table-check flush is a teleport too, with
   only a 2.0 s reaction window), so anything longer will be cut mid-play.

## 5. Import seam

Today nothing loads an AnimationId for hiding, so the seam has to be added. Constraints for
whoever wires it:

- **Asset ownership**: the animation must be uploaded by the account/group that owns the
  experience, or it fails at load ("Animation failed to load" / sanitized id) and the player
  T-poses. Codex must publish under the owner's account, and hand over the numeric id.
- **Where the id goes**: the hide is a Level 3 feature, so the natural home is a new key in
  `ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua` under `Hiding`
  (e.g. `HideAnimationId`), read by the Table Hiding Client. The `Animation` instance itself
  should be created by that LocalScript (one per character) — do **not** add it to
  `StarterCharacter.Animate`, which the default Animate script owns.
- **How it loads**: `Humanoid:FindFirstChildOfClass("Animator"):LoadAnimation(animation)`,
  `track.Priority = Enum.AnimationPriority.Action`, `track.Looped = true`, played on the
  **local** player's own character only. Unlike the current `Transform` writes, an animation
  track played by the owning client **replicates to every other client by itself**, so the
  per-client pose writer would only be needed as the fallback.
- **Fallback (required)**: if the id is 0/empty, or `LoadAnimation`/`Play` fails, keep the
  existing procedural `CROUCH_POSE` for the `hidden` branch. That is today's shipped
  behaviour and it never T-poses. Only replace the `hidden` branch — the ordinary crouch
  (walking crouched, gait blending) still needs the procedural writer.
- **Do not touch**: the camera point (`Level3_HideCameraPosition`, published by the server at
  anchor + (lane, −0.45, 0)), the occupancy/lane maths, `ProximityPromptService.Enabled`
  being false while hidden, or the E/B exit handling.

## 6. Acceptance checks to run in Studio

1. Start a Level 3 round (`DevFastQueue` + LaunchZone9 + CREATE PARTY), walk to a
   `Level3_HideTableAnchor`, trigger the prompt.
2. `root.Position.Y - anchor.Position.Y == 0` and the horizontal offset == 2.0 (the lane).
3. Third-person capture from ~11 studs away: the whole body is below the tabletop, no part
   pokes through the cloth, the head does not intersect the collider.
4. `Animator:GetPlayingAnimationTracks()` shows the hide track at Action priority, looped,
   weight 1; the `mood`/idle tracks are outranked.
5. Leave hiding (E and the LEAVE HIDING button): the track stops, the avatar stands
   immediately at floor +3.60, WalkSpeed 16 / JumpPower 50 / AutoRotate true,
   `ProximityPromptService.Enabled == true`, camera back on the head.
6. Blank the id (or point it at an unowned asset) and repeat 1–3: the procedural pose must
   take over, no T-pose, no console error other than the load warning.
7. Console clean through all of it.

## 7. Does A80's runtime fix change any of this?

**Yes, and it is a prerequisite.** Before the fix, `character:PivotTo(hiddenCFrame)` moved the
model's authored pivot (the feet) onto the anchor, so the body sat **3.49 studs too high —
crouched on top of the table** while the camera was underneath it. Any animation authored
against that would have been wrong. After the fix (`pivotRootTo` in
`ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua`) the
**HumanoidRootPart** lands on the anchor CFrame, so §3's "root = floor +2.20" is now true, and
the exit places the root on `ExitVerticalOffset` instead of dropping the player ~3 studs.
Nothing else in §1–§5 is changed by the fix: the pose itself, the joints, the lanes, the
priorities and the camera point are all untouched.
