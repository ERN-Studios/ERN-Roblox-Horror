--!strict
-- Level 3 Reader Client
-- Compact, mobile-safe Energon Reader and server-authored alert toasts.
-- Direction is calculated locally from replicated state; the server remains the
-- sole authority for module collection, exit unlocks, and completion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer

local LEVEL = 3
local WORLD_NAME = "Level 3 Generated World"
local STATE_FOLDER_NAME = "Level 3 State"
local REMOTES_FOLDER_NAME = "Level 3 Remotes"
local CLIENT_EVENT_NAME = "ClientEvent"

local UPDATE_INTERVAL = 0.10
local MAXIMUM_RANGE = 650
local ACCURACY_DEGREES = {155, 105, 64, 36, 18, 5}
local DISTANCE_NOISE = {0.60, 0.42, 0.27, 0.15, 0.07, 0.0}

local ENERGON = Color3.fromRGB(66, 244, 218)
local PANEL = Color3.fromRGB(6, 13, 15)
local TEXT = Color3.fromRGB(218, 237, 223)
local MUTED = Color3.fromRGB(153, 174, 166)
local AMBER = Color3.fromRGB(231, 218, 145)

local gui = Instance.new("ScreenGui")
gui.Name = "Level3ReaderGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 42
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- C_READER_PANEL_IS_THE_CONTROL_20260830.
-- The panel is a TextButton rather than a Frame so that on a handheld THE
-- PANEL ITSELF is the control that puts it away -- the whole 248x101 readout
-- is the tap target, which is 5x the 44px floor and needs no second control
-- beside it. `Active` is written from the form factor in applyLayout: a
-- desktop keeps a plain, non-clickable readout and its R binding, exactly as
-- before, so nothing there gains an input sink it did not have.
local panel = Instance.new("TextButton")
panel.Name = "ReaderPanel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.AutoButtonColor = false
panel.Text = ""
panel.Active = false
panel.Selectable = false
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 6)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = ENERGON
panelStroke.Thickness = 2
panelStroke.Transparency = 0.25
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(10, 5)
title.Size = UDim2.new(1, -20, 0, 18)
title.Font = Enum.Font.Code
title.Text = "> EXIT DOOR READER"
title.TextColor3 = ENERGON
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local progressLabel = Instance.new("TextLabel")
progressLabel.Name = "Calibration"
progressLabel.BackgroundTransparency = 1
progressLabel.Position = UDim2.fromOffset(10, 26)
progressLabel.Size = UDim2.new(1, -20, 0, 18)
progressLabel.Font = Enum.Font.Code
progressLabel.Text = "[□□□□□]  0/5"
progressLabel.TextColor3 = TEXT
progressLabel.TextSize = 15
progressLabel.TextXAlignment = Enum.TextXAlignment.Left
progressLabel.Parent = panel

local track = Instance.new("Frame")
track.Name = "DirectionTrack"
track.Position = UDim2.fromOffset(12, 51)
track.Size = UDim2.new(1, -24, 0, 19)
track.BackgroundColor3 = Color3.fromRGB(18, 29, 29)
track.BackgroundTransparency = 0.08
track.BorderSizePixel = 0
track.Parent = panel

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 4)
trackCorner.Parent = track

local centerLine = Instance.new("Frame")
centerLine.Name = "Center"
centerLine.AnchorPoint = Vector2.new(0.5, 0.5)
centerLine.Position = UDim2.fromScale(0.5, 0.5)
centerLine.Size = UDim2.fromOffset(2, 13)
centerLine.BackgroundColor3 = Color3.fromRGB(74, 112, 105)
centerLine.BorderSizePixel = 0
centerLine.Parent = track

local needle = Instance.new("Frame")
needle.Name = "Needle"
needle.AnchorPoint = Vector2.new(0.5, 0.5)
needle.Position = UDim2.fromScale(0.5, 0.5)
needle.Size = UDim2.fromOffset(5, 17)
needle.BackgroundColor3 = ENERGON
needle.BorderSizePixel = 0
needle.Parent = track

local needleCorner = Instance.new("UICorner")
needleCorner.CornerRadius = UDim.new(1, 0)
needleCorner.Parent = needle

local signalLabel = Instance.new("TextLabel")
signalLabel.Name = "Signal"
signalLabel.BackgroundTransparency = 1
signalLabel.Position = UDim2.fromOffset(10, 75)
signalLabel.Size = UDim2.new(1, -20, 0, 19)
signalLabel.Font = Enum.Font.Code
signalLabel.Text = "SIGNAL // NO TRACE"
signalLabel.TextColor3 = AMBER
signalLabel.TextSize = 13
signalLabel.TextTruncate = Enum.TextTruncate.AtEnd
signalLabel.TextXAlignment = Enum.TextXAlignment.Left
signalLabel.Parent = panel

-- C_READER_TOGGLE_REMOVED_20260830 -- WHAT SHIPPED BROKEN.
-- `ReaderToggle` was a permanently-visible 150x44 chip reading "CLOSE READER
-- [R]" that sat beside the panel in EVERY state. Three faults at once: it
-- printed a keyboard binding for a key a phone has not got (only masked by
-- UIDevice.Caption, which then left the chip captioned "CLOSE READER" -- a
-- redundant second control for a panel the player can simply tap); it consumed
-- 150px of the widest thing on a landscape phone's band; and it doubled the
-- persistent HUD footprint of a readout that is glanceable by design.
--
-- What replaces it:
--   * VISIBLE state -- no control at all. The panel is the control (above).
--   * HIDDEN state -- this, and only this: a 44x44 tap target whose VISIBLE
--     mark is a 30x30 chip, drawn in the reader's own Energon on its own panel
--     colour. It carries a single expand chevron and NO text, so there is no
--     string here for a keyboard glyph to hide in.
-- The two states are mutually exclusive, so the HUD never carries both, and
-- the persistent footprint while hidden is 44x44 instead of 398x101.
--
-- C_READER_DESKTOP_CHIP_20260830 -- WHAT SHIPPED BROKEN.
-- The chip was drawn on DESKTOP as well, where it is wrong three times over: a
-- mouse device already has R bound (below) so the chip is a second control for
-- a job the key does; it is wordless by design, which is right for a finger and
-- leaves a keyboard player a bare 30px chevron with nothing naming the key; and
-- once the panel is away it is the ONLY thing on screen, so "hidden" was never
-- actually hidden. Desktop's hidden state now draws nothing at all -- the chip
-- is gated on UIDevice.IsTouch() in both applyLayout and updateReader.
local RESTORE_TARGET = 44
local RESTORE_CHIP = 30

