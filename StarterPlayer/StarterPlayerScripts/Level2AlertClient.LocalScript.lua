-- Level 2 completion announcement.
-- Kept separate from the Level 1 HUD so the existing game interface is untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("Level2AlertEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "Level2AlertGui"
gui.IgnoreGuiInset = false
gui.ResetOnSpawn = false
gui.DisplayOrder = 80
gui.Parent = player:WaitForChild("PlayerGui")

local function syncDispatchSuppression()
	gui.Enabled = player:GetAttribute("ZyntraDispatchClientActive") ~= true
		-- DisplayOrder 80, over the terminal's 55: without this the completion
		-- announcement painted straight across an open Zyntra terminal.
		and not UIDevice.ScreenOwningModalOpen()
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncDispatchSuppression)
UIDevice.OnScreenOwningModalChanged(syncDispatchSuppression)
syncDispatchSuppression()

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 1
shade.Visible = false
shade.Parent = gui

local panel = Instance.new("Frame")
-- Compact, inset-aware toast. On desktop, wide screens keep it left of the
-- persistent objective and medium screens use the remaining left column. On
-- touch the placement is not authored at all: it is whichever rectangle
-- UIDevice reports as clear of the movement controls and big enough for the
-- measured copy. See applySafePanelLayout.
panel.BackgroundColor3 = Color3.fromRGB(5, 13, 16)
panel.BackgroundTransparency = .12
panel.BorderSizePixel = 0
panel.Parent = shade
local panelSize = Instance.new("UISizeConstraint")
-- SEEDED, not authored: every layout pass rewrites both terms from the
-- rectangle the panel was actually given. A MinSize is applied AFTER Size, so
-- any number stated here that the panel's home rectangle cannot hold is a
-- silent override of the layout -- which is precisely what shipped: a 56px
-- MinSize against the 31px the top band leaves clear at 568x320 finished the
-- panel 25px below the band, and the dynamic thumbstick's activation region
-- starts 10px under that edge.
panelSize.MinSize = Vector2.new(0, 0)
panelSize.MaxSize = Vector2.new(560, 140)
panelSize.Parent = panel

-- Published for Level 2 Objective UI. True only while this announcement is
-- actually on screen AND the rectangle it was given is too narrow to share with
-- the upper-right objective column. The name predates the panel being able to
-- live outside the top band; the meaning is unchanged -- "I have taken the
-- rectangle we both wanted, stand down". Mirrored from `shade.Visible` at the one
-- property-changed signal every show and every hide path already lands on, so
-- a path that forgets to clear it is not expressible.
local bandOwnershipWanted = false
local function publishBandOwnership()
	local owns = bandOwnershipWanted and shade.Visible == true and gui.Enabled == true
	player:SetAttribute("Level2AlertOwnsBand", owns or nil)
end
shade:GetPropertyChangedSignal("Visible"):Connect(publishBandOwnership)
gui:GetPropertyChangedSignal("Enabled"):Connect(publishBandOwnership)

-- Forward declarations. These are created far below, and BOTH
-- measuredLineHeights and applySafePanelLayout close over them -- so the
-- declaration has to precede the first of the two. It did not, and the
-- consequence was silent: measuredLineHeights captured GLOBALS instead, its
-- own nil-guard then returned three zeroes, and every line of every
-- announcement was laid out zero pixels tall on every device.
local first, second, run

-- C_L2_ALERT_COPY_FITS_20260830. The three lines were laid out as FRACTIONS of
-- the panel (.24/.22/.24 of its height) with TextScaled and a minimum face. On
-- a 705x338 phone the panel is ~415x75, so the final line got a 382x18 box and
-- its copy -- "CLIMB TO THE TOP DECK AND TAKE THE FLUME OUT", 240x22 at its own
-- minimum face -- rendered outside it. A fraction of a box is not a promise
-- that anything fits inside it.
--
-- The three lines are laid out from MEASURED heights now and the panel is their
-- sum, bounded by the home rectangle it is allowed to occupy.
local TextService = game:GetService("TextService")
local ALERT_MIN_FACE = 11
-- The padding, stated once. The height the panel is SIZED to and the boxes the
-- three lines are GIVEN have to be built from the same numbers, or the panel is
-- fitted to a layout it does not then use.
local ALERT_PAD_TOP, ALERT_PAD_BOTTOM, ALERT_LINE_GAP = 6, 6, 2

