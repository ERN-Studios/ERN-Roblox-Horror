# CHANGES: ZyntraStore go-live cut (2026-10-07)

Owner order (2026-10-07): L4 goes live and replaces the old UI; delete the old UI; no other
backdrops removed; remove "Prices are read live from Roblox.".

| | Before | After |
|---|---|---|
| File | `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` | same |
| sha256 | `f288523b1c68...` (Studio holds this) | `f1eaf2dd0006baef937ef62e76b90cefe6436733d456da801b5a525d8f806229` |
| Lines / bytes | 4441 / 203979 | 2169 / 102289 |
| Register headroom (luau-compile 0.737 `-O0`, extra main-chunk locals) | **45** free | **79** free |
| `luau-analyze` lints | 4 | 2 (both pre-existing: `shopButtonRing` unused, one same-line statement) |

Backup of the legacy build: `go-live/backup/ZyntraStore.LocalScript.f288523b1c68.lua`
(byte-identical to Studio). Test backups sit beside it. Line numbers below refer to the
backup. Nothing was done in Studio or git, and the manifest was not touched.

## 1. Deleted blocks

| Backup lines | What | Why |
|---|---|---|
| 8-11 | `deviceCaptionRefreshers` and its comment | Only the DEV page registered into it |
| 19 | `ProtectionClient` require | Only the Shop TokenItem buy path and the Entity Shield card used it |
| 20 | `PCT` | Only the Upgrades Spend caption used it |
| 23 | `level3TimelineOwner` | Only the DEV page's SKIP TO BLACKOUT row used it |
| 31-35 | `productButtons`, `productPurchase` and their comment | Filled and read only by the Shop, Donate and Upgrades cards and refreshUI's OWNED loop. The wall bridge no longer needs a table (section 2) |
| 502 (field) | `contract.Donations` | Only the Donate page wrote it and only the probe's `donations` action read it |
| 653, 655 (entries) | `Skins = "ZyntraSkinsPage"`; `"Upgrades", "Shop", "Skins", "Donate", "Colors"` in the tab list | The tab set is now `{"Records", "Settings"}` |
| 661 | `if devAllowed then table.insert(tabNames, "Dev") end` | The DEV tab is gone, for developers too |
| 709-1372 | The DEV page: intro, GIVE RESEARCH TOKENS form, the 11+1 `controls` rows, `sendDevCommand`, row builder, caption refreshers, and the readbacks of respawn, pump and timeline | Replaced by "Zyntra Dev L4" |
| 1373-1592 | UPGRADES page: intro, scroll, grid, `makeUpgradeCard`, STAMINA/BATTERY cards, 3-tier hook | Replaced by the L4 Upgrades page |
| 1594-1740 | SHOP page: ShopCards scroll and grid, `productCards`, `shopDetail`, the SHOP_GRID hook | Replaced by the L4 Shop page |
| 1742-1896 | `makeProductCard`: icon, tags, Buy, Select, live price, `requestPurchase` | Shop page |
| 1898-1918 | The 8 product cards and the Token Earner 2x/3x/5x cards | Shop page |
| 1919-1965 | Token Earner live prices (`verifiedEarnerPrice`, `renderEarner`) | Shop page |
| 1967-2239 | The ShopDetail pane, **including DetailNote "Prices are read live from Roblox." (2037)** | Shop page; also the owner's text order |
| 2241-2273 | Entity Shield card | Upgrades page |
| 2275-2404 | FIELD SUPPLIES (SpeedPotion, RouteMarker) | Upgrades page |
| 2406-2606 | DONATE page: total, cards, hook, `makeDonationCard`, `donationEntries` | Replaced by the L4 Donate page |
| 2608-2899 | COLORS page: pickers, `HUE_SEQUENCE`, `makeColorPicker`, `hazmatPicker`, `glowstickPicker` | Replaced by the L4 Colors page |
| 3332-3375 | refreshUI's page-only body: donation totals, Spend text and its `applyTerminalLayout()`, upgrade readouts, the OWNED loop, `renderEarner`, the pickers | Its targets are deleted. Tokens, `updateReentry()` and the page-module refresh stay |
| 3617-3619 | `player:SetAttribute("DevPhoneOpen", ...)` in `setMainVisible` | The terminal is no longer the dev phone; Dev L4 is the only writer. Together with the D7 change below, keeping it would have fought Dev L4's re-assert on every in-round `updateVisibility` |
| 3979 | `selectTab("Dev")` (in `toggleMain`) | DEV tab gone |
| 4015-4018 | `boundShopPrompts` and the kiosk comment | Dead: no builder makes a `ZyntraShopPrompt` any more (TunnelLobbyBuilder 2417-2425). The binding listened to every `workspace.DescendantAdded` |
| 4088-4092 | Probe action `donations` | `contract.Donations` is gone |
| 4107-4122 | `bindShopPrompt`, the `workspace:GetDescendants()` scan and the `DescendantAdded` listener | Same dead binding as 4015-4018 |
| 4169-4182 | DEV tab hand-off to L4 (`ZyntraDevUIOpen(true, "terminal")`) | DEV tab gone; the L4 side is dropping the `from` parameter too |
| 4417-4423 | The `deviceCaptionRefreshers` loop in `UIDevice.Changed` | Only the DEV page registered into it |

