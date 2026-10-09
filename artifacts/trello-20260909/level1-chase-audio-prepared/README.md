# Level 1 chase audio: local spatial warning

Trello: https://trello.com/c/2GlQSXUc. The card asks that when another player is spotted, nearby players hear the direction of the chase, loudness decreases with distance, and very distant players hear nothing. This is one source proposal only; no runtime, Studio, audio upload, asset generation, pricing or Pool Foam work.

## Source finding and scope

The actual chase **loop** already satisfies the structural contract: `SoundController` binds ChaseSound to Entity.HumanoidRootPart, with InverseTapered rolloff10–200studs. Every eligible Level1 player's client follows the global EntityState; it is not restricted to the BeingChased target. CHASE fades in over0.6s; TRACK withdraws over5s. These existing loop properties, bindings and timings are unchanged.

The **first-spotted cue** is the concrete map-wide difference. SpotScream uses Linear rolloff60–2200studs and its attribute listener has no round/participant gate. EntityAI publishes the stationary howl's world position before EntitySpotScream; clients can create a tiny local world emitter there even if the far-away entity has not streamed in. The old2200stud range intentionally covered the whole map. This is the likely cue behind the reported global chase warning; that identification is a source-based inference, not a claim that the reporter's exact audio was reproduced.

The proposal changes that cue to10–200studs, matching the loop's audible range. It moves the existing `chaseActive` helper earlier and also uses it to gate the cue: Level1, RoundActive, InRound and not Escaped. Nearby teammates still receive the same spatial event even when they are not the target. There is no special map-wide exception for a distant chased player, consistent with the new requirement that far-away audio be silent. Peak volume, asset IDs, authoritative source position, deduplication, preload and cleanup remain intact. Death/yell/distant scream/footstep/music channels are outside this change.

The separate2D ALERT_SOUND siren is driven by `LightMode` from PuzzleManager's completed fuse/power stage, not EntityState detection. Its global puzzle warning is preserved. This distinction matters when listening: the card's first-spotted cue is82272419363488 and the chase loop is79246919959914; the unrelated puzzle siren is118863512220494.

Roblox documents distance attenuation and direction from the listener to BasePart/Attachment sounds; RollOffMaxDistance caps their audibility. See [Sound objects](https://create.roblox.com/docs/sound/objects) and [Sound reference](https://create.roblox.com/docs/reference/engine/classes/Sound). These contracts support the chosen source arrangement; they do not establish the perceived stereo mix of this particular clip without listening.

## Baseline and verification

Runtime SoundController raw/LF SHA `0675083878fde8e6f0a8b9220e1c5abeda417e81b14a40c652a5e4045f46f5e5` matches its saved Studio-sync manifest record with status `synced`. This preparation did not query or mutate Studio; the match is to the recorded audit, not a fresh live read. `manifest.json` preserves that exact record and the proposed hash. `before/` is immutable; `prepare.py` writes only `proposed/`, manifest and diff and refuses a changed baseline.

Run `python artifacts/trello-20260909/level1-chase-audio-prepared/test_audio.py`: **30 actual-source checks**, the original2200stud negative control and a complete SoundController compile pass. Checks execute the actual eligibility, spot-cue function and complete unchanged chase binding/state block with mocked Roblox objects. They inspect spatial parent/authoritative position/ranges, nontarget eligibility, lobby/other-level/escape rejection, duplicate suppression, holder cleanup, ordinary CHASE/TRACK transitions and entity replacement. Every authored SoundId and the complete loop block are independently compared with the baseline. Mock tweens set their target immediately; native fade/audio perception is not simulated.

## Focused native handoff

Root should first confirm the latest live source matches the recorded baseline, then apply this one-file proposal after the current feature's separate publication. In a normal Level1 round, trigger the existing detection while the listener is not the targeted player. Listen from left/right,10studs, midrange and comfortably beyond the200stud part boundary (for example250studs); compare the initial cue and subsequent chase loop, and verify they move with the existing source semantics. The stationary initial howl may use its authoritative snapshot; the moving loop follows the entity root.

Check a near teammate can hear another player's chase, a far listener cannot, and lobby/other-level/escaped states do not start this cue. Confirm no duplicate first-spotted cue, ordinary tracking fade, cleanup and replacement. Actual multi-client listening is the strongest evidence; a single-client Scriptable-camera/listener probe must be labelled accordingly. No native audible acceptance or publication is claimed here. Independent review is **9/10**; see independent-review.md.