-- The width the copy is allowed inside a panel of `panelWidth`, FLOORED.
-- The measurement used `width * .92` and the box was given
-- `math.floor(width * .92)`, so a line could be measured against up to a pixel
-- more room than it was handed and need one more wrapped row than it had.
local function alertCopyWidth(panelWidth)
	return math.max(24, math.floor(panelWidth * .92))
end

-- The three labels are created BELOW this function and the first layout pass
-- runs at module load, so this has to tolerate not having them yet.
-- `bindCurrentCamera()` is re-run once the labels exist.
local function measuredLineHeights(copyWidth)
	if not (first and second and run) then return 0, 0, 0 end
	local function need(label, face)
		if label.Text == nil or label.Text == "" then return 0 end
		-- A visible label with copy in it is never zero pixels tall, whatever a
		-- degenerate wrap width would measure it at.
		return math.max(face + 4, TextService:GetTextSize(label.Text, face, label.Font,
			Vector2.new(copyWidth, 100000)).Y)
	end
	return need(first, 16), need(second, 13),
		(run.Visible and need(run, ALERT_MIN_FACE) or 0)
end

-- What the announcement needs, in pixels, if the panel is `panelWidth` wide.
-- This is the number the home rectangle is tested against BEFORE the panel is
-- placed, and it is the same sum the block below lays the lines out to.
local function measuredCopyHeight(panelWidth)
	local firstNeed, secondNeed, runNeed = measuredLineHeights(alertCopyWidth(panelWidth))
	return ALERT_PAD_TOP + firstNeed + ALERT_LINE_GAP + secondNeed + ALERT_LINE_GAP
		+ runNeed + ALERT_PAD_BOTTOM
end

-- A readability PREFERENCE for the panel's width, not a clamp. It used to be a
-- floor -- and a UISizeConstraint MinSize as well -- so on a device whose home
-- rectangle is narrower than this the panel was widened past the rectangle it
-- had just been fitted to and drew over the control column.
local ALERT_PREFERRED_WIDTH = 180

-- Divide a home rectangle with the upper-right objective column, and say who
-- owns it. Returns the width the panel may use and whether the objective has to
-- stand down for it.
--
-- C_OBJECTIVES_UPPER_RIGHT_20260830: the pump readout moved from the
-- bottom-centre corridor into the top right, which is inside every rectangle
-- this panel can be given. The two are the only pair on Level 2 that can be on
-- screen together -- the announcement fires while the objective panel is up --
-- so this panel yields the width rather than drawing across it. Where the two
-- genuinely do not both fit, the rectangle is not divided: the announcement --
-- transient, at most five seconds, and restating the very state the objective
-- panel is showing -- takes it outright and the objective stands down for its
-- duration. Dividing a 380px landscape band into 134 + 236 would have produced
-- two illegible panels.
--
-- The reserved rectangle comes from UIDevice, not from a copied literal, so the
-- two files cannot drift.
local function shareHomeWithObjective(home)
	local homeWidth = math.floor(math.max(0, home.Width))
	local column = UIDevice.ObjectiveColumn(2)
	-- BOTH axes. The vertical test alone was enough while the home was always
	-- the top band, which the column always overlaps horizontally too. It is not
	-- enough for ModalArea: a column entirely outside the home horizontally
	-- would still have produced `column.Left - 10` as a right edge, i.e. a
	-- negative width and a spurious hand-over of a rectangle nothing contested.
	local shares = column.Width > 0 and column.Height > 0
		and column.Top < home.Bottom and column.Bottom > home.Top
		and column.Left < home.Right and column.Right > home.Left
	if not shares then return homeWidth, false end
	local available = math.floor(math.min(home.Right, column.Left - 10) - home.Left)
	if available >= ALERT_PREFERRED_WIDTH then
		return math.min(available, homeWidth), false
	end
	return homeWidth, true
end