local restoreButton = Instance.new("TextButton")
restoreButton.Name = "ReaderRestore"
restoreButton.AutoButtonColor = false
restoreButton.AnchorPoint = Vector2.new(1, 0)
restoreButton.BackgroundTransparency = 1
restoreButton.BorderSizePixel = 0
restoreButton.Text = ""
restoreButton.Size = UDim2.fromOffset(RESTORE_TARGET, RESTORE_TARGET)
restoreButton.Visible = false
restoreButton.Parent = gui

-- The mark. Smaller than the target on purpose: the control reads as a quiet
-- 30px chip while the finger is given the full 44.
local restoreChip = Instance.new("Frame")
restoreChip.Name = "Chip"
restoreChip.AnchorPoint = Vector2.new(0.5, 0.5)
restoreChip.Position = UDim2.fromScale(0.5, 0.5)
restoreChip.Size = UDim2.fromOffset(RESTORE_CHIP, RESTORE_CHIP)
restoreChip.BackgroundColor3 = PANEL
restoreChip.BackgroundTransparency = 0.10
restoreChip.BorderSizePixel = 0
restoreChip.Parent = restoreButton
local restoreCorner = Instance.new("UICorner")
restoreCorner.CornerRadius = UDim.new(0, 7)
restoreCorner.Parent = restoreChip
local restoreStroke = Instance.new("UIStroke")
restoreStroke.Color = ENERGON
restoreStroke.Thickness = 1.5
restoreStroke.Transparency = 0.34
restoreStroke.Parent = restoreChip

local restoreGlyph = Instance.new("TextLabel")
restoreGlyph.Name = "Glyph"
restoreGlyph.BackgroundTransparency = 1
restoreGlyph.Size = UDim2.fromScale(1, 1)
restoreGlyph.Font = Enum.Font.Code
-- U+25BE. A geometric-shapes glyph from the same block as the progress boxes
-- this file already draws, so it is known to render here, and it is the
-- conventional "expand this" mark rather than a key name.
restoreGlyph.Text = "\u{25BE}"
restoreGlyph.TextColor3 = ENERGON
restoreGlyph.TextSize = 15
restoreGlyph.Parent = restoreChip

local readerHidden = false

local toast = Instance.new("Frame")
toast.Name = "AlertToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundColor3 = PANEL
toast.BackgroundTransparency = 0.08
toast.BorderSizePixel = 0
toast.Visible = false
toast.ZIndex = 20
toast.Parent = gui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 7)
toastCorner.Parent = toast

local toastStroke = Instance.new("UIStroke")
toastStroke.Color = ENERGON
toastStroke.Thickness = 2
toastStroke.Transparency = 0.18
toastStroke.Parent = toast

local toastTitle = Instance.new("TextLabel")
toastTitle.BackgroundTransparency = 1
toastTitle.Position = UDim2.fromOffset(12, 6)
toastTitle.Size = UDim2.new(1, -24, 0, 20)
toastTitle.Font = Enum.Font.Code
toastTitle.TextColor3 = ENERGON
toastTitle.TextSize = 17
toastTitle.TextXAlignment = Enum.TextXAlignment.Left
toastTitle.TextTruncate = Enum.TextTruncate.AtEnd
toastTitle.ZIndex = 21
toastTitle.Parent = toast

local toastBody = Instance.new("TextLabel")
toastBody.BackgroundTransparency = 1
toastBody.Position = UDim2.fromOffset(12, 28)
toastBody.Size = UDim2.new(1, -24, 1, -34)
toastBody.Font = Enum.Font.Code
toastBody.TextColor3 = TEXT
toastBody.TextSize = 13
toastBody.TextWrapped = true
toastBody.TextXAlignment = Enum.TextXAlignment.Left
toastBody.TextYAlignment = Enum.TextYAlignment.Top
toastBody.ZIndex = 21
toastBody.Parent = toast

-- C4_READER_TOUCH_CONTROLS_20260829 is now HISTORY rather than a live
-- contract: the separate touch toggle it constrained no longer exists (see
-- C_READER_TOGGLE_REMOVED_20260830 above). What survives from it, and
-- is still enforced below, is the part that was never about the button:
--   * nothing is ever placed outside the rectangle the anchor handed back;
--   * the panel narrows rather than overflowing, never below READER_MIN_WIDTH;
--   * the panel's footprint is derived from the LAYOUT alone and never from
--     readerHidden, so it cannot move or resize under the finger on it.
local READER_PANEL_HEIGHT = 101
local READER_PANEL_MIN_HEIGHT = 58
local READER_MIN_WIDTH = 150

