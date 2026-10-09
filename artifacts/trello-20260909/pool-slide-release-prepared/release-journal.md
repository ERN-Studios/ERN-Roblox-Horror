# Pool Slide release journal — v1839

**Mouse-published as v1839 on 10 September 2026 at 08:31:17.844/.885 Europe/Copenhagen; final independent functional score 8/10.** The saved `pool-slide-published-v1839.jpg` visibly confirms both successful publication and the v1839 publish-notes link. Root completed 122/122 compilation, an Edit audit with temporary Play helpers absent, and an immediate post-publication source audit of 122 matched / zero drift (the existing Level 2 Lighting LF-only difference remains allowed). The fresh release-guard encounter used `StudioValidationMode = false` and both verification flags true. Root installed the accepted template/config in Edit before publishing. This journal's author only read saved evidence and updated documentation; no Studio or runtime mutations were made by this author.

`release-manifest.candidate.json` is the reconciled machine-readable journal. It preserves the original pending manifest, five baseline source hashes, exact candidate config hashes, per-file evidence hashes, complete pump/observation summaries and explicit remaining steps. `prepare_release_journal.py` reproduces the reduction and refuses to overwrite later guard/publication evidence.

## Accepted candidate identity

| Clip | Newly published animation ID | Native/authored length | Native parity cases |
| --- | ---: | ---: | ---: |
| Idle | 116085684636171 | 4 s | 3 |
| Walk | 140239794149902 | 1.0333333015441895 s | 10 |
| Run | 101625402038627 | 0.6333333253860474 s | 3 |
| Attack | 121778490512649 | 1.2000000476837158 s | 6 |

All four IDs agree between `pool-slide-published-contact-assets.json`, `pool-slide-contact-asset-owners.json` and `pool-slide-published-native-parity.json`. Each is asset type 24, owned by **ERN Roblox Studios, Group 1039373905** (`CreatorTargetId`; do not substitute the separate metadata `creator.Id`). All four upload records say `ok=true, reused=false`. The Run display name is filtered in metadata; its numerical ID, ownership and native playback still match.

The authored source is `ServerStorage.PoolSlideContactAnimations_20260910`, revision `contact-quarter-20260910`. Walk is the contact-corrected quarter-loop curve, not a runtime phase seek. Idle/Run/Attack retain their reviewed corrected curves, and Attack retains one Contact marker at authored 0.5 seconds. Inherited old `PublishedAssetId` values were retired before these genuine uploads; the earlier reused Idle ID is excluded from this candidate.

Native published-vs-authored comparison passes **22 phases / 440 bone pairs**, at one playing track per side with weight/target 1. Maximum position difference is **0**, angle difference **0.0006905339541845024 rad**, and seek error **1.3580322311135262e-08 s**. Running Attack produced exactly one Contact event on each side, both at **0.5000001788139343 s**. Both comparison clones were cleaned up. This is finite native pose/marker parity, not a new full-skin or moving-navigation proof.

## Template and source provenance

The candidate derives from the original scale-4 `ServerStorage.Level2Assets.Level 2 Pool Slide Template`, cloned and scaled through `ScaleTo(6)`. Its accepted parameter proposal is:

| Field | Value |
| --- | ---: |
| Model scale | 6 |
| GroundOffset | 6 |
| AgentRadius / AgentHeight | 7.5 / 16.7 |
| AnimatedEnvelopeRadius / AnimatedEnvelopeHeight | 7.3 / 16.1 |
| Walk / Run animation reference speed | 10.82 / 27.6 |
| Walk / normal run / enraged speed | 10 / 20 / 32 (unchanged) |
| Attack windup / recovery / cooldown | 0.5 / 0.7 / 2.4 s (unchanged) |

The saved scale-6 native full box has pivot-centred radius **6.095187664031982**, Y **−6 to +6**, height **12**, GroundOffset **6**. The independently reviewed valid sample union is radius **7.21915864944458**, Y **−6.301979064941406 to +9.71185302734375**, global height **16.013832092285156**. Rounding to 7.3/16.1 satisfies the unchanged controller's +0.1/+0.3 margins inside agent 7.5/16.7. See `sampled-envelope.md` and `.json` for exact inclusion/exclusion, source hashes and the **9/10** independent reduction review. These are sampled bounds, not a continuous-time upper-bound proof.