local cameraViewportConnection
local function applySafePanelLayout()
	-- The three labels are created BELOW this function and the first pass runs
	-- at module load. There is no copy to measure yet and therefore no honest
	-- home rectangle to choose, so the pass is skipped outright rather than
	-- fitting the panel to three zero-height lines. Nothing is on screen at that
	-- point; the call made once the labels exist is the first real one, and
	-- every announcement re-runs this before it is shown.
	if not (first and second and run) then
		bandOwnershipWanted = false
		publishBandOwnership()
		return
	end

	local layout = UIDevice.Layout()
	local viewport = layout.Viewport
	-- Reset first: only the touch branch can claim the shared rectangle, and a
	-- desktop reflow after a touch one must not inherit the claim.
	bandOwnershipWanted = false

	-- The width the panel was given and the height it may not exceed. On touch
	-- both come from a rectangle UIDevice owns; on desktop they are the authored
	-- composition, which is unchanged.
	local panelWidth, heightCeiling

	if layout.IsTouch then
		-- ── THE HOME RECTANGLE ──────────────────────────────────────────────
		-- C_L2_ALERT_HOME_20260830. The panel was pinned into TopBand
		-- unconditionally and then floored at 56px by its own UISizeConstraint
		-- MinSize, which is applied after Size and so won silently.
		--
		-- MEASURED at 568x320, the smallest device in the matrix: the band is
		-- 352x31 (12..364 x 8..39), the dynamic thumbstick's activation region
		-- starts at y 49, and the shorter of the two shipped announcements --
		-- "PRESSURE EQUALIZED" / "GRAND HALL UNSEALED" / "CLIMB TO THE TOP DECK
		-- AND TAKE THE FLUME OUT" -- measures 76px at the 213px the band leaves
		-- beside the objective column. So the panel finished at y 64: 25px below
		-- the band and 15px inside the region every movement touch is read from.
		--
		-- A rectangle that cannot hold the copy is not a home. The band is used
		-- while it can hold the MEASURED copy plus its padding, and ModalArea --
		-- the largest rectangle UIDevice can find that is clear of EVERY
		-- movement zone -- is used when it cannot. At 568x320 that is the
		-- 129x246 column between the thumbstick and the control cluster, which
		-- holds the same announcement in 124px.
		--
		-- RE-MEASURED 20260831, this time by driving the copy through the seam at
		-- the bottom of this file instead of writing shade.Visible on a panel with
		-- no text in it. The two WIDTH figures above predate Zones.Controls being
		-- derived from NoiseReporter's own edge/buttonSize/gap constants and are
		-- now understated: with the shipping cluster the band is 380x31 at
		-- (12,66)-(392,97) and the modal column is 157x246. Nothing about the
		-- decision moves. The band leaves 213px beside the objective column, the
		-- three authored lines need 79px at that width and the band has 31, so the
		-- home is ModalArea and the announcement lands 156x125 at
		-- (235,66)-(391,191): inside safe, clear of the thumbstick by 8px and of
		-- the control column by 9px, three lines at 16/13/11 wrapping to 2/2/3
		-- rows, the last of them finishing at y 185 with 6px of padding under it.
		local band = layout.TopBand
		local home = band
		local width, owns = shareHomeWithObjective(home)
		-- The band is built clear of the thumbstick and the control column, but
		-- the JUMP rectangle is anchored independently of both and the union of
		-- the registered controls can move the column's top edge, so the band is
		-- asked rather than assumed. ModalArea is checked against all three by
		-- UIDevice itself.
		local bandUsable = band.Width >= 1 and band.Height >= 1
			and UIDevice.OverlapsMovementZone(band.Left, band.Top, band.Right, band.Bottom) == nil
		if not (bandUsable and measuredCopyHeight(width) <= band.Height) then
			local modal = layout.ModalArea
			if modal.Width >= 1 and modal.Height >= 1 then
				home = modal
				width, owns = shareHomeWithObjective(home)
			end
		end

		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UIDevice.LocalPosition(gui, home.Left, home.Top)
		panelWidth = math.max(1, width)
		heightCeiling = math.max(1, math.floor(home.Height))
		panel.Size = UDim2.fromOffset(panelWidth, heightCeiling)
		bandOwnershipWanted = owns
	elseif viewport.X < 600 then
		panel.AnchorPoint = Vector2.new(.5, 0)
		panel.Position = UDim2.new(.5, 0, 0, 158)
		panel.Size = UDim2.new(1, -24, 0, 112)
		heightCeiling = 200
	elseif viewport.X < 860 then
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(12, 70)
		panel.Size = UDim2.fromOffset(math.max(180, viewport.X - 272), 118)
		heightCeiling = 200
	else
		panel.AnchorPoint = Vector2.new(.5, .5)
		panel.Position = UDim2.fromScale(.43, .24)
		panel.Size = UDim2.new(.56, 0, 0, 132)
		heightCeiling = 200
	end

	-- The panel's width may be an OFFSET (touch, and the mid-width branch) or a
	-- SCALE (the wide-screen branch). Reading only the offset made it 0 on the
	-- wide branch, and writing the size back as `fromOffset(0, h)` then made the
	-- panel itself zero pixels wide.
	if not panelWidth then
		panelWidth = panel.Size.X.Offset
		if panelWidth <= 0 then panelWidth = panel.AbsoluteSize.X end
		if panelWidth <= 0 then panelWidth = viewport.X * panel.Size.X.Scale end
		panelWidth = math.max(ALERT_PREFERRED_WIDTH, panelWidth)
	end

	-- Lay the three lines out from their MEASURED heights and let the panel be
	-- the sum. Offsets, not fractions: a fraction of a panel that is itself
	-- clamped to a rectangle produces a box nobody measured anything against.
	local copyWidth = alertCopyWidth(panelWidth)
	local firstNeed, secondNeed, runNeed = measuredLineHeights(copyWidth)
	local padX = math.floor(panelWidth * .04)
	local y = ALERT_PAD_TOP
	first.TextScaled = false
	second.TextScaled = false
	run.TextScaled = false
	first.TextSize, second.TextSize, run.TextSize = 16, 13, ALERT_MIN_FACE
	first.Position = UDim2.fromOffset(padX, y)
	first.Size = UDim2.fromOffset(copyWidth, firstNeed)
	y += firstNeed + ALERT_LINE_GAP
	second.Position = UDim2.fromOffset(padX, y)
	second.Size = UDim2.fromOffset(copyWidth, secondNeed)
	y += secondNeed + ALERT_LINE_GAP
	run.Position = UDim2.fromOffset(padX, y)
	run.Size = UDim2.fromOffset(copyWidth, runNeed)
	y += runNeed
	local needed = y + ALERT_PAD_BOTTOM
	-- The home rectangle is the ceiling and the measurement is the height. The
	-- panel never grows past its home: on touch the home is the only rectangle
	-- on screen that is clear of the movement zones, so a panel that exceeds it
	-- is a panel taking the taps meant for the thumbstick.
	local height = math.max(1, math.min(needed, heightCeiling))
	if not layout.IsTouch then
		-- Desktop keeps its authored 56px floor. There is no movement zone under
		-- a desktop panel to fall into, and the composition above assumes it.
		height = math.max(56, height)
	end
	-- The X term is PRESERVED exactly as the branch above set it; only the
	-- height is replaced.
	panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, height)
	-- The constraint has to state the same numbers the measurement produced, or
	-- it clamps the panel to a size nothing was measured against. MinSize in
	-- particular can only ever be as large as what was actually laid out -- a
	-- floor larger than the home rectangle is how the panel left the band.
	--
	-- Released to zero FIRST because both terms now move in both directions
	-- between passes and the engine rejects a MinSize above the stored MaxSize:
	-- writing a 56px floor while the previous pass's 31px ceiling is still on
	-- the constraint throws, and the layout after it never runs. The old code
	-- could not hit this only because its MinSize was the constant (180, 56) and
	-- its MaxSize was floored at the same pair.
	panelSize.MinSize = Vector2.zero
	panelSize.MaxSize = Vector2.new(math.max(ALERT_PREFERRED_WIDTH, panelWidth), height)
	panelSize.MinSize = Vector2.new(math.min(ALERT_PREFERRED_WIDTH, panelWidth),
		math.min(56, height))

	publishBandOwnership()
