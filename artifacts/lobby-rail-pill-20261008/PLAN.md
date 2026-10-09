# Token pill and Friend Boost over the rail windows: final plan

## 0. Verdict

**Build Plan B (dock), with three parts taken from Plan A and seven corrections.** I checked both plans against the working tree, which is v2797 plus the uncommitted rail diff (apply on top of it, not HEAD). The Shop L4 draft is byte-identical to the mirror.

**Why Plan A is rejected.** I confirmed its own numbers.
- When the pill sits at rest, it covers the Shop and Daily Close buttons on every phone (table in §6).
- Plan A's right clamp shrinks the windows. On a two-column iPhone 13 the Shop row drops to 136 × 262 / 1016 = **35.1 px**; 705x338 and 667x375 lose about as much.
- It also leaves a case open: if the pill is hidden, the chip can still sit on a Close.

**Plan B leaves every window exactly as shipped.** While a rail window is open, it moves the pill and chip into `InsetAreas.TopbarSafeInsets`, the 58 px topbar band. That band lies outside every window's gui (each window is CoreUISafeInsets), so nothing overlaps on any phone.

**Taken from Plan A:**
- the wheel exemption written inline (no new top-level local);
- the switch route design (shared by both plans);
- the predicate shape.

**Corrections, checked against the code:**
1. **PC dock threshold: 1052 is wrong, use 1120.** The rail clamp (`ui.fit` :1023-1026) can push a PC window's centre right by up to (80 − 12) / 2 = 34 px. That happens when the safe height is about 535 px or less, where the holder's left edge falls inside the 80 px clamp line. Worked example: at a 1060x474 PC window the Shop window spans x 218..910. Its Close is at x 844..901, y 10..66, and the resting pill at x 889..1042, y 18..70 covers 12 px of it. The bound is: right edge ≤ W/2 + 34 + 347, which must be ≤ W − 171 − 8, so W ≥ 1119.
2. **Use `Safe.Right - Safe.Left`, not `Safe.Width`.** The Shop harness Layout fake has no `Width` (:750-752), so `nil < number` throws there.
3. **The harness needs `InsetAreas` in three fixtures, not one.** Plan B only listed :750. The TenFoot case (:1992, window open) and both touch fixtures (:2473, :2541, window open) would also index nil.
4. **The chip can go in `RequiresTopmost`.** `InviteButton` is a child of `FriendBoostChip`, so `hit:FindFirstAncestor("FriendBoostChip")` passes. Plan B's "SHIELDED" concern does not apply.
5. **Plan A's fragment `ZyntraLobbyPillL4.TokenPill.AddTokens` would not be measured.** Scan does not go inside a drawn, non-layout-group frame, so it would read as VACUOUS. Use `ZyntraLobbyPillL4.TokenPill`.
6. **The chip must re-check visibility when the pill hides.** Today the pill's Visible signal only re-runs `applyLayout`, so the chip could sit on a Close for up to 0.5 s, until the poll runs.
7. **Plan A risk 7 does not apply.** Under a screen-owning modal on touch, UIDevice throws away a union that is only the chip, because `union.Right < display.Right` (UIDevice:1031-1044, 1086-1104).

**The 44 px floor already fails today and stays as it is.** The windows are below 44 px on iPhone 13, 705x338 and 667x375, and Dev is below on all four phones (§6). This plan does not change window geometry, so it neither causes nor fixes that. Reaching 44 px for 136-artboard-px rows needs a window at least 329 px tall, and only 844x390 has that.

## 1. DisplayOrders

| Gui | At rest | Lobby, any rail window open |
|---|---|---|
| ZyntraStore rail | 55 | 119 (unchanged) |
| **ZyntraLobbyPillL4** | 55 | **119** |
| **FriendBoostGui** | 60 | **119** |
| Shop 56, Dev 57, Daily 117, Wheel 118, re-entry 120 | unchanged | unchanged |

- At 119 they sit above every Dim and WheelShade shield and below re-entry.
- The three 119 guis never overlap each other: the rail is on the left, and the pill and chip are in the corner or the band.
- At rest, 55 and 60 keep "Shop Display Client" (65) above them, as today.

