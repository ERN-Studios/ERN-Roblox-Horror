# Kill_Choke — the stranglehold, 2026-10-11

Authored offline on the supplied real 51-bone Studio rest rig and skinned mesh. Nothing was read from or written to Studio, installed, published, committed, pushed, stashed or reset. No network, browser, computer use, MCP server or helper agents were used. One Blender process ran at a time, with two CPU threads and 480 × 480 renders. The floor is root-space Y = −8.0.

## Beats and handoff

The clip is non-looping, 5.40 seconds, 162 samples, nominal fps 30, stride/speed 0 and contacts []. All 50 non-Root bone tracks are explicit. Its marks are:

| Mark | Seconds | Meaning |
|---|---:|---|
| grab | 0.30 | Cup meets the standing throat at (0, −3.9, −3.7); claw closed. |
| lifted | 1.30 | Victim fully raised; rigid upright body hangs from the cup. |
| tilt | 2.90 | End of the slow 2.00–2.90 s roll; head stays there. |
| squeeze | 3.40 | Pull toward the face and final tightening begin. |
| dark | 4.10 | Complete kill pose; victim preview turns black. |
| release | 4.20 | Fingers open; integration should drop the victim. |

Release recovery ends at 5.40. The squeeze draws the victim 0.60 stud closer along Z and 0.20 upward. The right hand tightens at 1.65, 3.20 and the squeeze. The left arm hangs with slow claw flexion. There is no blood, wound or strike.

The initial upper body is exactly Run sample 7 (phase 0.10), including Hips, spine, head, shoulders and arms; the left sole correction moves that toe up 0.2367 stud and changes the upper-leg local angle 8.40°. The opening claw sweeps inward/back from the existing extended Run reach to the throat. It is **not a fresh rear-to-front thrust**: the locked Run already puts this cup 6.916 studs forward, beyond the 3.7-stud capture point. This is a remaining entry tradeoff; I did not retune Run to hide it.

The final upper body returns to Walk sample 0. Its right wrist is offset +0.35 X / −0.50 Z, and both toe targets are about +0.9335 Y above that Walk pose. An exact final Walk pose and an above-floor, non-intersecting new clip cannot both be claimed here: the real Walk@0 sole is −0.8937 stud under the floor, and its native claw intersects the right leg. The corrected end differs by up to 45.82° in a leg joint. **A zero-pop, floor-safe 0.12 s handoff into the unchanged Walk is not verified or promised.** Main must evaluate that transition on the live rig; only this new clip was corrected.

## How the body takes the load

The stopping stance widens to a 2.44-stud toe track, staggered 1.70 studs fore/aft, and is planted from 0.65 to 4.20. The pelvis rises from the charge into the lift, the crouch opens, the upper spine counter-rotates 5° back and rolls 3° under the load. The right scapula rotates in **root axes**, dropping and rolling forward; arm IK preserves a bent elbow instead of stretching the chain. Hips height targets rise from 3.42 to 4.08, with reach/floor corrections applied to the actual rig.

A slow 0.022-stud breathing displacement and a small shoulder pitch carry the effort; the gripping arm has 0.007-stud tremor. Both are suppressed during the 2.00–2.90 tilt interval, when only neck/head change. The head rolls 30° with a small counter-roll/counter-turn through the neck. During squeeze the neck pitches forward and the head slowly returns upright. The bulky suit still looks hunched, as the supplied body does, rather than suddenly becoming a straight human torso.

## Measured grip and eyes

The grip is a fixed point in RightHand space, **(0.188231, 1.726739, 0.300936)**. The cup is 1.55 studs along the measured finger direction and 0.43 into the measured palm normal. A close-up exposed a missing vertical correction: Middle1/2/3 stood 0.326/0.335/0.322 stud above the horizontal plane. The final palm rises 20° through the lift, lowering the wrist/forearm below the victim frame while the cup remains at the throat. At that angle the measured cup correction is 0.365 stud upward in the grip reference. This moves the actual fingers down from the jaw to the throat. The giant palm and thumb also cover part of the upper chest; this is an oversized claw around a small R15 neck.

The two visor surface samples are mesh vertices **5729 and 7487** (zero-based). On the rest skinned mesh they are approximately (−0.462226, 1.239003, −2.941227) and (0.256469, 1.238304, −2.947885) in Entity root space. I selected forwardmost surface points near symmetric X positions and Y≈1.1 on the front visor, then transformed them through inverse Head rest CFrame. Their head-local midpoint is **(−0.009338, 2.634965, 0.003311)**. Each animated frame carries it through Head's quantized FK matrix.

