# Whole-game code and offline QA — 2026-09-24

Audited commit `2c2ff2a3e9d087a2fdfe6a558c808719b9d27633` on `codex/level5-indoor-suburbs`. Git fetch found no newer remote code during this pass. This is a broad source/offline audit, not a claim that every level was played end to end. The audit worker did not change repository or Studio state. The parent subsequently installed the focused Level 1 briefing correction in Studio; final source export/publication are tracked in the main delivery.

## Concrete findings

**P2 — a failed completion save permanently drops the earned clear reward.** `ServerScriptService/ZyntraMonetization.Script.lua:3496` calls `mutate` once and ignores the result. The underlying `mutate` at lines 1095–1133 returns false after a failed `UpdateAsync`; it does not retry or queue this award. The completion bindable fires once for each escapee in `GameManager.Script.lua:2953`. The subsequent badge call at monetization line 3529 still runs, so a player can receive First Clear while missing tokens, daily Clear progression, records and recorded level-clear flags. the task-local `reproduce_completion_save_failure.py` (result retained in `assets/qa/20260924/logs/completion-save-failure.log`) executes the actual mutate and completion handler with a fake DataStore that fails before commit: one failed write, no profile progression, badge still attempted, no retry. Hold this as a follow-up: a correct fix needs a stable completion transaction ID and idempotent retries, including uncertain after-commit responses; blindly retrying can double-pay.

**P3 — Level 1 elevator briefing overstates the puzzle for groups.** `GameManager.Script.lua:2868` publishes party size (2/3/4/5/6), while `Level 1 Systems/PuzzleManager.Script.lua:1201` generates `ceil(n/2)` (1/2/2/3/3). `MazeGenerator.Script.lua:976` uses this attribute for visible colored rows and the active-cable summary at line 995. The parent installed a one-line correction from the latest Studio furnishing baseline. Source hashes are in `assets/qa/20260924/game-manager-patch.json`. The portable regression at `tools/tests/test_level1_preview_allocation.py` extracts both real source blocks, checks the six expected party allocations and three clamp boundaries (18 assertions), and optionally proves that a historical baseline fails for parties 2–6 (19 assertions with baseline). It passed against the corrected source plus original baseline; full GameManager also compiled. This change only corrects the briefing; puzzle difficulty is unchanged.

No new P0/P1 defect was confirmed. Static review covered queue authority and Level4/5 dev gating, round loading/completion/returns, objective escape handlers, receipt deduplication, pass ownership retries, stamina/equipment, daily/token inventories and new challenge recording. Potential duplicate detector remotes was ruled out by read-only Studio inspection: no ZyntraDetector exists in the saved Edit Remotes folder; service creates it at runtime.

## Existing test results

**66 existing Python suites executed; 49 passed, 17 failed.** Every failure was inspected and is listed below. These failures expose missing test coverage or stale harness assumptions; they are not evidence of 17 production bugs. Two supplemental task-local runs inserted the actual new Challenges module into existing harnesses without changing assertions: daily rewards passed 370 checks and item inventory passed 87. Original 49/17 totals remain unchanged. Raw stdout/stderr is retained under `assets/qa/20260924/logs/`, command, exit status and test SHA256 for every run in `assets/qa/20260924/offline-results.json`, and classifications in `assets/qa/20260924/classified-results.json`.

The runner limits each process to 90 seconds and uses four workers. No process reached that limit. No paid prompts, real profile writes, external service writes or real Studio push occurred; the relay suite uses its own local HTTP fixture. The square-layout suite normally writes a repo artifact; this audit redirected only its output JSON to the task folder. All assertions and tested source remained unchanged.

