# MAP: the L4 side of going live (2026-10-07)

This is a read-only map. Nothing was edited, and Studio and git were not touched.
Line numbers refer to the repo mirror. Each mirror file is byte-identical to its draft and
matches its manifest sha:

| File | sha |
|---|---|
| `Zyntra Shop L4` | fc9956ce |
| `Zyntra Dev L4` | 97abda47 |
| `ShopBinder` | 5e2a0151 |
| `ShopData` | b975f21f |
| `ZyntraStore` | f288523b |

**Baseline (luau 0.737), all green before any change:**
- `tests/test_zyntra_shop_l4.py`: 1128 checks, plus the dump round-trip.
- `dev-menu/tests/test_zyntra_dev_l4.py`: 6835 checks and 12 legacy rows. The ZyntraStore hunks have 45 free registers.
- `tests/test_zyntrastore_patch.py`: 9 scenarios.

---

## 1. Flag checks and legacy fallbacks

### ShopBinder and ShopData: none

Neither module reads `ShopUIVersion`, knows about ZyntraStore or carries a fallback.
- `ShopBinder.shadowOf` has a local named `fallback` (line 199). It is the sibling-shadow
  lookup, not a UI fallback. Leave it.
- `ShopData` needs nothing from ZyntraStore.

### `Zyntra Shop L4` (StarterPlayerScripts)

| Line(s) | What it is | Go-live action |
|---|---|---|
| 10-12 | Header: "ZyntraStore stays alive: ... DEV, the in-round dev phone ... and the per-player fallback whenever this window cannot bind" | Rewrite. ZyntraStore keeps RECORDS, SETTINGS, the rail, re-entry and PARTY DOWN. There is no fallback. |
| 14-19 | Header: "A page an import lacks is handed to the legacy terminal" | Rewrite to match the missing-page rule in section 2. |
| 25-28 | Header: "THE SWITCH is workspace attribute ShopUIVersion ..." | Delete. Keep only the sentence about the bridge contract (true = opened, never yields). |
| 51 | `local DevAccess = require(...)` | Delete. Its only use is `wantsL4` (line 75). |
| 73-76 | `wantsL4()` (the flag gate: "L4" for everyone, "L4-dev" for DevAccess) | Delete. |
| 89 | Bridge pcall error: `warn("... L4 open failed, legacy opens instead: ")` | Reword to `L4 open failed: <err>`. Keep the `bindFailed` / `setOpen(false)` lines. |
| 101 | Folder/modules missing: `warn("... not installed; the legacy shop stays in charge")` | Reword: "... ZyntraShopUI (ShopBinder, ShopData) is not installed: the shop cannot open". |
| 163-169 | `ui.handoff(tab)`: the comment mentions "every shop tab whose page the import does not have" | Keep the function, because it is the RECORDS/SETTINGS path. Cut the comment to RECORDS and SETTINGS. Optionally warn when `ZyntraOpenTerminal` is absent (see section 3). |
| 886-889, 962-964 | `legacyTabs`: a missing `Page_<Tab>` is collected, then warned as "legacy opens them" | Replace (see section 2). |
| 894-896 | Tab press: `if ui.pages[name] then ui.selectTab(name) else ui.handoff(name) end` | Drop the `else ui.handoff(name)` branch. |
| 924, 930 | Comments: "the legacy hand-offs", "live only in the legacy terminal" | Reword to "the terminal". |
| 972 | `openShop`: `... or not wantsL4() then return false` | Drop `not wantsL4()`. |
| 1025-1030 | The pill's "+": if `openShop` refuses, `ZyntraOpenTerminal:Fire("Shop")` | Delete the fallback and keep `ui.openShop("Shop", "Tokens20")` and `ui.refreshPill()`. A failed bind already hides the pill (`not ui.bindFailed`, line 1039). |
| 1038-1039 | `refreshPill`: `wantsL4()` twice | Drop both. The guard becomes `if not pill and not make() then return end`. |
| 1263 | `applyLobbySkins`: `if applied or not wantsL4() then return end` | Drop `not wantsL4()`. The skins then apply once at boot (line 1401). |
| 1275 | `DisplayOrder = 56 -- one above legacy (55)` | Keep the value. The terminal stays at 55. Reword the comment only. |
| 1287-1298 | Re-asserts `ZyntraStoreOpen` when "legacy setMainVisible(false)" writes nil | **Keep.** The Records/Settings terminal still runs `setMainVisible` from `updateVisibility`. Reword "legacy" to "ZyntraStore's". |
| 1317-1321 | `ShopUIVersion` change listener (closes, skins, pill) | Delete the whole block. Its two other calls already run unconditionally at lines 1401-1402. |