end

local function bindCurrentCamera()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applySafePanelLayout)
	end
	applySafePanelLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera)
UIDevice.Changed:Connect(applySafePanelLayout)
bindCurrentCamera()

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(54, 210, 221)
stroke.Thickness = 3
stroke.Parent = panel

first = Instance.new("TextLabel")
first.BackgroundTransparency = 1
first.Position = UDim2.fromScale(.04, .07)
first.Size = UDim2.fromScale(.92, .24)
first.Font = Enum.Font.Code
first.Name = "AlertLine1"
first.TextColor3 = Color3.fromRGB(126, 224, 235)
first.TextWrapped = true
first.TextYAlignment = Enum.TextYAlignment.Top
first.Parent = panel
local firstSize = Instance.new("UITextSizeConstraint")
firstSize.MinTextSize = 14
firstSize.MaxTextSize = 27
firstSize.Parent = first

second = first:Clone()
local inheritedSecondSize = second:FindFirstChildOfClass("UITextSizeConstraint")
if inheritedSecondSize then inheritedSecondSize:Destroy() end
second.Name = "AlertLine2"
second.Position = UDim2.fromScale(.04, .36)
second.Size = UDim2.fromScale(.92, .22)
second.TextColor3 = Color3.fromRGB(231, 218, 145)
second.Parent = panel
local secondSize = Instance.new("UITextSizeConstraint")
secondSize.MinTextSize = 12
secondSize.MaxTextSize = 23
secondSize.Parent = second

