# Agent A88 — Trello #88, existing-product shop redesign (phase 1, offline)

Opus 5 agent A88, 2026-09-15. Phase 1 is code + tests only; **no Studio tool was
used and nothing has been seen running.** Everything below that says "verified"
was verified by the offline Luau harness or by `luau-compile`, and is named as
such. The Studio steps are listed at the end for the resume.

---

## 1. The design

### The wall

**Right service ledge, world z −68.2 … −45.8, wall face x = +32.9, ledge floor
y = +0.65** (all relative to the lobby centre `LOBBY_CENTER`).

Why this stretch and not another:

* It is the only empty closed-wall run on the main walk. `Builder.Build`'s
  `wallRanges` gives four closed sections per side. This one (`{-70, -10}`,
  right) has the **Level 2 gate's lintel ending at z = −69.5** and the
  **supply kiosk's floor pad starting at z = −44.75**; between them, 23 studs
  of bare concrete with nothing on it — checked part by part against the
  builder: the only thing crossing it is the `WallConduit` bar at x = 33.2,
  y = 10.5, which is behind and above everything the shop adds.
* It is on the funnel. A player spawns at z = −100 facing +Z, walks under the
  arrival gantry at −92.2, passes the Level 1 (left) and Level 2 (right) gates
  at −80, and this frontage is the next thing on their right — and it reads as
  one shop district with the existing Zyntra supply kiosk 13 studs further on,
  whose terminal is still the full catalogue.
* It stays clear of A7890's card #78. The donation leaderboard is on the
  **left** wall at x = −30, z = −35, so an enlarged Top Supporter sign cannot
  collide with this.
* **No existing geometry is moved, resized or deleted.** The shop is built in
  front of the wall: a deck, a back panel 0.25 studs proud of the wall face,
  two pilasters, a soffit, six stands.

The height ceiling is not the wall, which is why the sign stands forward rather
than flat: the tunnel's **curved shell** (inner radius 33.9 about x = 0,
y = +1) and its **reinforcement rib arch at z = −52** (inner radius 33.25) cut
in above roughly y = 9. The sign box sits at x = 31.22 … 31.62, y = 7.0 … 10.6,
whose far corner measures 33.05 from the tunnel axis — 0.2 studs clear of the
ribs. That arithmetic is in the module's header comment so the next person does
not have to redo it.

### The layout

```
  road  <—  x                                                      wall x=32.9
        plates x≈27.5      pedestals x≈30.0-30.9     sign x≈31.4   back x=32.55
        ┌───┐              ▉ crate (bobbing, 2 studs, y≈4.55)
        │ ▣ │  3.4x3.4     ▇ cap + emitter ring (y≈3.0)
        └───┘              █ pedestal 2.2x2.6, nameplate on its road face
                           ↑ ProximityPrompt "INSPECT"
   6 stands, 3.7 studs apart, on a gentle arc (middle leans 0.85 studs roadward)
   SHOP sign 14.4 x 3.6 above them, glow panel behind it, soffit over the lot
```

Six stands = every existing catalogue item, **nothing new**: Supporter,
AdvancedEquipment, Tokens4, Tokens20, EmergencyReentry, CosmeticEquipment, in
the terminal's own Shop-tab order. A key added to `ZyntraConfig` later gets a
pedestal automatically, with the fallback crate.

Lighting is deliberately restrained: one SurfaceLight on the sign, two
downward SpotLights over the row, one small PointLight per crate in the item's
accent colour. No moving beams. The sign's breath is the only motion in the
geometry, and the client owns it so it can stand down.

### The interaction contract

1. **Step on a plate** → the server sets `player:SetAttribute("ZyntraShopFocus",
   "<itemKey>")`. **Or press INSPECT** on the pedestal's ProximityPrompt (E /
   gamepad X / tap), which latches the same attribute and toggles it off on a
   second press. The latch drops when the player walks more than 14 studs from
   that pedestal.
2. The client draws **that item's card, for that player only** — name, kind,
   what you get, owned/used state, and the **live** price fetched from
   `MarketplaceService:GetProductInfo` exactly as `makeProductCard` does (the
   configured price shows until it answers, so the card always states a
   number).
3. **Nothing about focus ever prompts a payment.** The server module does not
   reference `MarketplaceService` at all — not for a prompt and not for a
   price, because a price read once per server could later disagree with a live
   sale. The test asserts this three ways: no `Prompt*Purchase` in the source,
   no `GetService("MarketplaceService")` in the source, and a fake DataModel
   that *errors* if the module asks for that service.
4. **BUY** fires `PlayerScripts.ZyntraShopBuy` with the item key. ZyntraStore
   listens and runs `productPurchase[key]` — the *same named function* its own
   product-card button runs. There is still exactly one place in the game that
   prompts Robux for an item. An owned pass shows `OWNED` and is taken out of
   the input stack, so it cannot route at all.
