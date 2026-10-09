# MAP: every OTHER consumer of the legacy shop UI and of ShopUIVersion (go-live, 2026-10-07)

Read-only map. Nothing in the repo or Studio was changed. Sister maps in this folder:
`MAP-zyntrastore.md` (ZyntraStore's own lines, decisions D1-D8) and `MAP-l4.md` (the two
L4 scripts). This one covers everybody else: runtime scripts, UIRegression, tests,
tools, docs, and the Studio-side leftovers.

Basis: ZyntraStore mirror sha256 `f288523b1c68` (= Studio). The L4 mirror files are byte-equal
to their drafts (`Zyntra Shop L4`, `Zyntra Dev L4`, `ShopBinder`, `ShopData`). All line numbers
are the current working tree.

Method: grep across the mirror, `tools/` and the draft. graphify was not used for the
answers. Its report is from 2026-09-16 (commit `a6551306`, HEAD is `1be05fc`), it predates
every L4 file, and `graphify explain "ZyntraStore"` returns 45 ambiguous artifact copies.
Excluded: `ServerStorage/Archive`, `ServerStorage/CodexBackup_*`, worktrees,
`.studio-push-backups`, dated artifact snapshots (`artifacts/trello-*`,
`artifacts/claude-brief-*`, `_backup_*`, `_review_*`, `install/out/`), and the
generated vault `Backrooms Stay Quiet/`.

Verdicts: **NO CHANGE**, **COMMENT** (prose only), **EDIT**, **DELETE**, **RETARGET**
(the same assertion, pointed at the L4 surface), **DECIDE**.

---

## 0. Read these first: four things that break silently

1. **The lobby SHOP wall's BUY dies, and the fix both sister maps suggest breaks an existing assertion.**
   - **What dies.**
     - `Shop Display Client` 637-646 fires `PlayerScripts.ZyntraShopBuy(key)`.
     - ZyntraStore 4433-4441 answers it with `productPurchase[key]`.
     - That table is filled only by the deleted Shop cards (1884) and FIELD SUPPLIES (2338).
   - **The wall is live in both lobbies.**
     - `TunnelLobbyBuilder` 3034 builds `LobbyShopDisplay`.
     - `LobbyReimaginedPreview/Builder` 100-115 clones it into the new lobby (`R3ShopDisplay` plus `PreviewShopPressurePlates`).
   - **What the wall sells.** Ten keys: Supporter, AdvancedEquipment, Tokens4, Tokens20, EmergencyReentry, ExpeditionPack, CosmeticEquipment, SpeedPotion, RouteMarker (`LobbyShopDisplay` 139-149), plus the extra EntityDetector from `Config.Passes`.
   - **The trap.** `MAP-zyntrastore.md` D2 and `MAP-l4.md` §3 both suggest adding Tokens4 and EmergencyReentry to ShopData's `robux` loop.
     - That fails `tests/zyntra_shop_l4_harness.luau` 1896-1903, which asserts `Data.purchase("EmergencyReentry") == false` and `Data.purchase("Tokens4") == false` ("hidden ... cannot be dispatched").
     - That assertion encodes OWNER-DECISIONS.md 23-26: Tokens4 is hidden, and Re-entry is sold in context only.
     - Relaxing it would weaken an assertion.
   - **What can work.**
     - **(a)** Keep a small wall-only dispatcher beside the bridge that never goes through `ShopData.purchase`. It needs about 15 lines: `Config.Passes` key → `PromptGamePassPurchase`, `Config.Products` key → `PromptProductPurchase`, `Config.Items` key → `ZyntraAction("BuyItem", {Key = key})`. Today's `requestPurchase` (1865-1883) is the model.
     - **(b)** The owner takes Tokens4 and EmergencyReentry off the wall (`LobbyShopDisplay.DISPLAY_ORDER` and the `catalogue()` extras), and the bridge calls `ShopData.purchase`. This is L4-ROBLOX-PLAN.md open question 4, still unanswered.
     - Either way, **Shop Display Client must not prompt itself**: `tools/tests/test_lobby_shop_display.py` 70-71 asserts it.
   - **DECIDE.** Default: (a).
2. **The Emergency Re-entry price stops being live.**
   - `displayedProductPrices.EmergencyReentry` is written only by the Shop card's `GetProductInfo` (ZyntraStore 1846-1855). It is read by the kept modal (3248) and published as `ZyntraReentryPrice` (3257-3258).
   - RoundUI's PARTY DOWN card shows that attribute (RoundUI 5109).
   - After the cut, both fall back silently to `Config.Products.EmergencyReentry.Price`. The fix is D3 in `MAP-zyntrastore.md`.
