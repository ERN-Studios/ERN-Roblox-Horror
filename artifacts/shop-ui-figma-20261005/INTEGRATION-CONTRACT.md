# Zyntra shop UI: Roblox integration contract

Date: 2026-10-05. This is a read-only analysis. No Studio call was made and no `.lua` file was edited.

Repo HEAD: `adf02cc`.

**Audience.** Read this before anyone turns the Framewisp import of the four Figma layouts (L1 Field Catalogue, L2 Storefront Shelves, L3 Terminal Split, L4 Bento Home) into a working Roblox UI. It covers:
- **Sections 1-4:** what exists today.
- **Section 5:** the proposed integration.
- **Section 6:** the layer-name contract that every Figma screen has to follow.

**Sources read:**
- `StarterPlayerScripts`: `ZyntraStore`, `Shop Display Client`, `Daily Rewards Client`, `Lucky Wheel Client`, `Friend Boost Client`, `HazmatSkinDriver`, and `RoundUI` (the PARTY DOWN block).
- `ReplicatedStorage`: `ZyntraConfig` (repo copy and the fresh Studio copy `_local/shop-ui-figma/studio/ZyntraConfig.studio.lua`), `ZyntraSkins`, `ZyntraSkinsPage`, `ZyntraDailyRewardsPage`, `ZyntraDailyResearch`, `ProtectionClient`, `UIDevice` (the screen-owning modal list), and `UIRegression` (the `Fit.Zyntra*` rows).
- `ServerScriptService`: `ZyntraMonetization`, `LobbyShopDisplay`, `HazmatSkinVisuals`.
- `tools/tests/*`.

---

## 0. Studio is newer than the repo: where it matters

`_local/shop-ui-figma/studio/server_sources.json` lists the byte length of each live Studio source. I compared those lengths with the repo after normalising CRLF:

| Script | Studio vs repo (bytes) | Matters for this contract? |
|---|---:|---|
| `ReplicatedStorage.ZyntraConfig` | +3276 | **No.** I diffed the full Studio copy. The only changes are `Badges` (FirstClearLevel4..6, AllSix, Welcome, ...) and a new `Achievements` list. Every shop key, product id, price, IconId, TokenEarner pass, Donation and Item is identical, so all keys in section 6 hold. |
| `ServerScriptService.ZyntraMonetization` | +4333 | **Yes, verify.** The content is unknown; it is probably the ACHIEVEMENTS_20261004 hook (`ServerStorage.ZyntraAchievement`). Before binding, re-check the `ZyntraAction` dispatcher (section 1.2), `publicProfile` (1.3) and the `ZyntraOwns*` writers (1.4). |
| `StarterPlayerScripts.ZyntraStore` | +2015 | **Yes, verify.** The routing edit in section 5 lands in `openKioskShop` / `toggleMain`. The live rail still has exactly 5 buttons (`client_images.json` shows ZyntraShopButton, ZyntraOpenButton, ZyntraRewardsButton, ZyntraWheelButton and ZyntraMusicButton). |
| `ServerScriptService.HazmatSkinVisuals`, `StarterPlayerScripts.HazmatSkinDriver` | +61 each | Low. Re-check the "visual only in rounds" gate (section 2.6). |
| LobbyShopDisplay, Shop Display Client, Daily Rewards Client, Lucky Wheel Client, Friend Boost Client, ZyntraSkins, ZyntraSkinsPage, ZyntraDailyRewardsPage, ZyntraDailyResearch, UIStyle, PurchaseAlerts, ZyntraAnalytics | ±0 | Same size, which does not prove the content is the same. |

`studio-sync-manifest.json` still marks all five drifted scripts `synced`, so another session edited Studio after the last pull. The first integration step is therefore `python tools/pull_source_from_studio.py --audit`, followed by a pull of those five. Re-read sections 1.2-1.4 against the pulled copies.

---

## 1. Shared plumbing (every surface uses some of this)

### 1.1 Remotes (`ReplicatedStorage.Remotes`, created by ZyntraMonetization `ensureRemote`)

| Name | Class | Use |
|---|---|---|
| `ZyntraGetProfile` | RemoteFunction | `InvokeServer()` returns the public profile (1.3). The server waits up to 10 s for the session and can return **nil**. |
| `ZyntraProfileChanged` | RemoteEvent | `OnClientEvent(profile, message, tone)`. `tone` is `"success"`, `"error"` or `"info"`. Every write pushes this event, and it is the ONLY source of purchase/refusal text. |
| `ZyntraAction` | RemoteEvent | `FireServer(action, payload)`. All token spending and equipping goes through it (1.2). |
| `ZyntraGrantTokens` | RemoteFunction | DEV tab only (DevAccess). Out of scope. |
| `ZyntraClaimLobbyBriefing` | RemoteFunction | Briefing. Out of scope. |

There are no other shop remotes, and the proposal adds none.

### 1.2 `ZyntraAction` actions the shop UI may send

| Action | Payload | Server result |
|---|---|---|
| `UpgradeStamina` / `UpgradeBattery` | none | Success: `Stamina increased by +5%.` or `Battery increased by +5%.`. Refusal: `You need N Zyntra Research Token(s).` The cost is `Config.UpgradeCost(level)` = level + 1. |
| `BuyItem` | `{Key = "SpeedPotion" \| "RouteMarker"}` | Success: `Speed Potion stored (n owned).`. Refusal: `You need N Research Tokens.` |
| `BuyProtection` | `{SessionNonce, Revision, RequestNonce}` | **Only through `ProtectionClient.Request("BuyProtection")` / `.Retry()`**, never raw. The result arrives in `profile.ProtectionLastResponse`. |
| `BuySkin` | skinId **string** (Tokens skins only) | Results: `<Name> unlocked.`, `Already owned.` (info), `Requires N lifetime clears.`, `Requires N Research Tokens.` A non-Tokens skin is silently ignored. |
| `EquipSkin` | skinId string | Result: `<Name> equipped.`. Silently ignored when the skin is not owned, already equipped, or Developer for a non-developer. |
| `SetHazmatColor` / `SetGlowstickColor` | `Color3` | Results: `Hazmat color saved.` / `Glowstick color saved.`, or `Advanced Equipment is required.` / `Glowstick Customizer is required.` |
| `ClaimPlaytimeReward` | `{Minutes = 5 \| 15 \| 35}` | Results: `<reward> collected -- N minutes of play today.` / `You already claimed...` / `Play N minutes...` |
| `SpinDailyWheel` / `ClaimWheelPrize` | none | Results: `Supply Wheel: <prize> -- collect your prize.` / `<prize> collected.` / `Collect your prize first: ...` / `Today's spin is done: ...` |
| `UseReentry` | none | Reserve, then invoke `ServerStorage.ZyntraReentry`, then refund on failure. Refusal: `You do not have an Emergency Re-entry credit.` |
| `MarkRewardsIntroSeen` | none | Idempotent, no message. |
| `ShopView` | `{Key, Demo}` | Analytics only, lobby only. It grants nothing. |
| `DeviceClass` | `{Class = "PC" \| "Phone" \| "Tablet"}` | Analytics, first answer per session. |

**Silent drops (the UI must time out on its own).** The server keeps a per-action window: 1 s for write-bearing actions (`UpgradeStamina/Battery`, colours, `SetAccessibility`, claims, spin/claim wheel, `BuyItem`, `BuySkin`, `EquipSkin`, `UseSpeedPotion`) and 0.12 s for the rest. A second press inside the window is dropped **with no push at all**. So every "pending" state needs a client timeout; the current `BuyItem` card uses 6 s. The same applies before the session exists: the action returns early with no reply.

### 1.3 Public profile (payload of 1.1, `publicProfile` + `enrichedPublicProfile`)

Fields the shop reads:
- **Balance and upgrades:** `Tokens`, `StaminaLevel`, `BatteryLevel`, `StaminaPercent` (includes the +50 Advanced Equipment bonus), `BatteryPercent`.
- **Stored consumables:** `Items = {SpeedPotion, RouteMarker}`, `ReentryCredits`, `ProtectionCharges`, `ProtectionRevision`, `ProtectionAvailable`, `ProtectionPending`, `ProtectionLastResponse`, `ProtectionSessionNonce`.
- **Skins:** `Skins = {Owned = {[SkinId]=true}, Equipped = SkinId}`.
- **Progress:** `CompletedLevels` (the lifetime clears gate on Blacksite Director).
- **Daily** = `{Today, PlaytimeSeconds, Claimed = {["5"]=true, ...}, Research = {{Key, Title, Detail, Reward, Complete}x3}, WheelDay, WheelLast = {Day, Key, SkinId, FallbackTokens, Serial, Claimed, PaidTokens}, SecondsToReset, Accruing}`.
- **Pass ownership:** `OwnsSupporter`, `OwnsAdvancedEquipment`, `OwnsCosmeticEquipment`, `OwnsEntityDetector`. These are copied from the attributes. There are no profile fields for Token Earner, the skin passes or Donation20K; those come from attributes only.
- **Support totals:** `RecordedSupportRobux`, `DonationRobux`, `UtilityRobux`, `PassRobux`.
- **Colours:** `HazmatColor` and `GlowstickColor` (Color3).
- **Flags:** `RewardsIntroSeen`, plus the accessibility keys.