-- C_OBJECTIVES_UPPER_RIGHT_20260830 -- WHAT SHIPPED BROKEN.
-- The reader was pinned to the TOP LEFT of the safe band on touch, which is
-- the third different answer the three levels gave to the same question
-- (Level 1 and Level 2 both used the bottom-centre corridor). It now shares
-- UIDevice.TopRightPanel with them, so all three objective readouts sit in the
-- same corner of the same true safe area, and the compact landscape variant is
-- selected from the height the anchor could actually give rather than from a
-- band that no longer decides the placement.
--
-- C_READER_DESKTOP_LOWER_RIGHT_20260830 -- WHAT SHIPPED BROKEN.
-- Desktop is a different composition and has its own convention, which this
-- file did not follow either. Level 1 (PuzzleUI, `objectivePanel`) and Level 2
-- (Level 2 Objective UI, `panel`) both anchor (1,1) one margin off the LOWER
-- right; Level 3 alone sat at UDim2.new(1, -10, 0, 70) -- the upper right of
-- the GUI, with 70 a guess at the topbar rather than a measurement of it, and
-- 10 not the 18 the other two use. That is the third answer again, on the
-- other form factor. It is now the lower-right corner of the true safe rect at
-- the shared 18px margin. Nothing else occupies that corner on a mouse device:
-- the stamina bar is bottom-centre and the flashlight cell is bottom-left, and
-- NoiseReporter's touch buttons are not drawn there at all.
local function applyLayout()
	local layoutInfo = UIDevice.Layout()
	local viewport = layoutInfo.Viewport
	local narrow = viewport.X < 620
	local mobileControls = layoutInfo.IsTouch
	local width = math.floor(math.clamp(viewport.X * (narrow and 0.56 or 0.30), 184, 248))
	local panelHeight = READER_PANEL_HEIGHT
	local compactLandscape = false

	if mobileControls then
		local column = UIDevice.TopRightPanel(width, READER_PANEL_HEIGHT)
		width = math.max(READER_MIN_WIDTH, math.floor(column.Width))
		-- Floored: the safe-area edges UIDevice derives are fractional (they come
		-- from thirds and fifths of a viewport) and a HUD a regression asserts to
		-- the pixel must not inherit that.
		panelHeight = math.floor(column.Height)
		if panelHeight < READER_PANEL_HEIGHT then
			-- The anchor could not give the authored height. Take what there is,
			-- never less than the readable minimum, and switch the internals to
			-- the compact arrangement so nothing renders outside the box.
			compactLandscape = true
			panelHeight = math.max(READER_PANEL_MIN_HEIGHT, panelHeight)
		end
		panel.AnchorPoint = Vector2.new(1, 0)
		-- Anchored (1,0): the X handed over is the panel's RIGHT edge, and it is
		-- converted like every other absolute coordinate.
		panel.Position = UIDevice.LocalPosition(gui,
			math.floor(column.Right), math.floor(column.Top))
		-- The restore chip lands on the panel's own top-right corner, so the
		-- control the player taps to bring the reader back is exactly where the
		-- reader was. Same anchor, both states.
		restoreButton.AnchorPoint = Vector2.new(1, 0)
		restoreButton.Position = UIDevice.LocalPosition(gui,
			math.floor(column.Right), math.floor(column.Top))
	else
		-- Anchored (1,1) at the safe rect's lower-right corner, the same 18px
		-- margin Level 1 and Level 2 use. Measured against layoutInfo.Safe rather
		-- than written as a bare `UDim2.new(1, -18, 1, -18)`: the gui's own
		-- rectangle is GetInsetArea(CoreUISafeInsets) and Safe is that intersected
		-- with the DEVICE inset, so the two separate the moment a client reports
		-- one. RightOffsetFor/BottomOffsetFor is that conversion for a
		-- (1,1)-anchored child, and it collapses to -18/-18 where they agree.
		local margin = 18
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Position = UDim2.new(
			1, -UIDevice.RightOffsetFor(gui, layoutInfo.Safe.Right - margin),
			1, -UIDevice.BottomOffsetFor(gui, layoutInfo.Safe.Bottom - margin))
		-- No restore chip and no open button, ever, on a mouse device: R is the
		-- entire interface and the hidden state is genuinely empty
		-- (C_READER_DESKTOP_CHIP_20260830). Put away HERE and not only in
		-- updateReader, because updateReader runs on a 0.1s accumulator -- a
		-- desktop client that flipped form factor while hidden would otherwise
		-- draw the chip for up to one interval before the next tick cleared it.
		UIDevice.SetInteractive(restoreButton, false)
	end
	panel.Size = UDim2.fromOffset(width, panelHeight)
	-- Only a handheld gets a tappable panel. A desktop keeps the readout inert
	-- and its R binding, so no mouse click is swallowed in the lower-right
	-- corner the panel now occupies.
	-- Never Active while invisible: a transparent TextButton left Active keeps
	-- taking taps. updateReader re-derives this every tick from the live state.
	UIDevice.SetEnabled(panel, mobileControls and panel.Visible)

	if compactLandscape then
		title.Position = UDim2.fromOffset(8, 2)
		title.Size = UDim2.new(1, -16, 0, 12)
		progressLabel.Position = UDim2.fromOffset(8, 15)
		progressLabel.Size = UDim2.new(1, -16, 0, 12)
		track.Position = UDim2.fromOffset(9, 29)
		track.Size = UDim2.new(1, -18, 0, 11)
		centerLine.Size = UDim2.fromOffset(2, 7)
		needle.Size = UDim2.fromOffset(4, 10)
		signalLabel.Position = UDim2.fromOffset(8, 43)
		signalLabel.Size = UDim2.new(1, -16, 1, -45)
		title.TextSize = 11
		progressLabel.TextSize = 10
		signalLabel.TextSize = 9
	else
		title.Position = UDim2.fromOffset(10, 5)
		title.Size = UDim2.new(1, -20, 0, 18)
		progressLabel.Position = UDim2.fromOffset(10, 26)
		progressLabel.Size = UDim2.new(1, -20, 0, 18)
		track.Position = UDim2.fromOffset(12, 51)
		track.Size = UDim2.new(1, -24, 0, 19)
		centerLine.Size = UDim2.fromOffset(2, 13)
		needle.Size = UDim2.fromOffset(5, 17)
		signalLabel.Position = UDim2.fromOffset(10, 75)
		signalLabel.Size = UDim2.new(1, -20, 0, 19)
		title.TextSize = narrow and 14 or 16
		progressLabel.TextSize = narrow and 13 or 15
		signalLabel.TextSize = narrow and 11 or 13
	end

	-- The toast carries two lines of authored copy in a box that was a fixed
	-- 52px -- 20 for the title and 18 for a body that regularly needs two
	-- lines. Its height is measured now, and it is centred on the SAFE rect
	-- rather than on the gui, which differ the moment a device has a
	-- horizontal inset.
	local toastWidth = math.floor(math.clamp(layoutInfo.Safe.Width - 40, 260, 410))
	local bodySample = toastBody.Text ~= "" and toastBody.Text
		or "Two full lines of authored alert copy, which is what these carry."
	local bodyNeed = TextService:GetTextSize(bodySample, toastBody.TextSize,
		toastBody.Font, Vector2.new(math.max(1, toastWidth - 24), 100000)).Y
	local toastHeight = math.clamp(30 + bodyNeed + 8, 52, 140)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UIDevice.LocalPosition(gui,
		(layoutInfo.Safe.Left + layoutInfo.Safe.Right) * .5, layoutInfo.Safe.Top + 8)
	toast.Size = UDim2.fromOffset(toastWidth, toastHeight)
	toastBody.Size = UDim2.new(1, -24, 0, math.max(18, bodyNeed))
end

-- There is no caption to maintain any more: on touch the visible state is the
-- panel itself and the hidden state is a wordless chip, and on desktop the
-- hidden state is empty. What remains is the state write, kept as one function
-- so the key binding, the panel's own Activated handler and the Studio seam
-- all go through the same door.

local function setReaderHidden(hidden: boolean)
	readerHidden = hidden
end

