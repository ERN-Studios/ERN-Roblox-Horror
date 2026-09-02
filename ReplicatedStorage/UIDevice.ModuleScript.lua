--!strict
-- UIDevice - the one place that answers "what kind of screen is this?"
--
-- Before this module every HUD script made its own guess, and they disagreed.
-- Three different questions were being conflated, so this module keeps them
-- strictly apart:
--
--   1. FORM FACTOR  - is this a phone or tablet?  UIDevice.IsTouch()
--      This and only this decides whether a keyboard binding may appear in a
--      string. It never consults the last input type, so picking up a mouse on
--      a tablet cannot make "[R]" appear on a device with no R key.
--
--   2. LATEST INPUT - what did they touch last?   UIDevice.LastInput()
--      Only ever used to choose BETWEEN desktop and gamepad hints. On a touch
--      form factor it is irrelevant, because there is no hint to show.
--
--   3. LAYOUT       - where may I draw?           UIDevice.Layout()
--      Viewport, the top GUI inset, the device safe area, and the rectangles
--      the movement controls own. Nothing about layout depends on 1 or 2
--      except which control zones are reserved at all.
--
-- Everything is cached and recomputed from signals; `UIDevice.Changed` fires
-- once per real change so callers can re-lay-out without polling.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UIDevice = {}

local changedEvent = Instance.new("BindableEvent")
UIDevice.Changed = changedEvent.Event

-- ---------------------------------------------------------------------------
-- 1. Form factor
-- ---------------------------------------------------------------------------

-- A Studio-only override so phone layouts can be exercised on a PC without a
-- device simulator. Mirrors the flag NoiseReporter and FlashlightController
-- already honoured, so existing testing habits keep working.
-- THREE-VALUED, deliberately. nil is "ask the device", true is "pretend this is
-- a handheld", and FALSE is "pretend this is a pointer device" -- which is not
-- the same as nil the moment the session itself is a handheld. Verifying a
-- mobile repair means running the suite inside Studio's Device Emulator, and
-- from in there the whole desktop half of every matrix was unreachable:
-- clearing the flag returned the emulator's own touch form factor, so the check
-- that keyboard captions COME BACK when a device stops suppressing glyphs could
-- never see them come back, and reported a genuine layout as broken. A pointer
-- override makes both directions reachable from either host.
local function forcedTouch(): boolean?
	if not RunService:IsStudio() then return nil end
	local forced = workspace:GetAttribute("ForceTouchUI")
	if typeof(forced) == "boolean" then return forced end
	return nil
end

-- The same idea one step further: a Studio-only VIEWPORT override, so the whole
-- HUD can be measured at phone and tablet sizes from a script. The Device
-- Simulator has to be set before entering Play and cannot be driven from Luau,
-- which makes a full device matrix impossible to automate without this.
local function forcedViewport(): Vector2?
	if not RunService:IsStudio() then return nil end
	local override = workspace:GetAttribute("UIRegressionViewport")
	if typeof(override) == "Vector2" and override.X >= 240 and override.Y >= 240 then
		return override
	end
	return nil
end

-- ── AN EXACT TRANSPORT FOR A FIXTURE'S INSET MARGINS ───────────────────────
-- C_INSET_TRANSPORT_IS_EXACT_20260831 -- WHAT SHIPPED BROKEN.
--
-- Both fixture inset overrides travelled as a Rect, and A RECT CANNOT CARRY
-- FOUR FREE MARGINS. Rect.new sorts each axis independently. Measured, by
-- constructing them and reading the components back:
--
--   Rect.new(0, 58, 0, 0)   -> Min(0, 0)   Max(0, 58)    NOT preserved
--   Rect.new(12, 3, 4, 7)   -> Min(4, 3)   Max(12, 7)    NOT preserved
--   Rect.new(59, 0, 59, 21) -> Min(59, 0)  Max(59, 21)   preserved, by luck
--
-- So {left 0, top 58, right 0, bottom 0} -- a topbar and nothing else, which is
-- the commonest inset shape there is -- is UNREPRESENTABLE. It arrives as a
-- 58px BOTTOM margin: the harness stated a topbar and the layout received a
-- bottom inset, on every row, silently. Any inset whose left margin exceeds its
-- right one is swapped the same way, so the corruption is not confined to the
-- topbar; it was latent in the housing override too and only invisible there
-- because the rows that exist happen to state symmetric cutouts.
--
-- The authoritative form is therefore TWO Vector2 attributes per inset --
-- `<Name>LT` carrying {left, top} and `<Name>RB` carrying {right, bottom}. A
-- Vector2 preserves both components verbatim, the two attributes are
-- independent of each other, and all four margins survive the round trip
-- exactly, in any combination.
--
-- The old Rect attribute is STILL READ, because several matrices and the
-- orchestrator's own probes still write it and it is still correct for every
-- inset it happens to be able to express. When both forms are present the exact
-- one wins OUTRIGHT -- not edge by edge -- so a stale Rect left behind by a
-- previous row cannot bleed a margin into a row that stated its own. Stating
-- only one half of the pair means the other two margins are ZERO: a margin that
-- is not stated is not inherited, which is the same rule the rest of the
-- fixture already follows.
local function statedMargins(name: string): any
	if not RunService:IsStudio() then return nil end
	-- NaN fails every comparison it takes part in, so it would sail straight
	-- through math.max and poison every rectangle derived from it.
	local function margin(value: any): number
		if type(value) ~= "number" or value ~= value then return 0 end
		return math.max(0, value)
	end
	local lt = workspace:GetAttribute(name .. "LT")
	local rb = workspace:GetAttribute(name .. "RB")
	if typeof(lt) == "Vector2" or typeof(rb) == "Vector2" then
		local ltv = if typeof(lt) == "Vector2" then lt else Vector2.zero
		local rbv = if typeof(rb) == "Vector2" then rb else Vector2.zero
		return {Left = margin(ltv.X), Top = margin(ltv.Y),
			Right = margin(rbv.X), Bottom = margin(rbv.Y)}
	end
	local legacy = workspace:GetAttribute(name)
	if typeof(legacy) == "Rect" then
		return {Left = margin(legacy.Min.X), Top = margin(legacy.Min.Y),
			Right = margin(legacy.Max.X), Bottom = margin(legacy.Max.Y)}
	end
	return nil
end

-- THE TOPBAR'S OWN BAND IS NOT THE FULL WIDTH OF THE SCREEN, and a fixture has
-- to be able to say how far in it starts. Measured on an iPhone 16 Pro Max in
-- Studio's Device Emulator, landscape:
--
--   GetInsetArea(None)             (-62,-58)..(893,381)   the display
--   GetInsetArea(DeviceSafeInsets) (  0,-58)..(831,360)
--   GetInsetArea(TopbarSafeInsets) (164,-58)..(831,  0)   <-- the band itself
--
-- The band is 667x58 on a 955-wide display: it is inset 164px from the
-- device-safe LEFT edge, because Roblox's own chrome does not begin at the
-- screen edge. That margin is a property of the widget, not of the housing and
-- not of the topbar's height, so there is nothing left to derive it from once
-- the host is out of the picture. A row STATES it, as a Vector2 of {left,
-- right} margins measured inside the device-safe rect, and it DEFAULTS TO ZERO:
-- a row that cares about the band's horizontal extent has to write it down.
local function statedTopbarBand(): Vector2
	if not RunService:IsStudio() then return Vector2.zero end
	local stated = workspace:GetAttribute("UIRegressionTopbarBandLR")
	if typeof(stated) ~= "Vector2" then return Vector2.zero end
	local left = if stated.X == stated.X then math.max(0, stated.X) else 0
	local right = if stated.Y == stated.Y then math.max(0, stated.Y) else 0
	return Vector2.new(left, right)
end

-- "Phone or tablet" means a touchscreen with no POINTER. MouseEnabled is the
-- right discriminator here, not KeyboardEnabled: a real phone or tablet reports
-- no mouse even when a Bluetooth keyboard is paired, while a desktop with a
-- touch monitor and a laptop with a trackpad both report one and should keep
-- their keyboard hints, because the keys are genuinely there.
--
-- This is a FORM FACTOR question and is answered without ever consulting
-- GetLastInputType, so touching the screen of a desktop cannot strip its
-- keyboard hints, and brushing a mouse on a tablet cannot conjure them.
local function computeTouchFormFactor(): boolean
	local forced = forcedTouch()
	if forced ~= nil then return forced end
	if not UserInputService.TouchEnabled then return false end
	-- A handheld is a touchscreen that is missing a pointer OR a keyboard.
	-- Requiring both to be absent was too strict: a phone with a Bluetooth mouse
	-- reports MouseEnabled and would have been served "[R]" for a key it has
	-- not got. Requiring only one to be absent is too loose in the other
	-- direction, so both are consulted -- a device with a real mouse AND a real
	-- keyboard (touchscreen laptop, Surface, tablet in a keyboard case) keeps
	-- its hints, because the keys genuinely are there.
	return not (UserInputService.MouseEnabled and UserInputService.KeyboardEnabled)
end

local touchFormFactor = computeTouchFormFactor()

function UIDevice.IsTouch(): boolean
	return touchFormFactor
end

-- Whether a KEYBOARD GLYPH may be printed at all. This is a strictly wider test
-- than the form factor: a touchscreen laptop or a tablet in a keyboard case is
-- laid out as a desktop, because it has the room and the pointer for it, but the
-- moment a touchscreen is present the same caption has to be reachable by finger
-- alone. Printing "[M]" next to a control someone is about to tap is at best
-- noise and at worst an instruction they cannot follow, so TouchEnabled alone
-- suppresses the glyph even when a mouse and keyboard are also present.
local function suppressesKeyboardGlyphs(): boolean
	-- The Studio override answers this one too, and has to. Studio's Device
	-- Emulator leaves UserInputService.TouchEnabled true for the whole session
	-- while still reporting a mouse and a keyboard, so from inside it EVERY
	-- device -- including the desktop rows -- suppressed glyphs and the keyboard
	-- half of the caption contract was untestable. `false` means "a pointer
	-- device with no touchscreen", which is precisely what those rows are.
	local forced = forcedTouch()
	if forced ~= nil then return forced end
	return touchFormFactor or UserInputService.TouchEnabled
end

function UIDevice.SuppressesKeyboardGlyphs(): boolean
	return suppressesKeyboardGlyphs()
end

function UIDevice.IsGamepadOnly(): boolean
	return UserInputService.GamepadEnabled
		and not UserInputService.KeyboardEnabled
		and not touchFormFactor
end

-- ---------------------------------------------------------------------------
-- 2. Latest input
-- ---------------------------------------------------------------------------