5. **Closing:** step off the plate (server clears the attribute), press INSPECT
   again, or press CLOSE. CLOSE dismisses only the current focus — step off and
   back on, or move to another pedestal, and the card returns. It also closes
   itself when a round starts and while a screen-owning modal (the terminal) is
   up.
6. Focus is derived every 0.2 s from the player's position rather than latched
   on `Touched`/`TouchEnded`, so a death, teleport or respawn cannot leave a
   card stuck open. 0.2 s is the debounce; a 0.6-stud hysteresis ring keeps a
   player standing on the edge from flickering it.

### Mobile fit

The card reuses the terminal's own three tiers and the same tier expression
(`(compact and touch) and 1 or (touch and 2 or 3)`), with the **same icon
ladder 52 / 64 / 76 px** that `test_zyntra_store_compact.py` pins, so a crate's
card and its terminal card are visibly the same object. Widths 300 / 380 / 420.
`compact` is read from the modal viewport, not from the card's own width (a
420px card would otherwise call itself compact on every screen).

It sits **bottom-centre of the true safe area**, not in a HUD corner: the top
right is the player list's on desktop, the left rail is the store's three
section buttons. On touch it is lifted above `Zones.Controls.Top`, because
walking off the plate is how the card is meant to close and a card over the
thumbstick would take that away.

On a short screen it gives way in one stated order — the icon/description row
shrinks to a 28px floor, then the state line goes — and **never** the type
(≥ 11px) or the tap target (≥ 44 on touch). Measured in the test at 956x382,
1024x700, 1280x684 and the 568x262 worst case.

### Accessibility

`ReduceFlashing` is honoured in both new places, and neither ever strobes:

* the sign's glow panel breathes on a cosine, 3.2 s period / 0.26 transparency
  range normally, **6 s / 0.10** under ReduceFlashing;
* the HUD shop ring breathes on a 2.6 s tween (≥ 2.4 s as briefed), **6 s and
  half the depth** under ReduceFlashing;
* **no colour ever changes** in either — a pulsing colour is a strobe with
  extra steps;
* the crates keep bobbing under ReduceFlashing (motion is not flashing), and
  all of it stops when `InRound` or `RoundActive` goes true, restoring every
  pose it wrote.

`ReduceCameraShake` is not relevant: nothing here touches the camera.

### The HUD icon

`ZyntraShopButton` only (the Upgrades and Music buttons are untouched):
the button's own `UICorner` becomes `UDim.new(1, 0)` — a disc — its accent
`UIStroke` thickens to 2.4–3.4 and breathes, and its icon/caption inset moves
from 3 to 8 px so they sit inside the disc. The hover border
(`SquareSectionBorder`) is untouched and still owns `MouseEnter`/`MouseLeave`,
so the two never fight over one property. **The button's rectangle does not
change** — `layoutSquareSections` still owns size and position, so
UIRegression's fit matrix measures exactly what it measured before.

---

## 2. Files

### New — the lead must create these in Studio first (they cannot be pushed)

| Studio path | Class | Repo mirror |
|---|---|---|
| `ServerScriptService.LobbyShopDisplay` | **ModuleScript** | `ServerScriptService/LobbyShopDisplay.ModuleScript.lua` (531 lines) |
| `StarterPlayer.StarterPlayerScripts."Shop Display Client"` | **LocalScript** | `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua` (463 lines) |

`LobbyShopDisplay` must be a **direct child of ServerScriptService**, beside
`TunnelLobbyBuilder` — the hook resolves it as `script.Parent:WaitForChild(...)`.
Both need manifest items afterwards (`sha256_of` / `canonical_bytes` from
`tools/studio_source_contract.py`); `test_full_sync_contract.py` currently fails
on exactly these two being unlisted (plus `UIStyle` and `Level 1 Cable Current`
from other agents).

### Edited

* **`StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`** — four
  surgical hunks, all re-read immediately before editing:
  * `local productPurchase = {}` beside `productButtons` (~L31);
  * `local shopButtonRing = outline(shopButton, …)` — captures the stroke that
    was already there, no new instance (~L204);
  * the circular + breathing block inside the existing
    `for _, entry in ipairs({openButton, shopButton, musicButton})` loop, guarded
    by `if entry == shopButton` (~L222–262);
  * inside `makeProductCard`, the anonymous `buy.Activated` handler became the
    named `requestPurchase`, registered as `productPurchase[key]` and connected
    unchanged — **the purchase logic itself is byte-identical**;
  * the `ZyntraShopBuy` bridge at the end of the file.
