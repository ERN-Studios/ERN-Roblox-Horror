# CHANGES: the L4 side of the go-live (2026-10-07)

The owner's order: L4 goes live, replaces the old UI, and the "Prices are read live from
Roblox." line is removed. No other backdrops were touched. Studio, git and Codex were not
used. ZyntraStore and tools/tests were not edited; another agent owns them.

## Result

| What | Before | After |
|---|---|---|
| `tests/test_zyntra_shop_l4.py` | 1128 checks + dump round-trip | **1150 checks + dump round-trip, green**, plus a source check (`check_go_live`) |
| `dev-menu/tests/test_zyntra_dev_l4.py` | 6835 checks, 12 legacy rows (read from the live ZyntraStore) | **6837 checks, 12 legacy rows (frozen fixture), green** |
| `tests/test_zyntrastore_patch.py` | 9 scenarios | **deleted** (see Tests) |
| `luau-compile -O0` | | OK for Shop L4, Dev L4, ShopBinder, ShopData, UIRegression, `install/04` and both `05` probes |
| Mirror vs draft | | `cmp` identical for all four L4 files |

New hashes (sha256, first 12):

| File | Before | After |
|---|---|---|
| Zyntra Shop L4 | fc9956cea1fe | 8c5c02f9d7cd |
| Zyntra Dev L4 | 97abda473d81 | 4beecaded185 |
| ShopBinder | 5e2a0151609b | unchanged |
| ShopData | b975f21f2650 | unchanged |
| UIRegression | 97b4d4f8c8a0 | 7075ea19ac95 |

Three manifest entries need `record_pending_push.py`: Zyntra Shop L4, Zyntra Dev L4 and
UIRegression.

Mutation checks were run on throwaway copies, and each was caught:
- putting the Shop hint back;
- not hiding a missing page's tab;
- putting a `ShopUIVersion` gate back into Dev L4.

The status-clear line cannot be reached through any public path, because `showHint` always
writes first. `check_go_live` pins that line in the source instead.

## Zyntra Shop L4 (mirror and draft)

### The switch is gone
- Deleted `wantsL4()` and its `DevAccess` require.
- Deleted the `wantsL4()` uses in `openShop`, `refreshPill` and `applyLobbySkins`.
- Deleted the `ShopUIVersion` change listener.
- The shop, the token pill and the lobby skins (rail, wheel, daily rewards) now apply for
  every account at boot.

### No legacy fallback, and clear warnings instead
- **Bridge error:** warns `L4 open failed: <err>`.
- **Modules missing:** warns `ReplicatedStorage.ZyntraShopUI (ShopBinder, ShopData) is not
  installed: the shop cannot open`.
- **A `Page_<Tab>` missing (MAP-l4 option b):** that dock tab is hidden, and one warning names
  it (`L4 pages missing, their tabs are hidden: ...`). The bridge refuses that tab and a stray
  press does nothing. `Page_Shop` stays purchase-critical.
- **The pill's "+":** no longer fires `ZyntraOpenTerminal("Shop")`. On a failed bind it stands
  down; the bind has already warned.
- **A skin template missing:** `run()` used to return silently. It now warns `<surface> skin
  skipped: ReplicatedStorage.ZyntraShopUI.<name> is missing`, and that surface keeps its own
  face.
- **`ui.handoff`:** now only serves RECORDS and SETTINGS. It warns if
  `PlayerScripts.ZyntraOpenTerminal` is missing.

### "Prices are read live from Roblox." is removed
- `TAB_HINTS.Shop` is deleted, so the Shop footer is empty.
- `ui.build` blanks the cloned `Footer/Status` right after binding. The import's sample text,
  which still holds the line, can never show, whatever a re-import carries.
- The line is no longer anywhere in the controller's source; a comment was reworded too.

### Comments
- The header and the "legacy" wording now describe ZyntraStore's terminal and rail.
- Kept as they were: the `ZyntraStoreOpen` re-assert (the Records/Settings terminal still
  writes nil) and DisplayOrder 56.

