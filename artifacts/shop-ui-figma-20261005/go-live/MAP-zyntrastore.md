# MAP: ZyntraStore.LocalScript.lua, before the L4 go-live deletion

Subject: `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`, 4441 lines,
sha256 `f288523b1c68...` (Studio holds this exact file). This map was made read-only on
2026-10-07. Nothing in the repo or in Studio was changed. All line numbers refer to
that file.

Verdicts: **KEEP** (unchanged), **EDIT** (stays, but lines inside it change),
**REWRITE** (stays, with new behaviour), **DELETE**, **DECIDE** (an open choice for
the main session, see section 5).

---

## 1. Line ranges

| Lines | What it builds | Owner | Verdict |
|---|---|---|---|
| 1-2 | File header ("Lobby shop, +5% upgrades, product prompts, HSV pickers") | - | EDIT: describe the rail, the Records/Settings shell, re-entry and routing |
| 4-27 | Services, Config, DevAccess, remotes | shared | KEEP, except 11 `deviceCaptionRefreshers`, 19 `ProtectionClient`, 20 `PCT` and 23 `level3TimelineOwner`: DELETE (only deleted code reads them) |
| 29-38 | Session state | mixed | 29 `profile` KEEP. 30 `currentTab` KEEP, but its default `"Upgrades"` must become a surviving tab (D8). 31 `productButtons` DELETE. 32-35 `productPurchase` DELETE, unless D2 keeps the wall bridge here. 36 `displayedProductPrices` KEEP, reduced to EmergencyReentry (D3). 37-38 KEEP |
| 40-51 | `COLORS` | shared; tests slice it; page modules receive it | KEEP |
| 53-59 | ScreenGui `ZyntraStore` (DisplayOrder 55) | parent of the rail, terminal and intro card | KEEP |
| 61-115 | `corner`, `outline`, `label`, `button` | shared | KEEP. The marker comment `-- Imagegen section art` (117) must survive, because two tests slice up to it |
| 117-158 | `SECTION_IMAGES`, `SECTION_CAPTIONS`, `sectionButtonContent` | rail | KEEP |
| 160-253 | `layoutSquareSections` | rail | KEEP |
| 255-282 | `openButton` (UPGRADES, and the touch dev chip in a round), `shopButton` (SHOPS), `rewardsButton`, `wheelButton` | rail | KEEP. 269 `shopButtonRing` is never read (dead local): optional DELETE |
| 284-309 | `notificationDot`, `rewardsDot`, `wheelDot` | rail dots | KEEP |
| 311-345 | `rewardsClaimable`, `wheelClaimable`, `introWanted` (markers RAIL_DOTS_20260922 and REWARDS_INTRO_20260922) | rail dots, intro | KEEP |
| 347-372 | `musicButton`, `railButtons`, the rail border loop | rail | KEEP |
| 374-420 | `TOUCH_MIN_TAP_HEIGHT`, queue/briefing attribute names, `modalBlocksStore` | shared guards | KEEP |
| 422-475 | `main` (frame "Terminal"), `mainScale`, `layoutHooks`, `pageMounts` | terminal shell | KEEP |
| 477-524 | `contract` (tag `ZyntraTerminalAction`; Cards, Scrolls, Donations), `contract.scroll`, `contract.card` | shell. Settings rows use it, Records gets it as `ctx.contract`, the probe reads it | KEEP. Drop the `Donations` field |
| 526-549 | `TextService`, `textHeightFor`, `textWidthFor`, `TEXT_FIT_SLACK`, forward declaration of `applyTerminalLayout` | shared (header layout, Settings rows) | KEEP |
| 551-620 | Header, title, subtitle, `tokenLabel`, `closeButton`, `tabBar`, `content`, `statusLabel`, `showStatus` | shell | KEEP. The comments at 572-576 and 593-598 name DEV and COLORS and become stale |
| 622-631 | `pages`, `tabButtons`, `selectTab` | shell | KEEP |
| 633-660 | `TERMINAL_PAGE_MODULES = {Records, Skins}`; `tabNames` built from the 7-name list | shell | EDIT: modules `{Records = "ZyntraRecordsPage"}`, list `{"Records", "Settings"}` |
| 661 | `if devAllowed then table.insert(tabNames, "Dev") end` | Dev tab | DELETE (but see D1) |
| 662-684 | Tab buttons, page frames, `selectTab(currentTab)` | shell | KEEP |
| 686-707 | Tab-row width hook | shell | KEEP |
| **709-1371** | **The DEV page: the whole `if devAllowed and pages.Dev then` block** | Dev tab | **DELETE** |
| . 713-780 | DevIntro, DevControls scroll, its layout hook | | |
| . 782-983 | GIVE RESEARCH TOKENS form (`ZyntraGrantTokens`) | | |
| . 985-1095 | The `controls` table (11 rows, plus SKIP TO BLACKOUT WARNING for the Level 3 timeline owner) | | |
| . 1097-1105 | `sendDevCommand`, which fires `PlayerScripts.DevCheatCommand` | | |
| . 1107-1318 | Row builder, `contract.card("Dev", ...)`, action availability, caption refreshers | | |
| . 1320-1370 | Readbacks of `DevRespawnSerial`, `DevLevel2PumpSerial` and `DevLevel3TimelineSerial`, shown through `showStatus` | | |
| **1373-1592** | **UPGRADES page**: intro, scroll, PermanentUpgrades section and grid, `makeUpgradeCard`, STAMINA/BATTERY cards, the 3-tier hook, Spend firing `UpgradeStamina`/`UpgradeBattery` | Upgrades | **DELETE** |
| **1594-1740** | **SHOP page**: ShopCards scroll, grid, `productCards`, the `shopDetail` table, the SHOP_GRID hook | Shop | **DELETE** |
| 1742-1896 | `makeProductCard`: icon, tags, Buy button, Select pick, live price from GetProductInfo, `requestPurchase`. It writes `productButtons`, `displayedProductPrices` and `productPurchase` | Shop | DELETE |
| 1898-1918 | The 8 product cards, plus the Token Earner 2x/3x/5x cards | Shop | DELETE |
| 1919-1965 | Token Earner live prices (`verifiedEarnerPrice`, `renderEarner`) | Shop | DELETE |
| 1967-2239 | The ShopDetail pane, including DetailNote **"Prices are read live from Roblox." (2037)** | Shop | DELETE |
| 2241-2273 | Entity Shield card (ProtectionClient) | Upgrades | DELETE |
| 2275-2404 | FIELD SUPPLIES (SpeedPotion, RouteMarker, sent as `BuyItem`) | Upgrades | DELETE |
| **2406-2606** | **DONATE page**: DonationTotal label, DonationCards, hook, `makeDonationCard`, `donationEntries`, `contract.Donations` | Donate | **DELETE** |
| **2608-2898** | **COLORS page**: ColorPickers, `HUE_SEQUENCE`, `makeColorPicker`, `hazmatPicker`, `glowstickPicker` | Colors | **DELETE** |
| 2900-3142 | SETTINGS page (AccessibilityRows). It also wires the **Music rail button**: 3032-3042 and 3073-3082, through the `LobbyMusicEnabled` row | Settings, Music | KEEP whole. Music has no other click handler |
| 3144 | `player:SetAttribute("ZyntraReentryOpen", nil)` (a test marker) | re-entry | KEEP |
| 3146-3262 | `ZyntraReentryModal`: card, USE RE-ENTRY (spends a credit or calls PromptProductPurchase), `updateReentry` (publishes ZyntraReentryOpen/Credits/Price/ProductId), PARTY DOWN listeners | re-entry | KEEP. D3 covers the price |
| 3264-3306 | FREE RESPAWN // DEV (fires DevCheatCommand directly, not through the Dev tab) and SPECTATE | re-entry | KEEP |
| 3308-3324 | `bindCharacter` (death raises re-entry) | re-entry | KEEP |
| 3326-3385 | `refreshUI` | mixed | EDIT. Keep 3327-3331 (tokens), 3376 `updateReentry()` and 3377-3384 (page refresh). Delete 3332-3375: donation totals, Spend text and its `applyTerminalLayout()` call (Records re-lays itself out on render), upgrade readouts, the owned loop, `renderEarner`, the pickers |
| 3387-3396 | `publishProfile` | shell (Records, subscribers) | KEEP |
| 3398-3421 | `refreshRailDots` and the re-read at the UTC reset | rail dots | KEEP |
| 3423-3505 | Rewards intro card | rail | KEEP |
| 3507-3576 | Page-module mount (the `ctx` contract) | shell (Records) | KEEP. The comment at 3514-3516 (Shop, pickers) becomes stale |
| 3578-3598 | Profile push and first load | shared | KEEP |
| 3600-3651 | `setMainVisible` (writes DevPhoneOpen at 3619 and ZyntraStoreOpen at 3624; calls SuppressTouchMovement) | shell | KEEP. D6 covers 3619 |
| 3653-3731 | Gamepad focus and ButtonB (`terminalNavigation`) | shell | KEEP. The comment at 3684-3685 ("Kiosks open Shop; the dev phone opens Dev") becomes stale |
| 3733-3937 | `updateVisibility`: rail interactivity, touch dev chip placement, rail captions | rail, shell | KEEP. D7 covers 3934 |
| 3938-3956 | InRound, queue, briefing and modal-set listeners; boot | shared | KEEP. The comment at 3939-3940 ("reopen directly on the DEV page with J") becomes stale |
| 3958-3982 | `toggleMain` | dev phone and terminal | **REWRITE** (section 3) |
| 3984-4013 | `lobbyModalOpener`, `openDailyRewards`, `openLuckyWheel` | Rewards, Wheel | KEEP |
| 4015-4050 | `boundShopPrompts`, `openKioskShop` | routing | **REWRITE** (section 3) |
| 4052-4057 | `PlayerScripts.ZyntraOpenTerminal` (BindableEvent) | routing | KEEP |
| 4059-4105 | Studio probe `UIRegressionZyntraStoreProbe` | regression | EDIT. Drop `donations`. `open` must still open the TERMINAL (UIRegression expects it). `kiosk` now asks L4 |
| 4107-4121 | `ZyntraShopPrompt` binding plus `workspace.DescendantAdded` | kiosk prompt | DELETE recommended (D5) |
| 4123-4149 | `PlayerScripts.DevPhoneCommand` (BindableEvent, developers only) | dev phone | KEEP the event; REWRITE the handler |
| 4151-4161 | `openButton.Activated` | rail | REWRITE |
| 4162-4168 | Activated for shop, rewards, wheel and close | rail, shell | KEEP (the shop route changes inside `openKioskShop`) |
| 4169-4181 | Dev tab hands off to L4 (`ZyntraDevUIOpen(true, "terminal")`) | Dev tab | DELETE (but see D1) |
| 4183-4190 | J (developers) and Escape | dev, shell | KEEP |
| 4192-4210 | Close on death, Escaped and RoundActive | shell | KEEP |
| 4212-4412 | `applyTerminalLayout`. `fit.DevStacked` is read by the Settings rows (3100-3124) | shell | KEEP. Several comments name Shop, Colors and DEV and become stale |
| 4414-4425 | UIDevice.Changed: layout, visibility, `deviceCaptionRefreshers` loop | shared | EDIT. Drop the refresher loop (4417-4423); only the Dev page registered into it |
| 4427-4441 | `PlayerScripts.ZyntraShopBuy`, which runs `productPurchase[key]` | lobby wall buy | **DECIDE D2** |

