# entity-animation: Level 1 Entity animation: new walk, chase and lunge ("den går goofy, chaser goofy og lunger goofy")

effort: large

## how_it_works_today

RIG (Studio Edit, Workspace.Entity, read 2026-10-10; mirror EntityAnimation is byte-identical to Studio, 10588 bytes)
- Model, PrimaryPart HumanoidRootPart (Part 2x2x1, invisible, CanCollide), attribute RigVersion="v3-fingers". Humanoid (RigType R6, HipHeight 7, AutoRotate) + Animator. No AnimationController, no scripts, no Animation instances inside (EntityAnimation creates them under itself at runtime, :52-71).
- One skinned MeshPart `char1` (8.23 x 11.00 x 5.98, MeshId 113409117000796, CanCollide false), WeldConstraint to the root, centre 2.80 below it. 51 Bones: Root > Hips > {Left/RightUpLeg > Leg > Foot > ToeBase; Spine02 > Spine01 > Spine > {neck > Head; Left/RightShoulder > Arm > ForeArm > Hand > Thumb1-2, Index/Middle/Ring/Pinky1-3}}. So: 22 body bones + 28 finger bones, no jaw, no eye bones. Leftovers: Folder InitialPoses (96 CFrameValues), ObjectValue AnimSaves, Attachments EyeL/EyeR (EntityAI:332-341 moves them under the Head bone).
- Sizes (floor taken as 8.0 below root centre = HipHeight + 1, the value EntityKill:178 assumes): height about 10.7; hip joints 4.82 up and 1.74 apart; thigh 1.738, shin 2.184 (leg 3.92; rest knee flexion 19 deg); ankle 1.01 up; ankle-to-toe-joint 1.548; shoulders 8.77 up and 3.87 apart; upper arm 2.071, forearm 2.075, hand about 2.6 to the middle fingertip; wrists hang at 4.9, fingertips at 2.2 above the floor. The entity faces root -Z.
- Bone axes (measured by FK on the rest CFrames): limb bones have local +Y along the bone. Spine chain: -X pitches forward, +Y yaws left, +Z leans left. UpLeg +X = thigh forward; Leg -X = knee flexion; Foot +X = toes up. Arm +X = swing forward; ForeArm +X = elbow flexion. Head -X = nod down, +Z = yaw left. Hips rest frame is yawed 16.5 deg, so pelvis motion must be computed in root space and converted.

PIPELINE
- Origin: Meshy rig "Dustwalker" (README:173), fingers added in Blender. The current .blend is not in the repo and not on this Mac: the tools drive "the user's open Blender scene" over 127.0.0.1:9876 (blender_mcp_client.py); the two oldest exporters write to G:\Roblox\MongoTV\... (export_entity_animations.py:25, export_entity_keyframes.py:37). Action names: export_entity_keyframes_retargeted.py:31-40 (ENT_LOC_Walk_Fwd_Loop_IP_v003, ENT_LOC_Chase_..., ENT_ATK_Lunge_FromChase_IP_v003, ENT_KILL_GroundPinPunch_IP_v002 ...).
- On this Mac only two older files exist, assets/blender/entity_v2_before_kill_2026-08-02.blend and entity_v2_before_ground_kill_2026-08-03.blend (33 MB each) in three old checkouts under ~/Documents, all iCloud-evicted (0 blocks). In the mirror's git but not checked out (sparse; `git show HEAD:<path>`): assets/animations/entity/entity_*_v1.fbx (7 files, 1.7-2.3 MB, mesh char1 + Armature with fingers), keyframes*/ JSON for every clip, published-assets-*.json, and assets/models/Meshy_AI_Dustwalker_biped_Animation_Running_withSkin.fbx (29.5 MB).
- Export: export_entity_keyframes_retargeted.py samples Blender global matrices at 30 fps, reads the live Studio Bone CFrames and maps each bone's global delta (relative to Watch frame 0, which IS the Studio rest pose, :246-255) onto the Studio rig. Output frames are [t, [[bone, px,py,pz, qx,qy,qz,qw] x 50]] = exactly Pose.CFrame = Bone.Transform. It zeroes non-Hips translation, removes each clip's first-frame Hips offset and clamps Hips translation to 1.25 studs (:318).
- Derived clips: build_restrained_walk.py damps the walk (Hips x0.42, spine/neck/head x0.5, arms x0.58-0.72, thighs x0.82; :28-55). build_corrected_entity_actions.py:72-100 makes the "run" by time-scaling that walk x0.62 and amplifying thighs x1.22, knees x1.14, upper arms x1.28, plus 5 and 3 deg of lean.
- Publish: publish_entity_animations.py builds a KeyframeSequence in ServerStorage.MongoTVEntityAnimations and calls AssetService:CreateAssetAsync(sequence, Enum.AssetType.Animation, {CreatorId = 1039373905, CreatorType = Group}) (:128-133). Fully scripted; the Animation Editor was never involved. That folder still holds about 75 KeyframeSequences v1..v10 with PublishedAssetId. The Python ran through the Windows bridge (sync_from_studio.py:255-259, select_studio by the old place name) and does not run on the Mac as is; its Luau payload does. `defaults read com.roblox.RobloxStudio BetaFeatureInformation` shows CreateAssetAsync enabled = 1 on this Mac.