## Zyntra Dev L4 (mirror and draft; still ASCII-only, headroom 170 of 200)

- Deleted `wantsL4()` and the `ShopUIVersion` clause in `workspace.AttributeChanged`.
  `DevAccess` (line one) is the only gate.
- Dropped the bridge's `from` parameter. `ui.blocked()` no longer has a hand-over exemption:
  the menu never opens over any screen-owning modal, the terminal included.
  - This matches the rewritten ZyntraStore, which calls `ZyntraDevUIOpen:Invoke(requested)`
    and closes its own terminal on a refusal.
- The warnings say what happens now:
  - `L4 dev menu failed: <err>`
  - `... ShopBinder is not installed: the dev menu cannot open`
  - `... DevMenu_L4/DevWindow: the dev menu cannot open`
- The header now documents the go-live routes.

## ShopBinder and ShopData: unchanged

Neither ever read the flag. Tokens4 and EmergencyReentry were deliberately not added to
ShopData:
- `zyntra_shop_l4_harness.luau` asserts that they cannot be dispatched (owner decision).
- The ZyntraStore agent kept a wall-only dispatcher for `ZyntraShopBuy` (MAP-consumers option
  a), which does not go through ShopData.

## UIRegression.ModuleScript.lua (9457 -> 9240 lines, compiles)

### resetScenario
Also closes `ZyntraShopL4` and `ZyntraDevL4` through their probes, so an L4 window cannot
leak into the next row.

### Scenario rows
- `store-modal` now selects `tab:Settings` before relayout.
- `store-modal-dev` is **deleted**: it opened `tab:Dev`, which no longer exists.

### REQUIRED_GUIS
Gains `ZyntraShopL4`, so a broken L4 install is a named failure. `ZyntraDevL4` is not
added: non-developers never get it.

### Deleted with the pages
- `donationTierCount`
- the Upgrades, Shop, Skins, Donate, Colors and Dev rows of `PAGE_CONTENT` (Settings and
  Records are kept)
- `Fit.DonationTierKeys`
- the Upgrades and Colors entries of `Fit.ZyntraExpectedActive` (Records = 1 is kept)

### ZyntraTerminalFitMatrix
- **Tab set:** `{Records, Settings}`. A new check asserts that none of the deleted tabs is
  built, **DEV included even under DevAccess**. That is a stronger contract than before.
- **Deleted:** the donation-tier oracle (`probe "donations"`), the Shop description and Colors
  heading proofs, the Donate reachable count, the Donate per-card tier block and the Colors
  three-rectangle block. All of them measured deleted pages.
- **Kept and unchanged:** the shell, per-tab containment, scroll, text, action and tap-target
  sweeps (they now run over Records and Settings), and `Fit.ZyntraDisabledCaptions`.

### BriefingExclusionMatrix
- **Lobby briefing.** The toggle still opens the terminal. SHOPS (`kiosk`) is now asserted to
  open the **L4 shop** (Root visible, `ZyntraStoreOpen`, panel yields, transmission keeps
  running) and never the terminal. The two windows are opened one after the other, because the
  shop correctly refuses to open over the terminal.
- **Queue open.** The kiosk must leave the L4 shop shut.
- **Developer captions** are now read off **Zyntra Dev L4**, with the same keys and noclip copy:
  - the eyebrow "WHITELISTED DEVELOPER CONTROLS · KEY J", which replaces the legacy
    "PHONE: J" intro;
  - each `Dev_<cmd>` KeyChip reads "KEY <k>" and shows exactly when the device has keys;
  - the noclip `Desc` copy.

  The menu opens and closes through `UIRegressionZyntraDevL4Probe`.
- **Cleanup.** The old baseline-text snapshot of the deleted DEV page is replaced: after
  `ForceTouchUI` is restored, the dev menu's captions must match the restored input mode.
