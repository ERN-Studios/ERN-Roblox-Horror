# RECORDS and SETTINGS as L4 pages; legacy terminal deleted (2026-10-07)

Owner-approved Figma (BINDINGS.md, pages-v3 fixture) implemented in "Zyntra Shop L4"; the RECORDS / SETTINGS
terminal in ZyntraStore, `ZyntraRecordsPage` and the UIRegression terminal lanes are deleted. No Studio, no git.
Pre-change copies of every deleted or rewritten repo file are in `code/before/` (sha256 prefixes: ZyntraStore
74ee23540b22, ZyntraRecordsPage 497b4f448494, UIRegression 7075ea19ac95, test_zyntra_store_compact b98cef2bc1cd,
test_controller_input ff612bcfbd0b, test_zyntra_records_page a626d76ba4bf).

## Files

| File | Lines | sha256 (12) | Change |
|---|---|---|---|
| `StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua` (= draft) | 1573 -> 1797 | c23d58572f04 | RECORDS + SETTINGS pages, header active look, every Page_* hidden but the chosen one, `ui.handoff` removed |
| `ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua` (= draft) | 502 -> 566 | 665da0c8a0f0 | `setting`, `settingReady`, `toggleSetting` (the settings send) |
| `ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua` | unchanged | | |
| `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` | 2190 -> 1191 | a4bbd3c68f8c | terminal shell, tabs, both pages, layout, navigation deleted; MUSIC block kept |
| `ReplicatedStorage/UIRegression.ModuleScript.lua` | 9240 -> 8129 | cde884db916d | terminal rows pointed at L4, terminal lane deleted |
| `ReplicatedStorage/ZyntraRecordsPage.ModuleScript.lua` | deleted | | nothing needs it; its manifest item is removed |
| `studio-sync-manifest.json` | | 24a2e2ebc0fd | ZyntraRecordsPage item removed; counts scripts 224 -> 223, total 243 -> 242 |
| `tools/tests/test_zyntra_records_page.py` | deleted | | ported to the L4 harness, section 17 |
| `tools/tests/test_zyntra_store_compact.py` (CRLF kept) | 1254 -> 1267 | 8cd38ce238e2 | rewritten to the new rule, MUSIC lane added |
| `tools/tests/test_controller_input.py` | 330 -> 272 | 59548852817b | terminal focus lane deleted |
| `roblox-draft/tests/test_zyntra_shop_l4.py` | 276 -> 291 | 7ca8d40ca857 | variant `v3` (pages-v3 fixture), ZyntraChallenges source |
| `roblox-draft/tests/zyntra_shop_l4_harness.luau` | 2897 -> 3406 | 0d1a241cb288 | section 17, rewrites below |
| `roblox-draft/install/05_qa_probe_client.luau` | | 32dfab9b4c32 | header comment only |

All Lua compiles with `luau-compile -O0`. Shop L4, ShopData, the harness, its runner and 05 are ASCII + LF;
ZyntraStore, UIRegression and the two tools/tests files were non-ASCII before and gained no non-ASCII.
`cmp` draft vs mirror: Shop L4, ShopData, ShopBinder identical.

## Zyntra Shop L4

- `HEADER_PAGES = {"Records", "Settings"}`: pages without a dock tab. `TAB_ORDER` is untouched, so the dock bind
  loop never asks for a `Tab_Records`.
- `ui.bindHeaderPages`: binds each page by name with its own `need`/`needText` (not purchase-critical). A page
  the import lacks, cannot bind (a missing node, warned by path), or whose header button is missing hides that
  button; all such losses are ONE warn: `[ZyntraShopUI] L4 header pages missing, their buttons are hidden:
  Records, Settings`. The window keeps working. Records/Settings left the "optional nodes missing" list.
- `ui.selectTab` hides every `Page_*` of the import (`ui.allPages` = `Binder.all(window, "Page_")`, unknown pages
  included) except the chosen one, and refuses a page that did not bind (`ui.pages`, was `pages`).
- Active look (BINDINGS.md): TILE fill, BT 0, the button's own ring RAIL TEAL at 4/3 of its resting width,
  `Tab_Shop`'s ActiveBar cloned at 112x8, 4 px off the bottom of the 144 button. All dock tabs show inactive.
  The other header button keeps its import look (INK, 3 px LINE). DEV is cloned before, so it never carries it.
