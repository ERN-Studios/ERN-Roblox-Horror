# Coordination — 2026-09-16

Studio: **Codex** — reclaimed around 06:54 UTC on 16 September 2026 after Claude reached its session limit. Native UI confirmed limit; the last A-SHOP-WALL agent was explicitly stopped and no agents remain running. Studio is in Edit. Codex owns all remaining code, assets, integration, QA and release. Prior ownership below is historical.
Animation is uploaded, integrated, native-tested and source-parity verified. Read
`codex-animation-handoff.md`. Codex does not operate Studio until a coordinated handback.
Codex owns: assets/animations/table-hiding, animation authoring tools, Level 3 Configuration,
Level 3 Hiding Controller, Level 3 Table Hiding Client, generated textures.
Claude (Fable 5.1 lead + Opus 5 agents) owns all other approved feature code and tests.
Claude checkpoints: claude-status.md and claude-handoff.md at every meaningful milestone.
Contracts every agent builds against: claude-contracts.md.

## File ownership (Claude side, one writer per file; lead merges)

| Agent | Cards | Files (exclusive while the agent runs) |
|---|---|---|
| A-SERVER | #83 #84 #89 #85 (server) | ServerScriptService/ZyntraMonetization.Script.lua, ReplicatedStorage/ZyntraConfig.ModuleScript.lua, tools/tests/test_daily_rewards.py, test_item_inventory.py |
| A-REWARDS-UI | #83 #84 #89 (UI) | ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua (new), tools/tests/test_daily_rewards_page.py |
| A-NOTES | Field Notes (#85 extension) | ReplicatedStorage/ZyntraFieldNotes.ModuleScript.lua, ZyntraFieldNotesPage.ModuleScript.lua, ServerScriptService/FieldNotesService.Script.lua, StarterPlayerScripts/Field Notes Client.LocalScript.lua (all new), tools/tests/test_field_notes.py |
| A-ITEMS | #85 (gameplay) | ServerScriptService/RouteMarkerService.Script.lua (new), StarterPlayerScripts/NoiseReporter.LocalScript.lua, tools/tests/test_route_markers.py, test_speed_potion.py |
| A-HUD | #101 + potion/marker controls | StarterPlayerScripts/ProtectionHUD.LocalScript.lua, ReplicatedStorage/UIDevice.ModuleScript.lua (control slots only), UIRegression control allow-lists, tools/tests/test_equipment_hud.py |
| A-EXIT | #74 | StarterPlayerScripts/Round Exit Client.LocalScript.lua, tools/tests/test_round_exit_hold.py |
| A-BOARD | #100 | ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua (addDonationLeaderboard only), tools/tests/test_donation_board_columns.py — releases TunnelLobbyBuilder to A-SHOP-WALL when done |
| A-SHOP-UI | #102 (terminal) #88 (square button) + tab mounts | StarterPlayerScripts/ZyntraStore.LocalScript.lua, ReplicatedStorage/UIRegression.ModuleScript.lua (terminal rows), artifacts/trello-20260916/shop-research.md, tools/tests/test_zyntra_store_compact.py |
| A-SHOP-WALL | #102 (physical shop) | ServerScriptService/LobbyShopDisplay.ModuleScript.lua, StarterPlayerScripts/Shop Display Client.LocalScript.lua, TunnelLobbyBuilder addSupplyKiosk (after A-BOARD), tools/tests/test_lobby_shop_display.py, texture-requests.md |

Untouched by everyone: RoundUI (register limit), GameManager, Level 3 Codex files, _local/,
studio-sync-manifest.json, any Studio tool.

## Completion (lead updates)

| Item | State |
|---|---|
| Contracts written | done 06:20 UTC |
| Agents dispatched | done 06:22 UTC (nine Opus 5 agents) |
| Offline tests green per agent | pending |
| Lead review of every diff | pending |
| Studio handover from Codex | done 06:35 UTC |
| New scripts created in Studio + manifest items | waiting for Studio |
| Push + compile probe + parity audit | waiting for Studio |
| Native UI/gameplay QA | waiting for Studio |
| Publish | waiting for release checklist |

Next status check: at least 10 minutes after successful Claude dispatch.
