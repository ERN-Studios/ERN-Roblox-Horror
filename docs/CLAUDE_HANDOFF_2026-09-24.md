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

## Residual fixes, 24 September evening (repo only — NOT in Studio)

These were written by a Claude CLI session **without Studio MCP**. Nothing below is in Studio, saved in the place, or published. `ServerScriptService/ZyntraMonetization.Script.lua` is queued in the manifest as `pending-studio-push`:

| | sha256 |
| --- | --- |
| Live Studio baseline (`studioSha256Before`) — `pull_source_from_studio.py --audit` at session start: 182/182 scripts matched | `541ce85f582c9762c2f34f422f90ef954ea027ad6ed83e44c3882c93db9ea63b` |
| Repo target (manifest `sha256`, committed LF blob) | `b4c29497074d901f2a8206f22f12d14d2ef2eb70b7fa487055ef9676cf0a6c99` |

A recheck at the end could not run because Studio was in Play mode (`Edit datamodel is not available in Play mode`). Before applying: stop Play, run `python tools/push_repo_to_studio.py --audit --file ServerScriptService/ZyntraMonetization.Script.lua`, and expect `ready`. A `conflict` means someone edited the script in Studio since then. Merge that edit; never `--overwrite-conflicts`.

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
- `luau-compile` is clean.
- The three stale harnesses fail with the same messages as at HEAD.

**Native validations still required (none done):**
1. Push through the verified compare-and-swap, then run the Studio compile probe.
2. A Play round with a forced ownership outage. Clear once and check `TokenEarner.Pending` in the saved profile. Rejoin with ownership answering, and see exactly one "Token Earner bonus" payment.
3. A live DataStore clear with a failed write, then a rejoin, on a published server.
4. A two-client round where a non-developer sees no Signal Architect.
5. A developer revoke plus rejoin on a real account.
6. A forged `EquipSkin` from a non-developer client.
7. Physical mobile.

Keep all six Token Earner passes **off sale**. No purchases were made and nothing was published.