function UIDevice.LastInput(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:find("Gamepad") then return "Gamepad" end
	if last == Enum.UserInputType.Touch then return "Touch" end
	return "Keyboard"
end

-- ---------------------------------------------------------------------------
-- Binding text
-- ---------------------------------------------------------------------------

-- The single gate every caption goes through. Anywhere a touchscreen exists this
-- returns an empty string, unconditionally and regardless of what was touched
-- last. On a pointer-only desktop it prefers the gamepad glyph, and then only
-- when a gamepad is actually the live input.
function UIDevice.Binding(keyboard: string?, gamepad: string?): string
	-- A phone/tablet never prints bindings, including when a Bluetooth gamepad is
	-- paired or happened to be the most recent input. Touch controls must remain
	-- self-explanatory and the user explicitly should not see keyboard/gamepad
	-- hints on those form factors.
	if suppressesKeyboardGlyphs() then return "" end

	-- Pointer-only devices may prefer the gamepad glyph when it is genuinely the
	-- live input.
	local wantsGamepad = gamepad and gamepad ~= ""
		and UserInputService.GamepadEnabled
		and UIDevice.LastInput() == "Gamepad"
	if wantsGamepad then return gamepad :: string end
	-- On a gamepad-only device the keyboard string names keys that do not
	-- exist, so it is withheld rather than shown as a fallback.
	if UIDevice.IsGamepadOnly() then return "" end
	return keyboard or ""
end

-- Compose a caption with its binding, collapsing the separator when there is no
-- binding to show. `UIDevice.Caption("OPEN EXIT READER", "[R]", "[Y]")` gives
-- "OPEN EXIT READER  [R]" on desktop and "OPEN EXIT READER" on a phone.
function UIDevice.Caption(text: string, keyboard: string?, gamepad: string?): string
	local binding = UIDevice.Binding(keyboard, gamepad)
	if binding == "" then return text end
	return text .. "  " .. binding
end

-- ---------------------------------------------------------------------------
-- 3. Layout
-- ---------------------------------------------------------------------------

local layout: any = nil

-- Forward-declared. The control-zone watchers below are wired up as controls
-- register themselves, which happens long before the change-propagation block at
-- the foot of this file defines what a refresh actually is; nilable rather than
-- annotated as a plain function so the call site has to say so.
local refresh: ((boolean?) -> ())? = nil

-- ---------------------------------------------------------------------------
-- THE COORDINATE CONTRACT  (C_ONE_SAFE_AREA_20260830)
-- ---------------------------------------------------------------------------
--
-- There is ONE space, and everything in this module speaks it: the space that
-- `GuiService:GetInsetArea()` and `GuiObject.AbsolutePosition` already share.
-- Measured in a live client at a 1476x628 window with a 58px topbar:
--
--   GetInsetArea(None)             = (0,-58)-(1476,570)   the whole display
--   GetInsetArea(DeviceSafeInsets) = (0,-58)-(1476,570)   minus notch/indicator
--   GetInsetArea(CoreUISafeInsets) = (0,  0)-(1476,570)   ...and minus the topbar
--   GetInsetArea(TopbarSafeInsets) = (164,-58)-(1476,0)   the topbar's own strip
--
-- and, for a ScreenGui at any ScreenInsets setting:
--
--   ScreenGui.AbsolutePosition == GetInsetArea(ScreenGui.ScreenInsets).Min
--   ScreenGui.AbsoluteSize     == that rect's size
--   child.AbsolutePosition     == ScreenGui.AbsolutePosition + child offset
--
-- verified for all four ScreenInsets values and both IgnoreGuiInset settings
-- (IgnoreGuiInset is the legacy alias and no longer decides anything once
-- ScreenInsets is set). So the conversion from this space into ANY gui's local
-- offsets is one subtraction, in BOTH axes, and it is exact:
--
--   local = absolute - screenGui.AbsolutePosition        (UIDevice.LocalOffset)
--
-- WHAT THIS REPLACES, and why it had to go:
--   * a hard-coded 59px "sensor housing" applied to every landscape phone.
--     It was invented because `GuiService.TopbarInset` was mistaken for a
--     housing API (its Min.X is where Roblox's own topbar chrome ends, 164 on
--     a notchless desktop). GetInsetArea IS the API. The constant is gone: it
--     double-applied the notch on real iPhones, whose CoreUI/Device inset
--     areas already exclude it, and stole 118px from notchless Androids.
--   * a Y-only conversion helper, which silently left X unconverted.
--   * "viewport space with the top inset already applied", which is neither
--     the display nor any gui's space and agreed with neither.
--
-- The Studio-only fixture inset overrides REPLACE the measured inset amounts
-- rather than adding to them, so a synthetic device can never double-apply a
-- housing the engine has already accounted for. Their authoritative transport
-- is a PAIR of Vector2 attributes per inset -- UIRegressionSafeInsetsLT/RB for
-- the housing, UIRegressionTopbarInsetLT/RB for the topbar, plus
-- UIRegressionTopbarBandLR for the topbar band's horizontal margins. The older
-- single-Rect attributes are still honoured but cannot express every inset; see
-- C_INSET_TRANSPORT_IS_EXACT_20260831 above.
--
-- All four ScreenInsets rectangles are answered by UIDevice.InsetArea(kind),
-- from the engine on a real device and from the row's stated numbers under a
-- fixture. TopbarSafeInsets is the topbar's OWN BAND -- a short strip, inset
-- horizontally -- and never "the screen less a top margin".
-- ── THE REAL CONTROL RECTANGLES ────────────────────────────────────────────
-- C_LIVE_CONTROL_RECTS_20260831.
--
-- `Zones.Controls` was a PROXY: a 168x290 (196x330 on a tablet) block pinned to
-- the display's bottom-right corner, guessed from what the cluster was thought
-- to occupy. Every objective readout then dodged that guess -- and because the
-- guess is 290px tall, a panel that wanted the screen's own safe right edge was
-- pushed hundreds of pixels toward the centre to get out of its way, on a
-- device where the real buttons start far lower.
--
-- The controls now REGISTER THEMSELVES. NoiseReporter and FlashlightController
-- call RegisterControlRect for each button they build; the zone is the union of
-- whatever is currently visible, measured. The proxy survives only as the
-- answer before any control has registered (module load, and the first frames
-- of a session), so nothing is ever unbounded.
-- TAGGED, not held in a table, and the difference is the whole point. Studio's
-- execute_luau -- which is what drives every device matrix in this game -- runs
-- in a SEPARATE require cache from the running LocalScripts, so a module local
-- populated by NoiseReporter is an empty table as far as the harness is
-- concerned. Registration through a module local therefore made the measured
-- union invisible to the very thing that has to check it: the matrices went on
-- reading the proxy and reported it as the live cluster. CollectionService is
-- datamodel state, so both VMs see the same set.
local CONTROL_TAG = "UIDeviceControlRect"

-- ── KEEPING THE MEASURED ZONE LIVE ─────────────────────────────────────────
-- C_CONTROL_ZONE_INVALIDATION_20260831 -- WHAT SHIPPED BROKEN.
--
-- Tagging made the cluster visible to the harness's VM, and there it stopped:
-- NOTHING recomputed when the cluster itself moved. The union was measured only
-- when some unrelated input happened to call refresh() -- a viewport resize, or
-- the one-second inset watcher -- so for up to a second at a time `Zones.Controls`
-- described a cluster that was no longer on screen: a round that had just shown
-- SNEAK, a lobby that had lifted RUN, a fixture that had untagged a button. Every
-- HUD that dodges the zone dodged a ghost. And refresh() did not compare
-- Zones.Controls at all, so even when it did recompute, a layout whose ONLY
-- change was the cluster fired no UIDevice.Changed and nothing relaid out.
--
-- Every input the union is built from now marks the zone dirty: the tag going on
-- or off, Visible, AbsolutePosition, AbsoluteSize, the element's ancestry, and
-- its ScreenGui's Enabled. They COALESCE through task.defer, so a relayout that
-- moves five buttons costs one recompute rather than five, and nothing in this
-- path polls per frame.
local controlRefreshScheduled = false
local function scheduleControlRefresh()
	if controlRefreshScheduled then return end
	controlRefreshScheduled = true
	task.defer(function()
		controlRefreshScheduled = false
		if refresh then refresh() end
	end)
end

-- One bundle of connections per tagged element, released the moment the tag goes
-- away or the element is destroyed. WEAK-KEYED as well, because Destroy() gives
-- no ordering guarantee between clearing an instance's tags and firing its
-- AncestryChanged: a control destroyed without ever being untagged must not be
-- able to keep this table -- and itself -- alive.
local controlWatches: any = setmetatable({}, {__mode = "k"})
local watchControl, unwatchControl

unwatchControl = function(element: Instance)
	local bundle = controlWatches[element]
	if bundle == nil then return end
	controlWatches[element] = nil
	for _, connection in ipairs(bundle) do
		connection:Disconnect()
	end
end

watchControl = function(element: Instance)
	if controlWatches[element] ~= nil then return end
	if not element:IsA("GuiObject") then return end
	local bundle = {}
	controlWatches[element] = bundle
	for _, property in ipairs({"Visible", "AbsolutePosition", "AbsoluteSize"}) do
		table.insert(bundle,
			element:GetPropertyChangedSignal(property):Connect(scheduleControlRefresh))
	end
	-- A ScreenGui's Enabled is as much a part of "is this drawn" as Visible is --
	-- the flashlight body lives in a gui that is disabled out of round -- and
	-- reparenting can change WHICH gui that is, so the watch is rebuilt rather
	-- than patched when the ancestry moves.
	local screen = element:FindFirstAncestorWhichIsA("ScreenGui")
	if screen then
		table.insert(bundle,
			screen:GetPropertyChangedSignal("Enabled"):Connect(scheduleControlRefresh))
	end
	table.insert(bundle, element.AncestryChanged:Connect(function()
		unwatchControl(element)
		if element.Parent ~= nil and CollectionService:HasTag(element, CONTROL_TAG) then
			watchControl(element)
		end
		scheduleControlRefresh()
	end))
	table.insert(bundle, element.Destroying:Connect(function()
		unwatchControl(element)
		scheduleControlRefresh()
	end))
end

-- CollectionService is the cross-VM channel, so the SIGNALS are too: a control
-- tagged by a LocalScript starts being watched in the harness's require cache as
-- well, and both copies of this module answer for the same cluster.
CollectionService:GetInstanceAddedSignal(CONTROL_TAG):Connect(function(element)
	watchControl(element)
	scheduleControlRefresh()
end)
CollectionService:GetInstanceRemovedSignal(CONTROL_TAG):Connect(function(element)
	unwatchControl(element)
	scheduleControlRefresh()
end)
for _, element in ipairs(CollectionService:GetTagged(CONTROL_TAG)) do
	watchControl(element)
end

function UIDevice.RegisterControlRect(key: string, element: GuiObject?)
	if element == nil then return end
	if not CollectionService:HasTag(element, CONTROL_TAG) then
		CollectionService:AddTag(element, CONTROL_TAG)
	end
	element:SetAttribute("UIDeviceControlKey", key)
	-- Not left to the tag signal alone: re-registering an already-tagged element
	-- under a new key changes nothing CollectionService reports, and the caller
	-- has still told us the cluster is not what it was.
	watchControl(element)
	scheduleControlRefresh()
end

function UIDevice.UnregisterControlRect(element: GuiObject)
	CollectionService:RemoveTag(element, CONTROL_TAG)
	unwatchControl(element)
	scheduleControlRefresh()
end

-- Is this element actually on the screen right now? Visible is not the whole
-- answer. A control inside a DISABLED ScreenGui is not drawn either, and the
-- flashlight body lives in exactly such a gui out of round -- so without this the
-- lobby's control zone reserved a torch nobody could see, and it reserved it at
-- the in-round cluster's height.
local function drawnOnScreen(element: GuiObject): boolean
	if element.Parent == nil or not element.Visible then return false end
	if element.AbsoluteSize.X <= 1 or element.AbsoluteSize.Y <= 1 then return false end
	local node: Instance? = element.Parent
	while node ~= nil do
		if node:IsA("ScreenGui") then return node.Enabled end
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	-- Nothing is rendering an element with no LayerCollector above it.
	return false
end

-- The union of every registered control that is currently drawn, in the one
-- space (AbsolutePosition IS that space). Returns nil when nothing is drawn,
-- which is the signal to fall back to the proxy.
-- How many controls are REGISTERED, drawn or not. The difference between
-- "nothing has registered yet" (use the proxy) and "the cluster is registered
-- and currently off screen" (there is nothing to avoid) -- see
-- C_NO_CONTROLS_IS_NOT_A_PROXY_20260831.
local function registeredControlCount(): number
	local count = 0
	for _, element in ipairs(CollectionService:GetTagged(CONTROL_TAG)) do
		if element:IsA("GuiObject") and element.Parent ~= nil then count += 1 end
	end
	return count
end

local function measuredControlUnion(): any
	local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
	local counted = 0
	for _, element in ipairs(CollectionService:GetTagged(CONTROL_TAG)) do
		if element:IsA("GuiObject") and drawnOnScreen(element) then
			local position, size = element.AbsolutePosition, element.AbsoluteSize
			left = math.min(left, position.X)
			top = math.min(top, position.Y)
			right = math.max(right, position.X + size.X)
			bottom = math.max(bottom, position.Y + size.Y)
			counted += 1
		end
	end
	if counted == 0 then return nil end
	return {Left = left, Top = top, Right = right, Bottom = bottom, Count = counted}
end

-- ── THE CLUSTER'S OWN ARITHMETIC, IN ONE PLACE ─────────────────────────────
-- C_SHORT_SCREEN_CLUSTER_20260831 -- WHAT SHIPPED BROKEN.
--
-- NoiseReporter stacked JUMP / RUN / SNEAK up the right edge at 64px with 14px
-- gaps above a 22px margin, FlashlightController re-derived the same edge,
-- button and second-column constants from its own copy of them, and this module
-- kept a third copy to build the proxy from. 22 + 64*3 + 14*2 is 242px of
-- cluster. On a 568x320 landscape phone the safe area is 262px tall, so the
-- whole screen above the cluster came to 4px of usable height -- and the
-- objective readout, which needs 56, gave up the safe right edge and stepped
-- into the middle of the screen looking for it. The owner's rule is the
-- opposite: the readout owns the upper-right corner on every touch device, and
-- the CLUSTER is what gives way.
--
-- So the cluster has two arrangements and this module chooses between them:
--   * COLUMN -- what has always shipped, unchanged to the pixel, whenever the
--     safe area can hold it and still leave a usable readout above it;
--   * ROW -- the same controls laid along the bottom edge instead, sized to the
--     daylight between the dynamic thumbstick's activation edge and the safe
--     right edge, which turns 242px of reserved height into 67.
--
-- Both are described as SLOTS: an inset from the ScreenGui's right and bottom
-- edges plus a size, which is exactly the idiom the buttons are positioned with.
-- The proxy zone is the union of those same slots, so the rectangle every HUD
-- dodges is the cluster BY CONSTRUCTION rather than by a second copy of the
-- arithmetic that can drift away from it.
local CONTROL_CUSHION = 8
-- What an objective readout needs above the cluster, and the margins it is
-- placed with. Stated here because the ARRANGEMENT is chosen against them, and
-- TopRightPanel then honours them; two numbers, one meaning.
local OBJECTIVE_MARGIN = 8
local OBJECTIVE_GUTTER = 8
local MINIMUM_USABLE_HEIGHT = 56
-- Roblox's dynamic thumbstick owns the left 40% of a landscape screen. A row
-- control may not touch it, and this is the daylight kept from its edge.
local THUMBSTICK_CLEARANCE = 8
-- The floor for a touch target, in BOTH axes. No arrangement may produce
-- anything smaller; a row that cannot seat every control at this size is not
-- offered at all.
local MINIMUM_TOUCH_TARGET = 44

-- Rightmost first, which is the order the row fills from: the thumb-nearest slot
-- goes to JUMP, because in the lobby -- where ours is hidden -- that is the slot
-- Roblox's own jump button occupies, and one arrangement should not have to
-- dodge the other.
local CONTROL_KEYS_RIGHT_FIRST = {
	"TouchJump", "TouchRunHold", "TouchSneakHold",
	"TouchDropGlowstick", "TouchPOV", "FlashlightPower",
}

local function columnControlPlan(tablet: boolean): any
	local edge = tablet and 26 or 22
	local button = tablet and 76 or 64
	local gap = tablet and 18 or 14
	-- The second column and the flashlight slot beneath it, verbatim from what
	-- NoiseReporter and FlashlightController each used to compute for themselves.
	local second = edge + button + (tablet and 18 or 16)
	local secondWidth = tablet and 72 or 58
	local flashlightSlot = 58
	local run = edge + button + gap
	return {
		Mode = "column",
		Edge = edge,
		Gap = gap,
		Cell = button,
		Order = CONTROL_KEYS_RIGHT_FIRST,
		Slots = {
			TouchJump = {Right = edge, Bottom = edge,
				Width = button, Height = button, TextSize = tablet and 17 or 15},
			TouchRunHold = {Right = edge, Bottom = run,
				Width = button, Height = button, TextSize = tablet and 18 or 16},
			TouchSneakHold = {Right = edge, Bottom = run + button + gap,
				Width = button, Height = button, TextSize = tablet and 17 or 15},
			TouchDropGlowstick = {Right = second,
				Bottom = edge + flashlightSlot + button + gap,
				Width = secondWidth, Height = tablet and 72 or 58, TextSize = 12},
			TouchPOV = {Right = second,
				Bottom = edge + flashlightSlot + (tablet and 14 or 12),
				Width = secondWidth, Height = tablet and 54 or 48, TextSize = 13},
			FlashlightPower = {Right = second, Bottom = edge,
				Width = secondWidth, Height = secondWidth},
		},
	}
end

-- The bottom-edge arrangement. `usableWidth` is the daylight from the safe right
-- edge back to the thumbstick's activation edge: the row is SIZED to fit inside
-- it rather than clamped into it afterwards, so no control can land in the
-- region a finger uses to walk. Six 44px targets and their gaps do not fit every
-- short screen, so a second attempt seats them three-abreast in two ranks;
-- returns nil when even that will not fit, and the column stands.
local function rowControlPlan(tablet: boolean, usableWidth: number): any?
	local edge = tablet and 26 or 22
	local gap = tablet and 12 or 8
	local largest = tablet and 68 or 56
	local count = #CONTROL_KEYS_RIGHT_FIRST
	for _, perRank in ipairs({count, math.ceil(count / 2)}) do
		local cell = math.floor((usableWidth - edge - gap * (perRank - 1)) / perRank)
		cell = math.min(cell, largest)
		if cell >= MINIMUM_TOUCH_TARGET then
			local slots = {}
			for index, key in ipairs(CONTROL_KEYS_RIGHT_FIRST) do
				-- Index 1 is the rightmost slot of the bottom rank, so the primary
				-- controls stay under the thumb and the second rank -- when there
				-- is one -- carries GLOW, POV and the torch.
				local column = (index - 1) % perRank
				local rank = math.floor((index - 1) / perRank)
				slots[key] = {
					Right = edge + column * (cell + gap),
					Bottom = edge + rank * (cell + gap),
					Width = cell,
					Height = cell,
					TextSize = tablet and 13 or 12,
				}
			end
			return {
				Mode = "row",
				Edge = edge,
				Gap = gap,
				Cell = cell,
				Order = CONTROL_KEYS_RIGHT_FIRST,
				Slots = slots,
			}
		end
	end
	return nil
end

local function insetArea(kind: Enum.ScreenInsets): Rect?
	local ok, rect = pcall(function() return GuiService:GetInsetArea(kind) end)
	if ok and typeof(rect) == "Rect" then return rect end
	return nil
end

-- A rectangle in the one space, as the four edges plus its size. NOT as a Rect:
-- Rect.new sorts each axis, which is harmless for a rectangle whose Min really
-- is its minimum but is a trap the moment anything is derived from one (see
-- C_INSET_TRANSPORT_IS_EXACT_20260831), and every other rectangle this module
-- hands out already speaks the four-field shape.
local function edgeRect(left: number, top: number, right: number, bottom: number): any
	return {
		Left = left, Top = top, Right = right, Bottom = bottom,
		Width = math.max(0, right - left), Height = math.max(0, bottom - top),
	}
end

-- Roblox's default touch controls, reproduced from PlayerModule so the HUD can
-- stay out of their way without reaching into PlayerGui for measurements.
--
-- TouchJump:        size 70 when min(width, height) <= 500, else 120, anchored
--                   bottom-right at (1, -(size*1.5-10)), (1, -size-20).
-- DynamicThumbstick: an ACTIVATION REGION, not a visible ring. Landscape it is
--                   the left 40% of the bottom two thirds; portrait the whole
--                   width of the bottom 40%. A finger anywhere in it drives
--                   movement, which is why no interactive HUD may sit there.
local function computeLayout(): any
	local camera = workspace.CurrentCamera
	local realViewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)
	local viewport = forcedViewport() or realViewport
	local width, height = viewport.X, viewport.Y
	local inset = GuiService:GetGuiInset()
	local portrait = height > width
	local minAxis = math.min(width, height)

	local class
	if not touchFormFactor then
		class = "desktop"
	elseif minAxis >= 700 then
		class = "tablet"
	else
		class = "phone"
	end

	-- ── THE DISPLAY AND THE SAFE AREA, TAKEN FROM THE ENGINE ────────────────
	-- C_SAFE_AREA_FROM_ENGINE_20260831 -- WHAT SHIPPED BROKEN, and it is the
	-- whole of P0.
	--
	-- The previous version built the display as `GetInsetArea(None).Min` plus
	-- `Camera.ViewportSize`, then derived cutout/home-indicator insets by
	-- comparing None against DeviceSafeInsets and subtracted them AGAIN. Both
	-- halves are wrong, and together they apply the notch twice.
	--
	-- MEASURED on a real Studio Device Emulator run, iPhone 16 Pro Max:
	--
	--   Camera.ViewportSize                  831x418     <-- ALREADY device-safe
	--   GetInsetArea(None)         (-62,-58)..(893,381)  955x439  <-- the display
	--   GetInsetArea(DeviceSafeInsets) (0,-58)..(831,360)  831x418 == the camera
	--   GetInsetArea(CoreUISafeInsets)  (0,  0)..(831,360)
	--
	--   the old model produced  Display (-62,-58)..(769,360)
	--                           Safe    (   0,  0)..(707,339)  insets L62 R62 B21
	--
	-- i.e. a right edge 124px inside the true safe edge, because the camera --
	-- which the engine had already inset by the cutout -- was pasted onto the
	-- display's negative origin and then inset by the cutout a second time.
	--
	-- Camera.ViewportSize is NOT the display. It is DeviceSafeInsets' size. So
	-- nothing is reconstructed here any more: the display IS GetInsetArea(None),
	-- and the safe area IS the intersection of the two inset areas the engine
	-- reports. There is no modelled housing constant anywhere in this function.
	local noneArea = insetArea(Enum.ScreenInsets.None)
	local coreArea = insetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local deviceArea = insetArea(Enum.ScreenInsets.DeviceSafeInsets)
	-- A client too old to answer degrades to the camera plus the topbar inset,
	-- which is exactly what the pre-ScreenInsets world assumed.
	local fallbackDisplay = Rect.new(0, -inset.Y, realViewport.X, realViewport.Y - inset.Y)
	noneArea = noneArea or fallbackDisplay
	coreArea = coreArea or Rect.new(0, 0, realViewport.X, realViewport.Y - inset.Y)
	deviceArea = deviceArea or fallbackDisplay
	-- The topbar's OWN BAND, kept as a fourth rectangle because it is one: on the
	-- iPhone 16 Pro Max measured above it is 667x58 at (164,-58) inside a 955x439
	-- display, i.e. neither the screen nor the screen less a top margin. A client
	-- too old to answer for it degrades to GuiService.TopbarInset, which is the
	-- same strip under the pre-ScreenInsets API, and failing that to the full
	-- width of the device-safe rect down to where the core area begins.
	local topbarArea = insetArea(Enum.ScreenInsets.TopbarSafeInsets)
	if topbarArea == nil then
		local okBand, legacyBand = pcall(function() return GuiService.TopbarInset end)
		if okBand and typeof(legacyBand) == "Rect" then topbarArea = legacyBand end
	end
	topbarArea = topbarArea or Rect.new(deviceArea.Min.X, deviceArea.Min.Y,
		deviceArea.Max.X, math.max(deviceArea.Min.Y, coreArea.Min.Y))

	local engineDisplay = {
		Left = noneArea.Min.X, Top = noneArea.Min.Y,
		Right = noneArea.Max.X, Bottom = noneArea.Max.Y,
	}
	-- The intersection, edge by edge. Not "None minus some insets".
	local engineSafe = {
		Left = math.max(coreArea.Min.X, deviceArea.Min.X),
		Top = math.max(coreArea.Min.Y, deviceArea.Min.Y),
		Right = math.min(coreArea.Max.X, deviceArea.Max.X),
		Bottom = math.min(coreArea.Max.Y, deviceArea.Max.Y),
	}

	-- ── the SYNTHETIC FIXTURE space, kept explicitly separate ───────────────
	-- A forced viewport is a FIXTURE, not a device. It gets its own rectangle,
	-- built from the requested size at the real display's origin, and its own
	-- safe insets -- either the ones a matrix states, or the real device's,
	-- expressed as amounts rather than as edges so they survive the resize.
	-- Mixing the two spaces is what let a fixture inherit a real cutout it had
	-- already been told about.
	local synthetic = forcedViewport() ~= nil
	local display, safe, insetAreas
	if not synthetic then
		display, safe = engineDisplay, engineSafe
		-- ── THE FOUR SCREENINSETS RECTANGLES ────────────────────────────────
		-- C_INSET_AREAS_ARE_ANSWERED_20260831.
		--
		-- On a real device these are the engine's own answers and nothing is
		-- modelled: GetInsetArea IS the API. They are published because the
		-- SYNTHETIC branch below has to answer the same four questions from a
		-- fixture's stated numbers -- under a forced viewport the engine still
		-- renders at the host window, so its rectangles describe that window and
		-- say nothing whatever about the fixture -- and a caller must be able to
		-- ask one question and get the right answer on either kind of layout.
		insetAreas = {
			None = edgeRect(noneArea.Min.X, noneArea.Min.Y,
				noneArea.Max.X, noneArea.Max.Y),
			DeviceSafeInsets = edgeRect(deviceArea.Min.X, deviceArea.Min.Y,
				deviceArea.Max.X, deviceArea.Max.Y),
			CoreUISafeInsets = edgeRect(coreArea.Min.X, coreArea.Min.Y,
				coreArea.Max.X, coreArea.Max.Y),
			TopbarSafeInsets = edgeRect(topbarArea.Min.X, topbarArea.Min.Y,
				topbarArea.Max.X, topbarArea.Max.Y),
		}
	else
		-- The fixture's SAFE ORIGIN has to land on the real gui origin, not its
		-- display origin. Panels are positioned through UIDevice.LocalPosition,
		-- which subtracts the gui's REAL AbsolutePosition -- so if the fixture's
		-- safe rect started 62px left of where an inset-respecting gui actually
		-- begins, every panel resolved 62px left of where it renders and the
		-- analytic and live edges disagreed by the whole cutout. Anchoring the
		-- fixture's SAFE corner to the engine's safe corner makes the two spaces
		-- coincide exactly where the writers convert between them.
		-- C_FIXTURE_INSETS_ARE_STATED_20260831 -- WHAT SHIPPED BROKEN.
		--
		-- A fixture that stated no insets used to INHERIT the host's, and that
		-- made every such row a different device depending on where the suite
		-- was run. Run from a desktop Studio window the four notchless rows
		-- (705x338, 568x320, 375x667, 338x705) were rectangles with no housing
		-- and passed; run inside the Device Emulator on an iPhone 16 Pro Max --
		-- which is where a mobile repair is actually verified -- they inherited
		-- its 62px cutout on BOTH sides, so "iPhone SE portrait 375x667" was
		-- tested as a 251px-wide screen and the Zyntra terminal collapsed onto
		-- its 260px floor and hung off the left edge. Green on one host, red on
		-- another, for a layout that never changed.
		--
		-- A row states what its device reports. What it does NOT state is zero
		-- -- except for the TOPBAR, which is Roblox's own chrome and exists on
		-- every device no matter the housing. The topbar's contribution is
		-- CoreUISafeInsets measured against DeviceSafeInsets: that difference is
		-- the topbar alone, where measuring either against None would fold the
		-- host's cutout back in.
		--
		-- STATED, NOT MEASURED, when the fixture says so. C_FIXTURE_TOPBAR_20260831.
		-- Deriving the topbar from the host makes a fixture row's geometry depend
		-- on where the suite is run: the same "375x667" is a different rectangle
		-- under a desktop Studio window (36px topbar) and under the Device
		-- Emulator on a notched iPhone (58px), so a matrix that states the exact
		-- rectangles a row must produce could not state them at all. A row that
		-- states a topbar gets EXACTLY that topbar; a row that does not keeps the
		-- host's, which is what every existing caller relies on.

		-- Read through the EXACT transport, which falls back to the legacy Rect
		-- attribute when a caller still writes one. See
		-- C_INSET_TRANSPORT_IS_EXACT_20260831 at the head of this file for why a
		-- Rect cannot be the authoritative form.
		local topbar = statedMargins("UIRegressionTopbarInset") or {
			Left = math.max(0, coreArea.Min.X - deviceArea.Min.X),
			Top = math.max(0, coreArea.Min.Y - deviceArea.Min.Y),
			Right = math.max(0, deviceArea.Max.X - coreArea.Max.X),
			Bottom = math.max(0, deviceArea.Max.Y - coreArea.Max.Y),
		}
		-- The HOUSING, and it is zero unless the row states one. A cutout the row
		-- did not write down is not a cutout.
		local housing = statedMargins("UIRegressionSafeInsets")
			or {Left = 0, Top = 0, Right = 0, Bottom = 0}

		-- ── HOUSING AND TOPBAR NEST; THEY DO NOT COMPETE ────────────────────
		-- C_FIXTURE_INSETS_NEST_20260831 -- WHAT SHIPPED BROKEN.
		--
		-- The two stated insets used to be combined by keeping the LARGER edge by
		-- edge. That is not how a device reports them. Measured on an iPhone 16
		-- Pro Max in the Device Emulator, landscape:
		--
		--   None             (-62,-58)..(893,381)   the display, 955x439
		--   DeviceSafeInsets (  0,-58)..(831,360)   = None less the HOUSING
		--   CoreUISafeInsets (  0,  0)..(831,360)   = DeviceSafe less the TOPBAR
		--
		-- CoreUISafeInsets is nested INSIDE DeviceSafeInsets: the engine subtracts
		-- the housing first and then puts its own chrome inside what is left. The
		-- two margins therefore ADD on any edge they share. `max` agreed with that
		-- only because every edge measured so far has a zero on one side of it --
		-- in landscape the cutout is left/right and the topbar is top -- so the
		-- defect was invisible on exactly the rows that exist and would have
		-- appeared the moment a row stated a portrait notch (housing top) together
		-- with the topbar that sits below it, under-insetting the safe area by the
		-- whole 58px topbar and putting every top-pinned panel under the chrome.
		--
		-- Summing is also what makes the four rectangles below consistent with
		-- Safe: Safe is CoreUISafeInsets, and CoreUISafeInsets is the display less
		-- housing less topbar. Under `max` a fixture's Safe was a rectangle no
		-- device could report and no row could write down.
		--
		-- The clamps that stop a pathological row eating the screen now apply to
		-- the PAIR, and the TOPBAR is served first: it is Roblox's own chrome and
		-- is present on every device, so it is the margin that must survive a row
		-- that states an absurd housing.
		local function fitPair(housingMargin: number, topbarMargin: number,
			cap: number): (number, number)
			local chrome = math.clamp(topbarMargin, 0, cap)
			return math.clamp(housingMargin, 0, cap - chrome), chrome
		end
		housing.Left, topbar.Left = fitPair(housing.Left, topbar.Left, width * .25)
		housing.Right, topbar.Right = fitPair(housing.Right, topbar.Right, width * .25)
		housing.Top, topbar.Top = fitPair(housing.Top, topbar.Top, height * .35)
		housing.Bottom, topbar.Bottom =
			fitPair(housing.Bottom, topbar.Bottom, height * .25)
		local left, top = housing.Left + topbar.Left, housing.Top + topbar.Top
		local right, bottom = housing.Right + topbar.Right, housing.Bottom + topbar.Bottom
		-- Anchor the fixture so its SAFE top-left sits exactly on the engine's.
		display = {
			Left = engineSafe.Left - left, Top = engineSafe.Top - top,
			Right = engineSafe.Left - left + width,
			Bottom = engineSafe.Top - top + height,
		}
		safe = {
			Left = display.Left + left, Top = display.Top + top,
			Right = display.Right - right, Bottom = display.Bottom - bottom,
		}

		-- ── THE FOUR SCREENINSETS RECTANGLES, FROM THE ROW'S OWN NUMBERS ────
		-- C_INSET_AREAS_ARE_ANSWERED_20260831 -- WHAT SHIPPED BROKEN.
		--
		-- A fixture could not say what a ScreenGui of a given ScreenInsets would
		-- be given, so callers that needed it borrowed the HOST's amounts off
		-- GuiService -- which under a forced viewport describe the real window and
		-- change with the machine the suite runs on. The four rectangles are now
		-- built here, from the stated geometry and nothing else:
		--
		--   None             the fixture's whole display
		--   DeviceSafeInsets the display less the stated HOUSING
		--   CoreUISafeInsets DeviceSafeInsets less the stated TOPBAR (== Safe)
		--   TopbarSafeInsets THE BAND ITSELF, not the screen minus it
		--
		-- That last one is the trap. TopbarSafeInsets is the topbar widget's own
		-- strip: measured, a 667x58 rectangle at (164,-58) inside a 955x439
		-- display -- inset horizontally as well, and only 58px tall. Any model
		-- that treats it as "the screen less a top margin" produces a rectangle
		-- ten times too tall and fails it on every device. Its top edge is the
		-- device-safe rect's top, its height is the topbar's own margin, and its
		-- horizontal margins are the ones the row states (default zero, see
		-- statedTopbarBand).
		--
		-- Verified against the measured device by feeding it back in as a fixture:
		-- 955x439, housing {62,0,62,21}, topbar {0,58,0,0}, band {164,0} reproduces
		-- all four rectangles above exactly, origin included.
		local deviceRect = edgeRect(
			display.Left + housing.Left, display.Top + housing.Top,
			display.Right - housing.Right, display.Bottom - housing.Bottom)
		local band = statedTopbarBand()
		local bandLeft = math.min(deviceRect.Left + band.X, deviceRect.Right)
		local bandRight = math.max(bandLeft, deviceRect.Right - band.Y)
		insetAreas = {
			None = edgeRect(display.Left, display.Top, display.Right, display.Bottom),
			DeviceSafeInsets = deviceRect,
			CoreUISafeInsets = edgeRect(
				deviceRect.Left + topbar.Left, deviceRect.Top + topbar.Top,
				deviceRect.Right - topbar.Right, deviceRect.Bottom - topbar.Bottom),
			TopbarSafeInsets = edgeRect(bandLeft, deviceRect.Top,
				bandRight, deviceRect.Top + topbar.Top),
		}
	end

	local insetLeft = safe.Left - display.Left
	local insetTop = safe.Top - display.Top
	local insetRight = display.Right - safe.Right
	local insetBottom = display.Bottom - safe.Bottom

	safe.Width = math.max(0, safe.Right - safe.Left)
	safe.Height = math.max(0, safe.Bottom - safe.Top)

	-- ── movement zones, in the same space ───────────────────────────────────
	-- Anchored to the DISPLAY, because that is what the engine anchors them to,
	-- and clamped into nothing: a control that sits under the notch is the
	-- engine's business, not ours. We only have to stay clear of them.
	local jumpSize = minAxis <= 500 and 70 or 120
	local jumpLeft = display.Right - (jumpSize * 1.5 - 10)
	local jumpTop = display.Bottom - jumpSize - (minAxis <= 500 and 20 or jumpSize * .75)

	-- Our own control cluster: JUMP / RUN / SNEAK / GLOW / POV / FLASHLIGHT.
	-- Declared here so every HUD script reserves the same rectangle instead of
	-- each guessing, and DERIVED FROM THE SHIPPING CLUSTER -- the proxy below is
	-- the union of the very slots NoiseReporter and FlashlightController position
	-- their buttons from, so a cluster that reflows takes its reservation with it.
	--
	-- Converted through the SAFE rect, not the display's. A default ScreenGui is
	-- inset to CoreUISafeInsets, so `UDim2.new(1, -22, 1, -22)` on a notched phone
	-- resolves 62px left of the display's right edge, and a proxy anchored to the
	-- display sat that far right of the buttons it claimed to describe. The zone
	-- still REACHES the physical corner, matching what the measured branch does
	-- with its own union, so nothing that dodges it can slip down the outside.
	local tabletControls = class == "tablet"
	local plan = columnControlPlan(tabletControls)

	local function planZone(source): any
		local left, top = math.huge, math.huge
		for _, key in ipairs(source.Order) do
			local slot = source.Slots[key]
			left = math.min(left, safe.Right - slot.Right - slot.Width)
			top = math.min(top, safe.Bottom - slot.Bottom - slot.Height)
		end
		return {
			Left = left - CONTROL_CUSHION,
			-- Never above the display's own top. A viewport short enough for the
			-- column to be taller than the whole safe area would otherwise report a
			-- cluster starting off-screen, and every band derived from it collapses
			-- to nothing rather than to something small.
			Top = math.max(display.Top, top - CONTROL_CUSHION),
			Right = math.max(display.Right, safe.Right),
			Bottom = math.max(display.Bottom, safe.Bottom),
			Measured = false,
		}
	end

	-- What an objective readout at the safe right edge would actually get above a
	-- cluster shaped like this: the room down to whichever of the cluster and the
	-- engine's own jump button starts higher. TopRightPanel arrives at the same
	-- limit from the other end; asking it HERE, in advance, is what lets the
	-- arrangement be chosen to satisfy the readout instead of the readout being
	-- moved to survive the arrangement.
	local function objectiveHeadroom(zone): number
		return math.min(zone.Top, jumpTop) - OBJECTIVE_GUTTER
			- (safe.Top + OBJECTIVE_MARGIN)
	end

	local controls = planZone(plan)
	-- A SCREEN-OWNING MODAL HIDES THE CLUSTER, so there is nothing to reserve.
	-- C_NO_CONTROLS_IS_NOT_A_PROXY_20260831, the other half: the measured branch
	-- learns this by finding nothing drawn, but a SYNTHETIC fixture never reaches
	-- that branch -- the live buttons are laid out for the host window and say
	-- nothing about a simulated one -- so a fixture kept reserving the cluster
	-- under a modal that had just put it away. That is what pushed CREATE PARTY
	-- out of the party dialog on the three short landscape rows: the dialog was
	-- dodging a control column that, with the dialog open, does not exist.
	-- NoiseReporter and FlashlightController both stand down on exactly this
	-- predicate, so the zone and the buttons now agree by construction.
	-- Guarded because computeLayout runs once at module load, before the function
	-- table is fully populated; at that moment no modal can be open anyway.
	local modalOwnsTheScreen = touchFormFactor
		and UIDevice.ScreenOwningModalOpen ~= nil
		and UIDevice.ScreenOwningModalOpen()
	if modalOwnsTheScreen then
		controls = {
			Left = display.Right, Right = display.Right,
			Top = display.Bottom, Bottom = display.Bottom,
			Measured = false, Count = 0,
		}
		-- ...AND ROBLOX'S OWN JUMP BUTTON, for the same reason. A screen-owning
		-- modal suppresses movement through the engine's ControlModule, which
		-- takes the default jump with it -- so reserving its corner reserves a
		-- button that is not on screen either. Leaving it reserved simply moved
		-- the party dialog's collision from the Controls zone to the Jump zone.
		jumpLeft, jumpTop, jumpSize = display.Right, display.Bottom, 0
	end
	-- SHORT SCREEN: the vertical stack and a legible readout cannot both fit, so
	-- the cluster gives way and lies along the bottom edge. LANDSCAPE ONLY -- in
	-- portrait the thumbstick's activation region is the full width of the bottom
	-- 40%, so there is no bottom edge to lay a row along; portrait screens are
	-- also the tall ones and have never been short.
	if touchFormFactor and not portrait
		and objectiveHeadroom(controls) < MINIMUM_USABLE_HEIGHT then
		local usable = safe.Right
			- math.max(safe.Left, display.Left + width * .4 + THUMBSTICK_CLEARANCE)
		local rowed = rowControlPlan(tabletControls, usable)
		if rowed then
			local rowZone = planZone(rowed)
			-- Only if it actually buys the readout its height. A row that does not
			-- is churn, and the column is the arrangement players know.
			if objectiveHeadroom(rowZone) >= MINIMUM_USABLE_HEIGHT then
				plan, controls = rowed, rowZone
			end
		end
	end

	-- MEASURED wherever the controls have registered themselves. A synthetic
	-- fixture keeps the proxy on purpose: the live buttons are laid out for the
	-- REAL window, so their rectangles say nothing about the simulated one. So
	-- does a pointer device, where the only registered rectangle is the desktop
	-- torch in the bottom-LEFT corner, which is not a movement control at all.
	if not synthetic and touchFormFactor then
		local union = measuredControlUnion()
		-- A ONE-FRAME-STALE UNION IS NOT THE CLUSTER. The buttons and every HUD
		-- that dodges them all relayout from the same UIDevice.Changed, in
		-- connection order, so a consumer that runs first measures the cluster
		-- as it was laid out for the PREVIOUS form factor -- and on the frame
		-- the touch controls first become visible that can be the origin. It was
		-- not theoretical: entering a round on a 831x418 handheld produced a
		-- union at x 0, which left the Zyntra opener the `math.max(1, ...)` of
		-- its own available-width arithmetic and drew a 1-pixel-wide button.
		--
		-- The cluster is bottom-right-anchored by construction, inside exactly
		-- the rectangle the proxy reserves, so a union that does not reach that
		-- rectangle has not been laid out for this display yet and the proxy
		-- stands for one more frame.
		--
		-- The VERTICAL floor is deliberately looser than the proxy's own top. The
		-- lobby lifts RUN clear of Roblox's own jump button, and in the row
		-- arrangement that puts the entire drawn cluster ABOVE a 67px-tall proxy
		-- -- a legitimate layout that the proxy's top would reject for ever,
		-- leaving the zone describing a rectangle the lifted button is not in.
		local staleTop = math.min(controls.Top,
			jumpTop - plan.Gap - plan.Cell - CONTROL_CUSHION)
		if union and (union.Right < controls.Left or union.Bottom < staleTop) then
			union = nil
		end
		if union then
			local MARGIN = 8
			controls = {
				Left = union.Left - MARGIN,
				Right = math.max(union.Right + MARGIN, display.Right),
				Top = union.Top - MARGIN,
				Bottom = math.max(union.Bottom + MARGIN, display.Bottom),
				Measured = true,
				Count = union.Count,
			}
		elseif registeredControlCount() > 0 then
			-- C_NO_CONTROLS_IS_NOT_A_PROXY_20260831 -- WHAT SHIPPED BROKEN.
			--
			-- The proxy's stated job is to answer before anything has registered:
			-- module load, the first frames of a session. It was ALSO the answer
			-- whenever the cluster was registered and legitimately not drawn --
			-- in the lobby, out of a round, and under any screen-owning modal --
			-- so every HUD went on dodging a block of controls that were not on
			-- screen. On a 568x320 phone with the short-screen ROW arrangement
			-- that block is the whole bottom strip, and it is what pushed the
			-- party dialog's CREATE PARTY button out of its own modal: measured,
			-- QueueModalOpen=true, no control drawn, and Zones.Controls still
			-- reserving (228,209)-(568,284).
			--
			-- Registered but nothing drawn is not "I do not know yet". It is a
			-- definite answer, and the answer is that there is nothing there.
			-- Zero-area, pinned to the bottom-right corner so any consumer that
			-- reads .Top or .Left as a limit gets "no limit" rather than a
			-- rectangle to avoid.
			controls = {
				Left = display.Right, Right = display.Right,
				Top = display.Bottom, Bottom = display.Bottom,
				Measured = true, Count = 0,
			}
		end
	end

	-- Roblox's dynamic thumbstick ACTIVATION region: the left 40% of the bottom
	-- two thirds in landscape, the whole width of the bottom 40% in portrait.
	-- Fractions of the DISPLAY, not of a partly-inset viewport -- the old form
	-- put its top 39px lower than the engine's own, which made the band above
	-- it look bigger than it is.
	local thumbstick = {
		Left = display.Left,
		Right = portrait and controls.Left
			or math.min(display.Left + width * .4, controls.Left),
		Top = display.Top + height * (portrait and .6 or (1 / 3)),
		Bottom = display.Bottom,
	}
	if modalOwnsTheScreen then
		-- THE THIRD ZONE, and the model is now complete: a screen-owning modal
		-- calls UIDevice.SuppressTouchMovement, which disables the engine's
		-- ControlModule -- and that takes the dynamic thumbstick, the default
		-- jump and our own cluster with it. All three regions describe controls
		-- that are not on screen, so all three are empty.
		--
		-- THIS IS ONLY HONEST BECAUSE THE SUPPRESSION IS ASSERTED. Emptying the
		-- zones is what makes "the modal does not overlap a movement control"
		-- trivially true, so the claim that licenses it -- that movement really
		-- is suppressed while the modal is up, and really comes back when it
		-- closes -- is checked directly by QueueModalMatrix and ControlZoneMatrix
		-- rather than assumed here. Without those rows this block would be a way
		-- of not testing something.
		thumbstick = {
			Left = display.Right, Right = display.Right,
			Top = display.Bottom, Bottom = display.Bottom,
		}
	end

	-- ── HUD rectangles, all CONTAINED BY SAFE ───────────────────────────────
	-- Every one of these used to start at a literal x = 12 regardless of where
	-- the safe area began, so on a device with a horizontal housing the band
	-- and every panel pinned to it started inside the notch.
	local GUTTER = 12
	local bandLeft = safe.Left + GUTTER
	local bandRight = safe.Right - GUTTER
	local bandTop = safe.Top + 8

	local corridor = {
		Left = math.max(bandLeft, thumbstick.Right + 8),
		Right = math.min(bandRight, controls.Left - 8),
	}
	corridor.Width = math.max(0, corridor.Right - corridor.Left)

	-- The largest axis-aligned rectangle clear of BOTH movement zones. Two
	-- candidates, chosen by area because which one wins is genuinely
	-- orientation dependent:
	--   A) FULL SAFE WIDTH, down to whichever zone starts higher. Portrait.
	--   B) FULL HEIGHT above the thumbstick, stopping at the control column.
	--      Landscape, where the column reaches nearly to the top.
	local candidateA = {
		Left = bandLeft,
		Right = bandRight,
		Top = bandTop,
		Bottom = math.min(thumbstick.Top, controls.Top) - 10,
	}
	local candidateB = {
		Left = bandLeft,
		Right = math.min(bandRight, controls.Left - 8),
		Top = bandTop,
		Bottom = thumbstick.Top - 10,
	}
	local function rectArea(rect)
		return math.max(0, rect.Right - rect.Left) * math.max(0, rect.Bottom - rect.Top)
	end
	local topBand = rectArea(candidateA) >= rectArea(candidateB) and candidateA or candidateB
	-- Clamp into safe on every edge, so "inside the band" implies "inside safe".
	topBand.Left = math.max(topBand.Left, safe.Left)
	topBand.Right = math.min(topBand.Right, safe.Right)
	topBand.Top = math.max(topBand.Top, safe.Top)
	topBand.Bottom = math.min(topBand.Bottom, safe.Bottom)
	topBand.Width = math.max(0, topBand.Right - topBand.Left)
	topBand.Height = math.max(0, topBand.Bottom - topBand.Top)

	local contentBottom, contentRight
	if touchFormFactor then
		contentBottom = topBand.Bottom
		contentRight = topBand.Right
	else
		contentBottom = safe.Bottom - GUTTER
		contentRight = safe.Right - GUTTER
	end

	-- Where a MODAL that does NOT take input away may live: the largest
	-- rectangle clear of every movement affordance at once, inside safe.
	local MODAL_GUTTER = 8
	local function clearsZones(rect): boolean
		if not touchFormFactor then return true end
		for _, zone in ipairs({thumbstick, controls,
			{Left = jumpLeft, Right = jumpLeft + jumpSize,
			 Top = jumpTop, Bottom = jumpTop + jumpSize}}) do
			if rect.Left < zone.Right and rect.Right > zone.Left
				and rect.Top < zone.Bottom and rect.Bottom > zone.Top then
				return false
			end
		end
		return true
	end
	-- C_MODAL_LANE_FOLLOWS_THE_CLUSTER_20260831 -- WHAT SHIPPED BROKEN.
	--
	-- These three candidates were written for a cluster that is a COLUMN up the
	-- right edge, and the third one is the good one: the tall lane between the
	-- thumbstick's activation edge and the column. The short-landscape reflow
	-- lays the cluster out as a ROW along the bottom instead, and that lane
	-- closes -- `controls.Left` moves left of `thumbstick.Right`, so candidate
	-- three resolves to a negative width. What was left was candidate one, the
	-- full-width strip above the thumbstick's own top edge: 544x33 on a 568x320
	-- phone. Level 2's announcement takes ModalArea as its home when the top band
	-- cannot hold its copy, clamps its own height to that home, and does not clip
	-- its labels -- so the three authored lines rendered 30px outside the panel,
	-- across the HUD. Measured live before the fix: panel (12,8)-(314,40), copy
	-- running to y 70.
	--
	-- The lane still exists when the cluster is a row; it is just ABOVE it rather
	-- than beside it. That is the fourth candidate. Jump is folded into both
	-- bottoms because it is anchored independently of the other two zones and a
	-- candidate that reaches into it is discarded outright by clearsZones rather
	-- than shortened -- which is how a rectangle that only needed to stop 8px
	-- higher became no rectangle at all. On 568x320 this restores a 321x156 home,
	-- and the announcement fits inside it with room to spare.
	local modalCandidates = {
		{Left = bandLeft, Right = bandRight, Top = bandTop,
		 Bottom = math.min(thumbstick.Top, controls.Top, jumpTop) - MODAL_GUTTER},
		{Left = bandLeft, Right = controls.Left - MODAL_GUTTER, Top = bandTop,
		 Bottom = thumbstick.Top - MODAL_GUTTER},
		{Left = math.max(bandLeft, thumbstick.Right + MODAL_GUTTER),
		 Right = math.min(bandRight, controls.Left - MODAL_GUTTER),
		 Top = bandTop, Bottom = safe.Bottom - MODAL_GUTTER},
		-- The row cluster's lane: right of the thumbstick, above the controls.
		{Left = math.max(bandLeft, thumbstick.Right + MODAL_GUTTER),
		 Right = bandRight, Top = bandTop,
		 Bottom = math.min(controls.Top, jumpTop) - MODAL_GUTTER},
	}
	if not touchFormFactor then
		modalCandidates = {{Left = bandLeft, Right = bandRight, Top = bandTop,
			Bottom = safe.Bottom - MODAL_GUTTER}}
	end
	local modalArea
	for _, candidate in ipairs(modalCandidates) do
		candidate.Left = math.max(candidate.Left, safe.Left)
		candidate.Right = math.min(candidate.Right, safe.Right)
		candidate.Top = math.max(candidate.Top, safe.Top)
		candidate.Bottom = math.min(candidate.Bottom, safe.Bottom)
		candidate.Width = math.max(0, candidate.Right - candidate.Left)
		candidate.Height = math.max(0, candidate.Bottom - candidate.Top)
		if clearsZones(candidate)
			and (modalArea == nil
				or candidate.Width * candidate.Height > modalArea.Width * modalArea.Height) then
			modalArea = candidate
		end
	end
	if modalArea == nil then
		modalArea = {Left = bandLeft, Right = bandRight, Top = bandTop,
			Bottom = safe.Bottom - MODAL_GUTTER}
		modalArea.Width = math.max(0, modalArea.Right - modalArea.Left)
		modalArea.Height = math.max(0, modalArea.Bottom - modalArea.Top)
	end
	modalArea.Fits = modalArea.Width >= 200 and modalArea.Height >= 240

	-- Where a modal that DOES take input away may live: the whole safe area.
	-- The movement cluster stands down underneath it, so there is nothing left
	-- to dodge. This is what the Zyntra terminal is measured against; sizing it
	-- from the HUD band is what collapsed it.
	local modalViewport = {
		Left = safe.Left + GUTTER,
		Top = safe.Top + 8,
		Right = safe.Right - GUTTER,
		Bottom = safe.Bottom - 8,
	}
	modalViewport.Width = math.max(0, modalViewport.Right - modalViewport.Left)
	modalViewport.Height = math.max(0, modalViewport.Bottom - modalViewport.Top)
	modalViewport.Fits = modalViewport.Width >= 240 and modalViewport.Height >= 180

	return {
		Viewport = viewport,
		Width = width,
		Height = height,
		Portrait = portrait,
		Class = class,
		IsTouch = touchFormFactor,
		Inset = inset,
		-- Narrow is the old per-file breakpoint, unified. Level 2's alert client
		-- used 700 and the Level 3 reader used 900; 760 sits between them and is
		-- the width below which a full-width panel stops being readable.
		Narrow = width < 760,
		SafeTop = bandTop,
		SafeBottom = contentBottom,
		SafeLeft = bandLeft,
		SafeRight = contentRight,
		Corridor = corridor,
		TopBand = topBand,
		ModalArea = modalArea,
		-- The whole display, the authoritative safe area inside it, and the
		-- rectangle a screen-owning modal may occupy. All in the one space.
		Display = display,
		Safe = safe,
		-- The four rectangles a ScreenGui gets, one per Enum.ScreenInsets value,
		-- keyed by the enum item's Name. On a real device they are GuiService's own
		-- answers; under a fixture they are derived from the row's stated geometry
		-- alone. TopbarSafeInsets is the topbar's OWN BAND -- a short strip inset
		-- from the left -- not the screen less a top margin. Read them through
		-- UIDevice.InsetArea so a caller never has to know which kind of layout it
		-- is holding.
		InsetAreas = insetAreas,
		-- Whether this layout describes a real device or a forced-viewport
		-- fixture. The two are different spaces and a test has to say which one
		-- it is asserting against.
		Synthetic = synthetic,
		SafeInsets = {Left = insetLeft, Top = insetTop,
			Right = insetRight, Bottom = insetBottom},
		ModalViewport = modalViewport,
		-- The cluster's slots, so the two scripts that BUILD it position their
		-- buttons from the same table this module reserved the zone from. Present
		-- on every layout, touch or not; the pointer branch of each caller ignores
		-- it and keeps its own desktop composition.
		ControlPlan = plan,
		Zones = {
			Thumbstick = thumbstick,
			Controls = controls,
			Jump = {
				Left = jumpLeft,
				Right = jumpLeft + jumpSize,
				Top = jumpTop,
				Bottom = jumpTop + jumpSize,
				Size = jumpSize,
			},
		},
	}