- `ui.focus`: falls back to the header button (`ui.headers[ui.tab].Hit`). ButtonB/Escape/close unchanged.
- The bridge takes "Records" / "Settings" (true only when the page bound). `ui.handoff` is gone.
- `ui.render` renders only bound pages. `ui.knob` mirrors an imported knob to its other stop.
- DEV's font is read from `Header/Title` (the pages add 9 `Title` nodes).
- RECORDS: `ZyntraChallenges.Rows(profile.Records, profile.Challenges, Config.Challenges)`; Eyebrow CLEAN RUNS /
  ASSISTED RUNS; SHOW ASSISTED is client-local, session-long, survives pushes, sends nothing; times via
  `FormatTime` (whole seconds) in CREAM, em dash (`"\u{2014}"`) in SAGE; EQUIPPED per record; NO DEATHS and
  "UNDER m:ss" with the reward always shown (`+n TOKENS`, `+1 TOKEN`) and a DONE / NOT YET chip in the BINDINGS
  colours; Challenge2 hidden on a nil goal; HiddenUntilPlayed + `played()` as the legacy page; a card for a level
  the data lacks is hidden; RecordsList scrolls Y. Text fitting is the existing `scaleText` / `fitLine` (the
  window is solved before binding and every label refits on Text change).
- SETTINGS: one row per visible `Config.AccessibilitySettings` key via `Setting_<Key>`; the whole row
  (`Toggle_<Key>`) is the tap target; Title/Desc from the config; State ON/OFF (RAIL TEAL / SAGE), Track RAIL
  TEAL / #303C40, Knob CREAM right / SAGE left. Lobby music is disabled until its attribute is a boolean.

## ShopData: the settings send

`toggleSetting(key)` fires exactly `ZyntraAction "SetAccessibility" {Key, Enabled}`, draws the new value at once,
clears it when the player attribute agrees (a push does not end it, so not `sendAction`), and silently reverts
after 12 s. A press inside the server's 1 s per-key window is held to 1.1 s after the last send, and a newer press
replaces a held one: the legacy quick ON-OFF defect (dropped press shown for 12 s) is gone. Hidden keys and
unknown keys are refused. Works with a Config that has no AccessibilitySettings (the wall-buy lane loads it so).

## ZyntraStore

Deleted: the terminal frame and UIScale, layoutHooks, pageMounts, the CollectionService contract, TextService
helpers, header/tabs/content/status, `pages`/`selectTab`/`TERMINAL_PAGE_MODULES`, the SETTINGS do-block,
`publishProfile` and the page mount, `setMainVisible`, terminal navigation (focus, `ZyntraCloseTerminal`),
`openTerminal`, the close triggers (CloseTerminal, Escape, Died, Escaped, RoundActive), `applyTerminalLayout`
and `currentTab`. `not main.Visible` terms left `updateVisibility` and `introConditions` (the L4 window counts
through `ScreenOwningModalOpen()`).

Kept: the rail and its ladder, dots and intro card, MUSIC (own block: same action, caption MUTE / UNMUTE / MUSIC,
its own Pending, 12 s revert, not-ready guard), Emergency Re-entry with live price, DEV FREE RESPAWN, the PARTY
DOWN attributes, `lobbyModalOpener`, `ZyntraOpenTerminal` as a router ("Rewards" -> Daily Rewards verbatim, every
other name, Records/Settings included, -> `ZyntraShopUIOpen`), J / DevPhoneCommand, the wall-buy bridge.
`showStatus` is a `warn` stand-in (re-entry errors, profile read failure); push messages reach the L4 toast.
`refreshUI()` is `updateReentry()` (the re-entry tests slice up to it). The Studio probe answers `kiosk` only.
No `"terminal"` literal (frozen dev test).

## UIRegression

- `store-modal`: opens SETTINGS through the L4 probe (`open:Settings`), Requires
  `ZyntraShopL4.Root.WindowHolder`, Forbids the five rail buttons. REWRITTEN: the terminal shell Requires and the
  `TerminalHeader.CloseTerminal` TouchTargets went with the terminal; Check does not reach inside the L4 window,
  so its 44 px / text-fit / state checks live in the L4 harness (sections 4 and 17).