**The token balance is NOT an attribute.** ZyntraMonetization deliberately keeps raw numbers off attributes, so the UI reads `profile.Tokens`. The proposal does not add one (see 5.2).

### 1.4 Player attributes

| Attribute | Writer | Replicated | Meaning |
|---|---|---|---|
| `ZyntraOwnsSupporter`, `...AdvancedEquipment`, `...CosmeticEquipment`, `...EntityDetector` | server `refreshPasses` | yes | Pass ownership. A purchase is latched at `PromptGamePassPurchaseFinished`, so it flips within seconds. |
| `ZyntraOwnsTokenEarner2x` / `3x` / `5x` / `Up2to3` / `Up3to5` / `Up2to5` | server | yes | Earner passes. The tier is `Config.TokenEarner.Tier(owns)`. |
| `ZyntraTokenEarnerMultiplier` | server | yes | 1/2/3/5. Only written when the read is complete. The UI should derive the tier from the six booleans the way the terminal does. |
| `ZyntraOwnsStaticWraith`, `ZyntraOwnsFalseSun` | server | yes | Skin passes. The server also grants `Skins.Owned[id]`. |
| `ZyntraOwnsDonation20K` | server | yes | The one-time 20K gamepass. |
| `ZyntraSpeedPotions`, `ZyntraRouteMarkers` | server `applyAttributes` | yes | Stored counts. |
| `ZyntraSkinId` | server | yes | Equipped suit, as seen by others (fail-closed for Developer). |
| `ZyntraHazmatColor`, `ZyntraGlowstickColor` | server | yes | Saved colours. |
| `ZyntraDonationRobux`, `ZyntraUtilityRobux`, `ZyntraPassRobux`, `ZyntraRecordedSupportRobux` | server | yes | Support totals. |
| `ZyntraProfileLoaded` | server | yes | false while loading, true once the profile is live. **This is the gate.** |
| `ZyntraDailyAccruing` | server | yes | Playtime is counting. |
| `FriendBoostPercent`, `FriendBoostFriends` | server `FriendBoost` | yes | Friend Boost chip. |
| `ZyntraShopFocus` | server `LobbyShopDisplay` | yes | The wall plate the player stands on. |
| `ZyntraReentryUsed` | server (round) | yes | Re-entry used this round. |
| `ZyntraReentryCredits`, `ZyntraReentryPrice`, `ZyntraReentryProductId` | **client** ZyntraStore `updateReentry` | no (client-local) | Feeds the PARTY DOWN card. **Display only, never trusted.** |
| `ZyntraStoreOpen` | **client** ZyntraStore `setMainVisible` | no | The shop window is open. It is one of the screen-owning modal set. |
| `ZyntraReentryOpen`, `PartyDownCardOpen`, `PartyDownWindowOpen`, `DailyRewardsOpen`, `LuckyWheelOpen`, `ZyntraShopDetailOpen`, `QueueModalOpen`, `DispatchBriefingOpen` | clients | no | Modal flags. |
| `InRound`, `Escaped` (player), `RoundActive`, `RoundLoadingState` (workspace) | server | yes | Lobby vs round. |

### 1.5 MarketplaceService

**Who prompts what:**
- **Passes:** `PromptGamePassPurchase(player, id)`.
- **Developer products and donations:** `PromptProductPurchase(player, id)`.
- **Today's prompters:** only ZyntraStore (`productPurchase[key]`, the donation cards and the re-entry modal), ZyntraSkinsPage (Robux skins) and RoundUI (PARTY DOWN). The lobby wall prompts nothing; its BUY fires `PlayerScripts.ZyntraShopBuy(key)` into ZyntraStore.

**Live prices.**
- Every card reads `GetProductInfo(id, InfoType)` per player, because Managed Pricing can differ from `ZyntraConfig.Price`, which is only the fallback.
- Token Earner and skin passes also require `IsForSale == true`, `TargetId == id` and a positive integer price. If that fails, they show `UNAVAILABLE`.
- **The Token Earner passes are off sale until QA**, so today they read `CHECKING PRICE`, then `UNAVAILABLE`.

**Grants.**
- Developer products are granted in `ProcessReceipt`. It is idempotent on `PurchaseId`; the server pushes the success message and `PurchaseAlerts` fires on a first grant only.
- Passes are latched in `PromptGamePassPurchaseFinished`, followed by `refreshPasses`. The ownership attributes flip there.
- One-time pass grants: Supporter +10 tokens (`+10 Zyntra Research Tokens`) and Advanced Equipment +1 stamina/battery level.
- **A pass purchase has no generic success message.** The UI's success signal is the `ZyntraOwns<Key>` attribute turning true.

**Receipt messages:**
- `+N Zyntra Research Tokens`
- `+1 Emergency Re-entry credit`. If the buyer is dead in a live round, the credit is auto-used: `reentryEligible`, then `useReentry`.
- `Expedition Pack stored: 1 re-entry, 1 shield, 3 markers.`
- `Thank you — N R$ added to your donation total.`

### 1.6 Client bindables in `PlayerScripts`

| Name | Owner | Use |
|---|---|---|
| `ZyntraShopBuy` (BindableEvent) | ZyntraStore, created at the end of the script | `Fire(key)` runs `productPurchase[key]`. Valid keys: the 11 Shop keys plus `SpeedPotion` and `RouteMarker`. Unknown keys are ignored. |
| `ZyntraOpenTerminal` (BindableEvent) | ZyntraStore | `Fire(tab)` calls `openKioskShop(tab)`. `"Rewards"` opens Daily Rewards instead. |
| `OpenDailyRewards`, `OpenLuckyWheel` (BindableEvent) | created by whichever script runs first | Open the two lobby modals. |
| `DevPhoneCommand`, `DevCheatCommand` | ZyntraStore / DevCheats | Dev only. |
| Studio probes | ZyntraStore, Daily Rewards Client, Lucky Wheel Client, Shop Display Client | `UIRegressionZyntraStoreProbe` (under the `ZyntraStore` gui), `UIRegressionDailyRewardsProbe`, `UIRegressionLuckyWheelProbe`, `UIRegressionShopDemoProbe`. |

### 1.7 Screen-owning modals and draw order

`UIDevice.SCREEN_OWNING_MODALS` = `ZyntraStoreOpen`, `DevPhoneOpen`, `ZyntraReentryOpen`, `QueueModalOpen`, `LuckyWheelOpen`, `DailyRewardsOpen`. While any of them is true, HUDs stand down and touch movement is suppressed.

Some readers check `ZyntraStoreOpen` **directly** rather than through UIDevice: FlashlightController, NoiseReporter, ProtectionHUD, and RoundUI (`dispatchAudio.refresh`). Any new shop window must therefore publish **`ZyntraStoreOpen`**, not a new name (see 5.2).

DisplayOrders:

| GUI | DisplayOrder |
|---|---:|
| ZyntraStore terminal + rail | 55 |
| FriendBoostGui | 60 |
| LevelOneGuideGui | 110 |
| DailyRewardsGui | 117 |
| LuckyWheelGui | 118 (a full takeover that disables every other ScreenGui) |
| ZyntraReentryModal | 120 |

### 1.8 Studio behaviour that changes what you see

- `Config.Studio.GrantAllPasses = true`: **every pass reads as owned in Studio**, so unowned pass states cannot be seen there.
- `StartingTokens = 25` on a new Studio profile.
- `ProtectionAvailable` is always false in Studio, so the Entity Shield card shows `UNAVAILABLE` there.
- `ProcessReceipt` records `CurrencySpent` as 0 in Studio. Test purchases do grant.
- The Token Earner passes are off sale.

---

## 2. Surface by surface

### 2.1 Lobby rail (ZyntraStore)

**Data.** The buttons, top to bottom, are:

| Button | Icon (`rbxassetid`) |
|---|---|
| `ZyntraShopButton` | 132462891522145 |
| `ZyntraOpenButton` (UPGRADES) | 119432640057145 |
| `ZyntraRewardsButton` | 85423575361057 |
| `ZyntraWheelButton` | 111918608092047 |
| `ZyntraMusicButton` | 102262986416811 |

Each button holds `SectionButtonContent > <Kind>Icon, SectionCaption`, plus a `NotificationDot > DotRing` on REWARDS and WHEEL.

**Actions:**
- SHOPS: `openKioskShop()`, which opens the Shop tab.
- UPGRADES: `toggleMain()`. It opens the **last selected tab**; that is a known bug.
- REWARDS / WHEEL: `PlayerScripts.OpenDailyRewards` / `OpenLuckyWheel`.
- MUSIC: inactive until `LobbyMusicEnabled` is a boolean.

**Signals.**
- The dots come from `rewardsClaimable(profile)`: a milestone reached and `Claimed["<min>"] ~= true`.
- And from `wheelClaimable(profile)`: `WheelLast.Claimed == false`, or `WheelDay ~= Today`.
- The dots are recomputed on every profile push and once at the UTC reset (`SecondsToReset`).