end

function UIDevice.Layout(): any
	if not layout then layout = computeLayout() end
	return layout
end

-- What rectangle a ScreenGui set to `kind` is given, in the one space this
-- module speaks. Equal to GuiService:GetInsetArea(kind) on a real device, and
-- to the fixture's own stated geometry under a forced viewport -- where the
-- engine's answer describes the HOST window and is therefore the wrong number
-- by construction. Defaults to None, which is the whole display.
--
-- The returned table is {Left, Top, Right, Bottom, Width, Height}, the same
-- shape as Display and Safe. Deliberately not a Rect: see
-- C_INSET_TRANSPORT_IS_EXACT_20260831.
function UIDevice.InsetArea(kind: Enum.ScreenInsets?): any
	local areas = UIDevice.Layout().InsetAreas
	local name = (kind or Enum.ScreenInsets.None).Name
	return areas[name] or areas.None
end

-- Does a candidate rectangle collide with a movement-control zone?
-- Callers use this in assertions and in the regression harness; the layout
-- helpers below are what production code normally needs.
function UIDevice.OverlapsMovementZone(left: number, top: number, right: number, bottom: number): string?
	if not touchFormFactor then return nil end
	local zones = UIDevice.Layout().Zones
	for _, name in ipairs({"Thumbstick", "Controls", "Jump"}) do
		local zone = zones[name]
		if left < zone.Right and right > zone.Left
			and top < zone.Bottom and bottom > zone.Top then
			return name
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- The upper-right objective anchor
-- ---------------------------------------------------------------------------

