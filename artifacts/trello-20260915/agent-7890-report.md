# Agent A7890 — Trello #78 (Top Supporter sign) and #90 (lobby saturation)

Offline only. No Studio tools were used; nothing was pushed, committed or published.

**File changed:** `G:\Roblox\MongoTV\ServerScriptService\TunnelLobbyBuilder.ModuleScript.lua`
(only mirror file touched, 87 insertions / 41 deletions, LF preserved, no whole-file rewrite)

| | bytes | sha256 |
|---|---|---|
| before (HEAD, clean) | 111 868 | `4184fb6a958c625d44cc2dc533c8a3536d5bd429ad87dcf2382f6d5cfdb0c3bf` |
| after | 114 780 | `4c710024c6728eb1a127b69e641b7c00e0446bbd37f8f4153a17d2815a440f55` |

**File added:** `G:\Roblox\MongoTV\tools\tests\test_lobby_palette.py`

The manifest was deliberately **not** touched — the lead owns the Studio push and the
manifest item.

---

## #78 — TOP SUPPORTERS board

All changes are inside `addDonationLeaderboard` (now line 417). **No geometry moved.**
`LeaderboardPanel` keeps its exact `CFrame` (`center + (-30, 7.15, -35)`) and `Size`
(`0.62 × 12.6 × 18`); `LeaderboardCollision` is untouched. No panel enlargement was
needed — the text grew entirely through the canvas.

### Why the canvas shrank

