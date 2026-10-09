# Legacy RECORDS / SETTINGS: end-to-end map (2026-10-07)

Read-only map of what the legacy terminal does today, so the L4 pages (BINDINGS.md) can replace it and
the terminal can be deleted. Line numbers are for these working-copy files:

| File | sha256 (12) | Lines |
|---|---|---|
| `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` | 74ee23540b22 | 2190 |
| `ReplicatedStorage/ZyntraRecordsPage.ModuleScript.lua` | 497b4f448494 | 360 |
| `ReplicatedStorage/UIRegression.ModuleScript.lua` | 7075ea19ac95 | 9240 |

`Zyntra Shop L4` (mirror and draft are byte-identical, 1573 lines), ShopData and ShopBinder (mirror == draft) were
read as they are now.

---

## 1. ZyntraRecordsPage (RECORDS tab)

**How it is mounted.** ZyntraStore L654 `TERMINAL_PAGE_MODULES = {Records = "ZyntraRecordsPage"}`. The tab is built
only if the ModuleScript is in ReplicatedStorage (L656-661, FindFirstChild). The mount block is L1300-1356. It does
`require(module).mount(pages.Records, ctx)`, pcall'd, and on failure it warns `"[ZyntraStore] ZyntraRecordsPage
failed to mount"`. `ctx` carries: player, Config, UIStyle, UIDevice, COLORS, label, button, corner, outline, action,
`profile()`, `onProfile(fn)`, refreshProfile, showStatus, registerLayoutHook, isVisible, contract and pageName.
The page uses profile, onProfile, registerLayoutHook, contract, label, button, corner, Config, UIStyle and COLORS. It
never calls `ctx.action`, so **the page sends nothing to the server**.

**Data.**
- `profile = ctx.profile()` is ZyntraStore's local copy of the public profile.
- `rows = Challenges.Rows(profile.Records, profile.Challenges, Config.Challenges)` (L211).
  - `ZyntraChallenges` is required with FindFirstChild + assert at L29.
  - It is a pure module, shared with the server: `ZyntraMonetization` L238, applied in the clear transaction at L4173.
- One row per `Config.Challenges.Levels = {1, 2, 3, 4}`. Each row is `{Level, TimeGoal, NoDeath, TimeGoalDone,
  Records = {["solo:clean"], ["solo:assisted"], ["party:clean"], ["party:assisted"]}}`.
  - Each record is `{Best (tenths), Equipped, At}`, or nil.
  - The server keys are `"<level>:<mode>:<condition>"`, built by `Challenges.Key`.
- The public profile carries `Records`, `Challenges` and `LevelsCleared` (ZyntraMonetization L1021-1024).
  - An older server sends neither field. `Rows()` reads that as "no record, nothing done", which is also what a new
    player sees.
- Config (ZyntraConfig L342-354):
  - `TimeGoalSeconds = {["1"]=480, ["2"]=600, ["3"]=600, ["4"]=720}`, so the goals read 8:00, 10:00, 10:00, 12:00.
  - `RewardTokens = {NoDeath = 3, TimeGoal = 3}`.
  - `HiddenUntilPlayed = {}`.
- Page fallback when `Config.Challenges` is missing: `{Levels = {1,2,3}, TimeGoalSeconds = {}, RewardTokens = {}}`
  (L96-97). It is dead in practice, because the config ships with the block.

**FormatTime** (ZyntraChallenges L74-77):
- Rounds to whole seconds with `floor(x + 0.5)` and formats `"%d:%02d"`. There are no tenths and no hours, so
  599.9 reads "10:00" and the maximum reads "1439:59".
- The stored `Best` is in tenths. Display rounds it. Goal checks on the server use the tenths value
  (`seconds <= goal`).

**Assisted / clean views.**
- `showAssisted` is client-local and starts false. It lives as long as the mount, which is the whole session, and
  survives profile pushes.
- `condition = showAssisted and "assisted" or "clean"` (L216).
- Clean means no Emergency Re-entry and no consumable aid (`run.Revived ~= true and run.Aided ~= true`, Challenges
  L101). GameManager sets `Revived` (re-entry, L2927/L3155) and `Aided` (`ZyntraRunAided`, L3156).
