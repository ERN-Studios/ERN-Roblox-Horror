# Claude handoff — Trello To Do batch, 2026-09-14

Lead: Fable 5.1 (this session). Four Opus 5 agents did the independent workflows
(cards 68, 69, 70 and the audio/UI half of 73); the lead implemented 45, 64, 74, 76
and the spectator-counter half of 73, integrated Codex's 67/75/71 work, and ran the
Studio verification. Scope was only the 13 snapshot cards; no other lists, no Level 4.

## Result in one line

All eight Claude cards are implemented, offline-tested, pushed into Studio
(compile probe 129/129, drift audit 0) and Studio-verified in a solo play session,
except the parts that only a second real player or the owner can exercise (listed
under *Open*). Codex's three prepared changes are integrated; one runtime bug in
the ceiling sweeps was found in Studio and fixed. **Nothing is published** and no
Discord message was sent.

## Per-card status

| Card | Status | Files (repo = Studio) | Offline tests | Studio |
|---|---|---|---|---|
| 45 Player ESP | done | GameManager (`playerEsp` branch), DevCheats (client block), ZyntraStore (DEV row) | player-esp 67-check host reused from 2026-09-10 proposal (unchanged logic) | DEV command → `PlayerGui.DevPlayerESP` gained `Player_40920547 = @mikkelczar`, attr `DevCheatPlayerEsp = true`; server replies only to the requester |
| 64 Free dev respawn | done | GameManager (`requestDevRespawn`, shared `performRoundReentry`), DevCheats, ZyntraStore | `test_reentry_dismissal` 37, `test_round_loading_host` 83 (reentry paths still pass) | died in Level 1 → DEV `freeRespawn` → `DevRespawnStatus = RESPAWNED`, new character, health 100, tokens 35→35, credits 0→0, `ZyntraReentryUsed` false |
| 68 Phone/tablet shop + upgrades | done | ZyntraStore (Upgrades/Shop blocks only), UIRegression (4 new stated-reason captions) | `test_zyntra_store_compact.py` (210/246/330 px card; 52/64/76 icon) | `UIRegression.Compact("ZyntraTerminalFitMatrix")`: **1405 checks, 0 failed** across 11 device layouts (phone landscape/portrait, tablet, desktop); tab bar untouched |
| 69 Purchase alerts | code complete, **not operational** | new `PurchaseAlerts` ModuleScript, ZyntraMonetization hook (first-time grants only), `tools/purchase_alert_relay/` | `test_purchase_alerts.py` 97, `test_purchase_alert_relay.py` 30 | module present and compiled; disabled by design until configured (warns once) |
| 70 First-login guide | done | new `First Entry Guide` LocalScript | `test_first_entry_guide.py` 37 | fresh-profile probe: 17 waypoints / 16 beams through the Level 1 doorway, billboard on the nearest pad; ended the moment the player stood on `LaunchZone1` |
| 73 Spectator counter + parity | done (server/counter/UI/audio); **two-player check pending** | SpectateController, GameManager (`spectatetarget` → `SpectatorCount`), SoundController, Level 2/3 Sound Controllers, Level 2 Objective UI, Level 3 Reader Client, PuzzleUI | `test_spectate_parity.py` 17, `test_pool_foam_audio` 24, `test_controller_input` 120 | self-target correctly refused (`SpectatorCount` stays nil); counter/parity need a second client |
| 74 Back to lobby | done | GameManager (`leaveround`), new `Round Exit Client`, SpectateController (band button) | `test_queue_barrier` unaffected; leave path exercised in Studio | chip visible after the briefing (top-left 24,20), confirm card, `leaveack` + `lobby`, lobby character at spawn, solo round wound down and station reset (twice); Level 3 in Studio answers `leavefailed` with the notice |
| 76 Full-party barrier | done | GameManager (collision groups + `Station<N>FullBarrier`) | `test_queue_barrier.py` 72 + the 2026-09-10 circle regression re-run against the new source: 257 checks pass | capacity-1 party: 24 ForceField segments, CanCollide on, CanQuery off, group `QueueBarrier`, all 18 member parts `QueueMember`; wall gone and parts `Default` once the party launched / left; screenshot taken (ring around the pad, "PARTY FULL") |

Codex's cards, integrated by the lead:

| Card | Status | Notes |
|---|---|---|
| 67 Ceiling patterns | done, **one bug fixed** | `item.partColor * 0.14` threw `attempt to perform arithmetic (mul) on Color3 and number` on every sweep tick in Studio (Codex's fake engine allowed `Color3 * number`). Replaced with `partColor:Lerp(Color3.new(), 0.86)`; Codex's `test_ceiling.py` fake gained `Lerp`/`new` and now points at the mirror file (21940 assertions pass). Second play session: 28 lights, off/dimmed samples observed, no console errors. |
| 75 Level 3 finale at entry | integrated, chase pacing **not measured** | Canonical hashes matched `finale-basis.json`; `test_finale.py` 19 assertions pass; `test_level3_steering` 222 and `test_level3_flashlight_timeline` 322 still pass. Studio: Level 3 round started clean; `MazeStart.Y = 24.25` vs `Level3_FloorY = 24`, so the entry-spawn candidates sit on the real floor. The finale itself (all CDs + exit run) was not played. |
| 71 Feedback gift | integrated, **not yet delivered** | `refreshPasses` grants UserId 10152463945 once (`Grants.FeedbackThanks20260914`). `test_feedback_gift.py` 26: only that account, +1/+1/+10 once, repeat is a cancelled write, DataStore failure leaves no marker and the next load retries, receipts/pass flags untouched, Studio never writes; `normalizeProfile` keeps unknown Grants keys. Delivery happens on Kecoalmutt's next successful profile load on a server running this build, i.e. after publish. |

Cards 18 and 44 stay with Codex (investigation only).

## Studio parity

- Pushed through `record_pending_push.py` + `push_repo_to_studio.py` in two batches
  (17 scripts, then UIRegression + LobbyCeilingSweeps); 0 conflicts, every push
  compiled. Backups: `.studio-push-backups/20260914-162815` and `20260914-163844`.
- New instances created first with a placeholder source, then pushed like any
  other script; manifest now 129 scripts / 143 items, all `synced`; counts updated.
- Compile probe: 129/129. Final drift audit after this file: see the commit message
  (run `python tools/pull_source_from_studio.py --audit`; expected 0 drift).
- Play sessions: two (Level 1 twice, Level 3 once, lobby matrix twice). Console clean
  after the ceiling fix.

## Offline test suite

`tools/tests`: 24 pass. Four do not:

- `test_level3_run_in_exit`, `test_level3_hidden_chase`, `test_level3_slide_aperture`
  already failed at HEAD `d0ff99e` before this batch (Level 3 sources were untouched
  until Codex's finale landed; the failures predate it). Worth a card.
- `test_push_repo_to_studio` reports "no luau interpreter" because luau 0.737 has no
  `--version` flag; environment only.

Fixed in passing: `test_support_product_receipts.py` (stale `addSupporterTag`
marker) and `test_token_grants.py` (expected the retired third DevAccess id). New
tests: `test_queue_barrier.py`, `test_feedback_gift.py`, plus the agents' five.

## Open — needs the owner or a second player

1. **Card 69 is not live.** Owner steps, in order (details in
   `tools/purchase_alert_relay/README.md`): create private `#dev-purchase-alerts`
   with dev/admin-only permissions → create its webhook → deploy `relay.py` (Render
   Web Service, env `RELAY_TOKEN`, `DISCORD_WEBHOOK_URL`) → add Roblox Secrets
   `ZYNTRA_PURCHASE_ALERT_URL` / `ZYNTRA_PURCHASE_ALERT_TOKEN` → enable HTTP
   requests in Game Settings → one real cheap purchase and confirm exactly one
   alert (and none on a receipt retry). Until then the module disables itself with
   one warn per server; grants are unaffected.
2. **Card 73 two-player check** (counter on the watched player, custom footsteps
   instead of the default `Running` loop, bearings from the watched body, ESP not
   visible): not provable with one client. Checklist in `agent-73-report.md`.
   Breathing is deliberately own-only (stamina never replicates); ProtectionHUD
   was left alone (it is an input control, not a readout).
3. **Card 76 with real walking**: the wall was verified as geometry, groups and
   membership; a second player physically bumping into it, and the exact feel of
   an extra being pushed out against the ring, need two clients.
4. **Card 75 finale pacing**: Codex's note stands — physical chase tightness needs a
   full Level 3 playtest.
5. **Card 71**: delivery is automatic on the player's next login after publish;
   nobody has to click anything. Report back "delivered" only after that login.
6. **Publishing**: not done, per instructions. The place holds every change above.

## Product decisions taken by the lead (say if wrong)

- Back-to-lobby for an alive player is a small top-left chip plus a confirm card;
  dead/escaped players get a full-width button above the spectate caption. While
  the PARTY DOWN card is up the spectate button hides (the card owns the screen);
  it returns after NO THANKS. Studio-only Level 2/3 rounds answer "Not available
  in this test round" because those levels park the lobby; published servers
  teleport.
- The first-login guide reuses the lifetime welcome flag instead of a new saved
  field: a brand-new profile sees it, a returning one never does. It has no beam
  texture by default (an unverified asset id would render as a broken stripe);
  set a `BeamTexture` attribute on the script to audition one.
- The barrier is visual + physical for non-members only; the existing server
  push-out remains the authority, so a client that ignores collision still cannot
  join a full party.

## Files touched (repo = Studio)

GameManager, ZyntraMonetization, DevCheats, SpectateController, ZyntraStore,
SoundController, Level 2 Sound Controller, Level 3 Sound Controller, Level 2
Objective UI, Level 3 Reader Client, PuzzleUI, UIRegression, LobbyCeilingSweeps,
Level 3 Objective Controller, Level 3 Mall Manager AI Controller; new
PurchaseAlerts, First Entry Guide, Round Exit Client. Plus `tools/purchase_alert_relay/`,
seven new tests under `tools/tests/`, CLAUDE.md ("Added 2026-09-14"),
`studio-sync-manifest.json`. Agent reports: `agent-68/69/70/73-report.md` here.
