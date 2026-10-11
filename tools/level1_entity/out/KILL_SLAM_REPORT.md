# Kill_Slam — the slam, 2026-10-11

**One requested constraint is unmet:** the right gripping claw is only 0.223147 stud from the victim camera (required non-striking-mesh clearance ≥1.2). The body clip and review artifacts are delivered with that failed check recorded; this is not a fully compliant/approved integration.

Offline clip on the supplied real 51-bone rig and weighted Studio mesh, beside the unchanged seven Actions. 162 samples, 30 fps, 5.40 s, non-looping, stride/speed 0, contacts []. Root forward is −Z and the floor is Y = −8.0. Studio, network, browsers, MCP servers and computer use were untouched; no other agents, commits, pushes, stashes or resets. Every Blender invocation used `--threads 2`, one process at a time, and every render tile/video is 480 ×480. Scratch was confined to /tmp and removed after delivery checks.

## Beats and integration

| Mark | Seconds | Beat |
|---|---:|---|
| grab | 0.301863 | Known choke/run entry closes the right claw on the upright throat. |
| lifted | 0.804969 | Heave apex; body tipped back 20 degrees, feet fully clear. |
| slam | 1.073292 | Back hits the floor, head away and feet toward the Entity. |
| windup | 2.951553 | Highest authored fist sample, closed and clearly separate from the head. |
| strike | 3.119255 | Actual left middle-knuckle skin reaches the face; victim preview turns black. |
| release | 3.488199 | Throat opens; observers see the slow recovery to the corrected choke/Walk exit. |

The first sample's complete encoded pose and Hips are identical to Kill_Choke. The victim starts upright at throat (0, −3.9, −3.7), facing the Entity. From grab, use `grip` for the throat and the orthonormal `vup`/`vfront` attitude; body centre = `grip − 1.1*vup`, face/eyes = `grip + .55*vup + .35*vfront`. The lying throat is approximately (0, −7.45, −6.48), with up = −Z and front = +Y. The victim's head is away from the Entity; the feet point back toward it. One 0.22-stud rebound settles in about 0.15 s. The throat stays pinned until release; post-release tracks continue following the hands and are no longer victim attachment targets.

All six tracks are flat XYZ integer arrays ×1000, 486 integers each. Grip/head/eyes are calculated from decoded quantized FK. Eyes reuse the measured visor references in the choke report. Fist is the **actual linearly skinned mesh vertex 149** on the closed left middle knuckle, re-evaluated from the exported pose on every frame, including the open-hand entry. Its closed-hand local reference is (0.041113, 1.949037, 0.568670). Face contact is geometric, not a separately invented target track. `marks.strike` is the black-screen/skull-crunch cue; panic vision and sound remain the main agent's integration work. No blood, gore or wound is authored.

## How the body carries it

The rise is a heave, followed by a fast 0.268-second drop. The pelvis travels forward, the trunk folds into the floor pin, and both shoulders/head come down with the grabbing arm. Impact increases the spine fold and briefly flexes the right elbow to 41.33° (17.84° compression), recovering during the 0.15-second damped rebound. The stance is wide and staggered; fixed toes and corrected boot skin stay planted through release. The loaded right arm retains about 23.49° of protective elbow flex instead of the first draft's 96–113° fold; its wrist stays beneath the shoulder and its claw stays on the throat while the torso rears.

During dread the head approaches and studies the face, then rises as the left arm slowly cocks and closes. The raised fist stops at the highest authored sample. The strike uses one continuous quaternion branch, a 34° forward scapular drive at onset, and forward trunk/head follow-through. The actual closed fist reaches the face in five source intervals. It stays down a beat, then the right claw opens over 0.15 s and the Entity recovers slowly. The lit block victim stays on the floor after release; this is an illustrative body, not a Roblox ragdoll simulation.

## Exported-payload QA

**37 of 38 assertions pass; literal camera clearance FAILS.** These are offline source-frame and sampled interpolation measurements, not Roblox runtime, multiplayer or performance verification. The strict requested camera check includes the RIGHT gripping forearm/hand and fails at 0.223147 stud. The separately named choke-style diagnostic excludes both contact forearms/hands and passes at 2.546430 studs; torso, head, shoulders, upper arms and legs remain included. This exception must not be presented as satisfying the literal 1.2-stud requirement. Victim collision uses SAT against the same full 2.2 ×5.2 ×1 envelope as the choke, throat-relative longitudinal extent −4.1…+1.1, including the head. Torso/legs must stay outside; arms are permitted to touch.