- Legacy UI:
  - The toggle text flips between "SHOW ASSISTED" and "SHOW CLEAN".
  - `ModeReadout` reads "CLEAN RUNS" or "ASSISTED RUNS".
- Figma v2 changes this: a static "SHOW ASSISTED" label with a Track/Knob switch, and the Eyebrow carries the mode.
- Challenges are clean-only by definition, so the challenge lines do not change with the view.

**Times.** For each mode (solo, party):
- `record = row.Records[mode .. ":" .. condition]`.
- Text is `FormatTime(record.Best)`, or "\u{2014}" (em dash) when there is no record.
- Colour is ink when a record exists and muted when it does not (L222-224).

**The Equipped flag.**
- `tag.Visible = record ~= nil and record.Equipped == true` (L225), one tag per time row, text "EQUIPPED".
- Meaning: the run had a paid permanent upgrade. GameManager L2790 sets it as
  `Equipped = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true`, read at the run's start.
- The flag belongs to the record that set the best time. A later faster run overwrites both `Best` and `Equipped`.

**Challenge done flags** (L190-196, L227-230):
- NO DEATHS uses `row.NoDeath`. "UNDER m:ss" uses `row.TimeGoalDone`.
- The goal line is hidden when `row.TimeGoal == nil`.
- Legacy state text: done reads `"\u{2713} DONE"` in `UIStyle.Color.Positive`. Not done reads `tokens(reward)` in gold.
  - `tokens()` gives "+3 TOKENS", or "+1 TOKEN" for a reward of one (L76-79).