**States.** Interactive only when not `InRound`, no `QueueModalOpen`, no screen-owning modal and the window closed. The layout ladder is 64 px squares, then 56 on touch, then a 52 floor, then two columns. It dodges the resting thumbstick glyph.

**Tests:** `test_zyntra_store_compact.py` (5-button rail), `test_rail_dots_intro.py` (predicates sliced out by name), UIRegression rows at lines ~1097 and ~1381 (names forbidden in rounds), and the `ZyntraTerminalFitMatrix` rail rows.

**Risk.** UIRegression and the tests find the rail **by these exact names**. Keep the rail code-built in ZyntraStore and only restyle it. Do not replace it from Framewisp in phase 1 (5.6).

### 2.2 Shop window shell: open/close, tabs, token readout, status line

**Data.**
- Token readout: `profile.Tokens` (`TOKENS  --` before the profile arrives).
- Status line: the `message`/`tone` of every `ZyntraProfileChanged`. It is the **only** place purchase and refusal text appears.

**Open.**
- `openKioskShop(tab)`: the SHOPS rail, `ZyntraOpenTerminal`, and any `ZyntraShopPrompt` ProximityPrompt (none exists any more).
- `toggleMain()`: the UPGRADES rail, and the dev phone via J or in-round.

**Close triggers:** close button, Escape, gamepad ButtonB (bound at High priority), `InRound` change, character death, `Escaped`, `RoundActive` going false while `InRound`, and `QueueModalOpen` (`modalBlocksStore`).

**Publishes:** `ZyntraStoreOpen` (and `DevPhoneOpen` for devs) and `UIDevice.SuppressTouchMovement`. It also moves gamepad selection to the active tab.

**Tabs.** `UPGRADES, SHOP, SKINS, DONATE, COLORS, RECORDS, SETTINGS` and `DEV` for DevAccess.
- SKINS and RECORDS mount `ZyntraSkinsPage` / `ZyntraRecordsPage` through `mount(page, ctx)`. ctx carries: player, Config, UIStyle, UIDevice, COLORS, label, button, corner, outline, action, profile, onProfile, refreshProfile, showStatus, registerLayoutHook, isVisible, contract, pageName.
- **SETTINGS (accessibility) and RECORDS live only here.** A new shop window that drops them must still give a path to them (5.2, owner decision 7.2).

**Tests:** `test_zyntra_store_compact.py` (tiers, tab order, no REWARDS tab) and the UIRegression `ZyntraTerminalFitMatrix`. That matrix uses the CollectionService tag `ZyntraTerminalAction`, the `ZyntraPage`/`ZyntraCardKey` attributes, and `TerminalTapFloor`/`TerminalModalWidth/Height`/`TerminalContentHeight`. Probe actions: open, kiosk, close, tabs, cards, scrolls, donations, relayout, `tab:<Name>`.

### 2.3 SHOP tab

**Keys** (the build order is Supporter, AdvancedEquipment, EntityDetector, Tokens4, Tokens20, EmergencyReentry, ExpeditionPack, CosmeticEquipment, TokenEarner2x, TokenEarner3x, TokenEarner5x):

| Key | Kind | Config | Price source |
|---|---|---|---|
| Supporter, AdvancedEquipment, EntityDetector, CosmeticEquipment | Pass | `Config.Passes[key]` | live `GetProductInfo(GamePass)`, fallback `.Price` |
| Tokens4, Tokens20, EmergencyReentry, ExpeditionPack | Product | `Config.Products[key]` | live `GetProductInfo(Product)` |
| TokenEarner2x / 3x / 5x | Pass (tier card) | `Config.TokenEarner.Passes` | live, and only if `IsForSale`. The card targets `Config.TokenEarner.Offer(livePasses, Tier, owns, tier)`: the cheapest on-sale pass that lifts the owned tier to the card's tier. That is either the direct pass or `TokenEarnerUp2to3/Up3to5/Up2to5`. |

**Ownership signals:**
- Passes: `profile.Owns*` or `ZyntraOwns<Key>`.
- Earner: `Tier(owns)` over the six `ZyntraOwns*` booleans. A card is reached when `tier >= card tier`.
- Stored counts: `ReentryCredits` (shown as `n STORED` on EmergencyReentry).

**Button states today** (`Buy` / `DetailBuy`):
- `<config price> R$` until the live price lands, then `<live> R$`.
- `OWNED` (disabled, teal).
- Earner only: `CHECKING PRICE`, then `<offer> R$` or `UNAVAILABLE` (disabled).
- `COMING SOON` when an id is 0.

**Detail pane** (pointer tier only, content width ≥ 760): kind `PERMANENT PASS` / `DEVELOPER PRODUCT`, name, price or `IN YOUR ACCOUNT`, WHAT YOU GET (Description split on sentences, up to 5), and `BUY  //  N R$`.

**Action:** `productPurchase[key]`. A pass id calls `PromptGamePassPurchase`, a product id calls `PromptProductPurchase`, and an id of 0 shows the status `<Name>: Product ID is not configured yet.`

**Known faults:**
- Cards have no LayoutOrder, so they sort alphabetically.
- Before the first profile, a Robux button is live while ownership is unknown.

**Art.** Each Figma `product-*` `robloxAssetId` **equals** the corresponding Config `IconId` (all 11 checked against `figma-images-v2.json`). Supporter's 106022873152277 is the neutral replacement; the old hazmat art is retired.

### 2.4 Purchase flows: pending, success, failure, token purchase

| Flow | Pending (trigger) | Success (trigger) | Failure / cancel (trigger) |
|---|---|---|---|
| Robux pass | Prompt opened, until `MarketplaceService.PromptGamePassPurchaseFinished(player, id, wasPurchased)` fires on the client | `ZyntraOwns<Key>` turns true. For Supporter/Advanced there is also a success push (1.5). | `wasPurchased == false`: restore the button, no message. A cancel is not an error. |
| Robux product (Tokens4/20, EmergencyReentry, ExpeditionPack, donations) | Prompt opened, until `PromptProductPurchaseFinished(userId, productId, isPurchased)` (client-observable; **never grant from it**) and then the profile push | `ZyntraProfileChanged` with tone `success` (the receipt text in 1.5) | `isPurchased == false`: restore. `NotProcessedYet` (session not ready or not persistent) means **no push**; Roblox retries the receipt later. Show "Processing, it will arrive shortly" after a 15 s timeout. |
| Token spend (upgrade, item, token skin, equip, colour) | `FireServer`, until the next push or a 6 s timeout (silent drops, 1.2) | Push with tone `success` | Push with tone `error` (server text) |
| Entity Shield | `ProtectionClient.GetState().Pending` / `.ServerPending` | `ProtectionLastResponse.Status == "Bought"` | `Rejected` / `Refunded`, or `CanRetry` (shows `RETRY REQUEST`) |
| Token purchase (buying tokens) | Same as Robux product | `+4` / `+20 Zyntra Research Tokens`; `profile.Tokens` rises | Same as Robux product |

There is no in-game confirm dialog before a Robux prompt. Roblox's own prompt is the confirmation, and that should stay so.

### 2.5 UPGRADES tab

| Card (legacy name) | Data | Action | States |
|---|---|---|---|
| STAMINA | `StaminaLevel`, `StaminaPercent`; cost `Config.UpgradeCost(StaminaLevel)` | `ZyntraAction("UpgradeStamina")` | `+N%`, `LEVEL N`, `SPEND n TOKEN(S)  //  +5%`. **Never disabled**: the server refuses in the status line. |
| BATTERY | `BatteryLevel`, `BatteryPercent` | `UpgradeBattery` | same |
| Entity (Entity Shield) | `ProtectionClient.GetState()`: Charges, Tokens, Available, Pending, ServerPending, CanRetry. Cost `Config.ProtectionItem.TokenCost` = 5 | `ProtectionClient.Request("BuyProtection")`, or `.Retry()` when Pending | `OWNED  n`, `5 TOKENS` (disabled when tokens < 5), `CONFIRMING...`, `RETRY REQUEST`, `UNAVAILABLE` |
| SPEED / ROUTE (FIELD SUPPLIES) | `profile.Items[key]`; `Config.Items[key].TokenCost`, `PackSize`, `SpeedMultiplier`, `IconId` | `ZyntraAction("BuyItem", {Key=key})`. Also reachable as `ZyntraShopBuy(key)`. | `n STORED` / `n MARKERS`, `N TOKENS  //  BUY`, then `SAVING...` (6 s timeout). Never disabled for too few tokens. |

**Tests:** `test_zyntra_store_compact.py` (calls `productPurchase.SpeedPotion()` and `.RouteMarker()`), `test_item_inventory.py` and `test_daily_rewards.py` (server `BuyItem`), and `test_equipment_hud.py` (ProtectionClient). UIRegression `Fit.ZyntraExpectedActive.Upgrades = 4`.

**Art.** Field Supplies use `supply-*` (73457681182843, 100856675462356). **Entity Shield, Stamina and Battery have no flat `product-*` art.** `daily-entity-shield` belongs to the Daily/Wheel family only. Owner decision 7.6.

