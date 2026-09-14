# Trello #68 — Zyntra terminal: shrink page CONTENT on touch

**Card:** 28-day analytics — Phone 47.7%, PC 32.3%, Tablet 20.0%. 67.7% of the
audience is on touch. The shop and upgrades pages are too big on a phone; the
tabs may keep their size, the contents must shrink.

## Files changed

| File | What |
|---|---|
| `G:\Roblox\MongoTV\StarterPlayer\StarterPlayerScripts\ZyntraStore.LocalScript.lua` | Upgrades block (`makeUpgradeCard`, new `upgradeCards` registry, rewritten Upgrades layout hook), Shop block (tiered layout hook, `Icon` added to the `productCards` entry), Protection card block (its redundant one-line layout hook deleted) |
| `G:\Roblox\MongoTV\tools\tests\test_zyntra_store_compact.py` | **new** — offline check, extracts the tier tables and the two height expressions from the real source |

**Nothing else was touched.** No edit to `UIRegression.ModuleScript.lua`,
`UIDevice.ModuleScript.lua`, the `fit` table in `applyTerminalLayout`, the tab
bar, header, close button, status label, the DEV `controls` table or its row
builder, GameManager, Studio, git or the manifest. The `fit` table needed **no
new field** — `fit.Compact`, `fit.Touch`, `fit.Tap` and `fit.ContentWidth`
already carry everything the three tiers need, so the diff stays inside the two
page blocks.

The working copy already contained another engineer's DEV-page work (FREE
RESPAWN / PLAYER ESP rows, `DevRespawnSerial` readback). Those hunks are theirs,
not mine; I did not touch them.

## The change

Three tiers, selected identically in both hooks:

```lua
})[(fit.Compact and fit.Touch) and 1 or (fit.Touch and 2 or 3)]
```

1. **phone** — `fit.Compact and fit.Touch`
2. **tablet** — `fit.Touch`, not compact
3. **pointer** — neither; **the authored card, to the pixel**

Each tier is one row of a table literal inside the hook (no new chunk-level
local beyond `upgradeCards`; the file compiles, so it is still under Luau's
200-register ceiling). Every box in a row is a **floor the measured copy may
grow past**, never a ceiling text can be cut to — which is what makes the
smaller faces safe.

### Upgrade card

| | pointer (unchanged) | tablet | phone |
|---|---:|---:|---:|
| pad | 18 | 16 | 14 |
| title face / box floor | 22 / 34 | 18 / 26 | 16 / 22 |
| description face / box floor | 14 / 72 | 13 / 44 | 12 / 32 |
| percent readout face / box | 44 / 80 | 36 / 52 | 28 / 40 |
| level face / box | 13 / 24 | 12 / 20 | 11 / 18 |
| button | `max(Tap,48)` = **48** | `max(Tap,44)` = **44** | `max(Tap,40)` = **44** |
| **nominal card height** | **330** | **246** | **210** |

The pointer row's floors sum to exactly the authored
`18+34+8+72+10+80+24+18+48+18 = 330 = UPGRADE_CARD_HEIGHT`, and the child
offsets it produces are the authored `18 / 60 / 142 / 222`, button at
`UDim2.new(0, 18, 1, -66)`, width inset `-36`. Byte-identical.

Title and description are now **measured across the set** (`textHeightFor` at
the real column width, max over all three cards) so the percent readouts on a
row stay level with each other, the way the fixed boxes did.

### Shop card

| | pointer (unchanged) | tablet | phone |
|---|---:|---:|---:|
| pad | 14 | 14 | 10 |
| icon / icon top | 76 / 18 | 64 / 16 | 52 / 12 |
| `copyLeft` / `copyInset` | 104 / 118 | 92 / 106 | 72 / 82 |
| product name face | 18 | 16 | 14 |
| description face | 12 | 12 | 11 |
| pass tag face | 10 | 10 | 10 (authored, unchanged) |
| buy button | `max(Tap,38)` = **38** | **44** | **44** |
| cell height | `body + 16 + buy + 12` | `body + 16 + buy + 12` | `body + 10 + buy + 8` |

The icon's `UICorner` is **not** touched: the engine clamps `CornerRadius` to
half the smaller side, so the authored 38px radius still draws a circle at 76,
64 and 52.

### Breakpoints re-derived (no stale constants)

* **Upgrades:** the authored `fit.ContentWidth >= 520` is gone. Two columns now
  require the column to hold the widest string the card draws — which is the
  **SPEND button's label**, not the title — at the tier's own faces, plus
  `TEXT_FIT_SLACK`. Measured with `textWidthFor`, the same idiom the Shop hook
  uses.
* **Shop:** the existing name-width test kept its shape but now measures at
  `face.Title` against the tier's own `copyInset`, so the smaller icon buys real
  column width instead of being ignored.

Result: **every fixture keeps its current Upgrades column count**, and the Shop
gains a second column on three landscape-phone fixtures where the old 76px icon
had forced one (see the table below).