## 2. Predicates

**Pill:**
```
not bindFailed and not InRound and not QueueModalOpen and not ZyntraReentryOpen
```
- `not ui.open` and `not ScreenOwningModalOpen()` are dropped.
- The rail-clearance rule stays.
- When the pill is docked it also needs `band.Height >= 56`.

**Chip:**
```
inLobby() and not QueueModalOpen and not ZyntraReentryOpen and (not over or tokenPill() ~= nil)
```
- `over` is `ScreenOwningModalOpen()`. With the two guards in place, anything still open is a rail window.
- **Over a window, the chip only shows when the pill is drawn.** Otherwise it would sit on the window's Close.

**Docking rule:**
```
over and (IsTouch or IsTenFootInterface() or Safe.Right - Safe.Left < 1120)
```

## 3. Per-file edits, in order

### 3.1 `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`
1. **:1110-1111, comment.** Change it to: "Only the rail handlers and the lobby token pill's + (PlayerScripts.ZyntraRailSwitch, below) call this; ZyntraOpenTerminal, J and DevPhoneCommand still refuse over any modal."
2. **Insert after `switchFrom`'s `end` (:1125), before `-- Studio-only input seam` (:1127).** This keeps it inside the test's `kiosk_block` slice, and it adds no top-level local.
```lua
-- The lobby token pill's + ("Zyntra Shop L4", owner 2026-10-08) switches like a
-- rail press, through RAIL_WINDOWS above: one table. Synchronous, so the closed
-- window's flag is down when Invoke returns. A do-block: no new top-level local.
do
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ZyntraRailSwitch"
	bridge.OnInvoke = switchFrom
	bridge.Parent = player:WaitForChild("PlayerScripts")
end
```

### 3.2 `StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua`
Copy the finished file byte-identically to `artifacts/shop-ui-figma-20261005/roblox-draft/StarterPlayer/StarterPlayerScripts/`.

1. **:1365-1369, header comment.** Add that over a rail window (owner 2026-10-08) the pill stays up at 119. Where its corner would sit on the window (touch, TV, or a PC narrower than 1120), it docks at the right end of the topbar band and publishes `TokenPill.Docked`, which Friend Boost follows.
2. **:1371, after `local PILL_HEIGHT = 52 ...`** (inside the do-block):
```lua
	-- PC windows are centred, >= 693 px wide only at the 400 px floor (1760:1016), and the
	-- rail clamp can shift that centre 34 px right: the corner column (18 + 153 + 8 gap)
	-- clears them from a 1120 px safe width up. Narrower, the pill docks like on touch.
	local PC_DOCK_BELOW = 1120
```
3. **:1396.** `pillGui.IgnoreGuiInset = false` becomes:
```lua
		pillGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the topbar band is inside it (UIRegression TopBound); LocalPosition keeps the resting spot
```
4. **:1411-1416, the "+" handler:**
```lua
			ui.onPress(hit, function()
				-- Over another rail window: ZyntraStore's own switch closes it first;
				-- openShop still refuses over anything left, so two never stack.
				local switch = playerScripts:FindFirstChild("ZyntraRailSwitch")
				if switch and switch:IsA("BindableFunction") then pcall(switch.Invoke, switch, "ZyntraStoreOpen") end
				if not ui.openShop("Shop", "Tokens20") then ui.refreshPill() end
			end)
```
5. **:1421-1438, `ui.refreshPill`:**
```lua
	function ui.refreshPill()
		if not pill and not make() then return end
		-- Owner 2026-10-08: up over the rail's own windows too; a round, the queue
		-- host modal and re-entry still take it down.
		local visible = not ui.bindFailed and player:GetAttribute("InRound") ~= true
			and player:GetAttribute("QueueModalOpen") ~= true and player:GetAttribute("ZyntraReentryOpen") ~= true
		local over = UIDevice.ScreenOwningModalOpen() -- with the guards above: a rail window
		local docked = false
		if visible then
			local layout = UIDevice.Layout()
			local width = math.floor(PILL_HEIGHT * aspect)
			local right, top
			docked = over and (layout.IsTouch or GuiService:IsTenFootInterface()
				or layout.Safe.Right - layout.Safe.Left < PC_DOCK_BELOW)
			if docked then
				-- At rest the corner sits on the window's Close: the topbar band's right end.
				local band = layout.InsetAreas.TopbarSafeInsets
				right, top = band.Right - 8, band.Top + (band.Height - PILL_HEIGHT) / 2
				visible = band.Height >= PILL_HEIGHT + 4 -- a legacy 36 px bar: hidden over the window, as before
			else
				-- Only Right and Top: TopRightPanel's height is the room above the
				-- registered controls, and the Friend Boost chip is one of them.
				local panel = UIDevice.TopRightPanel(width, 1)
				right, top = panel.Right, panel.Top
			end
			pill.Size = UDim2.fromOffset(width, PILL_HEIGHT)
			pill.Position = UIDevice.LocalPosition(pillGui, right, top)
			visible = visible and right - width >= railRight() + 8
		end
		pill:SetAttribute("Docked", (visible and docked) or nil) -- Friend Boost follows it
		pill.Visible = visible
		pillGui.DisplayOrder = if visible and over then 119 else 55
	end
```
No new wiring is needed. `refreshPill` already re-runs on `OnScreenOwningModalChanged` (:1758), `UIDevice.Changed` (:1759-1762, which also fires on `TopbarSafeInsets` changes), `setOpen` (:993), InRound and Queue.

