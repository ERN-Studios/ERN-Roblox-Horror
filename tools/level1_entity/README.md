# Level 1 Entity: the motion layer (walk, prowl, run, lunge)

Owner, 2026-10-10: the Entity "walks goofy, chases goofy and lunges goofy; make new, high-quality ones, with Blender or
whatever". Marker `ENTITY_MOTION_20261010`. Authored by Codex (gpt-6.1-sol, effort ultra) from a brief and the live rig;
installed, played and adjusted by Claude.

## What it is

Six clips generated on the Entity's real rig and played as data on every client, over the server's Animator:

| Clip | For | Speed | Notes |
|---|---|---:|---|
| `Walk` | LURK, INVESTIGATE | 8 | a low stalk: 1.2 s cycle, 9.6-stud stride, claws hanging |
| `Prowl` | TRACK, SEARCH | 17 | the fast creep that state never had (it used the walk at 1.9x) |
| `Run` | CHASE | 27.2 | a lean with a flight phase and alternating claw reaches |
| `Lunge_Windup` | wind-up | | brace, then a sprinter's coil |
| `Lunge_Flight` | airborne | | both hands thrown forward by 0.15 s, held through the apex |
| `Lunge_Land` | standing landing | | three-point catch; a moving landing goes straight to `Run` with an absorb |

`StarterPlayerScripts."Level 1 Entity Motion"` reads them from `ReplicatedStorage.Level1EntityMotion.Clips` (six
StringValues, one clip of `out/clips.json` each) and writes `Bone.Transform` in a render step at
`RenderPriority.Character + 1`. The legs advance with the distance the root really covered on that screen (distance
matching), so the feet stay planted whatever the server's speed multiplier is. The server's `EntityAnimation` still plays
Watch, Howl, Yell and Kill; the layer fades out for them and for `EntityPaused`. Rollback: disable the LocalScript, or set
the client-local `workspace.L1EntityMotionOff = true`.

The old published animation assets and their controller are untouched except that `EntityAnimation` no longer plays its
1.7 s lunge clip while `ReplicatedStorage.Level1EntityMotion` exists. `SoundController` and `EntityShakeController` take the
step sound and the camera stomp from the feet (`workspace.L1EntityStep`, client-local) while a gait is playing.

## Why the old ones looked wrong (measured on the published keyframes)

- Walk: the ankle swept 2.3 studs a step against 5.85 studs of travel, so about 60% of every step was skating, with
  high knees under a frozen torso.
- Chase: the same walk compressed, 270 steps a minute, no flight phase.
- Lunge: no vertical hip motion at all, the reach came after most leaps were over, and its landing crouch played while
  the body was already running.

## Rebuild

```
cd tools/level1_entity
/Applications/Blender.app/Contents/MacOS/Blender -b --python work/build_clips.py -- [--only=Walk] [--no-render] [--floor_up 8.0]
python3 install_motion.py out/clips.json          # Studio in Edit mode; values are replaced, read back and checked
/private/tmp/stayquiet-luau-validation/luau out/sample_test.luau    # the sampling maths on a mock (any Luau interpreter)
```

`work/build_clips.py` asserts per clip and prints a table (`out/qa.json`): rest FK matches the rig to 0.001 stud, limb
reach, stance slide under 0.05 stud a frame (0.002 measured), no foot under the floor, loop continuity, no joint flips.
A rebuild from this folder reproduces `out/clips.json` byte for byte. `input/rig.json` is the rig as read from Studio on
2026-10-10 (51 bones under `char1`); `out/blend/entity_motion.blend` holds every clip as an Action on an armature whose
rest pose is the Studio rest. `out/README.md` is Codex's own record (data format, player contract, what it changed after
looking at its renders). Contact sheets: `artifacts/level1-entity-anim-20261010/renders`.

The preview is a capsule figure: the old FBX's bones are up to 0.87 studs off the live rig, so the mesh was not used.

## Measured in the game (Studio, 2026-10-10)

- The root rides 8.0 studs over the floor (`FLOOR_UP`), so the clips were built at the right height.
- A client write to `Bone.Transform` at that render step wins over the replicated Animator, and the value read there is
  the Animator's pose (60 of 60 reads).
- Walk at lurk speed: gait `Walk`, weight 1, toes 0.03 to 0.75 studs over the floor (the old walk put them 0.9 under
  it and 1.5 over). Chase: Walk -> Prowl -> Run inside 0.5 s as the speed rises; the kill takes over cleanly (weight 0
  while `EntityKillActive`). Three rounds in one session, a new Entity instance each round.
- A forced lunge in a real chase: 0.29 s, 16.7 studs at 59 studs/s, apex 3.7 studs; flight, moving landing, run.
- Seen from the player's own view on the real mesh: the walk coming down a corridor, and the frozen poses `Run@0.05`,
  `Lunge_Windup@1`, `Lunge_Flight@0.4` (`workspace.L1EntityMotionDebug = "Clip@phase"`, client-local).