## Per-viewport numbers (from the layout math)

Terminal geometry reproduced from `applyTerminalLayout`; text heights from the
card copy at each tier's face and column width. "cell" is the grid CellSize.

| Viewport | tier | terminal / ContentWidth × ContentHeight | Upgrades before | Upgrades after | Shop before | Shop after |
|---|---|---|---|---|---|---|
| **phone 956×440 landscape** | phone | 840×345, 816×201 | 2col 400×**330**, btn 48 | 2col 400×**210**, btn 44 | 2col 400×**184**, icon 76 | 2col 400×**157**, icon 52 |
| **phone 440×956 portrait** | phone | 416×610, 392×466 | 1col 384×**330** | 1col 384×**210** | 1col 384×**184** | 1col 384×**157** |
| phone 705×338 | phone | 681×286, 657×142 | 2col 320×330 | 2col 320×**210** | **1col** 649×166 | **2col** 320×**170** |
| phone 667×375 | phone | 555×302, 531×158 | 2col 257×330 | 2col 257×**220** | **1col** 523×170 | **2col** 257×**183** |
| phone 568×320 | phone | 544×268, 520×124 | 2col 252×330 | 2col 252×**220** | **1col** 512×170 | **2col** 252×**183** |
| phone 375×667 | phone | 351×610, 327×466 | 1col 319×330 | 1col 319×**210** | 1col 319×198 | 1col 319×**170** |
| phone 338×705 | phone | 314×610, 290×466 | 1col 282×330 | 1col 282×**210** | 1col 282×212 | 1col 282×**183** |
| **tablet 1024×768** | tablet | 840×610, 800×430 | 2col 392×**330** | 2col 392×**246** | 2col 392×**184**, icon 76 | 2col 392×**184**, icon 64 |
| tablet 1180×820 | tablet | 840×610, 800×430 | 2col 392×330 | 2col 392×**246** | 2col 392×184 | 2col 392×184 (icon 64, copy 286) |
| tablet 820×1180 | tablet | 796×610, 756×430 | 2col 370×330 | 2col 370×**246** | 2col 370×184 | 2col 370×184 (icon 64, copy 264) |
| **PC 1920×1080** | pointer | 840×610, 800×432 | 2col 392×330, btn 48 | **2col 392×330, btn 48** | 2col 392×178, icon 76, buy 38 | **2col 392×178, icon 76, buy 38** |
| **PC 1366×768** | pointer | 840×610, 800×432 | identical to 1920×1080 | **unchanged** | identical | **unchanged** |

What the card asked for:

* **956×440 landscape phone.** Both upgrade cards are in row 1 and that row went
  **330 → 210** against a 167px-tall scroll (201 page − 34 intro): from 2 full
  screens of scrolling to a 43px nudge. The Shop's first row is **157 in a 201px
  page — fully visible**, and all six cards now take 495px of canvas instead of
  576.
* **440×956 portrait phone.** Single-column cards: upgrades **330 → 210**
  (−36%), shop **184 → 157** (−15%). The three stacked upgrade cards need
  3×210+2×12 = **654px of canvas instead of 1014** against a 432px scroll — 1.5
  screens instead of 2.3. The six shop cards drop from 1164 to 1002.
* **Tablet.** Moderate: upgrades −25% (330 → 246), shop icon 76 → 64 which buys
  the copy 12px of column at the same cell height.
* **PC.** Byte-identical at both desktop fixtures.

The tablet Shop cell stays 184 because the description simply reflows into the
12px of column the smaller icon frees; that is the measured stack doing its job,
not a missed shrink.

## UIRegression coverage

`Fit.bodyZyntraTerminalFitMatrix` (`ReplicatedStorage/UIRegression.ModuleScript.lua`,
starts ~line 5139) runs all 11 `Fit.Devices` rows × every tab. **No assertion
needed changing** — nothing in the matrix hardcodes 330, 76, 104 or 118, and I
grepped for each. `PAGE_CONTENT.Upgrades = {2,2}` and `.Shop = {6,6}` are floors
the pages still clear (3 and 6). `Fit.ZyntraExpectedActive.Upgrades = 2` is
untouched: this change never alters an action's `Active`.

Rows that actually exercise the change, per device × per page (Upgrades, Shop):

| Assertion | What it now proves |
|---|---|
| `…: every card or row is contained horizontally and none has a zero or negative size` | the new `CellSize` in both column modes |
| `…: no two cards or rows overlap each other` | a cell shorter than its measured stack would overlap the row below |
| `…: the scroll canvas reaches its last row, measured from a canvas reset to zero` | `AutomaticCanvasSize` against the new cell heights |
| `…: and where the content overflows the viewport the page can actually be scrolled` | same |
| `…: no visible string overflows its own box` | **the row for this change** — every re-faced label against its new box: `UpgradeTitle`, `Description`, `Percent`, `Level`, `Spend`, `ProductName`, `ProductDescription`, `PassTag`/`ChargeCount`, `Buy` |
| `… / Shop: every product description box holds its own copy at its own width` (~line 5782) | the named Shop proof, re-measured through `GetTextBoundsAsync` at the new 11px/12px face and the new `copyWidth` |
| `… : every authored card has exactly one tagged action, drawn at the terminal's own tap floor on both axes` (`Fit.zyntraActionProblems`, ~line 5072) | `Spend` and `Buy` rectangles: 44×44 on the 9 touch rows, 32 on the 2 desktop rows |
| `…: holds its authored content (N+ rows, N+ actions)` | 3 upgrade cards / 6 product cards still built |