---

## 2. Helpers and top-level locals

The main chunk has 155 top-level locals.

**Only the deleted pages use these (32 locals, all DELETE):**
- Upgrades (9): `upgradeIntro`, `upgradeScroll`, `upgradeSection`, `upgradeGrid`, `UPGRADE_CARD_HEIGHT`, `upgradeCards`, `makeUpgradeCard`, `staminaCard`, `batteryCard`
- Shop (6): `shopScroll`, `shopGrid`, `productCards`, `shopDetail`, `makeProductCard`, `verifiedEarnerPrice`
- Donate (5): `supportTotalLabel`, `supportScroll`, `supportGrid`, `makeDonationCard`, `donationEntries`
- Colors (7): `colorsScroll`, `colorsLayout`, `colorsPadding`, `HUE_SEQUENCE`, `makeColorPicker`, `hazmatPicker`, `glowstickPicker`
- Dead once those go (5): `deviceCaptionRefreshers` (Dev only), `ProtectionClient` (Shop TokenItem path and Shield card), `PCT` (Spend text), `level3TimelineOwner` (Dev only), `productButtons` (Shop, Donate, refreshUI owned loop)

The Dev page has no top-level locals; everything in it sits inside its `if` block.

**Shared with the KEEP set (they stay, some shrink):**
- `displayedProductPrices`: after the cut only re-entry reads it (3248, 3258). Nothing writes it any more (D3).
- `productPurchase`: after the cut only the ZyntraShopBuy bridge reads it (D2).
- `contract`: Settings, Records (`ctx.contract`) and the probe use it. Drop `Donations`.
- `pageMounts.Subscribers`: the shop-pane and supplies subscribers go; Records stays.
- `layoutHooks`: the tab row, Settings rows and Records keep using it.
- `textHeightFor`, `textWidthFor`, `TEXT_FIT_SLACK`: the header and Settings rows use them.
- `MarketplaceService`: the re-entry prompt (3211) and the D3 fetch.
- `CollectionService`: `contract.card` (Settings).
- `UserInputService`: navigation, J, TouchEnabled.
- `RunService`: the probe.
- `Config`: rail dots, re-entry, AccessibilitySettings, page ctx.
- `actionRemote`: Settings, re-entry, intro, page ctx.
- `remotes`, `getProfileRemote`, `profileChangedRemote`, `devAllowed`, `DevAccess`.
- `currentTab`, `pages`, `tabButtons`, `selectTab`, `tabNames`, `showStatus`, `main`, `gui`, `COLORS`, `corner`, `outline`, `label`, `button`.

