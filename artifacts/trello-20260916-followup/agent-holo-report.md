# A-HOLO — Trello #105, floating hologram shop

Card: <https://trello.com/c/IA6VOViX>. Built 2026-09-16 against `2c60cf3`.

## Files

| File | What changed |
|---|---|
| `ServerScriptService/LobbyShopDisplay.ModuleScript.lua` | 757 -> 795 lines. Pedestal/crate/cap/prompt/visible-plate replaced by projector disc + beam + hologram box + invisible pressure plate. `ShopDisplayVersion` 2 -> 3. |
| `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua` | 493 -> 523 lines. Pointer tier 420 -> 560 wide with a 112px icon, a close-hint line on the kind row, yaw deleted. |
| `tools/tests/test_lobby_shop_display.py` | 732 -> 1014 lines. **404 -> 802 checks.** |

Nothing else was touched. `git status` shows other agents' edits to `UIDevice`,
`UIRegression`, `ZyntraDailyRewardsPage`, `ZyntraStore`, `studio-sync-manifest.json`,
`test_daily_rewards_page.py` and `test_zyntra_store_compact.py`; none of those are mine.

## Geometry

Measured by running the real `Build` under the real luau interpreter and printing the
world extents of every part (script kept in the scratchpad, not committed). Radius is
`r(x, y) = sqrt(x^2 + (y - 1)^2)` at the **worst of the eight corners**; the shell limit
is 33.70 everywhere and the rib limit 33.05 for anything crossing the arch at
z -52.36..-51.64. Box rows are quoted at full bob (+-0.35), which is the pose the client
can actually put them in.

### New parts — frontage row (6 slots, x-centre 30.40, 3.15 pitch, z -68.0..-46.1)

| Part | Size (along wall x h x depth) | Centre y | y span | x span | Worst corner | r | Limit | Clear |
|---|---|---|---|---|---|---|---|---|
| `ShopProjectorDisc` (CylinderMesh) | 2.60 x 0.20 x 2.60 | 0.90 | 0.80..1.00 | 29.10..31.70 | (31.70, 0.80) | 31.701 | 33.05 | 1.349 |
| `ShopNamePlate` | 2.86 x 1.10 x 0.12 | 1.80 | 1.25..2.35 | 29.08..29.20 | (29.20, 2.35) | 29.231 | 33.05 | 3.819 |
| `ShopProjectorBeam` (low slot) | 0.50 x 2.25 x 0.50 | 2.125 | 1.00..3.25 | 30.15..30.65 | (30.65, 3.25) | 30.732 | 33.70 | 2.968 |
| `ShopProjectorBeam` (high slot) | 0.50 x 3.40 x 0.50 | 2.70 | 1.00..4.40 | 30.15..30.65 | (30.65, 4.40) | 30.838 | 33.70 | 2.862 |
| `ShopHologramBox` (low, slots 1/3/5) | 3.00 cube | 4.40 | 2.55..6.25 | 28.90..31.90 | (31.90, 6.25) | 32.329 | 33.05 | 0.721 |
| `ShopHologramBox` (high, slots 2/4/6) | 3.00 cube | 5.55 | 3.70..7.40 | 28.90..31.90 | (31.90, 7.40) | 32.536 | 33.05 | 0.514 |
| `ShopPressurePlate` | 3.10 x 0.12 x 3.40 | 0.86 | 0.80..0.92 | 26.08..29.48 | (29.48, 0.80) | 29.481 | 33.05 | 3.569 |

### New parts — kiosk supply bays (2 slots, x-centre 29.70, z -42.3..-33.4)

| Part | Size | Centre y | y span | x span | Worst corner | r | Limit | Clear |
|---|---|---|---|---|---|---|---|---|
| `ShopProjectorDisc` | 2.60 x 0.20 x 2.60 | 4.62 | 4.52..4.72 | 28.40..31.00 | (31.00, 4.72) | 31.222 | 33.70 | 2.478 |
| `ShopProjectorBeam` | 0.50 x 1.33 x 0.50 | 5.385 | 4.72..6.05 | 29.45..29.95 | (29.95, 6.05) | 30.373 | 33.70 | 3.327 |
| `ShopHologramBox` | 3.20 cube | 7.30 | 5.35..9.25 | 28.10..31.30 | (31.30, 9.25) | 32.372 | 33.70 | 1.328 |
| `ShopPressurePlate` | 3.10 x 0.12 x 3.40 | 0.71 | 0.65..0.77 | 22.80..26.20 | (26.20, 0.65) | 26.202 | 33.70 | 7.498 |

The bays are at z -42.3..-33.4, nowhere near the rib arch, so they answer only to the shell.

