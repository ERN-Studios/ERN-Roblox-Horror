# L4 Bento Home shop: install (SHOP_UI_L4_20261005)

These steps install the owner-approved L4 shop into the open place. They assume the
four Framewisp imports sit, disabled and with their scripts removed, under
`ReplicatedStorage.ZyntraShopUI.Imports`.

Run every `.luau` step through `execute_luau` (the main session holds Studio).
For example: `python _local/shop-ui-figma/studio-turn/mcp.py <file.luau> Edit`.

## Go-live, 2026-10-07: there is no switch any more

The owner's order: L4 goes live and replaces the old UI. Read this before any step
below; it overrides what they say about a flag or a legacy fallback.

- **`workspace.ShopUIVersion` is gone.** No script reads it. "Zyntra Shop L4" opens for
  every account; "Zyntra Dev L4" is gated by DevAccess only. Step 4 now only clears a
  leftover attribute.
- **There is no legacy shop to fall back to.** ZyntraStore lost its Upgrades, Shop,
  Skins, Donate, Colors and DEV pages; it keeps the rail, the RECORDS / SETTINGS
  terminal, re-entry, PARTY DOWN and the wall's buy bridge.
  - A template the shop needs is missing: the shop warns by name
    (`[ZyntraShopUI] L4 missing: ...`) and does not open.
  - A `Page_<Tab>` other than `Page_Shop` is missing: its dock tab is hidden and warned
    once (`L4 pages missing, their tabs are hidden: ...`); the other pages still work.
  - A skin template (`LobbyRail_L4`, `LuckyWheel_L4`) is missing:
    `<surface> skin skipped: ReplicatedStorage.ZyntraShopUI.<name> is missing`, and that
    surface keeps its own face.
  - `DailyRewards_L4` is no skin any more: since 2026-10-07 it is the template of the
    Daily Rewards window itself ("Zyntra Daily L4"; install and contracts in
    `../../daily-l4/CHANGES.md`). Missing, it is warned and Daily Rewards does not open.
- **"Prices are read live from Roblox." is removed** from the Shop footer. The import
  still carries it as `ShopWindow/Canvas/Footer/Status`'s sample text; the controller
  blanks that at build. Optional tidy-up in Studio: set `Status.Text = ""` on both
  `ZyntraShopUI.ZyntraShop_L4` and its source under `ZyntraShopUI.Imports` (step 01
  re-clones from Imports).
- **Step 3 (`03_zyntrastore_patch.py`) is retired.** Its hunks were the legacy-fallback
  routing, which the go-live rewrote in ZyntraStore itself. Do not run it, and do not
  run its `--revert`. Its test (`tests/test_zyntrastore_patch.py`) was deleted with it.

## What the real import changed (read before installing)

- **The 2026-10-07 Live Sync bundle (`Framewisp_Live_ZyntraBundle_L4`) has all five
  pages** and `Toast`; it carries `ZyntraShop_L4`, `LuckyWheel_L4` and `DevMenu_L4` in
  one `ZyntraBundle_L4` frame. `LobbyRail_L4` and `DailyRewards_L4` are the 2026-10-06
  imports. Every shop tab runs in L4; a page an import lacks hides its tab (go-live).
  - Framewisp imports a tab group's inactive panels hidden: the Skins and Donate
    lists, and five of the dev menu's six. The controllers show every bound row.
  - The Skins grid's cells come in editor pixels; `Binder.scaleText` turns them into
    the cards' Scale.
  - The colour presets are hidden in the design (they overlap SAVE) and stay hidden.
- **The `TextSize` an import holds is not a 1080p size.**
  - It is Framewisp's solve for the editor viewport. The bundle's dumps were taken
    at k = 443/1080 (the 2026-10-06 ones at 361/1080).
  - `Binder.scaleText`, a port of FramewispTextScaler, re-solves text from
    Framewisp's own attributes (`FigmaFontSize`, `FigmaTextW` and `FW_M100`). Step 01
    checks that every text node carries them.
- `PendingText` is still a baked image of the design's sample line, so it is hidden
  and warned once. Only "WAITING FOR ROBLOX..." shows.
