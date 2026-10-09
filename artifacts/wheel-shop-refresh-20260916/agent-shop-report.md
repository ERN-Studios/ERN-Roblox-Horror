# A-SHOP — contract section 2, "Shop along the whole wall"

Status: implemented in the repo, verified offline. **Nothing pushed to Studio, git or
the manifest.**

## Files changed (only mine)

| File | What |
|---|---|
| `ServerScriptService/LobbyShopDisplay.ModuleScript.lua` | v3 → **v4**. 795 → 358 lines. Eight hologram boxes + eight invisible plates, nothing else. |
| `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua` | SHOP eyebrow, new kind tags, contract bob formula, sign pulse deleted. |
| `ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua` | Kiosk removal only: `addSupplyKiosk` + `addGameplayShopkeeper` definitions and the one call site, replaced by a 9-line comment saying what stood there and why it went. |
| `tools/tests/test_lobby_shop_display.py` | Rewritten for v4. |

## Verified offline

```
LUAU_BIN=.../codex-luau-0.737/luau.exe
python tools/tests/test_lobby_shop_display.py
  ok  2878 checks: 8 boxes on 16 parts, z -66.00..-14.00,
      worst corner r 32.900 (shell) / 32.900 (rib), tiers 300/380/560 px
python tools/tests/test_lobby_palette.py
  lobby palette + supporter board: 828 checks passed
```

Not required, but run because they read the same two files, and all green:

```
tools/tests/test_donation_board_columns.py    826 checks (+ builder compiles, 84198 B bytecode)
tools/tests/test_first_entry_guide.py          39 checks
tools/tests/test_zyntra_store_compact.py      540 checks
```

`luau-compile.exe --binary` is clean on all three `.lua` files.

The suite RUNS both scripts against a fake DataModel rather than pattern-matching them, so
a typo fails it. What it now holds, beyond the previous suite: eight box centres at
`-66 + 52/7*i` to 1e-6; every corner inside `r <= 33.70` (shell) and `r <= 33.05` (rib band
`-52.36..-51.64`) **measured at the top of the client's 0.35 bob, not at rest**; every box
centre >= 3.4 from both gate post edges; plate zones >= 4.0 apart AND wider than two
hysteresis slacks; six decals per box, one per named face, all the same id, and the eight
ids distinct; no descendant whose name contains deck/backdrop/sign/nameplate/projector/
beam/plinth/plaque/prompt/canopy/fascia/pilaster/pedestal/kiosk/monogram/trim/flood/soffit;
no `ProximityPrompt`, `SurfaceGui`, `TextLabel`, `Texture`, `SurfaceLight`, `SpotLight` or
`CylinderMesh` anywhere in the model; the bob checked against the exact formula
`origin + 0.35*sin(t*2π/3.4 + ShopBobPhase)` per box using the server's own phase, three
times a second over seven seconds; the walk *between* two boxes returns `nil` focus; and a
Python-side check that TunnelLobbyBuilder no longer contains any of the nine kiosk markers
while keeping the six concourse ones.

## What still needs Studio

1. **The real envelope.** The test measures corners against the documented radii (shell
   33.9, rib 33.25). It cannot see the actual concrete mesh. Worst corner is a box rear top
   at `(31.90, 9.05)` → r 32.900, i.e. **0.150 clear of the rib arch** at slot i = 2
   (z −51.14, the only one that crosses `-52.36..-51.64`). That is the tightest number in
   the build and it wants eyes on it in the place.
2. **Walkability.** Both gate thresholds and the ledge in front of them, with a box
   overhead at 5.30–9.05 (4.65 studs of headroom over the ledge top at 0.65). Nothing in
   the model is collidable, so this is a visual/feel check, not a collision one.
3. **Six-face decals on a ForceField part.** `Material.ForceField` at `Transparency 0.35`
   renders unlike SmoothPlastic; the Top and Bottom faces in particular have never carried
   art before. If a face reads badly, the fix is art-side, not code-side.
4. **The hole the kiosk left.** `ZyntraSupplyKiosk` included a decorative `ShopFloorPad`
   over the `RaisedServiceLedge` at z ≈ −795. The ledge itself is builder geometry and is
   untouched, so there should be bare ledge there now — confirm it does not read as a gap.