Deleting it frees two main-chunk locals (`DevAccess`, `wantsL4`).

### `Zyntra Dev L4` (StarterPlayerScripts, must stay ASCII)

| Line(s) | What it is | Go-live action |
|---|---|---|
| 28-29 | Header: "the legacy terminal's DEV tab opens instead (it is never removed)" | Rewrite: a missing name fails the menu for the session, with a warning. |
| 31-40 | OPENING: legacy DEV tab, `from = "terminal"`, "Live only while workspace.ShopUIVersion is ..." | Rewrite. The callers are J / DevPhoneCommand in the lobby, and `toggleMain` (J, the dev chip) in a round. There is no flag. |
| 59 | `if not DevAccess.IsAllowed(player) then return end` | **Keep.** It is the only gate. |
| 135-138 | `wantsL4()` (`"L4"` or `"L4-dev"`) | Delete. |
| 141 | Comment: "always has its fallback" | Reword. |
| 147-149 | Bridge `OnInvoke(requested, from)` passes `from` | Pass `requested` only. |
| 151 | `warn("... L4 dev menu failed, the legacy DEV tab opens instead: ")` | Reword to "L4 dev menu failed: <err>". |
| 162 | `warn("... ShopBinder is not installed; the legacy DEV tab stays")` | Reword: "... the dev menu cannot open". |
| 655 | `warn("... DevMenu_L4/DevWindow; the legacy DEV tab stays")` | Reword. |
| 841-848 | `ui.blocked(handoff)`: `handoff` skips the screen-owning check for the legacy DEV tab's hand-over | Drop the parameter. The predicate becomes `QueueModalOpen`, or briefing-in-round, or `ScreenOwningModalOpen()`. |
| 850-863 | `ui.toggle(requested, from)` and `if not wantsL4() or ui.blocked(from == "terminal") ...` | Change to `ui.toggle(requested)` with `if ui.blocked() or not ui.build() then return false end`. |
| 869 | `DisplayOrder = 57 -- above the legacy terminal (55)` | Keep the value and reword. |
| 902-903 | "Legacy setMainVisible(false) writes nil" re-assert of `DevPhoneOpen` | **Keep.** See the note on `DevPhoneOpen` in section 3. |
| 914-915 | `or (name == "ShopUIVersion" and not wantsL4())` closes the menu | Delete that clause. Keep the `RoundActive` clause. |

---

## 2. When a template is missing (after the change there is no legacy fallback)

### Shop

