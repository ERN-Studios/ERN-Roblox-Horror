# Level 1 Entity motion — ENTITY_MOTION_20261010

Six new clips are authored directly on the 51-bone Studio rest rig. The client layer distance-matches Walk/Prowl/Run to replicated root travel and plays a body-driven three-part lunge. The existing server Animator continues to provide Watch, Howl, Yell and Kill. Nothing in this folder has been installed or run in Roblox.

The preview is a weighted capsule rig. The supplied FBX failed alignment: its best single similarity fit over all 51 bone heads had a maximum error of **0.868624 stud**, worst at RightHandIndex3, against the required 0.05. We used capsules and did not approve the real mesh, its skinning or its sole contact.

## Rebuild

Run from the workspace root. Blender provides numpy; no external assets or services are required. Run one Blender process at a time.

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python work/build_clips.py --
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python work/build_clips.py -- --only=Walk
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python work/build_clips.py -- --no-render
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python work/build_clips.py -- --floor-up=8.25
```

`FLOOR_UP` defaults to 8.0 studs, measured downward from HumanoidRootPart centre. `--floor-up` overrides it; the `FLOOR_UP` environment variable is also supported. Measure the true value in the game, then rebuild **all** clips. Reach targets are asserted, and an envelope lowers the hips before a stance target becomes unreachable. The generator fails on unachievable horizontal reach.

`--only=<name>` updates that clip's data, publish JSON and sheets while preserving the other saved entries. The blend file regenerates **all six Actions from current code**, so a shared-code change can make non-selected Actions differ from their older saved JSON/sheets. Use a full build after shared edits or a FLOOR_UP change before comparing or delivering outputs. `--no-render` still generates data, runs assertions and saves the blend; existing PNGs are not refreshed. `--qa-only` generates/validates data without the Blender preview stage.

The re-runnable tool dependency is `work/build_clips.py` plus `work/rig_math.py` and `work/preview.py`. Each Action stores `fps`, `seconds`, `loop`, `stride` and `authored_speed` custom properties. Loop samples are keyed at Blender frames 1 through N, with pose 0 at frame N+1 to include the closing interval. One shots use fractional keys `1+i*N/(N-1)`, ending at frame N+1, so every Action spans exactly N frame intervals. Set effective scene fps (`render.fps / render.fps_base`) to the selected Action's `fps`, for example `render.fps=30` and `render.fps_base=30/action["fps"]`. The saved scene starts with Walk active and its fps. The other work files record QA and review evidence. A build produces `out/clips.json`, six publish JSON files in `out/keyframes_v4`, six Blender Actions in `out/blend/entity_motion.blend`, 18 sheets in `out/renders`, and `out/qa.json`.

After changing clips, regenerate the pure-Luau fixture and installer before installation:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python work/verify_blend.py --
/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 work/verify_payload.py --floor-up=8.0
/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 work/analyze_blends.py
/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 work/verify_runtime_layers.py
/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 work/verify_render_rate.py
python3 work/write_sample_test.py
/private/tmp/stayquiet-luau-validation/luau out/sample_test.luau
/private/tmp/stayquiet-luau-validation/luau-compile --null "out/Level 1 Entity Motion.LocalScript.lua"
python3 work/write_readme.py
python3 work/package.py
python3 work/verify_delivery.py
python3 work/package.py
```

Pass the same measured FLOOR_UP to the payload evaluator as to the build; 8.0 in the example is the delivered default. The blend/runtime audits read `out/qa.json["_build"]["floor_up"]` and record input hashes. `work/write_readme.py` refreshes the numeric QA table and floor header.

`work/package.py` refreshes the installer, copies validation/review reports and creates the manifest; run it after refreshed QA/review evidence and README edits. The sample test embeds actual generated Hips/Head tracks, uses the player's decode/sample/contact functions on a pure-Luau JSON, Vector3 and CFrame mock, and exercises wrapping, one-shot hold, translation, normalized short-path rotation, missing bones, blends and contacts. It tests sampling mathematics, not Roblox CFrame or Animator behavior. `work/verify_payload.py` independently decodes the integer payload and runs FK at quarter-frame intervals; its report is `work/payload_validation.json`.

## Installation and exact data layout

