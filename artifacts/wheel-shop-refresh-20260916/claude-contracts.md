# Wheel / Shop / Rewards / Friend Boost refresh — contracts (2026-09-16 evening, Claude-only)

Baseline: git `86c675d` (main, local). Studio == repo at 20:20 UTC (pull --audit 143/143, parity
PARITY OK). The previous follow-up (#103/#104/#105: wheel modal, standalone Daily Rewards,
hologram shop v3) is implemented in Studio and the repo but NOT yet published; this round stacks on
it and the owner publishes once at the end. Owner brief: `CLAUDE-PROMPT.md` + `REWARDS-ASSETS.md`
in this folder. Codex delivered images only.

Nothing in this round touches: RoundUI, UIDevice, UIRegression, the Level files, ZyntraStore
(the terminal UI and its rail stay as they are; its `ZyntraShopPrompt` binding simply finds no
prompt any more), the round loop, prices, product ids, DataStore names, the historical CSV import.

## Assets (uploaded and verified loadable in Studio — see claude-status.md)

| Use | rbxassetid | Local file |
|---|---|---|
| Wheel disc texture (THE DISC, not the rail icon; transparent, no pointer baked in) | `86770264881525` | assets/shop/lucky-wheel-disc-v2.png |
| Daily Rewards token card icon | `93116899475472` | assets/shop/rewards-token-v1.png |
| Daily Rewards speed potion card icon | `120211340805188` | assets/shop/rewards-speed-potion-v1.png |
| Daily Rewards entity shield card icon | `126728249949579` | assets/shop/rewards-entity-shield-v1.png |
| Daily Rewards header gift | `117126194981100` | assets/shop/rewards-gift-v1.png |

ImageLabels: `ScaleType = Fit`, never stretch or crop; the PNGs carry their own air around the
motif, so size the label for the visual, not the file. No text or cooldowns are baked in.

Wheel texture orientation, verified by eye on the 1254x1254 PNG (Claude, 20:45 UTC): five EQUAL
72-degree fields, the gold single-token field is centred at 12 o'clock (its edges run from about
-35 to +35 degrees), then clockwise: orange three tokens, blue single potion, purple two potions,
green shield. So field `i` (0..4, order Token1, Token3, Potion1, Potion2, Shield1) is centred at
`72 * i` degrees clockwise from the top and covers `[72i - 36, 72i + 36)`. The texture already has a
gold rim with lamps and a gold hub disc (about 0.12 of the diameter).

## Owners and files (no file has two owners)

| Agent | Files |
|---|---|
| A-WHEEL | `StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua`, `tools/tests/test_lucky_wheel_client.py` |
| A-DAILY | `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua`, `StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua`, `tools/tests/test_daily_rewards_page.py`, `tools/tests/test_daily_rewards_client.py` |
| A-SHOP | `ServerScriptService/LobbyShopDisplay.ModuleScript.lua`, `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua`, `ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua` (kiosk removal ONLY), `tools/tests/test_lobby_shop_display.py` (+ keep `test_lobby_palette.py` green) |
| A-FRIEND | NEW `ServerScriptService/FriendBoost.ModuleScript.lua`, NEW `StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua`, `ServerScriptService/GameManager.Script.lua` (call sites only), `ServerScriptService/ZyntraMonetization.Script.lua` (profile field + payout only), `ReplicatedStorage/ZyntraConfig.ModuleScript.lua` (one new table), NEW `tools/tests/test_friend_boost.py` |

Repo files are the mirror; Claude pushes them to Studio (`record_pending_push` + `push_repo_to_studio
--file`) and installs the two NEW scripts with `tools/install_new_scripts.py`. Agents never touch
Studio, the manifest or git.

## 1. Lucky Wheel (A-WHEEL) — full-screen takeover, textured disc, SPIN in the hub