## 2. Rewritten (kept, new behaviour)

| Backup lines | Now | Notes |
|---|---|---|
| 1-2 | File header | Describes the rail, RECORDS/SETTINGS, re-entry and the wall bridge, plus where the backup is |
| 30 | `currentTab = "Settings"` | `"Upgrades"` no longer exists (D8). Settings is always built |
| 633-652 | Tab comment | Two tabs; no shop page and no DEV tab, even for developers |
| 3264 (re-entry `do`) | **Live Emergency Re-entry price** (D3): one `GetProductInfo` in a `task.spawn`, all inside `pcall`, writes `displayedProductPrices.EmergencyReentry` and calls `updateReentry()` | Before, only the deleted Shop card fetched it. Without this, the modal and RoundUI's PARTY DOWN card (through `ZyntraReentryPrice`) would silently show the config 29 R$. No new top-level local |
| 3934 | `if inRound then setMainVisible(false) end` | Was `inRound and not devAllowed` (D7). In a round the terminal was only ever the dev phone |
| 3958-3982 | `toggleMain` becomes `toggleDevMenu(requested)` | Developers only. Asks `PlayerScripts.ZyntraDevUIOpen`, and its answer is final. A missing bridge warns by name. On a refusal it only closes an open RECORDS/SETTINGS terminal (J over the terminal); it never opens anything |
| 4020-4050 | `openTerminal(tab)` + `openKioskShop(tab)` | `"Rewards"` opens Daily Rewards. A tab the terminal has (Records, Settings) runs `openTerminal` with the old guards. Anything else (nil = `"Shop"`) asks `PlayerScripts.ZyntraShopUIOpen`, and the answer is final. A missing bridge warns by name. The function returns whether something opened |
| 4064-4068 | Probe: `open` runs `openTerminal(currentTab)`; `kiosk` returns `openKioskShop()` | UIRegression still opens the terminal through `open`; `kiosk` now reports L4's answer (MAP-consumers §3) |
| 4133-4144 | `DevPhoneCommand.Event:Connect(toggleDevMenu)` | Lobby and round alike |
| 4151-4161 | `openButton.Activated`: in a round it runs `toggleDevMenu()` (the touch dev chip); in the lobby it runs `openKioskShop("Upgrades")` | No terminal fallback |
| 4186 | J fallback runs `toggleDevMenu()` | Was `toggleMain()` |
| 4427-4441 | **Wall buy bridge** (D2, option (a)): `PlayerScripts.ZyntraShopBuy` dispatches by Config table. `Passes[key]` runs `PromptGamePassPurchase`. `Products[key]` runs `PromptProductPurchase`. `Items[key]` fires `ZyntraAction "BuyItem" {Key}`. An Id <= 0 warns; an unknown key is ignored | It used to run the deleted cards' buy. It deliberately does not go through `ShopData.purchase`, which must keep refusing Tokens4 and EmergencyReentry (L4 harness 1896-1903, owner decision). It uses the same three tables as `LobbyShopDisplay.catalogue()` |
| Comments: 3000, 3091-3092, 3514-3516, 3684-3685, 3939-3940, 4005, 4059-4060, 4073-4074, 4279, 4388-4392, 4215 area | Reworded | They named DEV, Shop, Colors or the plaque prompt |

## 3. Kept whole

The lobby rail (all five button names and children, the dots, the intro card), Settings (it also wires the
Music button), the Rewards and Wheel openers, `ZyntraOpenTerminal` (its handler is now `openKioskShop`),
the re-entry modal and its four attributes, FREE RESPAWN // DEV, the PARTY DOWN listeners, gamepad focus
and ButtonB, `applyTerminalLayout` (with `fit.DevStacked`, which the Settings rows and the Records test use),
the Records mount `ctx`, and every marker the tests slice by (MAP-consumers §3), including `refreshUI`
and `displayedProductPrices`.

## 4. Tests (`tools/tests`, luau 0.737)