Tier coverage across the fixtures: **phone** — 956×440, 440×956, 705×338,
568×320, 667×375, 375×667, 338×705 (7 rows). **tablet** — 1180×820, 820×1180
(2 rows). **pointer** — 1920×1080, 1366×768 (2 rows, must come back
byte-identical).

Also relevant: `makeUpgradeCard`'s title label is now **named** `UpgradeTitle`
and **TextWrapped**. Named so a clipping report can say which label overflowed;
wrapped because the hook measures it at a wrap width, which is only the truth
about what gets drawn if the label wraps. `UpgradeTitle` cannot collide with
UIRegression's Colors-page `node.Name == "Title"` check — that loop is gated on
`if name == "Colors"`.

## Verification

**1. Compile — PASS.**

```
C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe --null \
  StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua
Compiled 3 KLOC into 99 KB bytecode
```

This also clears the register question: the one new chunk-level local
(`upgradeCards`) did not push the file over Luau's 200-register ceiling.

**2. Offline check — PASS.**

```
python tools/tests/test_zyntra_store_compact.py
ok  upgrade card 210/246/330px (phone/tablet/pointer), shop icon 52/64/76px
```

No `LUAU_BIN` needed — the check is pure arithmetic over numbers **extracted
from the real source**, so it fails when the source moves rather than agreeing
with a private copy. It pulls both `local face = ({…})[…]` tier tables by regex,
and asserts the two height expressions and the tier selector are present
verbatim (string markers, the `test_round_loading_host.py` idiom) so the Python
mirror cannot silently drift from the Lua. It asserts:

* pointer upgrade stack **== 330** with child offsets `18/60/142/222`, button 48
  at `-66`, inset `-36`;
* pointer shop `copyLeft == 104`, `copyInset == 118`, icon bottom 94, buy 38,
  `cellHeight == body + 16 + 38 + 12`;
* phone upgrade card **210 < 260** and never shorter than the parts it is made
  of; a 3-line description grows it to 220 rather than clamping (measured, not
  clipped);
* phone < tablet < pointer;
* every tier's action ≥ 44 on touch (upgrade `Spend` and shop `Buy`);
* no face below 11 in either table;
* shop cell ≥ icon bottom + buy height, on every tier.

**3. Not verified offline — needs a Studio run.** The lead should run
`Fit.bodyZyntraTerminalFitMatrix`. Specifically:

* The real `TextService:GetTextSize` line counts. Every number in the per-device
  table above uses a character-width estimate for the copy; the *floors* and the
  *stack arithmetic* are exact, the measured description heights are not. The
  cards can only come out **taller** than quoted, never clipped.
* The two desktop rows must come back byte-identical. The arithmetic says they
  will; only a Studio run proves the engine agrees.
* `GetTextSize` (layout) and `GetTextBoundsAsync` (the Shop proof at ~line 5782)
  "do not agree to the pixel". The measured description box carries **no slack**
  — exactly as before this change, because adding slack would have moved the PC
  cell height — and the assertion tolerates 1px. At 11px the line count is
  higher than it was at 12px, so if that proof is ever going to fire on a
  rounding disagreement, the phone rows are where it will.

## Open questions

1. **568×320 and 667×375 now show a two-column Shop** (they were one column
   because the 76px icon ate the column). The copy wraps to ~5 lines of 11px in
   a 170px column. It is measured so nothing clips, and total canvas drops from
   1080px to 573px — but it is dense, and an owner may prefer one column there.
   One number changes it: the Shop breakpoint test.
2. **`introHeight` on the Upgrades page is still 34 on compact.** Shrinking it
   to ~26 would put the whole 956×440 first row inside the viewport with no
   scroll at all. Left alone because the intro copy is the page's only
   explanation of what a token buys.
3. **The pass tag stays at 10px** on every tier — it is the authored face and the
   brief restated it, but it is the one string in the terminal under the 11px
   floor this change otherwise holds.
4. **Tablet tier is `fit.Touch and not fit.Compact`**, which also catches a
   *large* touch phone in landscape if its modal viewport clears 640×430. That is
   the correct call for layout purposes (it has the room), but it is a policy
   choice worth a sanity look on a real device.
5. **A compact pointer window** (a desktop player who drags the window under
   640px wide) still gets the full pointer tier — 330px cards in a small panel.
   Left deliberately: "PC unchanged" was the requirement, and no fixture in the
   matrix covers it.
