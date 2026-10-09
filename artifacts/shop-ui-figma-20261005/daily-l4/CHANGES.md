# Daily Rewards L4: the Figma window replaces the legacy modal (2026-10-07)

The owner asked for this on 2026-10-07: "ui for daily rewards ser gammel ud ... Den skal altsaa vaere figma versionen". The old UI is replaced and deleted.

This work covered code and offline tests only. No Studio, no git and no Codex were used. The main session installs it (see "Install" below) and then runs Play tests with real hit tests.

## Files

| File | What |
|---|---|
| `roblox-draft/daily/StarterPlayer/StarterPlayerScripts/Zyntra Daily L4.LocalScript.lua` = mirror `StarterPlayer/StarterPlayerScripts/Zyntra Daily L4.LocalScript.lua` | **NEW.** The Daily Rewards window. 784 lines, ASCII, LF line endings, compiles at -O0, 158 registers of headroom. sha256 `fa390bb5...a64cf` |
| `roblox-draft/ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua` = mirror | **CHANGED.** Adds `ShopData.claim(minutes)` and `ShopData.refresh()`, and an optional `onTimeout` on the local `sendAction`. Nothing else in the shop's behaviour changed. sha256 `1da1b418...ac518` |
| `roblox-draft/StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua` = mirror | **CHANGED.** Deletes `skinDaily` and its `run("daily rewards", ...)`, and updates one comment. sha256 `f32e2890...6ffb` |
| `StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua` | **DELETED** from the mirror. |
| `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua` | **DELETED** from the mirror. Nothing else required it. |
| `tools/tests/test_daily_rewards_page.py`, `tools/tests/test_daily_rewards_client.py` | **DELETED.** They tested the deleted page and client. The client test was already failing at HEAD. |
| `daily-l4/backup/` | Copies of the four deleted files, for rollback. The client copy hashes to `f09c8a62...`, the manifest's synced sha. |
| `roblox-draft/daily/tests/test_zyntra_daily_l4.py` and `zyntra_daily_l4_harness.luau` | **NEW.** The window's harness (see Tests). |
| `roblox-draft/tests/zyntra_shop_l4_harness.luau` and `test_zyntra_shop_l4.py` | The `legacyMilestone` and `legacyDaily` fixtures are gone. The skinDaily checks were rewritten to the new rule (below). The 05 smoke plants the daily bridge. A static check was added: the shop contains no `skinDaily` and no `DailyRewardsGui`. |
| `roblox-draft/install/05_qa_probe_client.luau` | The step `daily skin` became `daily window`: the legacy `DailyRewardsGui` is absent and `PlayerScripts.ZyntraDailyUIOpen` is present. |
| `roblox-draft/install/README.md` | `DailyRewards_L4` is no longer a skin. The pill's `+` now works. |

**Untouched:**
- every server script, `ZyntraMonetization`, `ZyntraDailyResearch` and `Config.DailyRewards`;
- `UIDevice`, which still counts `DailyRewardsOpen`;
- `ZyntraStore`: its rail REWARDS, `ZyntraOpenTerminal "Rewards"`, red dot and intro card all still fire or read what they did;
- `Lucky Wheel Client`, `UIRegression` and `ShopBinder`.

## Deleted blocks

- **Zyntra Shop L4 `skinDaily`** (old lines 1319-1382) and `run("daily rewards", skinDaily, "DailyRewards_L4")` (old line 1401). It waited 10 s for `PlayerGui.DailyRewardsGui` and then recoloured the legacy shade, panel, header and cards. It also grafted a TokenPill whose "+" was dead.
- **Daily Rewards Client** (all 646 lines). It held the modal shell, its own profile copy, `OpenDailyRewards` and the probe. Each duty moved to the new window, and nothing client-side was left over: playtime accounting is server-side.
- **ZyntraDailyRewardsPage** (all 875 lines).

## New contracts

