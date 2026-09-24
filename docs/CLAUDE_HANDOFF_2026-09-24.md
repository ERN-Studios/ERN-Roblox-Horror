# Claude → Codex handoff — 24 September 2026

Branch `claude/trello-20260921`, draft [PR #8](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/8). The changes described here went into Studio through the verified compare-and-swap push (`tools/push_repo_to_studio.py`) against a fresh Source/editor baseline and were then mirrored. The owner published **v2083**; [the read-only receipt](../artifacts/publish-v2083-20260924/README.md) confirms all 182 mirrored scripts and the Level 2 wall-decal removal in its binary. The [v2081 receipt](../artifacts/publish-v2081-20260924/README.md) separately confirms the Pool Slide animation IDs. Upgrade-cost card KF7FDmP1 is Done after owner approval, published purchases, persistent DataStore readback, owner-confirmed new-server load and an offline insufficient-balance guard; the remaining Testing cards retain their live/physical or owner-acceptance gates.

Fresh Trello triage on 24 September moved eight code-implemented cards from To Do to Testing, preserving their verification gates. The rejected [Level 2 wall-depth card](https://trello.com/c/DDqjXkyU) remains To Do. The [Level 3 larger/maze-like map card](https://trello.com/c/3hEkFVUe) subsequently moved to Testing after the maze change and native QA. After the upgrade-cost card closed, Testing contains 14 cards. The [Level 2 render/nearby-loading review](LEVEL2_RENDER_STREAMING_REVIEW_2026-09-24.md) records the 64/1024-stud radii found in v2081 and a measured next-experiment sequence; no streaming or LOD setting was changed.

Final parity (end of session): 182/182 scripts match Studio `.Source`, 182/182 editor sources equal `.Source`, manifest 197/197 `synced`, no stray QA instances or attributes left in Edit.

**Studio non-script changes** (additive; no pre-existing object deleted or overwritten):

| Path | Change | Native export |
| --- | --- | --- |
| `ServerStorage.Level2Assets."Level 2 Pool Slide Template"` | Now x1.1 of the verified scale-6 rig (see Pool Slide) | `artifacts/claude-20260924/Level 2 Pool Slide Template (1p10, 20260924).rbxm` |
| `ServerStorage.Level2Assets."Level 2 Pool Slide Template (pre-1p10 backup 20260924)"` | The previous live template, renamed only (scale 6, untouched) | recoverable from v2061 |
| `ServerStorage.HazmatSkin_SignalArchitect_20260924` | Clone of Baseline Yellow template, `Scene.char1.SurfaceAppearance.ColorMap = rbxassetid://137400739559825` | `artifacts/claude-20260924/HazmatSkin_SignalArchitect_20260924.rbxm` |

Claude did not take a full `.rbxl` backup during that session (the desktop "Download a Copy" route was declined). Codex later saved the native place as `artifacts/poolslide-20260924/saved-place-v2074.rbxl` before changing the Pool Slide animation IDs. The two `.rbxm` exports and published v2061 remain separate recovery points; [v2081](../artifacts/publish-v2081-20260924/README.md) is the newer published snapshot.

## Cards

| Card | Commits | Studio evidence | Still required before Done |
| --- | --- | --- | --- |
| [EYpXKa9S completion save](https://trello.com/c/EYpXKa9S) | `8e623de`, `d50033f` | Real Level 1 round: one save with record/challenges in the same write; duplicate round ids through the real bindable answer "Level clear saved." without paying. Offline `test_completion_save.py` 61 (fail-before-commit, lost-response, duplicate, backoff, leave-time flush while unparented, outage, 5x tier). | Live DataStore: a clear with a forced failure and rejoin on a published server. |
| [PuuOYhmH LEVEL 1 START HERE](https://trello.com/c/PuuOYhmH) | `d4ae70e`, `e3f5bec` | Play with `DevSimulateFirstLogin`: no guide, marker, START HERE/THIS WAY/TRY AGAIN text or cyan beam. Script kept as a retired stub (no-delete rule). Published in v2081. | Published lobby check; Roblox Player playtest was skipped at the owner's request. |
| [x4kKwPZx standing viewer](https://trello.com/c/x4kKwPZx) | `623264b`, `1d7255d` | 3D preview stands for all six (hands 1.63–1.64 studs below shoulders); SKINS cards now use your six standing portraits (loaded in Play). | Published visual check desktop + touch. |
| [EtdsUM4e Token Earner](https://trello.com/c/EtdsUM4e) | `91106da`, `d50033f`, `66ddc5a`, `cb762f2`, `c6cbbc7`, `8937264` | Studio (all passes granted) tier 5: clear +2 +8; at 2x +2 +2; 2x owner sees 3x 150 / 5x 250; wheel Token3 at 5x paid 15 with `PaidTokens`; non-owner sees COMING SOON on all three cards (passes off sale). The residual automatic-earnings fix is published in v2081 and keeps a durable bonus pending while ownership is unknown; offline `test_token_earner.py` 383. | Published DataStore outage/clear/rejoin and exact-once bonus; keep passes off sale until the live checks, then test each purchase/upgrade path, rejoin and a claim immediately after join. |
| [rXhi1SZ8 Pool Slide](https://trello.com/c/rXhi1SZ8) | `234c66e` | Template x1.1 (x1.2 failed: AgentRadius 9 made every long enraged plan expire, ~13,000 queries vs 500–1,000). Walk/Run your IDs; reference speeds 13.62/33.74 and `AttackDistance` 11.55 carried by the template. Four rounds: seeds 1182081016, 101, 7331 (runtime swap) and random 813137647 from Edit — spawn ≥100 studs, run, attack, 3rd pump enrages the same entity, 600-stud enraged plan at 32 studs/s. Mouth audio emitter 0.94 studs from `Head`. Published in v2081. | Your uploaded Model `95190427565492` lost Neck/Head (18 bones) and was not used. Foot-slide tuning at 10/20/32 (new Walk dips the foot bone 0.15 below rest) and phone/tablet FPS. |
| [LigItMHi groans](https://trello.com/c/LigItMHi) | — | No code defect found by the audit; emitter follows `Head` on the larger rig. | Your listening test. |
| [SYUaXHKQ developer suit](https://trello.com/c/SYUaXHKQ) | `bc1192b`, `d50033f`, `2469d2d`, `c6cbbc7`, `8937264` | Developer owns/equips Signal Architect; teal texture renders in the viewport. Fail-closed: a Developer suit is never published for a non-developer, even before the revocation write lands. The durable revoke/sync retry compiles in Studio; offline `test_dev_suit_revocation.py` 34. | Non-developer account (no card, forged equip refused), revoke + rejoin, two-client visibility, mobile. |
| [IRLeRBcN skin VFX](https://trello.com/c/IRLeRBcN) | `bc1192b`, `d50033f` | False Sun motes (your parameters/texture) enabled in a round; visible from a third-person camera. The wearer never sees their own (first-person LocalTransparencyModifier) — teammates are the audience. Cleanup is idempotent (`test_hazmat_driver_cleanup.py` 12). The shop preview gets 2D embers from the topper window (ViewportFrames render no ParticleEmitter); 1–2 seen in Play. | Two-client round, phone frame time, ReduceFlashing check. |
| [KF7FDmP1 upgrade cost](https://trello.com/c/KF7FDmP1) | `8ee95f4` | `ZyntraConfig.UpgradeCost(level) = level + 1`; owner approved the ladder. Published Player: two consecutive Stamina and two Battery buys at 12/13 Tokens each, 892→842 balance, next price 14 for both. Read-only Open Cloud DataStore read confirmed persisted 842/13/13; owner confirmed the same after new-server rejoin. Real server branch passed 15/15 isolated Luau checks including insufficient balance with no write/deduction. | Done. Negative path was verified offline, not with a live low-balance account. |
| [DDqjXkyU wall depth](https://trello.com/c/DDqjXkyU) | `644be20` (rejected version), `9a15d4b` (removal) | The two decals were visible in generated halls, and the owner rejected their appearance after v2081 publication. The generator's decal table, placement function and call were then removed; the removal compiled in Studio Edit, and fresh Source/editor readback confirmed both decal image IDs and `placeWallDecals` absent. A scope audit found no remaining Studio script or instance references. The published v2083 binary contains the removal ([receipt](../artifacts/publish-v2083-20260924/README.md)). No replacement is approved. | Brainstorm and approve a new direction before any new wall asset. The wall-depth card stays open. |
| [uI8hg2At controller](https://trello.com/c/uI8hg2At) | `79b42d8`, `d50033f` | Potion D-pad right, markers RT; party panel CREATE PARTY focus + B; result CONTINUE focus; wheel/daily and RoundUI modals take focus when a pad appears while open (your review). Offline suites green. | Physical controller run from `docs/PHYSICAL_QA_2026-09-24.md`. |
| [DIktjy8U loading/teleport](https://trello.com/c/DIktjy8U) | `79b42d8` | Next-level server reserved once per post-win window; unclaimed station TeleportInitFailed lifts the cover; Reset disabled during entry (observed in Play). | Published 2–6 client teleport/rejoin/retry through Level 2→3. |
| [25GLltY6 wheel/daily](https://trello.com/c/25GLltY6) | `79b42d8` | Shop card no longer re-enabled by the wheel's restore; late GET cannot re-arm a pending COLLECT; owned-suit prize reads 3 TOKENS; COLLECTED names `PaidTokens`. | Physical touch; published day rollover/rejoin/once-only payout. |
| [FnF49TWk challenges](https://trello.com/c/FnF49TWk) | `91106da` | Entity Shield now marks the run aided when it activates (was after the finalize write). | Live rejoin persistence; time-goal tuning after 29 Sep. |
| [VSCGGIA9 hazmat skins](https://trello.com/c/VSCGGIA9) | `623264b`, `1d7255d` | Standing preview and card portraits. | Your listed purchase/rejoin/physical gates. |
| [Zpj0Gkbb arches](https://trello.com/c/Zpj0Gkbb) | — | Audit found no code defect. | Physical phone/tablet FPS/memory. |

## Audit record

A read-only audit of six areas found 16 candidate defects; 13 survived three independent verifiers (3/3 each) and are fixed in `79b42d8`/`91106da`; 3 were rejected. Arch culling had none. Three offline suites still fail exactly as at HEAD before this session (`test_item_inventory`, `test_support_product_receipts`, `test_leaderboard_backfill`: stale harnesses, see `docs/WHOLE_GAME_QA_2026-09-24.md`).

## Tooling

`tools/record_pending_push.py --file <path>` (repeatable) records only the named mirrored scripts, so one session can push its own files while another session's edits in the same checkout are mid-flight.

## Codex independent Level 2 QA

- [Pool Slide A/B](POOL_SLIDE_AB_2026-09-24.md): approved, scale-neutral Walk `100254982019982` and Run `80850407466977` had no all-bone rest flashes in the cloned-rig comparison. Codex changed only the live Edit template's two AnimationIds and RigNote; the old sibling template remains. In a generated solo Level 2 round, the entity spawned 141.98 studs away, used Run in chase and Walk at 10 studs/s. A Play-only counter probe selected Run at 32 studs/s. This does not prove the real third pump, sole contact or physical mobile FPS. The native `v2074` backup above predates the AnimationId change.
- [Pool Slide sound](../artifacts/poolslide-audio-20260924/README.md): three disposable rounds showed distant groan before spawn, alert/chase sound from the Head follow emitter, periodic Mouth audio and cleanup after reset. The sound files previously measured as Pool Slide were actually Pool Foam; the report corrects this. Direct listening, true despawn/exit and published play are still needed.
- [Level 2 wall art](../artifacts/level2-wall-20260924/README.md): the three placements were non-colliding/non-querying and did not affect Pool Slide sight-line rays, but the owner rejected the visual result. The decal-generation code is removed, compiled in Studio Edit and confirmed in published v2083. The [service-hatch image](../assets/level2/wall-depth-v2/service-hatch-concept.png) is only an unapproved brainstorming reference. The card remains open pending a new approved visual direction.

## Residual fixes, 24 September evening (Studio compiled; published in v2081)

Claude wrote these in a separate worktree. Codex reviewed them and then pushed `ServerScriptService/ZyntraMonetization.Script.lua` into the existing Studio Edit place through the scoped compare-and-swap tool. The Studio compile probe passed on 24 September; fresh `.Source` and editor-source were equal at 204,565 bytes. Commit `8937264` records the manifest as `synced`. The [v2081 receipt](../artifacts/publish-v2081-20260924/README.md) subsequently found that exact source among all 182 mirrored scripts in the published place binary. Runtime purchase and persistence behavior still needs live verification.

After the push, a full read-only Studio audit matched all 182 mirrored scripts to the repo (0 drift). An isolated solo Play check loaded the owner profile with 5× Token Earner and Signal Architect owned, then started a real Level 1 round (`WorldGenerated`, `LoadStage=READY`, `RoundActive`, `InRound`; no game-script errors). The Fuse prompt could not be activated from that position, so this did **not** verify an actual earned-token payout. No reward/completion bindable was fired artificially against the persistent profile. Studio was stopped back to Edit.

| | sha256 |
| --- | --- |
| Pre-push Studio baseline | `541ce85f582c9762c2f34f422f90ef954ea027ad6ed83e44c3882c93db9ea63b` |
| Studio + repo target (manifest `sha256`, committed LF blob) | `b3db78879c9e95af265544deac915341dd0f1dc7c2cae870045d7e786c8fa350` |

**Compile-limit incident, corrected.** The first target, `b4c29497…`, landed through the CAS push and then **failed the Studio compile probe**. Studio's error was `Out of local registers when trying to allocate salesImportReadback: exceeded limit 200`, and Codex reverted the script to the pre-push source.
- **Cause:** the patch added five top-level helper locals; at Studio's count the script had room for only three.
- **Why offline missed it:** `luau-compile` defaults to `-O1`, which folds constant locals so they don't count toward the limit. `-O0` reproduces Studio's error exactly, at line 4460.
- **Fix:** the helpers are now `tokenEarner.span/merge/compact/mark/waits` table fields, which restores the pre-change headroom of 3 locals. The pass-retry constants (`{0, 1, 3}` and the 20 s × 3 re-check) are also now declared inside `ownsPass`/`refreshPasses`, with the same values, for 6. `salesImportReadback` and the sales import are untouched.
- **Guard:** `tools/tests/test_studio_compile_limits.py` compiles all 182 manifest scripts at `-O0`, inside the probe's `return function() … end` wrapper. It proves on a synthetic chunk that `-O0` catches a limit `-O1` misses, and prints the remaining headroom for ZyntraMonetization (6) and RoundUI (11). It exits 1 on `b4c29497…`.

The first CAS write of `b4c29497…` failed Studio compilation and was immediately restored to the verified pre-push source. After `c6cbbc7`, a fresh scoped audit found the old source ready for replacement; the second CAS write of `b3db7887…` compiled successfully. The push tool saved the old source in `.studio-push-backups/20260924-160531/`. The six passes remain off sale.

**Token Earner, automatic earnings (commits `66ddc5a`, `cb762f2`).** Clears and Fuse/Lever research no longer wait 60 s and then pay 1× during an ownership outage.
- An unknown tier pays the base now and queues the bonus in the same write as the clear: `profile.TokenEarner.Pending` buckets `{Earned, Unowned, Job, First, Last}`. There is no cap and nothing is dropped; the earning is keyed by `CompletionIds` or the daily Research flag.
- Settlement happens at the first complete ownership answer, with the tier of the passes owned then, minus the passes *this game saw not owned after the earning*: our purchase latch, or a definitive "not owned" read that began later.
- Ordering uses `tokenEarner.stamp()`, a monotonic per-server sequence, not `os.time`. A bucket from another JobId predates the current server.
- A read in flight blocks merges across it and delays settlement of older buckets.
- A refresh that began before the newest answered one keeps its proofs but never replaces that snapshot or lowers the tier.
- `tokenEarner.latched` runs in the purchase callback before any yield. It records the proof and raises a known tier, so a clear during the slow purchase refresh pays the new tier.
- **Policy, not history.** `UserOwnsGamePassAsync` returns only a boolean, never a purchase time. A pass bought *outside the game* between an outage earning and the first read after it is paid as if already owned. The alternative underpays every pre-existing owner.
- Existing balance, Token packs, gifts, refunds and grants never pass through it. Friend Boost, Daily Clear and challenge tokens count as earned.

**Developer suit (commit `2469d2d`).** The `Skins.SyncDeveloper` write now retries through `mutateIdempotent` at 0/5/20/60 s. Its transform re-reads `DevAccess`, and a profile already in sync costs no request. Genuine developers are unchanged.

**Offline evidence (Luau 0.737; each new guard mutation-checked; the killed mutants are listed in the commit messages):**
- `test_completion_save.py` 177: case 15, which asserted the 1× fallback, is replaced.
- `test_token_earner.py` 383.
- `test_dev_suit_revocation.py` 34 (new).
- `test_friend_boost.py` 329: the stub gains `stamp` and a `known` return.
- Daily rewards 401, feedback gift 26, first login 33, lucky wheel 622, purchase alerts 97, rail dots 20, speed potion 498, token grants 243, upgrade cost 15, skins 31, hazmat cleanup 12.
- `test_studio_compile_limits.py` compiles all 182 scripts at `-O0`, wrapped like the probe. The earlier `-O1`-only check was NOT enough (see the incident above).
- The three stale harnesses fail with the same messages as at HEAD.

**Native validations still required:**
1. A Play round with a forced ownership outage. Clear once and check `TokenEarner.Pending` in the saved profile. Rejoin with ownership answering, and see exactly one "Token Earner bonus" payment.
2. A live DataStore clear with a failed write, then a rejoin, on a published server.
3. A two-client round where a non-developer sees no Signal Architect.
4. A developer revoke plus rejoin on a real account.
5. A forged `EquipSkin` from a non-developer client.
6. Physical mobile.

Keep all six Token Earner passes **off sale**. No purchases were made. Code was published in v2081, but the purchase and rejoin paths have not been verified on a published server.

## Codex follow-up, 24 September evening

- [Level 3 maze QA](LEVEL3_MAZE_QA_2026-09-24.md): owner kept the 560-stud scripted finale. Commit `7710853` enlarged the core and broke long straight structural chains. Forty offline seeds and four native built-world seeds passed; the native longest clear room-centre ray was 312–339.5 studs. A normal one-player lobby queue started a live Studio Level 3 round at `READY/SEARCH`; its active seed measured 338 studs. In a second normal solo round, ordinary movement and E-hold picked up CD02 and CD01, moving both `WORLD→CARRIED` and showing 2/5 progress at 100 HP; Manager remained OFF at 2/5. One CD prompt was hidden when close behind its table but appeared after backing away. Play stopped cleanly, with no Edit changes. Studio Source/editor and the repo matched 182/182 after the scoped push. The remaining three CDs, reader→exit, Mall Manager chase, physical mobile performance and publication remain. The card moved from To Do to In Progress, then Testing with these gates.
- [Published Player check](../artifacts/player-qa-v2083-20260924/README.md): a returning developer account showed the six-field wheel, dismissible first-clear intro and standing portraits for the six ordinary skins. The developer-only Signal Architect catalog card still showed a T-pose. Its replacement standing portrait is `assets/hazmat/catalogue-portraits/signal-architect-standing-card-v1.png`, approved group Image `139302197163453`. `ReplicatedStorage.ZyntraSkins.SignalArchitect.PreviewImageId` now uses that ID in Studio; Source/editor match, compile succeeds, and the full Studio audit remains 182/182. The replacement is **not published yet**, so this does not close the developer suit or viewer cards.
- Trello [upgrade card](https://trello.com/c/KF7FDmP1) records the owner's approval of the `level + 1` Token cost and four published Player purchases (12/13 each for Stamina and Battery; [receipt](../artifacts/player-qa-v2083-20260924/README.md)). Read-only Open Cloud confirmed 842 Tokens and level 13 in each upgrade; the owner confirmed those numbers after new-server rejoin. The Luau 0.737 branch test passed 15/15 including insufficient balance with no write or deduction, and Studio Edit source retains the guard. The card moved to Done with that explicit negative-path limitation. The friend checklists are attached directly to the [physical mobile/tablet](https://trello.com/c/lUKD3R8G) and [controller](https://trello.com/c/uI8hg2At) cards. Fourteen Testing cards remain open after Level 3 moved there and this upgrade card closed; they retain their documented live/physical/DataStore/purchase gates.

## Intro voice removed, text retained

The owner clarified that the lobby and Level 1–3 spoken intros should be disabled while their text, speech IDs and future restoration path remain. The captions must not lock other UI. [The QA report](INTRO_TEXT_ONLY_QA_2026-09-24.md) records the scoped Studio change, 182/182 Source/editor parity, all 182 Luau `-O0` compile checks, and the full Studio UI regression result (**3,025 checks, 0 failures**). Actual fresh Studio lobby and Level 1–3 queue rounds each showed multiple caption lines with zero speech-playing samples. The tiny landscape Level 3 reader case keeps the caption click-through and its 44px SKIP target outside movement zones.

Trello [xKozYUIo](https://trello.com/c/xKozYUIo) should remain in Testing until the owner publishes the new Studio version, a published client confirms the four intros, a physical phone confirms the caption does not block movement, and the retained radio-open cues are listened to for any baked speech. The latest confirmed published version is still v2083; the new intro change and the earlier Level 3 maze/Signal Architect portrait changes are in Studio only.