* **`ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua`** — **one line**
  (plus three comment lines) immediately before `return model, spawn, stations`:
  ```lua
  task.spawn(function() require(script.Parent:WaitForChild("LobbyShopDisplay")).Build(model, {Center = center}) end)
  ```
  Spawned rather than called so a fault in the shop can never cost the lobby,
  and so a missing module cannot hold the build (it prints Roblox's own
  "Infinite yield" warning instead). A7890's leaderboard work in the same file
  is untouched.
* **`ReplicatedStorage/UIRegression.ModuleScript.lua`** — **deliberately not
  edited.** `Fit.zyntraDisabledReason` is only asked about controls the terminal
  tags through `contract.card`, and the new card is not tagged; the top-level
  overlap collector records `shopButton` as one rect and does not descend into
  it, so the ring changes nothing it measures. The card's two stood-down
  captions are `OWNED` and `UNAVAILABLE`, both already in
  `Fit.ZyntraDisabledCaptions`. If the matrix does flag something in Studio,
  the fix is a caption string, not a rule.
* **`assets/shop/README.md`** — rewritten. **I overwrote a README Codex had
  just written there** while it was generating into that folder (the folder was
  empty when I started; eleven PNGs and a registry appeared during my run).
  Nothing else in the folder was touched and the prompts survive in
  `generation-registry.json`, but if that README carried an upload/asset-id
  mapping it needs writing back. My apologies — flagged rather than hidden.

### Also new

* `artifacts/trello-20260915/texture-requests.md` — the eleven textures, with
  dimensions, UV, subject, palette hex, purpose, repo path, import type and the
  exact config key each id goes into. **Codex has already generated all eleven**
  into `assets/shop/`; the ids are not in the code yet.
* `tools/tests/test_lobby_shop_display.py`
* `assets/shop/README.md`

---

## 3. Tests

```
LUAU_BIN=…/codex-luau-0.737/luau.exe python tools/tests/test_lobby_shop_display.py
  ok  333 checks: 6 stands, 6 plates, three tiers 300/380/420 px
python tools/tests/test_zyntra_store_compact.py
  ok  upgrade card 210/246/330px (phone/tablet/pointer), shop icon 52/64/76px
```

`test_lobby_shop_display.py` **runs both new scripts for real** — the whole
server module against a fake DataModel and the real `ZyntraConfig` source, and
the whole LocalScript against a fake PlayerGui and UIDevice — so it fails on a
typo as well as on a contract. It covers: one stand/pedestal/crate/plate/prompt
per catalogue item; the catalogue is every Pass and Product; a rebuild replaces
rather than stacks; every part anchored and only the pedestal solid; the whole
frontage inside z −70…−45, x ≤ 32.9, y 0.6…11; plate focus set/cleared with the
poll as its debounce and no rewrite while standing still; edge hysteresis; the
prompt's toggle and its range latch; no focus during a round; teardown clearing
the attribute; the card opening/closing/dismissing; the configured price then
the live one; `OWNED` taking BUY out of the stack and refusing to route; BUY
routing exactly once; the modal standing the card down; the three tiers and the
short-screen give-way; the bob and the breath, the reduced breath, and
everything restoring in a round.