### Opening
- **`PlayerScripts.OpenDailyRewards`** (BindableEvent). Whichever side loads first creates it, with the same create-if-absent rule ZyntraStore uses. The window listens to it, so ZyntraStore's rail REWARDS and `ZyntraOpenTerminal "Rewards"` open it with **no ZyntraStore change**. The harness proves an opener that ZyntraStore created first is reused and opens the window.
- **`PlayerScripts.ZyntraDailyUIOpen`** (BindableFunction).
  - `Invoke("open" | nil)` returns true when the window is open afterwards.
  - `Invoke("toggle")` returns that too.
  - `Invoke("close")` returns false.
  - It exists from the first frame and answers false until the modules load, or if the import fails to bind.
- **Refusals:** `InRound`, `QueueModalOpen`, and `UIDevice.ScreenOwningModalOpen()`, so it never opens over another modal.

### The open modal
- **`DailyRewardsOpen`** (player attribute) is true while the window is open and **nil** when it is closed, never false. Writing it comes before `UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())`.
- **Inputs:** gamepad B is bound at High priority as `ZyntraDailyL4Close`. It passes while the Roblox menu is open.
- **Focus:** a gamepad focuses the X when the window opens, and also when a pad is picked up while it is open. Closing clears the selection.
- **Closers:**
  - the X, Escape (unprocessed) and gamepad B;
  - `InRound` or `QueueModalOpen` becoming true;
  - `workspace.RoundActive` becoming true;
  - `GuiService.MenuIsOpen`.

