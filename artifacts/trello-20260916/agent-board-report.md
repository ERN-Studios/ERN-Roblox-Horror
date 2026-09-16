TunnelLobbyBuilder released

# A-BOARD — Trello #100, TOP SUPPORTERS board columns

Baseline: git `aa40f70`. Nothing committed, nothing pushed, Studio never touched.

## Files touched

| Path | Change |
|---|---|
| `G:\Roblox\MongoTV\ServerScriptService\TunnelLobbyBuilder.ModuleScript.lua` | `addDonationLeaderboard` only (lines 417–657). +110 / −37. Every diff hunk is inside that function; `local COLORS = {`, `local function saturatedLobbyColor(`, `local function makePart(`, `local function addDonationLeaderboard(` and `local function makeStationMonitorPart(` are byte-identical, so every marker the existing tests extract by still resolves. |
| `G:\Roblox\MongoTV\tools\tests\test_donation_board_columns.py` | New. 826 checks. |

Nothing else was opened for writing. `ZyntraMonetization.Script.lua` was read only.

## What was built

1. **Footer deleted.** The `RecordedSupportScope` TextLabel and the string
   "INCLUDES VERIFIED HISTORICAL PURCHASES" are gone from the canvas. The
   `RankingScope` model attribute is unchanged and still carries the full
   wording, so the audit trail survives. Title, Status, divider, background,
   border, panel, collision block and the 560×392 canvas are untouched.
2. **Each row is a Frame named `Rank01..Rank10`** holding three `TextLabel`
   columns, all Font `Code`, TextSize 20, tinted gold for ranks 1–3 and pale
   green below, exactly as before:

   | Column | x | width | right edge | alignment |
   |---|---:|---:|---:|---|
   | `Rank` | 12 | 44 | 56 | Right |
   | `Name` | 72 | 324 | 396 | Left, `TextTruncate.AtEnd`, `ClipsDescendants` |
   | `Robux` | 408 | 140 | 548 | Right |

   16 px of air after the rank, 12 px before the amount, 12 px margin at both
   ends of the canvas. All offsets are pure `Offset` with `Scale = 0`, so no
   name length can move a rank or an amount — on its own row or any other.
3. **Geometry.** Rows took the offered upgrade: first row still at y 98, pitch
   27, plate 25. Row 10's foot lands at 366, 26 px clear of the 392 canvas and
   10 px clear of the background's 16 px corner radius. Alternating plate
   colours and `UICorner` 6 kept; `UIPadding` removed (offsets are explicit).
4. **Render precedence.** One `renderRow`, three sources:
   attributes `Rank`/`Name`/`Robux` when `Rank` is a number in 1..99 →
   legacy string `^(%d+)%s+(.-)%s+•%s+(%d+) R%$$` →
   otherwise the string goes in the `Name` column alone with `Rank`/`Robux`
   blank (covers `""` and `"NO SUPPORT RECORDED YET"`). The board therefore
   works against a server that has not shipped the attributes yet.
5. **Thousands separator** is a plain `string.gsub("^(-?%d+)(%d%d%d)", "%1,%2")`
   loop, no locale. `21207 → "21,207 R$"`.
6. **Bindings preserved.** Same `bind(value, render)` shape with one added
   optional attribute list; `Status` and `Row01..Row10` still bind on
   `GetPropertyChangedSignal("Value")`, rows additionally on
   `GetAttributeChangedSignal` for each of the three attributes, and the
   `AncestryChanged` teardown still disconnects everything.

## Decisions taken (not asked)

- **The row frame moved from x 20 (width 520) to x 0 (width 560).** The three
  column offsets in the brief span 12..548, which is 28 px wider than the old
  520 px plate; 12 and 560−548 = 12 are a symmetric canvas margin, so the
  offsets are only self-consistent inside a full-width frame. Keeping x 20
  would have meant inventing different column numbers. The visible result is a
  full-bleed alternating band under the inset divider, and the text keeps a
  12 px margin from the border either way. If you would rather the plates stay
  inset to match the divider, the amount column has to lose 28 px (408..520)
  and a 7-digit total then collides with a long name — I would not.
