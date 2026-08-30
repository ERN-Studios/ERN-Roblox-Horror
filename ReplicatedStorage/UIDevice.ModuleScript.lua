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
local function forcedTouch(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("ForceTouchUI") == true
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
	if forcedTouch() then return true end
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
	local viewport = forcedViewport()
		or (camera and camera.ViewportSize)
		or Vector2.new(1280, 720)
	local width, height = viewport.X, viewport.Y
	local inset = GuiService:GetGuiInset()
	local portrait = height > width
	local minAxis = math.min(width, height)

	-- Device safe area (notches, home indicators). GetGuiInset covers the top
	-- bar; the bottom indicator is not exposed, so a conservative constant is
	-- used on touch form factors where it actually exists.
	local bottomSafe = touchFormFactor and 12 or 0

	local class
	if not touchFormFactor then
		class = "desktop"
	elseif minAxis >= 700 then
		class = "tablet"
	else
		class = "phone"
	end

	-- Everything below is in VIEWPORT pixel space with the top inset already
	-- applied, matching what a ScreenGui with IgnoreGuiInset = false sees.
	local usableTop = inset.Y
	local usableHeight = height - usableTop

	local jumpSize = minAxis <= 500 and 70 or 120
	local jumpLeft = width - (jumpSize * 1.5 - 10)
	local jumpTop = usableTop + usableHeight - jumpSize - (minAxis <= 500 and 20 or jumpSize * .75)

	-- Our own control column: RUN / JUMP / GLOW / FLASHLIGHT, stacked up the
	-- right edge. Declared here so every HUD script reserves the same rectangle
	-- instead of each guessing.
	-- Measured from the cluster NoiseReporter and FlashlightController actually
	-- build: two columns of buttons up the right edge. An earlier version
	-- derived the top from a fraction of the viewport and declared it 60px
	-- lower than the real GLOW button, so HUD panels were cleared to sit on top
	-- of a control. These spans are deliberately a little generous.
	local columnSpan = class == "tablet" and 196 or 168
	local stackHeight = class == "tablet" and 330 or 290
	local controls = {
		Left = width - columnSpan,
		Right = width,
		Top = math.max(usableTop, height - stackHeight),
		Bottom = height,
	}

	-- Roblox's dynamic thumbstick ACTIVATION region is the left 40% of the
	-- bottom two thirds in landscape, and the entire width of the bottom 40% in
	-- portrait. In portrait that nominally swallows our control column too --
	-- but the column draws above TouchGui and takes those taps, so the region
	-- genuinely left to the stick ends where the column begins. Modelling it
	-- that way is what lets "no HUD in the movement zone" be a real assertion
	-- rather than one every bottom-right button trivially fails.
	local thumbstick = {
		Left = 0,
		Right = portrait and controls.Left or math.min(width * .4, controls.Left),
		Top = usableTop + usableHeight * (portrait and .6 or (1 / 3)),
		Bottom = height,
	}

	-- The vertical corridor between the two movement zones. In landscape the
	-- thumbstick owns the left 40% and our column the right edge, which leaves a
	-- usable lane down the middle at ANY height -- the only place a bottom-
	-- anchored widget can live on a landscape phone, where the band below is
	-- barely 65px tall.
	local corridor = {
		Left = thumbstick.Right + 8,
		Right = controls.Left - 8,
	}
	corridor.Width = math.max(0, corridor.Right - corridor.Left)

	-- The full-width strip above the thumbstick's activation region. A wide
	-- panel that will not fit the corridor has to live here instead, and on a
	-- landscape phone it is only about 90px tall -- which is the real constraint
	-- every Level 1 and Level 2 panel has to be sized against.
	-- The largest axis-aligned rectangle clear of BOTH movement zones. There are
	-- two candidates and which one wins is genuinely orientation dependent, so
	-- it is chosen by area rather than assumed:
	--
	--   A) FULL WIDTH, down to whichever zone starts higher. Portrait wins here:
	--      the controls only reach the bottom third, leaving a ~280px band.
	--   B) FULL HEIGHT above the thumbstick, stopping at the control column.
	--      Landscape wins here: the column reaches nearly to the top, so A
	--      collapses to nothing while B still leaves a 478x80 strip.
	local bandTop = usableTop + 8
	local candidateA = {
		Left = 12,
		Right = width - 12,
		Top = bandTop,
		Bottom = math.min(thumbstick.Top, controls.Top) - 10,
	}
	local candidateB = {
		Left = 12,
		Right = math.min(width - 12, controls.Left - 8),
		Top = bandTop,
		Bottom = thumbstick.Top - 10,
	}
	local function rectArea(rect)
		return math.max(0, rect.Right - rect.Left) * math.max(0, rect.Bottom - rect.Top)
	end
	local topBand = rectArea(candidateA) >= rectArea(candidateB) and candidateA or candidateB
	topBand.Width = math.max(0, topBand.Right - topBand.Left)
	topBand.Height = math.max(0, topBand.Bottom - topBand.Top)

	-- The band that is free of BOTH movement zones. Bottom-anchored HUD moves
	-- into this band on touch instead of sitting on top of the controls.
	local contentBottom, contentRight
	if touchFormFactor then
		contentBottom = topBand.Bottom
		contentRight = topBand.Right
	else
		contentBottom = height - bottomSafe
		contentRight = width - 12
	end

	-- Where a MODAL may live: the largest rectangle clear of every movement
	-- affordance at once -- thumbstick, control column AND jump -- inside the
	-- safe area.
	--
	-- The queue panel used to pick its own spot from ONE zone (right of the
	-- thumbstick, else above it) and one screen edge. On a 705x338 Galaxy A06
	-- that put a 380-wide panel at x 290..670 while the control column owns
	-- x 537..705: Plus, Privacy, Create and half of Close were underneath RUN,
	-- JUMP, GLOW and FLASHLIGHT. A modal must not negotiate with one zone; it
	-- must never enter any of them.
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
	local modalCandidates = {
		-- Full width, above whichever zone starts higher. Portrait wins here.
		{Left = 12, Right = width - 12, Top = bandTop,
		 Bottom = math.min(thumbstick.Top, controls.Top) - MODAL_GUTTER},
		-- Left of the column, above the stick.
		{Left = 12, Right = controls.Left - MODAL_GUTTER, Top = bandTop,
		 Bottom = thumbstick.Top - MODAL_GUTTER},
		-- The vertical corridor between the two zones, full height. Landscape
		-- wins here: the column reaches nearly to the top, so the first two
		-- candidates collapse and only the lane down the middle survives.
		{Left = thumbstick.Right + MODAL_GUTTER, Right = controls.Left - MODAL_GUTTER,
		 Top = bandTop, Bottom = height - bottomSafe},
	}
	if not touchFormFactor then
		modalCandidates = {{Left = 12, Right = width - 12, Top = bandTop,
			Bottom = height - bottomSafe}}
	end
	local modalArea
	for _, candidate in ipairs(modalCandidates) do
		candidate.Width = math.max(0, candidate.Right - candidate.Left)
		candidate.Height = math.max(0, candidate.Bottom - candidate.Top)
		if clearsZones(candidate)
			and (modalArea == nil
				or candidate.Width * candidate.Height > modalArea.Width * modalArea.Height) then
			modalArea = candidate
		end
	end
	-- Every viewport this game supports produces at least one clear candidate,
	-- but a modal must still have somewhere to go if one ever does not.
	if modalArea == nil then
		modalArea = {Left = 12, Right = width - 12, Top = bandTop,
			Bottom = height - bottomSafe}
		modalArea.Width = math.max(0, modalArea.Right - modalArea.Left)
		modalArea.Height = math.max(0, modalArea.Bottom - modalArea.Top)
	end
	-- A modal narrower or shorter than this cannot hold a 44px control stack,
	-- so callers are told rather than left to silently squeeze one.
	modalArea.Fits = modalArea.Width >= 200 and modalArea.Height >= 240

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
		SafeLeft = 12,
		SafeRight = contentRight,
		Corridor = corridor,
		TopBand = topBand,
		ModalArea = modalArea,
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