### The gui
- **`PlayerGui.ZyntraDailyL4`**: DisplayOrder 117 (the legacy order, under the wheel's 118), ResetOnSpawn false, ZIndexBehavior Sibling.
- **Mount**, the same as Shop L4:
  - The artboard sits at ZIndex 1 and is transparent (the import's opaque #05090B fill was the backdrop). Its 16:9 lock is removed.
  - A transparent Active `Dim` is created, because the import has none.
  - `WindowHolder` sits at ZIndex 2. Inside it, `WindowFit` has the aspect of the panel (1680x1020, not the 1036-tall modal) and holds `ModalShadow` (z1, dropped 16/1020) and `DailyRewardsPanel` (z2).
- **Fit**, the same as Shop L4's `ui.fit`:
  - PC: half size, centred, never under 400 px.
  - Touch: the safe area's full height.
  - TV: full size.

### Data
- **`ShopData.claim(minutes)`** sends `ZyntraAction("ClaimPlaytimeReward", {Minutes = n})`.
  - Its pending key is `"Daily:<n>"`, with one request in flight per milestone. Any push clears it.
  - A re-press inside the server's 1 s window is held until the window passes, through ShopData's existing `sendAction`.
  - After 6 s with no answer, it shows "No answer yet. Try again." (error) and calls `ShopData.refresh()`. It never grants locally.
- **`ShopData.refresh()`** forces a `ZyntraGetProfile` re-read. An answer older than a newer push is dropped.

### Studio probe
`ZyntraDailyL4.UIRegressionZyntraDailyL4Probe` takes these actions:
- `open` / `close` / `toggle`
- `cards`: one id per control:
  - `Daily|Header|Close`
  - `Daily|Header|AddTokens`
  - `Daily|Milestone5|Claim`, `Daily|Milestone15|Claim`, `Daily|Milestone35|Claim`
  - `Daily|WheelLink|Spin`
- `state`: one line per control, `<id>|<caption>|<active>`.
- `press:<id>`: runs the real handler, only while the control is Active.

Every control also carries the attribute `ZyntraDailyL4Card`.

## What it renders

### Header
- The gift art is `rbxassetid://117126194981100`.
- The eyebrow becomes the **text** "ZYNTRA DAILY" (RobotoMono Bold, teal, FigmaFontSize 29.6, the L4 eyebrow type). The import's eyebrow is a baked image of "ZYNTRA // DAILY".
- The token pill shows `profile.Tokens`, or "--" before the profile loads.
- **"+"** closes Daily first, then calls `ZyntraShopUIOpen:Invoke("Shop", "Tokens20")`.

### Playtime and the countdown
- **Active play:** m:ss, with an hours field from one hour on. It reads "--:--" before the profile loads. If `Day ~= Today`, it reads 0.
- **RESETS IN:**
  - hh:mm:ss, re-anchored on every new profile;
  - ticks at 1 Hz only while the window is open (a `task.delay` loop, stopped when it closes);
  - at 0, one re-read, and its answer re-anchors the clock.
- **Bar:** the fill is played divided by the last milestone, drawn from the left. Tick5 and Tick15 sit at Minutes / last, from Config; a tick with no milestone is hidden.
- **Caption:** "m:ss to the N minute reward", then "Every milestone reached today." When `Config.DailyRewards` is missing it reads "Daily rewards are not configured on this server." in coral, and the cards and the wheel row are hidden.

### Milestone cards
Cards are bound by the legacy name `Milestone<min>`.
- The threshold reads "N MIN". The reward name comes from the config the server grants from, so the shield's name is `ProtectionItem.Name`.
- Reward art is keyed on the reward: token `93116899475472`, potion `120211340805188`, shield `126728249949579`.
- Milestone5's baked reward name is replaced by a wrapped text label cloned from Milestone15.
- The reward names are wrapped, two-line boxes.
- A card the config does not have is hidden.

The claim states, in priority order:

| State | Look | Enabled |
|---|---|---|
| CLAIMED | owned | no |
| CLAIMING... | off | no |
| CLAIM | equip, cream with its BuyShadow | yes |
| "m:ss TO GO" | off | no |
| LOADING (before ZyntraProfileLoaded) | off | no |

The caption's type follows the **state**, not the card. Every state other than CLAIM takes the import's TO GO type, so the 5 MIN card's "4:59 TO GO" is small and the 15 MIN card's CLAIM is big.

### Research rows
- Rows are bound by `Key` (`Research<Key>`), not by array index.
- Done/Value reads 1/1 (chip filled RailTeal, ink text) or 0/1 (TileHi, sage).
- The title and "+Reward" come from the server.
- Before the profile loads, every row reads 0/1; the import's sample shows Fuse as 1/1.
- A goal the server stops sending is hidden.

### LUCKY WHEEL row
The row is built at runtime from a clone of the last research row, so the Figma export is not needed again. It goes in the same list, at LayoutOrder +1.

- **Size:** 136 design px tall. Info is 294 wide, and the chip is 150x80, as in the design.
- **Icon:** the rail's wheel icon, `rbxassetid://115596488996319`.
- **Text:** the title reads "LUCKY WHEEL". The hook is in RobotoMono teal.
- **States:**
  - "FREE SPIN READY" / SPIN, teal: `WheelDay ~= Today`.
  - "PRIZE WAITING" / OPEN, teal: `WheelLast.Claimed == false`, from any day.
  - "SPUN TODAY" / OPEN, grey.
- **Input:** one hit covers the whole row. Pressing it closes Daily first, then fires `PlayerScripts.OpenLuckyWheel`. The window never sends `SpinDailyWheel`.

### Server messages
A server message takes the note's place for 6 s, in its tone: success RailTeal, error coral, otherwise sage. It goes in its own `Message` label, which is wrapped and two lines tall. The longest server line ("Play 15 minutes ... You are at 12 minutes.") does not fit one line at the phone's 11 px floor.

## Decisions to confirm with the owner

1. **Research Detail copy.**
   - The window keeps the **design's** Detail lines: "Insert a fuse in Level 1." and "Pull a powered lever in Level 1."
   - The server sends "Personally insert ..." and "Personally activate ...".
   - The Detail field is display-only, and the server's lines clip in the rows' one-line boxes on a phone.
   - The titles and rewards still come from the server.
   - To use the server copy instead, change `ZyntraDailyResearch.Goals[].Detail` (a server-side data change) or give the rows taller boxes.
2. **The wheel row is always shown** once the profile has loaded, in one of its three states. The Figma prototype bound its visibility to "spin available".
3. **COUNTING (R13) is not drawn.** Playtime only accrues in a round, and this window closes on `InRound`, so COUNTING could never be true while the window is up. For the same reason, active play, the caption and the TO GO captions only change on a push or a re-read. The reset countdown is the one clock that ticks.

## Install (main session; Studio)

1. **Lock first.** Take the Studio lock in `_local/studio-lock.json`, run `pull_source_from_studio.py --audit` and `git status`. Expect foreign edits.
2. **Install the new script:** `python tools/install_new_scripts.py --dry-run "StarterPlayer/StarterPlayerScripts/Zyntra Daily L4.LocalScript.lua"`, then the same command without `--dry-run`.
3. **Push the two changed scripts** with `record_pending_push.py` and `push_repo_to_studio.py`: `ReplicatedStorage.ZyntraShopUI.ShopData`, then `Zyntra Shop L4`.
   - The manifest's synced shas are ShopData `b975f21f2650` and Shop L4 `8b4119cdfaa2`.
   - The new shas are listed under Files above.
4. **Delete the legacy scripts in Studio:**
   - `StarterPlayer.StarterPlayerScripts["Daily Rewards Client"]`
   - `ReplicatedStorage.ZyntraDailyRewardsPage`

   Then remove both items from `studio-sync-manifest.json`; this work did not touch the manifest. **Do steps 2 and 4 in one sitting.** While the old client lives, both windows listen to `OpenDailyRewards`, and REWARDS would open two.
5. **No template work.** `DailyRewards_L4` is already installed (`01_templates`). No new image is uploaded; every art id above is already in use in the place.
6. **Play test with real clicks or taps:**
   - Run the 05 client probe; `daily window` must pass.
   - Open from the rail REWARDS.
   - Press CLAIM on a reached card.
   - Press X, Escape and gamepad B.
   - Press SPIN, which must open the wheel.
   - Press "+", which must open the shop on Tokens20.
   - At 844x390 with `ForceTouchUI`, every target must be at least 44 px. The fake measures 44.27 px for all six.
   - The PC window must be half size.
   - **Look at the Fuse and Clear Detail lines on the phone.** In the fake's font metrics, the import's own sample lines run past their one-line boxes at the 11 px floor.

## Tests (luau 0.737)

| Suite | Result |
|---|---|
| `roblox-draft/daily/tests/test_zyntra_daily_l4.py` (new, on the REAL dump) | **pass, 921 checks**, 171 text scans with no "//", no L<n> and no "read live from Roblox". Static checks: ASCII, LF, -O0, headroom 158; 4 drafts equal their mirrors; the legacy files are gone and no mirror code still names them; ZyntraStore still fires `OpenDailyRewards`; UIDevice still lists `DailyRewardsOpen`. |
| `roblox-draft/tests/test_zyntra_shop_l4.py` | **pass, 1266** (was 1283). The skinDaily checks were **rewritten to the new rule**: the shop never waits for, grafts into or warns about a daily gui, with or without one in PlayerGui. |
| `roblox-draft/dev-menu/tests/test_zyntra_dev_l4.py` | **pass, 6861** (unchanged) |
| `tools/tests/test_zyntra_store_compact.py` | **pass, 485** (unchanged) |
| `tools/tests/test_friend_boost.py`, `test_level4_clear_persistence.py` | pass |
| `tools/tests/test_daily_rewards.py`, `test_lucky_wheel_client.py`, `test_support_product_receipts.py`, `test_item_inventory.py`, `test_leaderboard_backfill.py` | **fail, already failing before this work**: their harnesses have no `ZyntraSkins` fixture. They test the server or the wheel; nothing here touched them. |
| `tools/tests/test_lobby_shop_display.py` | **fail, unrelated**: "expected 8 product textures, found 10". |

The daily harness drives:
- every claim state, the pending latch, the 6 s timeout re-read and the held re-press;
- the timers ticking, stopping when closed, re-anchoring, and the one re-read at 0;
- research 0/1 to 1/1 by Key, with the list order reversed;
- the wheel row in its ready, prize and spun states, and SPIN closing Daily before firing;
- the "+" hand-off;
- open and close through X, Escape, B, the menu, and every auto-close and refusal;
- the opener ZyntraStore created first;
- art and baked-text replacement;
- an explicit check that **the artboard and its Dim sit under the window holder**, including an import ZIndex of 1158;
- the PC half fit, the TV fit, and the 844x390 touch fit with the 44 px floor;
- the line fit at design size, 1080p and phone size in five states, the phone's 11 px floor, and no runtime text cut;
- offline;
- broken imports and hidden-imported controls;
- the width-exact stamps being dropped on clones;
- the probe.

Eight mutations of the controller were each caught: art ZIndex 4, SPIN not closing first, no pending state, a false attribute, PC_SCALE 1, a dim backdrop, a missing wheel row constant, and an untyped claim caption.

## Left alone (optional)

- **ZyntraStore comments** at lines 164, 647-653, 1289, 1531-1534 and 1547 still name "Daily Rewards Client" and "DailyRewardsGui 117". They are comments only, so a Studio push of ZyntraStore just for them was skipped.
- **ZyntraStore still draws "//"** in its re-entry and dev captions (lines 1055-1105 and 1674). That is not daily UI.
- **Docs:** `CLAUDE.md` and the vault still describe "Daily Rewards Client" in their history notes.

## Review fixes (2026-10-07, second pass)

Three confirmed defects, fixed in code and offline tests only (no Studio, no git, no Codex). Each draft still equals its mirror byte for byte.

### 1. The PC 400 px floor is now measured on the window, not on the holder
- **Defect.** `ui.fit` took `scale = max(PC_SCALE, 400 / height)` from the ModalViewport's height. When the viewport is narrower than the window's aspect, the aspect-locked `WindowFit` is width-bound inside the holder, so the window came out shorter than 400 px:
  - Daily at 1256x950 (a 1280x1024 5:4 monitor): 381 px.
  - Shop and Dev at 1256x950: 362.5 px.
- **Fix.** The same fix went into all three controllers that carried the formula: **Zyntra Daily L4, Zyntra Shop L4 and Zyntra Dev L4**. Dev L4 was not in the report, but it had the identical line.
  - Each `build` stores `ui.design = design`, the size the `UIAspectRatioConstraint` locks to: Daily 1680x1020, Shop 1760x1016, Dev its window.
  - `ui.fit` now computes `fitH = min(height, width * design.Y / design.X)` and `scale = min(1, max(PC_SCALE, PC_MIN_HEIGHT / fitH))`.
  - Touch and TV are unchanged. Every earlier fit case gives the same numbers as before: 1256x668 -> 400 tall, 1080p -> half, 800x350 -> fills.
- **Tests.**
  - Daily test 11 and Shop test 9 gained the viewports 1256x950 and 1000x694 (about a 1024x768 client). Each asserts that the window, fitted to its aspect inside the holder, is at least 400 px tall.
  - The dev harness's fake `UIDevice.Layout` now reads an optional `ctx.ModalViewport`. Its test 6 runs four viewports per template variant: 1256x668, 1080p, 1256x950 and 1000x694.
  - All three new checks fail with the old formula (mutation run: 381.3 / 362.5 / 362.5 px).

### 2. The LUCKY WHEEL row matches Figma 52:2164
- **Border.**
  - `buildWheelRow` keeps the row's own `UIStroke` (cloned from ResearchClear) as `wheel.Stroke`.
  - `render` colours it with the chip: `P.IconTeal` while a free spin or a prize is waiting, `P.Line` once spun today.
  - The research rows keep their grey Line border.
  - The row is drawn by the same `render` that makes it visible, so the build sets no colour.
- **SPIN / OPEN label.** The label now wears CLAIM's import face, `ui.faces.Claim.Font` (Montserrat Heavy). If the import carries no CLAIM sample, it falls back to `Font.new(Montserrat, Heavy)`. Before, it wore the narrow RobotoCondensed of the cloned "+2". The label's FigmaFontSize is unchanged. Binder's `em` (Montserrat 1.219) and `fitLine` size it, so a wider word shrinks instead of clipping.
- **Tests (daily test 9).**
  - Teal border on the ready row.
  - The research rows keep `P.Line`.
  - The chip's family and weight equal the import's CLAIM label (Montserrat, Heavy).
  - The border greys when spun today and turns teal again on a new day.
- **Fake engine.**
  - The fake measures text with a per-import-node glyph advance, and the chip's advance was the narrow "+2" one.
  - Test 12 therefore now gives the wheel chip the CLAIM label's advance before its clip sweeps, so SPIN and OPEN are measured as the wide face. They still pass at design size, 1080p and the phone.
  - A real Studio look is still the final check.
- **Mutations caught:** the render border line removed, and the font line removed.

### 3. `tools/tests/test_zyntra_records_page.py` runs again
- **Defect.** The suite imported `PRELUDE, section` from the deleted `test_daily_rewards_page.py` and stopped at `ModuleNotFoundError`. That silently dropped the offline coverage of ZyntraRecordsPage, which is still live through ZyntraStore's RECORDS.
- **Fix.**
  - `section()` and the static `PRELUDE` raw string (backup lines 64-329, unchanged) are inlined into `test_zyntra_records_page.py`.
  - The import and the now unused `sys` import are gone.
  - The docstring no longer names the deleted file.
  - The old file is not restored: it also read the deleted `ZyntraDailyRewardsPage` at module level.
  - The file keeps its CRLF working-copy endings.
- **Guard.** `check_static` in `test_zyntra_daily_l4.py` now also reads every `tools/tests/*.py` and fails if any names `test_daily_rewards_page` or `test_daily_rewards_client`. It also checks the Dev L4 draft against its mirror and compiles it, which makes 5 mirrors.

### Install delta (main session)
This adds **`Zyntra Dev L4`** to the push list:
- manifest synced sha `4f613d01...`, new sha `b96f9e8d...cdfa`.

Updated shas:
- **Zyntra Daily L4** (new script, install_new_scripts): `f6d9cd27...9b81`, 793 lines, ASCII, LF, headroom 158.
- **Zyntra Shop L4:** `fd64f253...6986`.

ShopData is unchanged from the first pass. Play-test addition: set the Studio window to about 1280x1024 or 1024x768. The Daily, Shop and Dev windows must each be at least 400 px tall, and the wheel row must show a teal border and a wide SPIN.

### Tests (luau 0.737)
| Suite | Result |
|---|---|
| `roblox-draft/daily/tests/test_zyntra_daily_l4.py` | **pass, 928 checks** (was 921), 172 text scans; 5 drafts equal their mirrors; headroom 158 |
| `roblox-draft/tests/test_zyntra_shop_l4.py` | **pass, 1268** (was 1266) + dump round-trip |
| `roblox-draft/dev-menu/tests/test_zyntra_dev_l4.py` | **pass, 6877** (was 6861); Dev L4 headroom 168 |
| `tools/tests/test_zyntra_records_page.py` | **pass, 11768** (was ModuleNotFoundError) |
| `luau-compile -O0 --null` on Zyntra Daily / Shop / Dev L4 | OK |