- `BriefingExclusionMatrix`: the modal under test is the L4 window, opened on Records / Settings through its
  probe and on Shop through ZyntraStore's `kiosk`; every row (open, briefing over/under, queue raised over it,
  queue refusing it, movement ownership, cleanup baseline) kept, with `terminal.Visible` -> `shopOpen()`.
- `FULLSCREEN_OVERLAYS`: `Terminal` -> `WindowHolder` (the L4 windows are the modal panels). `INTERNAL_PANELS`:
  `Terminal`, `TerminalHeader` removed.
- Deleted: `ZyntraTerminalFitMatrix` with `Fit.Zyntra*` / `zyntra*` helpers, `PAGE_CONTENT` and its
  `ZyntraConfig` require, the RunAll call, the terminal snapshot in `Fit.borrow/restore/residue`, the terminal
  close in `resetScenario`. Not runnable offline: compiled -O0 only; run `UIRegression.Compact("BriefingExclusionMatrix")`
  and a RunAll in Studio after the install.

## Tests

| Suite | Before | After |
|---|---|---|
| `roblox-draft/tests/test_zyntra_shop_l4.py` | 10299 | **11640** + dump round-trip |
| `tools/tests/test_zyntra_store_compact.py` | 485 | 492 (rail 123, layout 121, routing 78, music 22, chipskin 57, modals 19, wallbuy 19) |
| `tools/tests/test_controller_input.py` | 120 | 102 (terminal lane: 18 checks, now harness 8 + 17) |
| `tools/tests/test_zyntra_records_page.py` | 11768 | deleted (semantics in harness 17) |
| re-entry dismissal 37+5, free respawn 3+8, rail dots 20, challenges 61, friend boost 783, round exit 299, equipment HUD 303, UI style 83, level4 clear 21 | pass | pass |
| frozen `dev-menu/tests` 6877, `daily/tests` 928 (5 drafts == mirrors) | pass | pass |

Harness section 17 (pages-v3, variant `v3`): every Page_* hidden but the chosen one (an unknown `Page_Mystery`
included); header active look and every dock tab inactive; bridge and probe `tab:`; RECORDS ledger, both views,
badges, chips and colours, push keeps the view, close/reopen keeps it, older server, plural, HiddenUntilPlayed
(clear / record / none), nil goal, a card the data lacks; SETTINGS rows, default/attribute readback, music not
ready, exact payloads, attribute confirm, 12 s silent revert, held quick ON-OFF, three presses in one window,
push message to footer + toast; gamepad focus on the header button and ButtonB; partial page (warned path) and
button-less page; the no-import case (one warn, both buttons hidden); DEV clone without the active look; text
inside its box at 1760x1016, PC half size, Studio 443 and 844x390 (>= 11 px, no truncation above k 0.4);
24 no-'//'/no-L<n> scans. Section (4) now measures RECORDS (10) and SETTINGS (13) tap targets, all >= 44 px.

Assertions REWRITTEN to the owner's rules (each says so in place):
harness 0 (PendingText was the only warning: the no-import case adds the header-pages warn), 1 ("never L4" ->
refused without pages), 7 (hands off to the terminal -> no hand-off), (4) (real header 9 -> 7 targets without
pages), (5) (warning count), 15 (ZyntraStore emulation: every route to the bridge; runs on v3), 14 (page list);
store_compact 4 (design size -> the terminal is gone), 6 (tab set, deleted), 11 (Records/Settings open the
terminal -> asked of L4; "J closes the open terminal" -> J refusal opens nothing).

Pre-existing failures, untouched (they fail on ZyntraConfig / server harness drift, not on this work):
`test_lobby_shop_display` (8 vs 10 product textures), `test_lucky_wheel_client` ("five prizes"),
`test_daily_rewards`, `test_support_product_receipts` ("harness has no module ZyntraSkins"),
`test_item_inventory`, `test_leaderboard_backfill`.

## Shipping (main session)

1. Re-import `ZyntraShop_L4` with Live Sync and install this code in the same step (01_templates). Without the
   code the new pages draw over every tab; with the code and no import, RECORDS / SETTINGS hide with one warn.
2. Push ZyntraStore, Shop L4, ShopData, UIRegression; delete `ReplicatedStorage.ZyntraRecordsPage` in Studio
   (its manifest item is already gone). `ZyntraChallenges` must stay in ReplicatedStorage (Shop L4 requires it).
   The manifest shas of the edited scripts are not updated here (`record_pending_push.py` is yours to run).