CONTROLLER (EntityAnimation.Script.lua, server-side Animator, replicated)
- IDs :5-14. Walk 121187609243437 = Walk_Restrained (40 frames, 1.300 s); Run 90840395594409 = Run_PredatoryJog (0.806 s); LungeFromRun 132839013239254 (1.700 s); Watch 5.97 s; Howl 2.17 s; YellFromRun 2.87 s; Kill 4.97 s. One-shots are Action4.
- Heartbeat :257-284: root horizontal speed smoothed 0.10 s, hysteresis 0.55/0.18. Not moving -> Watch. EntityState == "CHASE" -> Run at speed/15. Everything else (LURK, INVESTIGATE, SEARCH, TRACK) -> Walk at speed/9. Clamp 0.08-2.5 (:16-19). Crossfade 0.25 s with phase carried by TimePosition (:119-157).
- playAction :159-182 (fade 0.12, Watch underneath, locomotion suspended until Ended, :273). PlayHowl/PlayYell/PlayKill/CancelKill BindableEvents :195-220. workspace attribute EntityLunge -> LungeFromRun :222-224. GameManager:761-788 invokes script.ReleaseAnimations before parking the entity.
- Speeds (EntityAI:198-201): LURK and INVESTIGATE 8, TRACK/SEARCH 17, CHASE 27.2, all x EntitySpeedMul (up to 1.1 from fuses, 1.3 once the exit opens: PuzzleManager:1598-1599, :2466).