### 3.3 `StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua`
1. **:13-16 and :32-33, header.** Rewrite to say: over a rail window the chip stays up (owner 2026-10-08). It docks left of a docked pill, centred on it. The queue modal, re-entry and rounds still stand it down.
2. **:66,** after `gui.DisplayOrder = 60`:
   ```lua
   gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the pill gui's insets: an offset in one is the same in the other
   ```
3. **:115-117.** Add `local docked = false` next to `phone`, and change `local applyLayout` to `local applyLayout, refresh`.
4. **:126-131, in `tokenPill()` inside `if pill ~= followed`:**
```lua
		for _, property in ipairs({"Visible", "AbsolutePosition", "AbsoluteSize"}) do
			pill:GetPropertyChangedSignal(property):Connect(function() applyLayout(); refresh() end)
		end
		pill:GetAttributeChangedSignal("Docked"):Connect(function() applyLayout(); refresh() end)
```
5. **:148-150, the head of `applyLayout`:**
```lua
	local pill = tokenPill()
	docked = pill ~= nil and pill:GetAttribute("Docked") == true
	phone = UIDevice.Layout().IsTouch == true or docked -- docked: the compact line, on PC too
```
6. **:155,** add a branch before `if pill then` (which becomes `elseif pill then`). Fix the comment at :156-157 to "Both guis use DeviceSafeInsets".
```lua
	if pill and docked then
		-- In the topbar band, LEFT of the docked pill and centred on it (owner 2026-10-08).
		local origin = (pill.Parent :: any).AbsolutePosition
		x = pill.AbsolutePosition.X - origin.X - GAP - width
		y = pill.AbsolutePosition.Y - origin.Y + (pill.AbsoluteSize.Y - height) / 2
```
7. **:173:**
   ```lua
   boost.Position = UDim2.fromOffset(0, if docked then (height - LINE_HEIGHT) / 2 else 0)
   ```
8. **:244-252.** `local function refresh()` becomes:
```lua
refresh = function()
	local over = UIDevice.ScreenOwningModalOpen()
	local shown = inLobby() and player:GetAttribute("QueueModalOpen") ~= true
		and player:GetAttribute("ZyntraReentryOpen") ~= true
		and (not over or tokenPill() ~= nil) -- over a window only beside the pill, never on its Close
	chip.Visible = shown
	-- (UI_REGRESSION_20260923 comment kept)
	UIDevice.SetInteractive(invite, inviteAllowed and shown)
	gui.DisplayOrder = if shown and over then 119 else 60
end
```