Keep: ScreenGui `LuckyWheelGui` (DisplayOrder 118, ResetOnSpawn false), opener
`PlayerScripts.OpenLuckyWheel`, attribute `LuckyWheelOpen`, Studio probe
`UIRegressionLuckyWheelProbe`, the profile subscription, `SpinDailyWheel` request with one in
flight + 6 s recovery, `WheelLast {Day, Key, Serial}` semantics (same-day unchanged Serial = show
landed without animating; first profile of the session is a seed, never a trigger), deterministic
jitter from Serial, `ReduceFlashing` = one turn 1.4 s Sine, Escape / ButtonB / InRound / RoundActive /
QueueModalOpen close it, `UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())` on open
and after close, refuse to open when blocked (`blockedFromOpening`).

Drop: the panel, eyebrow "ZYNTRA // DAILY SUPPLY", title, legend, banner, note line, status line,
scrolling body, footer SPIN/SKIP buttons, the 180-arm disc. There is NO rectangular container.

Build (all offsets from `UIDevice.Layout()`; `Safe` for the X, the full `Display`/viewport for the
disc — the disc is centred on the whole screen):
- `WheelShade`: full-screen Frame, black, `BackgroundTransparency 0.35` (discreet dimming), Active
  so clicks do not fall through. Everything below is its child.
- `WheelHolder`: square Frame, AnchorPoint .5,.5 at the screen centre, side =
  `floor(min(width, height) * 0.86)` clamped to `[220, 640]` (on 749x310 that is 266; on 390x844
  335; on 1280x720 619). Transparent.
- `WheelDisc`: ImageLabel `rbxassetid://86770264881525`, ScaleType Fit, Size 1,1 scale, AnchorPoint
  .5,.5, Position .5,.5, `Rotation` is THE animated property. Its children rotate with it:
  - `FieldLabel<i>` (i = 1..5 in config order): TextLabel "1 TOKEN" / "3 TOKENS" / "1 SPEED POTION" /
    "2 SPEED POTIONS" / "1 ENTITY SHIELD" (uppercase of a short label; A-WHEEL may shorten to
    "1 POTION" / "2 POTIONS" / "1 SHIELD" when side < 300), AnchorPoint .5,.5, centred at polar
    (radius 0.80 * R, angle 72 * (i-1)) in disc space, i.e. Position =
    `UDim2.fromScale(0.5 + 0.80 * 0.5 * sin(a), 0.5 - 0.80 * 0.5 * cos(a))`, Size
    `UDim2.fromScale(0.34, 0.075)`, `Rotation = 72 * (i-1)` so the text reads "upright" for the
    field at 12 o'clock and turns with the disc. GothamBlack, TextScaled off, TextSize
    `max(11, floor(side * 0.040))`, white with a dark UIStroke (thickness 1.5, transparency 0.2) so it
    reads over the coloured field and the rim lamps. A `UIStroke`, not a background pill.
  - `FieldOdds<i>`: "45%" / "20%" / "20%" / "5%" / "10%" (`oddsText` of the server weights — the
    weights are still the odds; equal fields do NOT change them), at polar (0.36 * R, same angle),
    Size scale (0.22, 0.06), TextSize `max(11, floor(side * 0.034))`, gold `Color3.fromRGB(255,203,79)`,
    same UIStroke. Discreet, no extra panel.
- `WheelPointer`: fixed, NOT a child of the disc: a downward-pointing triangle at 12 o'clock
  straddling the rim, drawn as an ImageLabel with a rotated square is NOT acceptable (the brief
  says the pointer never rotates and must stay crisp) — use a Frame `Rotation = 45` with UICorner
  for a diamond, or a TextLabel "▼" GothamBlack: size `max(18, floor(side * 0.09))`, centred at
  (0.5, 0.0) of the holder, gold with a dark stroke, ZIndex above the disc. Its own Rotation never
  changes.
