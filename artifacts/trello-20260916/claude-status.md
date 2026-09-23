# Claude status — 2026-09-16 (living document, lead = Fable 5.1)

Baseline: git `aa40f70` (clean tracked tree), Studio v1907, manifest 135 scripts / 149 items.
Studio: CLAUDE since 06:35 UTC (Codex handover, codex-animation-handoff.md). Claude has not touched git.

## 06:22 UTC — contracts written, nine Opus 5 agents DISPATCHED (all running in the background)

Files: `claude-contracts.md` (binding interface: schema, actions, remotes, keys, page API),
`shared-coordination.md` (ownership table). Agents and ownership are listed there.

| Agent | Card(s) | Model | State |
|---|---|---|---|
| A-SERVER | #83 #84 #89 #85 server side (ZyntraMonetization, ZyntraConfig) | Opus 5 | DONE + lead-reviewed 07:15 UTC: +791 lines (schema Items/Daily/FieldNotes, applyReward, rollDaily, dailyMutate with FlushId dedupe, 1 s accrual loop, ClaimPlaytimeReward/SpinDailyWheel/BuyItem/UseSpeedPotion, ServerStorage.ZyntraInventory, leaderboard row attributes, title tag). test_daily_rewards 320, test_item_inventory 146; all 8 pre-existing Monetization suites unchanged. Lead added IconId (Codex crate art) to Config.Items. Both files pushed to Studio. Needs Studio: os.date("!..."), real loop cost, remote dispatcher wiring, live DataStore behaviour |
| A-REWARDS-UI | Daily Rewards page module | Opus 5 | DONE + lead-reviewed 06:58 UTC: ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua (964 lines, contract API, no client grants, replay keyed on server Serial, no tweens, UTC day checked against Daily.Today), test_daily_rewards_page.py 403 checks against the real ZyntraConfig/UIStyle/ZyntraStore helpers. Disabled captions: CLAIMED, CLAIMING, %d+:%d+ TO GO, SPUN TODAY, SPINNING (sent to A-SHOP-UI for UIRegression). Needs Studio: mount by ZyntraStore, fonts, phone capture |
| A-NOTES | Field Notes (content, service, client, page) | Opus 5 | running |
| A-ITEMS | Route Marker service, Speed Potion speed integration | Opus 5 | DONE + lead-reviewed 07:02 UTC: ServerScriptService/RouteMarkerService.Script.lua (new, 300 lines: client sends only "place", geometry from the server-side root, Consume via ZyntraInventory, oldest retired at the cap, markers survive death/leave, cleared at round end), NoiseReporter +29 lines (one multiplier in applySpeed, edge re-apply in the in-round loop), test_route_markers.py 189, test_speed_potion.py 498, controller_input 120 unchanged. Balance: boosted sprint 28.6 outruns only the pre-fuse Level 1 entity (27.2); L3 blackout 31.2, enraged slide 32 still faster. Refusal strings sent to A-HUD |
| A-HUD | #101 equipment HUD + potion/marker controls | Opus 5 | running |
| A-EXIT | #74 hold-to-leave | Opus 5 | DONE + lead-reviewed 06:48 UTC: Round Exit Client rewritten (hold L / hold chip 1.5 s, per-frame cancel list, one request, dead-player card kept), test_round_exit_hold.py 294 checks (mutation-probed), test_ui_style.py 83 still green. Needs Studio: real mouse lock, real touch, chip text fit |
| A-BOARD | #100 board columns | Opus 5 | DONE + lead-reviewed 06:34 UTC: TunnelLobbyBuilder addDonationLeaderboard (3 fixed columns, footer gone), test_donation_board_columns.py 826 checks; lead re-shaped the #78 section of test_lobby_palette.py (888 checks). Native check still needed: real TextBounds + a screenshot (full-bleed row plates, left-aligned empty-board message) |
| A-SHOP-UI | #102 terminal redesign, #88 square button, tab mounts, item cards | Opus 5 | running |
| A-SHOP-WALL | #102 physical shop (after A-BOARD releases the builder) | Opus 5 | running |

Owner decisions applied: milestones 5/15/35 -> token/potion/shield; wheel 45/20/20/5/10 for
1 token / 3 tokens / 1 potion / 2 potions / 1 shield; casings and results frame rejected;
no paid spins, no new Robux products, no price changes.

Next for the lead: review each agent report + `git diff` per file, run every new test, then
wait for Codex to release Studio for script creation, push, compile probe, parity, native QA.

## 06:34 UTC — first landing

A-BOARD landed and is reviewed (see table). TunnelLobbyBuilder released to A-SHOP-WALL.
Known transient red: `test_leaderboard_backfill.py` fails while A-SERVER's ZyntraMonetization
edit is in flight; A-SERVER's brief requires it green before it reports.

## 06:37 UTC — Studio handed to Claude

Codex: animation 119040885264927 integrated, Level 3 Configuration + Table Hiding Client +
manifest synced (do not pull over them). Lead now runs `pull --audit` for a baseline and will
create the six new scripts + push reviewed files as agents land. Texture needs go to
texture-requests.md (A-SHOP-WALL writes them early so Codex can generate in parallel).

## 06:45 UTC — Studio baseline

`pull --audit`: Studio == HEAD for every script except the 8 the agents are editing (repo newer,
expected) and the 6 new mirror files not yet in Studio (expected). Codex's two Level 3 files
match. Studio compile probe is blocked by the sandboxed assistant thread again (cannot reparent
into ServerStorage), so the compile proof is offline `luau-compile --binary` over the whole
mirror (baseline green). New scripts will be created with `tools/install_new_scripts.py`
(multi_edit path that worked on 2026-09-15).

## 06:55 UTC — first Studio writes

- `ReplicatedStorage.ZyntraDailyRewardsPage` created in Studio via `tools/install_new_scripts.py`
  (byte-verified, manifest item synced; manifest now 136 scripts / 150 items).
- `Round Exit Client` pushed with `push_repo_to_studio.py --file` (19273 B, verified; backup in
  `.studio-push-backups/20260916-064222`). Studio compile probe cannot run (sandboxed
  assistant thread); offline `luau-compile` is the compile proof for this batch.
- Manifest: 8 files `pending-studio-push` = the agents' in-flight files (record tool marks
  every drift). Push ONLY with `--file` after lead review; never a bare push.

## 07:08 UTC — Codex textures received

codex-texture-handoff.md: crate faces Box.SpeedPotion 73457681182843 and Box.RouteMarkerPack
100856675462356 (assets/shop/). Forwarded to A-SHOP-WALL (wire into SHOP_TEXTURES, add both
token items to the wall with a token-priced card that fires BuyItem) and to A-SHOP-UI (optional
IconId on the supplies cards; the lead adds IconId to ZyntraConfig.Items after A-SERVER lands).
Studio compile probe: MCP sandbox blocks it; Codex can run the same probe from the Studio
command bar at handback. Offline luau-compile stays the interim proof.