**Already dead in the file today:** `shopButtonRing` (269) and, see D5, `boundShopPrompts` and `bindShopPrompt`.

---

## 3. Every route that opens a legacy page or the Dev tab

ZyntraStore never reads `ShopUIVersion` itself; the only mention is a comment at
4034-4037. The flag lives in the L4 scripts (see the end of this section).

| # | Where | Today | After go-live (L4 unconditional, no legacy fallback) |
|---|---|---|---|
| 1 | `openButton.Activated` 4151-4161 | Lobby: `ZyntraShopUIOpen("Upgrades")`; on false, `toggleMain()` opens the terminal on `currentTab`. Round (touch dev chip): `toggleMain` | Lobby: `ZyntraShopUIOpen("Upgrades")` only. Round: the dev toggle (`ZyntraDevUIOpen`) |
| 2 | `shopButton.Activated` 4164 | `openKioskShop()`: L4 Shop, else the legacy Shop tab | `openKioskShop()`: L4 Shop only |
| 3 | `openKioskShop` 4024-4050 | `"Rewards"` opens the Daily Rewards modal. Any other string asks L4 first, then falls back to legacy at 4045-4049 (`selectTab(tab or "Shop")` and `setMainVisible(true)`) | `"Rewards"` opens `openDailyRewards()` (as now). `"Records"`/`"Settings"` open the terminal, with the existing guards at 4045-4046. Anything else (or nil) goes to `ZyntraShopUIOpen(tab or "Shop")`. On false, stop: L4 warns about its own build failures. Warn here only if the bridge object is missing |
| 4 | `ZyntraOpenTerminal` 4052-4057 | Fires `openKioskShop(tab)`. Fired by L4's `ui.handoff` (RECORDS, SETTINGS, and pages the import lacks; Shop L4 165-169) and by the pill's AddTokens fallback `"Shop"` (Shop L4 1028-1029) | The event itself is unchanged. L4 should fire it only for Records and Settings; the other cases would just bounce back to L4 and stop (L4 map) |
| 5 | `ZyntraShopPrompt` 4107-4121 | `openKioskShop(nil or "Rewards")` | DELETE (D5), or leave it routing through `openKioskShop` |
| 6 | `toggleMain` 3958-3982. Callers: probe `open` 4066, DevPhoneCommand 4143, J fallback 4186, openButton 4160 | Round: `ZyntraDevUIOpen`, else `selectTab("Dev")` (3979) and open. Lobby: opens the terminal on `currentTab` | Becomes the dev toggle: `devAllowed` only, `ZyntraDevUIOpen(requested)`, no `selectTab("Dev")`, no terminal. The probe `open` must call the terminal opener from row 3 instead (UIRegression measures the terminal through it) |
| 7 | DevPhoneCommand handler 4133-4144 | Lobby: `ZyntraDevUIOpen`, else `toggleMain`. Round: `toggleMain` | Always the dev toggle (row 6), lobby and round |
| 8 | J key 4185-4186 | `devPhoneCommand:Fire()` or `toggleMain()` | KEEP; both now reach the dev menu |
| 9 | Dev tab hook 4173-4181 | `ZyntraDevUIOpen(true, "terminal")` | DELETE with the tab (D1) |
| 10 | Tab buttons 680-682 | `selectTab` for all 7 or 8 tabs | Records and Settings only |
| 11 | Probe 4064-4100 | `open` calls toggleMain; `kiosk` calls openKioskShop; `tab:` calls selectTab | `open` opens the terminal; `kiosk` asks L4 (returns `main.Visible`, which is now false); drop `donations` |
| 12 | 3934 `if inRound and not devAllowed then setMainVisible(false)` | A developer could keep the terminal (the dev phone) open in a round | `if inRound then setMainVisible(false) end` (D7) |
| 13 | Page mount 3524 (over `TERMINAL_PAGE_MODULES`) | Mounts ZyntraSkinsPage as the legacy SKINS tab | Gone with the table edit (D4) |

