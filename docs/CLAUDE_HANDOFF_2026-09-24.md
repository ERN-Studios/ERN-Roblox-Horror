# Claude → Codex handoff — 24 September 2026

Branch `claude/trello-20260921`, draft [PR #8](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/8). Every change below went into Studio first-class through the verified compare-and-swap push (`tools/push_repo_to_studio.py`) against a fresh Source/editor baseline, and was then mirrored. **Nothing here is published**: the latest publication is still **v2061**, which predates all of it. No card is Done; each still has the live/physical gate listed.

Final parity (end of session): 182/182 scripts match Studio `.Source`, 182/182 editor sources equal `.Source`, manifest 197/197 `synced`, no stray QA instances or attributes left in Edit.

**Studio non-script changes** (additive; no pre-existing object deleted or overwritten):

| Path | Change | Native export |
| --- | --- | --- |
| `ServerStorage.Level2Assets."Level 2 Pool Slide Template"` | Now x1.1 of the verified scale-6 rig (see Pool Slide) | `artifacts/claude-20260924/Level 2 Pool Slide Template (1p10, 20260924).rbxm` |
| `ServerStorage.Level2Assets."Level 2 Pool Slide Template (pre-1p10 backup 20260924)"` | The previous live template, renamed only (scale 6, untouched) | recoverable from v2061 |
| `ServerStorage.HazmatSkin_SignalArchitect_20260924` | Clone of Baseline Yellow template, `Scene.char1.SurfaceAppearance.ColorMap = rbxassetid://137400739559825` | `artifacts/claude-20260924/HazmatSkin_SignalArchitect_20260924.rbxm` |

A full place `.rbxl` backup was not taken this session (the desktop "Download a Copy" route was declined); the two `.rbxm` exports plus v2061 cover every non-script object changed.

## Cards

| Card | Commits | Studio evidence | Still required before Done |
| --- | --- | --- | --- |
| [EYpXKa9S completion save](https://trello.com/c/EYpXKa9S) | `8e623de`, `d50033f` | Real Level 1 round: one save with record/challenges in the same write; duplicate round ids through the real bindable answer "Level clear saved." without paying. Offline `test_completion_save.py` 61 (fail-before-commit, lost-response, duplicate, backoff, leave-time flush while unparented, outage, 5x tier). | Live DataStore: a clear with a forced failure and rejoin on a published server. |
| [PuuOYhmH LEVEL 1 START HERE](https://trello.com/c/PuuOYhmH) | `d4ae70e`, `e3f5bec` | Play with `DevSimulateFirstLogin`: no guide, marker, START HERE/THIS WAY/TRY AGAIN text or cyan beam. Script kept as a retired stub (no-delete rule). | Publish + lobby check. |
| [x4kKwPZx standing viewer](https://trello.com/c/x4kKwPZx) | `623264b`, `1d7255d` | 3D preview stands for all six (hands 1.63–1.64 studs below shoulders); SKINS cards now use your six standing portraits (loaded in Play). | Published visual check desktop + touch. |
| [EtdsUM4e Token Earner](https://trello.com/c/EtdsUM4e) | `91106da`, `d50033f` | Studio (all passes granted) tier 5: clear +2 +8; at 2x +2 +2; 2x owner sees 3x 150 / 5x 250; wheel Token3 at 5x paid 15 with `PaidTokens`; non-owner sees COMING SOON on all three cards (passes off sale). Your three review findings are fixed: purchase-race (both interleavings), off-sale gate incl. detail pane, and no 1x before ownership is known. Offline `test_token_earner.py` 366. | Put passes on sale only after publish; live purchase of each path (2x, 3x, 5x, 2→3, 3→5, 2→5, an upgrade bought before its prerequisite), rejoin, and a claim immediately after join. |
| [rXhi1SZ8 Pool Slide](https://trello.com/c/rXhi1SZ8) | `234c66e` | Template x1.1 (x1.2 failed: AgentRadius 9 made every long enraged plan expire, ~13,000 queries vs 500–1,000). Walk/Run your IDs; reference speeds 13.62/33.74 and `AttackDistance` 11.55 carried by the template. Four rounds: seeds 1182081016, 101, 7331 (runtime swap) and random 813137647 from Edit — spawn ≥100 studs, run, attack, 3rd pump enrages the same entity, 600-stud enraged plan at 32 studs/s. Mouth audio emitter 0.94 studs from `Head`. | Your uploaded Model `95190427565492` lost Neck/Head (18 bones) and was not used. Foot-slide tuning at 10/20/32 (new Walk dips the foot bone 0.15 below rest), phone/tablet FPS, publish. |
| [LigItMHi groans](https://trello.com/c/LigItMHi) | — | No code defect found by the audit; emitter follows `Head` on the larger rig. | Your listening test. |
| [SYUaXHKQ developer suit](https://trello.com/c/SYUaXHKQ) | `bc1192b`, `d50033f` | Developer owns/equips Signal Architect; teal texture renders in the viewport. Fail-closed: a Developer suit is never published for a non-developer, even before the revocation write lands. | Non-developer account (no card, forged equip refused), revoke + rejoin, two-client visibility, mobile. |
| [IRLeRBcN skin VFX](https://trello.com/c/IRLeRBcN) | `bc1192b`, `d50033f` | False Sun motes (your parameters/texture) enabled in a round; visible from a third-person camera. The wearer never sees their own (first-person LocalTransparencyModifier) — teammates are the audience. Cleanup is idempotent (`test_hazmat_driver_cleanup.py` 12). The shop preview gets 2D embers from the topper window (ViewportFrames render no ParticleEmitter); 1–2 seen in Play. | Two-client round, phone frame time, ReduceFlashing check. |
| [KF7FDmP1 upgrade cost](https://trello.com/c/KF7FDmP1) | `8ee95f4` | `ZyntraConfig.UpgradeCost(level) = level + 1`; Play: 35→33 tokens for level 2, label moved to SPEND 3 TOKENS. Owner can retune the one function. | Owner sign-off on the ladder; publish. |
| [DDqjXkyU wall depth](https://trello.com/c/DDqjXkyU) | `644be20` | Your two decals placed in generated halls (trace in the quietest plain hall, two murals on long solid walls; never pump/kids/slide/arrival/exit/den/grand). Seeds 1182081016 and 101 checked visually. `test_level2_wall_decals.py` 26. | Owner look, phone draw count/frame time. |
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