### 2.6 SKINS tab (ZyntraSkinsPage, ZyntraSkins, HazmatSkinVisuals/Driver)

**Order** (`Skins.Order`): BaselineYellow, PoolService, SuburbSurvey, BlacksiteDirector, StaticWraith, FalseSun, SignalArchitect. `skin-sample-1..7` map onto it in this order, and each sample's `robloxAssetId` equals that skin's `PreviewImageId`.

| SkinId | Kind | Price/gate | Button states |
|---|---|---|---|
| BaselineYellow | Free | none | `EQUIPPED` (disabled) / `EQUIP` |
| PoolService | Tokens | 25 | `UNLOCK` / `NEED TOKENS` (disabled), then `EQUIP` / `EQUIPPED` |
| SuburbSurvey | Tokens | 75 | same |
| BlacksiteDirector | Tokens | 300 + `CompletedLevels >= 100` | `LOCKED` (disabled; meta `300 TOKENS · n/100 CLEARS`) / `NEED TOKENS` / `UNLOCK` |
| StaticWraith | Robux pass 1994666374 | R$ 99 live, `IsForSale` checked | `CHECKING PRICE` (meta), `BUY` (meta `N R$`), `UNAVAILABLE` (meta `PRICE UNAVAILABLE`) |
| FalseSun | Robux pass 1994816385 | R$ 149 | same |
| SignalArchitect | Developer | not for sale | The card exists only for DevAccess. `DEVELOPER ONLY` / `UNAVAILABLE` until the grant lands. |

**Actions:**
- owned and not equipped: `EquipSkin(id)`
- Tokens kind: `BuySkin(id)`
- verified Robux pass: `PromptGamePassPurchase(player, PassId)`

**Signals.**
- `profile.Skins.Owned/Equipped` and `profile.Tokens`/`CompletedLevels`.
- `ZyntraOwns<SkinId>` for the passes. The server grants `Skins.Owned` on pass detection.
- `ZyntraSkinId` is what other players see.

**3D preview.** A ViewportFrame clones `ReplicatedStorage.HazmatSkinPreviewTemplates.<SkinId>`; it shows `3D PREVIEW LOADING` until the template exists. False Sun motes are suppressed under `ReduceFlashing`. **Framewisp cannot produce this**, so it stays code-built inside a placeholder frame (section 6).

**Equip effect.** HazmatSkinVisuals renders the suit **only while `InRound` and `RoundActive`**. Equipping in the lobby changes nothing visible on the avatar, so the UI should say so (for example `EQUIPPED · WORN IN YOUR NEXT RUN`).

**Tests:** no dedicated offline test. UIRegression captions cover `EQUIPPED`, `NEED TOKENS` and `LOCKED`.

### 2.7 DONATE tab

**Keys** (`Config.Donations`, `Order` 1..9): DonationSignal (10), DonationSupply (50), DonationField (100), DonationResearch (250), DonationCommand (500), DonationDirector (1000), Donation5000, Donation10000, all developer products, and Donation20K (`Kind = "GamePass"`, id 1978617781).

**Actions:**
- product: `PromptProductPurchase(Id)`
- pass: `PromptGamePassPurchase(Id)`, guarded by `ZyntraOwnsDonation20K`

**States:**
- `N R$  //  DONATE` / `N R$  //  ONE-TIME` (live price).
- `OWNED` (20K only, muted, disabled).
- `COMING SOON` (id 0).

**Readout:** `RECORDED SUPPORT n R$ / Donations / Products / Passes` from the profile, plus the static note "Purchases made before 2 Sep 2026 are not recorded."

**Contract attributes:** `DonationTierKey`, `DonationProductId`, `DonationPurchaseKind` on each card. UIRegression's `Fit.DonationTierKeys` holds all 9 keys by name.

### 2.8 COLORS tab

**Pickers:**
- `Hazmat` (`SetHazmatColor`, locked unless `OwnsAdvancedEquipment`, overlay `ADVANCED EQUIPMENT REQUIRED`).
- `Glowstick` (`SetGlowstickColor`, locked unless `OwnsCosmeticEquipment`, overlay `GLOWSTICK CUSTOMIZER REQUIRED`).

**Sliders:** H 0..1, S 0..0.9, V 0.35..1. The value is clamped the same way on load.

**Data:** `profile.HazmatColor` / `GlowstickColor`.

**SAVE behaviour.** SAVE stays Active while locked and shows the lock text in the status line (`Fit.ZyntraExpectedActive.Colors = 2`). The lock overlay offers no buy button today; the new design should add one (`GetPass_button`, section 6).

### 2.9 Daily Rewards modal (Daily Rewards Client + ZyntraDailyRewardsPage + ZyntraDailyResearch)

**Open/close.** Opened by `OpenDailyRewards`. It closes on `InRound`, `QueueModalOpen` and `RoundActive`. It publishes `DailyRewardsOpen` (DisplayOrder 117).

**Data:** `profile.Daily`.
- Milestones: `Config.DailyRewards.Milestones` (5 min: 1 token; 15 min: 1 Speed Potion; 35 min: 1 Entity Shield).
- Research: Fuse +1, Lever +1, Clear +2. These are granted automatically server-side; there is no claim button.

**Action:** `ClaimPlaytimeReward({Minutes})`.

**States:**
- `RESETS IN hh:mm:ss`.
- Milestone button: `m:ss TO GO` (disabled), then `CLAIM`, `CLAIMING...` and `CLAIMED`.
- Research rows: incomplete or complete.
- `RewardsOffline` when the config is absent.

**Names:** `DailyRewardsGui > DailyRewardsShade > DailyRewardsPanel > RewardsHeader (HeaderGift, HeaderTitle), CloseButton, PageContent, StatusLine`. The page holds `DailyRewards > CountdownStrip/ResetCountdown, PlaytimeSection > PlayStrip/PlaytimeReadout, ProgressTrack/Fill, ProgressCaption, Milestone<5|15|35> > Threshold, RewardIcon, ClaimedCheck/CheckMark, RewardName, ClaimButton, ClaimedLabel; PlaytimeNote; ResearchHeading; Research<Fuse|Lever|Clear>`.

**Art:** gift 117126194981100, token 93116899475472, potion 120211340805188, shield 126728249949579.

**Tests:** `test_daily_rewards_client.py`, `test_daily_rewards_page.py`, `test_daily_rewards.py` (server).

### 2.10 Lucky Wheel (Lucky Wheel Client)

**Takeover.** Opened by `OpenLuckyWheel`. It is a full takeover: every other ScreenGui is disabled and kept disabled, then restored on close. It publishes `LuckyWheelOpen` (DisplayOrder 118). It closes on `InRound`, `QueueModalOpen` and `RoundActive`.

**Data.**
- `Config.DailyRewards.Wheel` has **six** fields: Token1 40, Token3 20, Potion1 20, Potion2 5, Shield1 10, Skin5 5. CLAUDE.md's "five fields" note is stale.
- `profile.Daily.WheelDay/WheelLast/SecondsToReset`.
- Disc texture: `rbxassetid://70472139920072`. CLAUDE.md's 86770264881525 is stale.

**Actions:** `SpinDailyWheel`, then `ClaimWheelPrize`.

**Hub states:** `SPIN`, `SPINNING` (a tap skips the animation), the prize face, `COLLECT\n<prize>` / `COLLECT\nPRIZE`, `COLLECTING`, `<prize>\nCOLLECTED`, `RETRY`, and `SPUN\nhh:mm:ss`. The disc rotation and the polar placement of `FieldLabel1..6` / `FieldOdds1..6` are computed in code. ReduceFlashing gives a shorter Sine spin.

**Names:** `LuckyWheelGui > WheelShade > WheelHolder > WheelDisc, FieldLabel<n>, FieldOdds<n>, WheelPointer, HubButton, CloseButton`.

**Test:** `test_lucky_wheel_client.py`.

### 2.11 Emergency Re-entry modal (ZyntraStore, `ZyntraReentryModal`, DisplayOrder 120)

**Shown when** `InRound`, `RoundActive`, the player is dead, `ZyntraReentryUsed ~= true`, the modal has not been dismissed, and **`PartyDownWindowOpen` is false**. The modal stands down for the PARTY DOWN window.

**Button:**
- `USE RE-ENTRY CREDIT  //  n OWNED`: `ZyntraAction("UseReentry")`.
- `<price> R$  //  BUY CREDIT`: `PromptProductPurchase(EmergencyReentry.Id)`. The receipt then auto-uses the credit.

`SPECTATE` dismisses the modal. `FREE RESPAWN  //  DEV` (`DevCheatCommand:Fire("freeRespawn")`) appears for DevAccess only.

**Publishes:** `ZyntraReentryOpen`, `ZyntraReentryCredits/Price/ProductId`.

**Tests:** `test_reentry_dismissal.py` (it extracts the real UI and callbacks from ZyntraStore), `test_dev_free_respawn_offer.py`, `test_controller_input.py`.

### 2.12 PARTY DOWN card (RoundUI, inside a `do ... end` block)