-- Convert an ABSOLUTE screen y into the offset a bottom-anchored child of this
-- ScreenGui needs -- i.e. the value for Position = UDim2.new(_, _, 1, -offset).
--
-- This exists because the two coordinate spaces disagree. A ScreenGui with
-- IgnoreGuiInset = true is positioned at -inset but still sized to the viewport,
-- so its "1, 0" bottom edge lands one inset ABOVE the real screen bottom.
-- Subtracting the inset for those guis is the difference between a panel at the
-- foot of the screen and one 67px off the top of it.
-- Convert an ABSOLUTE screen y into the offset a TOP-anchored child of this
-- ScreenGui needs. The mirror of BottomOffsetFor, and needed just as often: a
-- ScreenGui with IgnoreGuiInset = false has its y = 0 one inset DOWN the
-- screen, so feeding it an absolute y silently shifts the element by the inset
-- in one direction, and an IgnoreGuiInset gui by the same amount in the other.
-- These convert by MEASURING the ScreenGui rather than recomputing the inset.
-- Where a gui's origin actually lands turned out to vary: these ScreenGuis
-- report AbsolutePosition (0,0) with a SHORTENED height rather than an inset
-- origin at full height, so arithmetic derived from GetGuiInset is not
-- trustworthy here. Measurement always is, and it is correct for both
-- IgnoreGuiInset settings without a special case.
function UIDevice.TopOffsetFor(screenGui: ScreenGui, absoluteY: number): number
	if not screenGui then return absoluteY end
	return absoluteY - screenGui.AbsolutePosition.Y
end

function UIDevice.BottomOffsetFor(screenGui: ScreenGui, absoluteY: number): number
	if not screenGui then return math.max(0, UIDevice.Layout().Height - absoluteY) end
	local bottomEdge = screenGui.AbsolutePosition.Y + screenGui.AbsoluteSize.Y
	return math.max(0, bottomEdge - absoluteY)
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

local function refresh(force: boolean?)
	local wasTouch = touchFormFactor
	touchFormFactor = computeTouchFormFactor()
	local previous = layout
	layout = computeLayout()
	if force or wasTouch ~= touchFormFactor or previous == nil
		or previous.Width ~= layout.Width or previous.Height ~= layout.Height
		or previous.Inset ~= layout.Inset then
		changedEvent:Fire(layout)
	end
end

do
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

	-- These genuinely flip when hardware is attached or removed, which changes
	-- the form factor and therefore every caption in the game.
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(function() refresh(true) end)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(function() refresh(true) end)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function() refresh(true) end)

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
	end
end

return UIDevice
