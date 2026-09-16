-- Lucky Wheel Client  (LUCKY_WHEEL_20260916, Trello card 103)
--
-- The daily supply wheel as an actual wheel. It is its own modal, opened from
-- its own rail button (PlayerScripts.OpenLuckyWheel), and it replaces the list
-- the terminal's Rewards tab used to draw.
--
-- WHAT THIS FILE IS ALLOWED TO DECIDE: nothing about the prize. The server
-- picks it inside its own transaction, writes it, and only then answers; by the
-- time `Daily.WheelLast` reaches this client the outcome is already durable.
-- The disc is a REPLAY of a recorded result, which is why it can be skipped,
-- cut short by closing the panel, or -- on a push carrying the SAME Serial --
-- not played at all. There is no client roll anywhere in this file.
--
-- WHY THE DISC IS 180 FRAMES AND NOT ARTWORK. A sector's size has to be
-- PROPORTIONAL to the server's own weight (45/20/20/5/10 -> 162/72/72/18/36
-- degrees), because the owner's rule for this card is that equal-looking
-- sectors must never imply equal odds. An uploaded disc image would freeze one
-- particular weight table into a PNG and silently lie the day the weights move.
-- 180 rotated arms, coloured from the live config, cannot: change a
-- weight and the wedge changes with it. The legend beside the disc prints the
-- real percentage for every prize, including the 18-degree one that is too
-- narrow to carry a label.
--
-- THE POINTER DOES NOT MOVE. The rail's wheel icon (rbxassetid://111918608092047)
-- has a pointer baked into it and is a BUTTON ICON only -- rotating it would
-- rotate its pointer too. The pointer here is a separate stationary marker at
-- 12 o'clock and the disc turns underneath it.
--
-- ROTATION, stated once because two places depend on it. GuiObject.Rotation is
-- clockwise-positive, so the stationary pointer at 12 o'clock sees wheel angle
-- `(-Rotation) % 360`. For the awarded sector [start, start+width) the landing
-- angle is `start + jitter`, jitter deterministic from WheelLast.Serial so a
-- replay of the same result lands on the same degree, and the tween's goal is
-- `current - (current % 360) + -(start + jitter) + 360 * turns`. Every term
-- after the first two is a whole number of turns plus the target, so the goal
-- always moves FORWARD and always resolves to that same angle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local getProfile = remotes:WaitForChild("ZyntraGetProfile")
local profileChanged = remotes:WaitForChild("ZyntraProfileChanged")

-- Create-if-absent on both sides, the pattern RoundExitPrompt already uses: the
-- rail button and this file load in an order neither of them controls.
local openEvent = playerScripts:FindFirstChild("OpenLuckyWheel")
if not openEvent then
	openEvent = Instance.new("BindableEvent")
	openEvent.Name = "OpenLuckyWheel"
	openEvent.Parent = playerScripts
end

-- The terminal's two accents. Teal is the system colour, gold is money.
local TEAL = Color3.fromRGB(68, 221, 196)
local GOLD = Color3.fromRGB(255, 203, 79)

local SPOKES = 180              -- one frame per 2 degrees
local SPIN_SECONDS = 4.2
local SPIN_TURNS = 5
local REDUCED_SECONDS = 1.4     -- ReduceFlashing: one slow turn, no strobe
local REDUCED_TURNS = 1
local JITTER_MARGIN = 4         -- never land within 4 degrees of a boundary
local ACTION_TIMEOUT = 6        -- the page module's own no-answer window
local LABEL_MIN_DEGREES = 36    -- narrower than this and a label cannot be read
local DESIGN_WIDTH, DESIGN_HEIGHT = 820, 620
local TWO_COLUMN_MIN = 560      -- below this the legend goes under the disc
local SCROLLBAR_ROOM = 8

-- Three faces, the same tiers and the same 11px floor the daily rewards page
-- uses: 1 phone (compact and touch), 2 tablet (touch), 3 pointer.
local FACES = {
	{Pad = 12, Gap = 10, Eyebrow = 11, Title = 20, Body = 11, Odds = 11,
		Row = 44, Swatch = 10, Sector = 11},
	{Pad = 14, Gap = 12, Eyebrow = 11, Title = 24, Body = 12, Odds = 12,
		Row = 46, Swatch = 12, Sector = 12},
	{Pad = 16, Gap = 14, Eyebrow = 11, Title = 28, Body = 13, Odds = 13,
		Row = 34, Swatch = 12, Sector = 13},
}

-- COLOUR CARRIES THE PRIZE FAMILY, BRIGHTNESS SEPARATES NEIGHBOURS. Three
-- families (tokens gold, potions teal, shields mint) would put two gold wedges
-- and two teal wedges side by side in the shipped order, and a 162-degree gold
-- next to a 72-degree gold reads as ONE 234-degree wedge -- which is exactly the
-- "equal sectors implying wrong odds" failure, inverted. Every second sector is
-- therefore drawn at 62% brightness, so each of the five is distinguishable from
-- both of its neighbours while still saying what kind of prize it is. The legend
-- swatches use the same colours, so the legend is the key.
local FAMILY = {
	Tokens = GOLD,
	SpeedPotion = TEAL,
	EntityShield = UIStyle.Color.Positive,
}
local function familyColor(reward)
	if type(reward) ~= "table" then return UIStyle.Color.Accent end
	if reward.Kind == "Tokens" then return FAMILY.Tokens end
	return FAMILY[tostring(reward.Key or "")] or UIStyle.Color.Accent