-- ONE answer to "where does a persistent objective readout go on a handheld?",
-- shared by Level 1 (PuzzleUI), Level 2 (Level 2 Objective UI) and Level 3
-- (the exit reader), so the three cannot drift apart again.
--
-- WHAT SHIPPED BROKEN: they had three different answers. Level 1 used the
-- CORRIDOR between the two movement zones (bottom-centre on a landscape
-- phone), Level 2 used the same corridor and fell back to the bottom of the
-- top band, and Level 3 used the top LEFT. None of them was the upper right,
-- none agreed with the others, and the corridor placements sat directly under
-- the player's thumbs in the middle of the screen.
--
-- The rule, stated once:
--   * TOP is the safe area's own top, one margin down. Never the band, never a
--     fraction of the viewport.
--   * RIGHT is the safe area's own right edge, one margin in. Always, on every
--     touch device -- there is no arrangement in which the readout steps left of
--     the movement cluster, because the cluster reflows along the bottom edge
--     instead (see C_SHORT_SCREEN_CLUSTER_20260831). UsesScreenEdge is therefore
--     always true on touch; it survives in the return because the desktop and
--     touch compositions still differ and callers branch on it.
--   * The returned height is what actually fits, so a caller that asks for
--     more than the device has gets a smaller panel rather than one hanging
--     over the thumbstick.
--
-- Desktop keeps its own composition: the helper answers for it (top right,
-- full safe height) but the level HUDs that authored a bottom-right desktop
-- layout deliberately do not call it there.
function UIDevice.TopRightPanel(desiredWidth: number, desiredHeight: number): any
	local info = UIDevice.Layout()
	local safe = info.Safe
	local margin = info.IsTouch and OBJECTIVE_MARGIN or 18
	local top = safe.Top + margin

	if not info.IsTouch then
		local right = safe.Right - margin
		local width = math.min(desiredWidth, math.max(0, right - (safe.Left + margin)))
		local height = math.min(desiredHeight, math.max(0, (safe.Bottom - margin) - top))
		return {
			Left = right - width, Top = top, Right = right, Bottom = top + height,
			Width = width, Height = height, UsesScreenEdge = true,
		}
	end

	local zones = info.Zones

	-- C_OBJECTIVE_KEEPS_THE_SAFE_EDGE_20260831 -- WHAT SHIPPED BROKEN.
	--
	-- This used to pick between three candidates BY AREA, and area is the wrong
	-- judge for this control. A tall column scored best by stepping LEFT to the
	-- control column's edge, so on a 956x440 iPhone the objective readout sat
	-- with its right edge at x 780 -- 117px short of the safe right edge, a
	-- sixth of the screen adrift of the corner it is supposed to occupy -- and
	-- on 568x320 it was narrowed to a 157px ribbon in the middle of the screen.
	-- Both were "clear of the movement zones" and neither was the upper-right
	-- corner the product asks for.
	--
	-- The rule is now stated rather than optimised: THE RIGHT EDGE IS THE SAFE
	-- RIGHT EDGE. What gives instead is HEIGHT -- the panel is only as tall as
	-- the space above the control cluster, which is what the owner asked for
	-- ("make the objective short enough to sit above them"). And the cluster's
	-- top is MEASURED from the real registered buttons wherever they are drawn
	-- (Zones.Controls.Measured), so in a live round the panel gets its full
	-- authored height at the corner instead of dodging a 290px-tall guess.
	--
	-- C_OBJECTIVE_ALWAYS_THE_SAFE_EDGE_20260831 -- and this is where the rule
	-- finally became unconditional.
	--
	-- Stepping left survived here as a "last resort" for a screen where the space
	-- above the controls could not hold a legible readout. It was not a last
	-- resort: on a 568x320 landscape phone the safe area is 262px tall and the
	-- vertical control stack reserved 250 of it, so the branch fired on an
	-- ordinary handheld and put the objective readout in the middle of the screen
	-- -- the exact placement the rule above exists to forbid. The composition, not
	-- the anchor, was wrong, and it is fixed where it was wrong: computeLayout now
	-- lays the cluster along the bottom edge when the column cannot leave
	-- MINIMUM_USABLE_HEIGHT above it, and only offers that arrangement when it
	-- does. So the contract here is now flat, and callers can rely on it:
	--
	--   ON TOUCH, Right IS ALWAYS Safe.Right - margin, and UsesScreenEdge is
	--   ALWAYS true. What varies is HEIGHT.
	--
	-- The zero-height case is unreachable rather than unhandled -- the arrangement
	-- is chosen against this same headroom -- but it is not GUARDED against
	-- either, because the honest answer to "the cluster ate the screen" is a
	-- shorter panel in the right corner, never a panel somewhere else.
	local gutterBelow = OBJECTIVE_GUTTER

	local function build(right: number, bottomLimit: number)
		local width = math.min(desiredWidth, math.max(0, right - (safe.Left + margin)))
		local left = right - width
		local limit = bottomLimit
		-- Only a column that actually reaches LEFT of the thumbstick's
		-- activation edge has to stop above it.
		if left < zones.Thumbstick.Right then
			limit = math.min(limit, zones.Thumbstick.Top - gutterBelow)
		end
		if right > zones.Jump.Left and left < zones.Jump.Right then
			limit = math.min(limit, zones.Jump.Top - gutterBelow)
		end
		local height = math.min(desiredHeight, math.max(0, limit - top))
		return {
			Left = left, Top = top, Right = right, Bottom = top + height,
			Width = width, Height = height, UsesScreenEdge = true,
		}
	end

	-- THE ANSWER: the safe right edge, as tall as the room above the control
	-- cluster allows. There is no second candidate and no choice by area.
	return build(safe.Right - margin, zones.Controls.Top - gutterBelow)
