# L4 Bento Home in Roblox: build plan

Date: 2026-10-05. Plan only: no Studio, Figma, git or `.lua` edits were made while writing it.

## What this plan covers

It turns the owner's chosen layout, **L4 Bento Home**, into the shop that ships. The layout lives in Figma file `7FXycGKH6OT6Lme6FV3VBc`, page `35:2`, section `35:3`. The plan runs the design through Framewisp, Roblox Studio and three new client scripts.

**Inputs:**
- `INTEGRATION-CONTRACT.md` (all of it; section numbers below are written "contract §n");
- `OWNER-DECISIONS.md`, `STYLE-GUIDE.md`, `DESIGN-SYSTEM.json`, `REVISION-ART.json`, `FIGMA-IDS.json`, `workflow-result-revision-1.json`;
- the Figma AI art in `figma-images-v2.json` (`*-v3-ai`);
- the current code: ZyntraStore, ZyntraConfig (the Studio copy), ZyntraMonetization, ZyntraSkins, ZyntraSkinsPage, Lucky Wheel Client, Daily Rewards Client, UIDevice, UIRegression and ProtectionClient.

## 0. Decisions this plan makes, in one place

1. **ZyntraMonetization, ZyntraConfig and every server script stay untouched.** The new UI uses only:
   - the existing remotes (`ZyntraGetProfile`, `ZyntraProfileChanged`, `ZyntraAction`);
   - MarketplaceService;
   - `ProtectionClient`.

   No new remote, server attribute or DataStore field is added, so old and new client builds can share a server.
2. **The shop window is new code**: `"Zyntra Shop L4"`, with modules `ShopData` and `ShopBinder`. It replaces the legacy terminal's five shop tabs (UPGRADES, SHOP, SKINS, DONATE, COLORS) only while the flag is on.
3. **The rail, wheel and daily rewards keep their owners and their logic.** L4 *skins* them in place by grafting the Framewisp art onto their existing, test-pinned instances (contract §6.8).
   - Lucky Wheel Client, Daily Rewards Client and the ZyntraStore rail are **not edited**.
   - Their tests and UIRegression's rail rows keep passing.
   - The skin is runtime-only, so turning the flag off and rejoining removes it.
4. **One small ZyntraStore edit, with two hunks** (§2.6): a routing hook in `openKioskShop` and in the UPGRADES rail handler. It is inert when the L4 script is absent.
5. **Legacy stays alive.** It handles RECORDS, SETTINGS, DEV, the in-round dev phone, the re-entry modal, the wall card's `ZyntraShopBuy` bridge and the per-player fallback when binding fails.
6. **Flag:** `workspace:GetAttribute("ShopUIVersion")`.
   - `nil`, or anything else: legacy.
   - `"L4-dev"`: only DevAccess players get L4.
   - `"L4"`: everyone gets it.
7. **Price format:** `R$ 149`, with comma thousands (`R$ 10,000`). This is owner decision 7.8 for the new surfaces.
8. **Tokens short:** the L4 design greys the button and shows `NEED n MORE` (frames 46:13293 and 48:11913). L4 follows the design, and the server still refuses on its own. This closes contract decision 7.3 for L4 only; legacy is unchanged.
9. **Skin preview:** phase 1 uses the 2D `PreviewImageId` in the preview panel. The 3D ViewportFrame from ZyntraSkinsPage is a later add.

   `ponytail:` the 2D preview only. Port `loadPreview`/`frameCamera` if the owner wants rotation.

**Stays on old code for now:**
- PARTY DOWN (RoundUI is at the 200-register limit);
- the Emergency Re-entry death modal (ZyntraStore);
- the lobby wall card (Shop Display Client);
- the Friend Boost chip;
- the rewards intro card;
- RECORDS, SETTINGS and DEV;
- the in-round dev phone.

The re-entry modal and the wall card get skins in phase 5 (§1.5).

---

## 1. Framewisp export structure

### 1.0 Rules for every export frame

**Page.** The rules apply to the new Figma page **"L4 · Roblox export"**. It is a *build* page, not a presentation page: overlapping hidden layers are fine there. Claude builds it in the next Figma run (§1.7). The presentation frames on page 35:2 stay as they are.

**Frames.**
- One top-level frame per conversion, at 1920x1080, named exactly as in §1.6.
- Mockup layers are tagged `_ignore`, and Framewisp skips them.

**Names.**
- Names follow contract §6 with the real ZyntraConfig keys.
- Framewisp tags are appended to the base name: `_button`, `_close`, `_panel`, `_tabgroup`, `_tab:<Name>`, `_scroll`, `_grid`, `_list`, `_txt`, `_shadow`, `_image`, `_ignore`.
- **The binder matches a name with or without its trailing tags** (§2.2). Write the base names below; the tag in brackets is what the Figma layer adds.
- Names are unique inside a card. Never name a node after a GuiObject property (`Name`, `Text`, `Image`, `Size`, `Visible` and so on): use `Name_txt`.