`out/install_clips.luau` contains embedded clip JSON and is intended for the Studio **Edit-mode Command Bar**. It creates/updates this layout; it needs no runtime filesystem access:

```text
ReplicatedStorage
└── Level1EntityMotion (Folder)
    └── Clips (Folder)
        ├── Walk (StringValue)
        ├── Prowl (StringValue)
        ├── Run (StringValue)
        ├── Lunge_Windup (StringValue)
        ├── Lunge_Flight (StringValue)
        └── Lunge_Land (StringValue)
```

Each StringValue.Value is JSON for **one clip object** selected from the named dictionary in `out/clips.json`. Do not put the entire dictionary in every StringValue. Create the LocalScript `StarterPlayer.StarterPlayerScripts["Level 1 Entity Motion"]` using `out/Level 1 Entity Motion.LocalScript.lua`.

A clip has `frames` (integer), `fps` (positive number), `loop` (boolean), `bones` (bone-name dictionary), `hips`, `stride` (studs per cycle), `speed` (authored studs/s), and `contacts`. Each bones array is flat `qx,qy,qz,qw` per frame, integers scaled by 10000. Hips is flat local-transform `x,y,z` per frame, integers scaled by 1000 studs. The Hips translation axes are the measured **bone-local** axes, not root axes. Quaternions are renormalized at decode.

Every delivered clip explicitly includes **50 tracks: every Studio bone except Root**. LeftShoulder and RightShoulder carry identity transforms, including where their authored pose is neutral. Omitting those tracks would leave the legacy server gait's 3–5° shoulder motion visible and change the assumed IK parent basis. Adding these neutral tracks changes serialization coverage, not the authored poses, Blender Actions or reviewed renders.

Duration is `frames/fps`, including for one shots. Loop sampling uses `(phase % 1) * frames`, with the next index wrapping modulo frames; there is no duplicated terminal frame. One-shot sampling uses `clamp(phase,0,1) * (frames-1)`, so phase 1 reaches the endpoint at the declared duration. Locomotion has positive stride and contacts `[0,0.5]`; stationary/body-relative one shots have stride/speed 0 and empty contacts. Missing tracks leave the underlying Animator pose available. Walk and Run are required; absent Prowl falls back to a continuous Walk/Run blend.

The publish files retain the old exporter wrapper `{name,looped,priority,retarget,duration,frames}`. `frames` is `[t, [[bone,px,py,pz,qx,qy,qz,qw], ...]]`. They are **not** published Animation assets. A later KeyframeSequence publisher must append the loop's frame-0 pose at `duration` to close the final interval; the clip-data player already wraps it.

Merge the dated changes from `out/integration` into the current live script versions, preserving any parallel edits:

- `EntityAnimation.Script.lua`: its EntityLunge handler dynamically checks for `ReplicatedStorage.Level1EntityMotion` before playing the old lunge. This guard is required, or the old 1.7-second Action4 tail can reappear when the layer yields. It checks at each event, so removing the folder restores the old lunge without restarting the server.
- `SoundController.LocalScript.lua` and `EntityShakeController.LocalScript.lua`: numerical changes to the client-local L1EntityStep attribute trigger the existing footstep/stomp. A nil-to-number change establishes a baseline; number-to-nil resumes the existing timers. Existing voices, proximity and ReduceCameraShake behavior are retained.

For full rollback, disable the new LocalScript and remove the Level1EntityMotion folder. The underlying server Walk/Run/Watch/action assets remain available, and nil L1EntityStep restores the sound/stomp timers.

## Runtime contract and debug

The layer finds `Workspace.Entity` (Model), its `HumanoidRootPart` (BasePart), `char1` (MeshPart), and descendant Bones by exact name. Hips and Head are mandatory to activate; missing other bones are tolerated. It re-collects when the model/mesh or streaming descendants change. `Entity.Humanoid.Animator` is optional for explicit action tracking; when present the layer observes Howl/Yell/Kill names and IDs and yields through their tails. Watch is restored by the stop/pause fade; it is not explicitly blocked as an action because the server also keeps Watch underneath one shots.

Existing workspace inputs are:

| Attribute | Format and meaning | Supplied-script evidence |
|---|---|---|
| EntityState | string/nil; ALERT and YELL yield; other states select gait by speed | EntityAI writes LURK, INVESTIGATE, TRACK, SEARCH, CHASE, ALERT, YELL |
| EntityLunge | finite numeric serial; a changed value starts windup | EntityAI bumps it at the windup, 0.32 s before launch |
| EntityIsLunging | boolean true during the horizontal ballistic phase; false/nil otherwise | EntityAI writes it; EntityKill clears it; it can clear before physical touchdown |
| EntityKillActive | boolean true during capture; false/nil otherwise | EntityKill writes it; kill cancels lunge and fades the layer in 0.12 s |
| EntityPaused | boolean true disables motion; false/nil otherwise | EntityAI and EntityAnimation readers verified; writer outside supplied files |
| EntitySpeedMul | positive finite number; nil/invalid defaults to 1 | EntityAI reader verified; PuzzleManager writer is described in the brief but not supplied |

`L1EntityMotionOff=true` immediately disables the client layer and restores cached Animator transforms. `L1EntityMotionDebug="Walk@0.25"` freezes a named clip at a clamped normalized phase; any of the six names is valid. Debug still yields to pause, kill and server Howl/Yell. Clear the string attribute to resume normal motion. The layer binds `L1EntityMotion` at `Enum.RenderPriority.Character.Value + 1`.

The client writes `workspace.L1EntityStep` as a numeric serial while a gait is active and nil during windup/flight/stationary Land, debug or inactivity; moving Land continues Run contacts. Crossed 0/0.5 contacts advance it; delayed multi-contact updates are coalesced by the sound/stomp consumers. Script-local attributes updated at 10 Hz are `Phase` (gait/windup/flight/land/moving_land), `Gait`, `Weight` (0..1), `GaitPhase` (0..<1), and `MeasuredSpeed` (studs/s).

Horizontal speed comes from replicated position differences, filtered over 0.10 s; vertical speed is filtered over 0.05 s. Teleport-sized updates are excluded. Gait choice divides speed by EntitySpeedMul: Walk below 10.5, Walk/Prowl blend 10.5–14, Prowl 14–20.5, Prowl/Run blend 20.5–24, Run at 24+. Smoothed gait weights select the weighted stride, and phase advances by observed speed times dt divided by that stride.

The lunge uses root height as well as EntityIsLunging, so an early horizontal stop does not prematurely play the landing. Flight is parameterized over 0.428 s; touchdown requires descending near the windup ground level after at least 0.12 s, with a 0.9 s safety timeout. A stationary landing plays 0.35 s. A landing above 8 studs/s goes immediately to Run with a 0.25-second upper-body absorb: Spine02/Spine01/Spine pitch 6°/4°/2° with −12° Head compensation, decaying quadratically. An independent dense audit found that the initial 0.9-stud Hips drop plus 12° pitch drove a Run contact toe to −1.445036 studs; the final absorb keeps the Run hips and leg chain intact. The first .06-second moving-Land handoff additionally adds `0.06*sin(pi*transition)^2` studs of root-up Hips clearance **after** the pose transition; both endpoints have zero lift. A sampled uncorrected handoff reached −0.030879 stud, while 244 corrected handoff poses have a minimum ankle/toe height of +0.023482 stud. Only the stated late-Flight-to-Run subset is checked; Animator fades and arbitrary lunge transitions are not. Roblox contact, blending and actual body appearance still require the lead checks.

## QA at FLOOR_UP = 8

All source-frame assertions passed: rest FK within 0.001 stud; leg reach ≤3.86 and arm reach ≤4.10; planted-toe slide <0.05 stud/frame; ankle/toe pivots ≥−0.02 stud for every clip, including Flight at the conservative launch-height root; looping wrap/mean transition <1.5; quantized loop mean horizontal Hips offset <0.001 stud; per-bone rotation <35° per authored sample at the listed fps; normalized authored/decoded quaternions and sign continuity. Integer quaternion norm error is below 0.0001 before decoder renormalization. A separate 60-Hz audit tests 1,024 possible interval-start phases per clip, rather than relying on the authored frame rate: maximum local-joint turns are Walk 16.515°, Prowl 23.748°, Run 30.529°, Windup 7.435°, Flight 33.058° and Land 33.471°, all below 35°. This is nominal-rate offline interpolation; variable render dt and cross-clip transitions still require Roblox.