| Case | Today | After |
|---|---|---|
| `ReplicatedStorage.ZyntraShopUI` absent (30 s) or ShopBinder/ShopData absent (10 s) | Warns once at boot and the script returns. The bridge stays and answers false, so the legacy terminal opens. | Same, with the warning reworded (line 101). Every SHOP/UPGRADES press then does nothing. The rail keeps its old face, because the skins never run. |
| `ZyntraShop_L4` absent | The first open warns `L4 missing: ReplicatedStorage.ZyntraShopUI.ZyntraShop_L4` and sets `bindFailed`, and every open is false for the session. The pill is never made, silently (`make()` returns false). | Same. Warning at boot is optional: `build()` is lazy and never yields. |
| `ShopWindow` absent | Warns `L4 missing: ZyntraShop_L4/ShopWindow` and fails for the session. | Same. |
| A purchase-critical name absent (card, Buy/Price, Close, TokenCount, Page_Shop, tabs, picker parts) | Warns every path, destroys the root and fails for the session. | Same. This is the right behaviour. |
| A `Page_Upgrades/Skins/Donate/Colors` absent | Warns "legacy opens them", and the dock tab hands that page to the terminal. | **Choose one** (recommendation: b). |
| `LobbyRail_L4` / `LuckyWheel_L4` / `DailyRewards_L4` absent | `run()` returns silently, so that surface keeps its legacy face (line 1255). | Add one warning: `"%s skin skipped: ReplicatedStorage.ZyntraShopUI.%s is missing"`. The surface still works. |
| An optional node absent (`AddTokens`, `PendingText`, Records, Settings, Status, Toast) | One "optional nodes missing" warning, and the window still opens. | Unchanged. |

The two options for a missing page:
- **(a)** Make all five pages required, with `need(nil, "Page_" .. name, "ShopWindow")` at line 888. One missing page then fails the whole shop.
- **(b)** Keep the window, hide that dock tab (`tab.Visible = false`) and warn once with "L4 pages missing, their tabs are hidden: ...". `openShop` for that tab is already false (line 976). This is the recommendation: the other pages keep selling, and nothing reaches a deleted page.

### Dev

| Case | Today | After |
|---|---|---|
| ShopBinder absent | Warns at boot, and the legacy DEV tab opens | The warning is reworded. J does nothing. |
| `DevMenu_L4` / `DevWindow` absent | The first open warns, and the legacy DEV tab opens | The warning is reworded and nothing opens. |
| A required row absent (the `ROWS` set, `Dev_grantTokens` parts, `Close`) | Warns every path and fails for the session | Same. |

---

## 3. The RECORDS and SETTINGS hand-off, and what L4 needs from ZyntraStore

### The path today, which stays

1. The L4 header nodes `Records` and `Settings` are bound at lines 928-932, and a press calls `ui.handoff(tab)`.
2. `ui.handoff` (165-169) runs `ui.setOpen(false)`, which writes `ZyntraStoreOpen = nil`
   synchronously. It then runs `PlayerScripts.ZyntraOpenTerminal:Fire(tab)`, found by
   `FindFirstChild`, with no wait.
3. ZyntraStore's `ZyntraOpenTerminal.Event` (4052-4057) calls `openKioskShop(tab)` (4024-4050).
4. `openKioskShop` asks the `ZyntraShopUIOpen` bridge first. L4's `openShop("Records")` returns
   false at once, because `pages.Records` is nil (line 972).
5. The guards run (InRound, `modalBlocksStore`, and `ScreenOwningModalOpen() and not main.Visible`).
   Then `selectTab(tab)`, `setMainVisible(true)` and `showStatus("")`.

### What ZyntraStore must still provide after the deletion

1. **`PlayerScripts.ZyntraOpenTerminal`** (a BindableEvent, created at load) whose handler
   opens the terminal on `"Records"` and `"Settings"`. It keeps answering `"Rewards"` with
   `OpenDailyRewards`.
   - The final fallback `selectTab(... or "Shop")` (line 4047) must no longer fall back to
     Shop.
   - Any other tab name must not open the terminal at all. The bridge has already been
     asked, and its refusal is final.
2. **`pages.Records` and `pages.Settings`** in the terminal.
   - Records only exists while `ReplicatedStorage.ZyntraRecordsPage` does (line 653). If that
     module is absent, L4's RECORDS closes the window and nothing opens. This is an edge case;
     the module is installed.
   - `currentTab` starts at `"Upgrades"` (line 30) and must start on a tab that survives.