### Parts that cross the rib band, measured

Slots 5 (`EmergencyReentry`, z -55.35..-52.35) and 6 (`CosmeticEquipment`, z -52.20..-49.20)
cross z -52.36..-51.64. All four of each slot's parts are flagged and checked by the test:
box 32.469, disc 31.701, nameplate 29.231, plate 29.481 — the worst is 0.514 clear of 33.05.
The pre-existing sign glow panel is still the tightest thing in the shop at r = 33.040,
0.010 under the derated limit and 0.21 clear of the ribs themselves. I did not touch it.

`ShopAlcoveBackdrop` (r = 33.611) keeps the documented wall-dressing exemption: it is flat
against the wall at x >= 32.34 and the arch crosses in front of it. The test now enforces
that exemption instead of assuming it — a part claiming it must have its road-side face at
x >= 32.0.

### Lane clearance

| Edge | Road-side face | Limit | Clear |
|---|---|---|---|
| Frontage pressure plate | x 26.08 | 25.78 | 0.30 |
| Frontage deck (unchanged) | x 26.00 | 25.78 | 0.22 |
| Kiosk bay pressure plate | x 22.80 | 22.60 | 0.20 |
| Curb face to the nearest shop part | x 17.80 -> 22.80 | — | 5.00 studs of open lane |

The road keeps its full 33-stud width (x -16.5..+16.5). `TunnelLobbyBuilder` is untouched:
no queue station, gate, kiosk shelf, counter or floor pad moved. The shop is now
**walk-through** — the only solid part left in it is `ShopRewardsPlinth`, and the test
asserts exactly that for all 56 parts.

## What was removed

* `ShopPedestal` (the 4.00-tall solid column, one per item — the only thing in the shop
  that blocked a player), `ShopPedestalCap`, `ShopPedestalRing`.
* `ShopInspectPrompt` x 8 (six frontage, two kiosk bays), the `prompts` table, the
  `Triggered` handlers, the `latched` map, `pedestalPosition()` and `LATCH_RANGE`.
  The whole latch branch of `focusFor` is gone: focus is now purely positional.
* `ShopInspectPlateEdge` x 8 (the neon border), the `PlateTop` decal, and the
  `"STEP TO\nINSPECT"` `PlateHint` SurfaceGui.
* `ShopItemBox` (the opaque 2.20 metal crate with art on four faces).
* `SHOP_TEXTURES.PedestalTop` (`101891958398163`) and `SHOP_TEXTURES.PlateTop`
  (`131434121223604`). Both surfaces no longer exist. The ids are recorded in a comment at
  the top of the module and remain in `assets/shop/README.md`; nothing else in the repo
  referenced them (checked with grep across every service folder).
* Client: `SPIN_RATE` and the `CFrame.Angles` term. The word "inspect" no longer appears
  in either file in any case (asserted in Python before the run).
* Plaque copy: `"FREE DAILY SPIN"` -> `"PLAY TO EARN"`, `"ZYNTRA TERMINAL"` ->
  `"PRESS E TO OPEN"`. Prompt `ObjectText` `"Zyntra Terminal"` -> `"Daily Rewards"`.
  The prompt keeps `ZyntraShopPrompt` + `ShopRewardsPrompt = true`, so A-RAIL's rebinding
  to `OpenDailyRewards` needs nothing from me.

## Verified offline, and how

`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`.