-- Tapping the readout puts it away. This is `panel.Activated`'s handler, and on
-- a handheld a finger raising that signal is what runs it; `panel.Active` is
-- false on desktop, so a mouse click in the lower-right corner cannot raise it
-- there.
-- Both production handlers are named locals so the Studio seam below can call
-- the SAME function object the connection carries instead of re-implementing
-- it. Calling a function is not an input event, and no name, comment or
-- published string here may read as though it were -- see
-- C_HANDLER_SEAM_IS_NOT_INPUT_20260831.
local function onPanelTapped()
	-- Restated for the Studio seam. `panel.Active` is false on desktop so
	-- Activated cannot fire there at all, but the seam calls this function
	-- directly, with no button involved, and it has to obey the same rule: on
	-- desktop R is the only thing that may put the reader away.
	if not UIDevice.IsTouch() then return end
	setReaderHidden(true)
end
-- Deliberately NOT gated on IsTouch. The chip it belongs to is never drawn on
-- desktop, so no click can reach this; and R restores through exactly this same
-- state write, so a form-factor guard here would forbid nothing and would only
-- give the two ways back different behaviour.
local function onRestoreTapped()
	setReaderHidden(false)
end
-- C_ACTIVATED_WIRING_CONTRACT_20260831.
--
-- The connections are RECORDED as they are made, so a regression can prove the
-- routing exists rather than only that the handler body works.
--
-- WHAT THIS CLOSES: the Studio seam below calls onPanelTapped/onRestoreTapped
-- as plain functions, and C_HANDLER_SEAM_IS_NOT_INPUT_20260831 says why it can
-- do nothing else. A check built on that alone stays green when someone
-- deletes an `Activated:Connect` line: the control would be dead in the
-- player's hands and every row would still pass. The recorded
-- RBXScriptConnection is the half that cannot exist without the connection --
-- Connect had to run to produce it, `Connected` says whether it still holds,
-- and `Button` pins WHICH instance it was made on, because a connection that
-- is live on some other TextButton, or on one no longer in the tree, routes a
-- finger nowhere either.
--
-- The two call statements below are also matched VERBATIM by UIRegression's
-- source half, which reads this LocalScript's `.Source` and requires both to
-- be present -- that is what catches a deleted connection even when the
-- runtime probe is bypassed entirely. Renaming `wireTap` or either handler
-- means changing those two literals in the same edit.
local tapWiring = {}
local function wireTap(name: string, button: TextButton, handler: () -> ())
	local connection = button.Activated:Connect(handler)
	tapWiring[name] = {Button = button, Handler = handler, Connection = connection}
	return connection
end

wireTap("ReaderPanel", panel, onPanelTapped)
wireTap("ReaderRestore", restoreButton, onRestoreTapped)

-- Studio-only HANDLER seam for UIRegression. It calls the PRODUCTION handlers
-- rather than a copy of them, so a matrix that drives it runs the code a
-- player's tap reaches -- and nothing else.
--
-- C_HANDLER_SEAM_IS_NOT_INPUT_20260831 -- WHAT SHIPPED BROKEN.
--
-- This seam was written as though the test had TAPPED something. Its two
-- actions were "tapPanel" and "tapRestore", the note above them called it an
-- "input seam", and the regression rows it feeds read "TAPPING THE PANEL
-- hides it". None of that is what happens. The probe calls onPanelTapped and
-- onRestoreTapped as plain Lua functions: no touch, no click and no
-- InputObject exists at any point, and the button itself is never involved --
-- so everything between a finger and the handler (the hit test, `Active`,
-- `Visible`, ZIndex, a modal drawn over the top) is left unexercised by
-- invoking it. A name that says "tap" invites the next reader to believe an
-- input path was proven when it was not.
--
-- WHY IT CANNOT BE MORE THAN THIS: VirtualInputManager refuses in this Studio
-- session ("lacking capability RobloxScript"), and the MCP bridge's synthetic
-- mouse does not reach the GUI input stack at all -- it never even raises
-- MouseEnter on a GuiObject. Nothing in this project can deliver a real input
-- event to this GUI, so the actions are named for what they actually do: they
-- invoke a handler.
--
-- WHAT THE PAIR DOES PROVE -- this seam plus the wiring contract above -- is
-- that the handler body does the right thing when it runs, AND that the
-- handler is the live endpoint of an Activated connection on the button this
-- file draws. The one link neither half covers is the engine delivering a
-- touch to a visible, Active button; that is Roblox's own behaviour, and it is
-- untested here by necessity rather than by choice.
--
-- WHAT THE TESTS DID BEFORE EVEN THAT: they set
-- UIRegressionForceReaderHidden, which is the OUTPUT of these handlers. That
-- proved the renderer honours a flag and said nothing about whether the
-- handlers ever set it.
--
-- C_READER_VISIBILITY_FORWARD_20260831.
--
-- The probe object has to be created HERE, beside the two handlers it invokes,
-- but the "visibility" action has to read isActive(), the toast and the
-- renderer's own gates -- none of which this file declares until two hundred
-- lines further down. A forward local is the seam between those two facts: the
-- probe closes over the variable, the bottom of the file fills it in. It is nil
-- only for the microseconds this script spends between the two points, and the
-- action says so plainly rather than inventing a plausible answer for a caller
-- that arrived too early.
local readerVisibilityReport: (() -> string)? = nil
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionReaderProbe"
	probe.OnInvoke = function(action)
		-- "invokePanelHandler" and "invokeRestoreHandler" are the names of the
		-- two actions that run a handler. "tapPanel" and "tapRestore" are kept
		-- as ALIASES, and for one reason only: so UIRegression can be corrected
		-- in its own change without any run in between calling a name that no
		-- longer answers. They are the same call; do not use them in new code.
		if action == nil or action == "state" then
			return readerHidden and "hidden" or "open"
		elseif action == "invokePanelHandler" or action == "tapPanel" then
			onPanelTapped()
			return readerHidden and "hidden" or "open"
		elseif action == "invokeRestoreHandler" or action == "tapRestore" then
			onRestoreTapped()
			return readerHidden and "hidden" or "open"
		elseif action == "visibility" then
			-- Reports what the reader IS, at the instant of the call, with no tick
			-- in between. It deliberately does NOT run updateReader first: the
			-- claim under test is that flipping a gating attribute takes the reader
			-- down in the SAME frame
			-- (C_READER_IMMEDIATE_EXCLUSION_20260831), and a probe that rendered on
			-- demand would satisfy that claim by doing the very work whose absence
			-- is the bug. Every row would go green and the 100ms window would still
			-- be there.
			--
			-- The string carries BOTH halves so a caller can assert they agree:
			-- `active` is recomputed from the live attributes on this very line, so
			-- it is never stale; the ReaderPanel/ReaderRestore fields are whatever
			-- the renderer last wrote. A reader that is still up after its gate
			-- closed reads active=false with ReaderPanel=true/true, which is exactly
			-- the defect, stated in one line.
			--
			-- Grammar: one line, single spaces, fixed field order, every value the
			-- literal "true" or "false" except forcehidden.
			--   ReaderPanel=<Visible>/<Active>
			--   ReaderRestore=<Visible>/<Active>
			--   active=        isActive(), the gate the renderer applies
			--   hidden=        readerHidden, the player's own hide toggle
			--   forcehidden=   none | true | false -- the Studio-only override of
			--                  `hidden` that updateReader honours
			--   toast=         toast.Visible; an alert owns the same band and both
			--                  controls stand down under it
			--   touch=         UIDevice.IsTouch(); the restore chip is touch-only
			-- then the raw inputs isActive() reads, each true when SET:
			--   level=         workspace SelectedLevel == 3
			--   inround=       player InRound == true
			--   escaped=       player Escaped == true          (blocking)
			--   forcelevel=    UIRegressionForceLevel3Reader   (Studio override)
			--   dispatch=      ZyntraDispatchClientActive      (blocking)
			--   hiding=        Level3_Hiding                   (blocking)
			--   modal=         UIDevice.ScreenOwningModalOpen() (blocking)
			-- So a reader that should be on screen reads
			-- "active=true ... escaped=false ... dispatch=false hiding=false
			-- modal=false".
			-- Copied to a local before the nil check so --!strict actually
			-- narrows it: an upvalue that is assigned from another scope is not
			-- refined by a test on the upvalue itself.
			local report = readerVisibilityReport
			if report == nil then return "visibility:notready" end
			return report()
		elseif action == "wiring" then
			-- One field per control, "<name>=<routed>/<sameFunction>". The shape
			-- is fixed: UIRegression matches the whole string against
			-- "ReaderPanel=true/true ReaderRestore=true/true".
			--   routed        the Activated connection was made, is still
			--                 Connected, and was made on the very button this
			--                 file draws and hides, which is still in the tree.
			--                 A connection that is live on some other instance,
			--                 or on a detached one, routes a finger nowhere.
			--   sameFunction  the function this seam invokes IS the function that
			--                 was connected, not a copy of it.
			-- Neither field says an input event was delivered; nothing in this
			-- file can (C_HANDLER_SEAM_IS_NOT_INPUT_20260831).
			local parts = {}
			for _, entry in ipairs({
				{Name = "ReaderPanel", Handler = onPanelTapped, Button = panel},
				{Name = "ReaderRestore", Handler = onRestoreTapped,
					Button = restoreButton},
			}) do
				local wiring = tapWiring[entry.Name]
				local routed = wiring ~= nil
					and wiring.Connection.Connected == true
					and wiring.Button == entry.Button
					and wiring.Button.Parent ~= nil
				table.insert(parts, string.format("%s=%s/%s", entry.Name,
					tostring(routed),
					tostring(wiring ~= nil and wiring.Handler == entry.Handler)))
			end
			return table.concat(parts, " ")
		end
		-- An action this seam does not implement is not a state query. Answering
		-- one with the state would hand a mistyped action a plausible "open" and
		-- a passing row; the caller gets back something that cannot be mistaken
		-- for a result instead.
		return "unknownaction:" .. tostring(action)
	end
	probe.Parent = gui