3. **`test_zyntra_dev_l4.py` reads the legacy DEV tab out of the mirror.**
   - `legacy_rows()` (70-96) slices `\tlocal controls = {` … `\tlocal function sendDevCommand(command)` and asserts three payload lines.
   - The harness then proves that every legacy command has an L4 row (`zyntra_dev_l4_harness.luau` 285-360).
   - Deleting the Dev tab makes `text.index` raise. Freeze the rows into a fixture captured from `f288523b1c68`, and keep every parity assertion.
4. **`ReplicatedStorage.ZyntraSkinsPage` is orphaned.**
   - Only ZyntraStore (`TERMINAL_PAGE_MODULES`, 653) and UIRegression 5538 name it.
   - It is the legacy SKINS page, so it falls under "delete the old UI": a Studio delete, the mirror file, and its manifest item (`studio-sync-manifest.json` 157-159).
   - No test covers it.

---

## 1. ShopUIVersion: every reader and writer

| Where | Lines | What | Change |
|---|---|---|---|
| `Zyntra Shop L4` | 25-29 (header), 73-76 `wantsL4`, used at 972, 1038, 1039, 1263; listener 1317-1321 | Gates open, pill and lobby skins | EDIT (detail in `MAP-l4.md` §1) |
| `Zyntra Dev L4` | 37 (header), 135-138 `wantsL4`, used at 860; listener 913-916 (the `ShopUIVersion` arm) | Gates the dev menu | EDIT. DevAccess (line 59) remains the gate |
| `ZyntraStore` | 4035 | Comment only | Goes with the routing rewrite |
| `UIRegression` | none | The unapplied spec `patches/UIRegression.L4-lane.md` §1 adds it to `BORROWED_WORKSPACE_ATTRIBUTES` | That §1 is now moot. Drop it when the lane is written |
| Server scripts, GameManager, ZyntraMonetization | none | grep-checked | NO CHANGE |
| `tests/zyntra_shop_l4_harness.luau` | 685 (context), 967 (`ready` defaults to `"L4"`), 1177-1188, 1625, 1665-1666, 1778-1780, 2096-2097, 2385 | Flag gating and "legacy" fallbacks | §6 |
| `dev-menu/tests/zyntra_dev_l4_harness.luau` | 93, 450-485, 553-554 | Flag gating | §6 |
| `install/04_flag.luau` | whole file | Sets `"L4-dev"` on the Play server | DELETE or mark superseded |
| `install/05_qa_probe_server.luau` | 23-24 | Fails unless the flag is L4/L4-dev | EDIT: drop that precondition |
| `install/05_qa_probe_client.luau` | 92-95 | `record("flag", …)` precondition | EDIT: drop it, or assert that the attribute is absent. `test_zyntra_shop_l4.py` 53 loads this file into the harness |
| `install/02_scripts.md` 50, `install/README.md` 133, `L4-ROBLOX-PLAN.md`, `DEV-MENU-INVENTORY.md`, `patches/ZyntraStore.routing.{md,json}` | — | Describe the flag | COMMENT, or leave as history |
| `artifacts/monocode-night-20261003/coordination.md`, `artifacts/level1-quality-20261002/coordination.md`, `workflow-result-l4-prep.json` | — | Dated logs | NO CHANGE |
| **Studio** `workspace.ShopUIVersion` | — | Only 04_flag sets it, and only in Play. Whether the saved place persisted it cannot be checked offline | Studio step: clear it if it is there. Inert after the code change |

---

## 2. Runtime scripts outside ZyntraStore and the two L4 scripts