**The mesh export has no UVs, texture or eye material. These are measured visor references, not recovered yellow-eye texture pixels.** The dark renderer places two small yellow emissive markers on these samples. Exact eye texture registration remains unsatisfied and needs the main agent's Studio check. During the upright hold the victim's eyes are about one stud below these references; the camera looks upward into the face.

All three integer tracks are generated after quaternion/hips export and decoding, from animated FK. They are flat XYZ ×1000 arrays of 3 ×162 integers. `head` is the actual Head bone position; `eyes` is the visor reference; `grip` is the measured cup. Before grab it follows that point on the moving hand. Main can place a standard victim HRP at `grip − (0,1.1,0)` and turn the upright body horizontally toward `head`. The camera position is `grip + (0,0.5,0)` plus 0.25 horizontally away from `head`, with 70° vertical FOV, looking at `eyes`.

## QA on the exported integer payload

All 31 assertions in `out/qa.json["Kill_Choke"]` pass. This is offline geometry evidence, not Roblox execution.

| Check | Measured | Requirement | Result |
|---|---:|---:|---|
| Clip length / samples / fps | 5.40 s / 162 / 30 | 4.6–5.4 s; 30 fps | PASS |
| Victim feet, lifted → dark | 4.0900 studs | ≥1.5 | PASS |
| Grip height over floor, lifted → dark | 8.1900 studs | ≥5.6 | PASS |
| Victim eye → Entity eyes, hold | 3.1737–3.2978 studs | 3–4.5 | PASS |
| Head roll at tilt end | 29.9836° | 25–35° | PASS |
| Largest grip step, grab | 0.4777 studs | ≤0.9/frame | PASS |
| Largest grip step afterwards | 0.2307 studs | ≤0.25/frame | PASS |
| Largest planted toe slide | 0.001908 studs | <0.05/frame | PASS |
| Lowest ankle/toe pivot | 0.2710 studs | ≥0 | PASS |
| Lowest actual mesh sole | 0.0246 studs | ≥0 | PASS |
| Largest local joint turn | 27.2532° | <35°/frame | PASS |
| Smallest right elbow bend away from straight | 55.8523° | >8° | PASS |
| Camera → non-grabbing mesh | 1.6997 studs | ≥1.2 | PASS |
| Grabbing forearm/hand vertical projection | -1.265117 NDC | ≤−1 (below frame) | PASS |
| Victim envelope / body intersecting triangles | 0 | 0 | PASS |
| Right hand / body intersecting triangle pairs | 0 | 0 | PASS |
| FK track rounding error | 0.000500 studs | ≤0.0005/axis | PASS |
| Encoded quaternion norm error | 0.00007305 | <0.0001 | PASS |

The collision tests use the real linearly skinned triangles: SAT against the full oriented 2.2 ×5.2 ×1 victim envelope, including its head, and triangle/triangle SAT for the right hand against torso/legs/left arm. The camera distance is point-to-triangle distance, excluding the grabbing forearm/hand, from grab through release. The other body parts remain outside the victim envelope. Wrist/palm/phalange joint-to-body distance also passes as an extra proxy check. Floor QA covers actual boot vertices as well as pivots. Source frames and sampled interpolation cannot prove every continuous instant or a different live mesh/skin implementation.

A further **483 quarter-interval poses** pass: lowest sole 0.065582, camera clearance 1.700049, feet clear 4.090066 studs; zero hand/body and victim/body intersections; eye distance 3.174558–3.296764. The highest grabbing-arm projection is -1.265810 NDC, below the −1 frame edge. Linear grip-track interpolation differs from FK by at most 0.001725 stud while held. Blender replay of all seven Actions had maximum bone-head FK error **0.000019844 stud**.

## Six old clips: byte for byte

Original whole-file SHA256: `92cce2dded8211025f7f8c5511ea7d31f60cd6792ac1308e2f52231bd83d9d82`.

Every existing clip's serialized JSON bytes are identical after the full build. The new file also begins with the **exact original file bytes minus its final outer brace**, followed by the appended Kill_Choke entry. The whole-file hash changes because a seventh entry was added. Final SHA256: `daf1c237f5871648d989d5a613265b37eef35ce4506bafb2b69db9f2f0fa2730`.

| Existing clip | SHA256 of its unchanged JSON entry | Comparison |
|---|---|---|
| Walk | `4fed261de8211f593cbdfaaefb19d16d2fdd6becd7b9eeb0f7aa9f24d2a992cb` | identical |
| Prowl | `40fb2aaa342f47db4ca4e18a9e6ff7a343eb1bf653c5b995a3e5c975ba683fd6` | identical |
| Run | `c10a265ffd0dfe6d6519afce7ea68f42d2764211fd7ec96f9cbaba7a86b6c40a` | identical |
| Lunge_Windup | `c6c4d0f3de7c5481423a3d5b28c8824500a88bf446d7ab6734b6db468c19cd0c` | identical |
| Lunge_Flight | `020c6793963c2fa271468d92d20141fee2d924c8fa70e70ccce9d2338271f084` | identical |
| Lunge_Land | `4997033abc9ebcc01b101e0f090694cea0ec6d6a82212c299ee1fd9b5a562329` | identical |

