# pages-v3 test fixture: RECORDS and SETTINGS before the Live Sync import (2026-10-07)

`roblox-draft/tests/framewisp-dump.ZyntraShop_L4.pages-v3.json` is the real 2026-10-07 Live Sync dump of
`ZyntraShop_L4` (`tests/framewisp-dump.ZyntraShop_L4.json`, sha256 `94f5fc82...`, not modified) with three changes:

1. `Page_Records` (Figma 157:6) and `Page_Settings` (158:2) are inserted into `ShopWindow/Canvas/Pages`, after
   `Page_Colors`, in Figma's stacking order. Both are converted from Figma the way Framewisp converts (rules below).
2. Every `ZIndex` is renumbered with Framewisp's rule: preorder over GuiObjects, `4 + 2i`. This rule holds for all
   577 GuiObjects of the real dump. Everything after `Pages` moves up by 344: Footer 1078 -> 1422, Categories
   1082 -> 1426, Pending 1138 -> 1482, Toast 1148 -> 1492.
3. `summary` is updated: nodes 1321 -> 1680, `TextButton x47` -> `x52`, textFixedSize 203 -> 278.

The fixture is written in the dump tool's own byte format (indent 1, ASCII escapes, CRLF, no final newline). A
plain line diff against the real dump shows exactly those three changes: 3 summary lines, 1 inserted block, and 40
ZIndex lines.

## Files (all in this folder)

| File | What |
|---|---|
| `build_pages_fixture.py` | Builds the fixture. `--check` is the converter's self-check against the real import. `--diff DUMP` compares the fixture with a future real dump. |
| `figma-91-3.json` | Read-only `use_figma` export of the whole export frame 91:3: ids, names, absolute boxes, auto-layout, sizing, clip, overflow, paints, strokes, radii, text (characters, font, size, line height, alignment, auto-resize). It was reassembled from 7 chunks and the hash was checked. |
| `figma-91-3.renderbounds.json` | `absoluteRenderBounds` of all 247 TEXT nodes in 91:3. Framewisp sizes a hug text's height to its ink. |

```
python build_pages_fixture.py           # rewrite the fixture from the two exports + the real dump
python build_pages_fixture.py --check   # compares 258 nodes; prints the residual differences
python build_pages_fixture.py --diff ../../roblox-draft/tests/framewisp-dump.ZyntraShop_L4.json   # after the re-import
```

The exports describe the file as it was on 2026-10-07 around 12:30. If Figma changes, re-export the frame and
rebuild. The script's docstring describes the export format.

## Status

- The fixture loads in the shop harness (`stamp()`, the fake engine, and the dump-tool round trip).
- The current draft controller fails on it, which is the expected result: `CHECK FAILED: Upgrades draws 19 tap
  targets (want 14)`. This is the re-import hazard from BINDINGS.md. The two new pages stay Visible over every tab,
  and their 5 buttons (`ShowAssisted` + 4 `Toggle_<Key>`) count on the Upgrades tab. The fixture exists to catch this.
- `test_zyntra_shop_l4.py` hard-codes the dump name. Until it takes the fixture as a frame variant, run it against
  the fixture like this (read-only, from `roblox-draft/tests`, with `LUAU_BIN` set):

```python
import json, test_zyntra_shop_l4 as t
orig = t.load_dumps
def load():
    frames = orig()
    frames["ZyntraShop_L4"] = json.loads((t.HERE / "framewisp-dump.ZyntraShop_L4.pages-v3.json").read_text(encoding="utf-8"))["root"]
    return frames
t.load_dumps = load
t.main()
```

## Conversion rules (derived from the real dump, checked by `--check`)

`--check` converts Header, Footer, Categories and the five existing pages from the same Figma export. It then
compares them node by node with the real import. It covers 258 nodes. Images and gradients are skipped, because the
new pages have none.