end

-- The footprint each level's persistent objective readout asks for, declared
-- HERE rather than only inside the file that draws it. A panel that shares the
-- top band with one of them -- the Level 2 completion alert is the only one --
-- has to reserve the same rectangle, and reserving it from a copied literal is
-- how two files drift apart. Level 1's panel is content-sized and so is absent:
-- PuzzleUI calls TopRightPanel directly with the height its visible rows need,
-- and no other panel shares Level 1's band.
UIDevice.ObjectivePanelSize = {
	[2] = Vector2.new(236, 78),
	[3] = Vector2.new(248, 101),
}

-- The rectangle a level's objective readout occupies on touch, for the level
-- itself and for anything that must stay clear of it.
function UIDevice.ObjectiveColumn(level: number): any
	local size = UIDevice.ObjectivePanelSize[level] or Vector2.new(236, 78)
	return UIDevice.TopRightPanel(size.X, size.Y)
end

-- ---------------------------------------------------------------------------
-- Movement suppression under a screen-owning modal
-- ---------------------------------------------------------------------------

-- The game's OWN cluster already stands down on ZyntraStoreOpen (NoiseReporter,
-- FlashlightController). Roblox's dynamic thumbstick did not: its activation
-- region is the left 40% of the bottom two thirds, so a full-screen modal was
-- being dragged around by every finger that landed on its left half.
--
-- PlayerModule's ControlModule is the documented way to stand the engine's own
-- controls down, and it is reversible. Touch only: a desktop modal has never
-- taken movement away and starting now would be a regression.
local controlModule: any = nil
local movementSuppressed = false
-- What the last caller ASKED for, regardless of whether the form factor
-- allowed it to be applied. See UIDevice.SuppressTouchMovement.
local movementIntent: boolean? = nil