3. **`ZyntraShopUIOpen` asked from every shop entry**, with no fallback:
   - rail SHOP, through `openKioskShop()`;
   - rail UPGRADES in the lobby (`Invoke("Upgrades")`, line 4155);
   - `ZyntraOpenTerminal` for shop tab names;
   - the `ZyntraShopPrompt` kiosk route (`bindShopPrompt`). The v4 lobby removed those prompts,
     so this path is probably dead.
4. **`ZyntraDevUIOpen` asked from every dev entry**, with no fallback:
   - in-round `toggleMain` (3964-3970), which the J key and the rail button reach in a round;
   - lobby J through `DevPhoneCommand` (4136-4142).

   The DEV-tab hand-over (4173-4181) goes with the Dev tab. The lobby J path then falls into
   `toggleMain(requested)`, which today would OPEN the terminal (now on Records) when the dev
   menu refuses. It should only close an open terminal and otherwise do nothing.
5. **The rail, for `skinRail` and the pill.** `PlayerGui.ZyntraStore` must keep these buttons:
   - `ZyntraShopButton`, `ZyntraOpenButton`, `ZyntraRewardsButton`, `ZyntraWheelButton` and
     `ZyntraMusicButton`;
   - each with `SectionButtonContent` (hidden, never destroyed) and `SquareSectionBorder`;
   - Music's `SectionCaption`, which is mirrored.

   `railRight()` (988-998) reads their positions to place the pill.
6. **The `ZyntraStoreOpen` and `DevPhoneOpen` writes.**
   - `setMainVisible` writes `ZyntraStoreOpen`, and also `DevPhoneOpen = devAllowed and
     main.Visible` (line 3619).
   - Both L4 scripts re-assert their own flag, so they tolerate this.
   - Once the terminal is no longer the dev phone, the `DevPhoneOpen` write has no purpose and
     should go. That is ZyntraStore-side work, and either way is safe for L4.

### Things the deletion breaks on the L4 side unless they are moved

None of these is a flag, but each one depends on the legacy Shop page.

- **Lobby SHOP wall BUY.** `Shop Display Client` fires `PlayerScripts.ZyntraShopBuy`.
  ZyntraStore answers it (4432-4441) with `productPurchase[key]`, and that table is filled
  only by the legacy Shop and Upgrades card builders (lines 1884 and 2338). Delete those
  builders and every wall BUY silently does nothing.
  - The wall sells: Supporter, AdvancedEquipment, Tokens4, Tokens20, EmergencyReentry,
    ExpeditionPack, CosmeticEquipment, SpeedPotion and RouteMarker (LobbyShopDisplay
    140-148).
  - `ShopData.purchase` already covers seven of them. It does not cover Tokens4 or
    EmergencyReentry.
  - Smallest fix: L4 owns the bridge, with a create-if-absent `ZyntraShopBuy` whose `Event`
    runs `ShopData.purchase(tostring(key))`. ShopData's product list (line 103) gains
    `"Tokens4", "EmergencyReentry"`; they become promptable but get no card.
  - The legacy `requestPurchase` had no special case for either key (1863-1882).
  - The consumer test `tools/tests/test_lobby_shop_display.py` fakes the bridge by name and
    is unaffected.
- **The Emergency Re-entry live price.** The kept re-entry modal and `ZyntraReentryPrice`
  read `displayedProductPrices.EmergencyReentry` (3248, 3258).
  - That value is filled by the Shop page's `makeProductCard("EmergencyReentry")` (1903) and
    its `GetProductInfo` (1844-1860).
  - Without the card it falls back to the Config price. For ZyntraStore to handle: keep one
    `GetProductInfo` for that id.
- **UIRegression** (Studio-only, not offline) drives the legacy terminal through
  `UIRegressionZyntraStoreProbe` "kiosk", "cards", "scrolls" and "donations" (for example
  `ZyntraTerminalFitMatrix` at 5427 and the kiosk rows at 4967/5005).
  - Once the kiosk opens L4 for everyone, those lanes fail.
  - The unapplied spec `patches/UIRegression.L4-lane.md` (its `ShopUIVersion` borrow) is
    obsolete.
  - For the ZyntraStore mapper.