| Script | What it touches | Verdict |
|---|---|---|
| **Shop Display Client** | Fires `PlayerScripts.ZyntraShopBuy` (35, 637-646; "STILL LOADING -- TRY AGAIN" when the bridge is missing). Reads `ZyntraReentryCredits` (652) and `ZyntraOwns*`. Publishes `ZyntraShopDetailOpen` (582). Requires `ZyntraDetectorVisual` (451) | NO CHANGE in code under §0.1 (a) or (b). COMMENT 10-12 and 643 ("ZyntraStore owns the purchase … SAME product-card purchase path") |
| **LobbyShopDisplay** (server) | Comments at 19 ("into ZyntraStore's own product-card purchase path") and 62 ("ZyntraStore.COLORS restated") | COMMENT. Under §0.1 (b): EDIT `DISPLAY_ORDER` (owner decision) |
| **RoundUI** | Reads `ZyntraStoreOpen` (317), `DevPhoneOpen` (1084, 1154, 1163), `ZyntraReentryOpen/Used/Credits/Price/ProductId` (1085, 5099-5187, 5283-5284), `ZyntraShopDetailOpen` (172, 318) | NO CHANGE. L4 publishes both modal flags under the same names; re-entry stays. Only exposed to §0.2 (price). Comments 1087, 1101, 4890, 5092-5181 stay true |
| **PuzzleUI** | `detectorObstacleRect("ZyntraStore", "ZyntraOpenButton")` at 1304, 1606, 1682, 1697: the in-round ZYNTRA // DEV chip | NO CHANGE (the rail and the chip stay) |
| **ProtectionHUD** | 680-683: "ZyntraStore's status line owns these in the LOBBY". Watches `ZyntraStoreOpen`/`DevPhoneOpen` (688) | COMMENT. The lobby message surface is now L4's status/toast (`ShopData.Message`) |
| **NoiseReporter** (127, 900, 965), **FlashlightController** (404, 418), **UIDevice** (1543, 1644 `SCREEN_OWNING_MODALS`) | Attribute names only | NO CHANGE |
| **Daily Rewards Client** | Owns `OpenDailyRewards` (579-583). Its own `ZyntraPage`/`ZyntraCardKey` contract (486-494). Comments 22, 45, 82-102 copy ZyntraStore's palette **by value** | NO CHANGE. Its palette is a copy, not a require |
| **Lucky Wheel Client** | Owns `OpenLuckyWheel` (59-63). Comment 822 | NO CHANGE |
| **Level2AlertClient** (26-27, 602), **Round Exit Client** (26) | Comments that name the terminal or its probe | NO CHANGE. Still true: the terminal remains, and DisplayOrder 80 > 57 |
| **DevCheats** | Owns `DevCheatCommand`, which Zyntra Dev L4 fires (179) | NO CHANGE |
| **ZyntraRecordsPage** | Mounted by ZyntraStore with a context table (ZyntraStore 3529-3566: `player, Config, UIStyle, UIDevice, COLORS, label, button, corner, outline, action, profile, onProfile, refreshProfile, showStatus, registerLayoutHook, isVisible, contract, pageName`). Reads fit `Compact, ContentWidth, Tap, Touch` | NO CHANGE, as long as every one of those survives the cut. `DevStacked` in the fit can go |
| **ZyntraDailyRewardsPage** | Comments 62 and 607 ("ZyntraStore's own Upgrades and Shop pages") | COMMENT |
| **GameManager** (grepped directly) | Only 634 `lobby:FindFirstChild("ZyntraShopDisplay")`, the wall model | NO CHANGE |
| **ZyntraMonetization and every server script** | No flag, no client UI name | NO CHANGE (scope) |
| **TunnelLobbyBuilder** | 2417-2425: comment that no `ZyntraShopPrompt` is built any more | NO CHANGE. It is the evidence for D5 |
| **First Entry Guide, ZyntraDetectorClient / ZyntraDetectorVisual, LobbyMusicController, Friend Boost Client, HazmatSkinDriver, Lucky Wheel / Daily Rewards skins, LobbyReimaginedQueueController, R4DevGateController** | Checked: no legacy terminal names, no flag. ZyntraDetectorVisual is required only by Shop Display Client and ZyntraDetectorClient, never by ZyntraStore. No "tutorial" code names the shop | NO CHANGE |

Player-facing strings: no script outside ZyntraStore and UIRegression points players at
a legacy tab. "SUPPLIES & UPGRADES" (LobbyShopDisplay 311) and "PERMANENT UPGRADES"
(LobbyPolishScene 238) are wall signage, not routes.

---

## 3. The ZyntraStore surface that other scripts call