- `HubButton`: TextButton, circular (UICorner 1,0), AnchorPoint .5,.5 at (0.5, 0.5) of the holder,
  diameter `max(56, floor(side * 0.26))` (so >= 44 px on every device), gold fill
  `Color3.fromRGB(255,203,79)` with a darker gold UIStroke, ZIndex above the disc, NOT a child of
  the disc (it never rotates). Text states (GothamBlack, TextScaled off, TextSize
  `max(12, floor(diameter * 0.30))` for the one-word state, `max(11, floor(diameter*0.19))` for the
  two-line states):
  - ready: "SPIN"
  - request in flight / spinning: "SPINNING" (button disabled via `UIDevice.SetEnabled`)
  - landed this session (first 3.5 s after landing): the prize short label, e.g. "1 TOKEN" /
    "3 TOKENS" / "1 POTION" / "2 POTIONS" / "1 SHIELD" (two lines allowed), then
  - spun today: "SPUN\nHH:MM:SS" — the countdown from `SecondsToReset` re-anchored on every push,
    ticking once a second while open (existing `updateNote` logic moves here), disabled.
  - no answer (6 s recovery): "RETRY" enabled, and re-read the profile exactly as today.
  Skipping: a tap on the hub while spinning SKIPS (sets the final rotation) — that replaces the
  SKIP button. Keep the `spinning` / `activeTween` / `finishSpin` guard so a skip can never finish a
  spin twice or double-pay (the server pays exactly once per SpinDailyWheel; the client only
  animates).
- `CloseButton`: TextButton "X", GothamBlack, square `max(48, tap)` x same, top-right of
  `layout.Safe` with an 8 px margin, dark fill, gold stroke, never rotates, works on desktop
  (mouse), touch and gamepad (ButtonB still closes). Also Escape.
- No other element. No legend: the odds live inside the fields.

Rotation math (unchanged sign convention, `GuiObject.Rotation` clockwise-positive, the pointer sees
`(-Rotation) % 360`): for awarded field `i` (0-based), `start = 72 * i - 36`, `width = 72`,
`target = -(start + jitterFor(serial, 72))` with jitter in `[6, 66]` (so at least 6 degrees from either
edge), `spinGoal = current - (current % 360) + target + 360 * turns`. `landedRotation` for the
"already spun" seed uses the same formula without the turns. The five sectors come from
`Config.DailyRewards.Wheel` order with EQUAL width; weights are used only for the odds text.

Takeover — "when the wheel is open, every other game UI is hidden":
- On open, BEFORE showing the shade: for every `ScreenGui` in `PlayerGui` other than
  `LuckyWheelGui`, remember `Enabled` in a table keyed by the instance and set `Enabled = false`.
  Also disable ScreenGuis added to PlayerGui while open (`PlayerGui.ChildAdded` while open → record
  and disable; a ResetOnSpawn clone counts). CoreGui (topbar, chat) is untouched.
- On close (any path, including InRound / respawn): restore `Enabled = true` ONLY for a remembered
  gui that still exists AND is still `Enabled == false` (something that re-enabled itself while
  hidden is left alone), then clear the table. `player.CharacterAdded` while open → close first.