---

## 4. "Prices are read live from Roblox."

### Where it reaches the screen

1. **`Zyntra Shop L4` line 57**: `TAB_HINTS.Shop`. `ui.showHint` (645-650) writes it into
   `ui.status`, the cloned `ShopWindow/Canvas/Footer/Status`:
   - on every `selectTab("Shop")` (709);
   - so on every open on Shop, because `openShop` selects before `setOpen(true)` (977-978);
   - 6 s after any message shown while on Shop (661-663).
2. **The template default**: `ZyntraShop_L4/ShopWindow/Canvas/Footer/Status.Text` is exactly
   that string. The live-20261007 dump, the root dump, `framewisp-tree.L4.json` and the
   20261006 dump all hold it.
   - Today the clone's copy is always overwritten by `showHint` before `Root.Visible`, so on
     its own it never shows.
   - It is the copy that would come back if a hint were ever missing for Shop and a code path
     showed the window without `selectTab`.
   - The dev menu's template Status is a different line ("Every command is checked again by
     the server."), and the dev menu uses it as its hint (`ui.statusHint`, 755). It is not
     affected.
3. **The legacy terminal**, ZyntraStore line 2037. This goes with the Shop page.
4. Design docs and prompts hold it with no runtime effect: `SHARED-SPEC-SHOP-TAB.md`,
   `LAYOUTS.md`, `L4-ROBLOX-PLAN.md`, `catalog-v1.json`, `refs/L*-prompt.txt` and
   `workflow-result.json`. Leave them; they are history.

### Removing it so that it can never show

1. Delete line 57 (`Shop = "Prices are read live from Roblox.",`). `showHint` then writes `""`
   on Shop (`TAB_HINTS[ui.tab] or ""`).
2. Add one line in `ui.build` after line 940: `if ui.status then ui.status.Text = "" end`. The
   clone then never carries the template's text, whatever the import says, and the guarantee
   no longer depends on `selectTab` ordering.
3. In Studio, set `Status.Text = ""` on both template copies:
   - `ReplicatedStorage.ZyntraShopUI.ZyntraShop_L4 ... Footer.Status`;
   - its source under `ZyntraShopUI.Imports` (the `Framewisp_Live_ZyntraBundle_L4` bundle).
     `install/01_templates.luau` re-clones from Imports, so editing only the template would
     come back on a re-run.
4. Optional: the Figma source (file 7FXycGKH6OT6Lme6FV3VBc, ZyntraShop_L4 Footer/Status). A
   Live Sync re-import restores the text into Imports. Starter plan budget: about 20 calls a
   month, so ask first. Step 2 makes this cosmetic.
5. Leave the offline dumps holding the text. The test then proves the worst case: the import
   carries the string, and it still never shows.

---

## 5. Tests that assert flag or fallback behaviour

### `tests/zyntra_shop_l4_harness.luau` (run by `test_zyntra_shop_l4.py`)