### 3.4 `StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua`
- **:725,** with no new top-level local:
```lua
	if other == gui or not other:IsA("ScreenGui") or other.Name == "ZyntraStore"
		or other.Name == "ZyntraLobbyPillL4" or other.Name == "FriendBoostGui" then return end
```
- Update the comments at :5-10 and :715-718: three exemptions, and the owner date 2026-10-08.

### 3.5 `ReplicatedStorage/UIRegression.ModuleScript.lua`
Everything goes inside `Scenarios`; nothing is added at top level.
- **After `rail` (:1157-1158):**
```lua
	-- The token pill and Friend Boost chip stay up over the same windows (owner 2026-10-08).
	local overWindows = {"ZyntraLobbyPillL4.TokenPill", "FriendBoostGui.FriendBoostChip", table.unpack(rail)}
```
- **`store-modal` (:1389), `daily-modal` (:1404), `wheel-modal` (:1415):**
  - `Requires = {<window>, table.unpack(overWindows)}`
  - `RequiresTopmost = overWindows`
  - `RequiresActive = rail` stays as it is (the invite depends on `CanSendGameInviteAsync`).
  - Keep the pill out of `TouchTargets`: `touchTargetProblems` flags `Top < -1`, and the docked pill is at y −55.
- Because `wheel-modal` requires both guis, it also proves the takeover exemption.

## 4. The "+" switch route

Pill "+" → `PlayerScripts.ZyntraRailSwitch:Invoke("ZyntraStoreOpen")` → `switchFrom` (the one `RAIL_WINDOWS` table) → `ui.openShop("Shop", "Tokens20")`.

| Open window when "+" is pressed | What happens |
|---|---|
| Shop | Nothing closes; tab switch and scroll to Tokens20 (`openShop` passes because `ui.open`). |
| Daily | `ZyntraDailyUIOpen "close"`, then the shop opens. |
| Wheel, even mid-spin | `CloseLuckyWheel`: `finishSpin` and `handBack` re-enable ZyntraShopL4, then the shop opens. |
| Dev | `ZyntraDevUIOpen(false)`, then the shop opens. |
| Switch route missing or failed | `openShop` refuses over the modal (:1357). Two windows never stack. |

**INVITE FRIENDS** only calls `SocialService:PromptGameInvite`. That is a CoreGui prompt with no modal flag, so nothing stacks.

## 5. Unchanged
- Window fits for Shop, Daily, Dev and Wheel.
- PC 50% centring.
- Rounds (pill hidden by InRound, chip by `inLobby`).
- RoundUI.
- UIDevice.
- The Daily and Dev drafts and harnesses.

## 6. Touch geometry

Coordinates are in Layout space: y = 0 is the safe top, and the topbar band is y −58..0. The real-device band starts at about Safe.Left + 164 (measured on an iPhone 16 Pro Max). Tap sizes are for the 136-artboard-px rows; the 144-px header squares are in brackets.

| Device (safe area) | Rail edge | Shop window, tap | Daily, tap | Dev, tap | Resting pill vs Close (why it docks) | Docked pill ("+" 49x49) | Docked chip (104x44 tap) | Band room left of chip |
|---|---|---|---|---|---|---|---|---|
| 844x390 (844x332) | 64 / 126 | 575x332, **44.4** (47.1) | 547x332, **44.3** | 547x316, 42.3 | pill 683..836 x 8..60 covers the Shop Close (685..732 or 716..763, y 1..48) and the Daily Close | x 683..836, y −55..−3 | x 573..677, y −51..−7 | 409 |
| iPhone 13 (749x310) | 118 measured (60 with one column) | 537x310, 41.5 (43.9) | 511x310, 41.3 | 509x294, 39.4 | pill 588..741 covers the Close at 649..693, y 1..45 | 588..741 | 478..582 | 314 |
| 705x338 (705x280) | 118 | 485x280, 37.5 (39.7) | 461x280, 37.3 | 457x264, 35.3 | pill 544..697 covers the Close at 606..645 | 544..697 | 434..538 | 270 |
| 667x375 (667x317) | 60 / 118 | 549x317, 42.4 (44.9) / 529x305, 40.9 | 522x317, 42.3 | 521x301, 40.3 | pill 506..659 covers the Close at 584..629 / 605..648 | 506..659 | 396..500 | 232 |