**Server contract:**
- GameManager fires `RoundStatus "partydown", 15, lastDeathName` once. The name is nil after a leave.
- `"partydownclear"` closes the card, as do `"lose"`, `"win"` and the round ending.

**Names:** `PartyDownOverlay > PartyDownCard > PartyDownTitle, PartyDownFallen, PartyDownTrack > PartyDownFill, PartyDownTimer, PartyDownReentry, PartyDownFreeRespawn (dev), PartyDownDecline`.

**Button behaviour.** Buttons arm after 0.6 s. The re-entry button reads **only** the client-local `ZyntraReentryCredits/Price/ProductId`. With credits it fires `UseReentry`; otherwise it calls `PromptProductPurchase(ZyntraReentryProductId)`.

**Publishes:** `PartyDownCardOpen` (the card is drawn) and `PartyDownWindowOpen` (the window owns the purchase). These are two different facts.

**Constraint.** **RoundUI's main chunk is at the 200-register limit.** Any restyle stays inside that do-block (fields on the `pd` table, no new top-level local) and must be followed by the compile probe.

**Tests:** UIRegression row (`Forbids = {"ZyntraReentryModal"}`, `TouchTargets = {"PartyDownDecline"}`), `test_round_exit_hold.py`, `test_dev_free_respawn_offer.py`.

### 2.13 Lobby shop wall card (LobbyShopDisplay + Shop Display Client)

**Data.** The server builds 10 hologram boxes in this order: Supporter, AdvancedEquipment, Tokens4, Tokens20, EmergencyReentry, ExpeditionPack, CosmeticEquipment, SpeedPotion, RouteMarker, and EntityDetector appended. It publishes `ZyntraShopFocus` from the plates.

**Card.** The client draws `ZyntraShopDisplayCard > ShopDetailCard > ItemIcon, ItemMonogram, ShopTitle, ItemName, ItemKind, ItemDescription (ProductContents), ItemState, Buy, Close, CloseHint`.

**States:**
- `PERMANENT -- BOUGHT ONCE` / `OWNED`.
- `ADDS N RESEARCH TOKENS`.
- `STORED CREDITS  n`, read from the client-local `ZyntraReentryCredits`.
- `n STORED`.
- BUY reads `N R$` (live), `N TOKENS  //  BUY`, `OWNED` or `UNAVAILABLE`.
- The second button is `TRY DEMO` for AdvancedEquipment, CosmeticEquipment and EntityDetector, otherwise `CLOSE`.

**Actions:**
- BUY fires `PlayerScripts.ZyntraShopBuy(key)`, or shows `STILL LOADING -- TRY AGAIN` when the bridge is missing.
- Analytics: `ShopView {Key, Demo}` and `DeviceClass` after `ZyntraProfileLoaded`.

**Test:** `test_lobby_shop_display.py`. It asserts that BUY routes to `ZyntraShopBuy` exactly once and that an owned pass does not prompt.

### 2.14 Friend Boost chip (Friend Boost Client)

**Data:** `FriendBoostPercent` and `FriendBoostFriends`, both replicated and server-computed.

**Action:** `SocialService:PromptGameInvite(player)` only. Nothing is sent to the server.

**Names:** `FriendBoostGui (DisplayOrder 60) > FriendBoostChip > BoostLabel, FriendsLabel, InviteButton`.

**Texts:** `FRIEND BOOST +N%`, then `INVITE FRIENDS TO EARN +10% PER FRIEND`, `1 FRIEND ON THIS SERVER` or `n FRIENDS ON THIS SERVER`.

**Visible only** inside the lobby bounds, with no round flags and no screen-owning modal.

**Test:** `test_friend_boost.py`.

### 2.15 Rewards intro card (ZyntraStore, `RewardsIntroCard`)

The card shows once when `CompletedLevels >= 1` and `RewardsIntroSeen ~= true`, after 4 quiet seconds in the lobby. `GOT IT` sends `MarkRewardsIntroSeen`. It is out of scope for the shop window, but it sits beside the rail.

---

## 3. Tests that pin today's UI

| Test | Pins |
|---|---|
| `tools/tests/test_zyntra_store_compact.py` | Terminal tiers (phone/tablet/pointer), shop list+detail, tab order and presence, 5-button rail, `productPurchase.SpeedPotion/RouteMarker`, modal flags |
| `test_lobby_shop_display.py` | Wall build/order, card states, the `ZyntraShopBuy` bridge into ZyntraStore |
| `test_reentry_dismissal.py` | Re-entry modal lifecycle. It **extracts** code from ZyntraStore, so do not rename `updateReentry` / `bindCharacter`. |
| `test_rail_dots_intro.py` | `rewardsClaimable` / `wheelClaimable` / `introWanted`, sliced from ZyntraStore by name |
| `test_daily_rewards_client.py`, `test_daily_rewards_page.py` | The Daily modal and page |
| `test_lucky_wheel_client.py` | The wheel |
| `test_friend_boost.py` | Chip, module, payout |
| `test_controller_input.py` | Slices the real `UIDevice.SCREEN_OWNING_MODALS` |
| `test_round_exit_hold.py`, `test_dev_free_respawn_offer.py`, `test_equipment_hud.py` | PARTY DOWN, free respawn, ProtectionClient |
| `test_daily_rewards.py`, `test_item_inventory.py`, `test_support_product_receipts.py`, `test_token_grants.py`, `test_feedback_gift.py`, `test_zyntra_analytics.py`, `test_purchase_alerts.py` | Server side of every action and receipt above |
| `ReplicatedStorage.UIRegression` | `ZyntraTerminalFitMatrix`: tag `ZyntraTerminalAction`, `Fit.ZyntraFloorFallback = 44`, `Fit.ZyntraDisabledCaptions`, `Fit.ZyntraExpectedActive {Upgrades=4, Colors=2, Records=1}`, `Fit.DonationTierKeys`. It also has the rail-name rows, the PARTY DOWN row and the modal-attribute list (line ~2224). |

Several tests restate the modal list in their fakes: `daily_rewards_client`, `friend_boost`, `lucky_wheel_client`, `round_exit_hold`. They keep passing because the proposal reuses `ZyntraStoreOpen`.

---

## 4. Risks

1. **Double purchase paths.** If two UIs or a Framewisp-generated script wire the same Buy, one tap can open two prompts or spend tokens twice.
   - Exactly one dispatcher (5.3).
   - Delete every `LuaSourceContainer` from the imports. A `RunContext = Client` script runs even inside ReplicatedStorage.
   - Disable each Buy_button from the prompt until `Prompt...Finished` (or 30 s).
   - Server idempotency (`ReceiptIds`, one-time passes, the 1 s windows) is the backstop, not the plan.
2. **Client-trust attributes.** `ZyntraReentryCredits/Price/ProductId` and `ZyntraStoreOpen` are client-local and display only. The server never reads them, and nothing new may start trusting them. Robux prices are never trusted from config: they are read live, and earner/skin passes are verified `IsForSale`.
3. **Profile-loaded gating.** Until `ZyntraProfileLoaded == true` **and** the first profile has arrived:
   - Every Buy_button is disabled with `LOADING`.
   - TokenCount shows `--`.
   - No ownership is assumed.

   Today a Robux card is live before ownership is known. `ZyntraGetProfile` can return nil after 10 s; retry on the next `ZyntraProfileChanged`. If `passReadFailed`, ownership keeps the last attribute value and the server rechecks.
4. **Fit tiers and tap floor.** The legacy terminal has three measured content tiers and a 44 px logical tap floor that UIRegression enforces. A Framewisp "Fit & centre" 1920x1080 composition scales by about 0.361 on an 844x390 phone, or about 0.307 under a 58 px top inset.
   - A 96 px button becomes about 35 px and fails 44.
   - Reaching 44 needs **≥ 122 artboard px**, or ≥ 144 if the inset applies.

   The window must also fit `UIDevice.ModalViewport` (the safe area, `IgnoreGuiInset = false`). TextScaled caps at 100 px, so 72-80 px hero prices can clip on ≥ 1440p screens if Framewisp uses TextScaled. Owner decision 7.1.
5. **Register limits.** RoundUI is at 200 top-level registers, and ZyntraStore says of itself that it is "close to Luau's 200-local ceiling".
   - Every edit to either goes inside function bodies or `do ... end` blocks.
   - Run `tools/studio_compile_probe.luau` after each edit.
6. **Accessibility reachability.** SETTINGS and RECORDS exist only in the legacy terminal. If the rail opens the new window, both need a path from it (5.2).
7. **Lucky Wheel takeover.** The wheel disables and restores every ScreenGui, including the new one. The two must never be open together; the openers already check `ScreenOwningModalOpen`.
8. **Silent server drops** (1.2). Without client timeouts, a pending state can stick forever.
9. **Token Earner offer mismatch.** If the new UI shows an earner price and a different script prompts, a transient fetch failure leaves the prompting side with `Id = 0`. Its error then lands in a hidden status line, so it reads as a silent no-op. The fix: the same script that displays the offer prompts it (5.3).
10. **Studio masks states** (1.8). GrantAllPasses, ProtectionAvailable=false, and the earner passes off sale. Unowned and on-sale states are covered by the offline harness, not by a Studio look.
11. **Framewisp unknowns** (verify on the first import):
    - Whether tag suffixes stay in `Instance.Name`.
    - Whether `_tab`/`_button` generate scripts.
    - ScrollingFrame canvas sizing.
    - Whether an image fill becomes an ImageLabel or a Frame with an image child.
    - The free plan's 15 distinct images per frame.