run = Instance.new("TextLabel")
run.Name = "AlertRunLine"
run.Position = UDim2.fromScale(.04, .65)
run.Size = UDim2.fromScale(.92, .24)
run.BackgroundTransparency = 1
run.Font = Enum.Font.Code
run.TextColor3 = Color3.fromRGB(231, 218, 145)
run.TextStrokeColor3 = Color3.fromRGB(35, 28, 12)
run.TextStrokeTransparency = .72
run.TextWrapped = true
run.TextYAlignment = Enum.TextYAlignment.Top
run.Visible = false
run.Parent = panel
local runSize = Instance.new("UITextSizeConstraint")
runSize.MinTextSize = 11
runSize.MaxTextSize = 19
runSize.Parent = run

-- Now that the three labels exist, lay them out for real.
applySafePanelLayout()

local valveVisionEnabled = player:GetAttribute("DevEspEnabled") == true
local valveHighlights = {}

local function clearValveHighlights()
	for _, highlight in ipairs(valveHighlights) do
		highlight:Destroy()
	end
	table.clear(valveHighlights)
end

local function refreshValveHighlights()
	clearValveHighlights()
	if not valveVisionEnabled or workspace:GetAttribute("SelectedLevel") ~= 2 then return end
	local world = workspace:FindFirstChild("Level 2 Generated World")
	local objectives = world and world:FindFirstChild("Level 2 Objectives")
	if not objectives then return end
	for _, valve in ipairs(objectives:GetChildren()) do
		if valve:IsA("Model") and valve.Name:match("^Level 2 Pump Station") then
			-- Each station publishes its lever handle colour; use it so the dev
			-- ESP distinguishes the three pumps instead of showing generic green.
			local color = valve:GetAttribute("Level2_LeverHandleColorValue")
				or Color3.fromRGB(80, 220, 180)
			local highlight = Instance.new("Highlight")
			highlight.Name = "ValveVisionHighlight"
			highlight.Adornee = valve
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = color
			highlight.OutlineColor = color:Lerp(Color3.new(1,1,1), .25)
			highlight.FillTransparency = .58
			highlight.OutlineTransparency = .05
			highlight.Parent = workspace.CurrentCamera
			table.insert(valveHighlights, highlight)
		end
	end
end