| Test | Baseline (f288523b) | After | Change |
|---|---|---|---|
| test_zyntra_store_compact.py | FAIL (stale "shop cell height", which measured deleted code) | **PASS, 417 checks** | **Deleted:** §1-3 and their module-level tier-table extraction, which only measured the deleted Upgrades and Shop cards; the §5b FIELD SUPPLIES key checks; the §7 `supplies` and `supplies-absent` lanes; the §8 Shop-hook lane. All of these exercised deleted UI only. **Rewritten:** §6 tabs: Records,Settings, with no shop page and no DEV even for a developer or with a stale ZyntraSkinsPage in the place, so the check is stricter. §11 routing: SHOPS, UPGRADES and every non-terminal name ask L4 only; the refusal is final; a throwing bridge opens nothing; a missing bridge warns; RECORDS/SETTINGS open the terminal under the guards; the dev route goes to Dev L4 only and J closes the terminal on refusal. The `ZyntraShopPrompt` cases were deleted with the dead binding. **Added:** source checks that the deleted UI and the "Prices are read live from Roblox" text are absent, and a §13 `wallbuy` lane (13 checks). Two mutations were tried (a refusal falling back to the terminal; a dev refusal opening the terminal) and both fail the suite |
| test_controller_input.py | FAIL (stale NoiseReporter fake) | **PASS, 120** | Fixture tabs renamed Shop/Dev to Records/Settings, with the same assertions. Stale fake fixed by adding stubs: `inPreview`, `workspace`, and the real `isHiding` slice |
| test_reentry_dismissal.py | PASS 37 | **PASS 37 + 5** | New live-price lane: one `GetProductInfo(77, Product)`, `ZyntraReentryPrice` = 35, button "35 R$  //  BUY CREDIT" |
| test_dev_free_respawn_offer.py | PASS | PASS (17/24/3/8) | none |
| test_lobby_shop_display.py | FAIL (8 vs 10 product textures, server module) | same FAIL, same line | Deleted 82-83: the `STORE` tier-expression assert, whose drift partner (Upgrades/Shop tiers) is deleted. Line 81 still pins the card's own expression |
| test_daily_rewards_page / test_zyntra_records_page / test_rail_dots_intro / test_friend_boost / test_round_exit_hold | PASS | PASS (521 / 11768 / 20 / 717 / 299) | none |
| test_daily_rewards_client / test_lucky_wheel_client | FAIL (boot fake: nil `Connect`; missing ZyntraSkins fixture) | same FAIL | none. Neither reads ZyntraStore code |

Draft tests (owned by the L4 agent, run read-only against the new mirror): `test_zyntra_shop_l4.py`
passes 1150 checks; `test_zyntra_dev_l4.py` passes 6837 and reports "ZyntraStore ... no DEV tab, no hand-over".

## 5. Left for the main session

- **Studio push** of ZyntraStore (`record_pending_push.py`, then push). New sha above.
  Watch for: UIRegression's `donations` probe action is gone, and `kiosk` now returns L4's boolean.
- **ZyntraSkinsPage is orphaned.** Nothing mounts it now. Delete it in Studio, in
  `ReplicatedStorage/ZyntraSkinsPage.ModuleScript.lua`, and in its manifest item (lines 157-159), all
  together. The mirror file was left in place so the mirror does not drift from Studio.
- **D1 (open): touch developers in the lobby have no route to the dev menu.** J needs a keyboard, and the
  ZYNTRA // DEV chip shows only in a round. The DEV tab button was not kept, because the scope deletes the
  tab and UIRegression will assert it is absent. Options: a DEV entry in the L4 header (L4 agent), or a
  lobby dev chip.
- `tools/playtest_dev_phone.py` (a Studio playtest outside tools/tests) still drives the legacy DEV page.
  Retarget it to `ZyntraDevL4` or retire it; it needs Studio to verify.
- The comments that name the old purchase path in other scripts were left alone, so the push stays one
  script: Shop Display Client 10-12 and 643, ProtectionHUD 680-683, ZyntraDailyRewardsPage 62 and 607,
  LobbyShopDisplay 19, 62 and 134.
- Two behaviour notes on the wall:
  - A token-item BUY no longer shares the deleted supplies card's SAVING latch. The server's 1 s
    per-action window is the double-press guard.
  - An unconfigured product id warns in the console. Before, the message went to the hidden terminal's
    status line.

## 6. Review fixes (2026-10-07, second pass)

| | After go-live | Now |
|---|---|---|
| sha256 | `f1eaf2dd0006...` | `703647cb5003ad3e1e3b7030c8f6c5ed457f190948457c0f8a07fdcab609a9dc` |
| Lines / bytes | 2169 / 102289 | 2190 / 103281 |
| Register headroom (top-of-chunk padding; the same method reads 44 for the legacy build recorded as 45 above) | 79 | **83** |
| `luau-analyze` lints | 2 | 2 (the same two) |