- Every pass card has an `OwnedBadge` (the earner's reads ACTIVE).

## Before you start

```
git status                                        # foreign untracked files = another session is active
python tools/pull_source_from_studio.py --audit   # ZyntraStore is known to be newer in Studio than the repo
```

## 1. Templates: `01_templates.luau` (Edit)

This step clones each imported frame to `ReplicatedStorage.ZyntraShopUI.<Frame>` and
copies its ScreenGui's `BB_*` attributes onto the clone. `Imports` stays as it was.
The step is idempotent.

**Expected output:** `"ok": true`.
- `templates.ZyntraShop_L4.missingNames` is `[]`, and `pages` holds all five `Page_`s.
- In `text`, `nodes` equals `figmaFontSize` for every template (156 for the shop).
- `title` shows `TextSize` 31 next to its `FigmaFontSize` (about 61).
- `DevMenu_L4` has `devRows` 14 and `levelChips` 0.
- `importsUntouched` counts `Imports`' children: the bundle, the rail and the daily
  rewards, plus `Superseded_20261006` when step 00 moved older imports there.

**If `ok` is false:**
- A missing `FigmaFontSize` means text scaling has no baseline. Stop here and
  re-import; do not go on.
- A missing name means the binder will refuse the window.
- `duplicates` means two Imports hold the same frame (a second Framewisp run).
  Nothing was written. Ask the owner which import is current, move the other
  out of `Imports`, and re-run.

**Rollback:** destroy the four template frames under `ZyntraShopUI`. `Imports` keeps
the originals.

## 2. Scripts: `02_scripts.md`

Copy the three drafts to their mirror paths. Then run `tools/install_new_scripts.py`:
first `--dry-run`, then for real.

**Expected output:** three `PLAN` lines, then three `VERIFIED` lines, and +3 `synced`
manifest items.

**Rollback:** see that file.

## 3. ZyntraStore routing: `03_zyntrastore_patch.py` (RETIRED 2026-10-07)

**Do not run this step.** It installed the legacy-fallback routing; the go-live
ZyntraStore has its own routing and no legacy pages. Kept below as history.

This was the only edit this install made to an existing script.

```
python artifacts/shop-ui-figma-20261005/roblox-draft/install/03_zyntrastore_patch.py --dry-run
python artifacts/shop-ui-figma-20261005/roblox-draft/install/03_zyntrastore_patch.py
```

**Expected dry-run output:**

```
read     201295 B  sha256 d23ad62e809b  saved ZyntraStore.before.d23ad62e809b.lua
patched  2 hunks: 201295 -> 202362 B  sha256 a6819073eadc  saved ZyntraStore.patched.a6819073eadc.lua
compile  OK: Compiled 4 KLOC ...
DRY RUN: nothing written
```

These figures are from the 2026-10-05 Studio copy. If Studio has moved on since, the
sizes and hashes will differ, and that is fine as long as the patch applies.

**Expected real-run output:** the same lines, then `WRITTEN`,
`VERIFIED read-back sha256 ...` and `COMPILED in Studio`.

**Other outcomes:**
- `ALREADY APPLIED` means a re-run, and the script exits 0.
- `REFUSED` means the anchors moved. Re-derive the patch (see
  `../patches/ZyntraStore.routing.md`).
- `NOT WRITTEN: Studio changed this script between the check and the write` means
  another session wrote ZyntraStore in between. Nothing was written. Re-run: the
  patch is re-applied to Studio's new text, so their lines stay.
- `COMPILE FAILED in Studio` means the bytes landed but Roblox will not compile
  them (the register ceiling). Run `--revert` at once.

The patch is always applied to the source read from Studio in the same run, never to
the repo copy, so lines another session added are kept. The write is a
compare-and-swap: if Studio moved after the read, nothing is written.

**After it is written** (the script has already compiled ZyntraStore in Studio;
it keeps 45 free registers):
1. Run `python tools/pull_source_from_studio.py --audit`, then pull, so ZyntraStore
   is mirrored with the patch.
2. Run the compile probe (`tools/studio_compile_probe.luau`) for the whole place.

**Rollback:**

```
python .../install/03_zyntrastore_patch.py --revert --dry-run
python .../install/03_zyntrastore_patch.py --revert
```

This takes the two hunks back out of the LIVE source through the same
compare-and-swap, so edits other sessions made since the patch survive. (Writing
`out/ZyntraStore.before.*.lua` back would erase them; do not.) Then pull again.
`tests/test_zyntrastore_patch.py` covers apply, re-run, revert, a concurrent edit,
a bad read-back, moved anchors and a half-patched source against a fake Studio.

## 4. Retired switch: `04_flag.luau` (Edit)

`workspace.ShopUIVersion` no longer exists as a switch (go-live 2026-10-07). This
step clears the attribute if an older run left it in the place, and reports the
install. It is idempotent and harmless: nothing reads the attribute.

**Expected output:** `"ok": true`, `"now": null`, and every `installed` entry is
`true` (the six templates, `Zyntra Shop L4` and `Zyntra Dev L4`). `"cleared": true`
only when it found a leftover.

**Rollback:** none needed. There is no legacy UI to switch back to.

## 5. QA in Play (any account)

1. Start Play and wait in the lobby until the rail shows. Any account will do: the
   shop has no switch and no developer gate.
2. Run `05_qa_probe_server.luau` on the **Server** data model. It records the
   baseline `ZyntraStaminaMultiplier` and ownership.
3. Run `05_qa_probe_client.luau` on the **Client** data model three times, setting
   `PHASE` to `"main"`, then `"mobile"`, then `"buy"`. Each call has about 60 s.
   - `"buy"` spends tokens (1 + StaminaLevel) through the real `ZyntraAction`. In
     Studio that profile is in memory only (ZyntraMonetization:
     `persistent = not RunService:IsStudio()`, 25 starting tokens), so nothing
     reaches the DataStore and no Robux moves. If the profile is short of tokens,
     the step reports it instead of passing.
4. Run `05_qa_probe_server.luau` again. `ZyntraStaminaMultiplier` must have risen by
   one level step, and `problems` must be `[]`.

**Expected:** `"ok": true` in each JSON.
- In `main`, `text scale` reports `sizeOverBox` of about 1.6. The editor's
  solve would read about 0.5.
- In `main`, every `tab ...` step passes inside L4. A page the import lacks fails its
  step (there is no legacy page to hand it to).
- In `main`, `prompt ...` shows the recorded `Product:3713829859`. A `GamePass:<id>`
  row appears only if some pass reads unowned; with `Config.Studio.GrantAllPasses`
  on (it is) every pass is owned and `prompt (game pass)` says so. No purchase
  dialog opens: the probe hooks `ShopData.promptHook`, finishes the prompt as a
  cancel and unhooks (the offline harness proves the next press is real again).
- In `mobile`, the 844x390 row must have `under44: []`. The 705x338 row is reported
  only; it is plan open question 1.
- The rail clicks use VirtualInputManager when the context allows it. Otherwise the
  probe takes ZyntraStore's own kiosk path (`openKioskShop`), and `detail.path` says
  which one ran.

## Watch items

- **Advanced Equipment's price label** is authored in the OWNED style (TextSize 12
  in the editor solve, against 17 on the other cards). A player who does not own it
  sees `R$ 149` smaller than the neighbouring prices. To fix it, re-export the card
  in its buyable state; the code does not resize one card to match the others.
