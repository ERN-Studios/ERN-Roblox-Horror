# Follow-up contracts — Trello #103 / #104 / #105 (2026-09-16, Claude-only batch)

Baseline: git `2c60cf3` = published v1920, Studio == HEAD (141 scripts, 0 drift, Edit mode).
Server side (ZyntraMonetization: `SpinDailyWheel`, `ClaimPlaytimeReward`, `Daily.*` payload,
`SecondsToReset`, `WheelLast {Day, Key, Serial}`) is UNCHANGED by this batch. Nothing here
touches ZyntraMonetization, ZyntraConfig, GameManager, RoundUI or any Level file.

## The three cards, as built

| Card | What ships | Owner |
|---|---|---|
| #103 | `StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua` (NEW): a real spinning wheel modal, opened by its own rail button | A-WHEEL |
| #104 | `StarterPlayerScripts/Daily Rewards Client.LocalScript.lua` (NEW): a standalone Daily Rewards modal hosting the existing page module (milestones only), opened by its own rail button; the terminal's Rewards tab is REMOVED | A-DAILY (client + page module), A-RAIL (terminal) |
| #105 | LobbyShopDisplay + Shop Display Client: floating hologram product boxes, INVISIBLE pressure plates that auto-open the product card, no INSPECT prompts, explicit BUY | A-HOLO |
| rail | ZyntraStore's left rail grows from 3 to 5 square buttons; UIDevice modal list; UIRegression rows | A-RAIL |

## Names (fixed — do not invent alternatives)

| Thing | Name | Created by |
|---|---|---|
| Open the wheel | `PlayerScripts.OpenLuckyWheel` (BindableEvent) | whoever finds it missing (create-if-absent on both sides, pattern of `RoundExitPrompt`) |
| Open daily rewards | `PlayerScripts.OpenDailyRewards` (BindableEvent) | same |
| Wheel ScreenGui | `LuckyWheelGui`, DisplayOrder 118, `ResetOnSpawn = false` | A-WHEEL |
| Rewards ScreenGui | `DailyRewardsGui`, DisplayOrder 117 | A-DAILY |
| Modal attributes (client-local, on LocalPlayer) | `LuckyWheelOpen`, `DailyRewardsOpen` (true while drawn, nil otherwise) | the owning client |
| UIDevice modal list | `SCREEN_OWNING_MODALS` gains `"LuckyWheelOpen", "DailyRewardsOpen"` | A-RAIL |
| Rail buttons | `ZyntraShopButton`, `ZyntraOpenButton`, `ZyntraRewardsButton` (NEW), `ZyntraWheelButton` (NEW), `ZyntraMusicButton` — top to bottom in that order | A-RAIL |
| Rail icons | `SECTION_IMAGES.Rewards = "rbxassetid://85423575361057"`, `SECTION_IMAGES.Wheel = "rbxassetid://111918608092047"` (transparent 1254² PNGs, ScaleType Fit, same inset as the others); captions "Rewards", "Wheel" | A-RAIL |
| Kiosk plaque prompt | still `ZyntraShopPrompt` with attribute `ShopRewardsPrompt = true`; ZyntraStore now fires `OpenDailyRewards` for it instead of opening the terminal | A-RAIL (binding), A-HOLO (plaque copy) |
| Studio-only probes | `UIRegressionLuckyWheelProbe` / `UIRegressionDailyRewardsProbe` BindableFunctions parented to the ScreenGui, actions "open" / "close" / "state" (returns Visible) — only when `RunService:IsStudio()` | A-WHEEL / A-DAILY |

## Modal rules (both new clients)
- Lobby only: refuse to open when `player:GetAttribute("InRound") == true`, when
  `UIDevice.ScreenOwningModalOpen()` is already true (the terminal, the queue host modal,
  re-entry, the other new modal), or when `QueueModalOpen == true`.
- Close on: CLOSE button, Escape, gamepad ButtonB, `InRound` -> true, `RoundActive` -> true,
  `QueueModalOpen` -> true.
- While open: publish the attribute above, call
  `UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())` on open AND after close
  (exactly as ZyntraStore.setMainVisible does), size the panel against
  `UIDevice.Layout().ModalViewport` (never the HUD band), keep every touch target >= 44 px,
  text >= 11 px, no keyboard glyphs on touch (`UIDevice.SuppressesKeyboardGlyphs()`).
- Chrome from `ReplicatedStorage.UIStyle` (panel/button/title/body/readout/caption); the
  terminal's palette for the two accents (teal `Color3.fromRGB(68,221,196)`, gold
  `Color3.fromRGB(255,203,79)`).
- Profile: subscribe like `ReplicatedStorage/ProtectionClient.ModuleScript.lua` does
  (`Remotes.ZyntraGetProfile:InvokeServer()` once, `Remotes.ZyntraProfileChanged.OnClientEvent`
  after); never keep a second copy of reward state; never grant anything client-side.
- One request in flight per action (`SpinDailyWheel` / `ClaimPlaytimeReward {Minutes}`), 6 s
  no-answer recovery = re-enable + `ZyntraGetProfile` re-read, exactly like the page module.

## The wheel (A-WHEEL) — construction that is known to render
- Disc = a square Frame (AnchorPoint .5,.5) holding 180 "spoke" Frames: each
  `AnchorPoint = Vector2.new(0.5, 1)`, `Position = UDim2.fromScale(0.5, 0.5)`,
  `Size = UDim2.fromOffset(spokeWidth, radius)` with `spokeWidth = ceil(radius * 2π / 180) + 1`,
  `Rotation = index * 2`, colour of the sector that owns that 2° slice. Spoke tips form the rim;
  a Frame on top with `UICorner(1,0)`, transparent background and a thick `UIStroke` draws the
  rim; a small centre hub (UICorner 1,0). NO images for the disc.