| Check | Measured | Limit | Result |
|---|---:|---|---|
| Lifted feet | 3.325000 | ≥2.5 studs | PASS |
| Heave → floor | 0.268323 | ≤0.3 s | PASS |
| Pinned body-centre height | 0.549–0.551 | 0.5–0.6 studs | PASS |
| Vector norm error | 0.000404 | ≤0.01 | PASS |
| Vector dot product | 0.000000 | ≤0.01 | PASS |
| Grip step during slam | 1.377452 | ≤1.6 studs/frame | PASS |
| Grip step elsewhere | 0.477704 | ≤0.9 studs/frame | PASS |
| Windup fist / floor | 7.650000 | ≥7 studs (height alternative) | PASS |
| Windup eyes–fist angle | 19.929314 | ≤32° | PASS |
| Windup → hit | 0.167702 | ≤0.2 s | PASS |
| Fist → face at hit | 0.001414 | ≤0.5 stud | PASS |
| Camera → non-striking mesh, including gripping claw | 0.223147 | ≥1.2 studs | FAIL |
| Camera → non-contact mesh diagnostic | 2.546430 | ≥1.2 studs | PASS |
| Planted toe slide | 0.001983 | <0.05 stud/frame | PASS |
| Lowest boot skin | 0.024542 | ≥0 | PASS |
| Lowest knee pivot | 1.246147 | ≥0 | PASS |
| Victim envelope / floor | 0.000000 | ≥−0.05 stud | PASS |
| Victim / torso–leg triangle intersections | 0 | 0 | PASS |
| Right hand / body triangle pairs | 0 | 0 | PASS |
| Maximum local joint turn | 33.995767 | <35°/frame | PASS |
| Steady pin elbow flex from straight | 23.493850 | ≤30° (added authoring check) | PASS |
| Impact elbow compression | 17.840807 | ≥10° (added authoring check) | PASS |
| Encoded quaternion norm error | 0.000076 | <0.0001 | PASS |
| FK track rounding error | 0.000500 | ≤0.0005 stud/axis | PASS |
| Serialized entry size | 161888 | ≤185,000 characters | PASS |

A further **483 quarter-interval poses** pass: boot skin ≥0.024497, camera (excluding both contact forearms/hands) ≥2.556271, victim envelope/floor ≥0.002002; zero victim/body and right-hand/body intersections. Linear grip-track interpolation differs from quaternion FK by at most **0.032833 stud** during attachment. Continuous collision freedom is not analytically proven. The six striking-hand source poses, windup through strike, also have zero left-hand/torso–leg triangle intersections.

## Seven old clips: byte for byte

The final file retains the **entire original file prefix**, omitting only the final outer brace before appending Kill_Slam. Every old raw JSON entry has identical bytes; this is not only a comparison of parsed values. Every pre-existing QA entry is also unchanged. `artifacts/.../preservation.json` records the proof.

| Old clip | Identical SHA256 before/after |
|---|---|
| Walk | `4fed261de8211f593cbdfaaefb19d16d2fdd6becd7b9eeb0f7aa9f24d2a992cb` |
| Prowl | `40fb2aaa342f47db4ca4e18a9e6ff7a343eb1bf653c5b995a3e5c975ba683fd6` |
| Run | `c10a265ffd0dfe6d6519afce7ea68f42d2764211fd7ec96f9cbaba7a86b6c40a` |
| Lunge_Windup | `c6c4d0f3de7c5481423a3d5b28c8824500a88bf446d7ab6734b6db468c19cd0c` |
| Lunge_Flight | `020c6793963c2fa271468d92d20141fee2d924c8fa70e70ccce9d2338271f084` |
| Lunge_Land | `4997033abc9ebcc01b101e0f090694cea0ec6d6a82212c299ee1fd9b5a562329` |
| Kill_Choke | `35ae6e87d6c531456fd1e35dd228446c911f544eb6fd1d98f17fb912c53e9e55` |

Original whole-file SHA256: `daf1c237f5871648d989d5a613265b37eef35ce4506bafb2b69db9f2f0fa2730`.

Final whole-file SHA256: `93bc4f8bb3e2b444af857b4a39cd85c0be7fbacef3c5b8a565fef03bb82d520b`.

Kill_Slam SHA256: `6ca6b6add773edf827d5f57b0e503aa663f59d4a4c4122d34e8479fe3990fe63` (161,888 ASCII characters).

## Render review and artifacts

I opened the first lit side/threequarter sheets and successive dark victim sheets. The first review exposed the clipped far end of the lying victim; the final cameras are recentered. The dark view exposed the raised fist hidden behind the head despite the direction-angle test passing. Moving it outward/toward the victim makes its silhouette distinct beside the head. I also replaced the deeply bent pin with the loaded near-straight arm, corrected the passive wrist/strike IK branch flips, moved the descent clear of the thighs, restored the safe entry/exit leg branches, and added the forward scapular drive to prevent a whole-source-frame rise after windup. The final sheets were opened after these changes. A last refinement added elbow compression to rebound frames 33–36; those four frames were rerendered in all three videos. All 22 sheet poses were unchanged. I then opened the six-frame rebound detail and both eight-frame strike details: the pin compresses, returns under load and the fist finishes at the face.