12. **Equip expectations.** The suit only renders in rounds (2.6).
13. **Mixed builds.** No server, profile or remote change is proposed, so old and new client builds can share servers. No "Migrate To Latest Update" is needed.

---

## 5. Integration architecture (proposal)

### 5.1 Principles

- **ZyntraMonetization stays untouched.** No new remote and no new server attribute. The new UI speaks only the existing remotes (1.1-1.2), MarketplaceService and `ProtectionClient`.
- **One binder, driven by layer names.** One new LocalScript finds nodes by the names in section 6, writes only the dynamic slots, and wires every button through one `purchase(key)` dispatcher. Static copy (names, hooks, benefits) stays as designed.
- **Legacy stays alive and is the fallback.** ZyntraStore keeps:
  - the rail
  - the re-entry modal
  - the intro card
  - RECORDS, SETTINGS and DEV
  - the wall card's `ZyntraShopBuy` bridge
  - its whole terminal, which remains the rollback

  The new window replaces only the five shop tabs (UPGRADES, SHOP, SKINS, DONATE, COLORS) **while a layout is selected**.

### 5.2 Pieces

| Piece | Where | New? |
|---|---|---|
| Framewisp imports `Shop_L1..L4` and per-tab frames (6.1) | `ReplicatedStorage.ZyntraShopUI` (Folder). Not StarterGui, so all four are not cloned into every PlayerGui. | new (assets, Studio first) |
| Controller | `StarterPlayer.StarterPlayerScripts."Zyntra Shop UI"` (one LocalScript) | new (Studio first) |
| Routing hook | ZyntraStore `openKioskShop(tab)` and the lobby branch of `toggleMain()`: `local alt = player.PlayerScripts:FindFirstChild("ZyntraShopUIOpen"); if alt and alt:Invoke(tabOrDefault) == true then return end`. UPGRADES passes `"Upgrades"`, which also fixes the "opens the last tab" bug. | 2 small edits, locals inside functions only |
| Optional DEV row "SHOP LAYOUT" | ZyntraStore DEV tab | optional |

**What the controller does:**
- Creates the BindableFunction `PlayerScripts.ZyntraShopUIOpen`. It returns **true only** when a layout is selected, that layout bound without missing purchase-critical names, the tab is one of the five shop tabs, and the player is in the lobby. Everything else returns false, so legacy opens (RECORDS, SETTINGS, DEV, in-round).
- Clones the selected layout into a ScreenGui `ZyntraShopUI` (DisplayOrder 55, `ResetOnSpawn = false`, `IgnoreGuiInset = false`, Sibling) and sizes it to `UIDevice.Layout()` ModalViewport. It deletes every LuaSourceContainer and `*_ignore` node.
- Assembles `Page_<Tab>` from each tab frame into the shell (6.1).
- **Publishes `ZyntraStoreOpen = true|nil`.** It reuses the existing name because RoundUI, FlashlightController, NoiseReporter, ProtectionHUD and UIDevice already read it. While open, it re-asserts the value if anything clears it.
- Closes on the same triggers as legacy (2.2), binds gamepad ButtonB/Escape, and selects the active tab for gamepads.
- Subscribes to `ZyntraProfileChanged` and invokes `ZyntraGetProfile` once.
- Fetches live prices **on first open**, once per session, through pcall'd `GetProductInfo`.
- Shows the `message`/`tone` of each push in `Footer > Status` and the optional `Toast`.
- Header `Settings_button` / `Records_button` call `PlayerScripts.ZyntraOpenTerminal:Fire("Settings" | "Records")` after closing itself, which keeps accessibility reachable (risk 6).

**Tokens attribute.** No new `ZyntraTokens` attribute: the binder writes TokenCount from `profile.Tokens`. Add one, client-local and display-only, only if a Framewisp `{attr:}` binding is ever wanted.

**Analytics.** Optionally send `ShopView {Key}` when the L3 detail selection changes, to keep the shop funnel comparable. Recording which layout was used would need a server change, so that is out of scope.

### 5.3 The one dispatcher: `purchase(key)` in the controller

| Layer key | Call |
|---|---|
| `Card_Supporter` / `AdvancedEquipment` / `EntityDetector` / `CosmeticEquipment` | `PromptGamePassPurchase(player, Config.Passes[key].Id)`. Skip if owned. |
| `Card_Tokens4` / `Tokens20` / `EmergencyReentry` / `ExpeditionPack` | `PromptProductPurchase(player, Config.Products[key].Id)` |
| `Card_TokenEarner2x` / `3x` / `5x` | Compute `offer = Config.TokenEarner.Offer(livePasses, Config.TokenEarner.Tier, owns, tier)` here. Prompt `PromptGamePassPurchase(player, livePasses[offer].Id)` from **the same script that rendered it** (risk 9). With no offer the button is disabled. |
| `Card_SpeedPotion` / `RouteMarker` | `ZyntraAction:FireServer("BuyItem", {Key = key})`, with a 6 s `SAVING...` pending state |
| `Card_EntityShield` | `ProtectionClient.GetState().Pending and ProtectionClient.Retry() or ProtectionClient.Request("BuyProtection")` |
| `Upgrade_Stamina` / `Upgrade_Battery` | `FireServer("UpgradeStamina" \| "UpgradeBattery")` |
| `SkinCard_<SkinId>` | owned and not equipped: `FireServer("EquipSkin", id)`; Tokens kind: `FireServer("BuySkin", id)`; Robux kind and verified: `PromptGamePassPurchase(player, Skins.ById[id].PassId)` |
| `Donate_<DonationKey>` | `Kind == "GamePass"`: `PromptGamePassPurchase` unless `ZyntraOwnsDonation20K`. Otherwise `PromptProductPurchase(Config.Donations[key].Id)`. |
| `Picker_<Hazmat\|Glowstick>` / `Save_button` | `FireServer("Set" .. Picker .. "Color", Color3.fromHSV(h, s, v))` |
| `Lock_panel` / `GetPass_button` | `purchase("AdvancedEquipment")` / `purchase("CosmeticEquipment")` |
| `AddTokens_button`, `GoUpgrades_button` | Navigation only: scroll to or select `Section_Tokens` / `Card_Tokens20`, or switch to tab Upgrades |

**Duplication.** The Robux prompting duplicates about 15 lines of ZyntraStore's `productPurchase`, which is intentional. Phase C (5.6) moves the `ZyntraShopBuy` bridge onto this dispatcher, after which ZyntraStore's copy is deleted.

### 5.4 Switching layouts for the owner's evaluation

**Attribute** `ZyntraShopLayout` = `"L1" | "L2" | "L3" | "L4"`. Anything else or nil means legacy.

1. **Player override** (client-local, honoured only when `DevAccess.IsAllowed(player)`). From the Studio command bar on the client: `game.Players.LocalPlayer:SetAttribute("ZyntraShopLayout", "L2")`. The optional DEV row sets the same attribute.
2. **Workspace default** (`workspace:GetAttribute("ZyntraShopLayout")`). It is saved with the place, and it is the release switch.

The controller reads the attribute on every open and rebuilds when the value changed while the window was closed. A layout that fails binding warns `[ZyntraShopUI] L2 missing: Card_Tokens20/Buy_button/Price` and returns false, so legacy opens. The binder doubles as the Studio name-lint.

### 5.5 What must be created in Studio first

Per CLAUDE.md, the sync tools cannot create scripts.

1. **Audit.** Run `pull_source_from_studio.py --audit` and pull the 5 drifted scripts (section 0). `git status` for foreign files.
2. **Imports.** Import the four layouts through Framewisp into `ReplicatedStorage.ZyntraShopUI`. Strip scripts. Run a one-shot `execute_luau` walk that lists every node name per layout, and diff it against section 6.
3. **Controller.** Create the LocalScript `"Zyntra Shop UI"` through `execute_luau` with `ScriptEditorService:UpdateSourceAsync`. Add its manifest item with `sha256_of` / `canonical_bytes` from `tools/studio_source_contract.py`.
4. **ZyntraStore routing edit.** Make it in Studio, then mirror it. Then run the compile probe.
5. **UIRegression lane.** Add the new lane (5.7). Add the new captions to its own caption list. Leave `ZyntraTerminalFitMatrix` as it is: legacy still exists.

There are no server, Config or ProcessReceipt changes, no new remotes, no new DataStore fields, and no publish-migration concerns.

### 5.6 Migration and rollback