Studio and Codex were not used. One read-only `git show` was issued by mistake while comparing lints;
it changed nothing and its output was discarded.

### What changed

1. **The L4 graft covered the in-round ZYNTRA // DEV chip** (finding at line 1690).
   - `updateVisibility` now runs one loop over `railButtons`:
     - `L4Skin_Face.Visible = sectionIconsVisible`;
     - `SectionButtonContent.Visible = sectionIconsVisible and not skin`.
   - The five `*ButtonSections` locals are now plain `sectionButtonContent(...)` calls. Only the five lines this loop replaces read them.
   - **New hook:** a `ChildAdded` hook on each rail button re-runs `updateVisibility` when an `L4Skin_Face` lands. skinRail can graft after a round has already turned UPGRADES into the chip, for example on a reserved-server join.
   - **Second bug, fixed by the same rule:** every lobby `updateVisibility` pass used to show the legacy SectionButtonContent again under the graft that L4 had hidden once.
2. **The wall's token items could buy twice** (finding at line 2164).
   - `Config.Items` keys now call `require(ReplicatedStorage.ZyntraShopUI.ShopData).purchase(key)`, the module instance that "Zyntra Shop L4" started. That brings:
     - the pending latch the L4 cards use, cleared by the next profile push or after 6 s;
     - the balance check;
     - the hold past the server's 1 s window.
   - Passes and Products still prompt directly, so ShopData still refuses Tokens4 and EmergencyReentry.
   - A missing ShopData warns by name.
   - **Behaviour change:** a BUY that the balance cannot cover now sends nothing. Before, the server refused it.
3. **There was no lobby dev entry without a keyboard** (finding at line 1893).
   - Fixed on the L4 side: a DEV header button (see CHANGES-l4.md). Only the header comment changed here.
   - **Option (b) was not taken.** In the lobby, `openButton` is the UPGRADES square, so a lobby chip would take UPGRADES away from every touch developer.

### Tests

`tools/tests/test_zyntra_store_compact.py` (CRLF kept): **417 -> 485 checks**.

- **5a.** The `ipairs(railButtons)` pin is still an exact count, now 5 instead of 3. The two new loops are the graft rule and its hook. Two new source checks:
  - no `*ButtonSections.Visible =` line is left;
  - the `ChildAdded` hook is present.
- **New lane `chipskin` (57 checks)** runs the production block through five rail states:
  - skinned, in the lobby;
  - skinned, as the in-round chip;
  - back in the lobby;
  - unskinned;
  - partly skinned (lobby and chip).
- **routing (+3 checks).** For a developer in the lobby:
  - UPGRADES and SHOPS reach the L4 shop and never the dev menu or the terminal. The shop's DEV header is the touch and gamepad entry.
  - J asks the dev menu.
- **wallbuy (13 -> 19 checks).** The lane now loads the real ShopData behind fake remotes. Added checks:
  - a second BUY during the write fires nothing;
  - after the push, the next BUY waits out the server window and then fires once;
  - a BUY the balance cannot cover fires nothing;
  - a missing ShopData warns and fires nothing.

  The existing assertions are unchanged.
- **Mutations**, each caught:
  - a direct `FireServer` again (fails "a second BUY during the write fires nothing");
  - the graft always visible;
  - the legacy content not tied to the graft;
  - the hook removed.

**Full `tools/tests` run: 65 of 87 pass.** All 22 failures are pre-existing:
- Three read ZyntraStore, and each fails at the line recorded in section 4:
  - lobby_shop_display: 8 vs 10 textures;
  - daily_rewards_client: nil `Connect`;
  - lucky_wheel_client: missing ZyntraSkins fixture.
- `test_full_sync_contract` lists four files whose canonical content differs from the manifest, which means a push is pending: UIRegression, SoundController, ZyntraStore and Kit World Builder. ZyntraStore was already LF and on that list after the go-live.
- `test_push_repo_to_studio` cannot run `luau --version`.
- The other 17 read none of the files changed here: ZyntraMonetization, Levels 1-3, NoiseReporter, Round Entry Client and First Entry Guide.

### Left for the main session

- **Push ZyntraStore** (new sha above), together with Zyntra Shop L4 and Zyntra Dev L4. At press time the wall needs `ReplicatedStorage.ZyntraShopUI.ShopData`, which is already installed and in the manifest.
- **ZyntraSkinsPage can go now.** The finding's condition is met: L4 has the developer suit's equip route. Delete it in Studio, in the mirror and in the manifest together, as section 5 says.