| Clip | Frames | fps | Seconds | Stride | Speed | Max stance slide/frame | Loop ratio | Max joint rotation/frame | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Walk | 72 | 60.000 | 1.200 | 9.600 | 8.0 | 0.002320 | 0.717 | 16.66° | PASS |
| Prowl | 64 | 80.000 | 0.800 | 13.600 | 17.0 | 0.002217 | 1.395 | 18.03° | PASS |
| Run | 68 | 100.000 | 0.680 | 18.496 | 27.2 | 0.002341 | 0.836 | 20.22° | PASS |
| Lunge_Windup | 33 | 103.125 | 0.320 | 0.000 | 0.0 | 0.002242 | one-shot | 4.57° | PASS |
| Lunge_Flight | 85 | 198.598 | 0.428 | 0.000 | 0.0 | 0.000000 | one-shot | 10.17° | PASS |
| Lunge_Land | 43 | 122.857 | 0.350 | 0.000 | 0.0 | 0.002116 | one-shot | 17.33° | PASS |

A saved-file Blender replay independently evaluates all 368 keyed poses × 51 bones at their actual (including fractional) key times. All Action spans and fps metadata reproduce their declared durations; the largest replayed head-position error is 0.000017750 stud. Blender quaternion F-curves between keys can differ slightly from Roblox CFrame:Lerp; exact source-key parity is the verified scope.

Rest FK maximum positional error is 0.000079114 stud over all 51 bones. Final Blender pose-head FK error is below 0.000018 stud; its full rest-matrix component error is below 0.000035. The independent integer-payload evaluator checks interpolated limb lengths and floor pivots at quarter-frame intervals, rather than reusing IK targets. Packaged reports include `out/qa_interpolated.json`, `out/blend_validation.json`, `out/runtime_validation.json` and `out/render_rate_validation.json`. Its reported worst full-vector slide is about 0.0244 stud per source-frame equivalent, still below 0.05.

An additional runtime-blend audit found that uncorrected local-rotation blends dip a planted toe to −0.128 stud between adjacent gaits and −0.299594 stud in the Walk/Run fallback. The player adds a root-space Hips lift of `0.68*WalkWeight*ProwlWeight + 0.68*ProwlWeight*RunWeight + 1.40*WalkWeight*RunWeight`. It is zero for pure clips, 0.17 stud at a 50/50 adjacent blend, and up to 0.35 stud at a 50/50 Walk/Run blend. An independent grid of 231 weight combinations × 256 phases (59,136 poses) finds a minimum ankle/toe height of +0.027446 stud after this correction. This is sampled conservative clearance, not a proof between grid points or runtime planted-foot IK: changing blend weights can make feet float vertically. Real blended contact must still be checked.

The floor checks concern **ankle and ToeBase bone pivots**, not mesh soles or every skin vertex. Flight is body-relative but is also checked against a conservative floor with the root held at launch height; the actual upward ballistic arc adds clearance. The HumanoidRootPart carries that arc, which is not baked into the clip. The final 30% of stationary Land intentionally releases its planted feet for the Run handoff, so that section is excluded from stance-slide QA. Loop ratio is an RMS local-joint-angle/Hips-translation metric; one shots have no wrap test. These limits describe this offline build and do not certify blended in-game poses.

## What was seen and changed

Three full render rounds were opened in side, front and three-quarter for all six clips, with eight poses per sheet; the final lower landing wrist was then inspected in all three views again, followed by the six final Flight/Land sheets after the render-cadence refinements (63 sheet inspections by the preview reviewer). Two reviewers inspected the capsule motion. Final sheets use 384-square renders with separate readable frame/time/phase/contact footers, arranged at 1536×856. `L`, `R`, `LR`, `--` indicate left stance, right stance, overlap and flight. Front-facing red head marks are direction cues on the proxy.