| Figma | Roblox in the fixture | Evidence |
|---|---|---|
| Layer name tags `_button _list _scroll _txt _panel _shadow ...` | Stripped from `Name` (`Desc_txt` -> `Desc`, `Toggle_LobbyMusicEnabled_button` -> `Toggle_LobbyMusicEnabled`, `RecordsList_scroll` -> `RecordsList`, `Content_list` -> `Content`) | `namesKeepingTags: 0` in every dump |
| Hidden layer at import time | Not created at all | Hidden `Hook`/`Meta`/`OwnedBadge` are absent from the dump |
| Any node | `Size`/`Position` in Scale of the parent's box, offsets 0, `AnchorPoint` 0.5,0.5, 6 decimals | every node |
| `_button` / `_tab` / `_close` frame | `TextButton`, `Text ""`, TextSize 8, LegacyArial, `AutoButtonColor`/`Selectable`/`Active` true, no FW_Scale | Records, Buy, Tab_* |
| Solid fill | `BackgroundColor3`, `BackgroundTransparency = 1 - opacity`; no fill gives `[163,162,165]`, 1 | 161 + 16 unfilled nodes |
| Corner radius r | `UICorner` `r / min(w,h)`, 4 decimals, not clamped (Face: 0.8333) | every corner `--check` reaches, within 0.002 |
| Inside stroke | `UIStroke` Round/Enabled. A TextButton is `Border` and ScaledSize (`w / min(w,h)`). A filled non-pill frame is `Contextual` ScaledSize. An unfilled frame or a pill/circle (corner 0.5) is `Contextual` pixel (`w * 443/1080`). | all 101 strokes in the dump split this way |
| `clipsContent` | `ClipsDescendants = true`. This applies also to childless frames (`Knob`, `Rule`, `Separator`). | HueBar_n, TierIcon |
| Clip + radius + a child past the rounded corners | With a stroke: the frame keeps fill/corner/stroke, plus a `Canvas` CanvasGroup child (clip, own UICorner) that holds the children. Without a stroke: the frame itself is a CanvasGroup. | ShopWindow, Picker_*, SkinViewport, Tab_Colors icon |
| `_list` / `_tabgroup` | An `Items` Frame (the union of the children's boxes) holding a `UIListLayout`: Padding = gap / Items length, alignment from Figma, children `Position 0`, `AnchorPoint 0`, `LayoutOrder 1..n` | 12 of 16 `_list` frames, see caveat 3 |
| Other auto-layout frames | Absolute: Figma's computed positions, no UIListLayout | TokenPill, Pending, Toast/Body, Buy, Ribbon, Tab_* |
| `_scroll` | A `ScrollingFrame` with clip, ScrollBarThickness 6, WhenScrollable, AutomaticCanvasSize None. `CanvasSize` = the content extent in the scroll's PARENT Scale, or all 0 when nothing overflows. The content child fills the canvas. | Products 1.576, Skins 0.66/1.256, Upgrades and Donate 0 |
| TEXT | `TextLabel` + `FW_Scale` UIScale (+ `k_text` NumberValue). Font: Montserrat Black -> Heavy, ExtraBold, SemiBold; Roboto Mono Bold; Roboto Condensed Black -> Heavy. | 156 text nodes |
| Hug text (`WIDTH_AND_HEIGHT`) | Figma width; height = ink height (render bounds); centred on the Figma line; `TextXAlignment Center`, YAlignment Center, not wrapped | 66 hug texts |
| Fixed-width text (`HEIGHT`, and `NONE`) | The Figma box. X alignment as in Figma. More than one line in the sample (`h / lineHeight > 1`) gives `TextWrapped` + YAlignment Top, otherwise Center. | 44 fixed texts |
| TextSize | `round(fontSize * k * em)`, k = 443/1080, em = ShopBinder's EM table | see caveat 1 |
| AbsoluteSize / AbsolutePosition | The design box * k, plus the root at (93.222, 0). This is the 443 px Studio viewport of the real dump, at CanvasPosition 0. | every node |

What the new pages come out as (172 GuiObjects):
- `RecordsList` is a ScrollingFrame Y, CanvasSize `{1,0,1.256098,0}` (824 / 656), wrapping `Content/Items`
  (UIListLayout V, Padding 16/824). It holds `Record_Level1..4` in LayoutOrder 1..4.
- Every card is absolute inside (TitleCol, Times, Divider, Challenges). Each State chip is an absolute Frame
  with a centred `Label`.
- `SettingsList` is a ScrollingFrame Y with CanvasSize `{0,0,0,0}` (it never overflows), wrapping `Content/Items`
  (V, Padding 20/656) with the two Sections.
- Each `Group` is Frame + UICorner + UIStroke + `Canvas` CanvasGroup. `Setting_<Key>` > `Toggle_<Key>` (TextButton,
  no fill, full row) > `Info` (Title, Desc), `State`, `Track` > `Knob`.
- Both EQUIPPED badges and both challenge chips are present on all four cards, and they are Visible.

## What may differ in the real import, most important first

1. **Items wrappers are heuristic in Framewisp.** In the real dump, 4 of 16 `_list` frames came without `Items`
   (Upgrade_Stamina/Battery `Info`, Card_SpeedPotion/RouteMarker `Info`). The untagged `RecordsIcon` got one
   anyway. Both new `Content_list` frames hold frames only and are modelled with `Items`; the real import may
   have none.
   - Bind by name through descendants. Never rely on a fixed depth or on a `UIListLayout` being the cards' parent.
   - The same applies to the plain auto-layout frames (`Times`, `SoloRow`, `Challenge1`, `State`, `SectionHeader`,
     `Info`, ...). The fixture keeps them absolute, like every untagged auto-layout frame in the real dump.
2. **`SettingsList_scroll` has `overflowDirection` NONE.** No existing scroll has that.
   - The fixture assumes ScrollingFrame, `ScrollingDirection Y`, CanvasSize 0, from the zero-canvas rule.
   - Framewisp could pick another direction, a non-zero CanvasSize, or a plain clipping Frame. None of these should
     matter if the page is bound by name.
3. **`Desc` wrapping follows the Figma sample, not the setting.**
   - The Records `Desc` (3 lines) and the Settings `Desc` of LobbyMusicEnabled and ReduceCameraShake (2 lines) are
     `TextWrapped`/Top.
   - The `Desc` of ReduceFlashing and CaptionsEnabled (1-line samples) are NOT wrapped (YAlignment Center).
   - `ShopBinder`'s `MULTILINE` set (`Name`, `Benefit`, `Detail`, `Title`) does not include `Desc`. A longer
     runtime description on those two rows goes through `fitLine` (shrink, then truncate) unless the controller
     sets `TextWrapped` itself.
   - The config strings match the Figma samples word for word today, so the fixture is the real case.
4. **TextSize is plus or minus 1.**
   - Framewisp solves the TextSize for one-line authored text width-exactly (`FW_M100`). It came out 1 lower than
     `round(size*k*em)` on 33 of the 110 compared texts in the real dump, mostly Montserrat.
   - The fixture uses the rounded value. This is the larger size, so it is the harder case for fitting.
   - The harness rebuilds `FigmaFontSize` from TextSize, so the reconstructed design size can be about 2 px off
     either way.
5. **Text vertical centres move 0.5 to 3 design px lower** in the real import (Header Title, tab labels, badge
   texts, Donate names). TokenLabel (a FILL text inside a HUG row) came out 6 px narrower. The fixture centres on
   the Figma line.
6. **Ink heights of the Level 3 and Level 4 cards are estimates.**
   - Their hug texts sit below the scroll's visible area, so Figma returns clipped or null render bounds.
   - The builder uses the same font, size and text from the visible cards (`EQUIPPED`, `+3 TOKENS`, `NOT YET`, ...).
     `LEVEL 3`/`LEVEL 4` take the median of the Montserrat Black 44 samples.
   - Framewisp measures the real ink and may differ by about 1 px.
7. **The `Group` CanvasGroup is an inference.** The fixture follows the ShopWindow/Picker pattern. A real import
   could instead make `Group` itself the CanvasGroup, or clip with a plain Frame and leave square corners on the
   first and last row.
8. **`State` (Settings) has `textAutoResize` NONE.** It is treated like a fixed-width text: 84x36, Right/Center,
   not wrapped.
9. **No attributes.** The dump tool records none. `FigmaFontSize`, `FigmaTextW`/`FW_M100` and `FigmaStrokeW` exist
   only in the real import. The harness stamps `FigmaFontSize` itself.
10. **Live Sync visibility.** A layer hidden in Figma after an import arrives as `Visible = false`; it is not
    deleted. Examples in the real dump: four Shop `Benefit`s, both `Presets`, some `BuyShadow`s.
    - A layer hidden before the import is never created. `Header/Records_active` and `Settings_active` are hidden,
      so they are absent here and will be absent in the real import. The active look must be drawn at runtime, as
      BINDINGS.md says.
    - Everything in the new pages is visible, so everything is `Visible = true`.
11. **Unchanged on purpose.** The fixture still holds the real Footer `Status` text ("Prices are read live from
    Roblox."; Figma now says "Status"), because `check_go_live` relies on it. Header, Footer, Categories, Pending and
    Toast are byte-identical to the real dump except for ZIndex.

The window now holds 12 `Title` nodes; the Header's comes first in preorder. That matches the BINDINGS.md note.

## After the Live Sync import

1. Dump the new import with `tools/dump_framewisp_tree.luau` into `roblox-draft/tests/framewisp-dump.ZyntraShop_L4.json`.
   Use the same Studio viewport if possible: k = root AbsoluteSize.Y / 1080 is read from the dump.
2. Run `python build_pages_fixture.py --diff <that dump>`. It lists every node of the two pages where the real
   import departs from the fixture: class, Scale, colour, clip, text props, UICorner/UIStroke/UIListLayout values,
   and child names. That shows which of the caveats above came true.
3. Re-run `test_zyntra_shop_l4.py` (and `tools/tests`) on the real dump. If anything in the controller depended on a
   caveat, fix the controller, not the dump.
4. Once the real dump covers both pages, this fixture is redundant. Delete it, or keep it as a frozen variant.