3. Dump the new import to `tests/framewisp-dump.ZyntraShop_L4.json`, run `build_pages_fixture.py --diff`. The
   harness reads `REAL_HAS_PAGES` from the dump, so sections 0/1/4/5/7/14 switch on their own (verified by
   swapping the fixture in as the real dump). Only the 01_templates text count (`== 156`) and
   `check_go_live`'s footer needle describe the old import and need its new numbers.
4. In Studio: `UIRegression.Compact("BriefingExclusionMatrix")`, a RunAll, and the 05 QA probe.

## Known ceilings

- Settings `Desc` on the two one-line rows is not wrapped (Framewisp follows the sample): a longer config
  description shrinks, then truncates, via fitLine. The shipped strings equal the samples.
- RecordsList's canvas is the import's fixed size: a hidden card leaves its 194 px at the end of the scroll.
- With no pages imported, DEV sits left of two hidden header slots.
- MUSIC's rail press keeps the legacy no-hold behaviour (the rail is never pressable while SETTINGS is open).
- README.md (Settings tab) and CLAUDE.md (2026-09-05 terminal notes) still describe the terminal; not edited here.

## Review fixes (2026-10-07, second pass)

Four confirmed defects. No Studio, no git. Supersedes, above: the ZyntraStore "MUSIC (own block ...)" line, the
Known ceiling "MUSIC's rail press keeps the legacy no-hold behaviour", the test_controller_input row's "now harness
8 + 17", and Shipping step 2's "manifest shas ... not updated here".

| File | Lines | sha256 (12) | Change |
|---|---|---|---|
| `Zyntra Shop L4.LocalScript.lua` (= draft, `cmp` identical) | 1797 -> 1801 | 825b0ecb35a4 | RECORDS Eyebrow left-aligned |
| `ZyntraStore.LocalScript.lua` | 1191 -> 1180 | 798485a43048 | MUSIC sends through `ShopData.toggleSetting` |
| `studio-sync-manifest.json` | | 02959e648231 | four entries `pending-studio-push` |
| `tools/tests/test_zyntra_store_compact.py` (CRLF kept) | 1267 -> 1330 | f7a7505c62ef | MUSIC lane rewritten, ShopData fixture shared |
| `tools/tests/test_controller_input.py` | 272 -> 276 | fc403088f2c6 | docstring: what was ported, what was not |
| `roblox-draft/tests/zyntra_shop_l4_harness.luau` | 3406 -> 3450 | fffb67bb0a80 | Eyebrow check (17), focus / ButtonB port (8) |

ShopData and ShopBinder unchanged (draft == mirror). Every touched file keeps its encoding: Shop L4 and the harness
ASCII + LF; ZyntraStore and the two tools/tests files gained no non-ASCII.

1. **RECORDS Eyebrow off its title (Shop L4 `pages.Records.bind`).** Framewisp imports every hug text centred
   (`TextXAlignment.Center`); the Eyebrow's box is sized for the longer sample ASSISTED RUNS (235 design px), and
   `fitLine` returns untouched when the text fits, so CLEAN RUNS sat ~27 design px right of RECORDS and its TitleBar
   (records.png has it flush). The bind now sets the Eyebrow `Left`; `fitLine` keeps a Left label's x at its left
   edge, so it can still widen. Harness 17 `switchState` (both views, 5 calls) checks `Left` and the box's left
   edge at TitleCol x 0. Verified to FAIL with the line removed ("... in the CLEAN RUNS view").