end
ContextActionService:BindAction("Level3ToggleExitReader", function(_, inputState)
	if inputState == Enum.UserInputState.Begin
		and UserInputService:GetFocusedTextBox() == nil
		and workspace:GetAttribute("SelectedLevel") == LEVEL
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true then
		setReaderHidden(not readerHidden)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
-- C_READER_CONNECTION_TRACKING_20260831 -- WHAT SHIPPED BROKEN.
--
-- Every signal this file subscribed to was connected and then forgotten. There
-- was no teardown path at all -- not for the script being destroyed, not for
-- the ScreenGui leaving PlayerGui. That was survivable while the list was four
-- entries long and the gui was built with ResetOnSpawn = false so it outlived
-- respawns; it stops being survivable now that the reader also subscribes to
-- every attribute that gates it (C_READER_IMMEDIATE_EXCLUSION_20260831). A
-- destroyed LocalScript would leave a dozen callbacks alive, each still writing
-- Active and Visible onto orphaned instances once per state change for the rest
-- of the session, and each still holding this whole closure set in memory.
--
-- So: connections go through trackReaderConnection, teardownReader at the
-- bottom of the file disconnects the lot exactly once, and a connection handed
-- to the tracker AFTER teardown is disconnected on the spot instead of being
-- added. That last rule is what makes a second setup pass harmless rather than
-- a second leak.
--
-- The two REBINDING connections -- the camera viewport and the Level 3
-- ClientEvent -- are deliberately not in the list. Each replaces itself
-- whenever its subject changes, so the list would fill with dead entries and
-- grow without bound over a session. teardownReader disconnects whichever one
-- is live, by name, instead.
local readerConnections: {RBXScriptConnection} = {}
local readerAlive = true

local function trackReaderConnection(connection: RBXScriptConnection): RBXScriptConnection
	if not readerAlive then
		connection:Disconnect()
		return connection
	end
	table.insert(readerConnections, connection)
	return connection
end

-- Rebuild on UIDevice.Changed, which fires for viewport, inset, form factor,
-- and (on desktop only) last-input changes. On a phone this can never fire for
-- an input flip, which is the whole point.
trackReaderConnection(UIDevice.Changed:Connect(applyLayout))

local viewportConnection: RBXScriptConnection? = nil
local function bindCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	-- Cleared, not left holding a dead handle: teardownReader reads this to
	-- decide what still needs disconnecting, and a stale handle would have it
	-- disconnect something already gone.
	viewportConnection = nil
	if not readerAlive then return end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end
trackReaderConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
bindCamera()

local function stateFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return if folder and folder:IsA("Folder") then folder else nil
end

local function stateAttribute(name: string, workspaceMirror: string?): any
	local state = stateFolder()
	local value = state and state:GetAttribute(name)
	if value == nil and workspaceMirror then value = workspace:GetAttribute(workspaceMirror) end
	return value
end

local function numberAttribute(name: string, workspaceMirror: string?, fallback: number): number
	local value = stateAttribute(name, workspaceMirror)
	return if type(value) == "number" then value else fallback
end

local function isActive(): boolean
	local levelActive = workspace:GetAttribute("SelectedLevel") == LEVEL
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
	if RunService:IsStudio()
		and player:GetAttribute("UIRegressionForceLevel3Reader") == true then
		levelActive = true
	end
	return levelActive
		and player:GetAttribute("ZyntraDispatchClientActive") ~= true
		and player:GetAttribute("Level3_Hiding") ~= true
		-- A screen-owning modal takes the reader with it. The panel is a
		-- TextButton on touch, so leaving it up under an open terminal would put
		-- a live control beneath a modal.
		and not UIDevice.ScreenOwningModalOpen()
end

local function currentWorld(): Model?
	local world = workspace:FindFirstChild(WORLD_NAME)
	return if world and world:IsA("Model") then world else nil
end

local function exitPosition(): Vector3?
	local value = stateAttribute("Level3_ExitPosition", nil)
	if typeof(value) == "Vector3" then return value :: Vector3 end
	return nil
end

local function generationMatches(payload: {[any]: any}): boolean
	local payloadGeneration = payload.Generation
	if type(payloadGeneration) ~= "number" then return true end
	local world = currentWorld()
	local liveGeneration = world and world:GetAttribute("Level3_Generation")
	return type(liveGeneration) ~= "number" or liveGeneration == payloadGeneration
end

local toastSerial = 0
local function cleanText(value: any, fallback: string, maximum: number): string
	local text = (if type(value) == "string" then value else fallback) :: string
	text = text:gsub("[%c]", " ")
	return text:sub(1, maximum)
end

local function showToast(titleText: any, subtitle: any, instruction: any, duration: any)
	if not isActive() then return end
	toastSerial += 1
	local serial = toastSerial
	toastTitle.Text = cleanText(titleText, "LEVEL 3", 72)
	local first = cleanText(subtitle, "", 110)
	local second = cleanText(instruction, "", 110)
	toastBody.Text = if first ~= "" and second ~= "" then first .. "\n" .. second else first .. second
	toast.BackgroundTransparency = 0.08
	toastTitle.TextTransparency = 0
	toastBody.TextTransparency = 0
	toastStroke.Transparency = 0.18
	toast.Visible = true
	-- The alert owns the same safe top band for its brief lifetime. Do not draw
	-- the reader underneath it; updateReader restores both controls afterwards.
	-- SetInteractive, not a bare Visible write. Both are TextButtons, and a
	-- TextButton left Active keeps taking taps through a transparent
	-- background -- so `Visible = false` alone left an invisible 248x101
	-- hitbox over the toast until the next update tick (up to 0.1s). Active
	-- and Visible move together, synchronously, in one statement.
	UIDevice.SetInteractive(panel, false)
	UIDevice.SetInteractive(restoreButton, false)
	local hold = math.clamp(if type(duration) == "number" then duration else 2.4, 0.8, 6)
	task.delay(hold, function()
		if serial ~= toastSerial or not toast.Parent then return end
		local info = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(toast, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(toastTitle, info, {TextTransparency = 1}):Play()
		TweenService:Create(toastBody, info, {TextTransparency = 1}):Play()
		TweenService:Create(toastStroke, info, {Transparency = 1}):Play()
		task.delay(0.30, function()
			if serial == toastSerial and toast.Parent then toast.Visible = false end
		end)
	end)
end

local function handleClientEvent(payload: any)
	if type(payload) ~= "table" or not generationMatches(payload) then return end
	local kind = payload.Type
	if kind == "Alert" then
		showToast(payload.Title, payload.Subtitle, payload.Instruction, payload.Duration)
	elseif kind == "ModuleCollected" then
		local progress = math.max(0, math.floor(tonumber(payload.CollectedProgress or payload.Progress) or 0))
		local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
		local collector = cleanText(payload.CollectorName, "A TEAM MEMBER", 36)
		showToast(
			string.format("CD %02d SECURED", math.max(1, math.floor(tonumber(payload.CDIndex or payload.ModuleIndex) or progress))),
			string.format("%s  //  FOUND %d/%d", collector, math.min(progress, goal), goal),
			if payload.RecoveredDrop == true then "RECOVERED  //  CARRY IT TO THE DISC PLAYER"
				else "CARRY IT TO THE DISC PLAYER",
			2.2
		)
	elseif kind == "CDInserted" then
		local progress = math.max(0, math.floor(tonumber(payload.InsertedCount or payload.Progress) or 0))
		local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
		if progress >= goal then return end
		local depositor = cleanText(payload.DepositorName, "A TEAM MEMBER", 36)
		showToast(
			string.format("DISC RELAY %d/%d", math.min(progress, goal), goal),
			string.format("%s INSERTED %d CD%s", depositor,
				math.max(1, math.floor(tonumber(payload.Count) or 1)),
				(if math.floor(tonumber(payload.Count) or 1) == 1 then "" else "S")),
			"OTHER HOLDERS MUST INSERT THEIRS",
			2.3
		)
	elseif kind == "CDDropped" then
		showToast("A CARRIED CD WAS DROPPED", "RECOVER IT AT THE PLAYER'S LAST POSITION", "", 2.4)
	elseif kind == "CDTransferred" and payload.RecipientUserId == player.UserId then
		showToast("TEAM CD TRANSFERRED", "A DEPARTING PLAYER'S CD IS NOW ON YOUR BACK",
			"TAKE IT TO THE DISC PLAYER", 2.8)
	elseif kind == "ExitUnlocked" then
		showToast("ALL CDS INSERTED", "WALL FRAME REVEALED  //  FOLLOW EXIT SIGNAL", "", 3.0)
	end
end

local clientEventConnection: RBXScriptConnection? = nil
local boundClientEvent: RemoteEvent? = nil
local function bindClientEvent()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	local candidate = folder and folder:FindFirstChild(CLIENT_EVENT_NAME)
	local event = if candidate and candidate:IsA("RemoteEvent") then candidate else nil
	if event == boundClientEvent then return end
	if clientEventConnection then clientEventConnection:Disconnect() end
	clientEventConnection = nil
	boundClientEvent = event
	if event then clientEventConnection = event.OnClientEvent:Connect(handleClientEvent) end
end

ReplicatedStorage.ChildAdded:Connect(bindClientEvent)
ReplicatedStorage.ChildRemoved:Connect(bindClientEvent)
bindClientEvent()

local smoothedNeedle = 0
local smoothedSignal = 0
local accumulated = 0

local function signedPlanarAngle(forward: Vector3, target: Vector3): number
	local a = Vector3.new(forward.X, 0, forward.Z)
	local b = Vector3.new(target.X, 0, target.Z)
	if a.Magnitude < 0.001 or b.Magnitude < 0.001 then return 0 end
	a = a.Unit
	b = b.Unit
	return math.atan2(a.X * b.Z - a.Z * b.X, math.clamp(a:Dot(b), -1, 1))
end

local function updateReader(dt: number)
	local active = isActive()
	local hidden = readerHidden
	if RunService:IsStudio() then
		local forced = player:GetAttribute("UIRegressionForceReaderHidden")
		if type(forced) == "boolean" then hidden = forced end
	end
	-- The two states are mutually exclusive and neither draws under a toast.
	-- SetInteractive rather than a bare Visible write: a TextButton left Active
	-- keeps taking taps through a transparent background, and BOTH of these are
	-- buttons now -- the restore chip is transparent apart from its 30px mark,
	-- and the panel is the control that hides itself.
	local touch = UIDevice.IsTouch()
	UIDevice.SetInteractive(panel, active and not hidden and not toast.Visible)
	-- SetEnabled AFTER SetInteractive, which writes Active = Visible: this is the
	-- correction that keeps the desktop readout inert, so a click at the panel's
	-- corner still reaches the world behind it.
	UIDevice.SetEnabled(panel, panel.Visible and touch)
	-- `and touch` is the whole desktop fix here: on a mouse device the hidden
	-- state draws nothing (C_READER_DESKTOP_CHIP_20260830). Touch is unchanged --
	-- panel and chip remain mutually exclusive and neither draws under a toast.
	UIDevice.SetInteractive(restoreButton,
		touch and active and hidden and not toast.Visible)
	if not active then
		toastSerial += 1
		toast.Visible = false
		return
	end

	local goal = math.clamp(math.floor(numberAttribute("Level3_ModuleGoal", "Level3ModuleGoal", 5)), 1, 12)
	local progress = math.clamp(math.floor(numberAttribute("Level3_ModuleProgress", "Level3Modules", 0)), 0, goal)
	local index = math.clamp(progress + 1, 1, #ACCURACY_DEGREES)
	local cells: {string} = {}
	for cell = 1, goal do cells[cell] = if cell <= progress then "■" else "□" end
	progressLabel.Text = string.format("DISC RELAY [%s]  %d/%d", table.concat(cells), progress, goal)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = exitPosition()
	if not (root and root:IsA("BasePart") and target) then
		signalLabel.Text = "SIGNAL // NO TRACE"
		signalLabel.TextColor3 = MUTED
		return
	end

	local offset = target - root.Position
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local camera = workspace.CurrentCamera
	local forward = camera and camera.CFrame.LookVector or root.CFrame.LookVector
	local trueAngle = signedPlanarAngle(forward, offset)
	local time = os.clock()
	local angularNoise = math.noise(time * 0.43, progress * 2.71) * math.rad(ACCURACY_DEGREES[index])
	local noisyAngle = trueAngle + angularNoise
	local needleTarget = math.clamp(noisyAngle / math.rad(90), -1, 1)

	local facing = math.clamp((math.cos(noisyAngle) + 1) * 0.5, 0, 1)
	local rangeSignal = 1 - math.clamp(distance / MAXIMUM_RANGE, 0, 1)
	local distanceJitter = math.noise(time * 0.61, 19 + progress) * DISTANCE_NOISE[index]
	local signalTarget = math.clamp(facing * 0.72 + rangeSignal * 0.28 + distanceJitter, 0, 1)
	local response = 1.3 + progress * 0.72
	local alpha = 1 - math.exp(-dt * response)
	smoothedNeedle += (needleTarget - smoothedNeedle) * alpha
	smoothedSignal += (signalTarget - smoothedSignal) * alpha
	needle.Position = UDim2.new(0.5 + smoothedNeedle * 0.43, 0, 0.5, 0)

	local signalBars = math.clamp(math.floor(smoothedSignal * 5 + 0.5), 0, 5)
	local bars = string.rep("▮", signalBars) .. string.rep("□", 5 - signalBars)
	local unlocked = stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true
	if unlocked then
		signalLabel.Text = string.format("SIGNAL // %s  %dm", bars, math.floor(distance / 3.571 + 0.5))
		signalLabel.TextColor3 = ENERGON
		panelStroke.Color = ENERGON
	elseif progress == 0 then
		signalLabel.Text = "SIGNAL // UNSTABLE"
		signalLabel.TextColor3 = MUTED
		panelStroke.Color = Color3.fromRGB(75, 122, 116)
	elseif progress < math.ceil(goal * 0.6) then
		signalLabel.Text = "SIGNAL // " .. bars .. "  WEAK"
		signalLabel.TextColor3 = AMBER
		panelStroke.Color = Color3.fromRGB(89, 170, 159)
	else
		signalLabel.Text = "SIGNAL // " .. bars .. "  CALIBRATING"
		signalLabel.TextColor3 = TEXT
		panelStroke.Color = ENERGON
	end
	needle.BackgroundColor3 = if unlocked then Color3.fromRGB(128, 255, 222) else ENERGON
end

-- C_READER_IMMEDIATE_EXCLUSION_20260831 -- WHAT SHIPPED BROKEN.
--
-- The reader consumed isActive() from ONE place: the accumulator below, which
-- lets dt pile up to UPDATE_INTERVAL (0.10s) before updateReader runs at all.
-- So every state that is meant to take the reader off the screen -- a dispatch
-- briefing, the Zyntra terminal or the queue modal through
-- UIDevice.ScreenOwningModalOpen(), Level3_Hiding, the round ending, the player
-- escaping -- turned on and the reader stayed up for as much as 100ms
-- afterwards.
--
-- Not merely drawn. ReaderPanel and ReaderRestore are both TextButtons, and it
-- is updateReader that clears their Active, so for those 100ms there was a live
-- >= 44x44 touch target sitting on top of somebody else's screen -- in the
-- upper-right corner, which is where a modal's own dismiss control lives. A
-- player who reached for the terminal's close in that window hid the reader
-- instead, and the tap never reached the modal at all. 100ms is not a
-- theoretical window: it is longer than a deliberate tap.
--
-- The fix is to drive updateReader from the state changes themselves, so the
-- panel goes Active = false and Visible = false in the same frame the gating
-- attribute is written. Every attribute isActive() reads gets a
-- GetAttributeChangedSignal, and the screen-owning-modal group is subscribed
-- through UIDevice's own helper so this file never keeps a second copy of which
-- modals count -- if that list grows, this reader follows it for free.
--
-- THE TICK BELOW STAYS, AND STAYS AS A FALLBACK -- it is no longer the path
-- mutual exclusion depends on, and it is still the only thing that covers what
-- no signal reports: the needle, the signal bars and the distance readout,
-- which are recomputed from the camera and the character and change with
-- neither; toast.Visible, which is cleared by a task.delay inside showToast and
-- has no changed signal of its own; the Level 3 state folder's attributes,
-- which are read through stateAttribute() from a folder that may not exist yet;
-- and any gate a later change adds to isActive() without adding it to the list
-- here. The tick is what keeps a missed subscription a 100ms latency bug
-- instead of a permanent one.
--
-- dt = 0 on the signal-driven calls, deliberately. updateReader integrates the
-- needle and signal smoothing with alpha = 1 - math.exp(-dt * response); dt = 0
-- gives alpha = 0, so a state change advances no animation and the needle
-- cannot jump because a modal opened. All the smoothing stays with the tick,
-- which is the only caller that holds a real elapsed time.
local READER_STATE_ATTRIBUTES = {
	"InRound", "Escaped", "ZyntraDispatchClientActive", "Level3_Hiding",
}
-- Read by isActive() and updateReader only under RunService:IsStudio(), so they
-- are only subscribed there. In a live game these attributes are never written
-- and a subscription to them would be a connection that can never fire.
local READER_STUDIO_ATTRIBUTES = {
	"UIRegressionForceLevel3Reader", "UIRegressionForceReaderHidden",
}

local readerSignalsBound = false
local function bindReaderStateSignals()
	-- Idempotent by a flag, not by hope: call this twice and the second call
	-- returns, so nothing is ever connected to a second time. Without it a
	-- re-entry would double every write and leave a second set of connections
	-- that teardown would then have to disconnect twice.
	if readerSignalsBound or not readerAlive then return end
	readerSignalsBound = true
	local function respond()
		if not readerAlive then return end
		updateReader(0)
	end
	trackReaderConnection(
		workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(respond))
	for _, attribute in ipairs(READER_STATE_ATTRIBUTES) do
		trackReaderConnection(
			player:GetAttributeChangedSignal(attribute):Connect(respond))
	end
	if RunService:IsStudio() then
		for _, attribute in ipairs(READER_STUDIO_ATTRIBUTES) do
			trackReaderConnection(
				player:GetAttributeChangedSignal(attribute):Connect(respond))
		end
	end
	-- UIDevice.OnScreenOwningModalChanged connects internally and returns
	-- NOTHING, so there is no handle here to track or to disconnect. That is the
	-- reason `respond` carries its own readerAlive guard above rather than
	-- leaning on the tracker: after teardown this one callback still fires, and
	-- the guard is what makes it do nothing instead of writing onto a destroyed
	-- panel. It is the single subscription in this file that outlives the reader,
	-- and it is inert.
	UIDevice.OnScreenOwningModalChanged(respond)
end

bindReaderStateSignals()

-- Fills the forward local declared beside the probe
-- (C_READER_VISIBILITY_FORWARD_20260831). Everything it reports is live: the
-- two controls' own properties as the renderer last left them, and the gating
-- inputs recomputed on the spot. The field order and spelling ARE the probe's
-- documented grammar -- the regression rows match this string, so change the
-- format and the comment above the action in the same edit.
readerVisibilityReport = function(): string
	local forced = player:GetAttribute("UIRegressionForceReaderHidden")
	return string.format(
		"ReaderPanel=%s/%s ReaderRestore=%s/%s active=%s hidden=%s forcehidden=%s"
			.. " toast=%s touch=%s level=%s inround=%s escaped=%s forcelevel=%s"
			.. " dispatch=%s hiding=%s modal=%s",
		tostring(panel.Visible), tostring(panel.Active),
		tostring(restoreButton.Visible), tostring(restoreButton.Active),
		tostring(isActive()),
		tostring(readerHidden),
		(if type(forced) == "boolean" then tostring(forced) else "none"),
		tostring(toast.Visible),
		tostring(UIDevice.IsTouch()),
		tostring(workspace:GetAttribute("SelectedLevel") == LEVEL),
		tostring(player:GetAttribute("InRound") == true),
		tostring(player:GetAttribute("Escaped") == true),
		tostring(player:GetAttribute("UIRegressionForceLevel3Reader") == true),
		tostring(player:GetAttribute("ZyntraDispatchClientActive") == true),
		tostring(player:GetAttribute("Level3_Hiding") == true),
		tostring(UIDevice.ScreenOwningModalOpen()))
end

trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
	accumulated += dt
	if accumulated < UPDATE_INTERVAL then return end
	local elapsed = accumulated
	accumulated = 0
	bindClientEvent()
	updateReader(elapsed)
end))

-- C_READER_TEARDOWN_20260831.
--
-- One teardown, idempotent, that every exit path funnels into. The triggers are
-- the three ways this reader can actually stop existing: the LocalScript being
-- destroyed, the ScreenGui being destroyed, and the gui being pulled out of the
-- tree WITHOUT being destroyed (PlayerGui cleared, gui reparented). The last
-- one is checked as `not gui:IsDescendantOf(game)` rather than
-- `gui.Parent == nil`, because a reparent into a detached folder leaves Parent
-- non-nil and the reader just as dead.
--
-- The three trigger connections are deliberately NOT tracked. Each is made on
-- an instance that is being destroyed or detached at the moment it fires, so
-- none can outlive what it watches; tracking them would only mean disconnecting
-- a connection from inside its own handler.
local function teardownReader()
	if not readerAlive then return end
	readerAlive = false
	for _, connection in ipairs(readerConnections) do
		if connection.Connected then connection:Disconnect() end
	end
	table.clear(readerConnections)
	-- The two rebinding connections, by name, for the reason given in
	-- C_READER_CONNECTION_TRACKING_20260831.
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	if clientEventConnection then
		clientEventConnection:Disconnect()
		clientEventConnection = nil
	end
	boundClientEvent = nil
	-- The R / ButtonY binding is not an RBXScriptConnection and so was never in
	-- the list. ContextActionService holds it against the action NAME until that
	-- name is unbound, which outlives the gui on its own.
	pcall(function()
		ContextActionService:UnbindAction("Level3ToggleExitReader")
	end)
end

script.Destroying:Connect(teardownReader)
gui.Destroying:Connect(teardownReader)
gui.AncestryChanged:Connect(function()
	if not gui:IsDescendantOf(game) then teardownReader() end
end)