- Figma differs: the reward is always shown, and a separate chip reads DONE or NOT YET.
- Writer: `Challenges.Apply` inside the clear transaction. It pays once per flag and returns player messages ("New
  solo record, Level 2: 9:58.", "Challenge complete: ..."), which are pushed as the profile message.

**Level list including Level 4.**
- The cards are built once at mount from `settings.Levels`, named `Level1` to `Level4`.
- Card visibility (L198-215): a level listed in `HiddenUntilPlayed` stays hidden until `played(profile, row)` is true:
  - `LevelsCleared[tostring(level)] == true`,
  - or NoDeath,
  - or TimeGoalDone,
  - or any record.
- The list is empty today, so all four cards always show. A hidden card takes no layout room (L287).

**Refresh triggers.** `render()` runs on:
1. mount (profile may still be nil, which draws dashes and the rewards on offer);
2. `handle.refresh()` from ZyntraStore `refreshUI()` (L1160-1165), on every `ZyntraProfileChanged` (L1358), the
   initial `ZyntraGetProfile` (L1367), `ctx.refreshProfile` and the rail-dot UTC-reset re-read (L1190-1200);
3. the `ctx.onProfile` subscriber via `publishProfile` (L1172) on the same events. **So every push renders twice**;
   it is harmless;
4. a toggle press.

Layout re-runs from `registerLayoutHook` on every `applyTerminalLayout` (`UIDevice.Changed`).

**Published for UIRegression:**
- `contract.scroll("Records", scroll)` registers scroll "Records".
- `contract.card("Records", "View", header, toggle)` registers the ViewToggle. It is tagged `ZyntraTerminalAction` and
  is the page's only control (`Fit.ZyntraExpectedActive.Records = 1`).
- `PAGE_CONTENT.Records = {Rows = 5, Actions = 1}`.

**Static copy reused by Figma:** NOTE = "Personal bests for each level. CLEAN: no re-entry, no consumables. EQUIPPED:
set with a paid upgrade. Challenges pay tokens once." (L56-57).

---

## 2. SETTINGS tab in ZyntraStore (L708-950, one `do ... end`)

**Rows.**
- From `Config.AccessibilitySettings` (ZyntraConfig L366-405), skipping `Hidden = true`.
- Each row is `{Key, Label, Description, Default}`:

| Key | Label | Default | Row |
|---|---|---|---|
| LobbyMusicEnabled | Lobby music | true | yes (special case, below) |
| ReduceCameraShake | Reduce camera shake | false | yes |
| ReduceFlashing | Reduce flashing lights | false | yes |
| CaptionsEnabled | Show captions | true | yes |
| DisableCaptions | Hide captions | false | **no** (Hidden; the server still accepts and persists it) |

- **Fallback** (L747-768) applies when the config list is empty. It draws two `Local = true` rows (ReduceCameraShake,
  ReduceFlashing) that also write the attribute locally. That path is dead while the config ships with the list.
- Legacy row shape:
  - Frame `<Key>` holding `RowTitle`, `Description` and a TextButton `Toggle`.
  - The toggle text is "ON" (accent) or "OFF" (muted).
  - Registered with `contract.card("Settings", Key, row, toggle)`, so each Toggle is tagged.
  - Scroll `AccessibilityRows` is registered with `contract.scroll`.

**State and readback.**
- `currentValue()` (L821-831): `entry.Pending` if set, otherwise `player:GetAttribute(Key)`. Before the profile loads
  the attribute is nil, which falls back to `entry.Default`.
- The server publishes every key:
  - as a player attribute, at profile load and after every accepted change (ZyntraMonetization L1153-1154,
    `applyAttributes`);
  - in the public profile (`result[Key]`, L1043-1044).
- Attribute readers include:
  - LobbyMusicController (LobbyMusicEnabled);
  - EntityShakeController, JumpscareUI and the Pool Foam client (ReduceCameraShake);
  - Level 3 and 4 Lighting, Lucky Wheel, RoundUI, the Zyntra Shop L4 wheel skin and many others (ReduceFlashing);
  - the Pool Foam client and the Level 4 Round Client (CaptionsEnabled / DisableCaptions).

**What a tap sends** (`requestToggle`, L852-879):
1. LobbyMusicEnabled only: return if its attribute is not yet a boolean.
2. `wanted = not currentValue()`, then `entry.Pending = wanted` and `entry.Serial += 1`, then `refresh()`. This is the
   optimistic redraw.
3. Fallback rows only: `player:SetAttribute(Key, wanted)`.
4. `actionRemote:FireServer("SetAccessibility", {Key = entry.Key, Enabled = wanted})` on `Remotes.ZyntraAction`.
5. `task.delay(12, ...)`: if no newer press happened and the press is still pending, clear Pending and redraw from the
   attribute. This is a silent revert.

The attribute-changed listener (L891-896) clears Pending when the attribute equals Pending (or Pending is nil), then
redraws. Pressing again while pending is simply the opposite request. The control never stands down; only the music
row disables, and only before load.

**Server side** (ZyntraMonetization, server untouched):
- L3880-3883 and L3901: per-key window `"SetAccessibility:<Key>"` of `WRITE_ACTION_WINDOW = 1` s. Presses inside it are
  **dropped silently**, and unknown keys share one bucket.
- L3993-4008:
  - The payload must be `{Key: string, Enabled: boolean}` and the key must be in the config list.
  - **Idempotent:** an unchanged value returns with no attribute write and no push.
  - Otherwise it writes `session.data.Settings[Key]` and calls `queueAccessibilityWrite`.
    - That is one coalesced DataStore write behind `ACCESSIBILITY_WRITE_FLOOR = 6` s (L3152-3203).
    - It is re-asserted over unrelated profile writes (`reassertPendingAccessibility`) and flushed on leave.
  - Then `applyAttributes` and `pushProfile(player, Label .. ": on|off", "success")`.

**Known legacy edge.** ON then OFF inside 1 s: the second press is dropped by the server window. The attribute then
lands on the first value, which is not equal to Pending, so the row shows the dropped value for up to 12 s and then
snaps back. ShopData's `sendAction` avoids this by holding a press until the window has passed (`WRITE_WINDOW = 1.1`);
the L4 row should do the same.

**LobbyMusicEnabled special case and the shared MUSIC rail button.**
- The rail button `ZyntraMusicButton` (L346-351) is created `Active = false`. Its state is driven **only** from the
  LobbyMusicEnabled row's `refresh()` (L840-850):
  - `ready = type(attr) == "boolean"`;
  - `musicButton.Text` is "Mute music", "Unmute music" or "Loading music";
  - `SectionCaption.Text` is "Mute" when on, "Unmute" when off and "Music" while loading. Colour is accent when ready,
    muted otherwise;
  - `UIDevice.SetEnabled(toggle, ready)`, so the Settings row is disabled until load;
  - `UIDevice.SetEnabled(musicButton, Visible and ready and not InRound and not ScreenOwningModalOpen())`.
- `musicButton.Activated` (L882-888) calls **the same `requestToggle`** (same `entry.Pending` and `Serial`) when
  Visible, Active, not InRound and no screen-owning modal is up.
- Rail visibility changes re-run `refresh()` (L889).
- `updateVisibility` (L1555-1560) sets `SetInteractive(musicButton, railAvailable)`, then forces Active and
  Selectable to false while the attribute is not boolean.
- The L4 rail graft (`Zyntra Shop L4` L1264-1268) mirrors `string.upper(SectionCaption.Text)` into its own Label, so
  the grafted rail reads MUTE, UNMUTE or MUSIC from this writer.
- Today the row and the rail can never both be pressable:
  - While the terminal or the L4 shop is open, `ZyntraStoreOpen` is set, which makes `ScreenOwningModalOpen()` true,
    which takes the rail out of the input stack.
  - They share one server window, `SetAccessibility:LobbyMusicEnabled`.
- The only thing actually shared is the optimistic `Pending`.

**How LobbyMusicEnabled is set.**
- There is no separate path. It is an AccessibilitySettings key like the other three:
  `SetAccessibility {Key = "LobbyMusicEnabled", Enabled = b}` goes to the server, which publishes the attribute.
- LobbyMusicController (`shouldPlay`, L108-112) plays only when the attribute `== true`, so nil never plays. It listens
  on `GetAttributeChangedSignal("LobbyMusicEnabled")`.

**Layout.**
- A layout hook per row (L905-948), stacked when `fit.DevStacked` (content width < 460).
- The tap height is `max(fit.Tap, 36)`, where `fit.Tap` is 44 on touch and 32 on a pointer.
- Descriptions wrap and the row grows. There is no fitting work worth porting; the Figma rows are fixed.

---

## 3. The rest of the terminal shell (ZyntraStore)

| What | Where | Fate |
|---|---|---|
| `main` Frame "Terminal" (1180x760 design) and UIScale | L449-461 | delete |
| `layoutHooks`, `pageMounts {Handles, Subscribers}` | L467-474 | delete |
| `contract {Tag = "ZyntraTerminalAction", Cards, Scrolls}`, `main:SetAttribute("TerminalActionTag")`, CollectionService tag | L501-523 | delete |
| TextService helpers and `TEXT_FIT_SLACK` (terminal layout and settings rows only) | L528-544 | delete |
| Header: TerminalTitle "ZYNTRA RESEARCH", TerminalSubtitle "EQUIPMENT DEVELOPMENT TERMINAL", TokenReadout "TOKENS n", CloseTerminal | L550-569 | delete (L4 has Title, TokenCount and Close) |
| TerminalTabs ScrollingFrame and tab buttons, TerminalContent, TerminalStatus plus `showStatus` | L576-619 | delete, **but keep a `showStatus`**, see below |
| `pages`, `tabButtons`, `selectTab`, `currentTab = "Settings"` (L33), `TERMINAL_PAGE_MODULES`, `tabNames`, tab-bar layout hook | L621-706 | delete |
| SETTINGS do-block | L708-950 | delete the page; **move the music-button logic** (section 2) |
| `refreshUI()`: TokenReadout plus the page refresh loop | L1151-1166 | reduce to `updateReentry()` (keep the name: the tests slice up to `local function refreshUI()`) |
| `publishProfile` / Subscribers (only RECORDS subscribes) | L1168-1177, also called at L1198, L1338, L1363, L1374 | delete |
| Page-mount do-block | L1288-1356 | delete |
| `setMainVisible`: publishes `ZyntraStoreOpen = main.Visible or nil`, `UIDevice.SuppressTouchMovement(ScreenOwningModalOpen())`, keeps CloseTerminal interactive, re-runs `updateVisibility` (re-entrance latch `refreshingVisibility`) | L1380-1430 | delete. `ZyntraStoreOpen` stays the L4 shop's flag (`ui.setOpen`, plus its re-assert at L4 1465-1474) |
| `terminalNavigation`: gamepad focus on the current tab (scrolls the tab bar to reveal it), CAS `ZyntraCloseTerminal` on ButtonB at High priority (passes while the Roblox menu or a TextBox has focus), restores the previous selection on close | L1432-1510 | delete. L4 has `CLOSE_ACTION` and `ui.focus`, see section 5 |
| Terminal terms in `updateVisibility` | `blockedByModal and main.Visible then setMainVisible(false)` L1521-1523; `and not main.Visible` L1537/1543/1545/1551; `if inRound then setMainVisible(false)` L1719 | remove those terms only. `ScreenOwningModalOpen()` already covers the L4 window |
| `InRound` handler `setMainVisible(false)` | L1723-1727 | keep `updateVisibility()` only |
| Initial `setMainVisible(false)` | L1745 | delete |
| `toggleDevMenu` tail: "J closes an open RECORDS/SETTINGS terminal" | L1762 | delete. J while the L4 window is open then does nothing, since Dev L4 refuses over a modal; that is the same as any other L4 tab today |
| `openTerminal(tab)` guards: not InRound, not `modalBlocksStore()`, not over another screen-owning modal unless already open | L1799-1806 | delete. `ui.openShop` has the same guards |
| `openKioskShop` line `if type(tab) == "string" and pages[tab] then return openTerminal(tab) end` | L1822 | delete. Records and Settings then flow to `ZyntraShopUIOpen:Invoke(tab)` like every other name |
| Close triggers: CloseTerminal, Escape (L1917), Humanoid.Died (L1922-1932), Escaped (L1933), RoundActive false while InRound (L1936) | L1912-1940 | delete. L4 has all of them (L4 1476-1507, Escape and ButtonB in `ui.setOpen`) |
| `applyTerminalLayout` and its published attributes (`TerminalHeaderStacked/Compact/TapFloor/SubtitleShown/ModalWidth/ModalHeight/ContentHeight`); constants `STORE_DESIGN_*`, `MIN_*` | L1942-2142, L2148 | delete. Keep `UIDevice.Changed:Connect(updateVisibility)` |
| Studio probe `UIRegressionZyntraStoreProbe` (on the ZyntraStore gui) | L1844-1882 | shrink to `kiosk` (the QA probe client and BriefingExclusionMatrix use it). Have unknown actions return false, or delete the probe and rewrite its users (section 4) |

**Keep in ZyntraStore** (not terminal):
- the rail and its fit ladder;
- RAIL_DOTS and the REWARDS_INTRO card (L1204-1286). Drop `not main.Visible` from `introConditions` L1256: the L4
  window already counts through `ScreenOwningModalOpen()`;
- the re-entry modal, its live price, DEV FREE RESPAWN and the PARTY DOWN attributes;
- `lobbyModalOpener` (OpenDailyRewards / OpenLuckyWheel);
- `openKioskShop` and the BindableEvent `PlayerScripts.ZyntraOpenTerminal` (L1833-1838);
- J / DevPhoneCommand -> `ZyntraDevUIOpen`;
- the `ZyntraShopBuy` bridge;
- the profile fetch and push (re-entry credits, dots, intro);
- the music-button logic.

**`showStatus` after deletion.** The re-entry modal still calls it:
- "Emergency Re-entry Product ID is not configured yet." (L1016);
- "Developer controls are still loading. Try again." (L1117);
- "Could not load the Zyntra profile." (L1376);
- every push message (L1364).

Today every one of these lands in the terminal's status line. The terminal never shows in a round, so the re-entry
errors are **already invisible to the player**. Push messages already reach L4: `ShopData.Message` -> `ui.showMessage`
gives a status line and a toast while the window is open. A one-line `warn` stand-in is enough.
`test_reentry_dismissal` asserts that `showStatus` is called once for the unconfigured product; the test defines its
own `showStatus`.

**Intro card:** `RewardsIntroCard` is a rail note, not part of the terminal. It stays.

**Who calls `PlayerScripts.ZyntraOpenTerminal`:**

| Caller | Tab | Today |
|---|---|---|
| Zyntra Shop L4 `ui.handoff` (L165-173), from header `Records` / `Settings` (L1039-1043) | "Records", "Settings" | closes L4 (`ui.setOpen(false)`), fires the event, ZyntraStore opens the terminal on that tab |
| Nobody live | "Rewards" | `openKioskShop` routes it to `OpenDailyRewards`. The Daily plaque prompt that used it is gone (Shop v4, 2026-09-16); "Zyntra Daily L4" names it in a comment only (L15) |
| Tests and QA | all | `test_zyntra_store_compact` routing; L4 harness `ctx.Terminal` (L663-666); `install/05_qa_probe_client.luau` emulation |

Keep the event as the public "open the shop on tab X" route. Once the L4 pages bind, `ui.handoff` is unused. The
frozen daily test needs `'if tab == "Rewards" then\n\t\topenDailyRewards()'` verbatim in ZyntraStore, plus
`local openDailyRewards = lobbyModalOpener("OpenDailyRewards")` and
`rewardsButton.Activated:Connect(function() openDailyRewards() end)`.

---

## 4. Everything else that depends on the terminal or ZyntraRecordsPage

### UIRegression (ReplicatedStorage)

| Where | What | Action |
|---|---|---|
| `resetScenario` L1070-1082 | closes the terminal through the store probe (`close`), else `terminal.Visible = false` | both nil-safe; simplify |
| Scenario `store-modal` L1387-1411 | Requires `Terminal/TerminalHeader/TerminalTabs/TerminalContent/TerminalStatus`, TouchTargets `TerminalHeader.CloseTerminal`, Forbids the 5 rail buttons; opens via probe `open` + `tab:Settings` + `relayout` | **rewrite** to the L4 window on Settings (`UIRegressionZyntraShopL4Probe` `open:Settings`). New owner rule: the terminal is deleted |
| `PAGE_CONTENT` L1820-1834 (`Settings {2,2}`, `Records {5,1}`) | terminal fit matrix only | delete |
| `Fit.borrow` L2352-2362, L2388-2390; `Fit.restore` L2400-2403; residue L2549-2575 | snapshots and restores `TerminalTab` / `TerminalOpen`; asserts exactly one visible terminal page | delete. Nil-safe if left, but dead |
| `BriefingExclusionMatrix` L4598-5240 | **hard-requires** `ZyntraStore.Terminal` and the probe at L4655-4662 ("the briefing, queue modal, store opener, terminal and Studio probe all exist"); "The full terminal participates" block L4925-5090 (open/close/toggle-during-briefing/queue-over-terminal/movement ownership) uses probe `open`/`close` and `terminal.Visible`; cleanup L5150-5210 compares `terminal.Visible` | **rewrite** to the L4 window as the modal under test (`open:Records`). Otherwise the whole lane fails once `Terminal` is gone |
| `Fit.ZyntraFloorFallback`, `Fit.ZyntraDisabledCaptions`, `Fit.ZyntraExpectedActive`, `zyntraDisabledReason/zyntraActions/parseZyntraCards/zyntraActionProblems` L5260-5445; `bodyZyntraTerminalFitMatrix` L5446-~6206; `UIRegression.ZyntraTerminalFitMatrix` L6208; its call in RunAll L9088-9090 | the per-device terminal sweep (tab set, card index, tagged actions, Settings row count from config, no Hidden row, CloseTerminal reachable, shell rects) | **delete**. Nothing else uses these helpers. There is NO L4 fit lane in UIRegression (Zyntra Shop L4's header comment names a "ZyntraShopL4FitMatrix" lane that does not exist) |
| HarnessLockMatrix L8646, L8735; SafeAreaMatrix L8118 | the `ZyntraStoreOpen` attribute only (label "the Zyntra terminal") | keep; relabel at most |

CLAUDE.md 2026-09-05 records "the terminal fit matrix covers the SETTINGS tab". That coverage dies with the lane; the
L4 harness has to take it over (sections 5 and 6).

### tools/tests

| Test | Dependency | Action |
|---|---|---|
| `test_zyntra_records_page.py` (991 lines) | mounts the real ZyntraRecordsPage through the terminal page contract, with ZyntraStore's helpers sliced by marker | **delete** with the module. Port its semantics to the L4 harness: config numbers (480/600/600/720, +3/+3, Levels {1..4}, HiddenUntilPlayed empty); m:ss and dash; EQUIPPED only beside an equipped record; DONE vs reward; toggle sends nothing and survives a push; older-server profile; synthetic HiddenUntilPlayed hide/reveal; Level 4 card "UNDER 12:00" |
| `test_zyntra_store_compact.py` | section 4 (`STORE_DESIGN_*`, clamp); section 6 tab set (slices `local TERMINAL_PAGE_MODULES = {` .. `for order, name in ipairs(tabNames)`); section 11 routing (slices `-- RECORDS and SETTINGS, the only pages left` .. `-- Studio-only input seam`, fakes `pages/main/selectTab/setMainVisible`, asserts Records/Settings open the terminal and "J over the open terminal closes it") | **rewrite** to the new rule: Records/Settings are asked of the L4 bridge, the terminal does not exist. Delete sections 4 and 6. Keep the rail checks; note `SRC.count("ipairs(railButtons)") == 5` and the `musicButton.Active == false` asserts |
| `test_controller_input.py` | `store_setup/store_logic/store_tests` slice `local updateVisibility\n` .. `function updateVisibility()` (terminal focus, ButtonB `ZyntraCloseTerminal`, tab reveal) | **delete** that part. ButtonB and focus are covered by the L4 harness (L1753, L1790); extend it to the header pages |
| `test_reentry_dismissal.py`, `test_dev_free_respawn_offer.py` | slice `local reentryDead = false` .. `local COLORS =` and `player:SetAttribute("ZyntraReentryOpen", nil)` .. `local function refreshUI()` | unaffected if those four markers survive |
| `test_rail_dots_intro.py` | `RAIL_DOTS_20260922 BEGIN/END`, `REWARDS_INTRO_20260922 BEGIN/END` | unaffected |
| `test_friend_boost`, `test_lucky_wheel_client`, `test_round_exit_hold`, `test_lobby_shop_display` | `ZyntraStoreOpen` as a modal flag; "terminal" only in prose | unaffected |
| `test_daily_rewards`, `test_item_inventory`, `test_leaderboard_backfill`, `test_support_product_receipts`, `test_level4_clear_persistence` | server-side `Config.AccessibilitySettings` / Records normalisation | unaffected (server untouched) |

### L4 artifacts (shop-ui-figma-20261005/roblox-draft)

- `tests/zyntra_shop_l4_harness.luau`:
  - L1159-1161 "RECORDS, SETTINGS and DEV are never L4" and L1723-1728 "RECORDS/SETTINGS hand off to the terminal":
    **rewrite**.
  - L2780 asserts that exactly the five imported pages exist (real dump): extend after the re-import.
  - Section 15 (L2810-2830) emulates ZyntraStore opening the terminal for Records/Settings: update.
  - The real dumps (`framewisp-dump.ZyntraShop_L4.json`, `live-20261007/`) have header `Records` / `Settings` but no
    `Page_Records` / `Page_Settings`. The new pages need a synthetic fixture until a dump of the new import exists.
- `install/05_qa_probe_client.luau` uses the store probe (`kiosk`, `close`, and an unknown action read as
  `main.Visible`). Keep `kiosk` or update it.
- `dev-menu/tests/test_zyntra_dev_l4.py` (frozen) requires ZyntraStore to compile -O0, to contain `ZyntraDevUIOpen`, to
  contain no `"terminal"` string literal and no `table.insert(tabNames, "Dev")`. Do not introduce `"terminal"`.
- `daily/tests/test_zyntra_daily_l4.py` (frozen): the three needles above.

### Other

- `studio-sync-manifest.json` L141-143 has the ZyntraRecordsPage entry. Deleting the module from Studio needs the
  manifest item removed in the same step.
- Docs that describe the terminal:
  - README.md L434 ("Zyntra terminal's SETTINGS tab ... fifth tab");
  - CLAUDE.md L283 and L309;
  - ZyntraMonetization L1022 comment "Read by the terminal's RECORDS page". The server is untouched; leave it or note
    it.
- `Level2AlertClient` L602 names the probe in a comment only.

---

## 5. Delete outright vs move into L4

**Delete outright:**
- `ReplicatedStorage.ZyntraRecordsPage`, its manifest item and `tools/tests/test_zyntra_records_page.py`.
- The ZyntraStore terminal shell and both pages (section 3 table). Of the settings block, everything except the music
  rail logic. The `Local` fallback rows.
- UIRegression: `ZyntraTerminalFitMatrix` and its helpers, `PAGE_CONTENT`, and the terminal snapshot in
  `Fit.borrow/restore/residue`.
- The terminal-only parts of `test_zyntra_store_compact.py` and `test_controller_input.py`.
- `ui.handoff` in Zyntra Shop L4, once both pages bind.

**Keep, unchanged:**
- `ZyntraChallenges` (server ledger).
- `Config.Challenges` and `Config.AccessibilitySettings`.
- The server `SetAccessibility` contract.
- The `ZyntraStoreOpen` modal flag.
- `PlayerScripts.ZyntraOpenTerminal` as a router. Its "Rewards" branch stays verbatim; everything else goes to
  `ZyntraShopUIOpen`.

**Move into L4** (Zyntra Shop L4, with ShopData for the one send):

1. **Pages and header.**
   - Bind `Page_Records` / `Page_Settings` by name.
   - If either is missing: hide that header button, warn once, keep the window working.
   - Hide every `Page_*` not in `ui.pages`. `Binder.all(window, "Page_")` will find the new pages, and an unknown page
     is never hidden.
   - **Do not add Records/Settings to `TAB_ORDER` as-is.** The bind loop calls `need(nil, "Tab_" .. name)`, and a
     missing `Tab_Records` would fail the whole window as purchase-critical.
   - `ui.render` and `ui.selectTab` must cover the header pages. Draw the active look on the header button and show
     every dock tab inactive.
   - `ui.focus` falls back to the header button: `ui.tabs[ui.tab]` is nil for these pages.
   - `ui.addDevButton` clones the header Settings node, so clone before any active-look children are added.
2. **RECORDS, ported as-is:**
   - `Challenges.Rows(ShopData.profile().Records, .Challenges, Config.Challenges)`;
   - `FormatTime`; em dash written as `"\u{2014}"` (keep the file ASCII); EQUIPPED visibility;
   - NO DEATHS / "UNDER m:ss" with the reward always shown and a DONE / NOT YET chip; hide Challenge2 on a nil goal;
   - `tokens()` plural rule;
   - the client-local `showAssisted` switch (session-long, survives pushes, sends nothing);
   - `HiddenUntilPlayed` + `played()`;
   - re-render on `ShopData.Changed`;
   - `scaleText` / `fitLine` for the hug-width chip labels.
3. **SETTINGS:**
   - rows from `Config.AccessibilitySettings` minus Hidden, found with `need(page, "Setting_" .. Key)`;
   - state = Pending, else the attribute, else Default;
   - a tap sends `ZyntraAction "SetAccessibility" {Key, Enabled}`, optimistic, with the 12 s silent revert.
     **Hold** a press that falls inside the server's 1 s per-key window (as `sendAction` does) instead of losing it.
     Do not use `sendAction` itself: any push clears its pending, and its timeout text talks about a balance;
   - LobbyMusicEnabled is disabled until its attribute is a boolean;
   - the push message `"<Label>: on|off"` already reaches the L4 status and toast through `ShopData.Message`.
4. **MUSIC rail button: stays in ZyntraStore**, as a small block:
   - `refresh` for the caption, Text and SetEnabled;
   - the same `SetAccessibility` send with its own Pending;
   - the attribute and `Visible` listeners;
   - the not-ready guard in `updateVisibility`.

   The L4 graft reads its caption. Separate Pending state is fine because the rail and the L4 row are never pressable
   at the same time, and both read the same attribute.
5. **Tests:**
   - L4 harness sections for both pages: the Records semantics from section 4, plus every Settings row, payloads,
     pending and revert, the music not-ready state, missing-page warn-and-hide, and gamepad focus.
   - Rewritten `store-modal` and BriefingExclusionMatrix rows against the L4 window.
   - Rewritten `test_zyntra_store_compact` routing.