The panel's `Face = Right` maps the canvas onto an 18 × 12.6 stud face. Roblox never
draws a label above 100 px, so the only way to enlarge text on a fixed board is to put
**fewer pixels on the same studs** (the project's own `TextScaled` 100-px note).
900 × 660 also did not match the face aspect, so every glyph was drawn 4.8 % wider than
tall; 560 × 392 is exactly 18 : 12.6, which removes that stretch as a side effect.

| | before | after |
|---|---|---|
| CanvasSize | 900 × 660 | **560 × 392** |
| px/stud horizontal (U) | 50.000 | **31.111** |
| px/stud vertical (V) | 52.381 | **31.111** |
| horizontal glyph stretch | 1.048 | **1.000** |

### Text and layout, before → after

Physical height = `TextSize / px-per-stud-V`, i.e. what a player actually sees.

| element | TextSize px | studs tall | TextSize px | studs tall | gain |
|---|---:|---:|---:|---:|---:|
| Title "TOP SUPPORTERS" | 43 | 0.821 | **44** | **1.414** | **1.72×** |
| Status line | 19 | 0.363 | **17** | **0.546** | **1.51×** |
| Rank rows (×10) | 24 | 0.458 | **20** | **0.643** | **1.40×** |
| Footer / scope | 17 | 0.325 | **15** | **0.482** | **1.49×** |

| geometry | before | after |
|---|---|---|
| Title | offset (38, 22), size (1,−76, 0, 58), **Left** | offset (0, 12), size (1, 0, 0, 46), **Center** |
| Status | offset (40, 78), size (1,−80, 0, 30), Left | offset (0, 60), size (1, 0, 0, 22), **Center** |
| Divider | y 116, h 3, x-margin 38 | y 90, h 2, **x-margin 20** |
| Rows | y `128 + (n−1)·50`, h 42, x 38, pad 16 | y `98 + (n−1)·26`, h 24, **x 20, pad 12** |
| Row pitch | 50 px = 0.955 studs | 26 px = **0.836** studs |
| Footer | y 630, h 22, x-margin 40, Left | y 366, h 18, **x-margin 20, Center** |
| Background UICorner | 26 px (0.520 studs) | 16 px (**0.514** studs — same real size) |
| Border UIStroke | 5 px (0.095–0.100 studs) | 3 px (**0.096** studs — same real size) |
| Row UICorner | 8 px | 6 px |
| Board part | 0.62 × 12.6 × 18 studs | **unchanged** |

Every element is either full-width + `TextXAlignment.Center` (title, status) or sits on a
single shared 20 px gutter (divider, rows, footer), so the column is centred on the face
regardless of what the server publishes. Fonts are unchanged and already in use in this
project (`GothamBlack` for the title, `Code` for status/rows/footer); no new font.

### Clipping headroom (the reason rows are 20 px, not larger)

`ZyntraMonetization.publishSupportRows` emits `"%02d   %s   •   %d R$"`. Worst realistic
row = rank (2) + 3 spaces + a 20-character Roblox name + 7 separator chars + 6-digit
amount + " R$" = **41 monospace characters**. `Enum.Font.Code` advance is 0.6 em, so
`41 × 0.6 × 20 = 492 px` against the `560 − 40 − 24 = 496 px` a row plate leaves after
padding. It fits with 4 px to spare; 21 px would clip a maximum-length name. Rows stay
left-untruncated and no supporter's name is ever cut.

### Data binding

Untouched. `rowLabels[1..10]`, the `ReplicatedStorage.ZyntraDonationLeaderboard`
`WaitForChild`, `Status` + `Row01..Row10` binds, the `AncestryChanged` disconnect and
`RankingScope` all behave exactly as before; the test asserts all eleven binds still fire
and that each row renders the published string.

`LeaderboardVersion` bumped **2 → 3**. Nothing in the codebase reads it (grep: only the
`SetAttribute` itself and two ServerStorage backups), so this is a provenance marker only,
matching how `ComingSoonGateVersion` is used a few functions above. Say the word and it
goes back to 2.

---

## #90 — lobby saturation

### The lever

One constant and one helper, added directly under the `COLORS` table (line ~98). The
authored literals stay exactly where they were and remain the source of truth.

```lua
local LOBBY_SATURATION = 1.35

local function saturatedLobbyColor(color)
	if LOBBY_SATURATION == 1 then return color end
	local h, s, v = color:ToHSV()
	if s <= 0 then return color end
	return Color3.fromHSV(h, math.min(s * LOBBY_SATURATION, 1), v)
end
```

Hue is preserved, HSV **Value is preserved exactly** (nothing darkens), saturation clamps
at 1, and `1.0` short-circuits to the identical `Color3` — not an approximation.

### Where it is applied (5 sites, all funnels — no per-part multiplications)

| site | line | covers |
|---|---|---|
| `makePart` | 127 | **the only `Instance.new("Part")` in the module** — every wall, floor, ceiling, curb, trim, neon strip, station geometry, kiosk, signage backing, barricade. ~127 authored literals plus every `COLORS.*` world use. |
| `styleLevelOneBay` | 1303–1315 | the Level 1 bay recolour pass (bypasses `makePart`) |
| `styleLevelTwoBay` | 1470 | the Level 2 poolrooms recolour pass |
| `styleLevelThreeBay` / `cloneLobbyLevelThreeFurniture` | 1608, 1634–1650 | the Level 3 mall recolour pass and the cloned furniture tint |
| `addQueueStation` (`padColor`) | 1145–1164 | the station pads: the pad *parts* are `Transparency = 1`, the visible ring is a floor-painted SurfaceGui, so it follows the surface palette |

Plus a correctness fix the lever forced: the signal-sweep colours (line 2827) are written
both at build time (through `makePart`) and again by the runtime tweens / idle restore.
The raw literal now feeds `makePart` (`baseSignalSource`) while the tween targets resolve
through the helper, so a sweep still returns the nodes and console button to exactly the
colour they were built with. Without this the first sweep would have desaturated them.

### Deliberately NOT touched

- **Lights.** Every `PointLight` / `SurfaceLight` / `SpotLight` `Color` and `Brightness` is
  unchanged, so the lobby is lit identically and the change is pure albedo. This is the
  main horror/visibility safeguard: no cue gets dimmer, no shadow moves.
- **Lighting globals.** `TunnelLobbyBuilder` sets no `Lighting`, `Atmosphere` or
  `ColorCorrection` at all (grepped — the only hit is a folder named `TunnelLighting`), so
  nothing round-owned was in reach and none was added.
- **UI colours.** `COLORS` itself is not mutated, so `addBoard` title/subtitle text, the
  COMING SOON gate board (its red border, title, divider and progress fill), the
  leaderboard's own text/border and every `TextColor3` keep their authored values. Only
  world surfaces go through the helper.
- **Texture tints** (`LEVEL_TWO_BAY_STYLE.tileTint`, `Texture.Color3`) — near-white
  multipliers over the real texture images; left alone.
- **Pure greys and blacks** — `s <= 0` returns them unchanged, so darkness stays neutral.
  Near-black tinted colours (the UI-dark plates, `partyCarpetColor`) move by at most 2–4
  steps out of 255 because the absolute change scales with V.
- **A separate neon multiplier was skipped.** Measured first: at 1.35 the accents already
  land at S = 0.76–1.00 (`green` 0.895, `zyntraCyan` 0.948, `amber` 0.969, `red` 1.000
  clamped, station pads 0.68–0.92). A second constant would have bought a further push on
  four values and clamping on the rest, at the price of a classification branch. Add it
  later if the captures say the pads read flat.

### Colour table (1.35, H in degrees)

**COLORS — shared lobby palette (surface uses only; UI uses keep the left column)**

| colour | RGB before | H/S/V before | RGB after | H/S/V after |
|---|---|---|---|---|
| concrete | 116,105,82 | 41/0.293/0.455 | 116,101,70 | 41/0.396/0.455 |
| concreteDark | 73,68,58 | 40/0.205/0.286 | 73,66,53 | 40/0.277/0.286 |
| concreteLight | 157,144,111 | 43/0.293/0.616 | 157,139,95 | 43/0.396/0.616 |
| asphalt | 27,28,27 | 120/0.036/0.110 | 27,28,27 | 120/0.048/0.110 |
| curb | 116,112,95 | 49/0.181/0.455 | 116,111,88 | 49/0.244/0.455 |
| metal | 32,35,34 | 160/0.086/0.137 | 31,35,34 | 160/0.116/0.137 |
| metalLight | 62,66,62 | 120/0.061/0.259 | 61,66,61 | 120/0.082/0.259 |
| paint | 222,207,140 | 49/0.369/0.871 | 222,202,111 | 49/0.499/0.871 |
| green | 86,255,173 | 151/0.663/1.000 | 27,255,144 | 151/0.895/1.000 |
| zyntraCyan | 73,245,204 | 166/0.702/0.961 | 13,245,190 | 166/0.948/0.961 |
| amber | 255,183,72 | 36/0.718/1.000 | 255,158,8 | 36/0.969/1.000 |
| red | 255,76,60 | 5/0.765/1.000 | 255,21,0 | 5/**1.000**/1.000 |

`red` is the one that clamps. Its only world use is the decorative neon rails around the
COMING SOON gates; the warning *text* on those boards is UI and keeps 255,76,60.

**Level 1 bay**

| colour | RGB before | H/S/V before | RGB after | H/S/V after |
|---|---|---|---|---|
| wallColor | 197,180,116 | 47/0.411/0.773 | 197,174,88 | 47/0.555/0.773 |
| floorColor | 158,144,96 | 46/0.392/0.620 | 158,139,74 | 46/0.530/0.620 |
| ceilingColor | 222,214,170 | 51/0.234/0.871 | 222,211,152 | 51/0.316/0.871 |
| lightColor | 255,244,200 | 48/0.216/1.000 | *unchanged* | *unchanged* |

**Level 2 bay (poolrooms)**

| colour | RGB before | H/S/V before | RGB after | H/S/V after |
|---|---|---|---|---|
| wallColor | 206,221,212 | 144/0.068/0.867 | 201,221,209 | 144/0.092/0.867 |
| floorColor | 236,227,196 | 46/0.169/0.925 | 236,224,182 | 46/0.229/0.925 |
| ceilingColor | 228,224,205 | 50/0.101/0.894 | 228,223,197 | 50/0.136/0.894 |
| metalColor | 83,96,99 | 191/0.162/0.388 | 77,95,99 | 191/0.218/0.388 |
| railColor | 196,202,205 | 200/0.044/0.804 | 193,201,205 | 200/0.059/0.804 |
| waterColor | 48,150,159 | 185/0.698/0.624 | 9,147,159 | 185/0.942/0.624 |
| lightColor | 255,247,210 | 49/0.176/1.000 | *unchanged* | *unchanged* |

**Level 3 bay (mall party)**

| colour | RGB before | H/S/V before | RGB after | H/S/V after |
|---|---|---|---|---|
| partyCarpetColor | 13,17,24 | 218/0.458/0.094 | 9,15,24 | 218/0.619/0.094 |
| wallpaperColor | 220,213,187 | 47/0.150/0.863 | 220,211,175 | 47/0.203/0.863 |
| orangeWallColor | 183,78,35 | 17/0.809/0.718 | 183,53,0 | 17/**1.000**/0.718 |
| ceilingColor | 218,211,184 | 48/0.156/0.855 | 218,209,172 | 48/0.211/0.855 |
| lightColor | 255,222,181 | 33/0.290/1.000 | *unchanged* | *unchanged* |

**Station launch pads (the biggest read change in the bays)**

| pad | RGB before | H/S/V before | RGB after | H/S/V after |
|---|---|---|---|---|
| 1 | 82,255,180 | 154/0.678/1.000 | 21,255,154 | 154/0.916/1.000 |
| 2 | 88,218,255 | 193/0.655/1.000 | 30,205,255 | 193/0.884/1.000 |
| 3 | 168,255,112 | 97/0.561/1.000 | 138,255,62 | 97/0.757/1.000 |
| 4 | 126,196,255 | 207/0.506/1.000 | 81,175,255 | 207/0.683/1.000 |

**Signal sweep**

| colour | RGB before | H/S/V before | RGB after | H/S/V after |
|---|---|---|---|---|
| idle node | 39,126,121 | 177/0.690/0.494 | 9,126,119 | 177/0.932/0.494 |
| pulse | 86,255,173 | 151/0.663/1.000 | 27,255,144 | 151/0.895/1.000 |
| console button | 45,157,112 | 156/0.713/0.616 | 6,157,96 | 156/0.963/0.616 |

The remaining ~100 inline literals (benches, kiosk metals, wood, barricades, crossing
stripes, monitor housings, sign backings, trims) all route through `makePart` and follow
the same S × 1.35 rule; the test sweeps all 127 distinct authored colours and asserts each
stays in gamut, keeps its V and never loses saturation.

---

## Capture plan for the lead

`LOBBY_CENTER = Vector3.new(0, 30, -760)`. Tunnel: length 280 (z −900 … −620), radius 35,
road 33 wide on x = 0, raised ledges at x = ±25.

**Getting the "before" without reverting anything:** set `LOBBY_SATURATION = 1.0` and
restart play. The lobby is rebuilt from `TunnelLobbyBuilder` at play start, and the test
proves 1.0 reproduces the authored palette byte for byte — so the same build, same seed,
same camera gives a true like-for-like pair. Flip back to 1.35 and re-shoot. **Do not**
capture "before" from an old place file; the #78 layout change would confound it.

Six positions (`Camera.CFrame = CFrame.lookAt(pos, look)`, `FieldOfView` default 70):

| # | what | camera position | look-at |
|---|---|---|---|
| 1 | Concourse overview down-tunnel (road, curbs, ledges, shell, signal nodes, door signs) | `(0, 39, -866)` | `(0, 33, -740)` |
| 2 | TOP SUPPORTERS at concourse distance (30 studs — the #78 acceptance shot) | `(0, 35, -795)` | `(-29.7, 37.15, -795)` |
| 3 | TOP SUPPORTERS close (15 studs — row legibility) | `(-14, 37.2, -795)` | `(-29.7, 37.15, -795)` |
| 4 | Zyntra supply kiosk / terminal wall | `(6, 36, -796)` | `(28, 35, -796)` |
| 5 | Level 1 bay + neon station pads | `(-44, 38, -841)` | `(-70, 30.2, -849)` |
| 6 | Tunnel ceiling and `TunnelLighting` fixtures | `(0, 32, -772)` | `(0, 46, -760)` |

Optional extras if the bays need their own pair: Level 2 poolrooms `(44, 38, -841)` →
`(70, 31, -841)`; Level 3 mall `(-44, 38, -761)` → `(-70, 32, -761)`.

Note for #90 review specifically: shot 1 and shot 6 are the horror-readability check
(nothing should be darker or muddier), shots 4–6 are where the saturation actually reads.

---

## Tests

`tools/tests/test_lobby_palette.py` — extracts the real `COLORS` table,
`LOBBY_SATURATION`, `saturatedLobbyColor`, `makePart` and `addDonationLeaderboard` out of
the module by string anchors and runs them under a fake Instance / Color3 (real HSV maths)
/ UDim2 / Enum surface. Follows the `test_queue_barrier.py` pattern.

```
LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe \
  python tools/tests/test_lobby_palette.py
→ lobby palette + supporter board: 763 checks passed
  (LOBBY_SATURATION=1.35, canvas 560x392 = 31.11 px/stud)   exit 0
```

Covers, for #90: saturation raised by exactly the lever, hue and V preserved, clamp at 1,
greys/blacks byte-identical, all 127 authored colours stay in gamut and never lose
saturation, `LOBBY_SATURATION = 1.0` returns the identical `Color3` for all 127, and
`makePart` applies it while keeping the requested material. For #78: panel size and
position unchanged, canvas aspect equals the face aspect, fewer px/stud than before,
exactly ten rank plates, all centred, evenly pitched, non-overlapping, below the divider
and above the footer, footer inside the canvas, the 41-character worst-case row fits the
plate, every text element physically larger than the layout it replaces, and all eleven
value bindings still fire.

**Mutation-checked** (mutation applied, test run, file restored — final hash verified):

| mutation | caught |
|---|---|
| drop the `math.min(..., 1)` clamp | yes |
| rows back to `TextXAlignment.Left` | yes |
| draw 11 rank rows in the same budget | yes |
| restore the old 900 × 660 canvas | yes |
| `if s <= 0` → `if s < 0` (grey guard) | **no — equivalent mutant**: `Color3.fromHSV(h, 0, v)` returns the same grey, so the guard is a short-circuit, not a behaviour |

Also run: `luau ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua` reaches line 7
(`game:GetService` is nil offline), i.e. the file parses clean. No other test in
`tools/tests/` touches this module, so nothing else was re-run.

---

## Limitations — what I did NOT verify

- **Nothing was run in Roblox Studio.** No compile probe, no play session, no screenshot.
  All #78 numbers are computed from the source; the fonts' real advance widths
  (`Enum.Font.Code` assumed 0.6 em, `GothamBlack` estimated ~0.72 em for the title) are
  standard values, not measured in-engine. If the title overflows, drop `TextSize` to 40.
- **No before/after capture was taken.** The capture plan above is for the lead.
- **1.35 is a first proposal, not a tuned value.** It is one edit to change and the test
  re-reads the constant automatically. If the pads or the Level 3 orange read too hot,
  1.20–1.25 is the obvious next stop.
- **Two colours clamp to S = 1.0** at 1.35: `COLORS.red` (COMING SOON neon rails) and
  `LEVEL_THREE_BAY_STYLE.orangeWallColor` (Level 3 bay walls). Both are intentional and
  reversible, but they are the two most likely to draw an owner comment.
- The saturation is albedo-only by design. If the owner wanted the *lighting* warmer/cooler
  too, that is a separate decision and a separate lever.
- Manifest not updated and nothing pushed — the lead owns the Studio write. A88's hook line
  near the end of the build is unaffected: my last edit is at line ~2905, inside
  `addLobbyConcourse`, not at the tail of `Builder.Build`.