WHY IT LOOKS GOOFY (forward kinematics of the published keyframes on the Studio rest rig; my FK matches Studio's rest joint positions to 0.001 stud)
1. Walk. The ankle sweeps 2.2-2.4 studs fore-aft per step; the controller assumes 9 studs/s x 1.3 s = 5.85 studs per step. About 60% of every step is skating. Knees fold to 84-89 deg and the ankle lifts 1.6 studs (a high-knee march) while the damping froze everything above: spine bones move 1.5-2.1 deg, hands 0.34 studs, hips bob 0.07 studs. At lurk the clip runs at 0.89x = 82 steps/min; the step sound runs at 113/min (SoundController:104).
2. TRACK/SEARCH (17 studs/s) has no gait of its own: the same walk at 1.89x, 174 steps/min.
3. Chase. The "run" is that walk compressed; at 27.2 it plays at 1.81x: cycle 0.444 s = 270 steps/min, ankle sweep 2.5-2.6 studs against 6.05 studs of travel per step, hands move 0.45 studs, hips bob 0.07, no flight phase. Step sound and camera stomp run at 0.34 s (176/min).
4. Lunge. The clip has no vertical hip motion at all (root-space hips Y is -2.76 in every frame): its crouch is both ankles lifting up to 1.8 studs at 1.0-1.3 s, on a body the Humanoid holds at standing height. Hips forward/back flat-lines at +1.74 from 1.07 to 1.30 s (the 1.25-stud clamp). The arm thrust peaks at 0.6-0.7 s with fingertips 3.1 studs ahead of the root (the arm is 6.7 long). Against EntityAI: the clip starts at the wind-up (:1094), launch is 0.32 s later (:211), horizontal travel stops within 2.5 studs of the captured point (0.12 s after launch for 10 studs, 0.40 s for 27; :1022), touchdown is about 0.43 s after launch whatever the distance (42 up, gravity 196.2), and the chase resumes 0.35 s after the stop = 0.73-1.08 s after the wind-up began. So the reach comes after most flights are over, and the clip's "landing crouch" plays while the entity is already running at 27.2 with locomotion locked out until the 1.7 s track ends: a floating crouch sliding across the floor.
5. From code only, not run: EntityKill:122-128 anchors the entity wherever a touch lands and takes killBaseCFrame there. A touch during the lunge arc (up to 4.5 studs high) would leave it hovering for the 5 s kill.

OTHER CONSUMERS
- The kill is Touched on any entity part (EntityKill:228-232); the skinned mesh collides in its rest shape, so the grab window is body contact, not the arms.
- JumpscareUI:112-132 aims the kill camera at the Head bone's WorldPosition.
- Step sounds and camera stomps are free-running client timers, not tied to the animation: SoundController:104-105 and :721-790 (0.53 s per step, 0.34 s when state is CHASE), EntityShakeController:27-28 and :101-106.
- LUNGE_SOUND is "" (SoundController:35): the lunge has no audio telegraph.

## design

DECISION: route A as a client-side override layer, fed by clips generated on the Studio rig; the same clip files are also written in the publish format so route B stays one command away.
- One new LocalScript writes Bone.Transform for locomotion and the lunge on each client. The server controller and its eight assets stay and keep driving Watch, Howl, Yell and Kill. Rollback = disable the LocalScript.
- Gate 0, before authoring (two spikes): (a) Level 1 play session, Client: BindToRenderStep that sets LeftArm.Transform = CFrame.Angles(math.rad(90),0,0) while Watch plays, then screen_capture. Arm raised = the layer can override the replicated Animator. (b) Edit: CreateAssetAsync a 2-keyframe KeyframeSequence as an Animation for group 1039373905. If (a) fails, go route B with the same clips.

1. TOOLING, new folder tools/level1_entity/
- dump_rig.py -> rig.json: every Bone under char1 (name, parent, CFrame components), mesh offset in root space (-0.0937, -2.8033, -0.0170), FLOOR_UP (measure, see tests).
- rig_math.py (numpy): fk with G(bone) = G(parent) * Bone.CFrame * Transform; world-delta -> Transform conversion; two-bone IK for legs and arms (aim local +Y at the child joint, hinge axis from the rest pose); foot orientation from pitch and toe-out; finger curl axis computed per bone from the rest frames (do not assume local X).
- build_clips.py, run headless: /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level1_entity/build_clips.py -- [--only=Walk] [--no-render]. Generates poses, asserts, writes clips.json and keyframes_v4/*.json (publish format), builds an armature whose rest pose is the Studio rest in Roblox axes (object rotated +90 deg X, EditBone.matrix = Studio rest; then pose_bone.matrix_basis equals Bone.Transform), keys every frame, saves artifacts/level1-entity-anim-<date>/blend/entity_motion.blend, renders side / front / three-quarter contact sheets.
- Preview mesh (optional): `git show HEAD:assets/animations/entity/entity_watch_v1.fbx`, apply its armature at Watch frame 0, scale 0.0647, rebind by vertex-group name. If toe and fingertip are not within 0.05 stud of the FK, render capsules and judge the mesh in Studio.
- install_clips.py: StringValues in ReplicatedStorage.Level1EntityMotion.Clips (pattern: build_dance.py:151-162).

2. DATA FORMAT (Level 6's, plus four fields)
{frames, fps (= frames / seconds, may be fractional), loop, bones: {name: [qx,qy,qz,qw x frames as ints x10000]}, hips: [x,y,z x frames, studs x1000, in the Hips bone's local frame], stride (studs per cycle), speed (authored studs/s), contacts: [phase of left contact, phase of right contact]}. Bones absent from a clip are not written (the Animator's pose shows through; fingers only appear in the lunge clips). Loops: frame N wraps to frame 0, no duplicate end frame. Root motion convention: in place. HumanoidRootPart carries all travel; Hips translation carries only bob, sway, crouch and the lunge's body shift; loops have zero mean lateral and fore-aft Hips offset.

3. PLAYER: StarterPlayerScripts."Level 1 Entity Motion" (LocalScript, every client, nothing new replicated)
Inputs: the root's replicated position, and workspace attributes that already exist: EntityState, EntityLunge, EntityIsLunging, EntityKillActive, EntityPaused, EntitySpeedMul.
RunService:BindToRenderStep("L1EntityMotion", Enum.RenderPriority.Character.Value + 1, step):
  rig = Workspace.Entity.char1 bones, re-collected when the mesh instance changes; return if Hips or Head is missing (streamed out or parked)
  speed = low-pass 0.10 s of horizontal |dpos|/dt; vy = low-pass 0.05 s
  lunge machine:
    EntityLunge changed -> phase "windup", groundY = root Y
    windup and (EntityIsLunging or Y - groundY > 0.3) -> "flight"
    no phase and EntityIsLunging -> "flight" (bump missed or Studio hook)
    flight and t > 0.12 and Y - groundY < 0.35 and vy <= 0, or t > 0.9 -> "land"
    land and t >= 0.35 -> none, gaitPhase = 0
    windup for 0.6 s without flight -> none
  want = not EntityKillActive and not EntityPaused and state not ALERT/YELL and (phase or moving [0.55 in / 0.18 out])
  w moves to (want and 1 or 0) in 0.18 s up, 0.22 s down, 0.12 s when a kill starts; w == 0 -> return
  locomotion: v = speed / EntitySpeedMul. Walk below 10.5, Walk->Prowl 10.5-14, Prowl 14-20.5, Prowl->Run 20.5-24, Run above; weights smoothed 0.15 s. stride = weighted sum of clip strides; gaitPhase += speed * dt / stride (distance matching: the legs advance with the distance actually covered on that screen). Sample each active clip at gaitPhase and blend. When gaitPhase crosses a contact phase: workspace:SetAttribute("L1EntityStep", n + 1) (client-local).
  lunge: sample Lunge_Windup at t (hold last frame); Lunge_Flight at clamp(t / 0.428, 0, 1); Lunge_Land at t if speed at touchdown < 8, otherwise go straight to Run and add a decaying absorb (Hips -0.9 studs, pitch +12 deg, 0.25 s).
  write: for each bone in the pose, animator = bone.Transform (if it equals what this script wrote last frame, reuse the last animator value or identity); bone.Transform = animator:Lerp(target, w).
Debug hooks (client-local): workspace attribute L1EntityMotionOff = true disables it; L1EntityMotionDebug = "Walk@0.25" freezes a clip at a phase; the script publishes Phase, Gait, Weight on itself at 10 Hz.
Cost: 50 reads, up to 3 clip samples, 50 writes per frame, only while the entity is streamed in.

4. SERVER: EntityAnimation gets one guard. local CLIENT_MOTION = ReplicatedStorage:FindFirstChild("Level1EntityMotion") ~= nil; in the EntityLunge handler (:222-224): if CLIENT_MOTION then return end. Otherwise a lunge that ends in a stop would uncover the tail of the old 1.7 s clip. Old Walk/Run stay as the fallback for a client without the layer.

5. CLIP BRIEF. Frame used below: right, up from floor, forward; centre line x = -0.09. Rest: hip joints (+-0.87, 4.82, -0.44), ankles (+-1.46, 1.01, -0.73), toe joints 1.06 below and 1.13 ahead of the ankle, shoulders (+-1.93, 8.77, 0.15), wrists (+-3.13, 4.92, 0.16). Phase 0 = left foot contact, 0.5 = right. Legs are solved by IK from foot paths, never hand-keyed; every stance frame moves the planted toe at exactly -speed. All numbers are starting values; the build asserts hip-to-ankle <= 3.86 and shoulder-to-wrist <= 4.10 and adjusts hip height.

WALK "stalk", authored at 8.0: cycle 1.20 s (36 frames), stride 9.60, duty 0.62 (stance travel 5.95).
- Feet: track width +-1.15 (rest is +-1.46), toe-out 10 deg. Contact at forward +3.13 with toes up 18 deg, flat by 12% of stance, heel-off from 55%, toe-off at -2.82 with the heel up 50 deg and ToeBase bent 35 deg. Swing: ankle clears 0.9, foot slows to ground speed over the last 15%.
- Pelvis: hip joints about 4.0 up at each contact, 4.35 at mid-stance (rest 4.82: a crouched prowl; the reach of a 3.92 leg forces it). Lateral shift +-0.30 over the stance foot, yaw +-8 deg (swing hip forward), list +-3.5 deg, a quick 0.12 s dip after each contact.
- Torso: lean 22 deg from vertical (rest 13.3; add about 3/3/2/1 deg down Hips, Spine02, Spine01, Spine), pitch pulse +-2.5 deg twice per cycle, 0.07 cycle after contact; shoulder line counter-yaws +-5 deg, counter-rolls +-2 deg.
- Head: cancels 85% of the thorax yaw and roll and all of the pitch pulse; 5 deg down.
- Arms, opposite to the legs: upper arm +16 / -10 deg, elbow 30 -> 48 deg peaking 0.08 cycle late, wrist drag +-12 deg a further 0.06 late, fingers 15 -> 35% curl on the back swing. Hands travel about 1.5 studs (0.34 today). Asymmetry: right arm x1.2 and 6 deg more bent, left x0.9, head tilted 4 deg, thorax yaw bias 3 deg.
- No-audio-edit variant: cycle 1.06 s, stride 8.48, stance travel 5.26, contact hip height about 4.3.

PROWL, authored at 17.0 (TRACK and SEARCH; without it that state stays a sped-up walk): cycle 0.80 s (24 frames), stride 13.60, duty 0.42 (stance travel 5.71, two 0.064 s flights). Forefoot contact at +2.87, toe-off -2.84, swing clearance 1.3, swing knee to 95 deg. Hip joints 4.0 at contact, 3.85 mid-stance, 4.1 in flight. Lean 32 deg, pelvis yaw +-10, thorax +-8, arms low and forward (upper arm +30 / -20, elbows 55-75), hands within 1.2 studs of the floor on the back swing, neck +14 deg so the face stays up.

RUN, authored at 27.2: cycle 0.68 s (20 frames at 29.41 fps; equals the 0.34 s step sound), stride 18.50, duty 0.28 (stance 0.19 s, travel 5.18, two 0.15 s flights).
- Feet: forefoot contact at +2.41 (toes down 15 deg), toe-off at -2.77 (heel up 65 deg), heel kicks to ankle height 3.2 (knee 115-120 deg), thigh drives to +55 deg at mid-swing.
- Pelvis: 4.25 at contact, 3.95 mid-stance, 4.55 at the top of flight; yaw +-12, list +-5, lateral +-0.15.
- Torso: lean 40 deg (add about 9/8/6/4), thorax counter-yaw +-14; neck and head +28 deg, stabilised 90%.
- Arms: alternating claw reaches. Forward wrist about (+-1.4, 7.4, +5.4), elbow 35 deg, fingers spread; back wrist about (+-2.6, 5.2, -1.0), elbow 85 deg, fingers hooked; the pull-back is fastest during the opposite foot's stance. Asymmetry: right hand 0.6 further and 0.5 higher, head cocked 6 deg, thorax biased 4 deg toward the right arm, left hand drops to 2.5 above the floor.

LUNGE, three clips driven by what the body is doing:
- Lunge_Windup, 0.32 s then hold (the server has stopped it dead and turns it to face the target). 0.10 s "brake": left toe planted at +2.6, right at -3.4 on the ball of the foot, hip joints down 0.9 and back 0.5, pitch 35 deg, wrists swept to (+-2.4, 4.4, -1.6). 0.24-0.32 s "coil": hip joints down 1.5 and back 0.9 (sprinter's crouch, rear knee about 100 deg), pitch 55 deg with Spine01 and Spine rounded 8 deg more each, wrists cocked at (+-3.0, 5.2, -1.8), elbows 80 deg, fingers spread, head up 35 deg relative to the torso, thorax wound 12 deg left.
- Lunge_Flight, parameterised by airtime u = t / 0.428 (body-relative, no floor). u 0-0.25 "explode": pitch 68 deg, spine arched, head up 45 deg, ankles trailing at (+-1.0, 3.3, -3.3) with toes pointed, wrists thrown to (+-1.3, 7.2, +7.1), right hand 0.3 further and higher, elbows about 35 deg, thorax unwinds to 8 deg right. u 0.5: 3% overshoot and settle, knees start to 60 deg. u 0.75-1 "strike": pitch 75 deg, wrists down to (+-1.2, 3.5, +5.8), fingers curl to 60%, feet swing forward under the body.
- Lunge_Land, 0.35 s (= LUNGE_RECOVER), used when it lands standing still. 0.08 s: three-point landing, hip joints down 2.2, pitch 75 deg, left wrist on the floor at (-1.6, 0.5, +4.6), right arm sweeping across to (-0.4, 3.2, +3.0), head up 30 deg. 0.20 s: off the hand, hips down 1.0, pitch 50 deg. 0.35 s: equals Run at phase 0.
- A kill at any moment: the layer lets go in 0.12 s and the Animator's Kill clip takes over.

6. STEP SOUND AND STOMP follow the feet: in SoundController's step loop and EntityShakeController's stomp block, when workspace:GetAttribute("L1EntityStep") is not nil, fire on its change and skip the timer; the layer sets it to nil when inactive so the timers return.

7. ROUTE B BAKE (optional, later): keyframes_v4/*.json through the publish Luau (CreateAssetAsync), new ids into ANIMATION_IDS, WALK_ANIM_SPEED 8 and RUN_ANIM_SPEED 27.2, so the server-side fallback matches.

## dependencies_and_risks

- Gate 0a decides the route. The layer relies on a RenderStepped write to Bone.Transform winning over the replicated Animator, and on bone.Transform read at that moment being the Animator's pose. Level 6 writes bones the same way, but its doll has no Animator.
- Streaming is on and the Entity's ModelStreamingMode is Default: char1 and its bones can leave and return on a client. The layer must re-collect bones and tolerate nil (Level 6 client :1174-1199 shows the pattern).
- The entity's motion reaches clients in bursts (SoundController:748-752 says so). Distance matching will show that as leg stutter unless speed is smoothed; the 0.10 s constant needs tuning on a real client.
- Speeds are not constants: EntitySpeedMul 1.0-1.3 and two MasterConfiguration keys. Distance matching absorbs it; the gait thresholds are divided by EntitySpeedMul but not by a retuned L1_EntityLurkSpeed or L1_EntityChaseSpeed. If the owner moves those far, thresholds should come from EntityState instead.
- The stride forces a crouch: a 3.92-stud leg cannot take 4.8-stud steps upright. If the stalk reads too low, use the 1.06 s variant.
- Short lunges resume the chase before or at touchdown (0.35 s counts from the horizontal stop, not from landing), which is why the landing has a moving variant. Changing that timing is gameplay and the owner's call.
- A lunge that hits may leave the entity anchored in the air for the kill (EntityKill:122-128). If true, new lunge clips will not hide it.
- Kill staging, DEATH_AT 124/30 and the Kill clip are untouched; the layer must be at weight 0 for the whole capture or the kill camera's framing changes.
- ReleaseAnimations (GameManager:761-788) and the three Level 2/3/4 adapters that toggle EntityAnimation by name keep working because the script and its contract are unchanged.
- New data replicates to every client on every server, lobby included: about 100-150 KB of StringValues.
- New scripts cannot be pushed by the sync tools; create in Studio, then add the manifest item. Other sessions edit Studio: audit before pushing EntityAnimation, SoundController and EntityShakeController.
- Route B depends on the CreateAssetAsync beta, which this project has seen come and go; every revision is a new group asset.
- Not touched: RoundUI, ZyntraMonetization, any GUI (nothing for UIRegression), anything parented to a player character (nothing for the Mimic).

## alternatives_considered

B. Publish Animation assets (what publish_entity_animations.py did). Smallest code change: new ids, WALK_ANIM_SPEED 8, RUN_ANIM_SPEED 27.2, a third gait and a three-part lunge in EntityAnimation, about 80 lines; engine blending and replication for free; the beta flag is on today. Not chosen as primary because every look iteration is a new group asset (ten versions already sit in ServerStorage), the project has been refused by CreateAssetAsync before, and it cannot do distance-matched feet or a lunge posed from the body's real height. It is the fallback if Gate 0a fails, and the optional bake afterwards.

A-full. Move all eight clips to data and drop the Animator. The existing keyframes_v3 JSON would carry Watch, Howl, Yell and Kill over unchanged, but it touches the kill path, needs about 0.7 MB of clip data on every client, and removes the fallback. More risk for nothing the owner asked for.

C. Purely procedural motion with no clips. Used only as layers (landing absorb, later turn lean and head look); on its own it reads robotic.

Meshy's animation library on a re-rigged copy. Mocap quality for the upper body, but it costs credits (needs the owner's confirmation), needs the old retarget path, and still slides because its stride is not ours.

Re-author in the original Blender file. That file is on the Windows PC; this Mac only has evicted v2 copies, and the old retarget chain (ten versions of fixes, a 1.25-stud Hips clamp) is where the lunge's missing crouch came from. Generating directly on the Studio rest pose avoids it.

## could_not_establish

- Whether a client RenderStepped write to Bone.Transform overrides the replicated Animator on this rig (no play session allowed). Gate 0a.
- Whether CreateAssetAsync accepts Enum.AssetType.Animation from this Mac session today. The beta flag reads enabled = 1; the last proven Animation upload was on the Windows PC (v10, 2026-10-02). Not called: it would create an asset.
- The true standing height: floor relative to the root centre. 8.0 comes from HipHeight + 1 and EntityKill:178; the mesh bottom is 8.30 below the root, so the soles are either 0.3 into the floor or the body stands higher. Every foot target depends on it.
- Where the current Blender file is (name and path on the Windows PC). The two older iCloud copies were not opened (33 MB each would be downloaded).
- Whether the lunge-into-kill hover really happens, and how often a natural lunge fires and from what distance.
- Whether Bone.WorldPosition in JumpscareUI:120 ignores animation (my reading of the Bone API: only TransformedWorldCFrame includes it). If so the kill camera already aims at the rest head position.
- Whether EditableMesh can read this mesh's skin weights for a Blender preview (not tried: Studio is short of memory). The FBX route is the fallback.
- Finger curl axes per bone (rest frames differ per finger; compute, do not assume).
- Streaming radii (the properties are not readable from the sandbox).
- How any of the new poses look on the real mesh: nothing was authored or rendered.

## test_plan

OFFLINE (build_clips.py asserts, every build)
- Stance: planted toe speed relative to root = -authored speed within 0.3 studs/s; toe and ankle never below the floor; hip-to-ankle <= 3.86, shoulder-to-wrist <= 4.10; knee flexion >= 3 deg.
- Loop: pose delta from last frame to frame 0 no larger than 1.5x the mean per-frame delta; contacts at phase 0 and 0.5 in all three gaits.
- FK of the exported data equals Blender's pose_bone heads within 0.001.
- Contact sheets: side, front, three-quarter at phases 0, 0.08, 0.25, 0.38 and the six lunge keyposes.

STUDIO, STEP 1: parity (Edit or a play session, Client). Write three exported poses to the bones and compare LeftToeBase, RightHand, Head TransformedWorldCFrame with rig_math: within 0.02 stud.

STEP 2: measure FLOOR_UP once in a Level 1 round (Server): root.Position.Y minus a downward raycast that excludes the entity. Feed it to the build.

STEP 3: test rig, no round. Play session on the lobby server; Server: clone ServerStorage."Lobby Stored Level 1 Entity" into Workspace as "Entity", root anchored, and step its CFrame along the road at exactly 8, 17 and 27.2 studs/s; set workspace EntityState by hand. Client probe, bound after the layer (RenderPriority.Last): record LeftToeBase / RightToeBase TransformedWorldCFrame.Position and root position for 6 s.
- Foot slide = horizontal toe speed while the toe is within 0.12 of its lowest height: mean < 0.6, p95 < 1.5 studs/s at all three speeds. Run the same probe with L1EntityMotionOff = true for the baseline (expect several studs/s).
- Step interval from stance starts: 0.60 / 0.40 / 0.34 s within 0.03; L1EntityStep changes within 0.04 s of each measured contact.
- Gait changes 8 -> 17 -> 27.2 -> 0: largest per-frame bone rotation <= 12 deg at 60 fps.
- Pictures: L1EntityMotionDebug at each phase, camera parked beside, in front and three-quarter (BindToRenderStep at Camera + 5), ScreenGuis hidden, body standing near so the lights draw; screen_capture one call at a time.

STEP 4: real Level 1 round (Client ConfigureQueue on queue 101)
- Patrol: foot-slide probe on the natural lurk; step sound audible on contacts (read L1EntityStep against the Sound's Playing).
- Chase: stand in sight; probe at 27.2; read the script's Gait and Weight attributes.
- Lunge: with the optional hook, TestForceEntityLunge at 10 and at 26 studs. Log at 60 Hz: time, root height above floor, horizontal speed, layer Phase. Pass: windup within 2 frames of the EntityLunge change; flight pose within 0.10 s of launch; land within 0.05 s of touchdown; never "land" above 0.5 studs; locomotion again within 0.35 s; no old lunge track playing (Animator:GetPlayingAnimationTracks on the Server).
- Lunge into the player: while EntityKillActive read entityRoot.Position.Y minus floor. Expect standing height; more than 0.5 above it confirms the hover.
- Howl, pit yell, kill, cancelled kill (shield): layer Weight is 0 throughout; kill camera and death at 4.13 s unchanged.
- Round end and a second round: Workspace.Entity leaves and returns, the layer re-binds, console clean; EntityAnimation's ReleaseAnimations still runs.
- Level 2 or 3 round: the layer is idle (no Workspace.Entity).
- tools/tests/test_level1_entity_animation.py after repointing; studio_compile_probe.luau for the four edited scripts.
- Final look as a player: own camera, full quality, HUD on, with ReduceCameraShake both off and on.

## changes

- [tooling] tools/level1_entity/dump_rig.py (new) :: whole file
  One Edit execute_luau: every Bone under Workspace.Entity.char1 (or the stored copy) with parent and CFrame components, mesh offset in root space, HipHeight; writes rig.json.
- [tooling] tools/level1_entity/rig_math.py (new) :: whole file
  numpy FK on arbitrary rest frames, world-delta to Bone.Transform conversion, two-bone IK for legs and arms, foot and finger helpers; self-test against the rest joint positions in rig.json.
- [tooling] tools/level1_entity/build_clips.py (new) :: whole file
  Blender-headless generator for Walk, Prowl, Run, Lunge_Windup, Lunge_Flight, Lunge_Land: procedural IK gait plus keyposes, asserts (reach, stance foot speed, loop continuity, no knee hyperextension, nothing under the floor), clips.json, keyframes_v4/*.json, .blend, contact sheets.
- [data] tools/level1_entity/install_clips.py (new) :: whole file
  Creates ReplicatedStorage.Level1EntityMotion.Clips and one StringValue per clip via tools/level6_playground/import_to_studio.Studio().luau; reads back lengths.
- [client layer] StarterPlayer/StarterPlayerScripts/Level 1 Entity Motion.LocalScript.lua (new) :: whole file
  The client override layer described in the design: clip decode, distance-matched gait blend, lunge phase machine, weight against the Animator pose, footfall attribute, debug attributes. Create in Studio first (Instance.new + UpdateSourceAsync; if refused, take over an obsolete disabled LocalScript), then add the manifest item.
- [server guard] ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua :: after line 24 (new constant) and lines 222-224 (EntityLunge handler)
  local CLIENT_MOTION = game:GetService("ReplicatedStorage"):FindFirstChild("Level1EntityMotion") ~= nil; handler returns early when CLIENT_MOTION. Nothing else changes.
- [audio sync] StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua :: entity step loop, inside the Heartbeat callback around lines 765-789 (state kept in the existing closure, no new top-level local)
  If workspace:GetAttribute("L1EntityStep") ~= nil: play the existing step block when the value changes and return before the timer. Timer path unchanged when the attribute is nil.
- [shake sync] StarterPlayer/StarterPlayerScripts/EntityShakeController.LocalScript.lua :: lines 101-108 (stomp timer), one new local beside line 56
  Same switch: a changed L1EntityStep adds the stomp impulse; otherwise the STOMP_*_INTERVAL timer. The ReduceCameraShake gates stay as they are.
- [tests] tools/tests/test_level1_entity_animation.py :: line 13 (SOURCE), lines 190 and 206
  Point SOURCE at the mirrored EntityAnimation file and expect no lunge track when the motion folder exists.
- [optional] ServerScriptService/Level 1 Systems/EntityAI.Script.lua :: lines 990-1002 (Studio-only hook)
  Optional test aid: make TestForceEntityLunge go through the real wind-up (lungePhase = 1, lungeWindupUntil = now + LUNGE_WINDUP, bump EntityLunge) instead of launching directly.
- [optional, needs the test first] ServerScriptService/Level 1 Systems/EntityKill.Script.lua :: runKill, lines 122-128
  Only if the hover is confirmed by test: after anchoring, raycast the floor (code already at 168-181) and put the entity root at floor + standing height before killBaseCFrame is taken.
- [docs] README.md :: line 173 paragraph and the animation pipeline bullet at 659-662
  Describe the motion layer, the new tool folder and that Walk/Prowl/Run/lunge are data clips.

## key_locations

- ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua : 5-24 : ANIMATION_IDS and tuning: WALK_ANIM_SPEED 9, RUN_ANIM_SPEED 15, speed clamp 0.08-2.5, fades 0.25 / 0.12, speed smoothing 0.10, move thresholds 0.55 / 0.18
- ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua : 119-182 : captureGaitPhase, stopLocomotion, switchLocomotion (phase carry by TimePosition, 154-156), playAction (kill guard 162, Watch under actions 173)
- ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua : 195-224 : PlayHowl / PlayYell / PlayKill / CancelKill events; EntityLunge attribute plays LungeFromRun (222-224)
- ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua : 226-284 : cleanup and ReleaseAnimations contract (239-249); Heartbeat state-to-clip mapping and playback speed (257-284)
- ServerScriptService/Level 1 Systems/EntityAI.Script.lua : 198-217 : SPEED_LURK 8, SPEED_INVESTIGATE 8, SPEED_CHASE 27.2, SPEED_LOST 17; LUNGE_RANGE 28, WINDUP 0.32, SPEED 62, UP_SPEED 42, MAX_TIME 0.82, RECOVER 0.35, COOLDOWN 10, CHANCE 0.35
- ServerScriptService/Level 1 Systems/EntityAI.Script.lua : 959-1101 : launchBallisticLunge (959-974); lunge Heartbeat: Studio hook TestForceEntityLunge (990-1002, skips the wind-up), flight and its three end conditions (1016-1039), wind-up freeze and faceFlat (1061-1070), recover (1075-1080), roll and EntityLunge bump (1085-1099)
- ServerScriptService/Level 1 Systems/EntityAI.Script.lua : 1218-1378 : main loop: ALERT howl hold 2.2 s (1241-1283), chase / track / pit-yell speeds (1308-1340), search / investigate / lurk (1355-1371), published EntityState incl. TRACK and YELL (1374-1377)
- ServerScriptService/Level 1 Systems/EntityKill.Script.lua : 13-15, 105-198, 228-232 : KILL_DURATION 5.0, DEATH_AT 124/30, CAPTURE_DISTANCE 3.7; runKill: anchor and pivot (122-128), PlayKill (139), crouch tween at 1.05 s (151-155), victim pull and pin (156-187); Touched on every part
- StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua : 35, 104-105, 698-716, 721-790 : LUNGE_SOUND empty; STEP_WALK_INT 0.53 / STEP_RUN_INT 0.34; lunge telegraph hook; entity step timer loop (cadence chosen at 769)
- StarterPlayer/StarterPlayerScripts/EntityShakeController.LocalScript.lua : 27-28, 56, 101-113 : STOMP_CHASE_INTERVAL 0.34, STOMP_TRACK_INTERVAL 0.53 and the stomp timer; ReduceCameraShake gates at 73, 160, 187
- StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua : 112-132 : kill camera looks at the entity's Head bone (WorldPosition) from the victim's head
- ServerScriptService/GameManager.Script.lua : 758-790, 1812, 1914 : setLevelOneEntityActive: invokes EntityAnimation.ReleaseAnimations, parks the entity in ServerStorage as 'Lobby Stored Level 1 Entity', toggles EntityAI / EntityAnimation / EntityKill
- ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua : 70-71, 1598-1599, 2466 : EntitySpeedMul: +0.06 per fuse capped at 1.1, 1.3 when the exit opens
- ReplicatedStorage/MasterConfiguration.ModuleScript.lua : 96-100, 109-110 : L1_EntityChaseSpeed (8-60), L1_EntityLurkSpeed (2-30), L1_EntityLungeChance: owner-tunable, so gait speeds are not fixed constants
- tools/export_entity_keyframes_retargeted.py : 28-40, 246-255, 318, 337-339 : clip list and Blender action names; Watch frame 0 as the rest reference; 1.25-stud Hips clamp; loop-tail easing. Defines the keyframe JSON format (= Bone.Transform per bone per frame)
- tools/publish_entity_animations.py : 54, 88-143, 155 : scripted publish: KeyframeSequence in ServerStorage.MongoTVEntityAnimations then AssetService:CreateAssetAsync(..., Enum.AssetType.Animation, group 1039373905); Windows-only transport
- tools/build_corrected_entity_actions.py : 72-100 : the live run is the damped walk time-scaled x0.62 with amplified thighs, knees and arms
- tools/build_restrained_walk.py : 28-55 : the live walk: per-bone damping that froze the upper body
- tools/level6_entity/rig_math.py : 1-150 : reusable pattern: FK, frame(), two-bone solve_arm, asserts, in plain Python (identity rest frames there; Level 1 needs the rest CFrames)
- tools/level6_entity/build_dance.py : 48-70, 145-162 : clip dict format {frames, fps, loop, bones{name: flat int quats x10000}, hips x1000} and the StringValue install through import_to_studio.Studio().luau
- StarterPlayer/StarterPlayerScripts/Level 6 Playground Client.LocalScript.lua : 1140-1199, 1344-1400 : reference player: clip decode, rig lookup that survives streaming, per-frame Bone.Transform write with crossfade and stride-based rate
- StarterPlayer/StarterPlayerScripts/Level 4 Round Client.LocalScript.lua : 846-914 : Usher: client-side Motor6D.Transform player whose phase advances by observed speed / reference speed
- tools/tests/test_level1_entity_animation.py : 13, 159, 190, 206 : harness reads drafts/level1-quality-20261002/EntityAnimation.Script.lua (absent in the mirror), pins the eight asset ids and exercises EntityLunge
- /tmp/l1batch/anim (scratch, mine) : rig.txt, fk.py, axes.py, gait.py, lunge.py : Studio rest rig (body bones), numpy FK verified against Studio, axis table, stride-feasibility check, clip timing tables; plus the nine published keyframe JSONs extracted from git