* Both `.lua` files compile: `luau-compile.exe --binary` on each, clean.
* `tools/tests/test_lobby_shop_display.py` — **802 checks**, up from 404. It runs the real
  `LobbyShopDisplay.Build` against the real `ZyntraConfig` catalogue and the real
  `Shop Display Client` against a fake PlayerGui/UIDevice. Neither is pattern-matched.
  * Geometry is **computed from the built parts**, not read from the source: a helper
    derives each part's world extents from its `CFrame` (all shop parts are a quarter turn
    about Y, so local x is along the wall) and tests all eight corners of all 56 parts
    against 33.70, plus 33.05 for the ones whose z span actually intersects the rib band.
    Same loop checks the lane limit at the road-side face, the y floor and ceiling, and
    that only `ShopRewardsPlinth` collides.
  * Retired names are asserted absent by tallying every descendant's name.
  * Per item: exactly one box / disc / beam / plate; box is ForceField at 0.35 with
    **exactly one** Decal, on `NormalId.Front`, at `Transparency 0` (so a fallback
    monogram would fail the test — all eight keys have uploaded art); SelectionBox and
    PointLight present; disc has a `CylinderMesh` and is 2.60 x 0.20; beam is 0.50 square,
    non-query/non-touch/non-collide, and its top is exactly `box bottom + 0.35` so the
    bob never opens a gap; plate is `Transparency 1`, non-query/non-collide/non-touch,
    childless and carries `ShopItemKey`.
  * Alternating heights are checked by sorting the frontage row by z: 4.40 / 5.55 / 4.40…,
    pitch exactly 3.15, neighbours more than 1.0 apart in y.
  * Focus: publishes on step-on, **switches** when the player steps into the neighbour's
    zone and switches back, clears on step-off and stays clear for five further polls,
    holds through hysteresis at the edge, writes nothing across ten polls standing still
    (the debounce), both the road-side and wall-side edges of the enlarged zone are live,
    blanks during `InRound` and returns after.
  * Card: opens on focus without firing the buy bridge, routes BUY exactly once, and —
    the reopen-loop case — after CLOSE it stays down while every other signal the client
    listens to is fired (`ZyntraSpeedPotions`, `ZyntraReentryCredits`, modal changed,
    UI changed). It reopens only on a focus change (next hologram) or a step-off/step-on.
  * Tiers 300 / 380 / 560 with icons 52 / 64 / 112, phone card exactly 300x200, BUY and
    CLOSE both >= 44px on both touch tiers, all type >= 11px, short-screen give-way and
    the native free-lane composition unchanged.
  * Motion: boxes bob, bob never exceeds the 0.35 the geometry was solved for, **yaw never
    changes** (the fake CFrame carries a `Yaw` and it is compared every frame for 7 s),
    sign swell, `ReduceFlashing` calms it, a round freezes and restores every pose.
* `tools/tests/test_lobby_palette.py` (888 checks) and `tools/tests/test_donation_board_columns.py`
  (826 checks) both still pass — `TunnelLobbyBuilder` is genuinely untouched.

## NOT verified — needs Studio

1. **Native walk-through at desktop and phone.** Nobody has walked this. Specifically:
   does the enlarged 3.40-deep zone open the card at the moment the player expects, and
   does walking the row switch cards cleanly at 3.15 pitch with 0.6 of hysteresis?
2. **The hologram look.** A `Decal` on an `Enum.Material.ForceField` part is the one
   rendering assumption I could not test offline. If the product art reads badly through
   the ForceField shader, switch the box to `Enum.Material.Glass` — one constant, no
   geometry changes. Also unchecked: whether the 0.85-transparent beam is visible at all
   against the lit deck, and whether the SelectionBox edge still reads on a translucent part.
3. **Trigger feel.** Debounce is `FOCUS_POLL` = 0.2 s, unchanged from the prompt build,
   but the plate is now the only way in, so a 0.2 s lag on stepping on is more noticeable.
4. **The removed collider.** With the pedestals gone the player can walk to the backdrop
   at x 32.34. The `RaisedServiceLedge` runs to x 33.2, so there is floor the whole way,
   but that is read from `TunnelLobbyBuilder`'s source, not observed.
5. **Camera.** Walking under a 3.00 box at y 2.55 will push the third-person camera. Not
   modelled offline.
6. Both files are LF-on-disk after editing, like every other file this batch touched.
   `tools/studio_source_contract.py` normalises line endings before hashing, so this is
   benign, but the manager should expect it on the push.

## Decisions

1. **No yaw.** The shipped client turned the crates at 24 deg/s; the brief allowed a new
   turn up to 12 deg/s. I removed turning entirely. The product art lives on the one face
   that looks at the road, and a turning box spends half its cycle hiding it. It also
   removes the diagonal footprint: a 3.00 cube swung 45 deg reaches 2.12 from centre and
   would overlap its neighbour by 1.09 studs at the 3.15 pitch, which no stagger that fits
   under the canopy could separate. Even a +-10 deg sway overlaps by 0.33. Square-on is
   the only pose where 3.00 boxes fit this row.
2. **Hover pair 4.40 / 5.55, not the brief's 4.6 / 6.4.** The brief's high row tops out at
   8.25 with its bob. That does not collide (the fascia is only 0.44 deep and the boxes
   stand behind it; the real collider is the soffit at 8.90) but it is **occluded**: from
   the far lane of the road, eye about (16, 4.5), the line grazing the fascia's inner
   bottom corner (28.64, 7.60) is at y 7.66 over the front face of a box. A box top at
   8.25 loses its top half-stud behind the fascia for every player who has not walked up
   yet. 7.40 clears that by 0.26 and keeps 1.50 studs under the soffit. The module header
   carries this arithmetic. The stagger is 1.15 studs — it buys visual rhythm and an
   oblique sightline to both rows, not clearance, and the header says so.