- Sectors are PROPORTIONAL to the server weights (45/20/20/5/10 -> 162°/72°/72°/18°/36°), laid
  clockwise from 12 o'clock in `Config.DailyRewards.Wheel` order. A legend beside the disc (or
  under it on phones) lists swatch + label + "45%" for every prize, so the odds are visible
  even for the 18° sector; the four sectors >= 36° also carry a short label inside.
- Pointer: stationary at 12 o'clock, outside the disc.
- Rotation math: `GuiObject.Rotation` is clockwise-positive, so the pointer sees wheel angle
  `(-Rotation) mod 360`. For the awarded sector [start, end) choose
  `target = -(start + jitter)` with jitter in [4°, width - 4°] (deterministic from
  `WheelLast.Serial` so a replay lands identically), then tween `Rotation` from the current
  value to `current - (current mod 360) + target + 360 * 5` over 4.2 s with
  `Enum.EasingStyle.Quint, Out`. `ReduceFlashing == true` -> one turn over 1.4 s, Sine.
  SKIP sets the final rotation immediately. After landing: banner "YOU RECEIVED: <Label>".
- The server picks and records the prize (`SpinDailyWheel` -> profile push with a new
  `Daily.WheelLast.Serial`); the client only animates to it. A same-day push with an unchanged
  Serial shows the landed state without animating. `Daily.WheelDay == Daily.Today` -> button
  "SPUN TODAY" (disabled) + "Next spin in HH:MM:SS" from `SecondsToReset`.

## Daily Rewards (A-DAILY)
- `ZyntraDailyRewardsPage.ModuleScript.lua` keeps its milestones section and header (countdown,
  UTC note, active-play readout, progress track, three claim cards) and DROPS the wheel section
  entirely (the wheel now lives in #103). Its `mount(page, ctx)` API stays exactly as documented
  in `artifacts/trello-20260916/claude-contracts.md`.
- `Daily Rewards Client` builds the modal shell (title bar "DAILY REWARDS", CLOSE, status
  line) and mounts the page module into its content frame with a ctx that implements every
  contract field itself (its own `label/button/corner/outline` helpers may be local copies of
  ZyntraStore's; `action` fires `Remotes.ZyntraAction`; `registerLayoutHook` is called with a
  `fit` table shaped like the terminal's: `{Compact, Touch, ContentWidth, ContentHeight,
  TabHeight, TabMinWidth, Tap}`; `contract.scroll/card` may be no-ops that record names).
  Mount ONCE at build time; `refresh()` on open; never a second mount.
- A-RAIL removes `Rewards` from the terminal (TERMINAL_PAGE_MODULES / tab list) and routes the
  kiosk plaque prompt to `OpenDailyRewards`. `Notes` stays a terminal tab.

## Hologram shop (A-HOLO)
- Every product (6 Robux items on the frontage + the 2 token items at the kiosk bays) becomes a
  FLOATING HOLOGRAM BOX: a translucent box (`Enum.Material.ForceField` or Glass, Transparency
  ~0.35, the product decal on the road-facing face and the accent colour on the others, a
  neon `SelectionBox` edge, a PointLight), roughly 1.5x the shipped crate size, hovering above a
  low projector base (a flat neon-ringed disc with a faint vertical beam part) instead of the
  pedestal column. The client keeps the bob/turn motion (existing attributes) and stands it
  down in rounds / under ReduceFlashing rules exactly as today.
- Alternate hover heights (upper/lower) so bigger boxes fit the 3.15-stud slot pitch; keep
  every corner inside the documented envelope (`r(x,y) = sqrt(x² + (y-1)²) <= 33.70`, and
  `<= 33.05` for anything crossing the rib band at z -52.36..-51.64); nothing crosses the walk
  lane (plates stop at x = 25.78 today; keep the road's 33-stud width untouched); the queue
  stations, gates and kiosk pad are untouched.
- Pressure plates: keep the zones (positions, sizes may grow to 3.4 x 3.2) but make them
  INVISIBLE: `Transparency = 1`, no decal, no neon edge part, no hint text, `CanQuery = false`,
  `CanCollide = false`. The focus loop (position-polled, hysteresis, latch) stays the trigger.
- REMOVE every `ProximityPrompt` named `ShopInspectPrompt` and the prompt latch code paths;
  the rewards plaque prompt (`ZyntraShopPrompt` + `ShopRewardsPrompt`) stays and its copy
  becomes "DAILY REWARDS" / "PLAY TO EARN" / "PRESS E" (no "ZYNTRA TERMINAL" line).
- Shop Display Client: the card opens automatically from `ZyntraShopFocus`, BUY is the only
  purchase path (unchanged bridge), CLOSE dismisses the current focus until the focus changes
  (no reopen loop while standing still), switching plates switches the card. Remove any
  "INSPECT" wording. The card may grow on pointer tiers; phone tier stays >= 44 px targets.

## Tests (all agents)
Python + real luau (`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`,
`luau-compile.exe` beside it). Whole-LocalScript-under-fake-DataModel pattern:
`tools/tests/test_round_exit_hold.py`, `test_equipment_hud.py`; page/module pattern:
`test_daily_rewards_page.py`; server/geometry pattern: `test_lobby_shop_display.py`. Every
touched .lua must compile. Print check counts. Fakes: Color3 has no arithmetic; Vector3/CFrame
do; `GuiObject.Rotation` is a plain number property.

## Reporting
`artifacts/trello-20260916-followup/agent-<id>-report.md`: files, verified offline and how,
NOT verified (needs Studio), decisions, open questions, Trello draft.