Also run: `luau-compile --null` clean on all four touched scripts (including
`RoundUI`, untouched, as a control), and the rest of `tools/tests/`. Failing
there and **not mine**: `test_level3_run_in_exit`, `test_level3_hidden_chase`,
`test_level3_slide_aperture` (documented as failing at HEAD),
`test_level1_cable_current` (another agent's file), `test_push_repo_to_studio`
(needs Studio), `test_full_sync_contract` (the four unlisted new scripts).

**Not tested, because it cannot be offline:** anything about how this actually
looks, whether the card's bottom-centre placement collides with something the
lobby draws, whether the ProximityPrompt's frustum rule makes INSPECT awkward,
and whether a real `PromptProductPurchase` still opens from the world card.

---

## 4. Studio verification steps (for the resume)

1. **Create the two scripts** (paths and classes in §2), push, add manifest
   items, run the compile probe.
2. **Play**, then in the Server datamodel confirm
   `workspace.ServerLobby.ZyntraShopDisplay` exists with 6 `ShopStand_*` models
   and `ShopItemCount = 6`. The lobby is only real in play.
3. **Camera for the wide shot:** look along the tunnel from roughly
   `(LOBBY_CENTER + Vector3.new(6, 9, -96))` toward
   `(LOBBY_CENTER + Vector3.new(30, 6, -57))` — that is the spawn's own
   sightline onto the sign. **Close shot:** `(+22, 4, -57)` looking at
   `(+31, 4, -57)`. **Plate shot:** `(+24, 3, -66)` looking at `(+30, 3, -66)`.
   Screenshot all three; the sign's legibility from the first one is the whole
   "notice" half of the funnel.
4. **Walk onto a plate.** The card must appear bottom-centre for that player
   only, name the right item, state a price, and *not* prompt anything. Walk
   off: it closes. Press INSPECT: it opens; press again: it closes.
5. **Press BUY** and confirm Roblox's own purchase prompt opens with the right
   product (cancel it — do not spend). Then confirm the terminal's own Shop tab
   still buys, since it now runs through the same named function.
6. **Owned state:** with `ZyntraOwnsSupporter` true, the Supporter card must say
   `OWNED` and refuse to route.
7. **Mobile:** emulate a phone (the device emulator, or force UIDevice's touch
   override if it has one) and re-check the card at 956x440 and at the smallest
   handheld you can set; the BUY row must stay inside the card and above the
   thumbstick.
8. **Accessibility:** set `ReduceFlashing` true on the player and watch the sign
   and the HUD ring slow down rather than stop or strobe.
9. **UIRegression** fit matrix, for the HUD ring: the three section buttons must
   still measure the same rectangles.
10. **Textures:** paste Codex's ids into `SHOP_TEXTURES` at the top of
    `LobbyShopDisplay` and rebuild the lobby; each slot swaps a procedural
    placeholder for the art. Before that, the wall renders complete — the sign
    draws "SHOP" as text on its housing, the plates read "STEP TO INSPECT", the
    pedestals have a neon emitter ring, and **the crates wear the six existing
    live monetization icons** (`IconId` from `ZyntraConfig`) on the face that
    looks at the road.

## 5. Remaining limitations

* Nothing has been seen. Every visual claim here is arithmetic against
  `TunnelLobbyBuilder`'s own numbers, not a screenshot.
* The card's bottom-centre placement is the one layout choice I could not check
  against the lobby's other UI. If it fights the dispatch briefing or the round
  chip, the fix is one line in `cardArea`.
* The pedestal nameplate is small (a 2.2-stud face). It may need to move up onto
  the crate or a plaque after the first screenshot.
* One rib arch at z = −52 passes in front of the back panel. That reads as
  industrial structure, but it is a deliberate acceptance, not an oversight.
* `assetUrl` accepts a bare id or an `rbxassetid://` url and ignores anything
  else, so a malformed id leaves the placeholder rather than a broken surface —
  but it will do that *silently*. If a texture does not appear, check the table
  before checking the geometry.
* Crate art is applied to four vertical faces; the top and bottom keep the shell
  colour and the neon `SelectionBox` edge. A lid texture was not requested.

## 6. Observations for the owner's proposal — NOT implemented

Input only, for the #83/#84/#85/#89 proposal Codex owns. I built nothing here.

* **The wall has room for exactly two more stands** (z −45.8 … −44.75 is the
  kiosk, so a seventh and eighth item would mean re-spacing the row from 3.7 to
  about 2.9 studs, which is tight for the 3.4-stud plates). If the owner wants a
  Speed Boost Potion (#85) and a Daily Rewards pedestal (#89) out here, the
  honest options are: re-space to 8 at 2.8 studs, or extend the frontage to the
  left wall's matching stretch (z −70 … −47, x = −32.9) as a second bay. Worth
  deciding **before** any new product exists, because it changes the geometry
  constants, not the code.
* **A token-priced pedestal would need a different card.** All six existing
  items are Robux; Entity Shield (`ProtectionItem`, 5 tokens) is the only
  token-priced thing in the game and it lives on the Upgrades tab, bought
  through `ProtectionClient`, not MarketplaceService. The bridge already
  supports it (`kind == "TokenItem"` is one of `requestPurchase`'s branches) —
  what is missing is a token balance on the card, and **tokens are not published
  as a player attribute** the way credits and pass ownership are. Adding one
  client-local attribute in ZyntraStore (next to `ZyntraReentryCredits`) is the
  small, honest way to make any token-priced pedestal possible later.
* **The shop wall is a better home for a daily/streak reward than a HUD popup.**
  A seventh pedestal whose crate is *closed* until the reward is claimable, and
  whose plate says `COLLECT` instead of `INSPECT`, would reuse this entire
  mechanism — focus attribute, card, prompt, fit tiers — for the price of one
  extra branch. It also keeps retention UI out of the horror levels, which is
  where a popup would otherwise end up.
* **The funnel has a measurable gap.** Nothing in the lobby tells a player the
  shop exists before they walk past it. The First Entry Guide (card 70) already
  draws a pathfinding beam to Level 1 for a brand-new profile and ends on pad
  arrival; a second, *shorter* beam to the shop wall would be the cheapest
  "notice" step there is — but it competes with the guide's one job, so it is an
  owner decision, not a developer one.