| Suite | Result | Assessment |
|---|---|---|
| test_controller_input.py | PASS | Existing suite passed under offline engine fakes. |
| test_daily_rewards.py | FAIL | New real ZyntraChallenges is missing from fake require. Supplemental harness run embedding real module passed 370 checks. |
| test_daily_rewards_client.py | PASS | Existing suite passed under offline engine fakes. |
| test_daily_rewards_page.py | PASS | Existing suite passed under offline engine fakes. |
| test_death_advice.py | FAIL | Extracted hookLife now accesses runFacts[player]; harness does not declare runFacts. Captured fixture line 365. |
| test_dev_free_respawn_offer.py | PASS | Existing suite passed under offline engine fakes. |
| test_donation_board_columns.py | PASS | Existing suite passed under offline engine fakes. |
| test_equipment_hud.py | PASS | Existing suite passed under offline engine fakes. |
| test_feedback_gift.py | PASS | Existing suite passed under offline engine fakes. |
| test_first_entry_guide.py | PASS | Existing suite passed under offline engine fakes. |
| test_first_login_flag.py | PASS | Existing suite passed under offline engine fakes. |
| test_flashlight_player_control.py | PASS | Existing suite passed under offline engine fakes. |
| test_friend_boost.py | FAIL | Actual completion callback gained run argument; extraction still searches the older three-argument header, so no payout test executes. |
| test_full_sync_contract.py | FAIL | All canonical reconciliation checks pass; sole failure demands this checkout contain CRLF files. This checkout has LF (0 of 191 CRLF). |
| test_item_inventory.py | FAIL | New real ZyntraChallenges is missing from fake require. Supplemental harness run embedding real module passed 87 checks. |
| test_leaderboard_backfill.py | FAIL | Extracted profile setup now requires modules through ReplicatedStorage; fake world lacks that service at first WaitForChild. |
| test_level1_cable_current.py | PASS | Existing suite passed under offline engine fakes. |
| test_level1_relay_spawns.py | PASS | Existing suite passed under offline engine fakes. |
| test_level1_team_prompts.py | FAIL | Actual announceTeam calls shared TeamObjectives.Announce; harness does not provide TeamObjectives. |
| test_level2_pool_slide_release.py | PASS | Existing suite passed under offline engine fakes. |
| test_level2_tile_face_culling.py | PASS | Existing suite passed under offline engine fakes. |
| test_level2_tunnel_height.py | FAIL | Current archRibMeshTemplate calls RunService:IsStudio(); fake geometry host lacks RunService. |
| test_level3_first_cd.py | PASS | Existing suite passed under offline engine fakes. |
| test_level3_first_cd_prompt.py | PASS | Existing suite passed under offline engine fakes. |
| test_level3_flashlight_timeline.py | PASS | Existing suite passed under offline engine fakes. |
| test_level3_hidden_chase.py | FAIL | Actual livingPlayer now checks PlayerProtection.IsActive; harness omits PlayerProtection. |
| test_level3_hide_animation.py | PASS | Existing suite passed under offline engine fakes. |
| test_level3_run_in_exit.py | FAIL | Heartbeat excerpt now calls rememberCarriedPositions/updatePlayerRooms, but harness does not extract those helpers. First failure at rememberCarriedPositions, fixture line 565. |
| test_level3_slide_aperture.py | FAIL | Builder now sets ModelStreamingMode.Atomic; fake Enum lacks ModelStreamingMode. |
| test_level3_square_layout.py | PASS | Existing suite passed under offline engine fakes. |
| test_level3_steering.py | PASS | Existing suite passed under offline engine fakes. |
| test_level4_neighbour_brain.py | PASS | Existing suite passed under offline engine fakes. |
| test_level4_plan.py | PASS | Existing suite passed under offline engine fakes. |
| test_level5_access.py | PASS | Existing suite passed under offline engine fakes. |
| test_lobby_palette.py | PASS | Existing suite passed under offline engine fakes. |
| test_lobby_shop_display.py | FAIL | Pre-execution test guard insists on 8 product textures; source now has 10 after new products/art. |
| test_lucky_wheel_client.py | PASS | Existing suite passed under offline engine fakes. |
| test_no_level3_continue.py | PASS | Existing suite passed under offline engine fakes. |
| test_pool_foam_audio.py | PASS | Existing suite passed under offline engine fakes. |
| test_pool_foam_navigation.py | PASS | Existing suite passed under offline engine fakes. |
| test_pool_foam_separation.py | PASS | Existing suite passed under offline engine fakes. |
| test_pool_foam_sight_rule.py | PASS | Existing suite passed under offline engine fakes. |
| test_pool_slide_audio_states.py | PASS | Existing suite passed under offline engine fakes. |
| test_pool_slide_navigation.py | FAIL | Current production navigator passes 7 checks. Chosen historical Git baseline also passes, invalidating the expected-stall counterexample. |
| test_purchase_alert_relay.py | PASS | Existing suite passed under offline engine fakes. |
| test_purchase_alerts.py | PASS | Existing suite passed under offline engine fakes. |
| test_push_repo_to_studio.py | FAIL | Official Luau executable works for other suites but rejects --version. Harness treats exit 1 as unavailable, skipping 16 tests; its fixture-only checks run. No real Studio contacted. |
| test_queue_barrier.py | FAIL | Actual playerInsideZone now uses Routing.MaxLevel; fake queue harness does not provide Routing. |
| test_rail_dots_intro.py | PASS | Existing suite passed under offline engine fakes. |
| test_reentry_dismissal.py | PASS | Existing suite passed under offline engine fakes. |
| test_round_entry_client.py | PASS | Existing suite passed under offline engine fakes. |
| test_round_exit_hold.py | PASS | Existing suite passed under offline engine fakes. |
| test_round_loading_host.py | FAIL | Actual prepareGroupLoading now calls canAccessLevel; harness omits this local helper. Captured fixture line 2146. |
| test_round_loading_notice.py | PASS | Existing suite passed under offline engine fakes. |
| test_route_markers.py | PASS | Existing suite passed under offline engine fakes. |
| test_spectate_audio_gates.py | PASS | Existing suite passed under offline engine fakes. |
| test_spectate_parity.py | PASS | Existing suite passed under offline engine fakes. |
| test_spectator_count.py | PASS | Existing suite passed under offline engine fakes. |
| test_spectator_vitals.py | PASS | Existing suite passed under offline engine fakes. |
| test_speed_potion.py | PASS | Existing suite passed under offline engine fakes. |
| test_studio_source_contract.py | PASS | Existing suite passed under offline engine fakes. |
| test_support_product_receipts.py | FAIL | Profile setup requires DailyResearch/Challenges but fake receipt world lacks ReplicatedStorage. Fails before receipt assertions. |
| test_token_grants.py | PASS | Existing suite passed under offline engine fakes. |
| test_ui_style.py | PASS | Existing suite passed under offline engine fakes. |
| test_zyntra_analytics.py | PASS | Existing suite passed under offline engine fakes. |
| test_zyntra_store_compact.py | PASS | Existing suite passed under offline engine fakes. |