| Line | Assertion | Action |
|---|---|---|
| 685, 967 | Fixture: `context` sets `ShopUIVersion = opts.flag`; `ready()` defaults to `"L4"` | Make the default unset, so the whole suite runs flagless, which is production after go-live. Explicit `flag =` options become inert. |
| 1054 | "no shop tab is handed to the legacy terminal" (`#TerminalTabs == 0`) | Keep and reword. |
| 1175 | "a failed bind stays failed for the session (legacy every time)" | Keep and reword the message. |
| 1179 | "flag unset: legacy" (`Open == false`) | **Invert**: flag unset, so L4 opens (`true`). This is the owner's order, not a weakening. |
| 1180-1181 | "L4-dev and not a developer: legacy" | **Invert**: a non-developer opens L4 whatever the attribute says (`"L4-dev"`, `""`, nil). |
| 1182-1184 | "L4-dev and a developer: L4" | Merge into the inverted check above. |
| 1185-1186 | RECORDS, SETTINGS and DEV are never L4 | Keep. |
| 1188 | "InRound: legacy decides" (false) | Keep; message becomes "InRound: refused". |
| 1193-1194 | No template: false and a warning | Keep. Add `#TerminalTabs == 0`, so nothing is fired at the terminal. |
| 1570 | "tab X: the footer has a hint" (`Status.Text ~= ""`) on all five tabs | It conflicts with the order for Shop. Keep `~= ""` for Upgrades, Skins, Donate and Colors. For Shop, assert `Status.Text == ""`. The requirement changed (removed, not replaced), so this is not a weakening. |
| 1578-1583 | RECORDS and SETTINGS hand off to the terminal | Keep. This is the kept path. Reword "legacy" to "terminal". |
| 1625 | Modal trigger "flag off" closes the window | **Delete.** It tested the deleted `ShopUIVersion` listener. Replace with "setting `ShopUIVersion` while open leaves the window open". |
| 1665-1666 | "no pill without the flag" | **Invert**: the pill shows with the attribute unset. |
| 1778-1780 | "flag unset: the rail stays legacy" | **Invert**: the rail is skinned with the attribute unset. |
| 1920 | "a failed bind hands the pill's + to the legacy terminal" (`TerminalTabs[#] == "Shop"`) | **Delete.** It tested the deleted fallback. Replace with "a failed bind fires nothing at the terminal" (`#TerminalTabs == 0`). Keep line 1921 ("the pill stands down"). |
| 2096-2097 | Wheel "flag unset: no backdrop (legacy, no dim)" | Still passes, because the skin keeps the shade transparent. Reword. |
| 2386 (smoke) | `context({flag = "L4-dev", dev = true, ...})` runs `install/05_qa_probe_client.luau` | Drop `flag`. The probe changes are listed in the next table. |

**New checks**, one per order. Each fails if its order is broken:
- Attribute inert: covered by the inversions above.
- Missing-page rule (b): mutate the template to drop `Page_Donate`.
  - The window opens.
  - `Tab_Donate` is hidden and a warning names it.
  - `Open("Donate") == false` and `#TerminalTabs == 0`.
- Missing skin template: `skip = {LobbyRail_L4 = true}`, and a warning names it.
- The removed text never shows:
  - after opening each tab, and after a message times out on Shop (`Advance(6)`), no
    TextLabel under `ctx.Gui` contains "read live from Roblox";
  - the real dump still holds the string, so this proves the step-2 clear;
  - in `test_zyntra_shop_l4.py`, assert the string is absent from the `Zyntra Shop L4`
    source.

### `install/05_qa_probe_client.luau` and `05_qa_probe_server.luau`

These are the Studio QA probes; the client probe also runs offline in the smoke test.

- Client lines 92-95: the record `"flag"` requires `"L4"`, or `"L4-dev"` plus DevAccess.
  **Delete it**, or it fails on the unflagged production place. The `installed` record
  remains.
- Client lines 190-202 and 223-227: the branches "tab X (legacy)" and "rail UPGRADES opens
  legacy (no Upgrades page)". These describe the deleted hand-off. A missing page is now a
  failed record.
- Server lines 23-24 and 53: the `ShopUIVersion` check and "L4-dev shows them legacy".
  **Delete them.**
- The probe drives ZyntraStore's `UIRegressionZyntraStoreProbe` "kiosk", "open" and "close".
  Keep those three actions in ZyntraStore, or move the probe to L4's own seam.

### `dev-menu/tests/zyntra_dev_l4_harness.luau` and `test_zyntra_dev_l4.py`