**The flag and the "legacy opens instead" copy, outside ZyntraStore (for the L4 map):**
- Zyntra Shop L4: `wantsL4` 73-76, used at 972, 1038-1039, 1263 and 1317-1321. Its warnings at 89, 101 and 963 promise a legacy fallback, and so do the header comments at 10-19 and 25-28.
- Zyntra Dev L4: `wantsL4` 135-138, used at 860 and 915. Its warnings at 151, 162 and 655, and the header at 28-41, promise a legacy fallback. DevAccess stays its gate (line 59).
- `roblox-draft/install/04_flag.luau` and the workspace attribute in Studio.

**"Prices are read live from Roblox." appears in three places:**
- ZyntraStore 2037 (deleted with the Shop pane).
- **Zyntra Shop L4 line 57, `TAB_HINTS.Shop`.** This is the copy players see: `ui.showHint` (645-650) writes it into the footer on every Shop tab select.
- The default text of the live template's `ZyntraShop_L4/ShopWindow/Canvas/Footer/Status` (per the 2026-10-07 dump). `showHint` overwrites it on open; blank it at the next import.

---

## 4. What other scripts depend on

**Attributes ZyntraStore writes**

| Attribute | Line | Read by | Verdict |
|---|---|---|---|
| `ZyntraStoreOpen` | 3624 | UIDevice screen-owning set, RoundUI, NoiseReporter, FlashlightController, ProtectionHUD, UIRegression. Zyntra Shop L4 writes it too and re-asserts it at 1289-1298 | KEEP. D6 covers the nil-write fight |
| `DevPhoneOpen` | 3619 | Same set. Dev L4 owns it now and re-asserts it at 901-908 | Drop ZyntraStore's write (D6) |
| `ZyntraReentryOpen` | 3144, 3243 | UIDevice set, RoundUI, tests | KEEP |
| `ZyntraReentryCredits` / `ZyntraReentryPrice` / `ZyntraReentryProductId` | 3256-3259 | RoundUI's PARTY DOWN card. Shop Display Client reads Credits (402, 652) | KEEP (D3 for the price) |
| Frame `Terminal`: `TerminalActionTag` (503), `TerminalHeaderStacked` (4362), `TerminalCompact`, `TerminalTapFloor`, `TerminalSubtitleShown`, `TerminalModalWidth`/`Height`, `TerminalContentHeight` (4403-4411) | | UIRegression | KEEP |
| Card attributes `ZyntraPage`/`ZyntraCardKey` and the CollectionService tag `ZyntraTerminalAction` (`contract.card`) | | UIRegression | KEEP. Only Settings, and Records if it uses the contract, remain |
| `DonationTierKey`/`DonationProductId`/`DonationPurchaseKind` | 2543-2545 | UIRegression | Go with Donate |