local function resolveControlModule(): any
	if controlModule then return controlModule end
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, resolved = pcall(function()
		return require(module):GetControls()
	end)
	if ok then controlModule = resolved end
	return controlModule
end

-- PUBLISHED as a player attribute, not kept as a module local, and the reason
-- is not cosmetic. Studio's execute_luau -- which is what drives every device
-- matrix in this game -- runs in a SEPARATE require cache from the running
-- LocalScripts: a module required from there is a DIFFERENT table with its own
-- upvalues. Proved directly, by replacing UIDevice.Layout on the harness-side
-- table and invoking the store's own relayout probe: it called the patched
-- function zero times. So a module-local boolean is unobservable to the
-- harness. The attribute is written only after the engine call actually
-- succeeded, so it reports what IS, never what was intended.
local MOVEMENT_ATTRIBUTE = "TouchMovementSuppressed"

local function publishMovementSuppression()
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute(MOVEMENT_ATTRIBUTE, movementSuppressed or nil)
	end
end

function UIDevice.SuppressTouchMovement(active: boolean)
	-- The CALLER'S INTENT is remembered separately from what was applied.
	-- Suppression is touch-only, so a modal opened on a desktop applies nothing
	-- -- and if that device then becomes a touch form factor while the modal is
	-- still up (a mouse unplugged, a keyboard undocked), the suppression has to
	-- be applied late. UIDevice.Changed re-invokes this with the remembered
	-- intent for exactly that transition; without it a modal opened before the
	-- flip kept a live thumbstick underneath it for the rest of its life.
	movementIntent = active == true
	local wanted = active == true and touchFormFactor
	if wanted == movementSuppressed then
		-- Already in the wanted state, but the flag may never have been written
		-- (first call, or a player that arrived after the last one).
		publishMovementSuppression()
		return
	end
	local controls = resolveControlModule()
	if not controls then return end
	local ok = pcall(function()
		if wanted then controls:Disable() else controls:Enable() end
	end)
	if ok then
		movementSuppressed = wanted
		publishMovementSuppression()
	end