- **A. Evaluation.** The workspace attribute stays unset, so all players see legacy. Developers set the player override to compare L1-L4 on PC and in the Device Simulator (`ForceTouchUI`).
- **B. Release one layout.** Set `workspace.ZyntraShopLayout`, then publish. The legacy terminal keeps RECORDS, SETTINGS and DEV, and stays the fallback.
- **Rollback, three ways.** Clear the workspace attribute (publish). Disable the controller (publish). Or do nothing: any binding failure already falls back per player at open time. No data migrates, so nothing needs undoing.
- **C. Later, by owner decision only.** Delete the legacy SHOP, UPGRADES, SKINS, DONATE and COLORS pages. Move `ZyntraShopBuy` to the controller. Trim `ZyntraTerminalFitMatrix` and `test_zyntra_store_compact.py`. Decide whether RECORDS and SETTINGS get new designs.
- **Phase 2 surfaces.** Daily Rewards, the wheel, the re-entry modal, PARTY DOWN, the wall card, the friend chip and the rail are restyled in their own scripts later. Their Figma frames use the existing instance names (6.8), so a restyle swaps visuals without changing behaviour or test lookups. The wheel disc spin, the field placement and the skin viewport stay code-driven.

### 5.7 Test plan

**Offline (new):** `tools/tests/test_zyntra_shop_ui.py`. It runs the real controller under offline Luau (`LUAU_BIN`) with a fake PlayerGui. Each layout's fake tree is generated from the section 6 name list, and the remotes and MarketplaceService are fakes.

It asserts:
1. Every layout binds, and a missing `Buy_button` makes `ZyntraShopUIOpen` return false.
2. Each button causes **exactly one** expected call: a `Prompt*` with the right id, or `FireServer(action, payload)`.
3. State text for these profile fixtures:
   - no profile yet
   - `ZyntraProfileLoaded` false
   - 0 tokens
   - owned passes
   - earner tiers 1/2/3/5, including the upgrade offers and off-sale passes
   - each skin state
   - 20K owned
   - colour locks
4. Pending timeouts after a silent drop.
5. `ZyntraStoreOpen` set and cleared on every close trigger.
6. Nothing prompts before the profile arrives.

**Offline (existing, must stay green):** every test in section 3. Known failures at HEAD, unrelated: `test_level3_run_in_exit`, `test_level3_hidden_chase`, `test_level3_slide_aperture`.

**Studio:**
1. Compile probe.
2. `pull --audit`.
3. Play solo for each layout:
   - Open from SHOPS and from UPGRADES (both should land on the right tab).
   - Studio test-purchase of Tokens4: expect the toast `+4 Zyntra Research Tokens` and the TokenCount rising.
   - `UpgradeStamina`.
   - Buy a Speed Potion.
   - Unlock and equip PoolService.
   - Save both colours.
   - Open RECORDS and SETTINGS through the header path.
   - Close by ButtonB.
   - Confirm the rail, Friend chip and HUD stand down while the window is open.
   - Confirm the wheel takeover restores the window ScreenGui disabled-to-enabled correctly.
4. Run the UIRegression `ZyntraTerminalFitMatrix` (legacy unchanged).
5. Run the new lane `ZyntraShopFitMatrix` over `Fit.Devices`:
   - bound Buy_buttons ≥ the chosen tap floor
   - rendered text ≥ 11 px
   - reachable plus stood-down-with-caption equals the authored set
   - `ZyntraStoreOpen` true while open
6. Entity Shield `Bought` and the unowned pass states need a published dev server, or a temporary `Config.Studio.GrantAllPasses = false` (owner decision 7.5).

---

## 6. bindingNames: the layer-name contract for every Figma screen

### 6.0 Rules

1. **Tag suffixes are allowed and ignored.** The binder strips a trailing `_button`, `_close`, `_panel`, `_tabgroup`, `_scroll`, `_grid`, `_list`, `_txt`, `_shadow`, `_ignore`, `_tab:<X>`, `_aspect` and `_fit`, repeatedly, before matching. So `Buy_button`, `Name_txt` and `Close_button_close` bind as `Buy`, `Name` and `Close`.
2. **`<Key>` is the exact code key, case-sensitive, from the lists below.** Never use a display name ("Glowstick Customizer" is `CosmeticEquipment`).
3. **Fixed catalogue: the binder never clones templates.** Every key gets its own authored card. A key with no card is "not sold in this layout" and is reported by the lint.
4. **Names are unique within a card. A card's descendants are searched recursively** (`FindFirstChild(name, true)` after suffix strip), so wrappers such as `Art` and `BuySlot` are free.
5. **Never name a node after a GuiObject property:** Name, Text, Image, Size, Position, Visible, Parent, Active, Rotation. Code dot-access would hit the property. Use `Name_txt`, not `Name`. The binder tolerates `Name` (the L3 row spec) through `FindFirstChild`, but it is discouraged.
6. **The binder only writes the slots marked (dyn).** Everything else is static design copy.
7. **Owned cards keep `Buy_button`.** The binder disables it and writes `Price = "OWNED"`. Never rename by state.
8. **Images.** `ProductIcon`, `SkinArt`, `RewardIcon` and `CategoryIcon` are re-pointed by the binder to the in-game asset id (the `robloxAssetId` in `figma-images-v2.json` equals the Config IconId / PreviewImageId). Framewisp's own uploaded copy is only a placeholder, so any 15-image budget does not limit product art.

### 6.1 Shell (identical in all four layouts)

**Root frames.**
- Shop tab: `Shop_L1`, `Shop_L2`, `Shop_L3`, `Shop_L4`.
- Other tabs: `Shop_L#_Upgrades`, `Shop_L#_Skins`, `Shop_L#_Donate`, `Shop_L#_Colors`. Each has the same window geometry. The binder takes only its `Page_<Tab>` and parents it into the `Shop_L#` shell.

```
Shop_L#
├ Backdrop_ignore                      (mockup only, stripped)
├ Dim                                  (becomes the modal input shield)
├ WindowShadow_shadow
└ ShopWindow_panel
  ├ Header
  │ ├ TitleBlock > Eyebrow, Title, TitleBar
  │ ├ TokenPill > TokenGlyph, TokenCount (dyn: profile.Tokens | "--"), TokenLabel, AddTokens_button
  │ ├ Settings_button, Records_button      (NEW, required: open legacy SETTINGS / RECORDS)
  │ ├ CloseSlot > CloseShadow_shadow, Close_button_close
  │ └ HeaderRule
  ├ Categories_tabgroup
  │ └ Tab_<Tab>_tab:<Tab> > CategoryIcon, Label, ActiveBar (dyn: Visible on the active tab)
  │     <Tab> ∈ Upgrades | Shop | Skins | Donate | Colors
  ├ Page_Shop | Page_Upgrades | Page_Skins | Page_Donate | Page_Colors   (dyn: only the active one Visible)
  ├ Footer > Status                       (dyn: last push message, tone colour)
  └ Toast (optional, hidden) > ToastText (dyn), ToastIcon_Success, ToastIcon_Error
```

### 6.2 SHOP tab (`Page_Shop`)

```
Page_Shop
├ Products_scroll > Content_list
│ ├ Featured_panel | Hero_panel > Card_ExpeditionPack
│ ├ Section_Passes  > SectionHeader (SectionTitle, SectionBar, SectionHelper) + Passes_grid | Passes_scroll > Passes_list
│ ├ Section_Earner  > SectionHeader + Earner_grid | Earner_list | Earner_panel
│ │   L1: EarnerStatus > EarnerTier (dyn "2x"), EarnerBadge
│ │   L2: LadderLink_2to3, LadderLink_3to5 (dyn: rail-teal when reached)
│ └ Section_Tokens  > SectionHeader + Tokens_grid | Tokens_list   (L1: GoUpgrades_button)
└ Detail_panel (L3 only)
  ├ DetailArt > ProductIcon (dyn), Ribbon > RibbonText (dyn)
  ├ Kind (dyn), Name_txt (dyn), Benefit_txt (dyn), WhatYouGet
  ├ Contents_list > ContentRow_1..ContentRow_5 > Count (dyn), Label (dyn)
  └ BuySlot > BuyShadow_shadow, Buy_button > Price (dyn), PriceLabel (dyn)
```

**Card keys:** `Card_<Key>`, in L3 `Card_<Key>_button` (the whole row selects). `<Key>` ∈ `Supporter, AdvancedEquipment, EntityDetector, CosmeticEquipment, Tokens4, Tokens20, EmergencyReentry, ExpeditionPack, TokenEarner2x, TokenEarner3x, TokenEarner5x`.

**Every card:**

```
Card_<Key>
├ Art > ProductIcon (dyn image), Ribbon > RibbonText (dyn for TokenEarner*: "SAVE R$ n", hidden when no saving),
│        OwnedBadge > BadgeText (dyn: "OWNED" | "ACTIVE" | "<n> STORED"; hidden otherwise)
├ Name_txt (static)   Hook (static; dyn for TokenEarner*)   Benefit_txt (static)   Meta (dyn for TokenEarner*: "WAS R$ n")
└ BuySlot > BuyShadow_shadow, Buy_button > Price (dyn), PriceLabel (dyn: "UPGRADE" | "" )
```