- **`Rank` pre-bind text is empty, not "01".** Before any value arrives the
  board shows the old empty-board state (row 1 Name = "NO SUPPORT RECORDED
  YET", everything else blank). Showing "01" next to "no support recorded"
  would assert a rank that does not exist. The test asserts `"01"` after a
  render, which is where the brief's example belongs.
- **Hostile numbers render blank rather than throwing.** `string.format("%d", x)`
  errors on a NaN, an infinity or a non-integer float, and that error would fire
  inside a changed handler and leave the row frozen on stale text forever.
  `robuxText` returns `""` for anything unusable and floors a float. A rank
  outside 1..99 falls through to the legacy parse and then to the message path.
- **A 7-digit total is 4 px wider than its column.** Right alignment pushes the
  overhang into the 12 px gap, where it still stops 8 px short of the name
  column. Documented in the code and asserted in the test rather than widened,
  because widening costs the name column.

## Verified offline, and how

`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`

- **Compile:** `luau-compile.exe --binary ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua`
  → 100 120 bytes of bytecode, exit 0. The new test re-runs this compile on the
  whole shipped file on every invocation, so compile parity cannot silently rot.
- **`python tools/tests/test_donation_board_columns.py` → 826 checks, exit 0.**
  It extracts the real `COLORS`, `saturatedLobbyColor`, `makePart` and
  `addDonationLeaderboard` out of the shipped file by string marker and runs
  them under real Luau against a fake DataModel (Instance with property store,
  Parent, FindFirstChild, WaitForChild, real connect/disconnect signals,
  StringValue with Value + `GetPropertyChangedSignal` + attributes +
  `GetAttributeChangedSignal`, UDim2/Vector2/Vector3/CFrame/Color3/Enum,
  synchronous `task.spawn`). Coverage: footer absent and its wording absent from
  every child; RankingScope attribute intact; title/status/divider untouched;
  exactly ten `Rank%02d` frames; per row, per column, the fixed offset, width,
  scale-free sizing, alignment, font, size and tint; truncate and clip on the
  name; no `UIPadding` and no layout object that could reflow; the 16/12 px
  gaps; every row sharing one set of x offsets; plates inside the canvas and
  below the divider; the monospace character budget for a 20-char name, the
  empty-board message and a 6-digit total; attribute-driven render of
  (1, "AVERYLONGPLAYERNAMEXX", 21207) → `01` / name / `21,207 R$` with the rank
  and amount offsets unmoved and still level with row 2; single-attribute
  re-render; eight separator magnitudes 0 → 9 876 543; float, NaN, infinity and
  missing attributes; attributes beating a stale string; legacy parse including
  a name with spaces and a two-digit rank; both plain messages; an unparsable
  string; a ranked row going empty clearing all three columns; status binding
  re-render; the exact connection counts (1 value + 3 attribute signals per row);
  and teardown — every signal disconnected on unparent, later publishes ignored,
  a re-parent ignored.
- **Mutation-proofed.** The same test was run against
  `git show HEAD:...TunnelLobbyBuilder...` and fails at "the footer label is
  deleted" (exit 1). It is not a static string match and it is not vacuous.
- `python tools/tests/test_first_entry_guide.py` → 39 checks, exit 0 (unchanged).

## NOT verified — needs Studio

- **Real `TextBounds`.** Every width claim above uses the 0.6 em monospace
  advance of Font `Code`, which is the same assumption the shipped code has
  carried since #78. Nobody has measured a real `TextBounds` on this board.
  The two numbers worth measuring are the name column (324 px, claimed 27
  chars) and the amount column (140 px, claimed `999,999 R$` exactly).
- **Visual inspection at the board.** Full-bleed plates against the green
  border, the 26 px gap the footer left at the bottom, and whether
  "NO SUPPORT RECORDED YET" reads acceptably left-aligned at x 72 now that it
  is no longer centred.
- **Live refresh.** `publishSupportRows` sets `.Value` first and the three
  attributes after, so a refresh renders once from stale attributes and then
  converges within the same frame. Sub-frame and unobservable in theory;
  confirm on a real refresh that no row flickers a wrong amount.
- Nothing here ran in Studio, on a play session, or against a real DataStore.

## Blocking note for the lead — two tests are red, neither is fixable from my scope

1. **`tools/tests/test_lobby_palette.py` fails** (it was green at baseline:
   763 checks). Its #78 section asserts the board this card replaces, and I am
   not allowed to edit it. It now dies at `bind` because its fake StringValue
   has no `GetAttributeChangedSignal`. The full fix list, in file order:
   - line ~135, `function v:GetPropertyChangedSignal()` block: add
     `function v:GetAttributeChangedSignal() return {Connect = function() return {Disconnect = function() end} end} end`
     and a `GetAttribute` that returns nil, or give rows real attributes.
   - lines 240–242: `scope` no longer exists — delete the three lines.
   - line 260: `row.TextXAlignment` — rows are Frames; read the `Rank`/`Name`/
     `Robux` children instead.
   - line 261: `row.TextSize` is nil on a Frame (this one passes vacuously today).
   - line 267 and 270: `scope.Position` — compare against the canvas height.
   - line 271: `rows[1].TextSize / pxV` — arithmetic on nil.
   - lines 275–278: `Children[1]` is now the `UICorner`; there is no `UIPadding`.
   - line 283: `rows[rank].Text` — read `Rank%02d.Name.Text`.
   `test_donation_board_columns.py` covers everything those lines covered, in
   the new shape. The cleanest resolution is to delete the `#78 leaderboard`
   section from `test_lobby_palette.py` and leave it the palette test its
   docstring says it is.
2. **`tools/tests/test_leaderboard_backfill.py` fails, and it is not mine.**
   It was green at baseline and now dies in `utcDay` → `normalizeDaily` →
   `normalizeProfile`, i.e. in A-SERVER's in-flight `dailyClock` work in
   `ZyntraMonetization.Script.lua` (mtime moved during my run). Flagging for
   A-SERVER; I did not touch that file.

## Contract check against A-SERVER — matches, no gap

`publishRowColumns` at `ServerScriptService/ZyntraMonetization.Script.lua:1188`
already sets `Rank` (number), `Name` (upper-cased string) and `Robux` (number)
on each `Row%02d`, and clears all three to nil for an empty row. That is exactly
what `renderRow` consumes, and the legacy `"%02d   %s   •   %d R$"` string is
still published alongside, which is what the fallback parses. No name or type
needs changing on either side.

## Native inspection steps

1. Play in Studio and walk to the lobby concourse board (panel at lobby centre
   + (−30, 7.15, −35), facing the walkway).
2. In `execute_luau`, read the real bounds rather than trusting the estimate:
   ```lua
   local row = workspace:FindFirstChild("ZyntraDonationLeaderboardBoard", true)
       .LeaderboardPanel.DonationLeaderboardDisplay:GetChildren()[1]
   for _, name in ipairs({"Rank01", "Rank05", "Rank10"}) do
       local r = row:FindFirstChild(name)
       for _, col in ipairs({"Rank", "Name", "Robux"}) do
           local l = r[col]
           print(name, col, l.AbsolutePosition.X, l.AbsoluteSize.X, l.TextBounds.X, l.Text)
       end
   end
   ```
   Expect `TextBounds.X` ≤ `AbsoluteSize.X` for every `Name` and `Robux`, and
   the same `AbsolutePosition.X` for all three rows of each column.
3. Force a worst case without waiting for real supporters:
   ```lua
   local v = game.ReplicatedStorage.ZyntraDonationLeaderboard.Row01
   v:SetAttribute("Rank", 1); v:SetAttribute("Name", "AVERYLONGPLAYERNAMEXX")
   v:SetAttribute("Robux", 9876543)
   ```
   The rank must not move, the amount must stay right-aligned at the same pixel,
   and a name too long for the column must end in an ellipsis, not run under the
   amount.
4. Legacy path: clear the three attributes on `Row02` and set
   `Value = "02   SUPPORTER   •   4210 R$"`. It must render `02` / `SUPPORTER` /
   `4,210 R$`.
5. Empty path: `Row03:SetAttribute("Rank", nil)` and `Value = ""`. All three
   columns blank.
6. Screenshot the whole board from player eye height for the visual sign-off,
   and confirm the bottom 26 px now read as margin rather than a missing footer.

## Trello draft — card #100

> **Done — board columns**
>
> The "INCLUDES VERIFIED HISTORICAL PURCHASES" footer is removed from the TOP
> SUPPORTERS board. Its wording is kept as a data attribute on the board model
> so the audit record is not lost, it just no longer takes a line on screen.
>
> Each of the ten rows is now three separate columns instead of one centred
> line: rank on the left, player name in the middle, Robux on the right. The
> columns sit at fixed positions, so the rank and the amount land on exactly the
> same pixel on every row and a long name can no longer push them sideways.
> There is 16 px of clear space after the rank and 12 px before the amount, so
> nothing is crowded. Amounts are right-aligned and now carry a thousands
> separator (21,207 R$). A name too long for its column is cut with an ellipsis
> and clipped, so it can never run under the amount.
>
> The freed footer space went into slightly taller row plates (25 px on a 27 px
> pitch); the last row ends 26 px above the bottom edge.
>
> Value bindings, history and refresh are unchanged — the board reads the new
> per-row rank/name/amount data the server publishes, and still falls back to
> parsing the old single-line format, so it keeps working either way. Empty
> boards and "NO SUPPORT RECORDED YET" still display correctly.
>
> Offline test: `tools/tests/test_donation_board_columns.py`, 826 checks against
> the real code under the Luau interpreter, plus a compile check of the whole
> module. Still to do in Studio: measure the real text bounds and look at the
> board in game.

## Open questions for the owner

- Full-bleed row plates (x 0..560) vs the old 20 px inset that matched the
  divider. Forced by the column offsets; call it if you dislike the look.
- "NO SUPPORT RECORDED YET" is now left-aligned in the name column rather than
  centred across the board. Centring it again means a fourth, message-only
  label; say the word if it matters.

## Artwork needed from Codex

None. Everything on this board is typography.