## Real-body review and artifacts

I opened the side, three-quarter, dark victim and grip close-up sheets. Review 1 exposed a too-low hold and a hard-to-see grey avatar head. Review 2 confirmed the face/eye silhouette and unmistakeable tilt. The close-up exposed jaw contact; the measured cup correction seats the middle fingers at the neck. A projection test then exposed the forearm in the bottom strip of the victim lens; the 20° rising palm moves the wrist down while keeping the cup at the throat, and the final source/quarter-frame projection checks pass. I also corrected root-axis shoulder loading, replaced abrupt catch/release timing with equalized claw arcs, corrected mesh soles, and separated the final resting claw from the right leg. The avatar now has a teal body, dark blue head and orange throat so contact stays readable. The final side/three-quarter/victim sheets are inspected after the last build.

Final deliverables in `artifacts/level1-entity-kill-20261011/`:

- `final_Kill_Choke_side.jpg` and `.mp4`: lit, with hanging R15 blocks.
- `final_Kill_Choke_threequarter.jpg` and `.mp4`: lit, with hanging R15 blocks.
- `final_Kill_Choke_victim.jpg` and `.mp4`: dark, exact camera geometry, black from dark onward.
- `final_Kill_Choke_grip.jpg`: 16 evenly spaced close-ups and all six marks.
- `review1_Kill_Choke_side.jpg`, `review1_Kill_Choke_threequarter.jpg`, `review2_Kill_Choke_victim.jpg`: earlier comparison sheets.
- `measurement_Walk_front.jpg`, `measurement_Walk_side.jpg`: original body/sole references.

Each required final sheet has 16 evenly spaced samples including both endpoints, then six marked samples. Times use the existing one-shot player convention `i/(frames−1) ×seconds`, so nearest mark samples can differ by at most half a source interval. Every render tile/video frame is 480 ×480; sheets concatenate those tiles with separate footers. Each video is one whole clip at 30 fps, with no repeat. Release preview is an illustrative block drop, not a simulated Roblox ragdoll. Shake/vignette belong to the main agent's UI integration; they are not hidden in the motion data. Dark preview applies black at the nearest dark sample. Videos are encoded/metadata-checked, not played in an app under this job's computer-use restriction.

The dedicated `out/blend/kill_choke.blend` contains the real weighted mesh, measured rig, all seven quantized Actions, the Kill_Choke Action active, and named beat markers. The existing `entity_motion.blend` is preserved.

## Rebuild in this job's allowed scope

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/level1_entity/work/build_clips.py -- --kill-job --no-render
/usr/local/bin/python3 tools/level1_entity/work/build_clips.py -- --qa-only
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/level1_entity/work/render_real.py -- --clip Kill_Choke --phases 16 --views side,threequarter --video --size 480 --tag final --out artifacts/level1-entity-kill-20261011
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/level1_entity/work/render_real.py -- --clip Kill_Choke --phases 16 --views victim --dark --video --size 480 --tag final --out artifacts/level1-entity-kill-20261011
```

Wait for each Blender invocation before starting the next. `--kill-job` avoids legacy keyframe/capsule-preview writes outside the authorized paths; the normal build retains that legacy behavior. QA-only writes clips/QA and skips Blender. Renderer scratch is under /tmp and removed after use. Input data, other gaits, game scripts and unrelated work are preserved.

Remaining limitations: exact Walk handoff and exact eye texture placement described above; opening is an inward catch from the existing Run reach; no runtime cross-fade, client/server, avatar variants, camera shake/vignette, moderation decision or gameplay test was performed. The main agent still owns Studio and integration. Nothing is waiting unpublished in Studio from this helper job because it made no Studio changes.

## Final artifact verification

All three final videos passed ffprobe checks; all four final sheets are 1920 ×3144 concatenations of 480 ×480 render tiles plus 44-pixel footers.

| Video | Dimensions | fps | Frames | Duration |
|---|---|---:|---:|---:|
| side | 480 ×480 | 30 | 162 | 5.400 s |
| threequarter | 480 ×480 | 30 | 162 | 5.400 s |
| victim | 480 ×480 | 30 | 162 | 5.400 s |

All temporary render frames, measurement crops, logs and before-build snapshots were removed from /tmp after inspection. Only the allowed deliverables remain.