-- DevCheats owns B/V consistently in both levels. Valve vision follows B via
-- this local attribute, leaving V exclusively for noclip.
player:GetAttributeChangedSignal("DevEspEnabled"):Connect(function()
	valveVisionEnabled = player:GetAttribute("DevEspEnabled") == true
	refreshValveHighlights()
end)

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	refreshValveHighlights()
end)

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Level 2 Generated World" and valveVisionEnabled then
		task.wait(.5)
		refreshValveHighlights()
	end
end)

local announcementSerial = 0
-- When the announcement now on screen is due to begin fading, on the WALL
-- clock. Only the Studio seam at the bottom of this file reads it, and only to
-- give a live announcement back the remainder of its hold after the probe has
-- borrowed the panel; a production round never looks at it.
--
-- `time()` -- elapsed game time -- and NOT os.clock(), which on this engine is
-- process CPU time. A Studio session burns CPU time at a fraction of wall time,
-- so an os.clock deadline would hand a restored announcement a hold several
-- times longer than the one it had left.
local announcementHoldUntil = 0
local activeTweens = {}

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do tween:Cancel() end
	table.clear(activeTweens)
end

local function tween(instance, info, properties)
	local created = TweenService:Create(instance, info, properties)
	table.insert(activeTweens, created)
	created:Play()
	return created
end

local function hideAlert()
	announcementSerial += 1
	announcementHoldUntil = 0
	cancelTweens()
	shade.Visible = false
	panel.Visible = true
	run.Visible = false
end

-- C_L2_ALERT_HAS_NO_SEAM_20260831 -- WHAT SHIPPED BROKEN, in the test rather
-- than in the game, which is worse: it made the game look tested.
--
-- The device matrix "showed" this announcement by reaching into the ScreenGui
-- and writing `shade.Visible = true` on the frame it found. That paints the
-- panel and drives NOTHING else. The three labels keep whatever text was last
-- put in them, which in a matrix run is the empty string they were created
-- with; measuredLineHeights answers 0, 0, 0 for empty copy; the panel is laid
-- out fourteen pixels tall, and every child fits inside it trivially. The row
-- was green because it was measuring an empty box. The precise defect
-- C_L2_ALERT_COPY_FITS_20260830 was opened for -- the final line rendering
-- outside the box it was given -- cannot be seen by a test that never sets a
-- final line.
--
-- So the announcement is cut at the three seams it already had, and each is
-- named:
--
--   announcementAllowed()  the GATE: is this client somewhere an announcement
--                          means anything at all.
--   presentAlert()         the PRESENTATION: copy in, measured, laid out, on
--                          screen. Everything the fit of the panel depends on.
--   dismissAfter()         the DISMISSAL: the hold and the fade out.
--
-- `onAlertEvent` is those three in order and is the only thing connected to the
-- remote, so the production path is unchanged. The Studio probe at the bottom
-- of this file drives the same upvalues -- not a copy of their bodies -- so a
-- matrix that invokes it exercises the production measurement and the
-- production layout against real copy.
--
-- THE PRESENTATION HAD TO STOP YIELDING for that to be possible. It used to
-- `task.wait(hold)` in the middle of the handler thread. A BindableFunction
-- Invoke blocks until OnInvoke returns, so a presentation that waits out its
-- own hold would hold the harness for up to five seconds and then take the
-- panel down again before it could be measured. task.delay schedules the
-- identical fade on its own thread; the serial guard that already made a
-- superseded fade a no-op is unchanged, and so is every visible timing.
local function dismissAfter(serial, hold)
	task.delay(hold, function()
		if serial ~= announcementSerial then return end
		tween(panel, TweenInfo.new(.28), {BackgroundTransparency = 1})
		tween(stroke, TweenInfo.new(.28), {Transparency = 1})
		tween(first, TweenInfo.new(.24), {TextTransparency = 1})
		tween(second, TweenInfo.new(.24), {TextTransparency = 1})
		if run.Visible then
			tween(run, TweenInfo.new(.24), {TextTransparency = 1, TextStrokeTransparency = 1})
		end
		task.delay(.32, function()
			if serial ~= announcementSerial then return end
			shade.Visible = false
		end)
	end)
end