**Images.**
- **One shared placeholder image** fills every slot the game re-points at runtime:
  - `ProductIcon` (product art, from Config `IconId`);
  - `SkinArt` and `PreviewArt` (skin art, from `ZyntraSkins.ById[id].PreviewImageId`);
  - `RewardIcon` and `HeaderGift`;
  - `LockArt` (the pass's `IconId`).

  The placeholder is a neutral 64x64 #161D20 PNG, uploaded once with `upload_assets`. If that fails, reuse the hidden product `product-tokens-4` hash `bda4dd60…`. A slot is one distinct image however often it repeats.
- **New Figma AI raster art** that has no Roblox id yet (the `*-v3-ai` keys) goes in as real IMAGE fills and counts against the budget. On import, Framewisp uploads it. Claude then reads the resulting `rbxassetid` from the scratch tree and writes it into `figma-images-v2.json` (`robloxAssetId`).

**What may bake.** Only nodes tagged `_image` (the wheel disc and the wheel pointer) and the AI rasters. Everything else must be native:
- the token glyph (chip plus bar), the SKINS, DONATE and COLORS dock glyphs;
- the Records icon (three bars), the Settings icon (two bars and two circles) and the padlock (rounded rect plus ring);
- badges, dots and the hue track (a linear multi-stop gradient, which becomes a UIGradient);
- `VectorVersion_ignore` inside the disc component is skipped.

Anything else that bakes is a bug in the export page.

**Floors, in artboard px.** These apply to the window that is fit, not the whole 1920 artboard; see §2.4.
- **Tap targets ≥ 122** in height: every `*_button`, `*_close`, tab and slider track hit area. The target is **136** wherever it fits, because a 58 px top inset needs about 135 to keep UIRegression's 44 px floor on an 844x390 phone.
- **Text ≥ 30.** The STYLE-GUIDE floor is already 30.
- This means the L4 export frames raise:
  - card BuySlots: 112 → 122;
  - dock items: 96 → 122;
  - AddTokens and Close: 96/112 → 122 (the TokenPill grows from 112 to 138, and the header from 136 to about 160);
  - Records and Settings: 122.
- Product art shrinks to fit. Colour preset swatches stay only if they fit at 122. Otherwise they are dropped and the sliders remain the way to pick a colour.

**Pages are siblings.** Only `Page_Shop` is visible in Figma. If the first scratch import shows that Framewisp drops hidden layers, make all five visible and stacked: the controller hides all but the active page. That needs one more conversion of `ZyntraShop_L4`.

**Interactive behaviour.** None comes from Framewisp; our code wires every node. The controller deletes every `LuaSourceContainer` and every `*_ignore` node from each clone (contract risk 1).

**Where the imports go.** Imports land in a **scratch Baseplate first** (the owner, §5). Claude dumps the tree, adapts the binder and test fixture, then transplants the tree into the real place in this session's Studio slot as `ReplicatedStorage.ZyntraShopUI.<FrameName>`, a Folder with no StarterGui copy. The transplant uses a `SerializationService` `.rbxm` (memory `mongotv-studio-native-export`). The fallback is the owner re-importing the same code.

### 1.1 Conversion 1: `ZyntraShop_L4` (priority 1)

**Sources.**

| Layer | Source frame |
|---|---|
| Shell | `L4 / Shop` 44:2943 (after revision 1) |
| `Page_Upgrades` | 46:12520 |
| `Page_Skins` | 48:11913 |
| `Page_Donate` | 48:12797 (5 tiers) |
| `Page_Colors` | 49:7400 |
| `Pending` | the `L4 / Toast · Waiting for Roblox` card 49:14489 |
| `Toast` | 49:14495 |

**Layer tree.** "(dyn)" marks a slot the binder writes. Everything else is static design copy.

```
ZyntraShop_L4                                 1920x1080 artboard
├ Backdrop_ignore
├ Dim                                         INK 50%. Controller: full screen, Active (input shield)
├ WindowShadow [_shadow]
└ ShopWindow [_panel]                         1760x1016. Controller re-parents it into the ModalViewport fit
  ├ Header
  │ ├ TitleBlock > Eyebrow, Title, TitleBar
  │ ├ Records [_button] > RecordsIcon         native 3 bars. Opens legacy RECORDS
  │ ├ Settings [_button] > SettingsIcon       native. Opens legacy SETTINGS
  │ ├ TokenPill > TokenGlyph (TokenChip, TokenBar), TokenCount (dyn: Tokens | "--"), TokenLabel,
  │ │             AddTokens [_button] > Plus
  │ ├ CloseSlot > CloseShadow [_shadow], Close [_button_close] > CloseGlyph
  │ └ HeaderRule
  ├ Pages
  │ ├ Page_Shop          (visible)
  │ ├ Page_Upgrades      (hidden)
  │ ├ Page_Skins         (hidden)
  │ ├ Page_Donate        (hidden)
  │ └ Page_Colors        (hidden)
  ├ Footer > Status (dyn: last push message, else the tab hint)
  ├ Categories [_tabgroup]                    bottom dock
  │ └ Tab_Upgrades [_tab:Upgrades], Tab_Shop [_tab:Shop], Tab_Skins [_tab:Skins],
  │   Tab_Donate [_tab:Donate], Tab_Colors [_tab:Colors]
  │     each > CategoryIcon, Label, ActiveBar (dyn Visible)
  ├ Pending [_panel] (hidden) > PendingTitle "WAITING FOR ROBLOX…", PendingText (dyn)
  └ Toast (hidden) > ToastAccent (dyn colour by tone), ToastText (dyn)
```

`Page_Shop`. Its scroll runs horizontally (owner decision for L4):

```
Page_Shop > Products [_scroll] > Content [_list]
  Card_ExpeditionPack  > Art > ProductIcon (dyn img), Ribbon > RibbonText "FEATURED BUNDLE"
                         Name_txt, Benefit_txt, Contents [_list] > ContentRow_1..3 > Count, Label   (static)
                         BuySlot > BuyShadow [_shadow], Buy [_button] > Price (dyn "BUY · R$ 69")
  Card_Supporter       > Art > ProductIcon (dyn), OwnedBadge > BadgeText (dyn)
                         Name_txt, Benefit_txt, BuySlot > BuyShadow, Buy > Price (dyn)
  Card_AdvancedEquipment   (same; Hook "FOCUS BEAM")
  Card_EntityDetector      (same; Hook "THREAT SCANNER")
  Card_TokenEarner2x       (same; Hook (dyn): "DOUBLE TOKENS" | "TOKEN EARNER 2x/3x/5x ACTIVE")
  Card_Tokens20            (same + Ribbon "BEST VALUE")
```

`Page_Upgrades`:

```
Page_Upgrades
  Upgrade_Stamina   > Art > UpgradeIcon (AI image upgrade-stamina-v3-ai), Eyebrow, Name_txt, Benefit_txt,
                      Percent (dyn "+15%"), LevelReadout (dyn "LEVEL 3"),
                      BuySlot > BuyShadow, Buy > PriceLabel "+5% •", TokenGlyph (dyn Visible), Price (dyn)
  Upgrade_Battery   (same; AI image upgrade-battery-v3-ai)
  Card_EntityShield > Art > UpgradeIcon (AI upgrade-entity-shield-v3-ai), Eyebrow, Name_txt, Percent "5s",
                      StoredCount (dyn "OWNED n"), BuySlot > BuyShadow, Buy > TokenGlyph, Price (dyn)
  Card_SpeedPotion  > Art > ProductIcon (dyn), Eyebrow, Name_txt, Percent "+30%", StoredCount (dyn "n STORED"), BuySlot…
  Card_RouteMarker  > Art > ProductIcon (dyn), Eyebrow, Name_txt, Percent "x3",  StoredCount (dyn "n MARKERS"), BuySlot…
```

`Page_Skins`:

```
Page_Skins
  SkinPreview [_panel] > Eyebrow "HAZMAT SKINS", PreviewArt (dyn img), PreviewName (dyn), PreviewStatus (dyn), PreviewHint
  Skins [_grid] > SkinCard_BaselineYellow, SkinCard_PoolService, SkinCard_SuburbSurvey,
                  SkinCard_BlacksiteDirector, SkinCard_StaticWraith, SkinCard_FalseSun
     each > SkinArt (dyn img), Name_txt, Meta (dyn), EquippedBadge > BadgeText (dyn),
            BuySlot > BuyShadow, Buy > TokenGlyph (dyn Visible), Price (dyn)
```

`SkinCard_SignalArchitect` is not in the design. Developers equip it through legacy SKINS (RECORDS/SETTINGS path), which is acceptable.

`Page_Donate`:

```
Page_Donate
  Support [_panel] > SupportIcon, Eyebrow "THANK YOU", Thanks_txt, SupportTotal (dyn), SupportBreakdown (dyn),
                     Support20K (dyn Visible: ZyntraOwnsDonation20K), SupportNote
  Tiers [_grid] > Donate_DonationSignal, Donate_DonationSupply, Donate_DonationResearch,
                  Donate_DonationDirector, Donate_Donation10000
     each > TierIcon (native), TierLabel "TIER n", Name_txt, BuySlot > BuyShadow, Buy > PriceLabel "DONATE", Price (dyn)
```

`Page_Colors`. The two pickers are identical; the lock target differs:

```
Page_Colors
  Picker_Hazmat > Title, Subtitle (dyn "ADVANCED EQUIPMENT · OWNED"), Swatch (dyn colour),
                  Slider_H > Track (UIGradient, static rainbow), Knob (dyn), Value (dyn "46°")
                  Slider_S > Track (UIGradient dyn), Knob, Value (dyn "72%")
                  Slider_V > Track (UIGradient dyn), Knob, Value (dyn "89%")
                  Presets [_list] > Preset_1..6   (only if they fit at ≥122; colour = authored fill)
                  SaveSlot > SaveShadow [_shadow], Save [_button] > SaveText (dyn "SAVE COLOR" | "SAVING...")
                  Lock [_panel] (dyn Visible; Active) > LockArt (dyn img), LockIcon (native), LockText, LockBody_txt,
                        BuySlot > BuyShadow, GetPass [_button] > Price (dyn "BUY · R$ 149")
  Picker_Glowstick (same; lock = CosmeticEquipment, "GLOWSTICK CUSTOMIZER REQUIRED")
```

Track and Knob are plain Frames. The Track gets a transparent hit area at least 122 tall, and dragging is done in code.

**Binding keys (real ZyntraConfig).** The ids are read from Config at runtime and never hard-coded; the values are listed for QA.

| Layer | Config | Kind |
|---|---|---|
| `Card_ExpeditionPack` | `Products.ExpeditionPack` (3713829859) | product |
| `Card_Supporter` | `Passes.Supporter` (1941938256) | pass |
| `Card_AdvancedEquipment` | `Passes.AdvancedEquipment` (1945402536) | pass |
| `Card_EntityDetector` | `Passes.EntityDetector` (1982715834) | pass |
| `Card_TokenEarner2x` | `TokenEarner.Passes.TokenEarner2x` (1995218405) | pass, verified `IsForSale` |
| `Card_Tokens20` | `Products.Tokens20` (3707755233) | product |
| `Upgrade_Stamina` / `Upgrade_Battery` | `UpgradeCost(level)`, `StaminaLevel/Percent`, `BatteryLevel/Percent` | token action |
| `Card_EntityShield` | `ProtectionItem` (TokenCost 5) | ProtectionClient |
| `Card_SpeedPotion` / `Card_RouteMarker` | `Items.SpeedPotion` (3 tokens), `Items.RouteMarker` (2) | token action |
| `SkinCard_<id>` | `ZyntraSkins.ById[id]` (Kind Free/Tokens/Robux) | equip / token / verified pass |
| `Donate_<key>` | `Donations.DonationSignal/Supply/Research/Director/Donation10000` | product |
| `Picker_Hazmat` / `Picker_Glowstick` | `HazmatColor` / `GlowstickColor`; locks `OwnsAdvancedEquipment` / `OwnsCosmeticEquipment` | colour action / pass |

Hidden keys have no card, so the binder reports them as "not sold in this layout":
- `CosmeticEquipment` (sold only in COLORS);
- `EmergencyReentry` (sold only by the death modal, PARTY DOWN and Expedition Pack);
- `Tokens4`;
- `TokenEarner3x` / `TokenEarner5x` and the upgrade passes;
- `DonationField`, `DonationCommand`, `Donation5000`, `Donation20K`.

**Image budget, worst case 9 of 15:**

| Images | Count |
|---|---:|
| Shared placeholder | 1 |
| `upgrade-stamina/battery/entity-shield-v3-ai` | 3 |
| Dock tiles `rail-shop-v3-ai`, `rail-upgrades-v3-ai` (same art as the rail) | 2 |
| Records, Settings and padlock icons, *only if they fail to stay native* | ≤ 3 |

### 1.2 Conversion 2: `LobbyRail_L4` (priority 2)

**Source:** `Nav/LobbyButton` 80:2155 (Default state), its Badge, and the TokenPill from the DS. Instances are named after the **legacy** buttons, so the skin maps by name:

```
LobbyRail_L4                                  1920x1080
├ Backdrop_ignore
├ Rail [_list]
│ ├ ZyntraShopButton [_button]    > FaceShadow [_shadow], Face > Icon (AI rail-shop-v3-ai),     PlateShadow [_shadow], Plate > Label "SHOP"
│ ├ ZyntraOpenButton [_button]    > …                       Icon (rail-upgrades-v3-ai), Label "UPGRADES"
│ ├ ZyntraRewardsButton [_button] > …                       Icon (rail-rewards-v3-ai),  Label "REWARDS"
│ ├ ZyntraWheelButton [_button]   > …                       Icon (rail-wheel-v3-ai),    Label "WHEEL"
│ └ ZyntraMusicButton [_button]   > …                       Icon (rail-music-v3-ai),    Label "MUSIC"
└ TokenPill > TokenGlyph, TokenCount (dyn), TokenLabel, AddTokens [_button] > Plus
```

- **Hover and Pressed** are code-driven (§2.4), so only the Default variant is exported.
- **The NotificationDot stays legacy**: ZyntraStore owns its `Visible`, and it is already coral.
- **Images:** 5 (the AI rail icons). Everything else is native.
- **Floor:** the face is 168 ≥ 122. The plate label is 30 px.

### 1.3 Conversion 3: `LuckyWheel_L4` (priority 3)

**Source:** `L4 / Lucky Wheel` 52:2568 after the v3 art (disc 78:1449 with the AI `DiscArt` fill, pointer 78:1454). The names follow the legacy wheel (contract §6.8):

```
LuckyWheel_L4                                 1920x1080
├ Backdrop_ignore
├ TitleBlock > Eyebrow "ZYNTRA // DAILY SPIN", Title "LUCKY WHEEL", TitleBar
├ TokenPill (as in §1.1)
├ CloseSlot > CloseShadow [_shadow], CloseButton [_close]
├ Wheel
│ ├ WheelDisc [_image]      the "Art/Wheel Disc v3_image" instance (AI DiscArt; VectorVersion_ignore inside)
│ ├ WheelPointer [_image]   the "Art/Wheel Pointer_image" instance
│ └ HubSlot > HubShadow [_shadow], HubButton [_button] > HubText
└ Odds [_panel] > Title "PRIZES & ODDS", Subtitle, OddsRow_Token1 … OddsRow_Skin5 > OddsLabel, OddsValue (dyn),
                  Today > TodayTitle, TodayText
```

- **Images:** 2 (the disc and the pointer).
- **Disc geometry is checked before upload** (§4.3): field 1 sits at 12 o'clock, followed clockwise by Token3, Potion1, Potion2, Shield1, Skin5, in 60° fields. This is what Lucky Wheel Client's rotation maths assumes.
- **Odds** come from the server weights 40/20/20/5/10/5 (`Config.DailyRewards.Wheel[i].Weight`), never from the static design text.

### 1.4 Conversion 4: `DailyRewards_L4` (priority 4)

**Source:** `L4 / Daily Rewards` 52:2164. The names are the legacy ones:

```
DailyRewards_L4                               1920x1080
├ Backdrop_ignore
└ DailyRewardsPanel [_panel]
  ├ RewardsHeader > HeaderGift (placeholder), HeaderTitle, TokenPill, CloseButton [_close]
  ├ PageContent > CountdownStrip > ResetCountdown; PlayStrip > PlaytimeReadout; ProgressTrack > Fill; ProgressCaption;
  │              Milestone5 | Milestone15 | Milestone35 > Threshold, RewardIcon (placeholder), RewardName,
  │                                                      ClaimButton [_button], ClaimedLabel;
  │              ResearchHeading; ResearchFuse | ResearchLever | ResearchClear
  └ StatusLine
```

- **Images:** 1 (the placeholder). The live page sets its own reward art.
- **WheelLink** (the "LUCKY WHEEL · SPIN" row) is **not exported**. Daily Rewards has no close API that the wheel could open after, and the rail already has WHEEL. This is an owner question.

### 1.5 Later (phase 5)

- **`ReentryModal_L4`**, from 45:7652: `ZyntraReentryModal > InputShield, EmergencyReentry, ReentryUse, ReentryFreeRespawn, ReentryDecline`, with 1 placeholder image.
- **`ShopWallCard_L4`**, from 39:1245: `ZyntraShopDisplayCard > ShopDetailCard > ItemIcon, ItemName, ItemKind, ItemDescription, ItemState, Buy, Close`, with 1 placeholder image.
- Both are skinned the same way as §2.4.4.
- **PARTY DOWN is not converted**: RoundUI's register limit, and its round HUD timing. The Friend chip and the intro card are not converted either.

### 1.6 Conversion schedule (free plan: 5 a day, 15 images each)

| # | Frame | Images (worst case) | Day |
|---|---|---:|---|
| 1 | `ZyntraShop_L4` | 9 | 1 |
| 2 | `LobbyRail_L4` | 5 | 1 |
| 3 | `LuckyWheel_L4` | 2 | 1 |
| – | spare: re-convert `ZyntraShop_L4` after a Figma fix (for example if hidden pages are dropped) | – | 1 |
| 4 | `DailyRewards_L4` | 1 | 1 or 2 |
| 5 | `ReentryModal_L4`, `ShopWallCard_L4` | 1 + 1 | later |

### 1.7 Building the export page in Figma (Claude, next Figma run; about 6 `use_figma` calls)

1. Create the page "L4 · Roblox export".
2. **`ZyntraShop_L4`:**
   - Duplicate 44:2943 into the new frame.
   - Add `Pages` and move the scroll into `Page_Shop`.
   - Copy the page bodies of 46:12520, 48:11913, 48:12797 and 49:7400 in as hidden `Page_*`.
   - Add `Pending` (from 49:14489) and `Toast` (from 49:14495), hidden.
   - Add `Records_button` and `Settings_button` names.
   - Rename every node to §1.1.
   - Swap every product, skin and supply image to the placeholder.
   - Raise the tap floors (§1.0).
   - Check that nothing but the AI art and `_image` nodes is a vector.
3. **`LobbyRail_L4`:** 5 `Nav/LobbyButton` instances (Default), renamed to the legacy names, plus a TokenPill.
4. **`LuckyWheel_L4`:** duplicate 52:2568 (Ready), rename to §1.3, and make sure the disc instance is the v3 component.
5. **`DailyRewards_L4`:** duplicate 52:2164 and rename to §1.4.
6. **Audit and screenshot**, inside the last call:
   - the distinct image hashes per frame;
   - texts under 30 px;
   - buttons under 122 px;
   - names that fail the §2.2 strip.

   Return the frame ids and write them into `FIGMA-IDS.json` under `layouts.L4.export`.

---

## 2. Controller architecture

### 2.1 Files (Studio first, then mirrored)

| Studio path | Mirror path | Class |
|---|---|---|
| `ReplicatedStorage.ZyntraShopUI` | (Folder; it holds the 4 templates and the 2 modules) | Folder |
| `ReplicatedStorage.ZyntraShopUI.ShopBinder` | `ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua` | ModuleScript |
| `ReplicatedStorage.ZyntraShopUI.ShopData` | `ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua` | ModuleScript |
| `StarterPlayer.StarterPlayerScripts."Zyntra Shop L4"` | `StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua` | LocalScript |

Drafts are written to `artifacts/shop-ui-figma-20261005/roblox-draft/` under the same relative paths. The full file list is in the summary at the end.

### 2.2 `ShopBinder` (ModuleScript; no state, no remotes)

`Binder.base(name)`:
1. Strips a trailing `_tab[:_]<X>` once.
2. Then repeatedly strips a trailing `_<tag>` while the tag is in `{button, close, panel, tabgroup, scroll, grid, list, txt, shadow, image, ignore, aspect, fit}`.

Examples: `Close_button_close` → `Close`, `Tab_Shop_tab:Shop` → `Tab_Shop`, `Products_scroll` → `Products`, `Donate_Donation10000` → unchanged.

**Lookup:**
- `Binder.find(root, base)` returns the first descendant whose `base(Name) == base`, in preorder.
- `Binder.all(root, prefix)` returns `{[suffix] = node}` for `Card_`, `SkinCard_`, `Donate_`, `Tab_`, `Page_`, `OddsRow_` and `Preset_`.
- Cards are searched inside the card only (contract §6.0 rule 4).

**Class tolerance:**
- `Binder.button(node)` returns `node` if it is a GuiButton (setting `AutoButtonColor = false`). Otherwise it adds a child TextButton `Hit`: size (1,1), `Text = ""`, transparent, ZIndex above the node's deepest child, `Selectable = true`. It returns that child. Idempotent.
- `Binder.text(node)` returns a node with `.Text` (itself, or its first TextLabel descendant).
- `Binder.image(node)` returns an ImageLabel or ImageButton (itself, or its first ImageLabel descendant, or a new full-size ImageLabel).

**Visual helpers:**
- `Binder.press(button, face, shadow)`: on press (MouseButton1 or Touch `InputBegan`) the face moves down by the shadow's authored offset and the shadow hides. On `InputEnded` or `MouseLeave` both are restored. The original Position is stored once as attribute `BinderRestY`.
- `Binder.style(buttonNode, state)` applies the STYLE-GUIDE palette per state:
  - `robux`: AMBER face, #9C6410 stroke, TILE text, shadow on;
  - `token`: ICON TEAL face, #2D7774 stroke;
  - `owned`: #10292A face, RAIL TEAL stroke and text, shadow off;
  - `off`: TILE_HI face, LINE stroke, SAGE text, shadow off;
  - `equip`: CREAM face.

  It writes only `BackgroundColor3`, the node's `UIStroke` colour, `Price`/`PriceLabel` `TextColor3` and the sibling `*_shadow` `Visible`.

**Template helpers:**
- `Binder.strip(clone)` destroys every `LuaSourceContainer` and every node whose raw name ends in `_ignore`.
- `Binder.rescale(root, designHeight)` is **used only if the scratch import shows pixel units**. It stores the authored `TextSize` (non-scaled text), `UIStroke.Thickness`, `UICorner` offset and `UIPadding`/`UIListLayout` offsets as attributes. On `root.AbsoluteSize` change it multiplies each by `AbsoluteSize.Y / designHeight`. `TextScaled` nodes are left alone (the 100 px cap only limits growth).

**Skinning:**
- `Binder.skin(liveRoot, templateRoot, map)` runs an explicit per-surface map of entries `{from = base, to = liveName, props = {...}}`, `{hide = {liveName...}}` and `{graft = base, into = liveName, size = UDim2, pos = UDim2}`.
- It copies only the listed properties, plus `UIStroke`/`UICorner` children when `props` includes `"Stroke"`/`"Corner"`. Grafted clones are named `L4Skin_<base>`, which makes the operation idempotent.
- It returns the list of names it could not find. The caller warns and skips the surface; it never errors.

### 2.3 `ShopData` (ModuleScript; one instance per client, started by the LocalScript)

**State:**
- `profile` (the last public profile, or nil);
- `prices[id] = {state = "pending" | "live" | "off", price}`;
- `pending[key] = {kind, serial}`;
- `promptOpen` (key | nil).

**Gate:**
- `ShopData.ready()` is `profile ~= nil and player:GetAttribute("ZyntraProfileLoaded") == true`.
- Until it holds:
  - every Buy shows `LOADING` (disabled);
  - TokenCount shows `--`;
  - `purchase()` returns without calling anything (contract risk 3).
- **Start:**
  - `pcall(getProfile.InvokeServer, getProfile)` in a `task.spawn`. It can return nil after 10 s.
  - Retry once when `ZyntraProfileLoaded` turns true while `profile` is still nil, and accept every `ZyntraProfileChanged`.

**Ownership** (each returns `true`, `false`, or `nil` for unknown before ready):
- `owns(passKey)` is `profile["Owns"..key] == true or player:GetAttribute("ZyntraOwns"..key) == true`, for Supporter, AdvancedEquipment, EntityDetector and CosmeticEquipment. The attribute flips first after a purchase.
- `earnerTier()` is `Config.TokenEarner.Tier(owns)`, built from the six `ZyntraOwns<TokenEarner2x|3x|5x|Up2to3|Up3to5|Up2to5>` attributes. **3x and 5x owners keep their tier.** The 2x card reads OWNED, with `Hook`/badge `TOKEN EARNER 5x ACTIVE` (or 3x/2x).
- `skinState(id)` uses `profile.Skins.Owned/Equipped`, plus `ZyntraOwns<SkinId>` for StaticWraith and FalseSun.
- `owns20K()` reads `ZyntraOwnsDonation20K`; it only shows `Support20K`.

**Prices** (`fetchPrices()` runs on first open, once per session, one `task.spawn` + `pcall(GetProductInfo)` per id):

| What | InfoType | Shows | Fallback |
|---|---|---|---|
| Passes: Supporter, AdvancedEquipment, EntityDetector, CosmeticEquipment | GamePass | `PriceInRobux` | Config `Price` |
| Products: ExpeditionPack, Tokens20, the 5 donations | Product | `PriceInRobux` | Config `Price` |
| **Verified only:** TokenEarner2x, StaticWraith, FalseSun | GamePass | price only if `IsForSale == true`, `TargetId == id` and a positive integer `PriceInRobux` | `CHECKING PRICE` while pending, else `UNAVAILABLE` |

This is legacy `verifiedEarnerPrice` / `allowedRobuxPass`, re-implemented in about 6 lines. Today the earner card reads UNAVAILABLE until the owner puts 2x on sale (§5).

**The one dispatcher, `ShopData.purchase(key, arg)`.** Every L4 button goes through it. Nothing else prompts or fires.

| Key | Guard | Call | Pending until |
|---|---|---|---|
| `Supporter`, `AdvancedEquipment`, `EntityDetector`, `CosmeticEquipment` | ready, not owned, no `promptOpen` | `MarketplaceService:PromptGamePassPurchase(player, Config.Passes[key].Id)` | `PromptGamePassPurchaseFinished(plr, id, wasPurchased)`, else 30 s |
| `TokenEarner2x` | ready, `earnerTier() < 2`, verified on sale | `PromptGamePassPurchase(player, Config.TokenEarner.Passes.TokenEarner2x.Id)`. Only the 2x id: no upgrade offers. The same script renders and prompts (risk 9). | same |
| `ExpeditionPack`, `Tokens20` | ready, no `promptOpen` | `PromptProductPurchase(player, Config.Products[key].Id)` | `PromptProductPurchaseFinished(userId, id, isPurchased)`, else 30 s |
| `DonationSignal`, `DonationSupply`, `DonationResearch`, `DonationDirector`, `Donation10000` | same | `PromptProductPurchase(player, Config.Donations[key].Id)` | same |
| `Stamina` / `Battery` | ready | `ZyntraAction:FireServer("UpgradeStamina" / "UpgradeBattery")` | the next `ZyntraProfileChanged`, else 6 s |
| `SpeedPotion` / `RouteMarker` | ready | `FireServer("BuyItem", {Key = key})` | same |
| `EntityShield` | ready, `GetState().Available` | `GetState().Pending and ProtectionClient.Retry() or ProtectionClient.Request("BuyProtection")` | ProtectionClient's own `Pending`/`ServerPending`/`CanRetry` (render from `GetState()` on `ProtectionClient.Changed`) |
| `Skin`, arg = skinId | ready | owned and not equipped: `FireServer("EquipSkin", id)`. Kind Tokens and not owned: `FireServer("BuySkin", id)`. Kind Robux, verified, not owned: `PromptGamePassPurchase(player, Skins.ById[id].PassId)` | push, 6 s / Finished, 30 s |
| `Color`, arg = `{Picker = "Hazmat" | "Glowstick", Color = Color3}` | ready, the picker's pass owned | `FireServer("Set"..Picker.."Color", Color3)` | push, 6 s |

Notes on pending:
- **Price text while pending:** `WAITING` on the pressed Robux button, and every other Robux button is disabled while `promptOpen` is set. Token buttons read `SAVING...`.
- **After `isPurchased == true` on a product,** a 15 s timer starts. If no `ZyntraProfileChanged` lands in that time, the toast reads `Processing, it will arrive shortly.` (info). A receipt the server returned `NotProcessedYet` for is retried later by Roblox.
- **After `wasPurchased == true` on a pass,** the success toast `<Name> is yours.` fires when `ZyntraOwns<Key>` turns true. There is no server message for most passes.
- **Cancel** (`false`) restores the button with no toast. A cancel is not an error.

**Timeouts.** The constants live at the top of ShopData:

| Constant | Seconds | Why |
|---|---:|---|
| `ACTION_TIMEOUT` | 6 | Silent drops: the 1 s per-action window, or no session yet. |
| `PROMPT_TIMEOUT` | 30 | |
| `RECEIPT_TIMEOUT` | 15 | |
| `PROFILE_RETRY` | 10 | |

Each pending entry carries a serial, so a late timer never clears a newer request.

**Signals:**
- `ShopData.Changed` (BindableEvent) fires on a profile push, a price landing, a pending change, an ownership attribute change and `ProtectionClient.Changed`.
- `ShopData.Message` fires `(text, tone)` for every non-empty push message, plus the client-side toasts above.

### 2.4 LocalScript `"Zyntra Shop L4"`

#### 2.4.1 Flag and open

`wantsL4()` reads `workspace:GetAttribute("ShopUIVersion")`. The value `"L4"` returns true. The value `"L4-dev"` returns `DevAccess.IsAllowed(player)`. Anything else returns false. It is re-read on every open.

The script creates the BindableFunction `PlayerScripts.ZyntraShopUIOpen`. Its `OnInvoke(tab, focus)` **never yields** and returns true only when all of these hold:
- `wantsL4()`;
- the window is built and bound with no purchase-critical name missing;
- `tab` is in `{Shop, Upgrades, Skins, Donate, Colors}`;
- `InRound ~= true` and `QueueModalOpen ~= true`;
- `UIDevice.ScreenOwningModalOpen()` is false.

Every other call returns false, so legacy opens: RECORDS, SETTINGS, DEV, in-round, or a binding failure.

**The first open builds the window:**
1. Clone `ReplicatedStorage.ZyntraShopUI.ZyntraShop_L4` and run `Binder.strip`.
2. Create a ScreenGui `ZyntraShopL4`:
   - `DisplayOrder` 56, one above legacy so the window always covers the rail;
   - `ResetOnSpawn = false`, `IgnoreGuiInset = false`, `ZIndexBehavior = Sibling`.
3. Make `Dim` full-screen and `Active`.
4. Re-parent `ShopWindow` into a holder Frame:
   - the holder is placed at `UIDevice.Layout().ModalViewport` through `UIDevice.LocalPosition`;
   - the window is resized to (1,1) under a `UIAspectRatioConstraint` of 1760/1016.

   This fits the *window*, not the artboard, which gains about 6% of scale. If Framewisp emitted a `UIScale` on its container, keep the container and parent it into the holder instead. The window is re-fitted on `UIDevice.Changed`.
5. Bind every name and run the purchase-critical check:
   - Close and TokenCount;
   - 5 `Tab_` and 5 `Page_`;
   - each §1.1 key's Buy and Price;
   - each picker's Save, `Slider_H/S/V` (Track and Knob), Lock and GetPass.

   A missing name warns `[ZyntraShopUI] L4 missing: <path>`, sets `bindFailed`, and returns false.
6. `ShopData.fetchPrices()`.

**The script never writes `ScreenGui.Enabled`.** The Lucky Wheel takeover owns it. Show and hide go through `Root.Visible`.

#### 2.4.2 Open, close and modal contract

**Open:** select the tab; `player:SetAttribute("ZyntraStoreOpen", true)`; `UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())`; bind ButtonB with `ContextActionService:BindActionAtPriority("ZyntraShopL4Close", …, High, ButtonB)`; select the active tab's hit button when `UIDevice.LastInput() == "Gamepad"`.

**Re-assert.** `GetAttributeChangedSignal("ZyntraStoreOpen")` sets the attribute back to true (deferred) while the window is open. Legacy `setMainVisible(false)` writes nil from several paths.

**Close:** set `ZyntraStoreOpen = nil`; release suppression the same way; unbind; clear the selection if it is inside the window; hide Pending and Toast.

**Close triggers** (the same as legacy contract §2.2):
- the Close button and ButtonB;
- `InRound` becoming true;
- `Humanoid.Died`;
- `Escaped`;
- `RoundActive` turning false while InRound;
- `QueueModalOpen` turning true.

**Header:**
- `Records` / `Settings` close the window, then `PlayerScripts.ZyntraOpenTerminal:Fire("Records" / "Settings")`. This keeps accessibility reachable (contract risk 6).
- `AddTokens` selects the Shop tab and tweens `Products.CanvasPosition.X` to `Card_Tokens20`.

#### 2.4.3 Pages (renderers are functions of `ShopData` only; each page is in its own `do … end`)

**Tabs.** The active `Page_<Tab>` is Visible. `ActiveBar` is Visible on the active tab, which also gets a TILE fill, a RAIL TEAL stroke and a CREAM label; the others get SAGE. The Footer hint per tab is copied from the design:
- `Prices are read live from Roblox.`
- `Each level costs one token more than the last.`
- `Cosmetic only · owned suits stay unlocked.`
- `Donations have no gameplay effect. Thank you.`
- `Colors save to your profile and show in every level.`

**Shop:**
- `ProductIcon.Image = "rbxassetid://"..IconId`.
- Price:
  - not ready: `LOADING` (off);
  - owned: `OWNED` (owned), plus `OwnedBadge` "OWNED";
  - pending: `WAITING` (off);
  - `Id == 0`: `COMING SOON` (off);
  - otherwise `R$ n`, or `BUY · R$ n` on the hero (robux).
- Earner: tier ≥ 2 is OWNED with an "ACTIVE" badge and the Hook `TOKEN EARNER <tier>x ACTIVE`. Then `CHECKING PRICE` / `UNAVAILABLE` / `R$ n`.
- `Products` scrolls on X. If the import leaves `CanvasSize` at 0, set `AutomaticCanvasSize = X` (`ScrollingDirection = X`).

**Upgrades:**
- `Percent` is `+StaminaPercent%`, `LevelReadout` is `LEVEL n`, and `Price` is `UpgradeCost(level)`.
- Buy is token-styled.
- Short of tokens: `NEED n MORE` (off). Pending: `SAVING...` (off). The `TokenGlyph` hides whenever the text is not a number.
- `EntityShield`, from `GetState()`:
  - `OWNED n`;
  - `5`, or `NEED n MORE`;
  - `CONFIRMING...` / `RETRY REQUEST` (enabled only when `CanRetry`);
  - `UNAVAILABLE` (always in Studio).
- Supplies: `n STORED` / `n MARKERS` and the cost.

**Skins:**
- Cards: `SkinArt = PreviewImageId`. Selecting a card (a `Hit` under Buy, ZIndex 0) sets the preview art, name and status.
- `Price`:
  - `EQUIPPED` (off);
  - `EQUIP` (equip);
  - `<cost>` (token);
  - `NEED n MORE` (off);
  - `n/100 CLEARS` (off; Blacksite);
  - `R$ n` (robux, verified);
  - `CHECKING PRICE` / `UNAVAILABLE` (off);
  - `SAVING...` / `WAITING`.
- `Meta`: `OWNED`, `PREMIUM SUIT`, `300 TOKENS`, ….
- `PreviewStatus`, once equipped: `EQUIPPED · WORN IN YOUR NEXT RUN` (the suit only renders in rounds, contract §2.6).

**Donate:**
- `SupportTotal` is `RECORDED SUPPORT n R$`, from `RecordedSupportRobux` or `DonationRobux`.
- `SupportBreakdown` is `Donations n R$ · Products n R$ · Passes n R$`.
- `Support20K` shows when `ZyntraOwnsDonation20K`.
- Tier Price is `R$ n`, or `WAITING`.

**Colors:**
- The HSV state per picker is clamped as legacy: H 0..1, S 0..0.9, V 0.35..1, seeded from `profile.HazmatColor` / `GlowstickColor`.
- Dragging works through the `Track` `Hit`: `InputBegan`, then `UserInputService.InputChanged` until `InputEnded`.
- The S and V Track `UIGradient.Color` is rebuilt from the current H/S.
- `Swatch` colour, and the `Value` texts `46°` / `72%` / `89%`.
- `Preset_n` sets HSV from its authored `BackgroundColor3`, clamped.
- `Lock` is visible and `Active` when not owned. `GetPass` runs `purchase("AdvancedEquipment" / "CosmeticEquipment")` and shows `BUY · R$ n`.
- Save shows `SAVING...` while pending.

**Toast, Status and Pending:**
- Every `ShopData.Message` writes `Status` (for 6 s, then the tab hint) and shows `Toast` for 2.4 s (3.5 s on error). `ToastAccent` is RAIL TEAL for success, CORAL for error and ICON TEAL for info.
- `Pending` is visible while `promptOpen`, with `PendingText` = `<Name> · R$ n. Confirm in the Roblox window.`

#### 2.4.4 Lobby skins (applied once when `wantsL4()` first holds; a rejoin removes them)

**Rail.** Wait up to 10 s for `PlayerGui.ZyntraStore`. Then, for each of the 5 legacy buttons, run the `LobbyRail_L4` template:
1. Graft `Face` (with its shadows, `Plate` and `Label`) as `L4Skin_Face`: size (1,1), ZIndex 4. That is under `NotificationDot` (5) and above the legacy content.
2. Set the legacy `SectionButtonContent.Visible = false`. Never destroy it: ZyntraStore dot-indexes it.
3. Set the legacy `SquareSectionBorder.Color` to RAIL TEAL (#44DDC4). Legacy already toggles its Transparency on hover, which gives the design's hover stroke for free. Legacy never writes its Color.
4. Wire `Binder.press` on the legacy button to the grafted face.
5. MUSIC: the label mirrors `SectionCaption.Text:upper()` on change (`Mute` / `Unmute` / `Music`).
6. Labels get a `UITextSizeConstraint` with `MinTextSize = 11`, to keep UIRegression's text floor at the 52 px rail size.

The size stays on legacy's tested ladder (64 → 56 → 52 → two columns). A bigger PC rail is a one-number ZyntraStore change and an owner decision.

**Lobby token pill.** A ScreenGui `ZyntraLobbyPillL4` (DisplayOrder 55) holding the template `TokenPill`.
- Visible under the legacy rail's predicate: `InRound ~= true`, no QueueModalOpen, no screen-owning modal, and window closed.
- Placed at the safe top, with its right edge 12 px left of `UIDevice.TopRightPanel(layout.Narrow and 220 or 260, 1).Left` (the Friend Boost chip column).
- Hidden if that would cross the rail's right edge (narrow phones). The window header shows the balance anyway.
- `AddTokens` opens the window on Shop, focused on `Card_Tokens20`.

**Wheel** (`PlayerGui.LuckyWheelGui`, template `LuckyWheel_L4`). Every property below is written once by Lucky Wheel Client, and was checked in the repo copy. `applyLayout` writes only Size, Position, Text and TextSize, and `paintHub` only Text, TextSize and Active.
- `WheelDisc.Image` comes from the template disc.
- `FieldLabel1..6.Visible = false`: the pictograms are baked into the art.
- `FieldOdds1..6` stay, recoloured CREAM, unless the Odds panel is shown.
- `WheelPointer`: `BackgroundTransparency = 1`, its `UIStroke.Enabled = false`. The template pointer is grafted into `WheelHolder` at (0.5, 0), sized (104/760, 140/760) with AnchorPoint (0.5, 0.35).
- `HubButton`: `BackgroundColor3` RAIL TEAL, `TextColor3` INK, and its `UIStroke` set to INK at about 6/208 of the diameter.
- `CloseButton`: CORAL face and CREAM X.
- The `Odds` panel and `TitleBlock` are grafted into `WheelShade`:
  - the panel is a child of `WheelHolder`, at `UDim2.new(1, 24, 0.5, 0)` with AnchorPoint (0, 0.5) and size (0.62, 0.66) of the holder;
  - it is Visible only when `holder.AbsolutePosition.X + holder.AbsoluteSize.X * 1.62 + 24 <= Safe.Right`;
  - when it is visible, FieldOdds hide. `OddsValue` comes from `Config.DailyRewards.Wheel[i].Weight`.

The takeover keeps working, because every graft lives inside `LuckyWheelGui`.

**Daily rewards** (`PlayerGui.DailyRewardsGui`, template `DailyRewards_L4`):
- The skin map covers only `DailyRewardsPanel`, `RewardsHeader`, `HeaderTitle`, `CloseButton`, `StatusLine` and the `Milestone*` card frames (fill, stroke and corner).
- **Before the map is finalised,** grep Daily Rewards Client and ZyntraDailyRewardsPage for later writes to each listed property, and drop any that is rewritten after build. Claim-button state colours stay code-driven.
- The `TokenPill` is grafted into `RewardsHeader` and is visible only when the header is at least 900 px wide.

A full re-layout to match 52:2164 needs edits to the Daily client and page. That is an owner decision, not part of this plan.

#### 2.4.5 Studio probe

`RunService:IsStudio()` only. A BindableFunction `UIRegressionZyntraShopL4Probe` under the `ZyntraShopL4` gui accepts:
- `open[:Tab]`, `close`, `tab:<Name>`;
- `cards`, which returns `page|key|action` lines;
- `state`, which returns the current Price text per key.

### 2.5 What each flow uses, at a glance

| Flow | Remote / action | MarketplaceService | Reads | Writes |
|---|---|---|---|---|
| Profile | `ZyntraGetProfile:InvokeServer()`, `ZyntraProfileChanged.OnClientEvent(profile, msg, tone)` | – | `ZyntraProfileLoaded` | – |
| Pass buy | – | `PromptGamePassPurchase`, `PromptGamePassPurchaseFinished`, `GetProductInfo(GamePass)` | `ZyntraOwns<Key>`, `profile.Owns*` | – |
| Product / donation buy | – (the receipt is server-side) | `PromptProductPurchase`, `PromptProductPurchaseFinished`, `GetProductInfo(Product)` | push message | – |
| Earner | – | as for passes, verified `IsForSale` / `TargetId` | 6 `ZyntraOwnsTokenEarner*` | – |
| Upgrades / items / skins / colours | `ZyntraAction` `UpgradeStamina`, `UpgradeBattery`, `BuyItem`, `BuySkin`, `EquipSkin`, `SetHazmatColor`, `SetGlowstickColor` | Robux skins as passes | `Tokens`, `*Level`, `*Percent`, `Items`, `Skins`, `CompletedLevels`, `*Color` | – |
| Entity Shield | `ProtectionClient.Request("BuyProtection")` / `.Retry()` | – | `ProtectionClient.GetState()` | – |
| Modal | – | – | `InRound`, `Escaped`, `QueueModalOpen`, workspace `RoundActive`, `ShopUIVersion`, `UIDevice.ScreenOwningModalOpen()` | **`ZyntraStoreOpen`** (client-local), `UIDevice.SuppressTouchMovement` |
| Bridges | `PlayerScripts.ZyntraShopUIOpen` (created), `PlayerScripts.ZyntraOpenTerminal` (fired) | – | – | – |

### 2.6 The ZyntraStore routing patch (Studio first, after the pull; draft at `roblox-draft/patches/ZyntraStore.routing.md`)

**Hunk 1,** in `openKioskShop(tab)`, directly after the `if tab == "Rewards" then … end` block:

```lua
	local alt = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("ZyntraShopUIOpen")
	if alt then
		local ok, used = pcall(alt.Invoke, alt, type(tab) == "string" and tab or "Shop")
		if ok and used == true then return end
	end
```

**Hunk 2,** the UPGRADES rail handler (`openButton.Activated`), which also fixes "opens the last tab":

```lua
openButton.Activated:Connect(function()
	local alt = player.PlayerScripts:FindFirstChild("ZyntraShopUIOpen")
	if alt and player:GetAttribute("InRound") ~= true then
		local ok, used = pcall(alt.Invoke, alt, "Upgrades")
		if ok and used == true then return end
	end
	toggleMain()
end)
```

- **No new top-level local:** ZyntraStore is near the 200-register ceiling.
- `toggleMain` itself is not touched, so the dev phone, J and UIRegression's `probe("open")` keep opening legacy.
- Run `tools/studio_compile_probe.luau` afterwards.
- The anchors must be re-found in the **pulled** ZyntraStore (+2015 bytes are unknown).

### 2.7 Constraints on the drafts

- **Register limit.** Each draft compiles with `luau-compile.exe -O0`, with no "Out of local registers". Keep the LocalScript's top level under about 120 locals: per-page `do … end` blocks, and state in tables.
- **ASCII only in source.** `tools/install_new_scripts.py` embeds the source with `json.dumps`, so write `·` as `\u{B7}`, `…` as `\u{2026}` and `°` as `\u{B0}`.
- **No `WaitForChild` without a timeout on optional things.** Skins wait at most 10 s and then skip.
- **No yields inside `ZyntraShopUIOpen.OnInvoke`.**

---

## 3. Install and switch

### 3.1 The flag

`workspace` attribute `ShopUIVersion` (string), saved with the place:
- unset: legacy for everyone, and the default until the owner flips it;
- `"L4-dev"`: developers only;
- `"L4"`: the release.

The window reads it on every open. Skins apply when it first holds and are removed by a rejoin. No server code reads it.

### 3.2 Hiding legacy without deleting it

- **Routing (§2.6)** sends SHOP, UPGRADES and every `ZyntraOpenTerminal("Shop" | "Upgrades" | "Skins" | "Donate" | "Colors")` to L4.
- **The legacy terminal** stays built and still serves RECORDS, SETTINGS, DEV, the in-round dev phone and the fallback.
- **Its five shop tabs stay reachable** only from inside RECORDS or SETTINGS. That is accepted until phase C (contract §5.6), when the owner decides to delete them.
- **The legacy rail** is skinned, not replaced.
- **The wall card's `ZyntraShopBuy` bridge** stays on legacy `productPurchase`. That is a different UI surface, so there is no double prompt: every button has exactly one dispatcher.

### 3.3 Order of work in this session's Studio slot

0. **Wait for the slot** in the coordination queue. Other sessions hold Studio now; see memory `mongotv-parallel-sessions`.
1. **Check the working tree.** `git status`. The snapshot at the start of this session already showed uncommitted edits by another session to ZyntraConfig, ZyntraMonetization, UIRegression, DevCheats and more. Do not pull over those. Agree with that session first, or wait for its commit.
2. **Audit Studio.** `python tools/pull_source_from_studio.py --audit`, then pull the 5 drifted scripts: ZyntraConfig, ZyntraMonetization, ZyntraStore, HazmatSkinVisuals and HazmatSkinDriver. Only do this with no `pending-studio-push` entries.
3. **Re-check against the pulled copies** (§3.4). Fix the drafts if anything moved.
4. **Transplant the templates** from the scratch Baseplate into `ReplicatedStorage.ZyntraShopUI`:
   - create the Folder through `execute_luau`;
   - insert the `.rbxm`;
   - delete scripts;
   - check every frame's `LuaSourceContainer` count is 0.
5. **Run the offline tests** (§4.1). Compile the 3 drafts with `luau-compile -O0`.
6. **Copy the drafts to their mirror paths** and run `python tools/install_new_scripts.py --dry-run <3 paths>`, then the real run. It creates the scripts in Studio (via `multi_edit` when absent), reads `.Source` back byte for byte and writes `synced` manifest items with `sha256_of` / `canonical_bytes`.
7. **Apply the ZyntraStore patch in Studio** through `ScriptEditorService:UpdateSourceAsync`. That follows the Studio-first rule. Then mirror it back with `python tools/pull_source_from_studio.py` (or `tools/record_synced_source.py`), and confirm that `--audit` reports 0 drift. Run `tools/studio_compile_probe.luau`.
8. **Run the Studio QA** (§4.3) with `ShopUIVersion = "L4-dev"`. Leave the attribute **unset** in the saved place unless the owner says otherwise.
9. **Update `CLAUDE.md`** with a dated block (the flag, the 3 scripts, the skins, the routing hook) and commit **only on the owner's request**.

### 3.4 Re-check list after the pull (Studio is newer; the diffs are unknown)

**ZyntraMonetization (+4333 bytes):**
- the `ZyntraAction` dispatcher's action names and payload shapes (`UpgradeStamina`, `UpgradeBattery`, `BuyItem {Key}`, `BuySkin id`, `EquipSkin id`, `SetHazmatColor/SetGlowstickColor Color3`);
- the per-action windows (1 s);
- `publicProfile` / `enrichedPublicProfile` fields (`Tokens`, `Owns*`, `Skins`, `Items`, `CompletedLevels`, `*Robux`, `*Color`, `*Level`, `*Percent`);
- the `refreshPasses` attribute names (`ZyntraOwns*`, including all 6 TokenEarner and the 2 skin passes, and `ZyntraOwnsDonation20K`);
- `ZyntraProfileLoaded`;
- the receipt messages for Tokens20, ExpeditionPack and the donations;
- whether the ACHIEVEMENTS hook changed any push.

**ZyntraStore (+2015 bytes):**
- the routing anchors (`openKioskShop`, the `openButton.Activated` handler);
- `ZyntraOpenTerminal` tab names. Is there an **Achievements** tab now? If so, decide whether the L4 header needs a third entry, or whether Records covers it;
- the rail names, `SectionButtonContent > SectionCaption`, `SquareSectionBorder`, `NotificationDot`;
- that `setMainVisible` still writes `ZyntraStoreOpen`.

**HazmatSkinVisuals / HazmatSkinDriver (+61 each):** is the "visual only while InRound and RoundActive" gate still there? It decides the `WORN IN YOUR NEXT RUN` copy.

**ZyntraConfig:** no shop key changed (already diffed). Confirm `Donations` still has the 5 keys L4 uses.

**Lucky Wheel Client and Daily Rewards Client** (same size, not proven equal): re-verify the skin-map properties are still written only at build.

### 3.5 Coordination

- Reserve the Studio slot in the coordination files before step 3.3.0.
- Announce the touched scripts there: the 3 new ones and ZyntraStore.
- Expect a CONFLICT from `push_repo_to_studio.py` for any script another session touched. Merge it, and never `--overwrite-conflicts`.
- The friend's sessions also publish. **This work never publishes**; the owner publishes.
- Scratch-Baseplate reads touch only that Studio window: pick it by `studio_id` from `list_roblox_studios`, never the game place.

### 3.6 Rollback (no data migrates, so nothing needs undoing on the server)

1. **Per player, automatic.** Any binding failure makes `ZyntraShopUIOpen` return false, and legacy opens.
2. **Global, instant in Studio.** Unset `workspace.ShopUIVersion` and publish: everyone gets legacy, and skins stop applying from the next join.
3. **Hard.** Disable the LocalScript `"Zyntra Shop L4"` and publish. The routing hook finds no bindable and is inert.
4. **Full revert.** Revert the ZyntraStore patch from git (mirror, then push) and delete the 3 scripts and the `ZyntraShopUI` folder. Legacy UI was never changed beyond the patch.

---

## 4. Tests

### 4.1 Offline: `tools/tests/test_zyntra_shop_l4.py` (draft under `roblox-draft/tests/`)

It follows the house pattern of `test_friend_boost.py` and `test_lucky_wheel_client.py`:
- Python writes one Luau file and runs it with `LUAU_BIN`. The binary is `C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/CodexTools/luau/0.737/luau.exe`.
- The **real** `ShopBinder`, `ShopData` and `"Zyntra Shop L4"` run, against the real `ZyntraConfig` and `ZyntraSkins`.
- The fakes are: the Instance tree, the signals, `task.delay` with a manual clock, `UIDevice` (`Layout`, `SetEnabled`, `SetInteractive`, `ScreenOwningModalOpen`, `OnScreenOwningModalChanged`, `SuppressTouchMovement`, `LocalPosition`, `TopRightPanel`, `LastInput`, `Changed`), `ProtectionClient`, MarketplaceService (it records `Prompt*` calls and fires the `*Finished` events on demand), the remotes (`FireServer` is recorded; `InvokeServer` is scripted), `DevAccess`, `ContextActionService` and `UserInputService`.

**The fake tree** is built from `roblox-draft/tests/framewisp-tree.L4.json`. It starts as §1.1 written out by hand, and is **replaced by the real dump** of the scratch import (`roblox-draft/tools/dump_framewisp_tree.luau`). It is instantiated in four variants:
- (a) full tag names (`Buy_button`, `Tab_Shop_tab:Shop`);
- (b) tags stripped, with `_tab_Shop` in place of `_tab:Shop`;
- (c) every `Buy` as a Frame (it gets a `Hit`);
- (d) every `ProductIcon` as a Frame with an ImageLabel child.

**Asserts:**

1. **Binding.**
   - All four variants bind, and `ZyntraShopUIOpen:Invoke("Shop")` returns true.
   - With `Card_Tokens20 > Buy` removed, it returns false and warns `missing`.
   - With the flag unset, it returns false.
   - `"Records"` returns false.
   - It returns false when `InRound` is set or `QueueModalOpen` is true.
2. **Gate.**
   - Before a profile, and with `ZyntraProfileLoaded == false`: every Price reads `LOADING`, TokenCount reads `--`, and pressing every Buy makes **zero** calls.
   - `InvokeServer` returning nil, followed by a push, makes everything ready.
3. **Dispatch.** Each Buy press makes **exactly one** expected call:
   - `PromptGamePassPurchase(player, 1941938256)` for Supporter (the id is read from Config in the test, not a literal);
   - `PromptProductPurchase` for ExpeditionPack, Tokens20 and the 5 donations;
   - `FireServer("UpgradeStamina")`;
   - `FireServer("BuyItem", {Key = "SpeedPotion"})`;
   - `FireServer("BuySkin", "PoolService")`, then `FireServer("EquipSkin", "PoolService")` once owned;
   - `PromptGamePassPurchase(player, StaticWraith.PassId)` only when verified;
   - `FireServer("SetHazmatColor", <Color3>)`;
   - `ProtectionClient.Request("BuyProtection")`, and `.Retry()` when Pending.

   A second press while pending makes no call. Owned passes make no call.
4. **Earner.**
   - Tier 1 with 2x verified shows `R$ 149` and prompts the 2x id.
   - Tier 1 with 2x off sale shows `UNAVAILABLE` and makes no call.
   - Tiers 2, 3 and 5 (5 by `TokenEarner5x`, by `2x + Up2to5`, and by `3x + Up3to5`) show `OWNED`, the Hook `TOKEN EARNER <n>x ACTIVE`, and make no call.
5. **Timeouts.**
   - A token action with no push reverts `SAVING...` after 6 s on the fake clock.
   - A pass prompt cancelled (`wasPurchased == false`) restores the button with no toast.
   - A product with `isPurchased == true` and no push for 15 s shows the toast `Processing, it will arrive shortly.`
   - A prompt with no Finished event restores after 30 s.
   - A late timer from serial n does not clear request n+1.
6. **Ownership display.** Fixtures:
   - 0 tokens: `NEED n MORE` is disabled on Upgrades and Supplies;
   - every pass owned;
   - each of the 7 skin states;
   - `ZyntraOwnsDonation20K` shows `Support20K`;
   - colour locks: `Lock` visible and Active, and `GetPass` prompting the right pass;
   - Entity Shield `UNAVAILABLE`, `CONFIRMING...` and `RETRY REQUEST`.
7. **Tabs.** Selecting each tab leaves exactly one `Page_*` Visible and one `ActiveBar`. `AddTokens` selects Shop.
8. **Modal.**
   - `ZyntraStoreOpen` is true after open, re-asserted after an external nil while open, and nil after each close trigger: Close, ButtonB, InRound, Died, Escaped, `RoundActive` false while InRound, and QueueModalOpen.
   - `SuppressTouchMovement` is called on each open and close.
   - `ScreenGui.Enabled` is never written.
9. **Template hygiene.** A `LocalScript` and a `Foo_ignore` planted in the template are absent from the clone.
10. **Skin maps** run against fake `ZyntraStore`, `LuckyWheelGui` and `DailyRewardsGui` trees with the legacy names:
    - `SectionButtonContent` is hidden but present;
    - the `L4Skin_Face` graft is idempotent (applying twice makes one graft);
    - a missing legacy node is skipped with a warning and no error.

### 4.2 Existing tests and UIRegression rows affected

| Test / row | Effect | Action |
|---|---|---|
| `test_zyntra_store_compact.py` | Loads ZyntraStore. The patch is `FindFirstChild` + `pcall`, so with no bindable in the fake it is a no-op. | Re-run after the patch; it must stay green. |
| `test_reentry_dismissal.py`, `test_rail_dots_intro.py` | Slice ZyntraStore by function name. Nothing is renamed. | Re-run. |
| `test_lobby_shop_display.py` | The bridge is unchanged. | Re-run. |
| `test_lucky_wheel_client.py`, `test_daily_rewards_client.py`, `test_daily_rewards_page.py`, `test_friend_boost.py`, `test_controller_input.py`, `test_round_exit_hold.py`, `test_equipment_hud.py` | Untouched code. No new modal name; `ZyntraStoreOpen` is reused. | Re-run. |
| Server tests (`test_daily_rewards.py`, `test_item_inventory.py`, `test_support_product_receipts.py`, `test_token_grants.py`, …) | No server change. | Re-run after the pull. |
| Known red at HEAD (unrelated) | `test_level3_run_in_exit`, `test_level3_hidden_chase`, `test_level3_slide_aperture` | Leave. |
| UIRegression `store-modal`, `ZyntraTerminalFitMatrix`, rail rows (`ZyntraStore:FindFirstChild("ZyntraShopButton")` …) | Legacy paths. They pass with the flag **unset**. With skins on, the rail rows also measure the grafted labels (hence `MinTextSize` 11). | Run with the flag unset; run once more with `L4-dev` to catch skin text floors. |
| UIRegression, **new lane** `ZyntraShopL4FitMatrix` (a later edit to a mirrored file, before the owner sets `"L4"`) | Opens through the probe on every `Fit.Devices` row. Checks: bound actions ≥ 44 px; text ≥ 11 px; reachable + stood-down-with-caption = the probe's `cards`; `ZyntraStoreOpen` true while open; Forbids the 5 rail buttons while open. | Add the captions `LOADING`, `CHECKING PRICE`, `NEED %d+ MORE`, `%d+/%d+ CLEARS` to `Fit.ZyntraDisabledCaptions` (patterns, no literal `...`). |

### 4.3 Studio Play QA checklist (dev account, `ShopUIVersion = "L4-dev"` unless noted)

1. The compile probe and `pull --audit` are clean. The console has no `[ZyntraShopUI]` warnings and no errors at join.
2. **With the flag unset:** the rail, SHOP and UPGRADES are legacy, and the legacy UIRegression rows are green.
3. **Rail skin:**
   - the new faces on all 5 buttons;
   - hover gives a teal stroke, and press moves the face 6 px and hides the shadow;
   - the REWARDS and WHEEL dots appear when claimable;
   - MUSIC reads Mute/Unmute;
   - two-column fallback in the Device Simulator at 705x338.
4. **Routing:** SHOP opens L4 on Shop, and UPGRADES opens L4 on Upgrades (twice in a row: it does not remember the last tab).
5. **Gate and pill:** TokenCount equals the profile, and the lobby pill shows the same number. `--` and `LOADING` show only during profile load. AddTokens scrolls to 20 Research Tokens.
6. **Shop.** `GrantAllPasses` shows OWNED on all passes, and the earner reads `TOKEN EARNER 5x ACTIVE`.
   - Studio test-purchase of Expedition Pack: the toast `Expedition Pack stored…`.
   - Tokens20: the toast `+20 Zyntra Research Tokens`, and TokenCount rises by 20.
   - Cancel a prompt: the button is restored with no toast.
7. **Upgrades:**
   - UpgradeStamina: +5% and LEVEL +1, and the price rises by 1.
   - Speed Potion: `n STORED` +1. Route Marker likewise.
   - Entity Shield shows `UNAVAILABLE` (it always does in Studio).
   - Spend the Studio profile's 25 starting tokens down: `NEED n MORE` appears. The 0-token fixture is also covered offline.
8. **Skins:** unlock and then equip PoolService, which reads `EQUIPPED · WORN IN YOUR NEXT RUN`; Blacksite shows `n/100 CLEARS`; StaticWraith and FalseSun show EQUIP (`GrantAllPasses`).
9. **Donate:** a R$ 10 test purchase gives the toast `Thank you — 10 R$ added…`, and SupportTotal rises.
10. **Colors:** drag H, S and V (mouse, and touch in the Device Simulator), use a preset, SAVE, and get `Hazmat color saved.` Glowstick likewise. The locked state is covered offline.
11. **Header:** RECORDS and SETTINGS close L4 and open legacy on that tab. Close the legacy window, and the rail is back.
12. **Close paths:** X, ButtonB (gamepad emulation), reset character, step into a queue (QueueModalOpen). After each, `ZyntraStoreOpen` is nil and the rail is back.
13. **While open:** the rail, Friend chip and HUD stand down; touch movement is suppressed (`ForceTouchUI`); the wall card is not reachable.
14. **Wheel:**
    - the new disc is shown and FieldLabels are hidden;
    - spin, collect and skip still work;
    - the landed prize pictogram sits under the pointer (park check: `disc.Rotation` against each recorded key, using the dev wheel path);
    - the odds panel shows on PC, and FieldOdds show on a phone;
    - after close, the takeover restores `ZyntraShopL4` and `ZyntraLobbyPillL4` correctly.
15. **Disc geometry,** before upload, offline: a Python check on `figma-ai/upload/wheel-disc-v3-ai.png` samples a ring at 0.7R for the cream divider peaks. It asserts 6 peaks within ±3° of 30° + 60°k. The client's jitter margin keeps landings clear of the edges.
16. **Daily rewards skin:** claim 5 MIN works, and the skin survives the page's re-render.
17. **Device Simulator** at 844x390, 705x338 (with a 58 px inset), 956x440 and 1280x800 tablet: the new lane passes. Note any tap target under 44 at 705x338 for the owner (contract decision 7.1).
18. **Published dev server, by the owner:**
    - a non-dev alt account sees legacy under `L4-dev`;
    - a dev account sees L4;
    - unowned pass states, the real Robux prompt, and the AI images loading (if Framewisp uploaded them to the owner's user, check the creator; re-upload to group 1039373905 with the `tools/level4_blender/studio_upload.py` EditableImage pattern if they do not load).

---

## 5. Owner steps (Danish)

0. Vent til Claude melder, at siden **"L4 · Roblox export"** er bygget i Figma-filen (shop-filen 7FXycGKH6OT6Lme6FV3VBc).
1. **Figma:** åbn siden **"L4 · Roblox export"**.
   1. Markér rammen **ZyntraShop_L4**. Vælg selve rammen, ikke sektionen omkring den.
   2. Kør **Plugins › Framewisp › Code › Convert**.
   3. Kopiér den 6-tegns kode.
2. **Studio:** åbn en **NY, tom Baseplate** (File › New › Baseplate). Det må **IKKE** være spillets place.
   1. Kør Framewisp-pluginet, indsæt koden og tryk **Import**.
   2. Skriv til Claude: *"ZyntraShop_L4 importeret i en tom Baseplate"*.
   3. Lad vinduet stå åbent, og gem eller publicér det ikke.

   Claude læser det importerede træ fra netop det vindue over MCP og tilpasser binderen. Hvis Figma-rammen skal rettes, siger Claude til, og så gentages trin 1-2. Framewisp giver højst 5 konverteringer om dagen.
3. **Gentag trin 1-2** i denne rækkefølge: **LobbyRail_L4**, så **LuckyWheel_L4**, så **DailyRewards_L4**. Den sidste kan vente til næste dag, hvis dagens 5 konverteringer er brugt.
4. **Creator Dashboard:**
   - sæt **Token Earner 2x** til salg;
   - sæt **Token Earner 3x, 5x og de tre opgraderingspas** off-sale (dagens beslutning).

   Indtil 2x er til salg, viser kortet UNAVAILABLE. Dem, der allerede ejer 3x/5x, beholder deres multiplikator.
5. **Senere, i Claudes Studio-tid** (når de andre sessioner har givet Studio fri): åbn spillets place og sig til.
   - Claude flytter de importerede rammer ind i ReplicatedStorage, opretter de tre nye scripts, indsætter den lille routing-ændring i ZyntraStore og kører testene.
   - Du skal kun importere igen, hvis Claude beder om det.
6. **Afprøv:**
   1. I **Explorer › Workspace › Attributes** sæt `ShopUIVersion` = `L4-dev`. Så ser kun udviklere den nye butik.
   2. Tryk **Play**, og gennemgå tjeklisten (afsnit 4.3) sammen med Claude.
7. **Frigiv:** når du er tilfreds, sæt `ShopUIVersion` = `L4` og publicér.

   **Fortryd:** slet attributten og publicér. Alle får den gamle butik igen, og ingen data skal rettes.

---

## 6. Open owner questions (none of them blocks phase 1)

1. **Phone tap floor.** Under a 58 px inset on a 705x338 phone the L4 window can still go under 44 px. Accept it, or ask for 136+ px buttons in the export frame?
2. **Rail size on PC.** It stays on legacy's 64 px ladder. Bigger is a one-number ZyntraStore change.
3. **Daily Rewards.** Is a skin enough, or does it need a real re-layout to 52:2164 (edits to its client and page)? Should WheelLink go in?
4. **Lobby wall.** It still sells Tokens4, Emergency Re-entry and Glowstick through legacy. Keep it, or align it with the 6-product SHOP?
5. **Phase C.** Delete the legacy shop tabs? Do RECORDS and SETTINGS get L4 designs? Is there an Achievements entry in the header, if the Studio ZyntraStore has that tab?
6. **3D skin preview** (ViewportFrame) instead of the 2D render.