3. **`CylinderMesh` on a normal Part, not a `Cylinder`-shaped part.** A Cylinder part's
   axis is +X and would need a 90 deg roll to lie flat, putting a rotation into geometry
   whose every corner is checked against a radius. `CylinderMesh`'s axis is already +Y.
4. **The nameplate moved and shrank** (1.43 -> 1.10 tall, y 3.20 -> 1.80). It had been
   bolted to the column I deleted. It now floats in the beam under the box, in front of
   it rather than behind it, so nothing translucent sits between the name and the road.
   Width stays 2.86, so physical glyph height is unchanged; canvas 144x72 -> 143x55 keeps
   the 50 px/stud and matches the new 2.6:1 face so nothing stretches.
5. **Plate 3.10 along the wall, not the brief's 3.40.** 3.40 at a 3.15 pitch overlaps its
   neighbour by 0.25, and the winner in an overlap depends on the order the row is built.
   3.10 leaves a 0.05 gap that `PLATE_HYSTERESIS` (0.6) covers. Depth took the full 3.40
   and the plate moved 0.40 toward the row. I also made `plateUnder` test the **held**
   zone first so hysteresis always beats a neighbour's raw zone, in both directions.
6. **Kiosk bay hologram moved to (29.70, 7.30) from (30.75, 6.00).** A 3.20 box at the old
   pose cuts the bay shelf at y 4.46 on the down-bob and the bay info card at y 7.56 on
   the up-bob. Its disc floats 0.06 over the shelf lip rather than resting on it — a disc
   on the deck would be hidden behind the counter top at y 4.22.
7. **`addDecal` now sets `Transparency = 0` explicitly.** It was the default, but on a
   0.35-transparent box the fact that a Decal inherits nothing from its part is the whole
   reason the art reads. Stated so it is testable.
8. **No asset request.** `assets-handoff.md` says the existing art is sufficient and
   `SHOP_TEXTURES.Box` already covers all eight keys. I did not create
   `asset-requests.md`. If the native check finds the crate art reads wrong as a hologram
   panel, that is when to ask — not before anyone has looked at it.
9. **Close hint on the kind row, right-aligned**, rather than as its own line. Zero height
   cost on a 200px phone card that already has an ordered give-way ladder. Proportional
   Gotham instead of the kind tag's monospace: 27 characters of Code does not fit 168px.

## Open for the owner

* The pointer card is now 560 wide with a 112px icon. If that is too large next to the
  terminal's own 420px cards, the tier row is one table in `cardFace()`.
* `"PRESS E TO OPEN"` on the plaque is the copy the brief specified. It is wrong wording
  for touch and gamepad; the ProximityPrompt itself shows the right glyph. Say the word
  and it becomes "HOLD TO OPEN" or drops the input entirely.

## Trello draft — card #105

> **Done — the shop is now floating holograms with an invisible trigger.**
>
> Every product on the wall and both token bays are now a translucent hologram box
> floating in a projector beam, 3.00 studs on the frontage and 3.20 at the kiosk bays
> (they were 2.20 opaque crates). The product art you already uploaded is reused
> unchanged, on the one face that looks at the road, fully opaque so it reads through the
> box. The row hovers at two alternating heights so it does not occlude itself when you
> read it from down the tunnel.
>
> The pedestal columns are gone, so you can now walk right up to a hologram — the whole
> shop front is walk-through, and the only solid thing left in it is the Daily Rewards
> plinth. The Inspect prompt is gone from all eight stands.
>
> The trigger is the pressure plate, now invisible and larger (3.10 x 3.40, pulled a
> little toward the wall so you cross it walking up). Step on it and that product's card
> opens by itself. Step to the next one and the card switches. Step off and it closes.
> Press CLOSE and it stays closed until you move to another product or step off and back
> on — it cannot reopen while you stand still.
>
> **Opening a card still never buys anything.** BUY is the only purchase path and it is
> the same one the terminal's own cards use, so product ids, prices, inventories,
> ownership and receipts are untouched. The desktop card grew to 560px with a 112px icon;
> phone and tablet are unchanged and every tap target is still 44px.
>
> The Daily Rewards plaque stays and now reads DAILY REWARDS / PLAY TO EARN / PRESS E TO
> OPEN. Nothing reaches into the walk lane or the road, and every corner of all 56 parts
> is inside the tunnel shell with the tightest new part 0.51 studs clear of the rib arch.
>
> Offline: 802 automated checks (was 404) running the real server module and the real
> client script; both compile.
> Still to confirm in a live test: how the art reads through the ForceField material, the
> feel of the auto-open trigger, and a walk-through on desktop and phone.
