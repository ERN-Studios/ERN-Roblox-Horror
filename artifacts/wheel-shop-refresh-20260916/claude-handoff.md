# Wheel / Shop / Rewards / Friend Boost refresh — handoff (Claude, manager)

Clock: Windows clock, local = UTC + 2. State at 23:25 UTC, 16 September 2026.

## What is in Studio right now (== repo working copy, audit 145/145)

| Area | Files (repo mirror) | Offline checks |
|---|---|---|
| Lucky Wheel takeover | `StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua` | test_lucky_wheel_client 524 |
| Daily Rewards | `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua`, `StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua` | test_daily_rewards_page 508, test_daily_rewards_client 503 |
| Shop wall | `ServerScriptService/LobbyShopDisplay.ModuleScript.lua` (v4), `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua`, `ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua` (kiosk removed) | test_lobby_shop_display 2896, test_lobby_palette 828 |
| Friend Boost | NEW `ServerScriptService/FriendBoost.ModuleScript.lua`, NEW `StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua`, `ServerScriptService/GameManager.Script.lua` (4 call sites), `ServerScriptService/ZyntraMonetization.Script.lua` (profile field + payout), `ReplicatedStorage/ZyntraConfig.ModuleScript.lua` (`FriendBoost = {PercentPerFriend = 10}`) | test_friend_boost 318, test_token_grants 243 |

Agent reports: `agent-wheel-report.md`, `agent-daily-report.md`, `agent-shop-report.md`,
`agent-friend-report.md`. Contract: `claude-contracts.md`. Running log: `claude-status.md`.

## Decisions the owner should know about
- **Friend Boost interpretation** (the project has no invite tracking): a friend counts when
  `Player:IsFriendsWith` says so server-side AND they were a participant of the same round on the
  same server. Being friends elsewhere, or on the server but not in the round, pays nothing. The
  lobby chip shows verified friends currently on the server (updates on join/leave).
- **Friend Boost arithmetic**: 2 tokens × friends × 10% counted in tenths; the remainder is saved on
  the profile (`FriendBoostTenths`, 0..9) and whole tokens are paid as they are earned. One friend
  pays a whole extra token on the fifth clear; five friends pay +1 every clear. Only completion
  tokens; nothing else touched.
- **Shop**: eight 3.4-stud hologram boxes at relative z -66 .. -14 (7.43 apart) along the right
  wall between the Level 2 and Level 4 gates, 4.65 studs of headroom above the ledge, art on all
  six faces, no deck/sign/plinth/plaque/prompt; the kiosk, shopkeeper and access terminal are
  gone. The ZyntraStore terminal (Shops/Upgrades) is now reached ONLY from the left rail.
- **Wheel**: five EQUAL 72-degree fields on the texture (Token1 at 12 o'clock, then clockwise
  Token3, Potion1, Potion2, Shield1); the server weights are printed as odds inside each field.
  While open, every other ScreenGui in PlayerGui is disabled (and kept disabled if it re-enables
  itself) and restored on close/respawn.
- **Daily Rewards**: header gift + three card icons are Codex's uploads; no streaks, no new rewards.
- Accessibility: with ReduceFlashing or ReduceCameraShake on, the shop boxes stand still.
- **Owner feedback 2026-09-17**: product-name captions float over the boxes (BillboardGui, accent
  colour); the Daily Rewards footer keeps one line; SPECTATING NOW COUNTS toward daily playtime
  (dead / escaped / between bodies participants of an active round accrue without an AFK gate).

## Verified natively by Claude (Studio MCP only, no desktop control)
- Desktop 899x677: wheel open/spin/land (field matches the hub prize)/close with exact HUD restore;
  Daily Rewards renders with all four images loaded; Friend Boost chip "+0%" with INVITE FRIENDS;
  shop wall geometry (8 boxes, 6 decals each, nothing collidable, worst envelope r 32.900), bob
  moving, card auto-open "SHOP" / PERMANENT PASS / BUY / CLOSE, kiosk & plaque absent, no
  SUPPLY text anywhere in the lobby; console clean at boot.
- Synthetic phone layouts via the UIDevice overrides (390x844 and 844x390): wheel disc 335 / 285
  inside the safe band, hub >= 74, X 48; Daily portrait cards 150 tall with 126-px icons and 44-px
  CLAIM; touch takeover hides StaminaGui/RUN and restores it.

## Open / pending
- (done 23:20 UTC) Landscape phones: the countdown folds into the play strip and the cards shrink
  to 162 so CLAIM sits inside the 214-px content box (measured 286 <= 294 at 844x390).
- Real-device pass (iPhone emulator / phone), the two-account Friend Boost test and the final
  approval are the OWNER's (see `owner-test-checklist.md`). Note: Studio's Device Simulator still
  reports a mouse and keyboard, so set `workspace:SetAttribute("ForceTouchUI", true)` in the
  command bar to see the touch tiers there.
- Publish only after the owner's approval; then verify the version in the Creator Dashboard, save
  the .rbxl backup to `_local/wheel-shop-refresh-20260916/`, update Trello #103/#104/#105 (the only
  cards this work delivers; #106/#107 are untouched), commit.
