# DailyRewards_L4: template map for binding (2026-10-07, read-only)

Sources:
- The real import dump `roblox-draft/tests/framewisp-dump.DailyRewards_L4.json`. It is the 2026-10-06 import, measured at k = 361/1080 = 0.3343. `install/01_templates.luau` clones exactly this import to `ReplicatedStorage.ZyntraShopUI.DailyRewards_L4` and copies `BB_*` onto the root.
- Figma `7FXycGKH6OT6Lme6FV3VBc`, read 2026-10-07 with get_metadata and get_screenshot:
  - `91:331` "DailyRewards_L4" is the export frame the import came from. Screenshot: `figma-91-331-export-frame.png`.
  - `52:2164` "L4 / Daily Rewards" (instance `52:2165`) is the design page. It matches the owner's screenshot. Screenshot: `figma-52-2164-design-page.png`.

All rects below are in design px (1920x1080 artboard): `x,y wxh`. "Card-local" means relative to the milestone card.

## 0. Verdict

1. **The template is not the owner's screenshot.** It is the flattened export frame 91:331, and it differs from the design page 52:2164 in five ways:
   - **No Lucky Wheel row.** It was deleted on purpose. `_local/shop-ui-figma/l4-export/call5-rail-wheel-rewards.js:111` runs `del(n)` on every `WheelLink*` node. L4-ROBLOX-PLAN section 1.4 had left the row as an open owner question; the screenshot now answers it.
   - **Placeholder art in four image slots.** `HeaderGift` and the three `RewardIcon`s all hold `rbxassetid://116221992818153`, the grey square.
   - **The eyebrow is a stale baked image with "//" in it.**
     - `Eyebrow` is an ImageLabel 286 design px wide. Its text is "ZYNTRA // DAILY", as in the 10-05 export.
     - Figma now has the text node "ZYNTRA DAILY", 217 px wide.
     - This breaks rule 4.
   - **Milestone5's reward name is a baked image**, not text.
   - **Figma's hidden layers were not imported.** Framewisp drops hidden layers, so these are absent:
     - `ClaimedBadge` with `ClaimedLabel` "CLAIMED".
     - The hidden price children of `ClaimButton`: Label, PriceLabel, Sep, TokenGlyph, Price, Amount and Requirement.
2. **Backdrop and ZIndex:**
   - There is **no `Dim` layer**.
   - **The backdrop is the artboard root's own fill.** `DailyRewards_L4` has BackgroundColor3 5,9,11 (#05090B), **BackgroundTransparency 0**, ClipsDescendants true and a `UIAspectRatioConstraint` 1.7778.
   - The **root ZIndex is 1**, but `DailyRewardsModal` is **ZIndex 4** and its descendants run from 6 to 226. Every sibling pair is drawn in ascending order (shadow under face).
3. **There are only 5 input controls, and all are `TextButton`s:**
   - `AddTokens`
   - `CloseButton`
   - 3x `ClaimButton`

   Each has Text "", AutoButtonColor true and Selectable true. `Binder.button(node)` returns the node itself and turns off AutoButtonColor. Everything else is display.
4. **There is no ScrollingFrame and nothing scrolls.** The two columns fit the window.

## 1. Mount (rules 1-3), the same pattern as Zyntra Shop L4 `ui.build`

- **Art (`art` = clone of the root):**
  - Destroy its `UIAspectRatioConstraint`.
  - Set it full-screen: AnchorPoint 0,0, Size 1,1.
  - Set **BackgroundTransparency = 1**. This removes the opaque #05090B fill, which is the backdrop.
  - Set **ZIndex = 1**.
  - **Create** `Dim` (the template has none): full-screen, BackgroundTransparency 1, **Active = true**, parented to `art`.
- **Holder:**
  - `WindowHolder` with **ZIndex = 2**, in a ScreenGui with **ZIndexBehavior Sibling**.
  - `WindowFit` with a UIAspectRatioConstraint.
  - **Fit on `DailyRewardsPanel`, 1680x1020, not on `DailyRewardsModal`, 1680x1036.** At 844x390 the touch fit is 332 px tall. A 136 px button is then 136*332/1020 = **44.3 px**. With the 16 px shadow inside the fit box it would be 43.6 px, under the floor.
  - `ModalShadow` (1680x1020, 16 px lower) becomes the drop shadow: Position Y = 16/1020 = 0.0157, ZIndex 1. The panel goes at ZIndex 2.