**Attributes ZyntraStore reads and keeps reading:** InRound, QueueModalOpen,
DispatchBriefingOpen, PartyDownCardOpen, PartyDownWindowOpen, ZyntraReentryUsed,
Level6PlaygroundPreview (still a live name; GameManager uses it), Escaped,
LobbyMusicEnabled plus the accessibility keys, DevRespawnBusy, and `workspace.RoundActive`.

Read only by deleted code: SelectedLevel, `DevCheat*`, `DevLevel2Pump*`,
`DevLevel3Timeline*`, Level5VoidRound, Level2_ExitTransition and `ZyntraOwns*`.

**Bindables ZyntraStore creates**

| Instance | Lines | Used by | Verdict |
|---|---|---|---|
| `PlayerScripts.ZyntraOpenTerminal` (BindableEvent) | 4052-4057 | Zyntra Shop L4 165-169 and 1028-1029 | KEEP |
| `PlayerScripts.OpenDailyRewards` and `OpenLuckyWheel` (create-if-absent) | 3989-4013 | Daily Rewards Client 579-582; Lucky Wheel Client 59-62 | KEEP |
| `PlayerScripts.DevPhoneCommand` (BindableEvent, developers only) | 4123-4149 | Only ZyntraStore's own J fires it. Dev L4 mentions it in a comment | KEEP |
| `PlayerScripts.ZyntraShopBuy` (BindableEvent) | 4433-4441 | Shop Display Client 637-645 (the lobby wall's BUY) | DECIDE D2 |
| `gui.UIRegressionZyntraStoreProbe` (BindableFunction, Studio only) | 4061-4105 | UIRegression (many lanes); install/05_qa_probe_client | EDIT (section 3, row 11) |

**Bindables and remotes ZyntraStore calls**
- `PlayerScripts.ZyntraShopUIOpen` (BindableFunction, created by Shop L4 80-95): called at 4039-4043 and 4155-4159.
- `PlayerScripts.ZyntraDevUIOpen` (BindableFunction, created by Dev L4 142-156): called at 3965-3969, 4137-4141 and 4175-4179.
- `PlayerScripts.DevCheatCommand` (from DevCheats): fired at 1099-1101 (Dev page, deleted) and 3287-3290 (FREE RESPAWN in re-entry, KEEP).
- Remotes `ZyntraGetProfile`, `ZyntraAction`, `ZyntraProfileChanged`: KEEP. `ZyntraGrantTokens` is used only by the Dev page; Dev L4 calls it itself.

**GUI names other scripts look up**
- `PlayerGui.ZyntraStore`: Shop L4 989 and 1078 (`railRight`, `skinRail` wait for it), PuzzleUI 1304, 1606, 1682 and 1697 (`ZyntraOpenButton` obstacle rectangle), UIRegression.
- The rail: `ZyntraShopButton`, `ZyntraOpenButton`, `ZyntraRewardsButton`, `ZyntraWheelButton`, `ZyntraMusicButton`, plus `SectionButtonContent > SectionCaption`, `SquareSectionBorder` and `NotificationDot`. The Shop L4 skin uses them (63, 1077-1101); its comment says the content is hidden, never destroyed, because 3035 dot-indexes it. Daily Rewards Client, UIRegression and the tests use them too. KEEP every name.
- Terminal: `Terminal`, `TerminalHeader`, `TerminalTabs`, `TerminalContent`, `CloseTerminal`, `TokenReadout`, `TerminalStatus`, `<Name>Tab`. Used by UIRegression.
- `ZyntraReentryModal > EmergencyReentry > ReentryFreeRespawn / ReentryDecline`, and `RewardsIntroCard`. Used by UIRegression and the tests.
- Page modules: `ReplicatedStorage.ZyntraRecordsPage` (KEEP); `ReplicatedStorage.ZyntraSkinsPage` (D4).

---

## 5. Gaps and decisions for the main session

- **D1. Touch developers lose their lobby route to the dev menu.** Dev L4's header
  (34-35) names the legacy DEV tab as "the lobby route for touch developers
  (UPGRADES -> DEV)". After the cut a touch developer in the lobby has no way in:
  J needs a keyboard, and the ZYNTRA // DEV chip appears only in a round
  (`touchDevInLevel`, 3736). Options:
  - (a) Keep a DEV tab *button* with no page, whose Activated is today's 4173-4181
    hand-off. This adds no locals and leaves no legacy UI behind.
  - (b) Show the chip in the lobby for touch developers.
  - (c) Add a DEV entry in the L4 header.

  Default suggestion: (a).
- **D2. ZyntraShopBuy loses its backing.** Today `productPurchase` is filled only
  by the Shop cards and FIELD SUPPLIES. The wall sells Supporter, AdvancedEquipment,
  Tokens4, Tokens20, EmergencyReentry, ExpeditionPack, CosmeticEquipment, SpeedPotion,
  RouteMarker, and anything else in `Config.Passes`/`Products`/`Items`
  (LobbyShopDisplay 139-180). `ShopData.purchase` covers all of those except
  **Tokens4 and EmergencyReentry**: ShopData 108 adds only ExpeditionPack and Tokens20
  to its Robux catalogue.

  Suggestion: add Tokens4 and EmergencyReentry to that ShopData loop. They join
  `robux`, not the L4 card list `SHOP`. Then either move the bridge into Zyntra Shop
  L4, or have ZyntraStore's bridge call `ShopData.purchase(key)`. In both cases
  `productPurchase` goes. Two side effects to accept: ShopData refuses until the
  profile is loaded, and it refuses a pass whose ownership attribute has not been
  read yet (legacy prompted regardless). The comment in Shop Display Client
  (10-13, 641) names ZyntraStore as the owner, so update it.
- **D3. The re-entry price stops being live.** `displayedProductPrices.EmergencyReentry`
  was written only by the Shop card (1846, 1855). After the cut, 3248 and 3258 fall
  back to `Config.Products.EmergencyReentry.Price` (29). RoundUI's PARTY DOWN card
  shows whatever `ZyntraReentryPrice` publishes.

  Suggestion: one `task.spawn` GetProductInfo for that id, placed inside the re-entry
  `do` block (3264), which writes `displayedProductPrices.EmergencyReentry` and calls
  `updateReentry()`. That adds no top-level local. Keep the name
  `displayedProductPrices`: test_reentry_dismissal.py stubs it (107, 165).
- **D4. ZyntraSkinsPage becomes orphaned.** Only ZyntraStore mounts it (3524);
  UIRegression 5538 derives the expected tab list from its presence. It is the legacy
  SKINS page builder, so it falls under "delete the old UI". Deleting it is a Studio
  step on a separate ModuleScript; decide it explicitly.
- **D5. The ZyntraShopPrompt binding is dead.** No builder creates the prompt any
  more (TunnelLobbyBuilder 2417-2425 says exactly that), and no script sets
  `ShopRewardsPrompt` at all. The binding still scans `workspace:GetDescendants()` at
  boot and listens to **every** `workspace.DescendantAdded`, which fires for every
  generated level part. Suggestion: delete 4015-4018 and 4107-4121. A saved instance
  in the place cannot be ruled out offline; one Studio query can rule it out.
- **D6. Two writers per modal flag.**
  - `setMainVisible(false)` runs from many paths (InRound, death, Escaped,
    RoundActive, `updateVisibility`). Each run writes ZyntraStoreOpen=nil and
    DevPhoneOpen=nil, and the L4 windows re-assert both with `task.defer` (Shop L4
    1289-1298, Dev L4 901-908).
  - Suggestion: drop line 3619. The terminal is no longer the dev phone, and keeping
    the write would publish DevPhoneOpen=true whenever a developer opens
    Records/Settings.
  - Optionally, write ZyntraStoreOpen only on a real transition (`wasVisible ~=
    main.Visible`, or when the terminal was visible); the L4 re-assert hacks can then
    go (L4 map).
- **D7. Close the terminal in a round for everyone.** Change 3934 from
  `inRound and not devAllowed` to `inRound`. In a round the legacy terminal was only
  ever the dev phone.
- **D8. `currentTab` defaults to `"Upgrades"`** (30, used at 677 and 684). With that
  page gone, `selectTab` returns early and no page is visible until a tab is chosen.
  Default to `"Settings"` (always built) or call `selectTab(tabNames[1])`.

---

## 6. Register headroom

Measured with luau-compile 0.737 `-O0`, using test_zyntra_dev_l4.py's method: binary
search on extra `local` lines appended to the main chunk.

| Version | Compiles | Top-level locals | Headroom (of 200) | Lines |
|---|---|---:|---:|---:|
| Today (f288523b1c68) | yes | 155 | **45** | 4441 |
| Simulated cut, required deletions (709-1371, 1373-2898, locals 11/19/20/23/31) | yes | ~123 | **77** | 2248 |
| Plus optional dead code (32-35 productPurchase, 269, 4015-4018, 4107-4121) | yes | ~119 | **81** | 2224 |

The simulation does not apply the REWRITEs. Leftover references compile as globals,
so it is an upper bound for the deletion and a fair estimate for the result.

The deletion only frees registers. The rewrite needs at most 2 or 3 new top-level
names (a terminal opener, a bridge-call helper, a warn-once table), so the risk is
negligible. The peak inside the remaining `do` blocks (Settings 2920-3142, re-entry
3264-3306, focus 3654-3731) drops by the same ~32.

---

## 7. Tests: baseline at f288523b1c68, and what the cut does to each

Run with `LUAU_BIN=.../luau/0.737/luau.exe python tools/tests/<t>.py` on 2026-10-07,
before any change.

| Test | Baseline | Reads from ZyntraStore | After the cut |
|---|---|---|---|
| tools/tests/test_zyntra_store_compact.py | **FAILS already**: "the shop cell height is unchanged" (stale since SHOP_GRID_20261003) | Tier tables (2 needed), upgrade and shop stacks, tab list, FIELD SUPPLIES, Shop hook, rail, layout ladder, routing, modal set | DELETE sections 1-4, 5b, 6 (tab set incl. Upgrades/Shop/Dev), 7 (supplies) and 8 (Shop hook): they only exercised deleted UI. KEEP sections 5, 5a, 5c, 9, 10 and 12. REWRITE section 11 routing: the "SHOPS opens Shop tab", "no tab / unknown tab means Shop" and ZyntraShopPrompt cases become "asks ZyntraShopUIOpen, never the terminal". Its Rewards and refusal cases stay as they are |
| test_controller_input.py | **FAILS already**, at a NoiseReporter fake (`speedBoost` nil). Not ZyntraStore | Slices `local updateVisibility\n` to `function updateVisibility()` (KEEP code) | Marker survives. Its stub `tabButtons = {Shop, Dev}` should be renamed to Records/Settings, with the same assertions |
| test_reentry_dismissal.py, test_dev_free_respawn_offer.py | pass | Slice `local reentryDead = false` to `local COLORS =`, and `player:SetAttribute("ZyntraReentryOpen", nil)` to `local function refreshUI()` | Keep both markers and the name `displayedProductPrices` |
| test_daily_rewards_page.py, test_zyntra_records_page.py | pass | Slice `local COLORS = {` to `local gui = Instance.new("ScreenGui")`, and `local function corner(parent, radius)` to `-- Imagegen section art` | Keep the markers |
| test_rail_dots_intro.py | pass | RAIL_DOTS / REWARDS_INTRO markers | Keep them |
| test_lobby_shop_display.py | **FAILS already**: 8 vs 10 product textures | Line 83 asserts the tier expression exists in ZyntraStore | Line 83 dies with the pages: the drift partner it guarded is deleted. The ZyntraShopBuy fake (877-884) follows D2 |
| test_friend_boost.py, test_round_exit_hold.py | pass | Only the attribute names | Unaffected |
| test_daily_rewards_client.py, test_lucky_wheel_client.py | **FAIL already**: Daily Rewards boot fake; missing ZyntraSkins fixture. Not ZyntraStore | Only the attribute names | Unaffected |
| draft dev-menu/tests/test_zyntra_dev_l4.py | (not run here) | `legacy_rows` slices `\tlocal controls = {` to `\tlocal function sendDevCommand` from the **mirror**. `check_store_patch` requires the mirror to equal `patches/ZyntraStore.shop+dev.patched.lua` | **Both break.** Freeze today's controls as a literal fixture in the test, so "L4 covers every legacy command" keeps its assertion. Retire `check_store_patch` with the install hunks: the code it verifies is deleted |
| draft tests/test_zyntrastore_patch.py | (not run here) | A frozen `_local/.../ZyntraStore.studio.lua`, not the mirror | Unaffected by mirror edits. Retire it together with install/03 if that tool retires |
| draft tests/test_zyntra_shop_l4.py | (not run here) | Nothing from ZyntraStore. Its harness has flag cases (ShopUIVersion at 685, 1180, 1184 and 1625) | Belongs to the L4 map |

**UIRegression needs its own pass.** These lanes read the deleted pages or the old
probe semantics:
- 1373-1415: the store-modal rows, including `store-modal-dev` (`tab:Dev`).
- 2365-2441: the saved `TerminalTab` restore.
- 4656-5140: the modal-exclusion lane. Probe `open` must still open the terminal;
  the Dev caption block is at 5040-5135.
- 5427-6426: `ZyntraTerminalFitMatrix`. expectedTabs at 5537-5541 includes Skins
  and Dev; then donations from 5585, cards per page, `Fit.DonationTierKeys`.
- `Fit.ZyntraDisabledCaptions` (LEVEL n ONLY, SAVING..., COMING SOON).