| Seam | Callers outside ZyntraStore | After go-live |
|---|---|---|
| `PlayerScripts.ZyntraOpenTerminal` (BindableEvent) | Shop L4 `ui.handoff` (165-169): RECORDS and SETTINGS, plus every page an import lacks. Shop L4 pill "+" fallback (1026-1029): `"Shop"`. `test_zyntra_store_compact.py` §11 | KEEP for `"Records"`/`"Settings"`. `"Rewards"` → OpenDailyRewards stays. The pill fallback and the missing-page hand-off must stop asking for shop tabs (`MAP-l4.md`) |
| `ZyntraShopUIOpen` / `ZyntraDevUIOpen` | Owned by the L4 scripts; asked by ZyntraStore | KEEP. Without a fallback, a `false` must warn (`MAP-l4.md` §2) |
| `DevPhoneCommand` | J in ZyntraStore. `tools/playtest_dev_phone.py` 136 | KEEP (J → L4 dev menu) |
| `OpenDailyRewards` / `OpenLuckyWheel` | Rail; Daily Rewards / Lucky Wheel clients | NO CHANGE |
| `ZyntraShopBuy` | Shop Display Client | §0.1 |
| `UIRegressionZyntraStoreProbe` actions | UIRegression (§4), Shop L4 QA probe (`05_qa_probe_client.luau` "kiosk"), the Shop L4 harness emulation (2399-2405) | `open`, `close`, `tabs`, `tab:`, `cards`, `scrolls`, `relayout`: KEEP. `donations`: DELETE (contract.Donations goes). `kiosk`: RETARGET, so it reports whether L4 opened. Today it returns `main.Visible`, which will always be false |
| `ZyntraShopPrompt` / `ShopRewardsPrompt` bindings | No builder makes either prompt (TunnelLobbyBuilder 2417-2425; LobbyReimaginedPreview has none; Workspace mirror has none) | Dead. D5 suggests deleting. If so, the prompt cases in `test_zyntra_store_compact.py` §11 go with it, because they only exercised the deleted binding |
| Attribute `ZyntraStoreOpen` | RoundUI, NoiseReporter, FlashlightController, ProtectionHUD, UIDevice, UIRegression, many tests | KEEP (both the terminal and L4 write it; D6) |
| Attribute `DevPhoneOpen` | RoundUI cursor, the same readers | KEEP the name. D6: ZyntraStore should stop writing it (3619) |
| Attributes `ZyntraReentry*` | RoundUI, Shop Display Client | KEEP (§0.2) |
| GUI names `ZyntraStore > ZyntraOpenButton / ZyntraShopButton / ZyntraRewardsButton / ZyntraWheelButton / ZyntraMusicButton`, with children `SectionButtonContent`, `SectionCaption`, `SquareSectionBorder` | Shop L4 rail skin (1077-1109), pill `railRight` (988-998), PuzzleUI, UIRegression | KEEP, names unchanged |
| GUI names `Terminal`, `TerminalHeader`, `TerminalTabs`, `TerminalContent`, `TerminalStatus`, `CloseTerminal`, `RewardsIntroCard`, `ZyntraReentryModal` | UIRegression | KEEP |
| GUI names `UpgradeCards`, `ShopCards`, `ShopDetail`, `FieldSupplies`, `DonationCards`, `ColorPickers`, `DevControls`, `DevIntro`, `GrantResearchTokens` | UIRegression (5046) and `tools/playtest_dev_phone.py` only | DELETED with the pages. Their readers are in §4 and §7 |

**Markers that tests slice from ZyntraStore and that must survive the cut.** Keep them verbatim and in this order:

- `local reentryDead = false` → `local COLORS =`
- `local COLORS = {` → `local gui = Instance.new("ScreenGui")`
- `local function corner(parent, radius)` → `-- Imagegen section art`
- `-- RAIL_DOTS_20260922 BEGIN/END` and `-- REWARDS_INTRO_20260922 BEGIN/END`
- `player:SetAttribute("ZyntraReentryOpen", nil)` → `local function refreshUI()` (keep the name `refreshUI` even when it shrinks)
- `local updateVisibility\n` → `function updateVisibility()`
- `local openButton = button(gui,` → `-- C5_ZYNTRA_OPEN_BUTTON_20260829`
- `-- The two lobby modals that are NOT this terminal` → `\n-- Lobby supply kiosks use`, and the routing markers that `test_zyntra_store_compact.py` 1199-1207 uses (these change if D5 lands, see §5)
- the name `displayedProductPrices` (test_reentry_dismissal.py stubs it)

---

## 4. UIRegression (`ReplicatedStorage/UIRegression.ModuleScript.lua`, 9457 lines)

