# Pool Slide third-pump integration — 2026-08-31

## Installed and verified; not publicly published

ESP follow-up: see `ESP_VERIFICATION.md`. The giant now materializes while
developer pause is enabled, but remains frozen; dedicated named cyan ESP and
pump/spawn status are installed. The updated controller passes28/28 regressions.
The earlier24-case results below describe the initial integration revision.

Target: **BACKROOMS: STAY QUIET [CO-OP HORROR]**, place **131311258779917**, universe **10559217407**. The user confirmed this target with “DO IT”.

The clean, vivid Pool Slide humanoid is installed as a separate 16-stud entity. It spawns once per Level 2 round when the **third distinct pump lever** is activated, regardless of station order. The existing second-pump Slidemouth and third-pump escalation remain separate and unchanged.

## Installed assets and scripts

- ServerStorage.Level2Assets.Level 2 Pool Slide Template: 7 skinned mesh parts, 24 shared Bones under RootPart, 47,749 triangles, 16-stud height, measured radius 7.60017 and ground offset 0.15981.
- ReplicatedStorage.Level 2 Assets: Pool Slide Idle / Walk / Run KeyframeSequences, 121 / 32 / 20 frames.
- ServerScriptService.Level 2 Systems.Level 2 Pool Slide Controller: authoritative spawn, movement, eligibility and damage.
- StarterPlayer.StarterPlayerScripts.Level 2 Pool Slide Client: local Bone.Transform animation, streaming discovery, transitions and pause.
- Level 2 Round Adapter: six-line lifecycle integration. Original live source preserved in ServerStorage.Level 2 Pool Slide Import Backup 20260831.
- Original raw import also preserved in that backup folder. Final template has clean vivid textures, white mesh tint, dark metal bolts and round tube-end feet. No new Meshy generation was needed.

## Live test results

| Requested seed | Resolved layout | Pump order | Trigger result |
|---|---:|---|---|
| 101 | 101 | 3 → 1 → 2 | Absent at counts 0–2; one 24-bone giant at count 3; same Slidemouth instance |
| 202 | 2199511 | 1 → 2 → 3 | Passed; 77.7-stud spawn separation, 482 route queries |
| 303 | 942864 | 2 → 3 → 1 | Passed; 103.7-stud spawn separation, 320 route queries |

The generator's normal validation selected fallback layouts for requested seeds 202 and 303; the table reports actual resolved seeds, not an assumed seed.

- Seed101 live chase: 120.09 studs accumulated travel / 104.23 displacement in six seconds; client run Bone changed on all18 samples.
- Resolved2199511 live chase: 77.96 studs accumulated travel; one entity retained; tester alive.
- Full Adapter cleanup passed on resolved2199511: zero giant models/private candidates, both controllers stopped, generated world removed, own chase marker cleared. Fresh subsequent Play rebuilt successfully.
- Idle, Walk and Run deformation inspected visually on the actual imported rig. Runtime run playback verified; runtime Walk observed on12/12 changing Bone samples.
- **24/24 isolated controller regression checks passed** against the final source. Eight retarget tests and 4,152 actual-target global Bone-pose checks passed.
- Final four repository script files compare byte-for-byte equal to Edit Studio Source after testing. No QA preview objects or scripts persisted into Edit.

Two live issues were corrected during implementation: pump-plinth-adjacent players now admit a fully certified visible spawn approach within24 studs (actual attack reach remains5.5), and concealed distant anchors no longer outrank every nearby visible anchor. Body/route collision checks, minimum60-stud separation from every living participant, vertical reach and attack LOS remain enforced. Seed101's chase proof predates only the final candidate-ranking refinement; final-source seed202/303 and the ranking regression passed.

## Scope and test limits

This was single-client Studio Play, not a real multi-client/device or public-server load test. The separate controlled walking test on resolved942864 ended with tester death, so its subsequent living-tester cleanup helper refused; this is **not** counted as a movement/cleanup pass. No cause of that death was established. An existing Slidemouth over1024-stud shapecast warning occurred during cross-level QA teleports; Slidemouth code was not changed. All disposable Play changes were discarded.

The public experience was **not published**, and the repository was **not committed or pushed**. Studio displayed its saved-changes confirmation; an additional complete local place copy was created:

/Users/zeanjuul4/Desktop/Backrooms_Stay_Quiet_Level2_PoolSlide_Entity/Backrooms_Stay_Quiet_ThirdPump_2026-08-31.rbxl

## Repository and recovery

Repo: github/ERN-Roblox-Horror. The new controller/client, small live Adapter integration and preexisting live Navigator dependency were mirrored narrowly; unrelated marketing description and LobbyMusic changes were preserved. The Navigator snapshot is large because GitHub was stale, not because the giant rewrote that live module.

assets/level2/poolslide contains the actual asset IDs, complete template reconstruction data, keyframes, a checksummed source pack and a non-overwriting reconstruction helper. The source pack verifies across21 parts; nine safe-restore tests pass. JSON rig reconstruction is syntax-checked but has not been visually reimport-tested; the native full-place backup is the definitive saved copy.