-- Returns the serial it claimed, so a caller that wants to know whether its own
-- announcement is still the one on screen can compare rather than guess.
local function presentAlert(line1, line2, finalLine, holdSeconds)
	announcementSerial += 1
	local serial = announcementSerial
	cancelTweens()

	first.Text = tostring(line1 or "")
	second.Text = tostring(line2 or "")
	run.Text = tostring(finalLine or "")
	run.Visible = run.Text ~= ""
	-- The copy decides the layout, so a new cue re-runs it before the panel
	-- is shown rather than inheriting the previous announcement's boxes.
	applySafePanelLayout()
	first.TextTransparency = 0
	second.TextTransparency = 0
	run.TextTransparency = 0
	run.TextStrokeTransparency = .72
	panel.BackgroundTransparency = .12
	stroke.Transparency = .15
	panel.Visible = true
	shade.Visible = true
	-- Status messages must never black out the play space or mobile controls.
	shade.BackgroundTransparency = 1

	local hold = math.clamp(typeof(holdSeconds) == "number" and holdSeconds or 1.7, .7, 5)
	announcementHoldUntil = time() + hold
	dismissAfter(serial, hold)
	return serial
end

local function announcementAllowed()
	return workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
end

local function onAlertEvent(line1, line2, finalLine, holdSeconds)
	if not announcementAllowed() then return end
	presentAlert(line1, line2, finalLine, holdSeconds)
end

-- RECORDED as it is made, the way the Level 3 reader records its tap wiring and
-- for the same reason: a probe that calls the handler stays green if somebody
-- deletes the Connect line, because the handler still works and the server can
-- no longer reach it. The RBXScriptConnection exists only because the
-- connection was actually made, and `Connected` says whether it still is.
local alertWiring = {
	Handler = onAlertEvent,
	Connection = event.OnClientEvent:Connect(onAlertEvent),
}