| Lines | What | Verdict |
|---|---|---|
| 394-500 | `FULLSCREEN_OVERLAYS`/`INTERNAL_PANELS` hold `Terminal`, `TerminalHeader`. `KEYBOARD_PATTERNS` holds `"PHONE:%s*%u"` and the dev-row `"//%s+%u"` idiom | KEEP. The shell stays; the patterns are generic. The L4 window's nodes (`Root`, `ShopWindow`) are in neither list, so see the next row |
| 995-1117 `resetScenario` | Closes only the legacy terminal (probe `close`) and resets the rail | EDIT. Also close `PlayerGui.ZyntraShopL4.UIRegressionZyntraShopL4Probe` and `PlayerGui.ZyntraDevL4.UIRegressionZyntraDevL4Probe` (`close`), each when present. Otherwise an L4 window left open makes every scenario row report overlaps |
| 1375-1397 row `store-modal` | Opens through probe `open` + `relayout`; Requires the shell; Forbids the five rail buttons | KEEP. After the cut it opens on whatever survives (Records/Settings). Add `probe:Invoke("tab:Settings")` before `relayout` so it is deterministic |
| 1398-1414 row `store-modal-dev` | `tab:Dev` | DELETE (the Dev tab is gone). Optional replacement: a `dev-menu-l4` row that opens through `UIRegressionZyntraDevL4Probe "open"` and Requires the DevWindow nodes |
| 1789-1793 `REQUIRED_GUIS` | Includes `ZyntraStore` | KEEP. Add `ZyntraShopL4`: the gui exists only when the L4 modules loaded (Shop L4 101-102 returns before 1273), so a missing install becomes a named failure. That matches "must warn clearly". Do not add `ZyntraDevL4`: non-developers never get it |
| 1809-1819 `donationTierCount` | Used only at 5939 (Donate) | DELETE |
| 1821-1851 `PAGE_CONTENT` | Upgrades, Shop, Skins, Donate, Colors, Settings, Records, Dev | DELETE the rows Upgrades, Shop, Skins, Donate, Colors and Dev. KEEP Settings and Records |
| 2206-2215 `BORROWED_WORKSPACE_ATTRIBUTES` | No ShopUIVersion | NO CHANGE (the spec's §1 is moot) |
| 2217-2245 borrowed player attributes and `BORROWED_GUIS` | `ZyntraStoreOpen`, `DevPhoneOpen`, `ZyntraStore` | KEEP. Add `ZyntraShopL4`, `ZyntraDevL4` and `ZyntraLobbyPillL4` only when a lane starts mutating them |
| 2360-2410, 2420-2441, 2552-2600 `Fit.borrow`/`restore`/`residue` | Snapshot the selected terminal tab and the open state through the probe | KEEP (still valid for Records/Settings). L4 open state is not borrowed; add it with the L4 lane |
| 4592-4606 `DEV_CAPTION_KEYS`, `DEV_INTRO_*`, `DEV_NOCLIP_*` | Mirror the legacy Dev `controls` keys | RETARGET together with the block at 5041-5120. Zyntra Dev L4 carries the same contract: `ROWS` Key fields 75-89 match B/B/V/P/I/U/C/K/O, the noclip `KeyCopy`/`TouchCopy` 82-83 are the same strings, and 318-320 key the chip and copy off `SuppressesKeyboardGlyphs`. Read the L4 window through its probe instead of `terminal:FindFirstChild("Dev")`. Deleting the block outright would drop a still-true contract. `DEV_INTRO_*` has no L4 equivalent (L4 has no "PHONE: J" line), so those two checks go with the legacy intro |
| 4655-4700 exclusion-lane setup | `baselineDevPage = terminal:FindFirstChild("Dev", true)` at 4690 | DELETE that baseline. The rest (opener, shade, terminal, probe) stays |
| 4963-4980 | "lobby briefing: both toggle AND kiosk open the terminal" | RETARGET the kiosk half: kiosk now opens L4. Assert `ZyntraShopL4` Root visible and `ZyntraStoreOpen == true`, and that the panel still yields. The toggle half (probe `open` → terminal) stays |
| 5004-5010 | "queue open: toggle and kiosk refuse" | KEEP. It still holds because L4 `openShop` refuses under `QueueModalOpen` (Shop L4 973), but only once the probe's `kiosk` returns L4's answer (§3). Otherwise it passes vacuously |
| 5041-5120 | Developer-page captions follow the input mode (`DevControls`, `DevIntro`) | RETARGET (see 4592) |
| 5231 `Fit.ZyntraFloorFallback` | — | KEEP |
| 5237-5241 `Fit.DonationTierKeys` | Donate oracle | DELETE |
| 5279-5283 `Fit.ZyntraDisabledCaptions` | Patterns | KEEP unchanged. The L4 lane spec (§2) reuses OWNED/COMING SOON/WAITING/UNAVAILABLE/CONFIRMING/SAVING/EQUIPPED/LOCKED; Dev L4 draws WHEN DEAD/LEVEL n ONLY/WAITING (276-277) for a retargeted dev check. Removing entries is not needed |
| 5298-5317 `Fit.ZyntraExpectedActive` | Upgrades=4, Colors=2, Records=1 | DELETE Upgrades and Colors; KEEP Records |
| 5427-6425 `ZyntraTerminalFitMatrix` | | Partial: |
| . 5440-5530, 5626-5870 | Shell: the terminal inside ModalViewport, header/close, rect order, the opener hidden behind it, movement suppression, tab-bar fit | KEEP |
| . 5537-5565 | `expectedTabs = {Upgrades, Shop, (Skins), Donate, Colors, (Records), Settings, (Dev)}` | EDIT to `{(Records), Settings}`. Replace the `devExpected` arm with an assertion that `Dev` is ABSENT even under DevAccess. That makes it a stronger contract, not a weaker one |
| . 5570-5625 | Donation tier oracle (`probe "donations"`) | DELETE |
| . 5868-6100 | Per-tab sweep (page exists, scroll inside page, rows, order, reachability, clipping) | KEEP. It now runs over Records and Settings |
| . 5936-5941, 6113-6135, 6139-6160, 6231-6310, 6321-6360 | `name == "Donate"`, `"Shop"`, `"Colors"` branches, including 6240 `refreshDonationOwnership` | DELETE |
| 8335, 8863-8969 | `ZyntraStoreOpen`/`DevPhoneOpen` modal lists in the control-zone and exclusion-timing lanes | NO CHANGE |
| 9305 `RunAll` | Composes `ZyntraTerminalFitMatrix` | KEEP. Add `ZyntraShopL4FitMatrix` when `patches/UIRegression.L4-lane.md` lands. Until then the L4 shop has **no** UIRegression coverage, so say so in the go-live note |

**New for everyone.** `ZyntraLobbyPillL4` (DisplayOrder 55, top right, left of the Friend
Boost column) will show in every lobby scenario row, for every account. Until now it showed
only for L4-dev developers. Expect the scenario matrix to measure it the first time it runs
on a non-developer account.

---

## 5. tools/tests (offline)

Baselines are in `MAP-zyntrastore.md` §7: compact, controller, lobby-shop-display,
daily-rewards-client and lucky-wheel-client **already fail at HEAD**, for unrelated stale
fakes. Fix nothing here by bending an assert.

| Test | Exercises | After go-live |
|---|---|---|
| **test_zyntra_store_compact.py** | | |
| . §1-3 (90-171) | Upgrades/Shop tier tables, the 330px card, touch tiers, tap floors | DELETE: only the deleted Upgrades and Shop cards |
| . §4 (173-184) | 1180x760 panel, clamp, `compact` rule | KEEP (the shell) |
| . §5, 5a, 5c (186-252) | Square rail, enumerated once, icons/captions | KEEP |
| . §5b (217-232) | Items names pin the FIELD SUPPLIES contract keys | DELETE with the supplies cards. L4 covers the payload: harness 1284 `BuyItem {Key = SpeedPotion}` |
| . §6 TAB_TESTS (339-378) | Tab set incl. Upgrades/Shop/Donate/Colors/Dev | EDIT to the new set: `Settings`, `Records,Settings`, and **no Dev even with `devAllowed = true`**. Keep the "no Rewards / no Notes tab" assertions |
| . §7 SUPPLIES (380-460, 1008-1064) | FIELD SUPPLIES | DELETE (covered by the L4 harness, as above) |
| . §8 SHOP hook (461-527, 1066-1093) | Shop list + detail | DELETE |
| . §9-10 rail and layout (528-830) | — | KEEP |
| . §11 ROUTING (829-931) | | EDIT. KEEP: REWARDS/WHEEL fire their events, the three refusals on both buttons, `ZyntraOpenTerminal "Rewards"` → modal, "Rewords" does not reach the modal, the impostor warn. CHANGE: "SHOPS opens the terminal on Shop" becomes "SHOPS asks `ZyntraShopUIOpen` for Shop and never opens the terminal" (the fixture gains a fake bridge). `terminalEvent:Fire('Notes')` and the unknown/no-tab "falls back to Shop" cases follow the new rule (Records/Settings open the terminal; any other name goes to L4 or does nothing). DELETE the `rewardsPrompt`/`shopPrompt` cases if D5 deletes the binding. Update the `pages` fixture (1215) and the slices at 1199-1207 to the new markers |
| . §12 MODALS (933-966) | UIDevice list | KEEP |
| . docstring and final print | Name the tiers | EDIT |
| **test_lobby_shop_display.py** | 82-83: the tier expression must exist in ZyntraStore (a drift partner for the card) | DELETE 82-83: its partner (Upgrades/Shop tiers) is deleted, and line 81 still pins the card's own expression. The bridge fake at 877-884 needs no change. The docstring (34) and the "ZyntraStore" comment (69) become COMMENT edits |
| **test_controller_input.py** | 163: slices the terminal focus code (kept). Fixture `tabButtons = {Shop, Dev}` (144-145), `currentTab = 'Shop'` | EDIT the fixture names to Records/Settings. Same assertions |
| **test_daily_rewards_page.py, test_zyntra_records_page.py** | Slice COLORS and helpers (markers in §3) | NO CHANGE if the markers survive. `fitFor` in records 182 carries `DevStacked`; optional removal to mirror the published fit |
| **test_reentry_dismissal.py, test_dev_free_respawn_offer.py** | Re-entry slices | NO CHANGE if the markers survive (§0.2 may add a price fetch inside the slice: re-run both) |
| **test_rail_dots_intro.py** | RAIL_DOTS / REWARDS_INTRO blocks | NO CHANGE |
| **test_friend_boost.py, test_round_exit_hold.py, test_daily_rewards_client.py, test_lucky_wheel_client.py** | Attribute names only | NO CHANGE |
| **test_zyntra_analytics.py, test_support_product_receipts.py, test_token_grants.py, test_donation_board_columns.py** | Server only | NO CHANGE |

---

## 6. Draft tests and install files (`artifacts/shop-ui-figma-20261005/roblox-draft/`)

| File | Exercises | After go-live |
|---|---|---|
| `tests/zyntra_shop_l4_harness.luau` | | |
| . 965-972 `ready` | Defaults `flag = "L4"` | EDIT: no flag |
| . 1170-1176 | "a failed bind stays failed (**legacy** every time)" | KEEP the assertions; the message changes to "nothing opens, warned" |
| . 1177-1185 | flag unset → legacy; L4-dev non-dev → legacy; L4-dev dev → L4 | DELETE (the gate is gone). REPLACE it with "a non-developer opens L4" so the open path stays asserted for ordinary accounts |
| . 1186-1192 | RECORDS/SETTINGS/DEV never L4; InRound/queue/modal refuse | KEEP |
| . 1578-1583 | RECORDS/SETTINGS hand off through `ZyntraOpenTerminal` | KEEP |
| . 1625 | close trigger "flag off" | DELETE that one trigger row |
| . 1665-1666 | "no pill without the flag" | DELETE |
| . 1778-1780, 2096-2097 | "flag unset: the rail/wheel stays legacy" | DELETE |
| . 1916-1921 | "a failed bind hands the pill's + to the legacy terminal" | EDIT: assert that nothing is fired at `ZyntraOpenTerminal` for "Shop", that a warning exists, and that the pill stands down (that last assert stays) |
| . 1896-1903 | Hidden products (Tokens4, EmergencyReentry, 3x/5x, four donation tiers) are not dispatchable | **KEEP. This assertion constrains §0.1** |
| . 2380-2427 | Emulated patched ZyntraStore under `L4-dev` + the QA probe | EDIT: drop `flag = "L4-dev"`. The emulated kiosk now has no legacy fallback |
| `tests/test_zyntra_shop_l4.py` | Loads the harness + `install/05_qa_probe_client.luau` | Follows the harness and the probe edits |
| `dev-menu/tests/zyntra_dev_l4_harness.luau` | | |
| . 93 | `ShopUIVersion` default `"L4-dev"` | EDIT: none |
| . 450-485 | "Fallback to the legacy DEV tab": the bridge answers false; "flag off: legacy", "flag on later: L4" | DELETE the flag cases. KEEP the refusal cases (queue, briefing in a round, other modal, template missing → false) and RENAME "legacy opens" to "refused". A refusal no longer opens anything |
| . 545-549 | J over the open terminal: L4 refuses and ZyntraStore toggles the terminal | KEEP. It is still the behaviour while Records/Settings are open |
| . 553-554 | "flag off closes and refuses" | DELETE |
| . 285-360 | Parity with every legacy row | KEEP. It needs the frozen fixture from §0.3 |
| `dev-menu/tests/test_zyntra_dev_l4.py` | `legacy_rows` (70-96) from the mirror; `check_store_patch` (230-251) needs mirror == `patches/ZyntraStore.shop+dev.patched.lua` | `legacy_rows`: read the frozen fixture (§0.3). `check_store_patch`: RETIRE. The hunks it verifies are deleted code, so it would fail on purpose |
| `tests/test_zyntrastore_patch.py` | `install/03_zyntrastore_patch.py` apply/revert against a frozen `_local` copy | RETIRE with 03 and `patches/ZyntraStore.routing.*`. A `--revert` would reinstate a fallback into deleted pages. It is not a deleted-UI test, but its subject (the transitional patch) dies |
| `install/04_flag.luau`, `install/05_qa_probe_*.luau` | §1 | §1 |

---

## 7. tools/ (not tests)

| File | What | Verdict |
|---|---|---|
| `tools/playtest_dev_phone.py` | Studio playtest that requires `PlayerGui.ZyntraStore.Terminal` > `Dev` > `DevControls` (18-36, 81-83, 124, 140-145) and that J opens the terminal | RETARGET to `PlayerGui.ZyntraDevL4` (`UIRegressionZyntraDevL4Probe` `open`/`state`, `DevPhoneOpen`), or RETIRE. As written it fails at its first `require` (263) |
| `tools/apply_trello_ui_finishing.py` | One-shot historical patcher for ZyntraStore and Shop Display Client | NO CHANGE. It has already been applied; do not re-run it |
| `tools/vault/build_systems.py` 584, 620-621 | Vault prose: "Klientens terminal, 2.200 linjer", the probe | COMMENT (the vault is generated and git-ignored) |

---

## 8. Docs (prose)

- `README.md`:
  - 434-436: the Settings path, "the fifth tab, after Upgrades / Shop / Donate / Colors". Now it is the header SETTINGS in L4, or the terminal.
  - 676 and 700: the `ZyntraTerminalFitMatrix` description, "every tab including DEV".
  - 835-840: the probe's `kiosk`.
  - 915: "`J` opens the Zyntra developer phone (`ZyntraStore.LocalScript`)". It now opens `Zyntra Dev L4`.
- `docs/ZYNTRA_MONETIZATION_SETUP.md` 214, 309 and 416 name `ZyntraStore.LocalScript.lua` as the shop, prompts and price display. They now point to `ReplicatedStorage.ZyntraShopUI.ShopData` and `Zyntra Shop L4`.
- `CLAUDE.md` 283-284, 309, 328, 368-370 and 489-490 describe the legacy tabs, the DEV rows in the terminal, and test_zyntra_store_compact's tiers. These are the owner's / main session's to edit. Listed here only so they are not missed.
- `artifacts/shop-ui-figma-20261005/INTEGRATION-CONTRACT.md` §5.6 "C. Later, by owner decision only" is the step being executed now. Mark it done when it lands.

---

## 9. Owner-visible consequences (not consumers, but true after the cut)

- **No longer sold anywhere in-game.** TokenEarner 3x/5x and their upgrade passes, and the donation tiers Field (100), Command (500), 5000 and 20K. This was decided in OWNER-DECISIONS.md 28-39. The server still honours existing owners.
- **Tokens4 and Emergency Re-entry.** In-game they remain only on the wall (if §0.1 (a)), in the death modal and on the PARTY DOWN card.
- **"Prices are read live from Roblox."**
  - It survives only in `Zyntra Shop L4` 57 (`TAB_HINTS.Shop`) and in the Studio template text at `ZyntraShop_L4/ShopWindow/Canvas/Footer/Status` (dump `tests/live-20261007/framewisp-dump.ZyntraShop_L4.json`).
  - `showHint` overwrites the template text on every `selectTab`, before the window is shown.
  - No test asserts the string. The removal is in `MAP-l4.md` §4.