- `DEV_INTRO_*` is renamed `DEV_EYEBROW_*`, so the top-level local count is unchanged.

**Not covered yet:** the L4 shop window has no UIRegression fit lane (planned in
`patches/UIRegression.L4-lane.md`; its `ShopUIVersion` borrow is moot). The L4 token pill now
shows in every lobby scenario, for every account. UIRegression is Studio-only, so none of this
was run here.

## Tests (artifacts)

### Shop harness and runner
- **The fixture is flagless.** `ready()` no longer defaults `ShopUIVersion` to "L4", so every
  test runs the way production does.
- **Inverted** (by the owner's order, not weakened):
  - "flag unset: legacy" and "L4-dev, non-dev: legacy" become: a non-developer opens L4 with
    the attribute unset, and with `""`, `"L4-dev"`, `"L4"` or `"legacy"`. Each value also
    leaves an open window open.
  - "no pill without the flag" becomes: the pill shows whatever the attribute says.
  - "flag unset: the rail stays legacy" becomes: the rail is skinned with the attribute unset.
- **Deleted, because each exercised deleted code:**
  - the "flag off" modal-close trigger (the deleted listener);
  - "a failed bind hands the pill's + to the legacy terminal" (the deleted fallback). It is
    replaced by: nothing is fired at the terminal, and the missing name is warned.
- **Changed requirement:** "tab Shop: the footer has a hint" becomes "the Shop footer is
  empty". The other four tabs keep `~= ""`.
- **Added checks:**
  - the missing-page rule: the tab is hidden, warned once, refused, a stray press is inert,
    and the other pages still open;
  - a missing `Page_Shop` still fails the window;
  - a failed bind, or a missing template, fires nothing at the terminal;
  - a missing skin template is warned by name while the other skins apply;
  - the removed line is nowhere in PlayerGui after opening every tab, after a message times out
    on Shop, and after closing (the dump still carries it: worst case);
  - `check_go_live` in the runner: the line is absent from the source, the Status-blank line is
    present, no `wantsL4` and no `ShopUIVersion` read, and the dump still holds the string.
- **Smoke test** (`install/05_qa_probe_client.luau` on the fake client):
  - it now runs as an ordinary player with no attribute;
  - the emulated ZyntraStore follows the go-live routing: RECORDS and SETTINGS go to the
    terminal, everything else goes to the L4 bridge only, and `kiosk` returns L4's answer.

### Dev harness and runner
- **The fixture is flagless.**
- **Deleted:**
  - the "flag off" refusal case and "flag off: legacy / flag on later: L4" (the deleted gate);
    they are replaced by "unset, `""`, `"L4-dev"`, `"L4"` or `"legacy"`: opens";
  - "the DEV tab hand-over opens L4" (the deleted DEV tab). It is replaced by "the retired
    hand-over argument no longer skips the screen-owning guard";
  - "flag off closes and refuses". It is replaced by "ShopUIVersion changes leave the menu
    open".
- **Kept and re-set-up:** "J over the open terminal" is still refused. "L4 keeps DevPhoneOpen
  and the movement lock" now opens with `Open(true)` once the terminal is shut.
- **`legacy_rows` reads a frozen fixture.** It used to read the live ZyntraStore, whose DEV tab
  is deleted. It now reads `dev-menu/tests/legacy-dev-rows.json`: 12 rows and the three payload
  lines, stamped sha256 f288523b1c68.
  - The fixture is re-verified against `patches/ZyntraStore.shop+dev.patched.lua`, the stored
    last legacy build, whenever that file is present and matches the stamp.
  - Every parity check is kept.
- **`check_store_patch` is retired.** It pinned the live ZyntraStore to the legacy routing
  install, which the go-live rewrote on purpose. It is replaced by `check_store_contract`:
  - the live ZyntraStore compiles -O0;
  - it names `ZyntraDevUIOpen`;
  - it passes no `"terminal"` hand-over;
  - it no longer builds a DEV tab.

### Deleted test file
`tests/test_zyntrastore_patch.py`. It tested `install/03_zyntrastore_patch.py`, the installer
(and `--revert`) of the legacy-fallback routing hunks. The go-live ZyntraStore no longer
contains those hunks, and a `--revert` would only try to put a fallback back. `install/03` is
marked RETIRED in the README. The file itself is not mine to delete.

## Install files
- **`install/04_flag.luau`** no longer sets a flag. It clears a leftover
  `workspace.ShopUIVersion` (`CLEAR = true`; inert either way) and reports the install: six
  templates and both L4 scripts.
- **`install/05_qa_probe_client.luau`:**
  - no `flag` precondition and no legacy branches;
  - a missing page is a failed step;
  - rail UPGRADES asks only the bridge;
  - the variables are renamed from "legacy" to the terminal.
- **`install/05_qa_probe_server.luau`:** no `ShopUIVersion` precondition. It reports
  `retiredShopUIVersion` for information only.
- **`install/README.md`:**
  - a new "Go-live" section: no switch, the missing-template rules, the removed line, and
    step 3 retired;
  - step 4 rewritten;
  - QA runs on any account;
  - the re-import step that applied `03` is marked retired.

## Left for the main session (Studio or owner)
1. Push Zyntra Shop L4, Zyntra Dev L4 and UIRegression. Run `record_pending_push.py`, then the
   push tool, then the compile probe.
2. Run `install/04_flag.luau` once to clear a leftover `ShopUIVersion` from the saved place.
3. Optional: blank `Footer/Status.Text` on `ZyntraShopUI.ZyntraShop_L4` and its `Imports`
   source. The code already guarantees the line never shows.
4. **Gap D1 is still open:**
   - A touch developer in the lobby has no route into the dev menu: J needs a keyboard, and the
     DEV chip shows only in rounds.
   - The `from = "terminal"` exemption is gone. Any future DEV button inside the terminal must
     close the terminal first (`setMainVisible(false)` clears `ZyntraStoreOpen`
     synchronously), then invoke the bridge.
5. Delete `install/03_zyntrastore_patch.py` and `patches/ZyntraStore.routing.*` when
   convenient. They are retired, not mine.
6. The UIRegression L4 shop lane is still to be written.

## Review fixes (2026-10-07, second pass)

Gap D1 above is now closed by item 2 below.

| File | After go-live | Now |
|---|---|---|
| Zyntra Shop L4 | 8c5c02f9d7cd | **8b4119cdfaa2** (1492 lines) |
| Zyntra Dev L4 | 4beecaded185 | **4f613d014d49** (comment only) |
| ShopData / ShopBinder | b975f21f2650 / 5e2a0151609b | unchanged |

`cmp`: the mirror and the draft are identical for all four files. Everything compiles at `-O0`. Studio and Codex were not used.

### Zyntra Shop L4

1. **The developer suit, Signal Architect** (finding at ShopData line 71).
   - **The gate.** `DevAccess` is required again. It is the gate only; there is still no rollout switch.
   - **The card.** For a DevAccess player, the Skins bind's `addDevCard`:
     - clones the last card (`SkinCard_FalseSun`) as `SkinCard_SignalArchitect`, with LayoutOrder + 1;
     - writes the suit's name into the clone's Name label.
   - **ShopData.SKINS is untouched.** It lists what is sold, and this suit is not sold.
   - **The grid grows one row**, and the cards keep their on-screen size:
     - the canvas Y is multiplied by the growth factor, and CellSize and CellPadding Y are divided by it;
     - every card's Size is set to CellSize, which keeps `Binder.designSize` true for the clone's text.
   - **When it is skipped.** If the page is not a Scale grid inside a ScrollingFrame, or the card has no Name label, the card is skipped with a warning. The window still opens.
   - **How the card behaves.** It is bound like the other cards:
     - EQUIP runs `ShopData.purchase("Skin", "SignalArchitect")`, which sends EquipSkin. The server re-checks DevAccess (ZyntraMonetization line 4045).
     - EQUIPPED, the badge and the preview work.
     - Before the server's grant, the card reads UNAVAILABLE / DEVELOPER ONLY.
2. **A lobby dev entry without a keyboard** (finding at ZyntraStore line 1893, option a).
   - **The button.** `ui.addDevButton` gives a DevAccess player a `DevMenu` button in the header:
     - it is a clone of SETTINGS with the icon dropped;
     - its label reads "DEV": TextScaled, in the Title font, in Cream;
     - it sits one RECORDS-to-SETTINGS step left of RECORDS, between the title block and RECORDS.
   - **The press.** If `PlayerScripts.ZyntraDevUIOpen` exists, the press:
     1. calls `ui.setOpen(false)`, which clears ZyntraStoreOpen synchronously;
     2. calls `Invoke(true)` inside a pcall. A refusal is final.
   - **Failure cases:**
     - The bridge is missing: a warning, and the shop stays open.
     - Records or Settings is missing: a warning, and no DEV button.
   - **UIRegression is unaffected.** Its "no DEV tab" check covers the terminal, which still has no DEV tab.
3. **The header comment** documents both.

### Zyntra Dev L4

Comment only: OPENING now names the L4 shop's DEV route. The file is still ASCII-only (checked), with headroom 170.

### Tests

#### Shop harness: 1150 -> 1251 checks

- **Fake engine.** It gained `FindFirstAncestorWhichIsA`, a real Instance API that the new code calls.
- **New section 1c**, run on every variant (real, c, d, e).
  - **A player** gets no suit card, no DEV button and no probe entry.
  - **A developer** gets the suit card, and:
    - it is last in the grid, with its own name and its own art, and the probe lists it;
    - four rows fit the grown canvas, the canvas grew, and every card keeps its on-screen height;
    - `lineFaults` is clean, so the long name fits;
    - EQUIP sends EquipSkin once, and a second press while it saves sends nothing;
    - after a push the card shows EQUIPPED, with the badge and the preview;
    - after equipping another suit, the way back is still there.
  - **Wearing the suit at join** previews the suit.
  - **Before the grant** the card reads UNAVAILABLE and is inert.
  - **No grid:** the card is skipped, with a warning.
  - **The DEV button:**
    - it is in the header, with no settings glyph;
    - it sits between the title and RECORDS, at the RECORDS-to-SETTINGS gap;
    - a press asks `Invoke(true)` once, with ZyntraStoreOpen already nil; the shop closes and the terminal is untouched;
    - a missing bridge warns and the shop stays open;
    - a refusal opens nothing;
    - with no RECORDS, the button is skipped, with a warning.
- **Section 0** still asserts 26 bound controls, for a player.
- **Mutations**, each caught:
  - the card for everyone;
  - no grid growth;
  - invoking before closing;
  - the name not set;
  - DEV for everyone;
  - the card Size not reset.

#### Dev harness: 6837 -> 6857 checks

New case 6b, on touch and on a gamepad:
- the menu is refused while the L4 shop is up;
- once the shop clears ZyntraStoreOpen in the same frame, `Invoke(true)` opens it;
- the fastQueue and playerEsp rows are live and fire exactly their own command.

#### Other

`test_zyntrastore_patch.py` stays deleted (go-live).

### Left for the main session

- **Push** Zyntra Shop L4 and Zyntra Dev L4, together with ZyntraStore.
- **Check in Studio:**
  - the DEV button's look in the header at phone size (it is a TextScaled label with no Figma frame);
  - the fit of "Signal Architect Ascendant" in its card.

  The owner may want a Figma-drawn DEV button.
- **The UIRegression L4 lane is still to be written.** A developer account will see one extra header button and 27 bound cards.