`LUNGE_GROUND_20261010`: two faults in the landing, both found in play on a client running at about 12 frames a
second. The layer once left the flight a tenth of a second in, 2.4 studs off the floor, because its launch height had
been taken in mid-air: the leap is now measured against a low-water mark of the standing height and nothing lands in
under 0.22 s. And it once held the flight pose for 0.9 s after touchdown, because the filtered vertical speed stays a
hair above zero after the slightest rebound and the test was a strict `<= 0`: back at standing height and rising by less
than 1.5 studs/s is a landing now. After both: flight 0.53 s, moving landing at touchdown, run.

`ENTITY_MOTION_LIVE_20261010`: Codex's review made `nil` on `L1EntityStep` mean "no foot contact" (so a lunge or a
frozen pose is silent). That would have left the Entity without footsteps on any client where this layer did not run, so
the layer also publishes `workspace.L1EntityMotionBeat` (client-local, ten times a second, only while it has a rig and
valid gaits and is not switched off) and the two consumers hand over their timing only while that beat is younger than
1.5 s. Without it their own timers step: 6 legacy steps in 3 s in the mock.

The same review rebuilt how `SoundController` attaches the Entity's growl and step voices: it follows each round's new
Entity instance (`watchEntityRoot`). Before, both gave up for good when the Entity had not reached the client within
60 s of the script starting. Seen: growl and steps on the root in two consecutive rounds of one session.

Foot slide, a rough client measurement at lurk speed (toe travel while within 0.12 studs of its lowest height, against a
body moving 8.0 studs/s): 0.5 and 0.9 studs/s after the review's fixes. The test counts the start of each swing as
stance and the replicated root moves in bursts, so the true figure is lower; it is not zero.

## Not verified

- A natural lunge was logged once (wind-up, flight, landing, then the kill) before the landing fix; it has not been seen
  again since, and never by eye. The forced lunge was re-run after the fix.
- More than one player, a phone, a real 60 fps client (Studio ran at about 12 here), spectating a chase.
- How the footsteps sound now that they follow the feet: the sessions were silent.
- The Entity's visible body is 8 studs wide on a 2-stud collider: arms and shoulders still pass through wall corners in
  a chase. That is the rig and the collider, not the clips.
- Open from the review, each needs a play-test to settle: a lunge that stops dead at its target may play `Run` for the
  0.35 s of the server's standing recovery; a small teleport by the puzzle can be read as gait travel for a frame.

## RUN_CHARGE_20261010: the run was remade, and how animations are judged now

Owner, 2026-10-10 (night): "The entity walk animation in level 1 is good, but its chase/run animation is absolute dog
shit, remake it and QA that shit before you upload." Only `Run` was rewritten (and `Lunge_Land`, which ends in the
run's first pose, follows it); `Walk`, `Prowl`, `Lunge_Windup` and `Lunge_Flight` are byte for byte what they were.

**What was wrong.** The first pass was approved on a capsule figure. The real body is a bulky hunched hazmat suit with
heavy boots, and on it the run was the walk folded double: head at chest height, feet pattering under the hips, one
arm pawing ahead. Nobody had looked at it on the real mesh.

**The new run** (`GAITS['Run']`, the `Run` branches in `foot_path`, `torso`, `arms_gait`, `build_gait`): a heavy charge.
0.72 s cycle, 19.6 studs a cycle at 27.2 studs/s, stance 30% of the cycle; feet reach 2.95 studs ahead of the hips
and kick up 2.25 behind; the hips drop in each stance and rise in each flight (0.5 studs); 25 degrees of lean instead
of 40; the head thrown up out of the hunch and held on the prey; both arms pumping wide of the body with the claws
open, so that from the front (where the hunted player is) nothing crosses the face.

**Judge on the real body, offline.** `export_mesh.py` reads the live skinned mesh out of Studio
(`AssetService:CreateEditableMeshAsync` gives vertices, triangles, the four bones and weights of each vertex and the
bones' bind CFrames) into `input/mesh.json`; `work/render_real.py` skins it with any clip's poses on the measured rig
and renders contact sheets and videos over a floor whose stripes pass at the clip's speed. The mesh's bind pose
matches the rig to four decimals. This does not need Studio's viewport, which was unusable that night (a 214-pixel
strip, then a blank 3D capture after Studio had been restarted).

```
python3 tools/level1_entity/export_mesh.py                                    # once, Studio in Edit
Blender -b --python work/render_real.py -- --clip Run --tag final --phases 12 --views side,front,threequarter --video
```
Sheets and videos: `artifacts/level1-entity-anim-20261010/real/` (`final_Run_*`, and `old_Run_side.jpg`,
`old_Walk_side.jpg` for comparison).

**Checked.** The build's own asserts on all six clips (stance slide 0.002 studs a frame, no foot under the floor, loop
continuity, no joint flips: one was a toe that unbent in 0.25 studs of lift, now 0.9 for the run). In a Studio play
round, a baited chase: 48 frames at 26 studs/s, toes 0.03 to 2.26 studs over the floor, never under it, both feet off
the floor in 12% of those frames, and the kill took over. **Not checked:** the run seen moving in the game by anybody
(only frozen offline phases and numbers), a 60 fps client, more than one player, how the footsteps fall on the new
stride.

A capture trap from that night: `_G` is not shared between `execute_luau` calls, so a "disconnect the previous loop"
kept through `_G` stacks one render loop per call. Hand a token through a workspace attribute instead.