end
-- Color3 has no arithmetic, so the darker step is built from scaled NUMBERS.
local function dim(color: Color3, factor: number): Color3
	return Color3.fromRGB(
		math.floor(color.R * 255 * factor + 0.5),
		math.floor(color.G * 255 * factor + 0.5),
		math.floor(color.B * 255 * factor + 0.5))
end

-- The disc's own copy. The config Label ("1 Research Token") does not fit a
-- 72-degree wedge on a phone; the LEGEND carries the full label, the wedge
-- carries this.
local SHORT_WORD = {Tokens = "TOKEN", SpeedPotion = "POTION", EntityShield = "SHIELD"}
local function shortLabel(entry): string
	local reward = type(entry.Reward) == "table" and entry.Reward or nil
	local amount = math.max(1, math.floor(reward and tonumber(reward.Amount) or 1))
	local word = reward and (reward.Kind == "Tokens" and SHORT_WORD.Tokens
		or SHORT_WORD[tostring(reward.Key or "")]) or nil
	if not word then return string.upper(tostring(entry.Label or "PRIZE")) end
	return amount .. " " .. word .. (amount == 1 and "" or "S")
end

-- Whole percent, from the SERVER's own weights -- never a hand-written string.
local function oddsText(weight: number, total: number): string
	if total <= 0 then return "--" end
	return tostring(math.floor(weight / total * 100 + 0.5)) .. "%"
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", whole // 3600, (whole % 3600) // 60, whole % 60)
end

-- Deterministic from the Serial, and deliberately NOT Random.new: the same
-- recorded result must land on the same degree every time it is drawn, on every
-- client, whether it is being animated or parked by a rejoin.
local function jitterFor(serial: number, width: number): number
	if width <= JITTER_MARGIN * 2 then return width / 2 end
	local mixed = (math.floor(serial) * 2654435761) % 1000003
	return JITTER_MARGIN + (width - JITTER_MARGIN * 2) * (mixed / 1000003)
end

-- ── the sectors, straight off the config ──────────────────────────────────
-- Cumulative weights, not degrees: the spoke -> sector test below is an integer
-- cross-multiplication so a 45% wedge gets exactly 81 of the 180 spokes rather
-- than 80 or 82 depending on how 162.00000000000003 rounds.
local sectors = {}
local weightTotal = 0
do
	local wheel = type(Config.DailyRewards) == "table" and Config.DailyRewards.Wheel or nil
	for _, entry in ipairs(type(wheel) == "table" and wheel or {}) do
		if type(entry) == "table" then
			weightTotal += math.max(0, tonumber(entry.Weight) or 0)
		end
	end
	local cumulative = 0
	for order, entry in ipairs(type(wheel) == "table" and wheel or {}) do
		if type(entry) == "table" then
			local weight = math.max(0, tonumber(entry.Weight) or 0)
			local base = familyColor(entry.Reward)
			local start = weightTotal > 0 and cumulative / weightTotal * 360 or 0
			cumulative += weight
			table.insert(sectors, {
				Key = tostring(entry.Key or ""),
				Label = tostring(entry.Label or "Reward"),
				Short = shortLabel(entry),
				Weight = weight,
				Odds = oddsText(weight, weightTotal),
				Color = order % 2 == 0 and dim(base, 0.62) or base,
				Before = cumulative - weight, -- cumulative weight at this sector's start
				After = cumulative,
				Start = start,
				Width = weightTotal > 0 and weight / weightTotal * 360 or 0,
			})
		end
	end
end

local function sectorByKey(key: string)
	for order, sector in ipairs(sectors) do
		if sector.Key == key then return order, sector end
	end
	return nil, nil
end

-- ── chrome ────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "LuckyWheelGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 118
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- the terminal's space
gui.Parent = playerGui

-- Active, so a tap aimed past the panel reaches nothing behind it.
local shade = Instance.new("Frame")
shade.Name = "LuckyWheelShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.5
shade.BorderSizePixel = 0
shade.Active = true
shade.Visible = false
shade.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "LuckyWheelPanel"
panel.ClipsDescendants = true
panel.Parent = shade
UIStyle.panel(panel, {
	Background = UIStyle.Color.Card,
	Transparency = UIStyle.Transparency.Card,
	Radius = UIStyle.Radius.Card,
	StrokeTransparency = UIStyle.Stroke.CardTransparency,
})