end

-- Whether the engine's movement controls are currently standing down. Read by
-- the regression matrix, which must be able to say so rather than assume it --
-- hence the attribute rather than the upvalue.
function UIDevice.TouchMovementSuppressed(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute(MOVEMENT_ATTRIBUTE) == true
end

-- ---------------------------------------------------------------------------
-- Screen-owning modals
-- ---------------------------------------------------------------------------

-- The modals that OWN the screen while they are up, named once so every HUD
-- yields to the same list instead of each keeping its own.
--
-- WHAT SHIPPED BROKEN: only the dispatch briefing had a published flag every
-- HUD honoured. The Zyntra terminal (DisplayOrder 55) and the lobby queue modal
-- published theirs and nothing on Levels 1-3 read them -- so the Level 2 alert
-- (DisplayOrder 80) and the Level 1 guide (110) both PAINTED OVER an open
-- terminal and, being Active, took the taps meant for it. Raising the
-- terminal's DisplayOrder would have fixed the painting and not the input; the
-- HUD standing down fixes both, and is what the briefing already did.
local SCREEN_OWNING_MODALS = {
	"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen",
}

function UIDevice.ScreenOwningModalOpen(): boolean
	local player = Players.LocalPlayer
	if not player then return false end
	for _, attribute in ipairs(SCREEN_OWNING_MODALS) do
		if player:GetAttribute(attribute) == true then return true end
	end
	return false
end

-- Run `callback` whenever that answer can have changed.
function UIDevice.OnScreenOwningModalChanged(callback: () -> ())
	local player = Players.LocalPlayer
	if not player then return end
	for _, attribute in ipairs(SCREEN_OWNING_MODALS) do
		player:GetAttributeChangedSignal(attribute):Connect(callback)
	end
end

-- ---------------------------------------------------------------------------
-- Converting the one space into a ScreenGui's local offsets
-- ---------------------------------------------------------------------------

-- Every rectangle Layout() returns is in the space described at the top of the
-- layout section -- the space GetInsetArea and AbsolutePosition share. A
-- ScreenGui's children are positioned in offsets from that gui's own origin,
-- and that origin IS its AbsolutePosition, for every ScreenInsets setting.
-- So the conversion is one subtraction per axis, and it is exact.
--
-- WHAT SHIPPED BROKEN: this used to be `TopOffsetFor`, a Y-ONLY helper, and it
-- subtracted the wrong quantity as well. Every caller passed an absolute Y and
-- an unconverted X, so a panel on a device with a horizontal safe inset was
-- placed at the right height and the wrong column; and because the Y term was
-- an inset out in both directions, every touch panel also sat one topbar lower
-- than the rectangle it had been fitted to.
-- C_GUI_ORIGIN_FOLLOWS_THE_FIXTURE_20260831 -- WHAT SHIPPED BROKEN.
--
-- Every HUD in this game converts an absolute point into a child offset through
-- here, and this read the gui's LIVE AbsolutePosition. Under a synthetic
-- fixture that is the wrong space: the engine still renders at the host window,
-- so a ScreenGui at ScreenInsets.None reports the HOST's display origin -- on
-- the Device Emulator, y = -58 -- while the fixture's own display top is
-- wherever the row's stated topbar puts it, y = -36 for a row stating a 36px
-- bar. Production therefore placed the Level 1 objective panel 22px from a
-- corner the fixture said was somewhere else, and the regression that resolved
-- the same panel from the fixture's geometry measured it at y 30 against a safe
-- top of 8 and called the corner wrong. The panel was correct; the two halves
-- were speaking different coordinate systems.
--
-- The layout module already answers "what rectangle does a ScreenGui of this
-- ScreenInsets occupy" for both worlds -- InsetArea is GuiService on a real
-- device and the row's own geometry under a fixture. Ask it, and the conversion
-- is consistent with whatever space the rest of the layout is in.
--
-- On a real device this is EXACTLY AbsolutePosition (verified: a ScreenGui's
-- AbsolutePosition equals GetInsetArea(gui.ScreenInsets).Min for all four enum
-- values), so nothing about shipping behaviour changes.
local function guiOrigin(screenGui: ScreenGui?): Vector2
	if not screenGui then return Vector2.zero end
	if forcedViewport() == nil then return screenGui.AbsolutePosition end
	local area = UIDevice.InsetArea(screenGui.ScreenInsets)
	return Vector2.new(area.Left, area.Top)
end

-- Convert an absolute point into the offsets a top-left-anchored child of this
-- ScreenGui needs. Returns two numbers so callers cannot use one and forget
-- the other.
function UIDevice.LocalOffset(screenGui: ScreenGui?, x: number, y: number): (number, number)
	local origin = guiOrigin(screenGui)
	return x - origin.X, y - origin.Y
end

function UIDevice.LocalPosition(screenGui: ScreenGui?, x: number, y: number): UDim2
	local lx, ly = UIDevice.LocalOffset(screenGui, x, y)
	return UDim2.fromOffset(math.floor(lx), math.floor(ly))
end

-- The distance from this gui's own bottom edge up to an absolute Y, for a
-- bottom-anchored child: Position = UDim2.new(_, _, 1, -offset).
function UIDevice.BottomOffsetFor(screenGui: ScreenGui?, absoluteY: number): number
	if not screenGui then
		return math.max(0, UIDevice.Layout().Display.Bottom - absoluteY)
	end
	-- Same fixture hazard as guiOrigin: the gui's live rectangle is the HOST's.
	local bottom
	if forcedViewport() == nil then
		bottom = screenGui.AbsolutePosition.Y + screenGui.AbsoluteSize.Y
	else
		bottom = UIDevice.InsetArea(screenGui.ScreenInsets).Bottom
	end
	return math.max(0, bottom - absoluteY)
end

-- The distance from this gui's own right edge left to an absolute X, for a
-- right-anchored child.
function UIDevice.RightOffsetFor(screenGui: ScreenGui?, absoluteX: number): number
	if not screenGui then
		return math.max(0, UIDevice.Layout().Display.Right - absoluteX)
	end
	local right
	if forcedViewport() == nil then
		right = screenGui.AbsolutePosition.X + screenGui.AbsoluteSize.X
	else
		right = UIDevice.InsetArea(screenGui.ScreenInsets).Right
	end
	return math.max(0, right - absoluteX)
end

-- ---------------------------------------------------------------------------
-- Default jump suppression
-- ---------------------------------------------------------------------------

-- The game ships its own JUMP button next to RUN and GLOW, with round/death/
-- hiding gating the default control knows nothing about. Roblox's TouchGui sits
-- at DisplayOrder 5 and ours used to sit at 0, so there were literally two jump
-- buttons stacked and the default one -- ungated -- received every tap.
--
-- Rather than fight for z-order, the default button is hidden whenever our
-- cluster is the owner. TouchGui is rebuilt whenever the control scheme changes
-- (a gamepad is plugged in, DevTouchMovementMode changes), so this re-applies
-- on PlayerGui.ChildAdded rather than caching a reference.
local suppressDefaultJump = false
local jumpWatchStarted = false

local function applyJumpSuppression()
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if not jump or not jump:IsA("GuiObject") then return end
	jump.Visible = not suppressDefaultJump
	jump.Active = not suppressDefaultJump
end

local function startJumpWatch()
	if jumpWatchStarted then return end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	-- Latch only once the watch is genuinely established. Setting the flag
	-- first meant a caller that ran before PlayerGui existed would mark the
	-- watch as started without connecting anything, and every later call would
	-- short-circuit -- permanently disabling jump suppression.
	if not playerGui then return end
	jumpWatchStarted = true
	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "JumpButton" then
			task.defer(applyJumpSuppression)
		end
	end)
	task.defer(applyJumpSuppression)