The initial Play installer is saved as `../install-pool-slide-candidate-play.luau`: quiet-lobby checks, exact source fingerprints, scale-4/false-flag original preflight, preserved originals, scale-6 clone, the published revision/ID gate, full-box offset validation and four fresh ModuleScript identities. Generator/Adapter/Controller sources are unchanged; only Config differs. The initial installer uses validation mode and false verification flags. Root's later true-flag/false-mode guard candidate is distinct and its completed report is recorded below. Do not claim this historical installer file itself is the later guard result.

The production config SHA256 is `600ff29d74a931b358d4817506f5aaee2e046a26f25aecf5367a312d8f267703`; initial Play config SHA256 is `af83d1777dbcec4836db750fd53e0043310b80e3fb7566c79032f64f68002cf4`. Their only difference in runtime fields is StudioValidationMode. Production's source delta is exactly Enabled false→true and the two reference speeds. At the final journal update, the local config matches the accepted release hash and the other four tracked sources still match their original baselines; this author made no source writes.

The saved `pool-slide-template-edit-readback.json` confirms root's actual Edit installation, accepted four IDs, scale 6 and all seven intended attribute values including both true flags. It retains the entire original scale-4 model at **`ServerStorage.TrelloPoolSlideReleaseBackup_20260910`**. Independent numerical comparison confirms the same 105 descendants, identical model pivot, the same 20 Bone and two Motor6D keys, expected 1.5 position scaling with unchanged rest rotations to under 1e−6 per component, and all unrelated attributes unchanged. The inherited `SourceSHA256` attribute is preserved import provenance; it is not presented as a hash of the new animation bundle. Root's final audit confirmed source parity and absence of temporary Play helpers; its successful post-publication audit is recorded above. Historical raw Edit/Play evidence retains its original pre-publication state.

## Normal lobby queue evidence saved so far

Root observed ordinary lobby queue entry. Each report begins in the actual generated round with real player **40920547**, zero pumps/models, Controller running, and `EntityPaused=false`. The helper uses the existing DebugActivatePump with real-player distance/LOS validation. Root positions the actual player externally between stations and before the chase window; these are not claimed as uninterrupted manual walks between every pump. All three saved reports use **StudioValidationMode=true**, so they do not prove the final release guards.

| Seed / generation | Saved pump progression | Entity and movement evidence | Cleanup |
| --- | --- | --- | --- |
| 1003919623 / 1, **partial** | 3 accepted; 3 repeat rejected; 1 accepted | Zero/one pump: no entity. Second distinct pump: exactly one ACTIVE entity, SpawnCount 1. About 18.954 studs of model movement recorded. Player died with AttackSerial 0; no Pool Slide attack attribution and no third-pump evidence on this seed. | Passed; old model/world unparented, manifest cleared, Controller stopped, zero tagged models. |
| 651224003 / 2 | 2 accepted/repeat rejected; 3 accepted/repeat rejected; 1 accepted | Second distinct pump creates one entity; third produces ENRAGED on the same model ID 1 with SpawnCount 1. The later 20-second window records **zero** model travel and player death with AttackSerial 0, so this is not moving-pursuit or Pool Slide kill proof. | Passed, including model/world/manifest/controller/tag cleanup. |
| 341095071 / 3 | 1 accepted/repeat rejected; 2 accepted/repeat rejected; 3 accepted | Same count/identity/enrage behavior. The 20.010-second nearby clear-floor chase window records **64.64874358440531 studs** of actual model travel, net **64.6487435835323**, 168 samples, no identity changes or large-step flags. AttackSerial rises to 1; an ATTACK-state sample targeting player 40920547 records **100→0 HP**. Root also observed the actual attack. | Passed, including model/world/manifest/controller/tag cleanup. |