- **Windows start at y 0 (Shop and Daily) or y 8 (Dev).** The docked pill ends at y −3, so nothing overlaps on any row.
- **The Wheel's X stays in the safe area.** It sits at x 526..574, y 14..62 (844); 472..520 (iPhone 13); 441..489 (705); 433..481 (667). The docked row clears it, and also the odds panel and title.
- **Other touch targets:** pill "+" 49x49, chip 104x44, rail 52-56, wheel X 48, hub at least 56.
- **PC, not docked:** at 1920 the Shop window ends at x 1396 against the pill at 1749. At 1366 it ends at 1029 against 1195. At 1280 it ends at 986 against 1109. Taps are 67.3, 53.5 and 53.5 px. Below 1120 the pill and chip dock.

## 7. Tests

### `tools/tests/test_zyntra_store_compact.py`
- **After :195.** Regex-read these two lines and check each number equals `RAISED`:
  - in Shop L4: `^\t\tpillGui\.DisplayOrder = if visible and over then (\d+) else 55$`
  - in Friend Boost: `^\tgui\.DisplayOrder = if shown and over then (\d+) else 60$`
- **New ROUTING_TESTS case before :840.** Get the bridge with `playerScripts:FindFirstChild('ZyntraRailSwitch')` and check:
  - it is a BindableFunction;
  - with `flags.DailyRewardsOpen`, `OnInvoke('ZyntraStoreOpen')` logs exactly `daily:close` and asks the shop nothing;
  - with `flags.ZyntraStoreOpen`, it logs nothing and the flag stays up;
  - with `flags.LuckyWheelOpen`, it logs `wheel:close`;
  - with `flags.DevPhoneOpen`, it logs `dev:false`.

### `tools/tests/test_friend_boost.py`
- **:712:** add `equal(ctx.Gui.ScreenInsets, Enum.ScreenInsets.DeviceSafeInsets, ...)`. The value stays 60 at rest.
- **:800-806:** that context has no pill. Queue and re-entry hide the chip and make the invite inert. The four rail flags also hide it, now because there is no pill. Update the messages.
- **New block with `startClient(PHONE, true, 1, true)`:**
  - each of the four rail flags keeps the chip Visible with the invite Active and DisplayOrder 119, and it is back to 60 on close;
  - with a rail flag up, `ctx.Pill.Visible = false` hides the chip in the same step, without a Heartbeat (this tests edit 3.3.4).
- **New docked block (POINTER, with pill), after `ctx.Pill:SetAttribute('Docked', true)`:**
  - the chip's right edge is the pill's left minus 6;
  - its vertical centre is the pill's;
  - it is 104x44 with the text "FRIENDS +N%";
  - `BoostLabel` sits at y 10;
  - clearing `Docked` restores the box under the pill.

### `artifacts/shop-ui-figma-20261005/roblox-draft/tests/zyntra_shop_l4_harness.luau`
- **Fixtures:**
  - :750: add `InsetAreas = {TopbarSafeInsets = {Left = 0, Top = 0, Right = 1280, Bottom = 36, Width = 1280, Height = 36}}`.
  - :2473 and :2541: add `InsetAreas = {TopbarSafeInsets = {Left = 0, Top = 0, Right = 844, Bottom = 58, Width = 844, Height = 58}}`.
- **:1894, inverted:** "the pill stays up over its own window": visible, `DisplayOrder == 119`, `Docked == nil` at PC 1280. After `Press("Close")` it is back at 55.
- **New block after 8b (:1950):**
  - 844x390 touch fixture with the window open: the pill is at `LocalPosition(nil, 836, 3)`, `Docked == true`, DisplayOrder 119.
  - A 36 px band hides the pill and clears `Docked`.
  - TenFoot with the 58 px band: docked.
  - PC `Safe.Right = 1100` with the 58 px band: docked. At 1280: at the corner.
  - `QueueModalOpen` or `ZyntraReentryOpen`: hidden, DisplayOrder 55.