**`Price` values:**
- `LOADING` (disabled)
- `R$ <live>`
- `OWNED` (disabled)
- `WAITING` (disabled, while a prompt is open)
- `CHECKING PRICE` (disabled, earner only)
- `UNAVAILABLE` (disabled)
- `COMING SOON` (disabled)

**Ribbon and badge rules:**
- Static ribbons (`FEATURED BUNDLE`, `BEST VALUE`) stay as designed.
- EmergencyReentry `OwnedBadge` shows `<ReentryCredits> STORED` when the count is > 0.
- On the earner cards, `ACTIVE` goes on the card whose tier equals `Tier(owns)`, and `OWNED` on lower reached tiers.

**Detail pane (L3) for the selected key:**
- `Kind`: `PERMANENT PASS` / `REPEATABLE` / `REPEATABLE BUNDLE`.
- `Contents_list`: for ExpeditionPack, rows 1-3 come from `BundleGrant {Reentry=1, Shield=1, RouteMarkers=3}`. For any other key, each row's Label is one Description sentence (legacy `splitBenefits`, max 5) and its Count is hidden.

### 6.3 UPGRADES tab (`Page_Upgrades`)

```
Page_Upgrades > Upgrades_scroll > Content_list
├ Section_Upgrades
│ ├ Upgrade_Stamina > Art, Name_txt, Percent (dyn "+N%"), LevelReadout (dyn "LEVEL N"),
│ │                   Buy_button > Price (dyn "N TOKEN(S)" | "SAVING..."), PriceLabel (static "+5%")
│ ├ Upgrade_Battery  (same children)
│ └ Card_EntityShield > Art, Name_txt, Percent (static "5s"), StoredCount (dyn "OWNED n"),
│                       Buy_button > Price (dyn "5 TOKENS" | "CONFIRMING..." | "RETRY REQUEST" | "UNAVAILABLE")
└ Section_Supplies
  ├ Card_SpeedPotion > Art > ProductIcon (dyn), Name_txt, Percent (static "+30%"), StoredCount (dyn "n STORED"),
  │                    Buy_button > Price (dyn "3 TOKENS" | "SAVING...")
  └ Card_RouteMarker > … same, StoredCount (dyn "n MARKERS"), Price "2 TOKENS"
```

`Upgrade_<Stat>` maps to the action `"Upgrade" .. Stat`, the profile fields `Stat .. "Level"` and `Stat .. "Percent"`, and the cost `Config.UpgradeCost(level)`. `Card_EntityShield` is `Config.ProtectionItem`. Its Config key `EntityProtection` is not used as a layer name; `EntityShield` is the reward key in `Config.DailyRewards`.

### 6.4 SKINS tab (`Page_Skins`)

```
Page_Skins
├ SkinPreview_panel > SkinViewport (empty Frame; the binder inserts the ViewportFrame), PreviewName (dyn), PreviewStatus (dyn), PreviewHint (dyn)
└ Skins_scroll | Skins_grid > SkinCard_<SkinId>
    SkinCard_<SkinId> > SkinArt (dyn image = PreviewImageId), View_button (optional; else the card/art selects),
                        Name_txt, Meta (dyn), EquippedBadge > BadgeText (dyn), Buy_button > Price (dyn)
```

**`<SkinId>`** ∈ `BaselineYellow, PoolService, SuburbSurvey, BlacksiteDirector, StaticWraith, FalseSun, SignalArchitect`. The binder removes `SkinCard_SignalArchitect` for players without DevAccess.

**`Price` values:** `EQUIP`, `EQUIPPED`, `UNLOCK`, `NEED TOKENS`, `LOCKED`, `BUY`, `CHECKING PRICE`, `UNAVAILABLE`, `SAVING...`.

**`Meta` values:** `OWNED`, `25 TOKENS`, `300 TOKENS · n/100 CLEARS`, `R$ n`, `PRICE UNAVAILABLE`, `DEVELOPER ONLY`.

### 6.5 DONATE tab (`Page_Donate`)

```
Page_Donate > SupportTotal (dyn "RECORDED SUPPORT n R$"), SupportBreakdown (dyn), SupportNote (static)
            > Donate_scroll | Donate_grid > Donate_<DonationKey> > Name_txt, OwnedBadge (20K only),
                                            Buy_button > Price (dyn "R$ n" | "OWNED" | "COMING SOON"), PriceLabel ("DONATE" | "ONE-TIME")
```

`<DonationKey>` ∈ `DonationSignal, DonationSupply, DonationField, DonationResearch, DonationCommand, DonationDirector, Donation5000, Donation10000, Donation20K`. The prefix appears twice (as in `Donate_DonationSignal`); that is deliberate, because the key is the real Config key that UIRegression's `Fit.DonationTierKeys` uses.

### 6.6 COLORS tab (`Page_Colors`)

```
Page_Colors > Picker_Hazmat | Picker_Glowstick
  Picker_<P> > Title, Swatch (dyn colour), Slider_H | Slider_S | Slider_V > Track (keeps a UIGradient; dyn), Knob (dyn),
               Save_button, Lock_panel (dyn Visible) > LockText (static), GetPass_button
```

`Picker_Hazmat` maps to `SetHazmatColor` and the lock `OwnsAdvancedEquipment`. `Picker_Glowstick` maps to `SetGlowstickColor` and the lock `OwnsCosmeticEquipment`. The Track and Knob must be plain Frames, so the binder handles dragging.

### 6.7 Purchase-state overlays (prototype and in game)

Per-button state lives in `Price` (above). The global result is shown in `Footer > Status` plus the optional `Toast`. Do not design an in-game "Confirm purchase" dialog before Robux prompts: Roblox's prompt is the confirmation. A "Waiting for Roblox…" state is the button's `WAITING` caption, not a separate overlay.

### 6.8 Other lobby surfaces (phase 2 restyle): use the EXISTING instance names

UIRegression, the tests and the scripts find these surfaces by these names. Add only a Framewisp tag suffix.

| Surface | Names |
|---|---|
| Rail | `ZyntraShopButton`, `ZyntraOpenButton` (UPGRADES), `ZyntraRewardsButton`, `ZyntraWheelButton`, `ZyntraMusicButton`, each `> SectionButtonContent > <Shop\|Upgrades\|Rewards\|Wheel\|Music>Icon, SectionCaption`, plus `NotificationDot > DotRing` |
| Daily Rewards | `DailyRewardsPanel > RewardsHeader > HeaderGift, HeaderTitle; CloseButton; PageContent; StatusLine`. Page: `ResetCountdown, PlaytimeReadout, ProgressTrack > Fill, ProgressCaption, Milestone5 / Milestone15 / Milestone35 > Threshold, RewardIcon, RewardName, ClaimButton, ClaimedCheck > CheckMark, ClaimedLabel; PlaytimeNote; ResearchHeading; ResearchFuse / ResearchLever / ResearchClear` |
| Lucky Wheel | `LuckyWheelGui > WheelShade > WheelHolder > WheelDisc, WheelPointer, HubButton, CloseButton, FieldLabel1..6, FieldOdds1..6`. Field order follows `Config.DailyRewards.Wheel`: Token1, Token3, Potion1, Potion2, Shield1, Skin5. |
| Re-entry modal | `ZyntraReentryModal > InputShield, EmergencyReentry > (title, info), ReentryFreeRespawn (dev), ReentryDecline`. The use/buy button is unnamed today; name it `ReentryUse` in Figma. |
| PARTY DOWN | `PartyDownOverlay > PartyDownCard > PartyDownTitle, PartyDownFallen, PartyDownTrack > PartyDownFill, PartyDownTimer, PartyDownReentry, PartyDownFreeRespawn, PartyDownDecline` |
| Wall card | `ZyntraShopDisplayCard > ShopDetailCard > ItemIcon, ItemMonogram, ShopTitle, ItemName, ItemKind, ItemDescription, ItemState, Buy, Close, CloseHint` |
| Friend chip | `FriendBoostGui > FriendBoostChip > BoostLabel, FriendsLabel, InviteButton` |

---

## 7. Open owner decisions

1. **Tap floor for the Framewisp window.** Either keep 44 logical px (buttons ≥ 122 artboard px, or ≥ 144 under the top inset), or accept about 35 px for 96 px buttons. Today's specs use 96-128 px.
2. **Where SETTINGS and RECORDS live** in the new window. Proposed: header buttons into the legacy terminal. Alternative: new designs.
3. **Upgrades with too few tokens.** Keep today's "always pressable, the server refuses", or turn the button into "GET TOKENS", which jumps to `Section_Tokens`.
4. **Which phase-2 surfaces** (6.8) get restyled, and whether in code or as Framewisp shells.
5. **Unowned-state checks in Studio.** Flip `Config.Studio.GrantAllPasses` temporarily, or rely on the offline harness plus a published dev server.
6. **Flat art** for Entity Shield, Stamina and Battery. None exists in the `product-*` family.
7. **Token Earner passes stay off sale until QA.** The designs show the on-sale state, while the game shows `UNAVAILABLE` until then.
8. **Price format.** The new UI uses `R$ 149`. The wall card, re-entry modal and PARTY DOWN keep `149 R$` until they are restyled.