- `ui.fit()` is unchanged:
  - PC: `PC_SCALE` 0.5 and `PC_MIN_HEIGHT` 400.
  - Touch: the full safe-area height.
  - Ten-foot: full size.
- **Text:**
  - `design = Binder.designSize(panel)` gives 1680x1020. The root carries `BB_DesignW/H`; the default is 1920x1080.
  - `Binder.scaleText(panel, design, art:GetAttribute("BB_TextFactor"))` runs after any `TextWrapped` changes listed in section 4.
- **Input sinking:** the panel and modal are Active = false, so a tap on an empty part of the window falls to `Dim`, which sinks it. Nothing reaches the world.

## 2. Node map (every visible element)

Lookups use `Binder.at(panel, path)`. Every step is a descendant search, so the `Items` wrappers never need naming.

**Duplicate names:**
- `Label` appears twice (PlayStrip and CountdownStrip) and `State` three times. Scope them by their parent.
- `TokenGlyph` appears in the pill and in every research row.
- `Name` matches the first research row if it is looked up from the panel.

### Header: `DailyRewardsPanel/Items/RewardsHeader/Items/...` (horizontal UIListLayout)

| Lookup | Class | Rect | Shows / does | Data |
|---|---|---|---|---|
| `HeaderGift` | ImageLabel (Fit) | 166,87 112x112 | Gift art. **Placeholder** | Static: legacy `rbxassetid://117126194981100` |
| `TitleBlock/Eyebrow` | **ImageLabel** (Stretch) | 303,90 286x23 | **Baked "ZYNTRA // DAILY"** (rule 4) | Static "ZYNTRA DAILY": see section 5 |
| `HeaderTitle` | TextLabel, Montserrat Heavy, cream, Center | 302,135 585x47 | "DAILY REWARDS" | Static |
| `TitleBar` | Frame (IconTeal) | 302,197 96x8 | Accent bar | - |
| `TokenPill` | Frame (#05090B, stroke Line, r .373) | 1147,68 447x150 | Token pill. No list layout: children sit at fixed positions | - |
| `TokenPill/TokenGlyph` (TokenChip, TokenBar) | Frame x3 | 1182,113 44x59 | Token glyph | - |
| `TokenCount` | TextLabel, RobotoCondensed Heavy | 1242,122 58x41 | "37" | `profile.Tokens` (`ui.counts` / `renderCounts`) |
| `TokenLabel` | **ImageLabel** | 1316,133 113x22 | Baked "TOKENS" | Static |
| `AddTokens` | **TextButton** (IconTeal, r .147) | 1447,75 136x136 | The "+" | See section 3 |
| `AddTokens/Plus` | TextLabel | - | "+" | Static |
| `CloseSlot/CloseShadow` | Frame (126,47,39) + UIShadow | 1618,79 136x136 | Hard shadow. `shadowOf` finds it through the "...Shadow" fallback | - |
| `CloseSlot/CloseButton` | **TextButton** (Coral, stroke CoralStroke) | 1618,71 136x136 | Close (X) | close() |
| `CloseButton/CloseGlyph` | TextLabel | - | "X" | Static |

`HeaderRule` is a Frame at 166,242, 1588x4 (rule line).

### Left column: `PageContent/Playtime` (no list layout; children at fixed positions)

| Lookup | Class | Rect | Shows / does | Data |
|---|---|---|---|---|
| `PlayStrip` | Frame (TileHi, r .125) | 166,270 521x96 | Chip 1 | - |
| `PlayStrip/Label` | **ImageLabel** | 190,308 325x22 | Baked "ACTIVE PLAY TODAY" | Static |
| `PlaytimeReadout` | TextLabel, RobotoCondensed Heavy | 532,298 131x41 | "12:40" | `Daily.PlaytimeSeconds`, formatted with `formatSpan`, only if `Daily.Day == Daily.Today`, else 0 |
| `CountdownStrip` | Frame (TileHi) | 703,270 441x96 | Chip 2 | - |
| `CountdownStrip/Label` | **ImageLabel** | 729,308 168x22 | Baked "RESETS IN" | Static |
| `ResetCountdown` | TextLabel, RobotoCondensed Heavy | 915,298 205x41 | "07:12:55" | `Daily.SecondsToReset`, re-anchored on `workspace:GetServerTimeNow()` on every push. Ticks at 1 Hz while open (`formatClock`). At 0 it calls refreshProfile |
| `ProgressTrack` | Frame (TileHi, r .5) | 166,382 960x16 | Bar | - |
| `ProgressTrack/Fill` | Frame (IconTeal) | 166,382 347x16 | Fill. 347/960 = 760 s / 2100 s | `Size.X.Scale = clamp(played / (lastMilestone.Minutes*60))` |
| `Tick5`, `Tick15` | Frame (cream) | x 301 / 575, 4x16 | Milestone ticks, centred on Minutes/35 | Position X = Minutes/lastMinutes. Named by minutes, so a config with other milestones has no tick |
| `ProgressCaption` | TextLabel, Montserrat SemiBold, sage | 166,413 467x25 | "2:20 to the 15 minute reward" | Next milestone: `formatSpan(next - played) .. " to the " .. min .. " minute reward"`, else "Every milestone reached today." |
| `Milestone5/15/35` | Frame (Tile 22,29,32, stroke Line, r .092) | 166 / 494 / 822, y 460, 304x482 | Card, inside `Milestones/Items` (horizontal list) | `Config.DailyRewards.Milestones`. The name is `"Milestone"..Minutes`, the legacy name |
| `<card>/Threshold` | TextLabel, RobotoCondensed Heavy, IconTeal | card-local 95,30 115x35 | "5 MIN" | `Minutes .. " MIN"` |
| `<card>/Art/RewardIcon` | ImageLabel (Fit) | card-local 88,87 128x128 | Reward art. **Placeholder in all three** | By Reward Kind/Key, as in the legacy `REWARD_ART`: Tokens `93116899475472`, SpeedPotion `120211340805188`, EntityShield `126728249949579` |
| `Milestone5/RewardName` | **ImageLabel** | card-local 57,234 189x66 | **Baked "1 Research Token"** (two lines) | Must become text: see section 5 |
| `Milestone15/35/RewardName` | TextLabel, Montserrat ExtraBold, cream, **TextWrapped false** | card-local 16,228 272x80 (a two-line box) | "1 Speed Potion" / "1 Entity Shield" | `rewardLabel(Config, reward)`, from the legacy page |
| `<card>/ClaimSlot/BuyShadow` | Frame + UIShadow | card-local 16,327 272x136 | Hard shadow. **Hidden in 15 and 35** | Shown only for CLAIM (Binder.style shadow) |
| `<card>/ClaimSlot/ClaimButton` | **TextButton** | card-local 16,319 272x136 | Claim / state face. 5: cream, stroke 185,176,156. 15/35: TileHi, stroke Line | State machine below |
| `<card>/ClaimButton/State` | TextLabel. 5: Montserrat Heavy, Tile ink. 15/35: ExtraBold, sage | 5: 139x29. 15/35: 187-206x23 | "CLAIM" / "2:20 TO GO" / "22:20 TO GO" | `Daily.Claimed[tostring(min)]`, pending, and played against `min*60` |
| `StatusLine` | TextLabel, Montserrat SemiBold, sage | 166,962 598x31 | "Only time in an active round counts." | Static note. The legacy code also writes status messages here (`showStatus`) |

**The claim state machine** (legacy page `render`, styles from the `Binder.style` table):

| State | Condition | State text | Look | Active |
|---|---|---|---|---|
| Claimed | `Daily.Claimed["<min>"] == true` | CLAIMED | `owned` (OwnedFill / RailTeal, no shadow) | false |
| Pending | A claim is in flight | CLAIMING... | `off` | false |
| Ready | played >= seconds | CLAIM | The template's cream face plus BuyShadow (≈ `equip`) | true |
| Locked | Otherwise | m:ss TO GO | `off` | false |

- A press sends `ZyntraAction:FireServer("ClaimPlaytimeReward", {Minutes = min})`.
- Only one claim is in flight per key.
- After 6 s with no answer, the client re-reads the profile (`refreshProfile`).

### Right column: `PageContent/Research/Items/...` (vertical UIListLayout, LayoutOrder, Padding 0.0299 = 16 px)

| Lookup | Class | Rect | Shows / does | Data |
|---|---|---|---|---|
| `SectionHeader/ResearchHeading` | TextLabel, Montserrat Heavy, cream | 1158,279 375x29 | "DAILY RESEARCH" | Static |
| `SectionHelperRow/SectionBar` | Frame (IconTeal) | 1158,344 48x8 | Accent | - |
| `SectionHelperRow/SectionHelper` | **ImageLabel** | 1223,338 362x22 | Baked "SOLO · NO PURCHASES". Allowed: no "//" | Static |
| `ResearchFuse` / `ResearchLever` / `ResearchClear` | Frame (Tile, stroke Line) | y 382 / 516 / 688. 596x118 / **156** / 118 | One row per goal. LayoutOrder 2/3/4. Each holds an **`Items` wrapper** (horizontal list: Done, Info, Reward) | `Daily.Research[i]` = `{Key, Title, Detail, Reward, Complete}`. Row name = `"Research"..Key`, the legacy name |
| `<row>/Done` | Frame (r .278). Done: RailTeal. Not done: TileHi | 72x72 | Progress chip | `Complete` |
| `<row>/Done/Value` | TextLabel, RobotoCondensed Heavy. Done: Tile ink. Not done: sage | 59x34 | "1/1" / "0/1" | `Complete and "1/1" or "0/1"` |
| `<row>/Info/Name` | TextLabel, Montserrat ExtraBold, cream, Left | 371x38 (one line) | "Restore power" / "Open the route" / "Return with research" | `Title`. The server strings equal the samples |
| `<row>/Info/Detail` | TextLabel, Montserrat SemiBold, sage, Left. **Lever only: TextWrapped true, YAlign Top** | Fuse/Clear 371x38 (one line), Lever 371x76 (two lines) | "Insert a fuse in Level 1." / "Pull a powered lever in Level 1." / "Escape any level alive." | `Detail`: **longer at runtime** (section 4) |
| `<row>/Reward/TokenGlyph` | Frame x3 | 32x43 | Token glyph | - |
| `<row>/Reward/Amount` | TextLabel, RobotoCondensed Heavy. Done: RailTeal. Not done: IconTeal | 43x31 | "+1" / "+1" / "+2" | `"+" .. Reward` |

## 3. Frames where a button is needed

- **Wheel row with SPIN: missing entirely** (section 6). It needs a hit covering the whole row, as `WheelLink_button` was in Figma.
  - The design row is 120 px tall. At 844x390 that is **39.1 px, under the floor.**
  - The design `SpinChip` is 150x80, which is 26 px.
  - **The hit must be at least 136 design px tall.**
- **Existing controls are already buttons:**
  - `AddTokens`: the design page wires it to the token packs. When grafted, the "+" was hidden ("no dead +").
    - As a native L4 window it can close Daily and then call `PlayerScripts.ZyntraShopUIOpen:Invoke("Shop", "Tokens20")`, the same call the lobby pill makes.
    - The alternative is to hide it. This is an owner/main-session decision.
  - `CloseButton` and the 3x `ClaimButton`.
- **Display only:** the chips, the progress bar, the research rows and the TokenPill. They need no button.

## 4. Runtime text longer than the import sample

These are the `fitLine` and `settle` consequences.

| Node | Sample | Runtime | What happens / fix |
|---|---|---|---|
| `TokenCount` | "37" | "1250", "--" | `TokenLabel` (an image) sits 16 px to the right, and the pill has 18 px of slack before `AddTokens`. fitLine cannot widen the box, so it shrinks the text (digits go down to the 11 px floor). The shop's own pill accepts the same shrink |
| `PlaytimeReadout` | "12:40" | "0:00" to "59:59", then "1:05:12" | 24 px of slack to the strip edge; beyond that it shrinks. **Do not carry over the legacy suffix "  //  COUNTING"** (rule 4) |
| `ResetCountdown` | "07:12:55" | Always hh:mm:ss; "--:--:--" before the first push | Same length. **Drop the legacy suffix "· 00:00 UTC".** |
| `ProgressCaption` | 28 chars | "12:20 to the 35 minute reward" (29), "Every milestone reached today." (30) | The box is 467 px of a 960 px row with nothing beside it, so fitLine widens it. Fine |
| `Milestone15/35/RewardName` | "1 Speed Potion" | `rewardLabel`, for example "1 Research Token" or "2 Speed Potions" | The box holds two lines, but **TextWrapped is false**. The export renamed `RewardName_txt` to `RewardName`, which dropped the `_txt` tag, and `RewardName` is not in Binder's `MULTILINE`. **Set `TextWrapped = true` before `scaleText`** so the label is solved as a two-line box and settle is its backstop |
| `<card>/State` | 5: "CLAIM" (big). 15/35: "2:20 TO GO" (small) | Every card cycles through m:ss TO GO, CLAIM, CLAIMING..., CLAIMED | **The size follows the card, not the state.** `scaleText` solves non-sample text as `FigmaFontSize*k*em` of that node, so a 15 MIN card showing CLAIM is drawn small and the 5 MIN card's "4:59 TO GO" is drawn big. Fix: per state, copy `FigmaFontSize` and FontFace from the authored sample (CLAIM type from `Milestone5/State`, TO GO type from `Milestone15/State`) before writing Text. "CLAIMING..." widens inside the 272 px face; fitLine never moves a button face |
| `ResearchFuse/Detail` | "Insert a fuse in Level 1." (25) | Server: "Personally insert a fuse in Level 1." (36) | The box is **one line** (38 px, not wrapped). fitLine cannot widen it (it already fills Info), so it shrinks to 60% and then **truncates** |
| `ResearchLever/Detail` | "Pull a powered lever in Level 1." (32) | Server: "Personally activate a powered lever in Level 1." (47) | Two-line box; probably needs three lines. settle shrinks it by up to 6 px |
| `ResearchClear/Detail` | "Escape any level alive." | Same | OK |
| `StatusLine` | The note | Legacy messages, e.g. "Could not load the Zyntra profile." | Shorter or equal. Fine |

**Research Detail copy is a decision.** The Figma copy drops "Personally". `Detail` is display-only: the server grants by `Key` and `Reward`. The options are:
- (a) Align `ZyntraDailyResearch.Goals[].Detail` with the Figma copy. This keeps one source and keeps the rows at design height.
- (b) Bind the Figma copy by `Key` on the client.
- (c) Keep the server strings and grow the Fuse and Lever rows.

## 5. Text baked as images

Six visible strings are ImageLabels, so code can never change them:

| Node | Text | Status |
|---|---|---|
| `Eyebrow` | "ZYNTRA // DAILY" | **Must go.** Either hide it and add a TextLabel "ZYNTRA DAILY" (RobotoMono, teal, in the 303,90 286x23 slot; Roblox text has no letter-spacing, so it reads tighter than Figma), or re-import |
| `TokenLabel` | "TOKENS" | Static. Fine |
| `PlayStrip/Label` | "ACTIVE PLAY TODAY" | Static. Fine |
| `CountdownStrip/Label` | "RESETS IN" | Static. Fine |
| `SectionHelper` | "SOLO · NO PURCHASES" | Static. Fine |
| `Milestone5/RewardName` | "1 Research Token" | **Data-bound text.** Hide it, clone `Milestone15/RewardName` into Milestone5 with the same card-local rect (16,228 272x80) and ZIndex, set TextWrapped true, then set its Text from `rewardLabel` |

## 6. Missing compared with the owner's screenshot (52:2164)

| Owner item | In the template? |
|---|---|
| Eyebrow "ZYNTRA DAILY" | Present, but the **wrong text** (baked "ZYNTRA // DAILY") |
| Gift icon | Slot present (`HeaderGift`); **placeholder image** |
| Token pill "37 TOKENS" + "+" | Present. The pill is 447x150 and the "+" is 136x136, grown from the design's 456x112 and ~96 for the tap floor |
| Coral X | Present (`CloseButton` 136 px + `CloseShadow`) |
| Two chips | Present. Labels are images; values are TextLabels |
| Progress bar + ticks | Present (`Fill`, `Tick5`, `Tick15`) + `ProgressCaption` |
| Three cards: art + reward line + button | Cards and buttons present. **All three icons are placeholders.** Milestone5's reward line is an image. No CLAIMED badge (it was hidden in Figma); CLAIMED has to be a `State` text |
| Note "Only time in an active round counts." | Present (`StatusLine`) |
| DAILY RESEARCH + helper + 3 rows | Present |
| **LUCKY WHEEL row: icon, "FREE SPIN READY", SPIN** | **Absent** |

**The wheel row in the design** is `WheelLink_button` in Research_list: 596x120 at y 552, teal stroke. It holds:
- `CategoryIcon` 80x80 at 20,20.
- `Info` 294x74 at 116,23, containing `Name` "LUCKY WHEEL" (248x38) and `Hook` "FREE SPIN READY" (288x36, mono teal).
- `SpinChip` 150x80 at 426,20 (teal fill), containing `Label` "SPIN" (102x48).

There are two ways to restore it.

1. **Runtime, with no import and no upload:**
   - Clone `ResearchClear` into `Research/Items` with LayoutOrder 5.
   - Set Size Y to 136/536 = 0.254. The row then ends at y 958, inside PageContent, which ends at 996.
   - `Done`: icon via `Binder.image(Done)`. Hide Value; transparent fill.
   - `Info/Name`: "LUCKY WHEEL".
   - `Info/Detail`: the hook. Restyle it teal and mono; it is one line.
   - `Reward`: hide `TokenGlyph`. `Amount` becomes "SPIN" on an IconTeal chip; widen `Reward`, which is only 83x52.
   - Add one `Binder.button(row)` hit over the whole row.
   - Icon candidates (not verified in Studio): the rail's wheel icon `rbxassetid://115596488996319` (LobbyRail_L4 `ZyntraWheelButton/Face/Icon`), or the disc `rbxassetid://129978127964602` (LuckyWheel_L4 `WheelDisc`).
2. **Re-export:** put `WheelLink_button` back into 91:331 at 136 px tall and re-import. This would also bake the new eyebrow. It costs a Framewisp conversion (5 a day), and new images need the owner's OK to upload.

**The wheel row's data** is ZyntraStore's `wheelClaimable`:
- A spin is ready when `Daily.WheelDay ~= Daily.Today`.
- A prize is owed when `Daily.WheelLast.Claimed == false`.

In the design prototype, the row's `visible` is bound to `wheelSpinAvailable`. So either hide the row when no spin is ready, or show it disabled. **SPIN:** close Daily first, so that `DailyRewardsOpen` is cleared, then fire `PlayerScripts.OpenLuckyWheel`. Lucky Wheel Client refuses to open while any screen-owning modal is up.

## 7. Hidden panels and `Items` wrappers

- **Hidden at import:** only `Milestone15/ClaimSlot/BuyShadow` and `Milestone35/ClaimSlot/BuyShadow`. They are the locked state, and `Binder.style` owns their Visible. Nothing needs `Binder.reveal`.
- **`Items` wrappers** (each holds a UIListLayout with SortOrder LayoutOrder and Scale padding):
  - `DailyRewardsPanel/Items`, vertical: RewardsHeader 1, HeaderRule 2, PageContent 3.
  - `RewardsHeader/Items`, horizontal: HeaderGift, TitleBlock, TokenPill, CloseSlot.
  - `Milestones/Items`, horizontal: the three cards.
  - `Research/Items`, vertical: SectionHeader, then the three rows. **A new row goes here.**
  - `ResearchFuse|Lever|Clear/Items`, horizontal: Done, Info, Reward.
- **No layout:** `PageContent`, `Playtime`, `TokenPill` and `Info`. Their children sit at fixed positions.

## 8. Tap targets at 844x390

The touch fit is the panel at 332 px tall, so k = 0.3255.

| Target | Design px | Phone px |
|---|---|---|
| CloseButton, AddTokens, ClaimButton | 136 | **44.3** (pass, only if the fit box is the panel and not the modal) |
| A wheel row at the design's 120 | 120 | 39.1 (fail) |
| A wheel row at 136 | 136 | 44.3 (pass) |
| SpinChip alone | 80 | 26.0 (fail): never make it the only hit |