end

-- Ask UIDevice to hide Roblox's own touch jump button, because this game draws
-- its own. Idempotent; safe to call before TouchGui exists.
function UIDevice.SuppressDefaultJump(active: boolean)
	suppressDefaultJump = active == true
	startJumpWatch()
	applyJumpSuppression()
end

-- ---------------------------------------------------------------------------
-- Interactivity
-- ---------------------------------------------------------------------------

-- Hiding a control is not enough: a TextButton left Active keeps eating taps
-- through a transparent background, which is how an invisible flashlight
-- hitbox ended up stealing from the movement stick. Always route visibility
-- changes for interactive elements through here.
-- Remember a boolean that describes what a control IS, so that toggling its
-- availability cannot destroy it. Reading the live property each time would
-- latch whatever the last disable wrote.
local function rememberedFlag(element: GuiObject, key: string, current: boolean): boolean
	local stored = element:GetAttribute(key)
	if stored == nil then
		stored = current
		element:SetAttribute(key, stored)
	end
	return stored == true
end

-- Disable a control WITHOUT hiding it: it stays legible (and keeps reporting
-- its state to the player) but stops taking input. Use this where the label
-- itself is the message -- "SAVING", "LOADING", "DISPATCH OFFLINE" -- and
-- SetInteractive where the control has nothing to say while unavailable.
function UIDevice.SetEnabled(element: GuiObject, enabled: boolean)
	if not (element:IsA("TextButton") or element:IsA("ImageButton")) then return end
	element.Active = enabled
	element.Selectable = rememberedFlag(element, "UIDeviceSelectable", element.Selectable)
		and enabled
	element.Modal = rememberedFlag(element, "UIDeviceModal", element.Modal) and enabled
end

function UIDevice.SetInteractive(element: GuiObject, visible: boolean)
	element.Visible = visible
	if not (element:IsA("TextButton") or element:IsA("ImageButton")) then return end
	element.Active = visible
	-- Selectable and Modal both describe what the button IS, not whether it is
	-- currently shown, so both are remembered rather than recomputed. Writing
	-- Selectable unconditionally clobbered controls that deliberately opt out of
	-- gamepad selection (the flashlight's invisible hit target does).
	element.Selectable = rememberedFlag(element, "UIDeviceSelectable", element.Selectable)
		and visible
	-- Modal is remembered the same way. Writing
	-- `Modal = Modal and visible` looks equivalent but is destructive: the first
	-- hide latches it to false and showing the button again can never restore
	-- it, silently un-modalling a dialog after one hide/show cycle.
	element.Modal = rememberedFlag(element, "UIDeviceModal", element.Modal) and visible
end

-- ---------------------------------------------------------------------------
-- Change propagation
-- ---------------------------------------------------------------------------

-- What counts as "the layout changed". Size and topbar inset alone were not
-- enough: a device that rotates its sensor housing, or a client whose safe
-- area is reported late, moves the SAFE EDGES without moving the viewport, and
-- every panel is pinned to those edges. All four are compared.
local function sameRect(a, b): boolean
	if a == nil or b == nil then return a == b end
	return a.Left == b.Left and a.Top == b.Top
		and a.Right == b.Right and a.Bottom == b.Bottom
end

-- The CONTROL ZONE is part of "the layout changed", and its absence from this
-- comparison was the other half of C_CONTROL_ZONE_INVALIDATION_20260831: a
-- cluster that moved -- SNEAK appearing as a round starts, RUN lifting in the
-- lobby, a fixture untagging a button -- moves no viewport, no topbar and no
-- safe edge, so the recompute happened and then fired nothing, and every HUD
-- that dodges the zone kept dodging where it used to be. Measured and Count
-- count too: the same rectangle reached by a guess and by four real buttons is
-- not the same answer, and a consumer that trusts Measured has to be told.
local function sameControls(a, b): boolean
	if a == nil or b == nil then return a == b end
	return sameRect(a, b) and a.Measured == b.Measured
		and (a.Count or 0) == (b.Count or 0)
end

-- The four ScreenInsets rectangles are part of "the layout changed" too. Three
-- of them move with Display or Safe and would be caught anyway, but the TOPBAR
-- BAND is its own rectangle: its horizontal margins move without moving any
-- edge already compared here, so a fixture that changed only the band -- or a
-- host whose topbar widget resized -- would have recomputed and then fired
-- nothing, and every caller reading InsetAreas would have kept the old strip.
local INSET_AREA_KEYS = {"None", "DeviceSafeInsets", "CoreUISafeInsets",
	"TopbarSafeInsets"}
local function sameInsetAreas(a, b): boolean
	if a == nil or b == nil then return a == b end
	for _, key in ipairs(INSET_AREA_KEYS) do
		if not sameRect(a[key], b[key]) then return false end
	end
	return true
end

refresh = function(force: boolean?)
	local wasTouch = touchFormFactor
	touchFormFactor = computeTouchFormFactor()
	local previous = layout
	layout = computeLayout()
	if force or wasTouch ~= touchFormFactor or previous == nil
		or previous.Width ~= layout.Width or previous.Height ~= layout.Height
		or previous.Inset ~= layout.Inset
		or not sameRect(previous.Safe, layout.Safe)
		or not sameRect(previous.Display, layout.Display)
		or not sameInsetAreas(previous.InsetAreas, layout.InsetAreas)
		or not sameControls(previous.Zones.Controls, layout.Zones.Controls)
		or not sameRect(previous.Zones.Jump, layout.Zones.Jump)
		or not sameRect(previous.Zones.Thumbstick, layout.Zones.Thumbstick) then
		changedEvent:Fire(layout)
	end
end

do
	-- Screen-owning modal flags are direct layout inputs: while one is open the
	-- engine controls, jump region and registered control cluster all disappear.
	-- Waiting for the one-second inset watcher left cached movement zones live
	-- under a newly opened modal (and empty after it closed). Force both the
	-- recompute and Changed event so every HUD yields/restores on the deferred
	-- attribute signal's very next turn.
	UIDevice.OnScreenOwningModalChanged(function()
		if refresh then refresh(true) end
		-- One derived owner set governs both geometry and Roblox's ControlModule.
		-- This also covers future callers and ZyntraReentryOpen, so closing one
		-- modal cannot release movement while another remains open.
		UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	end)

	local camera = workspace.CurrentCamera
	local viewportConnection: RBXScriptConnection? = nil
	local function bindCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		camera = workspace.CurrentCamera
		if not camera then return end
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			refresh()
		end)
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		refresh()
	end)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function() refresh() end)
	-- The inset AREA has no changed signal of its own, and it is what every
	-- placement is derived from. A cheap watcher closes that gap: it only ever
	-- fires Changed when the safe edges actually move, and refresh() is the
	-- thing that decides that, so a quiet screen costs one rect compare a
	-- second and produces no events at all.
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)

	-- These genuinely flip when hardware is attached or removed, which changes
	-- the form factor and therefore every caption in the game.
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(function() refresh(true) end)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(function() refresh(true) end)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function() refresh(true) end)

	-- The form factor can flip while a modal is open (a keyboard is paired, a
	-- mouse is unplugged). Movement suppression is a TOUCH-only behaviour, so it
	-- has to be re-applied on that transition rather than latched at the moment
	-- the modal opened. PRODUCTION, not Studio-only: this is a real transition
	-- on a tablet leaving a keyboard case.
	changedEvent.Event:Connect(function()
		if movementIntent ~= nil then UIDevice.SuppressTouchMovement(movementIntent) end
	end)

	-- Last input only affects desktop/gamepad hint SELECTION, never the touch
	-- decision, but captions still need to be rebuilt when it changes.
	UserInputService.LastInputTypeChanged:Connect(function()
		if touchFormFactor then return end
		changedEvent:Fire(UIDevice.Layout())
	end)

	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("ForceTouchUI"):Connect(function() refresh(true) end)
		workspace:GetAttributeChangedSignal("UIRegressionViewport"):Connect(function()
			refresh(true)
		end)
		-- The safe-area override is a layout input like the other two. Without
		-- this a matrix that changed ONLY the insets -- two devices at the same
		-- size, one notched -- would have measured the previous device's safe
		-- area and reported it as this one's.
		-- The stated topbar is a layout input exactly like the other three.
		workspace:GetAttributeChangedSignal("UIRegressionTopbarInset"):Connect(function()
			if refresh then refresh(true) end
		end)
		workspace:GetAttributeChangedSignal("UIRegressionSafeInsets"):Connect(function()
			refresh(true)
		end)
		-- The EXACT four-margin transport is a layout input exactly like the two
		-- Rect attributes it supersedes, and so is the topbar band's horizontal
		-- margin. Every one of them has to invalidate, or a row that changes only
		-- its insets is measured with the PREVIOUS row's -- which is the failure
		-- the existing watchers were added to stop, and adding attributes without
		-- adding watchers would have reintroduced it through the new names.
		for _, name in ipairs({
			"UIRegressionSafeInsetsLT", "UIRegressionSafeInsetsRB",
			"UIRegressionTopbarInsetLT", "UIRegressionTopbarInsetRB",
			"UIRegressionTopbarBandLR",
		}) do
			workspace:GetAttributeChangedSignal(name):Connect(function()
				if refresh then refresh(true) end
			end)
		end
	end
end

return UIDevice