2. **MUSIC and the SETTINGS row raced the server's 1 s window.** Each kept its own pending state and send clock, so
   a row press, Close, MUSIC within the second (or the reverse) was dropped by the server and drawn wrong for 12 s.
   ZyntraStore's MUSIC block now requires `ReplicatedStorage.ZyntraShopUI.ShopData`, calls `ShopData.start()`
   (idempotent), presses `ShopData.toggleSetting("LobbyMusicEnabled")` and draws its caption from
   `ShopData.setting` / `settingReady` on `ShopData.Changed`. Its own pending/serial, 12 s revert and direct
   `FireServer` are deleted: one Pending, one Sent, the 1.1 s hold and the 12 s revert cover both surfaces. The
   block runs in `task.spawn`, so a missing ZyntraShopUI (Studio's infinite-yield warning) leaves MUSIC on its
   MUSIC caption without holding up the rail or Emergency Re-entry. Gating (Visible, Active, InRound, screen-owning
   modal) is unchanged.
   test_zyntra_store_compact lane 11a REWRITTEN to the new rule (says so in place): it runs the production block
   against the REAL ShopData (the wall lane's fixture, now shared as `shopdata_fixture`) with a stepped `os.clock`.
   "The only timer is the 12 s revert" became "the 1.1 s hold and the 12 s revert"; every other check is kept.
   Added: the review case (row, then MUSIC 0.7 s later: held, sent once after the window, OFF), the reverse (MUSIC,
   then the row 0.5 s later: held), the row reading MUSIC's press, and a static check that the block has no
   `FireServer` and exactly one `ShopData.toggleSetting(KEY)`.
3. **Manifest.** The four entries this work changed are `pending-studio-push` with `studioSha256Before` = their
   old sha and `sha256`/`bytes` = the canonical file (`sha256_of`, as `record_pending_push.py` does, but only
   these four, so other sessions' drift is not swept up):

   | Entry | studioSha256Before | sha256 | bytes |
   |---|---|---|---|
   | ZyntraStore | 74ee23540b22 | 798485a43048 | 54891 |
   | UIRegression | 7075ea19ac95 | cde884db916d | 401638 |
   | Zyntra Shop L4 | d3e90fcd4b12 (batch 2) | 825b0ecb35a4 | 78896 |
   | ShopData | 1da1b4182edd (batch 2) | 665da0c8a0f0 | 23228 |

   `pull_source_from_studio.py` now skips them. If Studio still holds batch 1 for Shop L4 / ShopData, the push tool
   will report a CONFLICT: install the batch-2 snapshot first, or merge, never `--overwrite-conflicts` blind.
   `test_full_sync_contract` now names only `SoundController` and `Level 2 Kit World Builder` (other sessions'
   edits, `record_pending_push.py --dry-run` agrees); before this pass it also named ZyntraStore and UIRegression.
4. **Lost controller coverage.** Harness section 8 now ports the deleted terminal lane's cases to the L4 window:
   B with `GuiService.MenuIsOpen` returns `ContextActionResult.Pass` and the window stays open (B still bound),
   then Sink and closes once the menu shuts; and on Donate, Records and Settings (v3): a Keyboard open leaves
   `SelectedObject` nil, `LastInputTypeChanged` to Gamepad puts focus on `Tab_Donate` / the header button, and a
   close leaves another UI's focus alone. Mutations verified to FAIL: B without the MenuIsOpen pass, no
   LastInputTypeChanged hook, `ui.focus` ignoring LastInput. Not ported (the L4 window has no counterpart): B
   passing during text entry (no TextBox), focus restored to the opener, the tab bar scrolled to reveal a tab.

### Tests (this pass)

| Suite | Before | After |
|---|---|---|
| `roblox-draft/tests/test_zyntra_shop_l4.py` | 11640 | **11658** + dump round-trip (Eyebrow 5, section 8 port 13) |
| `tools/tests/test_zyntra_store_compact.py` | 492 | **522** (rail 123, layout 121, routing 78, music 51, chipskin 57, modals 19, wallbuy 19) |
| `tools/tests/test_controller_input.py` | 102 | 102 |
| `tools/tests/test_full_sync_contract.py` | 1 FAIL (4 files) | 1 FAIL (2 files, other sessions'); 51 ok |
| re-entry 37+5, free respawn 24+3+8, rail dots 20, equipment HUD 303, friend boost 783, round exit 299, UI style 83, challenges 61, level4 clear 21, studio source contract | pass | pass |
| frozen `dev-menu/tests` 6877, `daily/tests` 928 | pass | pass |

Still failing, unchanged and unrelated: `test_lobby_shop_display` (8 vs 10 textures), `test_lucky_wheel_client`
("five prizes"). `test_push_repo_to_studio` cannot execute with this luau build (`--version` is not an option).
`luau-compile -O0`: Shop L4 (mirror and draft), ZyntraStore, ShopData, ShopBinder, UIRegression and the harness OK.