- **Walk:** initially the low steps read well but wide squared elbows looked like chicken wings from the front. A sagittal elbow plane and narrower wrist offset tuck the arms beneath the long shoulder line. Final views show dragging claws, pelvis list/weight shift and a stable aimed head, with low swing clearance rather than a high-knee march. Toe roll compensation calms contact-pad orientation.
- **Prowl:** initially shared the broad elbow issue. The same tuck fix preserves stronger arm overlap and a deeper forward body line. Final samples explicitly show its two brief flight intervals at about phases 0.453 and 0.953, distinguishing it from a sped-up stalk.
- **Run:** alternating reaches and flight were present in the first round, but the body looked too upright and excessive swing clearance drove a leg-fold singularity. More pitch in Hips changes the whole silhouette; lower swing clearance and a stable elbow plane preserve heel tuck while avoiding that singularity. Final views show both flight phases, asymmetric claw reaches and backward arm drag.
- **Lunge_Windup:** the first coil looked like a mild sit-back. Deeper hips and more proximal body pitch make the late .320-second coil visibly compress; wrists cock behind the torso while the gaze stays on the target. Both staggered feet stay anchored.
- **Lunge_Flight:** the coherent stretch/reach was the strongest first-round clip. Increased proximal pitch gives a near-horizontal explosion. A later nominal-60-Hz audit exposed an abrupt leg trail and a concentrated arm turn despite smooth high-rate source samples. Lower trailing toe targets avoid the near-hip IK crossing, and a slightly longer throw completes the claw reach by the first third of flight (0.150 s). The reach holds through mid-flight, then descends into the strike as the feet recover. The sheets do not simulate root ballistic height.
- **Lunge_Land:** first-round shoulders stayed high and absorption was weak. A deeper hip dip and forward body pitch give the catch weight. Round 2 exposed a cross-body elbow rising toward the head; a low fixed pole removed it. A flatter supporting palm, raised fingers and a final wrist catch lowered to 0.50 stud clean up the recovery before the exact Run-phase-zero endpoint. The three landing views were opened after that refinement. A nominal-60-Hz audit then found a fast palm-flattening turn; half of that orientation/curl catch now begins during Flight descent, so Land finishes the remaining half smoothly. Those six latest Flight/Land sheets were opened in all views: lower legs trail clearly, the throw still reads as a forward explosion, and the palm preparation flows into the weighted catch.

## Lead checks before enabling in a round

1. **Gate 0a:** in a real Level 1 client, write a visible test pose to LeftArm.Transform using a BindToRenderStep after the character step while the replicated Watch Animator plays. Confirm that the client write visibly wins. This gate has not been run; if it fails, the data needs the Animation-asset fallback route.
2. **Measure FLOOR_UP:** root.Position.Y minus a downward raycast excluding the Entity, on the real office floor. Rebuild all clips with that value. Check the actual mesh's toes, soles, claw/palm contact and skin deformation at planted and airborne poses.
3. **Rig parity:** apply three exported poses in Studio and compare LeftToeBase, RightHand and Head TransformedWorldCFrame positions against FK, within 0.02 stud. Do not use unanimated Bone.WorldPosition as a pose measurement.
4. **Controlled motion:** move an anchored test root at 8, 17 and 27.2 studs/s and measure toe slide for 6 s. Target mean horizontal contact slide <0.6 and p95 <1.5 studs/s; step intervals 0.60/0.40/0.34 s, step sounds/stomps within 0.04 s of contacts. Check 8→17→27.2→0 blending and replication bursts.
5. **Real lunges:** test both short (~10 stud) and long (~26 stud) captured targets. Log root height, horizontal speed and Phase. Windup should start within two frames of the serial change; reach should coincide with launch; land should start within 0.05 s of physical touchdown, never while >0.5 stud airborne. Test stationary Land and the moving Run upper-body absorb separately, including speed blends and foot clearance.
6. **Takeover and streaming:** test Howl, pit Yell, Kill, shield-cancelled Kill, round end/restart and streaming out/in. Ensure Weight is zero for server actions and the old lunge track does not play while the data folder exists. Check that a lunge-to-kill capture does not anchor the entity above the floor; the existing hover/camera risks remain unchanged.

Unverified: every Roblox execution, client-over-Animator precedence, real mesh appearance and floor contact, actual root height, lunge timing/collision window, network smoothing, streaming, sound/stomp callback timing, Roblox CFrame:Lerp parity against the mock, live moving-landing geometry, existing kill hover/camera behavior, and the missing EntityPaused/EntitySpeedMul writers. No animation assets were uploaded, and no gameplay timing, kill script, AI behavior or UI was changed here.