5. **Terminal access.** `ZyntraShopPrompt` no longer exists anywhere in the place, so the
   ZyntraStore terminal is reachable **only** from its left rail button. ZyntraStore's
   `CollectionService`-style prompt binding is unchanged and simply finds nothing (that is
   the contract's own preamble). Worth one play-test confirm.
6. **The bob under `ReduceFlashing`** — see decision 3 below; it is a behaviour change.

## Decisions

1. **The monogram fallback was dropped.** v3's per-box art chain had four rungs; v4 has
   three: product texture → `SHOP_TEXTURES.BoxFallback` → `item.IconId`. The fourth rung
   drew `item.IconText` into a `SurfaceGui` — the only thing in the whole model that could
   put *text* on the wall, which the contract's test list forbids outright. All eight keys
   have art at rung 1 and `BoxFallback` is a real uploaded id, so a blank face needs three
   ids to be missing at once. A missing id now `warn`s instead (and the test asserts the
   build warns zero times). This drops `addFace`/`addText`/`addTexture` from the module.
2. **Gate clearance is 3.45, not 3.5.** The contract fixes the centres at z −66.0 and
   −14.0; the post edges are at −69.45 and −10.55, so centre-to-post-edge is exactly 3.45
   (box face to post edge: 1.75). The contract's own test spec says `>= 3.4`, which is what
   I implemented. The prompt's prose said 3.5. I used the stated centres.
3. **`ReduceFlashing` / `ReduceCameraShake` now STOP the bob.** Previously they only made
   the overhead sign's pulse slower and shallower; the sign is deleted, so there was
   nothing left for them to do. The contract says the bob "stands down in rounds and under
   `ReduceFlashing`/`ReduceCameraShake` ... (`motionAllowed`)", so both flags are now in
   `motionAllowed` and every pose is restored. This is a real behaviour change for a player
   with either setting on: their shop is completely still. The boxes are readable standing
   still — the art is on all six faces — so it costs nothing.
4. **`BOB_PERIOD` 4.2 → 3.4 s** and the per-box offset moved from the client's
   `index * 0.7` to the server's `ShopBobPhase`, per the contract formula. The phase is now
   authoritative on the server, so every client sees the same row.
5. **The SHOP eyebrow is the last rung of the card's give-way ladder.** It is a new row
   above the product name (GothamBlack, accent, `face.Kind` px). The ladder is now: the
   icon/description row shrinks → the state line goes → the eyebrow goes. On the two
   cramped compositions the suite measures (568×262 short landscape, and the 568×320
   native free lane of 156 px) the eyebrow hides, because the alternative is a clipped BUY
   button. Everywhere else — phone 956×382, tablet, pointer — it shows. Card heights moved
   300×**217** / 380×242 / 560×295.
6. **"SHOP IS STILL LOADING" → "STILL LOADING"** in the bridge-missing error, so `SHOP` is
   written in exactly one place as the contract requires.
7. **The close hint is unchanged** ("Step off the plate to close" / "…or press CLOSE").
   `plate` is not in the forbidden grep list and the contract did not ask; the invisible
   plate is still literally what closes the card.
8. **`ShopDisplayVersion = 4`**, `Placement` = "Right wall between the Level 2 and Level 4
   gates", `FrontmostX` = 26.18 (27.78 − 1.60). `CanopyClearanceY` was dropped with the
   canopy. `ShellInnerRadius` / `RibInnerRadius` kept so a Studio probe can still check the
   geometry without reading the source.
9. **`LobbyConcourseVersion` left at 6** in TunnelLobbyBuilder — the contract says touch
   nothing else in that file.
10. **`DISPLAY_ORDER` gained the two token items** and `SOURCES` gained `Config.Items`, so
    all eight come from one ordered list. The "anything not named here still gets a box"
    fallback loop is unchanged, and the spacing formula is `(Z_LAST - Z_FIRST)/(count - 1)`,
    so a ninth product re-spreads the row instead of falling off the end.

## Open questions for the owner

- **ZyntraStore's Rewards route.** `ZyntraStore.openKioskShop(... "Rewards" ...)` fires when
  a bound prompt carries `ShopRewardsPrompt`. That prompt was the Daily Rewards plaque, now
  deleted, so that branch is unreachable from the world. Harmless dead code in a file I do
  not own — flagging it rather than touching it.
- **`assets/shop/README.md`** still lists SignFace / SignGlow / Backdrop / CanopyFascia /
  NamePlate / RewardsPlaque as shop textures. They now dress nothing. Not my file.
- The rear faces of the boxes sit 1.0 stud off the wall inner face (31.90 vs 32.90). Close
  enough to read as "on the wall", far enough not to z-fight. Worth an eye in Studio.

## Removed instances, by name

### `LobbyShopDisplay` (server model `ZyntraShopDisplay`)

`ShopDeck`, `ShopAlcoveBackdrop` (+ its tiling `ShopTexture`), `ShopPilaster` ×2,
`ShopPilasterTrim` ×2, `ShopCanopyFascia` (+ `ShopTexture`, the `ShopFace` SurfaceGui and
its `CanopyWord` TextLabel reading "ZYNTRA  //  SUPPLY", and `ShopCanopyLight`),
`ShopCanopySoffit`, `ShopFloodHousing` ×3 (+ `ShopFloodLight` ×3), `ShopSignGlowPanel`
(+ decal), `ShopSignFace` (+ decal, and the procedural `SignWord` "SHOP" / `SignLine`
"ZYNTRA // SUPPLY" fallback), `ShopSignTrim` ×2, `ShopSignLight`, `ShopProjectorDisc` ×8
(+ `ShopProjectorDiscMesh` ×8), `ShopProjectorBeam` ×8, `ShopNamePlate` ×6 (+ decal,
`ShopFace` SurfaceGui, `ItemKind` and `ItemName` TextLabels), and the whole
`ShopStand_DailyRewards` model: `ShopRewardsPlinth` (the only collidable part in the shop),
`ShopRewardsFrame`, `DailyRewardsPlaque` (+ decal, `ShopFace` SurfaceGui with
`RewardsTitle` "DAILY", `RewardsTitle2` "REWARDS", `RewardsLine` "PLAY TO EARN",
`RewardsFoot` "PRESS E TO OPEN", and `ShopRewardsGlow`) and the `ProximityPrompt` named
**`ZyntraShopPrompt`** carrying the `ShopRewardsPrompt` attribute.

Also gone as concepts: the two kiosk bays (`ShopSupplyBay` stands at z offsets 16.3 / 22
with `BAY_BOX_X/Y`, `BAY_BASE_Y`, `BAY_PLATE_X`), the alternating `BOX_Y_LOW`/`BOX_Y_HIGH`
hover pair, and `AREA_Z`/`AREA_HALF` (`faceCF` now takes z relative to the lobby centre
directly, which is the frame every measured number in the contract is in).

### `TunnelLobbyBuilder` (model `ZyntraSupplyKiosk`, and the `ZyntraShopkeeper` character)

The whole model and everything under it:
`ShopFloorPad`, `ShopBackWall`, `ShopRecessBackdrop`,
`ShopSideWing` ×2, `ShopFaceColumn` ×2, `ShopPortalVerticalGlow` ×2, `ShopHazardCap` ×2,
`ShopCanopy`, `ShopCanopyFascia`, `ShopPortalTopGlow`,
`ShopOverheadSign` (board "SHOP" / "EQUIPMENT • UPGRADES • RECOVERY", both tagged
`ShopMasthead`), `ShopSignTopTrim`, `ShopSignBottomTrim`, `ShopHeaderMarker` ×7,
`ProductBay1..3` × {`Recess`, `Shelf`, `ShelfGlow`, `Edge` ×2, `Info`} with the boards
"SPEED POTION" / "ROUTE MARKERS" / "RECOVERY",
`DisplayRecoveryCase`, `RecoveryCrossVertical`, `RecoveryCrossHorizontal`,
`RecoveryCaseHandle`,
`ShopUtilityShelf1..2`, `ShopSupplyCanister` ×6, `ShopCanisterBand` ×6,
`ShopCounterFront`, `ShopCounterTop`, `ShopCounterTopGlow`, `ShopCounterBottomGlow`,
`ShopCounterTelemetryGlass`, `TelemetryBar1..7`,
`ShopCounterCabinet1..3`, `ShopCounterCabinetHandle1..3`,
`ShopProductScanner`, `ShopScannerLine`,
`ShopAccessTerminal` (board "OPEN SHOP" / "PRESS  E  //  EQUIPMENT", attributes
`ShopInteraction` / `InteractionRole = OpenZyntraStore`) and its `ProximityPrompt` named
**`ZyntraShopPrompt`**, `ShopTerminalRail` ×2,
`ShopApproachInlay` (board "SHOP ACCESS" / "APPROACH TERMINAL"), `ShopApproachEdge` ×2,
`ShopkeeperPlatform`, `ShopkeeperPlatformGlow` ×2,
`ShopDisplayDownlight1..3` (+ `ShopDisplayLight1..3`),
`ShopkeeperKeyLightMount` (+ `ShopkeeperKeyLight`),
and the cloned `StarterCharacter` model named **`ZyntraShopkeeper`**.

Nothing else in `ZyntraDispatchConcourse` moved: `ArrivalGantryPost`/`Foot`/`Beam`,
`ConcourseCrossingStripe` ×9, both `addConcourseBench` calls, `addDonationLeaderboard`,
`addPartyButton` and `ZyntraSignalConsole` are untouched, and the
`task.spawn(... LobbyShopDisplay.Build ...)` at the end of `Builder.Build` is byte-identical.
`addBoard` is kept — five other call sites use it.

## Server per-frame work

None added. The only server loop is the unchanged `FOCUS_POLL = 0.2 s` focus pass, which
writes an attribute only when the answer changes. The bob is entirely client-side and
writes nothing that replicates.