- **"+" case:**
  - Add a fake `ZyntraRailSwitch` to `ctx.PlayerScripts` whose `OnInvoke` logs its argument and clears `DailyRewardsOpen`.
  - Set `DailyRewardsOpen`, then press "+": the log is `ZyntraStoreOpen`, and the Shop opens with `Page_Shop` visible.
  - Without the switch, with Daily open: refused, Root is hidden, and the pill stays visible.

### `tools/tests/test_lucky_wheel_client.py`, exemption block (:1300-1335)
- Add `addGui(ctx, 'ZyntraLobbyPillL4')` and `addGui(ctx, 'FriendBoostGui')`.
- Check both stay Enabled with no `@Enabled` watcher through open, close, respawn and reopen.

### Hygiene
- Run `luau-compile` on all changed Lua files.
- Use ASCII only and LF line endings (no CR).
- Check that `cmp` says the draft and mirror are identical.
- Run all suites in the integration.md list.

## 8. Residual risks and owner checks
1. **The window tap targets are already below 44 px.** On iPhone 13 they are 41.5, on 705x338 37.5, and on 667x375 40.9-42.4. Dev is 35.3-42.3 on all four phones. The owner needs to decide on a separate window-height change; this plan does not regress them.
2. **The topbar band is not verified in Studio.** Check rendering and taps there under `DeviceSafeInsets`, and `GetGuiObjectsAtPosition` at negative y. Use the Device Emulator at iPhone 13 and 705x338 with ForceTouchUI, and a PC window at 1100 px.
3. **Roblox's own topbar group can grow** (for example with chat or voice). The band shrinks and UIDevice re-lays out. On 667x375 there are 232 px before the chip slides under that CoreGui. The CoreGui draws on top and wins taps, which is a temporary cosmetic problem.
4. **Owner check: two token pills.** The Shop and Daily headers already draw their own token pill, so the lobby pill repeats it over them. This follows the literal decision.
5. **Narrow PC (under 1120) and console dock.** On PC the docked chip loses the "INVITE FRIENDS" text (line form). A legacy 36 px or absent band hides both over windows, as today.
6. **PC wheel, cosmetic.** On PCs about 1300-1600 wide with a safe height under about 735 px, the PC chip box can cover a few pixels at the top of the wheel's odds panel, which has no controls. Example: 1600x768.
7. **Brief lags.** Because signals are deferred, the chip can draw at its resting spot for one frame before it follows the docked pill.
8. **Gamepad.** The "+" and INVITE are selectable over windows. This is the same open item as the rail.
9. **Invite prompt.** If `PromptGameInvite` sets `GuiService.MenuIsOpen`, Daily closes underneath (:766-767). That is harmless; confirm in Studio.
10. **Ship as one batch.** Shop L4 and Friend Boost share the gui-origin assumption, so a mixed push puts the chip 58 px off. Drift-audit the Studio copies first. Run the compile probe before UIRegression, which is near the 200-local ceiling (nothing is added at top level). The UIRegression rows need the character inside the lobby box for the chip.
11. **Docs at commit time.** Add a dated CLAUDE.md note, coordinating with the session that is rewriting it. Update the QA step in `artifacts/shop-ui-figma-20261005/INTEGRATION-CONTRACT.md:624-625`.

## Files
- `G:/Roblox/MongoTV/StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`
- `G:/Roblox/MongoTV/StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua`, plus the draft `G:/Roblox/MongoTV/artifacts/shop-ui-figma-20261005/roblox-draft/StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua`
- `G:/Roblox/MongoTV/StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua`
- `G:/Roblox/MongoTV/StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua`
- `G:/Roblox/MongoTV/ReplicatedStorage/UIRegression.ModuleScript.lua`
- `G:/Roblox/MongoTV/tools/tests/test_zyntra_store_compact.py`
- `G:/Roblox/MongoTV/tools/tests/test_friend_boost.py`
- `G:/Roblox/MongoTV/tools/tests/test_lucky_wheel_client.py`
- `G:/Roblox/MongoTV/artifacts/shop-ui-figma-20261005/roblox-draft/tests/zyntra_shop_l4_harness.luau`