- **Long transient captions** such as `CHECKING PRICE` and `UNAVAILABLE` are sized
  by em and can overflow the narrow 300 px Buy buttons. The client probe's
  `price text fits its button` step names any that do.
- **Text above 100 px** (4K and up) is clamped to 100, because Framewisp's UIScale
  spill was not ported. This is marked in ShopBinder with a `ponytail:` comment.
- **Daily Rewards' token pill `+` works** (2026-10-07, "Zyntra Daily L4"): it closes
  the daily window first, then asks the shop for Shop / Tokens20.

## Re-import 2026-10-07: ZyntraBundle_L4 (shop pages + dev menu + wheel)

Framewisp's free plan allows 5 conversions a day. So the three frames that changed
travel in ONE conversion, inside the temporary Figma frame `ZyntraBundle_L4`
(143:2 on "L4 · Roblox export"), which holds clones of ZyntraShop_L4, DevMenu_L4 and
LuckyWheel_L4. Delete that frame once the import is installed.

The owner's rule (2026-10-06) applies to all of them: no "//" and no "L<n>" level
abbreviations in visible text, and no level chips in the dev menu.

1. `00_stage_reimport.luau` (Edit) moves the new `Framewisp_*` ScreenGui from
   StarterGui to `Imports`. Its scripts are destroyed and it is disabled. Any older import
   that holds the same frames moves to `Imports.Superseded_20261006`; nothing is
   deleted.
2. `01_templates.luau` (Edit) now knows `DevMenu_L4` and reads frames one level down
   inside a bundle. Bundled frames get standalone geometry (full size, centred) and
   the bundle's UIAspectRatioConstraint. Expect `"ok": true` with:
   - `forbiddenText` empty for every template;
   - `DevMenu_L4.levelChips` 0;
   - `missingNames` empty;
   - `ZyntraShop_L4.pages` listing all five `Page_*`.
3. `python tools/install_new_scripts.py "StarterPlayer/StarterPlayerScripts/Zyntra Dev L4.LocalScript.lua"`
   (first with `--dry-run`).
4. RETIRED 2026-10-07 (history): `03_zyntrastore_patch.py --patch .../dev-menu/patches/ZyntraStore.devmenu.json`
   put three dev hunks on top of the shop's two. The go-live ZyntraStore has no DEV
   tab and asks `ZyntraDevUIOpen` itself; do not run it.