## Studio checks and remaining limits

Parent reported Level4 pure suite in Edit: 163 plan checks and 18 brain checks, zero failures. Level3 suite cannot currently be required in Edit despite its old header, because it imports HidingController → PlayerProtection (server-only). Run it in Server Play. Exact bounded read-only Level2/3/4 commands are in `assets/qa/20260924/studio-smoke-checks.luau`. Level2 reads live completion sensors/recovery chamber without trying to rebuild the world; it does not claim the complete flume manifest/probes ran. Level3 reads actual replicated objective state. Level4 reads standing instances rather than a separate adapter module cache.

Full human multiplayer, real private-server continuation/return, live DataStore outages and receipts, physical mobile/tablet controls, device performance, and long session retention remain outside this offline audit. Hardware and physics claims must come from parent live tests; no publication claim is made here.

The standalone `test_level5_lobby_retention.luau` contains a pasted implementation rather than extracting current production source, so it was not counted among the 66 Python suites or used as fresh evidence. The Level5 access test does extract actual Routing/GameManager and passed.

## Re-running the focused regression

```sh
LUAU_BIN=/path/to/luau python3 tools/tests/test_level1_preview_allocation.py
```

Optional `--sources`, `--manager`, `--puzzle`, `--baseline-manager`, and `--luau` arguments support fresh exported sources before they are mirrored. The test does not alter Studio or profiles.

During live smoke preparation, a three-seed custom call to Level3 was rejected by its diversity floor. That probe input was corrected to the official defaults: nine generated-layout seeds and twenty navigation seeds. This failure is not a gameplay defect and is not counted among the 66 offline suites.

## Subsequent concurrent Records integration

The original 49/66 result is the baseline audit at `2c2ff2a`, not a fresh count after merging `2e5cfd8`. That upstream integration includes several repaired harnesses. The three concurrent Studio scripts match it exactly and pass 2,465 Records-page, 42 Challenges and 544 compact-store checks. Actual Studio validation additionally passed Level 2 seeds 1/101/7331 and the Level 3 official default suites (9 layout seeds, 20 navigation seeds). See `LEVEL5_FURNISHING_2026-09-24.md` for current map QA and delivery. The confirmed reward-save issue is tracked in Trello: https://trello.com/c/EYpXKa9S.