The reports' `ExpectationsPassed=true` means their specified counter/identity/phase and duration conditions passed. It does **not** turn the stationary second-layout window into successful navigation. The third-layout trace proves actual local pursuit and attack on that path; it is almost straight by its path/net distances, so it does not establish all corridor turns, all routes or uninterrupted movement on all three layouts. Model ID 1 is local to each report and is not a claimed shared instance across different rounds.

The first two HP drops are retained as unattributed to Pool Slide. No fake second player, dummy attack, health write, forced entity movement or fabricated cleanup is represented by this journal. All cleanup reports return to a normal lobby state with Controller stopped and zero runtime models.

## Final normal encounter with release guards

`pool-slide-acceptance-1660039617-generation1.json` is **518,728 bytes**, SHA256 **`6ce847d68d18579631c8beda76d3859e9b8f7f5c8f864385102ce5b8eb592ab7`**. It records a fresh normal round with Enabled true, StudioValidationMode false, published runtime `ValidationOnly=false`, Controller running and no error. Root supplied both true verification flags; the unchanged Controller successfully started and spawned under its release checks.

Pump order **1, repeated 1, 2, repeated 2, 3** behaves correctly: repeats are rejected without changing the count, zero/one pump has no model, the second distinct pump creates one entity, and the third makes the same model ID 1 ENRAGED with SpawnCount 1. All bounded windows completed and passed their specified expectations.

The local pursuit window lasts **20.02588200569153 seconds** over **153 samples**, with real model path distance **118.20130594300146 studs**, net displacement **52.28761351863408**, no identity changes and no large-step flags. AttackSerial rises once to **1**. An ATTACK-state sample targeting player 40920547 records **100→0 HP**. All five actual Pool Foam entities are captured around that hit; the nearest is **975.6944652603395 studs before** and **974.0575288185811 studs after**, supporting attribution to the nearby attacking Pool Slide instead of the earlier ambiguous deaths. This is actual local moving pursuit/attack evidence, not proof of every corridor route.

Normal cleanup passes: original world and entity are unparented, Adapter manifest is cleared, Controller and Foam are stopped, zero tagged/runtime models remain, SelectedLevel is 1, RoundActive/WorldGenerated are false, and the real player is back outside the round at 100 HP. The helper's `Published` object records runtime state attributes and does not mean the place was published.

## Final acceptance and disclosed limitations

Animation candidate, pending release runbook, diagnostic observer and sampled-envelope reduction each received independent **9/10** reviews in their own scopes. Three valid fade cases retain brief skin/plane penetration (worst −0.221979 studs); `contactPass` remains false. The animation review treats these as a disclosed cosmetic blend limitation pending actual viewing, not perfect planted feet. These scores do not substitute for final whole-feature acceptance.

The independent `pool-slide-final-functional-review.md` accepts this bounded second-pump/larger-entity delivery at **8/10**. It independently traces the 16-waypoint detour, attack attribution and normal cleanup. It also discloses approximately **8.909 seconds of initial route-planning delay** before the first installed path after player staging, plus the brief blend dips above. This is functional acceptance with those limitations, not immediate pursuit, universal routes, multiplayer or perfectly planted-foot certification. The first saved seed remains partial and the second saved pursuit remains stationary as recorded above.

Publication and final source verification are complete. Root used **File → Publish to Roblox with the mouse**; native Output reports success at **08:31:17.844** and completion at **08:31:17.885**, version **1839**, on 2026-09-10 Europe/Copenhagen. The screenshot was independently viewed for this journal. No release claims are made for the intervening versions 1836–1838.

Independent Trello readback confirms [second-pump feedback](https://trello.com/c/GdkBpbkc) is Done, complete=true and archived; [larger Pool Slide/tunnels](https://trello.com/c/KcUdv690) is Done, complete=true and unarchived. Raw card/checklist evidence is saved in `../trello-reconcile-20260910-card-details.json`; the final full-board snapshot is `../trello-reconcile-20260910-final.json`. No Trello mutation was performed by this journal's author.

Existing servers keep the old disabled version until their own lifecycle ends. No old-server restart or additional rollout change is claimed. `config.before.lua` and the original scale-4 model remain the rollback pair.