| Where | Assertion | Action |
|---|---|---|
| harness 93 | Fixture default `ShopUIVersion = "L4-dev"` | Make the default unset. |
| harness 278 | "non-dev gets no bridge (legacy keeps its path)" | Keep and reword. |
| harness 450-466, §5 case "flag off" | `{flag = false}` means the bridge answers false | **Delete the case.** It tested the deleted gate. Add "attribute unset: opens". The other §5 cases are kept, with "(legacy opens)" reworded to "(nothing opens)". |
| harness 476-479 | "flag off: legacy", "flag on later: L4" | **Delete.** It was the gate. The unset-opens check covers the new contract. |
| harness 485 | "close while closed: legacy decides" | Keep and reword. |
| harness 540 | "a hand-over still respects the queue modal" (`Open(true, "terminal")`) | **Delete with the `from` parameter.** Line 539 already checks that the queue blocks. |
| harness 545-547 | "J over the open legacy terminal: legacy toggles itself" (false while `ZyntraStoreOpen` and `DevPhoneOpen` are up) | Keep. It never opens over the Records/Settings terminal. Reword. |
| harness 548 | "the DEV tab hand-over opens L4" | **Delete.** It exercised only the deleted legacy DEV tab. |
| harness 549-550 | "L4 keeps DevPhoneOpen and the movement lock" | Keep the assertion and change the setup: clear the terminal flags, open with `Open(true)`, set `ZyntraStoreOpen` and `DevPhoneOpen` to nil, then check it is still open with `Suppress` true. |
| harness 552-554 | "flag off closes and refuses" | **Delete.** It tested the deleted listener. Optionally add "attribute change leaves the menu open". |
| py 69-90, 264 | `legacy_rows()` parses the DEV `controls` and payload lines out of the live ZyntraStore | Freeze before the deletion. Write the 12 parsed rows to `dev-menu/tests/legacy-dev-rows.json`, stamped with ZyntraStore sha f288523b, and read them there. All row-parity checks (§2, §3 and the 871 loop) are kept, and none is weakened. |
| py 230-250, 263 | `check_store_patch()` pins the live ZyntraStore equal to `patches/ZyntraStore.shop+dev.patched.lua` and re-applies the hunks | **Retire.** It pins the legacy routing install that the go-live rewrites by design, and it fails on any edit. Replace with: the live ZyntraStore compiles, and it still invokes `ZyntraDevUIOpen` at the in-round toggle and at lobby J, which is the contract Dev L4 needs. |

### `tests/test_zyntrastore_patch.py`

- It does not read the mirror. It tests `install/03_zyntrastore_patch.py` against the frozen
  2026-10-05 copy (`_local/.../ZyntraStore.studio.lua`), so it stays green.
- It tests the installer of the legacy-fallback routing hunks, which the go-live supersedes.
- Retire it together with `install/03` once the new ZyntraStore lands. Until then it can stay
  as history.

### `tools/tests`

- None reads `ShopUIVersion` or the L4 bridges.
- `test_zyntra_store_compact.py` exercises the legacy Shop page (`productPurchase.SpeedPotion`
  and `RouteMarker`). It is also the only test of `ZyntraOpenTerminal "Rewards"` (line 893),
  so keep that row. Both belong to the ZyntraStore mapper.

---

## 6. Obsolete install artifacts (flag-era, no runtime effect)

- `install/04_flag.luau`: sets `ShopUIVersion`. Delete it, or mark it superseded.
- `install/02_scripts.md` (50, 66), `install/README.md`, `L4-ROBLOX-PLAN.md` and
  `patches/ZyntraStore.routing.md` describe the flag and the fallback.
- `_local/shop-ui-figma/studio-turn/{qa_main,qa_slim,edit_probe}.luau` set the flag. It is
  harmless once the flag is inert.
- If the saved place persisted `workspace.ShopUIVersion`, which cannot be checked without
  Studio, clear it in the Studio step for tidiness. It no longer does anything.