local function newLabel(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local eyebrow = newLabel(panel, "Eyebrow", "ZYNTRA // DAILY SUPPLY")
UIStyle.readout(eyebrow, {TextSize = 11})

local title = newLabel(panel, "Title", "LUCKY WHEEL")
UIStyle.title(title, {TextSize = 28})

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Text = "CLOSE"
closeButton.AutoButtonColor = true
closeButton.Parent = panel
UIStyle.button(closeButton, {TextColor = UIStyle.Color.Body, TextSize = 12})

local statusLine = newLabel(panel, "StatusLine", "")
UIStyle.readout(statusLine, {TextColor = UIStyle.Color.Muted, TextSize = 11})

local body = Instance.new("ScrollingFrame")
body.Name = "WheelBody"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 5
body.ScrollBarImageColor3 = TEAL
body.CanvasSize = UDim2.new()
body.Parent = panel

-- ── the disc ──────────────────────────────────────────────────────────────
local discHolder = Instance.new("Frame")
discHolder.Name = "DiscHolder"
discHolder.BackgroundTransparency = 1
discHolder.Parent = body

local disc = Instance.new("Frame")
disc.Name = "WheelDisc"
disc.AnchorPoint = Vector2.new(0.5, 0.5)
disc.BackgroundTransparency = 1
disc.BorderSizePixel = 0
disc.ZIndex = 1
disc.Parent = discHolder

-- Which sector owns the slice centred on spoke `index` (0-based, so its ray is
-- at index * 360/SPOKES degrees). Integer cross-multiplication against the
-- cumulative WEIGHTS, never against a float degree.
local function sectorForSpoke(index: number): number
	if weightTotal <= 0 then return 1 end
	local scaled = index * weightTotal
	for order, sector in ipairs(sectors) do
		if scaled < sector.After * SPOKES then return order end
	end
	return #sectors
end

-- EACH SLICE IS TWO FRAMES, AND THAT IS NOT DECORATION. Roblox rotates a
-- GuiObject about the CENTRE OF ITS OWN RECTANGLE -- AnchorPoint only places
-- the rectangle, it is not the pivot. A single half-length frame anchored at
-- (0.5, 1) on the hub therefore spins about a point radius/2 ABOVE the hub, and
-- 180 of those draw a flower ring rather than a disc. So the thing that rotates
-- is an "Arm": a transparent frame the FULL DIAMETER tall, centred on the hub,
-- whose own centre is therefore the disc's centre under either pivot rule. The
-- coloured Spoke inside it is the TOP HALF only (Size 1, 0.5 at the origin), so
-- Arm rotation 0 still paints the 12 o'clock ray. Only the arm is resized on a
-- layout pass; the spoke follows by scale.
local arms = table.create(SPOKES)
local spokes = table.create(SPOKES)
for index = 0, SPOKES - 1 do
	local arm = Instance.new("Frame")
	arm.Name = "Arm" .. tostring(index + 1)
	arm.AnchorPoint = Vector2.new(0.5, 0.5)
	arm.Position = UDim2.fromScale(0.5, 0.5)
	arm.BackgroundTransparency = 1
	arm.BorderSizePixel = 0
	arm.Rotation = index * (360 / SPOKES)
	arm.ZIndex = 1
	arm.Parent = disc

	local spoke = Instance.new("Frame")
	spoke.Name = "Spoke" .. tostring(index + 1)
	spoke.Position = UDim2.new()
	spoke.Size = UDim2.new(1, 0, 0.5, 0)
	spoke.BorderSizePixel = 0
	spoke.ZIndex = 1
	local owner = sectors[sectorForSpoke(index)]
	spoke.BackgroundColor3 = owner and owner.Color or UIStyle.Color.Control
	spoke.Parent = arm

	arms[index + 1] = arm
	spokes[index + 1] = spoke
end

-- Sector copy rides ON the disc, so it turns with the wedge it names.
local sectorLabels = {}
for order, sector in ipairs(sectors) do
	if sector.Width >= LABEL_MIN_DEGREES then
		local label = newLabel(disc, "SectorLabel" .. tostring(order), sector.Short)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = 2
		-- Near-black ink: every wedge colour is a bright one.
		UIStyle.body(label, {TextColor = UIStyle.Color.Caption, TextSize = 11})
		label.Rotation = sector.Start + sector.Width / 2
		sectorLabels[order] = label
	end
end

-- The rim is a circle, so it is deliberately NOT a child of the disc: rotating
-- a ring is invisible work every frame of a 4.2 s tween.
local rim = Instance.new("Frame")
rim.Name = "WheelRim"
rim.AnchorPoint = Vector2.new(0.5, 0.5)
rim.BackgroundTransparency = 1
rim.BorderSizePixel = 0
rim.ZIndex = 3
rim.Parent = discHolder
local rimCorner = Instance.new("UICorner")
rimCorner.CornerRadius = UDim.new(1, 0)
rimCorner.Parent = rim
local rimStroke = Instance.new("UIStroke")
rimStroke.Color = UIStyle.Color.Line
rimStroke.Thickness = 3
rimStroke.Transparency = 0.12
rimStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
rimStroke.Parent = rim

local hub = Instance.new("Frame")
hub.Name = "WheelHub"
hub.AnchorPoint = Vector2.new(0.5, 0.5)
hub.BackgroundColor3 = UIStyle.Color.Card
hub.BackgroundTransparency = 0
hub.BorderSizePixel = 0
hub.ZIndex = 4
hub.Parent = discHolder
local hubCorner = Instance.new("UICorner")
hubCorner.CornerRadius = UDim.new(1, 0)
hubCorner.Parent = hub
local hubStroke = Instance.new("UIStroke")
hubStroke.Color = UIStyle.Color.Line
hubStroke.Thickness = 2
hubStroke.Transparency = 0.3
hubStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hubStroke.Parent = hub

-- A 45-degree square: its lower half sits under the rim, so what reads above
-- the rim is a marker pointing down into the wedge. A real triangle would need
-- an ImageLabel, and this card ships no disc artwork on purpose.
local pointer = Instance.new("Frame")
pointer.Name = "WheelPointer"
pointer.AnchorPoint = Vector2.new(0.5, 0.5)
pointer.BackgroundColor3 = GOLD
pointer.BorderSizePixel = 0
pointer.Rotation = 45
pointer.ZIndex = 5
pointer.Parent = discHolder
local pointerStroke = Instance.new("UIStroke")
pointerStroke.Color = UIStyle.Color.Caption
pointerStroke.Thickness = 2
pointerStroke.Transparency = 0.25
pointerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pointerStroke.Parent = pointer

-- ── legend, controls, readouts ────────────────────────────────────────────
local legend = Instance.new("Frame")
legend.Name = "WheelLegend"
legend.BackgroundTransparency = 1
legend.Parent = body

local legendRows = {}
for order, sector in ipairs(sectors) do
	local row = Instance.new("Frame")
	row.Name = "LegendRow" .. tostring(order)
	row.BackgroundTransparency = 1
	row.Parent = legend

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.BackgroundColor3 = sector.Color
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(0, 3)
	swatchCorner.Parent = swatch

	local name = newLabel(row, "LegendLabel", sector.Label)
	UIStyle.body(name, {TextSize = 13})
	local odds = newLabel(row, "LegendOdds", sector.Odds)
	odds.TextXAlignment = Enum.TextXAlignment.Right
	UIStyle.readout(odds, {TextColor = sector.Color, TextSize = 13})

	legendRows[order] = {Row = row, Swatch = swatch, Label = name, Odds = odds}
end

local spinButton = Instance.new("TextButton")
spinButton.Name = "SpinButton"
spinButton.Text = "FREE SPIN"
spinButton.AutoButtonColor = true
spinButton.Parent = body
UIStyle.button(spinButton, {TextColor = TEAL, TextSize = 14})

local skipButton = Instance.new("TextButton")
skipButton.Name = "SkipButton"
skipButton.Text = "SKIP"
skipButton.AutoButtonColor = true
skipButton.Visible = false
skipButton.Parent = body
UIStyle.button(skipButton, {TextColor = UIStyle.Color.Body, TextSize = 12})

local banner = Instance.new("Frame")
banner.Name = "ResultBanner"
banner.Visible = false
banner.Parent = body
UIStyle.caption(banner)
local bannerText = newLabel(banner, "ResultText", "")
bannerText.TextXAlignment = Enum.TextXAlignment.Center
bannerText.Size = UDim2.fromScale(1, 1)
UIStyle.readout(bannerText, {TextColor = UIStyle.Color.Live, TextSize = 13})

local noteLine = newLabel(body, "NoteLine", "One free spin a day. Resets 00:00 UTC.")
noteLine.TextWrapped = true
noteLine.TextYAlignment = Enum.TextYAlignment.Top
UIStyle.body(noteLine, {TextColor = UIStyle.Color.Muted, TextSize = 11})

if #sectors == 0 then
	-- The config and the server that honours it land together. With no wheel
	-- configured, a SPIN button would be a control that cannot work.
	spinButton.Visible = false
	noteLine.Text = "Daily rewards are not configured on this server."
end

-- ── state ─────────────────────────────────────────────────────────────────
local profile = nil
local profileSerial = 0
local sawProfile = false    -- the FIRST profile read seeds, it never triggers
local seenSerial = nil      -- the last WheelLast.Serial this session has DRAWN
local spinning = false
local spinGoal = 0
local activeTween = nil
local pendingSpin = false
local pendingSerial = 0
local resetAt = nil
local rollAsked = false
local clockAccum = 0
local lastDisc = nil
local render                -- forward-declared: applyLayout is defined below it

-- ── the profile, read-only ────────────────────────────────────────────────
local function dailyOf()
	if type(profile) ~= "table" then return nil end
	return type(profile.Daily) == "table" and profile.Daily or nil
end

local function acceptProfile(data)
	if type(data) ~= "table" then return end
	profile = data
	profileSerial += 1
	-- ANY push is the server's answer to whatever was in flight.
	pendingSpin = false
	rollAsked = false
	statusLine.Text = ""
	statusLine.TextColor3 = UIStyle.Color.Muted
	local daily = dailyOf()
	local seconds = daily and tonumber(daily.SecondsToReset) or nil
	-- Re-anchored on EVERY push, which is what keeps the local countdown honest
	-- without a second clock to reconcile.
	resetAt = seconds and (workspace:GetServerTimeNow() + math.max(0, seconds)) or nil
	render()
end

local function refreshProfile()
	local serial = profileSerial
	task.spawn(function()
		local ok, data = pcall(function() return getProfile:InvokeServer() end)
		-- A push that landed while the invoke was in flight is newer than it.
		if ok and serial == profileSerial then acceptProfile(data) end
	end)
end

-- ── spinning ──────────────────────────────────────────────────────────────
local function reduceFlashing(): boolean
	return player:GetAttribute("ReduceFlashing") == true
end

-- Where the pointer has to end up for this recorded result, as an absolute
-- Rotation in [0, 360). Used to PARK a replayed or rejoined result.
local function landedRotation(order: number, serial: number): number
	local sector = sectors[order]
	if not sector then return 0 end
	return (-(sector.Start + jitterFor(serial, sector.Width))) % 360
end

local function finishSpin()
	if not spinning then return end
	spinning = false
	-- Cancel fires Completed; the handler sees `spinning` already false and
	-- returns, so a skip cannot finish the same spin twice.
	if activeTween then activeTween:Cancel() end
	activeTween = nil
	disc.Rotation = spinGoal
	render()
end

local function startSpin(order: number, serial: number)
	local sector = sectors[order]
	if not sector then return end
	local reduced = reduceFlashing()
	local turns = reduced and REDUCED_TURNS or SPIN_TURNS
	local current = disc.Rotation
	local target = -(sector.Start + jitterFor(serial, sector.Width))
	spinGoal = current - (current % 360) + target + 360 * turns
	spinning = true
	banner.Visible = false
	local info = TweenInfo.new(
		reduced and REDUCED_SECONDS or SPIN_SECONDS,
		reduced and Enum.EasingStyle.Sine or Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out)
	local tween = TweenService:Create(disc, info, {Rotation = spinGoal})
	activeTween = tween
	tween.Completed:Connect(function()
		if not spinning or activeTween ~= tween then return end
		finishSpin()
	end)
	tween:Play()
	render()
end

-- ── layout ────────────────────────────────────────────────────────────────
-- Every rectangle is an OFFSET derived from UIDevice's ModalViewport, the way
-- the terminal's own layout is, so "does this fit" is arithmetic a test can do
-- rather than a screenshot someone has to look at.
local function applyLayout()
	local layout = UIDevice.Layout()
	local area = layout.ModalViewport
	local touch = layout.IsTouch == true

	local width = math.floor(math.min(DESIGN_WIDTH, area.Width))
	local height = math.floor(math.min(DESIGN_HEIGHT, area.Height))
	local compact = width < 640 or height < 430
	local tier = (compact and touch) and 1 or (touch and 2 or 3)
	local face = FACES[tier]
	local pad, gap = face.Pad, face.Gap
	local tap = touch and 44 or 32
	local spinHeight = math.max(tap, 40)
	-- THE ONE CONTROL THAT MATTERS DOES NOT SCROLL ON TOUCH. Measured in Studio
	-- Play at 844x390: the body was ~200px tall, the disc alone 260, and SPIN
	-- landed at y 600 of a 604px canvas -- a player had to scroll past the whole
	-- wheel and its legend to reach the only button on the panel. On touch tiers
	-- the spin row is a FIXED FOOTER between the body and the status line; the
	-- disc, legend, banner and note keep scrolling above it. A pointer tier has
	-- the height for the authored composition and keeps SPIN under the legend.
	local footer = touch
	local wantedParent = footer and panel or body
	if spinButton.Parent ~= wantedParent then
		spinButton.Parent = wantedParent
		skipButton.Parent = wantedParent
	end

	local left = area.Left + math.floor((area.Width - width) / 2)
	local top = area.Top + math.floor((area.Height - height) / 2)
	panel.Size = UDim2.fromOffset(width, height)
	panel.Position = UIDevice.LocalPosition(gui, left, top)

	local closeSize = math.max(tap, 36)
	local closeWidth = math.max(closeSize, 72)
	local headerHeight = compact and 52 or 70
	local statusHeight = 18
	local bodyWidth = width - pad * 2
	local function bodyHeight()
		return height - pad * 2 - headerHeight - gap - statusHeight - gap
			- (footer and (spinHeight + gap) or 0)
	end
	-- One give-way step: a short screen loses header ornament before it loses
	-- the disc.
	if bodyHeight() < 150 then headerHeight = math.max(44, closeSize) end

	closeButton.Size = UDim2.fromOffset(closeWidth, closeSize)
	closeButton.Position = UDim2.fromOffset(width - pad - closeWidth, pad)
	closeButton.TextSize = math.max(11, face.Body)
	eyebrow.Position = UDim2.fromOffset(pad, pad + 2)
	eyebrow.Size = UDim2.fromOffset(bodyWidth - closeWidth - 10, 13)
	title.Position = UDim2.fromOffset(pad, pad + 17)
	title.Size = UDim2.fromOffset(bodyWidth - closeWidth - 10, face.Title + 6)
	title.TextSize = face.Title

	statusLine.Position = UDim2.fromOffset(pad, height - pad - statusHeight)
	statusLine.Size = UDim2.fromOffset(bodyWidth, statusHeight)

	local bodyTop = pad + headerHeight + gap
	local bodyRoom = math.max(60, bodyHeight())
	body.Position = UDim2.fromOffset(pad, bodyTop)
	body.Size = UDim2.fromOffset(bodyWidth, bodyRoom)

	local contentWidth = bodyWidth - SCROLLBAR_ROOM
	local twoColumn = tier == 3 and contentWidth >= TWO_COLUMN_MIN

	-- THE DISC. Pointer tiers take the height (a browsing composition beside a
	-- legend); touch tiers take the width -- and, on a short landscape screen,
	-- whatever the body still has, so the WHOLE wheel is on screen and only the
	-- legend below it has to be scrolled to.
	local discSize
	if touch then
		discSize = math.min(260, contentWidth, bodyRoom - 20)
	else
		discSize = math.min(360, math.floor(height * 0.55))
	end
	if twoColumn then
		-- The legend needs two readable columns of its own beside the disc.
		discSize = math.min(discSize, contentWidth - 260 - gap)
	end
	discSize = math.max(140, math.min(discSize, contentWidth))
	local radius = math.floor(discSize / 2)
	local pointerSize = math.max(12, math.floor(discSize * 0.07))
	local holderHeight = discSize + pointerSize

	-- 180 frames only move when the disc actually changed size.
	if discSize ~= lastDisc then
		lastDisc = discSize
		local spokeWidth = math.ceil(radius * 2 * math.pi / SPOKES) + 1
		-- The arm is the full diameter, so its centre is the hub; its coloured
		-- top half is sized by scale and needs no write of its own.
		for _, arm in ipairs(arms) do
			arm.Size = UDim2.fromOffset(spokeWidth, discSize)
		end
		disc.Size = UDim2.fromOffset(discSize, discSize)
		disc.Position = UDim2.fromOffset(radius, pointerSize + radius)
		rim.Size = UDim2.fromOffset(discSize, discSize)
		rim.Position = disc.Position
		local hubSize = math.max(22, math.floor(discSize * 0.17))
		hub.Size = UDim2.fromOffset(hubSize, hubSize)
		hub.Position = disc.Position
		pointer.Size = UDim2.fromOffset(pointerSize, pointerSize)
		-- Straddles the rim: half above it, half inside the wedge it marks.
		pointer.Position = UDim2.fromOffset(radius, pointerSize)
		for order, label in pairs(sectorLabels) do
			local sector = sectors[order]
			local mid = math.rad(sector.Start + sector.Width / 2)
			label.Size = UDim2.fromOffset(math.floor(radius * 0.78), face.Sector + 6)
			label.Position = UDim2.fromOffset(
				math.floor(radius + math.sin(mid) * radius * 0.62),
				math.floor(radius - math.cos(mid) * radius * 0.62))
			label.TextSize = math.max(11, face.Sector)
		end
	end

	local legendLeft = twoColumn and (discSize + gap) or 0
	local legendTop = twoColumn and 0 or (holderHeight + gap)
	local legendWidth = twoColumn and (contentWidth - legendLeft) or contentWidth
	discHolder.Size = UDim2.fromOffset(discSize, holderHeight)
	discHolder.Position = UDim2.fromOffset(
		twoColumn and 0 or math.floor((contentWidth - discSize) / 2), 0)

	local rowHeight = face.Row
	local rowsHeight = #legendRows * rowHeight
	legend.Position = UDim2.fromOffset(legendLeft, legendTop)
	legend.Size = UDim2.fromOffset(legendWidth, math.max(1, rowsHeight))
	for order, row in ipairs(legendRows) do
		row.Row.Position = UDim2.fromOffset(0, (order - 1) * rowHeight)
		row.Row.Size = UDim2.fromOffset(legendWidth, rowHeight)
		row.Swatch.Position = UDim2.new(0, 0, 0.5, 0)
		row.Swatch.Size = UDim2.fromOffset(face.Swatch, face.Swatch)
		local oddsWidth = 52
		row.Label.Position = UDim2.fromOffset(face.Swatch + 8, 0)
		row.Label.Size = UDim2.fromOffset(
			math.max(40, legendWidth - face.Swatch - 8 - oddsWidth - 6), rowHeight)
		row.Label.TextSize = math.max(11, face.Body)
		row.Odds.Position = UDim2.fromOffset(legendWidth - oddsWidth, 0)
		row.Odds.Size = UDim2.fromOffset(oddsWidth, rowHeight)
		row.Odds.TextSize = math.max(11, face.Odds)
	end

	local cursor = legendTop + rowsHeight + gap
	-- SKIP and the banner are SIZED whether or not they are drawn: a control
	-- whose rectangle only exists after it has been shown once is a rectangle
	-- the fit matrix cannot measure, and only their POSITION depends on what
	-- else is on screen.
	local skipHeight = math.max(tap, 34)
	local bannerHeight = math.max(28, face.Body + 16)
	spinButton.TextSize = math.max(11, face.Body + 1)
	skipButton.TextSize = math.max(11, face.Body)
	if footer then
		-- One row in PANEL space, hard against the status line. SKIP takes a
		-- fixed strip on the right and SPIN the rest, so SPIN never narrows
		-- below a thumb's worth of button while a replay is running.
		local footerTop = height - pad - statusHeight - gap - spinHeight
		local skipWidth = math.max(tap, 92)
		skipButton.Position = UDim2.fromOffset(width - pad - skipWidth, footerTop)
		skipButton.Size = UDim2.fromOffset(skipWidth, spinHeight)
		spinButton.Position = UDim2.fromOffset(pad, footerTop)
		spinButton.Size = UDim2.fromOffset(
			bodyWidth - (skipButton.Visible and skipWidth + 8 or 0), spinHeight)
	else
		spinButton.Position = UDim2.fromOffset(legendLeft, cursor)
		spinButton.Size = UDim2.fromOffset(legendWidth, spinHeight)
		cursor += spinHeight
		if skipButton.Visible then cursor += 6 end
		skipButton.Position = UDim2.fromOffset(legendLeft, cursor)
		skipButton.Size = UDim2.fromOffset(legendWidth, skipHeight)
		if skipButton.Visible then cursor += skipHeight end
	end
	if banner.Visible then cursor += 8 end
	banner.Position = UDim2.fromOffset(legendLeft, cursor)
	banner.Size = UDim2.fromOffset(legendWidth, bannerHeight)
	bannerText.TextSize = math.max(11, face.Body + 1)
	if banner.Visible then cursor += bannerHeight end
	cursor += 8
	local noteHeight = 34
	noteLine.Position = UDim2.fromOffset(legendLeft, cursor)
	noteLine.Size = UDim2.fromOffset(legendWidth, noteHeight)
	noteLine.TextSize = math.max(11, face.Body)
	cursor += noteHeight

	local contentHeight = twoColumn and math.max(holderHeight, cursor) or cursor
	body.CanvasSize = UDim2.fromOffset(0, contentHeight)
end

-- ── what is drawn ─────────────────────────────────────────────────────────
local function updateNote(spun: boolean)
	if #sectors == 0 then return end
	local base = "One free spin a day. Resets 00:00 UTC."
	local remaining = resetAt and math.max(0, resetAt - workspace:GetServerTimeNow()) or nil
	if spun then
		noteLine.Text = base .. "  Next spin in "
			.. (remaining and formatClock(remaining) or "--:--:--")
	else
		noteLine.Text = base
	end
	if remaining == 0 and not rollAsked then
		-- The UTC day just rolled. The server owns the new counters, so this
		-- asks for them rather than zeroing anything itself.
		rollAsked = true
		refreshProfile()
	end
end

function render()
	local daily = dailyOf()
	local today = daily and tostring(daily.Today or "") or ""
	local spun = daily ~= nil and today ~= "" and tostring(daily.WheelDay or "") == today
	local record = daily and type(daily.WheelLast) == "table" and daily.WheelLast or nil
	local recorded = record and today ~= ""
		and tostring(record.Day or "") == today and record or nil

	if recorded then
		local serial = tonumber(recorded.Serial) or 0
		local order = sectorByKey(tostring(recorded.Key or ""))
		if not sawProfile then
			-- THE FIRST PROFILE THIS SESSION READS IS A SEED, never a trigger: a
			-- player who spun this morning and rejoined at lunch is SHOWN their
			-- prize, not made to watch it land again.
			seenSerial = serial
			if order then disc.Rotation = landedRotation(order, serial) end
		elseif serial ~= seenSerial then
			seenSerial = serial
			if order and not spinning then startSpin(order, serial) return end
		end
	end
	if daily ~= nil then sawProfile = true end

	if #sectors > 0 then
		if pendingSpin or spinning then
			spinButton.Text = "SPINNING..."
			spinButton.TextColor3 = UIStyle.Color.Muted
			UIDevice.SetEnabled(spinButton, false)
		elseif spun then
			spinButton.Text = "SPUN TODAY"
			spinButton.TextColor3 = UIStyle.Color.Muted
			UIDevice.SetEnabled(spinButton, false)
		else
			spinButton.Text = "FREE SPIN"
			spinButton.TextColor3 = TEAL
			UIDevice.SetEnabled(spinButton, true)
		end
	end
	-- SKIP exists only while a result is replaying.
	UIDevice.SetInteractive(skipButton, spinning)

	local order, sector = nil, nil
	if recorded then order, sector = sectorByKey(tostring(recorded.Key or "")) end
	banner.Visible = sector ~= nil and not spinning
	if banner.Visible and sector then
		bannerText.Text = "YOU RECEIVED: " .. sector.Label
		bannerText.TextColor3 = sector.Color
	end

	updateNote(spun)
	-- The banner and SKIP both take room, so the geometry is re-resolved rather
	-- than left describing the previous state.
	applyLayout()
end

-- ── open and close ────────────────────────────────────────────────────────
local function blockedFromOpening(): boolean
	return player:GetAttribute("InRound") == true
		or player:GetAttribute("QueueModalOpen") == true
		-- Read BEFORE this modal publishes its own flag, so it is always
		-- somebody else's modal that is being honoured here.
		or UIDevice.ScreenOwningModalOpen()
end

local closeModal, openModal

-- Gamepad focus and the ButtonB binding, scoped so they cost the main chunk
-- three locals rather than six.
local focusModal, blurModal, bindClose
do
	local ContextActionService = game:GetService("ContextActionService")
	local ACTION = "LuckyWheelClose"

	function focusModal()
		if UIDevice.LastInput() ~= "Gamepad" then return end
		GuiService.SelectedObject = spinButton.Active and spinButton or closeButton
	end

	function blurModal()
		ContextActionService:UnbindAction(ACTION)
		if GuiService.SelectedObject == spinButton
			or GuiService.SelectedObject == closeButton
			or GuiService.SelectedObject == skipButton then
			GuiService.SelectedObject = nil
		end
	end

	function bindClose()
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if not shade.Visible or GuiService.MenuIsOpen then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then closeModal() end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
end

function closeModal()
	if not shade.Visible then return end
	shade.Visible = false
	-- Nobody is watching the replay, so it is over. The prize was banked before
	-- the animation started; only the garnish is being skipped.
	finishSpin()
	player:SetAttribute("LuckyWheelOpen", nil)
	-- Suppression is SHARED. Derive the request from the complete published
	-- modal set rather than letting the last caller win -- exactly as
	-- ZyntraStore.setMainVisible does.
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	blurModal()
end

function openModal()
	if shade.Visible or blockedFromOpening() then return end
	statusLine.Text = ""
	statusLine.TextColor3 = UIStyle.Color.Muted
	shade.Visible = true
	player:SetAttribute("LuckyWheelOpen", true)
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	UIDevice.SetInteractive(closeButton, true)
	render()
	-- Open is also a re-read: a wheel opened minutes after the last push would
	-- otherwise draw a countdown anchored to a stale SecondsToReset.
	refreshProfile()
	bindClose()
	focusModal()
end

-- ── wiring ────────────────────────────────────────────────────────────────
openEvent.Event:Connect(openModal)
closeButton.Activated:Connect(closeModal)

spinButton.Activated:Connect(function()
	if pendingSpin or spinning or not spinButton.Active or #sectors == 0 then return end
	pendingSpin = true
	pendingSerial += 1
	local serial = pendingSerial
	statusLine.Text = ""
	statusLine.TextColor3 = UIStyle.Color.Muted
	actionRemote:FireServer("SpinDailyWheel")
	render()
	task.delay(ACTION_TIMEOUT, function()
		-- No answer at all. The recovery is a RE-READ, never a local grant.
		if not pendingSpin or pendingSerial ~= serial then return end
		pendingSpin = false
		statusLine.Text = "No answer yet. Try again."
		statusLine.TextColor3 = UIStyle.Color.DangerText
		refreshProfile()
		render()
	end)
end)

skipButton.Activated:Connect(finishSpin)

profileChanged.OnClientEvent:Connect(acceptProfile)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not shade.Visible then return end
	if input.KeyCode == Enum.KeyCode.Escape then closeModal() end
end)

for _, attribute in ipairs({"InRound", "QueueModalOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if player:GetAttribute(attribute) == true then closeModal() end
	end)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") == true then closeModal() end
end)

UIDevice.Changed:Connect(applyLayout)

RunService.Heartbeat:Connect(function(delta)
	clockAccum += delta
	-- 1 Hz, and only while the panel is on screen: a countdown redrawn every
	-- frame is 59 wasted string builds a second, and one redrawn behind a closed
	-- modal is 60.
	if clockAccum < 1 then return end
	clockAccum = 0
	if not shade.Visible then return end
	local daily = dailyOf()
	local today = daily and tostring(daily.Today or "") or ""
	updateNote(daily ~= nil and today ~= "" and tostring(daily.WheelDay or "") == today)
end)

-- Studio-only, so the UI regression matrix can drive this modal without a
-- remote of its own. Never present in a live server.
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionLuckyWheelProbe"
	probe.OnInvoke = function(action)
		if action == "open" then
			openModal()
		elseif action == "close" then
			closeModal()
		end
		return shade.Visible
	end
	probe.Parent = gui
end

applyLayout()
render()
refreshProfile()