- Attribute `LuckyWheelOpen` true while open (UIDevice's modal list already knows it), so the
  terminal, the rewards modal, the shop card and the queue modal stay refused/hidden for the whole
  time, and `UIDevice.SuppressTouchMovement(true)` keeps the thumbstick down (it is a CoreGui
  thing, so it is not in PlayerGui; SuppressTouchMovement is what hides it, as today).

Gamepad: the hub is the selected object on open (`GuiService.SelectedObject`), ButtonB closes.
Touch targets: hub >= 56, X >= 48. Text >= 11 px everywhere. No keyboard glyphs.

Tests (`test_lucky_wheel_client.py`, keep the harness and rewrite the checks): disc is an
ImageLabel with the id; five field labels + five odds labels with the right texts and rotations
`72(i-1)`; pointer and hub never rotate and are not disc children; hub diameter >= 56 and X >= 48 on
every stated viewport (1280x720, 390x844, 844x390, 705x338, 749x310, 1024x768); disc fits the
viewport (side <= min(w,h)); landing lands inside the awarded field for every one of the five keys
and for several serials (compute `(-Rotation) % 360` and check `[72i-36, 72i+36)` with the 6-degree
margin); a same-day unchanged Serial does not animate; skip via the hub finishes once; the takeover
disables every other ScreenGui on open and restores exactly the ones it disabled, leaves alone a
gui that re-enabled itself, and handles a gui added while open; CharacterAdded closes and restores;
the countdown text shape; ReduceFlashing one turn; no text below 11 px; no "SUPPLY" / "ZYNTRA"
strings drawn.

## 2. Shop along the whole wall (A-SHOP)

Measured in the running place (Server datamodel, 20:35 UTC). The builder's `center` is
`(0, 30, -760)` absolute (plates at absolute x 27.78 = PLATE_X; FLOOR_Y 0.65 = ledge top 30.65;
Level 4 doorway at absolute z -760 = relative 0). All numbers below are RELATIVE to center unless
marked abs. `faceCF(x, y, z)` in LobbyShopDisplay already adds `AREA_Z` to z — A-SHOP replaces
`AREA_Z`/`AREA_HALF` with the new span, so read the helper before reusing it.

- Right tunnel wall inner face: x = 32.9 (LowerTunnelWall centre x 34.0, 2.2 thick).
- RaisedServiceLedge: x 16.8 .. 33.2, top y = 0.65, z -140 .. +140 (abs -900 .. -620). Road edge
  x 22.8.
- Level 2 gate (abs z -840): door posts at abs z -849.8 and -830.2 (1.5 thick), header at y 15
  (abs 45), threshold 19.6 wide. The post edge facing the shop wall is at abs z -829.45 =
  relative **-69.45**.
- Level 4 gate (abs z -760, sealed "COMING SOON"): posts at abs z -769.8 and -750.2. The post edge
  facing the shop wall is at abs z -770.55 = relative **-10.55**.
- Usable wall between the two gates: relative z **-69.45 .. -10.55** (58.9 studs). Keep the boxes
  and plates at least 3.5 studs clear of each post so the gate openings and the ledge in front of
  them stay walkable: box centres from z **-66.0** to **-14.0**.
- Shell envelope (unchanged from the #105 contract): every corner must satisfy
  `sqrt(x^2 + (y - 1)^2) <= 33.70`, and `<= 33.05` for anything whose z range crosses the rib band
  `-52.36 .. -51.64`. The curved DoorClearanceShell slabs between the gates follow the same circle.
- Existing things that go: `ZyntraSupplyKiosk` (abs c (27,36,-795), 13.3x12.6x20 — the kiosk with
  its counter, canopy, fascia "ZYNTRA // SUPPLY", canisters, telemetry bars, ShopAccessTerminal
  "OPEN SHOP / PRESS E", `ZyntraShopPrompt`, shopkeeper platform and lights, and the
  `ZyntraShopkeeper` character), the shop deck, alcove backdrop, pilasters, overhead SHOP sign and
  its trims/glow, header markers, nameplates, projector discs and beams, the two kiosk bays, the
  rewards plinth + `DailyRewardsPlaque` + its prompt. Nothing else in the concourse (arrival gantry,
  crossing stripes, benches, donation leaderboard, party button, signal console) moves.

Build (LobbyShopDisplay v4, model name `ZyntraShopDisplay` unchanged, attribute
`ShopDisplayVersion = 4`, `Placement = "Right wall between the Level 2 and Level 4 gates"`):
- 8 products in `DISPLAY_ORDER`: the 6 Robux items, then SpeedPotion, then RouteMarker (the two
  token items are ordinary wall boxes now). Centres `z_i = -66 + 52 / 7 * i`, i = 0..7 (spacing
  7.43; boxes 3.4 wide leave about 4.0 studs of air; the old row had 0.15).
- `ShopHologramBox` per product: cube **3.4** (>= 3.2 required; the old box was 3.0), centre
  x **30.2** (rear face 31.9), centre y **7.0** (bottom 5.3 = 4.65 above the ledge top: a player
  walks under it; top 8.7 → r = sqrt(31.9^2 + 7.7^2) = 32.82 <= 33.05). `Material.ForceField`,
  `Transparency 0.35`, accent colour, `CanCollide = false`, `CanQuery = false`, `CanTouch = false`,
  `Anchored = true`, `SelectionBox` neon edge, `PointLight`, attributes `ShopItemKey`,
  `ShopBobOrigin` (the CFrame), `ShopBobPhase = i * (2π / 8)`, `ShopTextureSlot`. **Product art on
  all six faces**: one Decal per face (Front, Back, Left, Right, Top, Bottom) with the same product
  texture id from `SHOP_TEXTURES` / `IconId` (the `addDecal` helper takes a face). Never a blank
  face: the existing fallback chain applies per face.
- `ShopPressurePlate` per product, INVISIBLE exactly as today (Transparency 1, CanQuery/CanCollide/
  CanTouch false), centre x 27.78, y = 0.65 + 0.06, same z_i, size 3.4 along the wall (z) x 3.2
  (x). `PLATE_HALF_X = 1.6`, `PLATE_HALF_Z = 1.7`; the focus loop and `PLATE_HYSTERESIS = 0.6` stay.
  With 7.43 spacing two plates are >= 4.0 studs apart, so no accidental product switching.
- No deck, no backdrop, no sign, no nameplates, no projectors, no plaque, no prompt of any kind. The
  model attribute `FrontmostX` = 27.78 - 1.6.
- `TunnelLobbyBuilder`: delete the `addSupplyKiosk(concourse, center)` call and the now-unused
  `addSupplyKiosk`, `addGameplayShopkeeper` and any helper used only by them; keep the
  `LobbyShopDisplay` task.spawn exactly as it is. Do not touch anything else in that file.
- Server per-frame work: none. The bob is client-side.

Shop Display Client:
- Bob: continuous, calm: `y = origin + 0.35 * sin(t * 2π / 3.4 + phase)` with the box's
  `ShopBobPhase`, RenderStepped or Heartbeat on the client only, stands down in rounds and under
  `ReduceFlashing`/`ReduceCameraShake` exactly as today (`motionAllowed`). No turning.
- Card: eyebrow/title says "SHOP" (new `ShopTitle` label, GothamBlack) — the ONLY place the word
  SHOP appears; kind tags become "PERMANENT PASS" / "TOKEN ITEM" / "ROBUX PRODUCT" (no "SUPPLY"
  anywhere, no "ZYNTRA //"). BUY stays the only purchase path; CLOSE dismisses until the focus
  changes; stepping off clears; the card refuses while `UIDevice.ScreenOwningModalOpen()` (already
  there). Touch targets >= 44 px.
- Grep the three files for "SUPPLY", "Supply", "ZYNTRA //", "kiosk", "plaque", "Rewards" and remove
  every shop-presentation occurrence.

Tests (`test_lobby_shop_display.py`): 8 boxes at the stated centres, every corner inside the
envelope, every box >= 3.4 clear of both gate post edges (-69.45 / -10.55), plates 4.0+ apart,
six decals per box with the product id, no part named Deck/Backdrop/Sign/NamePlate/Projector/
Plinth/Plaque/Prompt, no ProximityPrompt anywhere in the model, no "SUPPLY"/"ZYNTRA" text, the
bob phases distinct, the client bob formula (offline, fake RunService) and the kind tags.
`test_lobby_palette.py` must stay green (it reads TunnelLobbyBuilder).

## 3. Daily Rewards (A-DAILY) — the inviting version

Keep: ScreenGui `DailyRewardsGui` (117), opener `PlayerScripts.OpenDailyRewards`, attribute
`DailyRewardsOpen`, probe `UIRegressionDailyRewardsProbe`, the `mount(page, ctx)` contract, ONE mount,
`ClaimPlaytimeReward {Minutes}` with one in flight + 6 s recovery, the three milestones (5 → 1
token, 15 → 1 Speed Potion, 35 → 1 Entity Shield) from `Config.DailyRewards.Milestones`, all
persistence, modal exclusion, close paths. NO seven-day streak, no new rewards, no economy change.

Layout (the client owns the shell, the page owns the content; both re-lay on `registerLayoutHook`):
- Shell: `RewardsHeader` bar, warm gradient (UIGradient orange `Color3.fromRGB(255,170,60)` →
  `Color3.fromRGB(255,120,40)`), height 64 (56 on compact touch): `HeaderGift` ImageLabel
  `rbxassetid://117126194981100` Fit, square = header height - 8, left; `HeaderTitle` "DAILY
  REWARDS" GothamBlack white with a dark UIStroke, TextSize 26 (22 compact); `CloseButton` "X"
  square `max(48, tap)` at the right, red-brown fill `Color3.fromRGB(190,60,50)`, white X, never
  smaller. Below the header a `CountdownStrip` (dark, 28-32 tall): "RESETS IN HH:MM:SS  ·  00:00
  UTC" from `SecondsToReset` (the existing clock code), plus `PlayStrip` "ACTIVE PLAY TODAY M:SS"
  with the existing progress track underneath. The panel keeps rounded corners; no eyebrow
  "ZYNTRA // DAILY SUPPLY" anywhere.
- Content: three `Milestone<minutes>` cards (names unchanged) as BIG colourful cards:
  token card gradient gold `(255,205,60) → (255,150,30)`, potion card cyan `(80,220,255) →
  (40,120,220)`, shield card purple/green `(150,90,230) → (60,200,140)`, each with UICorner 12,
  UIStroke 2 px (white 0.6 transparency), and inside, top to bottom: `Threshold` "5 MIN" /
  "15 MIN" / "35 MIN" (GothamBlack, white + dark stroke), `RewardIcon` ImageLabel (token
  `93116899475472`, potion `120211340805188`, shield `126728249949579`, Fit, the dominant element:
  >= 45% of the card height), `RewardName` ("1 Research Token" / "1 Speed Potion" / "1 Entity
  Shield" via the existing `rewardLabel`), and the state row: `ClaimButton` (existing name):
  - locked: disabled, dark, "M:SS TO GO" (existing text) — muted;
  - ready: enabled, bright green `Color3.fromRGB(70,200,90)` "CLAIM" GothamBlack, 44+ px tall,
    the most prominent thing on the card;
  - claimed: the button hidden, `ClaimedCheck` shown: a green circle with a white "✓" (TextLabel,
    GothamBlack) and "CLAIMED" under it.
  Tiers: pointer/tablet: the three cards in ONE ROW (card width = (contentWidth - 2 gaps) / 3,
  height ~ 260); compact touch portrait: one column, cards 150 tall with the icon on the left
  (a horizontal card: icon | threshold + name + state) inside the existing scroll; compact touch
  landscape: one row of three narrow cards (icon >= 56 px, CLAIM >= 44 px) — the body scrolls
  vertically if it must.
- Text >= 11 px, targets >= 44 px on touch, no keyboard glyphs, no odds/wheel content.

Tests: update both suites for the new structure (icon ids per card, header gift id, X >= 48,
CLAIM >= 44 on touch, claimed state shows the check and hides the button, locked state disabled,
three cards fit their tiers, no "SUPPLY"/"ZYNTRA //" text, still one mount, claim request shape
unchanged, 6 s recovery unchanged).

## 4. Friend Boost (A-FRIEND)

Interpretation (documented in the module header and in claude-status.md): the project has no
invite/referral tracking. It has parties (queue stations) and a per-round `participants` roster in
GameManager. A "friend you invited and play with" is therefore: a verified Roblox friend
(`Player:IsFriendsWith`, server-side, pcall'd, cached per pair) who was a participant of the SAME
round on the SAME server. Being friends and online elsewhere, or on this server but not in the
round, does not pay.

- `ZyntraConfig.FriendBoost = {PercentPerFriend = 10}` (additive: 1 friend +10%, 2 +20%, 3 +30%;
  no cap; the player never counts; a friend counts once).
- NEW `ServerScriptService/FriendBoost.ModuleScript.lua`:
  - `FriendBoost.Start()` (called once from GameManager boot): on every `PlayerAdded`/
    `PlayerRemoving` recompute, for every present player, the number of OTHER present players who
    are verified friends and publish the replicated Player attributes `FriendBoostFriends`
    (integer) and `FriendBoostPercent` (integer, count * PercentPerFriend). Pair lookups go through
    one cache keyed by `min(idA,idB) .. ":" .. max(idA,idB)`; only a DEFINITIVE answer (pcall ok) is
    cached; a failed/throttled lookup counts as "not a friend" for that pass and is retried on the
    next recompute (never trust anything from the client).
  - `FriendBoost.CountRoundFriends(player, roster: {Player}) -> number`: the payout count — other
    entries of the roster (deduplicated by UserId, self excluded) that are cached friends.
    `FriendBoost.PrimeRoster(roster)` resolves every pair of a launching party in the background so
    the answer is ready at completion; GameManager calls it where the party launches and again on a
    re-entry.
- GameManager: `zyntraLevelCompleted:Fire(participant, activeLevel, FriendBoost.CountRoundFriends(
  participant, participants))` in the win loop (line ~2711). One fire per escapee per round, as
  today.
- ZyntraMonetization: profile default `FriendBoostTenths = 0` (normalised to an integer 0..9 on
  load, included in the snapshot pushed to the client as `FriendBoostTenths`), and in the
  `levelCompletedEvent` handler:
  ```
  local base = Config.LevelCompletionTokens                -- 2
  local friends = math.max(0, math.floor(tonumber(friendCount) or 0))
  local tenths = data.FriendBoostTenths + base * friends * Config.FriendBoost.PercentPerFriend / 10
  -- base * friends * 10% expressed in tenths of a token: 2 tokens, 1 friend -> 2 tenths (0.2)
  local bonus = math.floor(tenths / 10)
  data.FriendBoostTenths = tenths % 10
  data.Tokens += base + bonus
  ```
  Message: "+2 Zyntra Research Tokens for completing the level." unchanged when friends == 0;
  with friends: "+N Zyntra Research Tokens for completing the level (Friend Boost +X%)." where N
  includes the bonus paid now. The remainder is server-side only; it is never shown as tokens.
  No other multiplier exists for completion tokens today (verified by grep), so nothing double
  counts; purchases, wheel, daily rewards, gifts and the historical import are untouched.
- NEW `StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua`: ScreenGui
  `FriendBoostGui` (DisplayOrder 60, ResetOnSpawn false) with one `FriendBoostChip` frame:
  "FRIEND BOOST +20%" (GothamBlack, gold) and "2 FRIENDS ON THIS SERVER" (Gotham, muted; "INVITE
  FRIENDS TO EARN +10% PER FRIEND" when 0), plus `InviteButton` "INVITE FRIENDS" (>= 44 px on touch)
  that calls `SocialService:PromptGameInvite(player)` after a pcall'd `CanSendGameInviteAsync`
  (hidden when it answers false or throws). Reads only the two Player attributes. Placement via
  `UIDevice.TopRightPanel(width, height)` (it already avoids the objective column) with the width
  260 / 220 compact. Visible only in the lobby (`InRound ~= true`), never while
  `UIDevice.ScreenOwningModalOpen()` (subscribe with `UIDevice.OnScreenOwningModalChanged`), and
  the wheel takeover disables the gui anyway. Nothing is granted client-side; nothing is sent to the
  server by this script. Register the chip with `UIDevice.RegisterControlRect("FriendBoost", chip)`
  so touch controls dodge it.
- `tools/tests/test_friend_boost.py`: the module under a fake DataModel (fake Players with a
  scripted `IsFriendsWith` that can throw): 0/1/3 friends, self excluded, duplicates once, join/
  leave republish, a throwing lookup counts 0 now and resolves later, roster count ignores a friend
  who is on the server but not in the roster; the payout arithmetic extracted from
  ZyntraMonetization by string markers (the same pattern as `test_token_grants.py`): base 2 with
  0/1/2/3/5 friends across several completions carries tenths correctly (1 friend: 0.2 per clear →
  a whole token on the 5th clear; 5 friends: +1 every clear), a replayed completion is just another
  completion (the server never fires twice for one clear — that guard is GameManager's, cover it
  by reading the loop); the client chip text for 0/1/2 friends and the invite gating.

## Reporting

`artifacts/wheel-shop-refresh-20260916/agent-<id>-report.md`: files, what was verified offline
and how (check counts), what needs Studio, decisions, open questions. Every touched .lua must
compile (`luau-compile.exe --binary`). Python + real luau (`LUAU_BIN=C:/Users/mikke/AppData/Local/
Temp/codex-luau-0.737/luau.exe`). Fakes: Color3 has no arithmetic; `GuiObject.Rotation` is a plain
number; ImageLabel needs `Image`, `ScaleType`, `ImageColor3`, `IsLoaded` in the fake.