The final victim camera is at the contract face point, uses `vup` as projected camera up, 70° vertical FOV, aims at Entity eyes, and blends its aim to fist during the final 0.25 s before strike. It is black from strike onward. The lit views display the block body using both attitude tracks. Final ffprobe verification confirms 480 ×480, 162 frames, 30 fps and 5.4 s for all three videos. The victim video is visible at frame 93 and exactly black at frame 94 (first video sample after strike), through frame 161. Every required sheet has 16 evenly spaced samples including endpoints plus one sample per mark (22 tiles). Each video is one unrepeated 5.4-second clip at 30 fps.

Artifacts in [level1-entity-kill-slam-20261011](../../../artifacts/level1-entity-kill-slam-20261011/):

- `final_Kill_Slam_side.jpg` / `.mp4`: lit side, full lying body.
- `final_Kill_Slam_threequarter.jpg` / `.mp4`: lit observer view.
- `final_Kill_Slam_victim.jpg` / `.mp4`: dark exact victim camera, black at impact.
- `review1_Kill_Slam_side.jpg`, `review1_Kill_Slam_threequarter.jpg`, `review2_Kill_Slam_victim.jpg`, `review3_Kill_Slam_victim.jpg`: retained review comparisons.
- `final_Kill_Slam_side_rebound.jpg`, `final_Kill_Slam_side_strike.jpg`, `final_Kill_Slam_threequarter_strike.jpg`: consecutive-frame impact/strike details.
- `preservation.json`, `verification.json`: hashes, metadata and validation records.

[out/blend/kill_slam.blend](blend/kill_slam.blend) has the real weighted mesh, measured rig, all eight decoded Actions, Kill_Slam active, and named marks. The old native blend files were untouched. Blender FK parity is recorded in verification.json. No installed/live game change is claimed.

## What I am not satisfied with

The requested literal camera clearance is the material unmet constraint: **0.223147 stud**, at frame 52. The victim's eye is only 0.651920 stud from its throat, while the measured right claw actually grips that throat. For the supplied 0.8 ×0.3 ×0.8 neck block and fixed eye offset, even the farthest neck point is only **1.101136 stud** from the camera, less than 1.2; a skin surface touching this neck cannot meet that literal clearance. I have not found a believable contact on this supplied oversized hand that keeps its gripping skin 1.2 studs away from the fixed camera; hiding that arm or exempting contact skin is an integration decision, not an authored pass. The pin is near-straight, **23.49° elbow flex**, rather than a literally locked 0° elbow. The fist is highest at the authored windup sample, but quaternion interpolation can lift its surface by **0.235686 stud** above that sample briefly during the first two strike intervals; the source samples, timing and face hit pass. I am not fully satisfied with that small intermediate arc. The integer grip track can differ from FK by 0.032833 stud between samples, so this clip does not inherit the choke's 0.001-stud continuous tracking claim.

The exit matches the corrected choke exit within **0.002051°** of local rotation after requantization, but differs from unchanged Walk@0 by up to **45.8157°**. The unchanged Walk sole penetration documented in KILL_REPORT.md remains; an exact floor-safe Walk crossfade needs the main agent's runtime check. The mesh has no UV/eye texture, so yellow emissive visor markers are placement proxies. Dark impact briefly obscures those references; exact live eye registration, panic vision, sound, avatar variants and ragdoll/crossfade are unverified here.

## Rebuild within this scope

```sh
OPENBLAS_NUM_THREADS=2 VECLIB_MAXIMUM_THREADS=2 /usr/local/bin/python3 tools/level1_entity/work/build_clips.py -- --only Kill_Slam --kill-job --qa-only
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/level1_entity/work/build_clips.py -- --only Kill_Slam --kill-job --blend-only --no-render
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/level1_entity/work/render_real.py -- --clip Kill_Slam --phases 16 --views side,threequarter --video --size 480 --tag final --out artifacts/level1-entity-kill-slam-20261011
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/level1_entity/work/render_real.py -- --clip Kill_Slam --phases 16 --views victim --dark --video --size 480 --tag final --out artifacts/level1-entity-kill-slam-20261011
```

Wait for each Blender invocation before starting the next. QA-only exits nonzero for the documented literal camera-clearance failure. `--blend-only` checks the verified payload and rig/mesh SHA256 values and requires every other assertion to pass before baking a review artifact; it explicitly reports the known camera failure and never changes it to a pass. Use the dedicated `--only Kill_Slam` route; it appends/replaces this entry while preserving the seven old raw entries. Only the authorized files and the new artifact folder were changed. Main retains Studio ownership and reviews the failed-clearance constraint before integrating the clip; this job leaves no Studio changes waiting unpublished.