-- Studio-only measurement seam for UIRegression, inert in production: it is a
-- BindableFunction nobody invokes, parented to this file's own ScreenGui, in
-- the shape UIRegressionReaderProbe and UIRegressionZyntraStoreProbe already
-- use -- a string action, plain scalars in and out.
--
-- ACTIONS
--   "show", line1, line2, finalLine, holdSeconds
--        Puts that copy on screen through the production path and answers with
--        the rectangles it produced. The FIRST show since the last restore
--        captures everything it is about to overwrite.
--   "restore"   undoes the borrow exactly. See below.
--   "wiring"    "remote=<connected>/<is the production handler>".
--   anything else, "rects" included, answers without changing anything.
--
-- THE ANSWER is one string. Each rect is left,top,right,bottom in the SAME
-- space UIDevice.Layout() reports its rectangles in -- AbsolutePosition already
-- is that space, because every panel here is placed through
-- UIDevice.LocalPosition, which is exactly that conversion, so a synthetic
-- fixture's analytic edges and these live edges are directly comparable.
if RunService:IsStudio() then
	local saved: any = nil

	local function rectText(object)
		local origin, size = object.AbsolutePosition, object.AbsoluteSize
		return string.format("%.0f,%.0f,%.0f,%.0f", origin.X, origin.Y,
			origin.X + size.X, origin.Y + size.Y)
	end

	-- ONE FRAME first, every time, then read. AbsolutePosition is committed by
	-- the render pass and not by the property write, so a probe that answered in
	-- the frame it laid the panel out would hand back the PREVIOUS
	-- announcement's rectangles -- the same one-frame-stale reading UIDevice
	-- refuses to accept from measuredControlUnion.
	local function answer()
		task.wait()
		return string.format(
			"panel=%s line1=%s line2=%s run=%s runVisible=%s owns=%s shown=%s gate=%s",
			rectText(panel), rectText(first), rectText(second), rectText(run),
			tostring(run.Visible),
			tostring(player:GetAttribute("Level2AlertOwnsBand") == true),
			tostring(shade.Visible and gui.Enabled),
			tostring(announcementAllowed()))
	end

	-- Everything presentAlert writes, and nothing else. gui.Enabled is absent on
	-- purpose: the probe never touches it, because syncDispatchSuppression and
	-- the harness's own reveal both own it, and a probe that restored a stale
	-- Enabled would undo whichever of them wrote last.
	local function capture()
		-- Present only when an announcement was genuinely on screen, and then it
		-- is what is left of that announcement's hold.
		local remaining: number? = nil
		if shade.Visible then
			remaining = math.max(0, announcementHoldUntil - time())
		end
		return {
			Line1 = first.Text, Line2 = second.Text, RunLine = run.Text,
			RunVisible = run.Visible,
			Line1Transparency = first.TextTransparency,
			Line2Transparency = second.TextTransparency,
			RunTransparency = run.TextTransparency,
			RunStrokeTransparency = run.TextStrokeTransparency,
			PanelVisible = panel.Visible,
			PanelTransparency = panel.BackgroundTransparency,
			StrokeTransparency = stroke.Transparency,
			ShadeVisible = shade.Visible,
			ShadeTransparency = shade.BackgroundTransparency,
			Remaining = remaining,
		}
	end

	-- A REAL restore, and the case that makes it one is an announcement already
	-- up when the probe was invoked. Presenting bumps the serial, and a bumped
	-- serial is precisely what turns the live announcement's own scheduled fade
	-- into a no-op -- so a probe that only put the pixels back would leave that
	-- announcement frozen on screen for the rest of the round with nothing alive
	-- to take it down. The remainder of its hold is captured and the dismissal
	-- is re-armed from it under the fresh serial.
	local function restore()
		local previous = saved
		saved = nil
		if previous == nil then return answer() end
		announcementSerial += 1
		cancelTweens()
		first.Text = previous.Line1
		second.Text = previous.Line2
		run.Text = previous.RunLine
		run.Visible = previous.RunVisible
		-- The geometry is RE-DERIVED through the production layout rather than
		-- replayed from stored UDim2s. It is a pure function of the copy and the
		-- device, so re-running it restores it exactly -- and a stored rectangle
		-- would be wrong anyway whenever the harness changed the fixture viewport
		-- between the borrow and the return.
		applySafePanelLayout()
		first.TextTransparency = previous.Line1Transparency
		second.TextTransparency = previous.Line2Transparency
		run.TextTransparency = previous.RunTransparency
		run.TextStrokeTransparency = previous.RunStrokeTransparency
		panel.BackgroundTransparency = previous.PanelTransparency
		stroke.Transparency = previous.StrokeTransparency
		panel.Visible = previous.PanelVisible
		shade.BackgroundTransparency = previous.ShadeTransparency
		shade.Visible = previous.ShadeVisible
		if previous.Remaining ~= nil then
			announcementHoldUntil = time() + previous.Remaining
			dismissAfter(announcementSerial, previous.Remaining)
		else
			announcementHoldUntil = 0
		end
		return answer()
	end

	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionLevel2AlertProbe"
	probe.OnInvoke = function(action, line1, line2, finalLine, holdSeconds)
		if action == "show" then
			if saved == nil then saved = capture() end
			-- Through the CONNECTED HANDLER wherever a real announcement would get
			-- through, and through the presentation it calls where it would not.
			-- Both land in presentAlert with the same arguments, so the answer is
			-- the same either way; taking the handler when the gate allows it means
			-- a broken onAlertEvent fails the matrix instead of being stepped over.
			--
			-- The gate is the ONE production check the probe can be made to skip,
			-- and it says so in every answer (`gate=`). The matrix deliberately does
			-- not put the client in a running Level 2 round -- doing that wakes
			-- every other Level 2 client script on the machine, which is a far
			-- larger disturbance than the one this probe promises to undo.
			if announcementAllowed() then
				onAlertEvent(line1, line2, finalLine, holdSeconds)
			else
				presentAlert(line1, line2, finalLine, holdSeconds)
			end
			return answer()
		elseif action == "restore" then
			return restore()
		elseif action == "wiring" then
			return string.format("remote=%s/%s",
				tostring(alertWiring.Connection.Connected),
				tostring(alertWiring.Handler == onAlertEvent))
		end
		return answer()
	end
	probe.Parent = gui
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	if workspace:GetAttribute("SelectedLevel") ~= 2 then hideAlert() end
end)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") ~= true then hideAlert() end
end)
