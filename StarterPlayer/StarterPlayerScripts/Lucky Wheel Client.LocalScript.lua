-- Lucky Wheel Client  (LUCKY_WHEEL_TAKEOVER_20260916, wheel/shop refresh)
--
-- The daily wheel as a FULL-SCREEN TAKEOVER. There is no panel, no legend, no
-- banner and no footer: the undimmed world, the textured disc, a fixed pointer
-- at 12 o'clock, SPIN living inside the hub, and one X beside the disc. While it is open every
-- OTHER ScreenGui in PlayerGui is disabled and restored on close -- see "the
-- takeover" below, which is the only part of this file that touches anything
-- it does not own.
--
-- WHAT THIS FILE IS ALLOWED TO DECIDE: nothing about the prize. The server
-- picks it inside its own transaction, writes it, and only then answers; by the
-- time `Daily.WheelLast` reaches this client the outcome is already durable.
-- The disc is a REPLAY of a recorded result, which is why it can be skipped,
-- cut short by closing, or -- on a push carrying the SAME Serial -- not played
-- at all. There is no client roll anywhere in this file.
--
-- THE DISC IS ARTWORK (rbxassetid://70472139920072) and its six fields are
-- EQUAL. Field i (0-based, in config order Token1, Token3, Potion1, Potion2,
-- Shield1, Skin5) is centred at 60*i degrees clockwise from the top. Equal art
-- must never be read as equal chances, so each field prints the SERVER's own
-- weight (40/20/20/5/10/5) as a percentage. Those weights are the odds;
-- the geometry is not.
--
-- ROTATION, stated once because three places depend on it. GuiObject.Rotation
-- is clockwise-positive, so the stationary pointer at 12 o'clock sees wheel
-- angle `(-Rotation) % 360`. For field `order` the landing angle is
-- `start + jitter` with `start = FIELD * (order - 1) - FIELD / 2` and jitter
-- deterministic from WheelLast.Serial, kept JITTER_MARGIN degrees clear of both
-- edges, so a replay of the same result lands on the same degree on every
-- client. The tween goal is
--   current + (target - current) % 360 + 360 * turns
-- which is congruent to `target` and always at least one WHOLE TURN FORWARD.
-- (The older `current - current % 360 + target + 360 * turns` reaches the same
-- angle but its travel is `target - current % 360 + 360 * turns`, which goes
-- NEGATIVE whenever turns is 1 -- i.e. the ReduceFlashing path -- and reads as
-- a backwards jerk.)

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
local Skins = require(ReplicatedStorage:WaitForChild("ZyntraSkins"))
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

local WHEEL_IMAGE = "rbxassetid://70472139920072"
local GOLD = Color3.fromRGB(255, 203, 79)
local GOLD_DEEP = Color3.fromRGB(150, 108, 24)  -- the hub's own stroke
local INK = Color3.fromRGB(12, 16, 12)          -- dark type on a gold hub
local WHITE = Color3.fromRGB(245, 248, 244)

local SPIN_SECONDS = 4.2
local SPIN_TURNS = 5
local REDUCED_SECONDS = 1.4     -- ReduceFlashing: one slow turn, no strobe
local REDUCED_TURNS = 1
local JITTER_MARGIN = 6         -- never land within 6 degrees of a field edge
local ACTION_TIMEOUT = 6        -- the no-answer window, unchanged
local PRIZE_SECONDS = 3.5       -- how long the hub carries the prize after it lands
-- The X is 48 on every device: that is the contract's floor AND above the 44 px
-- touch floor, so there is one number rather than a tier table.
local CLOSE_SIZE = 48
local CLOSE_MARGIN = 8
-- Below this the field prints the short prize name. The UITextSizeConstraint on
-- each label already stops a long name overflowing, but shrinking "2 SPEED
-- POTIONS" towards 11px is not the same as reading it: 400 puts every phone and
-- the emulator (335, 285, 266, 240) on the short form and leaves desktop (569)
-- and tablet (610) the long one. One constant if that balance moves.
local SHORT_LABEL_SIDE = 400

-- The word each prize family is called, long inside a big field and short
-- inside a small one or on the hub.
local WORD = {
	Tokens = {Long = "TOKEN", Short = "TOKEN"},
	SpeedPotion = {Long = "SPEED POTION", Short = "POTION"},
	EntityShield = {Long = "ENTITY SHIELD", Short = "SHIELD"},
}

local function labelFor(entry, short: boolean): string
	local reward = type(entry.Reward) == "table" and entry.Reward or nil
	-- The 5% wedge keeps its probability when all eligible skins are owned.
	-- Name the resulting 3-Token fallback on the field before a player spins.
	if reward and reward.Kind == "Skin" then
		return short and "SKIN / 3T" or "SKIN OR 3 TOKENS"
	end
	local amount = math.max(1, math.floor(reward and tonumber(reward.Amount) or 1))
	local words = reward and (reward.Kind == "Tokens" and WORD.Tokens
		or WORD[tostring(reward.Key or "")]) or nil
	if not words then return string.upper(tostring(entry.Label or "PRIZE")) end
	local word = short and words.Short or words.Long
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

-- ── the six fields, straight off the config ───────────────────────────────
local sectors = {}
local weightTotal = 0
do
	local wheel = type(Config.DailyRewards) == "table" and Config.DailyRewards.Wheel or nil
	local entries = type(wheel) == "table" and wheel or {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" then
			weightTotal += math.max(0, tonumber(entry.Weight) or 0)
		end
	end
	for _, entry in ipairs(entries) do
		if type(entry) == "table" then
			local weight = math.max(0, tonumber(entry.Weight) or 0)
			table.insert(sectors, {
				Key = tostring(entry.Key or ""),
				Long = labelFor(entry, false),
				Short = labelFor(entry, true),
				Odds = oddsText(weight, weightTotal),
			})
		end
	end
end

-- EQUAL fields, because the texture's fields are equal. Derived from the count
-- so the geometry can never disagree with the config -- but the artwork has
-- SIX fields baked in, so a config that is not six prizes needs new art.
local FIELD = #sectors > 0 and 360 / #sectors or 360

-- Centre of field `order` (1-based), clockwise from 12 o'clock.
local function fieldAngle(order: number): number
	return FIELD * (order - 1)
end

local function sectorByKey(key: string)
	for order, sector in ipairs(sectors) do
		if sector.Key == key then return order, sector end
	end
	return nil, nil
end

-- The sixth field stays a skin field even if the player already owns its two
-- eligible suits. The server records either the exact SkinId or the disclosed
-- 3-Token fallback before this client animates, so a rejoin shows the same win.
local function prizeFace(record, sector): string
	-- TOKEN_EARNER_20260924: a claimed Token payout names what the server
	-- actually paid (PaidTokens, multiplied by a Token Earner pass). Records
	-- claimed before that field existed keep the field's own text.
	local paid = record and type(record.PaidTokens) == "number" and math.floor(record.PaidTokens) or 0
	if paid >= 1 then return paid .. (paid == 1 and " TOKEN" or " TOKENS") end
	if not record or tostring(record.Key or "") ~= "Skin5" then return sector.Short end
	if tonumber(record.FallbackTokens) == 3 then return "3 TOKENS" end
	local skin = Skins.ById[tostring(record.SkinId or "")]
	return skin and string.upper(skin.Name) or sector.Short
end

-- Deterministic from the Serial, and deliberately NOT Random.new: the same
-- recorded result must land on the same degree every time it is drawn, on every
-- client, whether it is being animated or parked by a rejoin. Range
-- [JITTER_MARGIN, FIELD - JITTER_MARGIN) -- with the shipped five prizes that
-- is [6, 66) inside a 72-degree field.
local function jitterFor(serial: number): number
	local span = FIELD - JITTER_MARGIN * 2
	if span <= 0 then return FIELD / 2 end
	local mixed = (math.floor(serial) * 2654435761) % 1000003
	return JITTER_MARGIN + span * (mixed / 1000003)
end

-- ── chrome ────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "LuckyWheelGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 118
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.Parent = playerGui

-- No dimming (owner, Trello 25GLltY6: no dark overlay over the rest of the
-- screen), but still Active so a tap aimed past the disc reaches nothing
-- behind it. Everything else is its child.
local shade = Instance.new("Frame")
shade.Name = "WheelShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 1
shade.BorderSizePixel = 0
shade.Active = true
shade.Visible = false
shade.Parent = gui

-- A square, centred on the WHOLE screen. The disc fills it; the pointer and the
-- hub sit on its edge and its centre and are NOT children of the disc.
local holder = Instance.new("Frame")
holder.Name = "WheelHolder"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.BackgroundTransparency = 1
holder.BorderSizePixel = 0
holder.Parent = shade

local disc = Instance.new("ImageLabel")
disc.Name = "WheelDisc"
disc.Image = WHEEL_IMAGE
-- Fit, never stretch or crop: the art is round and a non-square holder would
-- otherwise turn it into an ellipse the pointer no longer agrees with.
disc.ScaleType = Enum.ScaleType.Fit
disc.BackgroundTransparency = 1
disc.BorderSizePixel = 0
disc.AnchorPoint = Vector2.new(0.5, 0.5)
disc.Position = UDim2.fromScale(0.5, 0.5)
disc.Size = UDim2.fromScale(1, 1)
disc.ZIndex = 1
disc.Parent = holder

-- The field copy rides ON the disc, so it turns with the field it names. Its
-- own Rotation is the field's angle, which makes the 12 o'clock field read
-- upright and every other one read along its own radius.
local fieldLabels, fieldLimits, fieldOdds = {}, {}, {}
for order, sector in ipairs(sectors) do
	local angle = fieldAngle(order)

	local label = Instance.new("TextLabel")
	label.Name = "FieldLabel" .. tostring(order)
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromScale(0.34, 0.075)
	label.Rotation = angle
	label.Font = Enum.Font.GothamBlack
	-- SCALED, BETWEEN A FLOOR AND THE AUTHORED SIZE. Nothing in this file knows
	-- a font's TextBounds, and "2 SPEED POTIONS" in a 0.34-wide field is the
	-- case where a fixed TextSize would clip rather than fit. The engine shrinks
	-- it instead, never below the project's 11px floor and never above the size
	-- applyLayout derives from the disc.
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = sector.Long
	label.ZIndex = 2
	label.Parent = disc

	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 11
	limit.MaxTextSize = 11   -- raised to the authored size by applyLayout
	limit.Parent = label

	local odds = Instance.new("TextLabel")
	odds.Name = "FieldOdds" .. tostring(order)
	odds.BackgroundTransparency = 1
	odds.AnchorPoint = Vector2.new(0.5, 0.5)
	odds.Size = UDim2.fromScale(0.22, 0.06)
	odds.Rotation = angle
	odds.Font = Enum.Font.GothamBlack
	odds.TextScaled = false
	odds.TextColor3 = GOLD
	odds.TextXAlignment = Enum.TextXAlignment.Center
	odds.TextYAlignment = Enum.TextYAlignment.Center
	odds.Text = sector.Odds
	odds.ZIndex = 2
	odds.Parent = disc

	-- Contextual is the DEFAULT and is exactly what is wanted here: on a
	-- TextLabel it outlines the GLYPHS, which is what makes white copy legible
	-- over both a bright field and the rim lamps. (UIStyle.panel states Border
	-- for the opposite reason -- there the stroke is a frame's edge.)
	for _, target in ipairs({label, odds}) do
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(10, 12, 10)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = target
	end

	fieldLabels[order] = label
	fieldLimits[order] = limit
	fieldOdds[order] = odds
end

-- A 45-degree square straddling the rim at 12 o'clock: what reads above the rim
-- is a marker pointing down into the field. It is a SIBLING of the disc and its
-- Rotation is written once, here, and never again.
local pointer = Instance.new("Frame")
pointer.Name = "WheelPointer"
pointer.AnchorPoint = Vector2.new(0.5, 0.5)
pointer.Position = UDim2.fromScale(0.5, 0)
pointer.BackgroundColor3 = GOLD
pointer.BorderSizePixel = 0
pointer.Rotation = 45
pointer.ZIndex = 4
pointer.Parent = holder
local pointerCorner = Instance.new("UICorner")
pointerCorner.CornerRadius = UDim.new(0, 3)
pointerCorner.Parent = pointer
local pointerStroke = Instance.new("UIStroke")
pointerStroke.Color = Color3.fromRGB(10, 12, 10)
pointerStroke.Thickness = 2
pointerStroke.Transparency = 0.25
pointerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pointerStroke.Parent = pointer

-- SPIN IS THE HUB. There is no button anywhere outside the wheel, so this one
-- carries every state the player needs: ready, asking, spinning, the prize, the
-- countdown, and the retry. Also a sibling of the disc -- it never turns.
local hub = Instance.new("TextButton")
hub.Name = "HubButton"
hub.AnchorPoint = Vector2.new(0.5, 0.5)
hub.Position = UDim2.fromScale(0.5, 0.5)
hub.BackgroundColor3 = GOLD
hub.BackgroundTransparency = 0
hub.BorderSizePixel = 0
hub.AutoButtonColor = true
hub.Font = Enum.Font.GothamBlack
hub.TextScaled = false
hub.TextColor3 = INK
hub.Text = "SPIN"
hub.ZIndex = 5
hub.Parent = holder
local hubCorner = Instance.new("UICorner")
hubCorner.CornerRadius = UDim.new(1, 0)   -- a circle, whatever the diameter is
hubCorner.Parent = hub
local hubStroke = Instance.new("UIStroke")
hubStroke.Color = GOLD_DEEP
hubStroke.Thickness = 2
hubStroke.Transparency = 0.15
hubStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hubStroke.Parent = hub

-- The one way out that is not a key or a button on a pad.
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Text = "X"
closeButton.AutoButtonColor = true
closeButton.ZIndex = 10
closeButton.Parent = shade
UIStyle.button(closeButton, {
	Background = UIStyle.Color.Card,
	Transparency = 0.08,
	Radius = UIStyle.Radius.Control,
	Stroke = GOLD,
	StrokeTransparency = 0.25,
	Thickness = 2,
	TextColor = GOLD,
	TextSize = 20,
})
closeButton.Font = Enum.Font.GothamBlack

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
local retryOffered = false  -- six seconds of silence: the hub says RETRY
local showPrize = false     -- the hub carries the prize for PRIZE_SECONDS
local prizeSerial = 0
-- WHEEL_COLLECT_20260922 (Trello 25GLltY6). The server records a spin and pays
-- on COLLECT PRIZE; the hub is that button while a prize is owed. Success is
-- shown only once the pushed profile says Claimed == true for the serial that
-- was asked for -- a toast or an animation alone is not a claim.
local pendingClaim = false
local claimSerial = 0
local awaitingClaim = nil   -- WheelLast.Serial the in-flight claim is for
local showCollected = false -- the hub carries "<prize> COLLECTED" for PRIZE_SECONDS
local collectedKey = nil
local collectedFace = nil
local collectedSerial = 0
local resetAt = nil
local rollAsked = false
local clockAccum = 0
-- What the hub says right now, decided by render() and painted by applyLayout()
-- (only applyLayout knows the diameter the text size comes from).
local hubText, hubEnabled, hubBig = "SPIN", false, true
local render                -- forward-declared: acceptProfile calls it

-- ── the profile, read-only ────────────────────────────────────────────────
local function dailyOf()
	if type(profile) ~= "table" then return nil end
	return type(profile.Daily) == "table" and profile.Daily or nil
end

local function todayKey(): string
	local daily = dailyOf()
	return daily and tostring(daily.Today or "") or ""
end

local function spunToday(): boolean
	local daily = dailyOf()
	local today = todayKey()
	return daily ~= nil and today ~= "" and tostring(daily.WheelDay or "") == today
end

-- Today's recorded result, or nil. A result stamped with a PREVIOUS day is not
-- today's result and must neither animate nor count as a spent spin.
local function recordedToday()
	local daily = dailyOf()
	local today = todayKey()
	if not daily or today == "" then return nil end
	local record = type(daily.WheelLast) == "table" and daily.WheelLast or nil
	if record and tostring(record.Day or "") == today then return record end
	return nil
end

-- The prize the server still owes: WheelLast with Claimed == false, from ANY
-- day. A result that was never collected is collectable after a day change and
-- after a rejoin; the server refuses a new spin until it is.
local function pendingPrize()
	local daily = dailyOf()
	local record = daily and type(daily.WheelLast) == "table" and daily.WheelLast or nil
	if record and record.Claimed == false then return record end
	return nil
end

local function remainingSeconds(): number?
	if not resetAt then return nil end
	return math.max(0, resetAt - workspace:GetServerTimeNow())
end

local function acceptProfile(data)
	if type(data) ~= "table" then return end
	profile = data
	profileSerial += 1
	-- ANY push is the server's answer to whatever was in flight.
	pendingSpin = false
	retryOffered = false
	rollAsked = false
	if pendingClaim then
		pendingClaim = false
		local daily = dailyOf()
		local record = daily and type(daily.WheelLast) == "table" and daily.WheelLast or nil
		if record and tonumber(record.Serial) == awaitingClaim and record.Claimed == true then
			showCollected = true
			collectedKey = tostring(record.Key or "")
			local _, sector = sectorByKey(collectedKey)
			collectedFace = sector and prizeFace(record, sector) or nil
			collectedSerial += 1
			local serial = collectedSerial
			task.delay(PRIZE_SECONDS, function()
				if collectedSerial ~= serial then return end
				showCollected = false
				render()
			end)
		end
		awaitingClaim = nil
	end
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
		-- AUDIT_FIX_20260924: so is the push still owed for a SPIN/COLLECT fired
		-- after the invoke went out -- this answer predates that action and must
		-- not be taken for its reply. The timeouts clear the flag before re-reading.
		if ok and serial == profileSerial and not pendingSpin and not pendingClaim then
			acceptProfile(data)
		end
	end)
end

-- ── spinning ──────────────────────────────────────────────────────────────
local function reduceFlashing(): boolean
	return player:GetAttribute("ReduceFlashing") == true
end

-- Where the pointer has to end up for this recorded result, as an absolute
-- Rotation in [0, 360). Used to PARK a replayed or rejoined result.
local function landedRotation(order: number, serial: number): number
	if not sectors[order] then return 0 end
	return (-(fieldAngle(order) - FIELD / 2 + jitterFor(serial))) % 360
end

local function finishSpin()
	if not spinning then return end
	spinning = false
	-- Cancel fires Completed; the handler sees `spinning` already false and
	-- returns, so a skip can never finish the same spin twice.
	if activeTween then activeTween:Cancel() end
	activeTween = nil
	disc.Rotation = spinGoal
	-- The hub shows what was won, then becomes the countdown. Keyed on a serial
	-- so a later landing's window cannot be closed early by an older timer.
	showPrize = true
	prizeSerial += 1
	local serial = prizeSerial
	task.delay(PRIZE_SECONDS, function()
		if prizeSerial ~= serial then return end
		showPrize = false
		render()
	end)
	render()
end

local function startSpin(order: number, serial: number)
	if not sectors[order] then return end
	local reduced = reduceFlashing()
	local turns = reduced and REDUCED_TURNS or SPIN_TURNS
	local current = disc.Rotation
	local target = -(fieldAngle(order) - FIELD / 2 + jitterFor(serial))
	-- Congruent to `target`, and always at least one whole turn forward. See the
	-- ROTATION note at the top for why this is not written as
	-- `current - current % 360 + target + 360 * turns`.
	spinGoal = current + (target - current) % 360 + 360 * turns
	spinning = true
	showPrize = false
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
local function paintHub(diameter: number)
	hub.Text = hubText
	-- "SPIN" and "RETRY" are short enough for the big face. "SPINNING", the
	-- prize and the countdown are not: eight characters at 0.30 of the diameter
	-- are wider than the circle they sit in, so they take the two-line face.
	hub.TextSize = hubBig and math.max(12, math.floor(diameter * 0.30))
		or math.max(11, math.floor(diameter * 0.19))
	-- While the disc is TURNING the hub must keep taking input, because a tap on
	-- it is the skip -- GuiButton.Activated does not fire on an inactive button.
	-- "Disabled while spinning" therefore applies to the request-in-flight half,
	-- where there is nothing to skip and a second tap must not re-ask.
	UIDevice.SetEnabled(hub, hubEnabled or spinning)
end

local function applyLayout()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local minAxis = math.min(safe.Right - safe.Left, safe.Bottom - safe.Top)

	-- 0.86 OF THE SAFE AREA'S SHORT AXIS, not the display's. The gui uses
	-- CoreUISafeInsets and the pointer sits ON the disc's top edge, so a disc
	-- sized off the whole display puts its pointer under Roblox's topbar on a
	-- landscape phone. Worked through against that 58px band:
	--   1280x720 -> safe 1280x662 -> 569
	--   390x844  -> safe 390x786  -> 335
	--   749x368  -> safe 749x310  -> 266
	-- The last min() is the guarantee that the clamp's 220 floor can never push
	-- the disc out of a safe area shorter than 256.
	local side = math.min(
		math.clamp(math.floor(minAxis * 0.86), 220, 640),
		math.floor(minAxis))

	holder.Size = UDim2.fromOffset(side, side)
	holder.Position = UIDevice.LocalPosition(gui,
		(safe.Left + safe.Right) / 2, (safe.Top + safe.Bottom) / 2)

	local pointerSize = math.max(18, math.floor(side * 0.09))
	pointer.Size = UDim2.fromOffset(pointerSize, pointerSize)

	-- >= 56 on every device, which is above the 44 px touch floor with room for
	-- the stroke.
	local diameter = math.max(56, math.floor(side * 0.26))
	hub.Size = UDim2.fromOffset(diameter, diameter)

	local short = side < SHORT_LABEL_SIDE
	local labelSize = math.max(11, math.floor(side * 0.040))
	local oddsSize = math.max(11, math.floor(side * 0.034))
	for order, sector in ipairs(sectors) do
		local label = fieldLabels[order]
		label.Text = short and sector.Short or sector.Long
		-- The ceiling only: the label is TextScaled, so this is the size it may
		-- reach if the copy fits, and 11 (the constraint's floor) is the size it
		-- may shrink to if it does not.
		fieldLimits[order].MaxTextSize = labelSize
		-- Polar, in disc space: 0.80 R for the name, 0.36 R for the odds, both
		-- on the field's own radius. Size is a scale, so nothing here is written
		-- twice when the disc resizes.
		local a = math.rad(fieldAngle(order))
		label.Position = UDim2.fromScale(0.5 + 0.80 * 0.5 * math.sin(a),
			0.5 - 0.80 * 0.5 * math.cos(a))
		local odds = fieldOdds[order]
		odds.TextSize = oddsSize
		odds.Position = UDim2.fromScale(0.5 + 0.36 * 0.5 * math.sin(a),
			0.5 - 0.36 * 0.5 * math.cos(a))
	end

	-- Just off the disc's top-right rim (owner, Trello 25GLltY6: the X closer
	-- to the wheel), clamped into the SAFE area so the topbar or a housing cutout
	-- never sits on the only way out. At 45 degrees the button's nearest corner
	-- is 0.8 * CLOSE_SIZE - CLOSE_SIZE / sqrt 2 (~4.5 px) outside the rim.
	local reach = (side / 2 + CLOSE_SIZE * 0.8) * math.sqrt(0.5)
	closeButton.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	closeButton.Position = UIDevice.LocalPosition(gui,
		math.clamp((safe.Left + safe.Right) / 2 + reach - CLOSE_SIZE / 2,
			safe.Left + CLOSE_MARGIN, safe.Right - CLOSE_MARGIN - CLOSE_SIZE),
		math.clamp((safe.Top + safe.Bottom) / 2 - reach - CLOSE_SIZE / 2,
			safe.Top + CLOSE_MARGIN, safe.Bottom - CLOSE_MARGIN - CLOSE_SIZE))

	paintHub(diameter)
end

-- ── what the hub says ─────────────────────────────────────────────────────
function render()
	local recorded = recordedToday() or pendingPrize()
	if recorded then
		local serial = tonumber(recorded.Serial) or 0
		local order = sectorByKey(tostring(recorded.Key or ""))
		if not sawProfile then
			-- THE FIRST PROFILE THIS SESSION READS IS A SEED, never a trigger: a
			-- player who spun this morning and rejoined at lunch is SHOWN their
			-- prize parked under the pointer, not made to watch it land again.
			seenSerial = serial
			if order then disc.Rotation = landedRotation(order, serial) end
		elseif serial ~= seenSerial then
			seenSerial = serial
			if order and not spinning then startSpin(order, serial) return end
		end
	end
	if dailyOf() ~= nil then sawProfile = true end

	local _, sector = nil, nil
	if recorded then _, sector = sectorByKey(tostring(recorded.Key or "")) end
	local _, collectedSector = nil, nil
	if collectedKey then _, collectedSector = sectorByKey(collectedKey) end
	local owed = pendingPrize() ~= nil

	if #sectors == 0 then
		-- The config and the server that honours it land together. With no wheel
		-- configured the hub is a control that could not work.
		hubText, hubEnabled, hubBig = "SPIN", false, true
	elseif spinning or pendingSpin then
		hubText, hubEnabled, hubBig = "SPINNING", false, false
	elseif pendingClaim then
		hubText, hubEnabled, hubBig = "COLLECTING", false, false
	elseif showCollected and collectedSector then
		-- The server's confirmation names the actual skin or fallback payout.
		local face = collectedFace or collectedSector.Short
		hubText = (collectedKey == "Skin5" and face:gsub(" ", "\n") or face)
			.. "\nCOLLECTED"
		hubEnabled, hubBig = false, false
	elseif owed and sector then
		-- The disc under the pointer already names the prize; the hub is the one
		-- primary action left, on touch and pad as much as with a mouse.
		if recorded.Key == "Skin5" then
			-- AUDIT_FIX_20260924: a suit bought after the spin is paid as the
			-- 3-Token fallback (the server's own IsOwned rule), so say that. Not in
			-- prizeFace: after a real grant the suit is owned too.
			local face = Skins.IsOwned(profile.Skins, recorded.SkinId) and "3 TOKENS"
				or prizeFace(recorded, sector)
			hubText = "COLLECT\n" .. face:gsub(" ", "\n")
		else
			hubText = "COLLECT\nPRIZE"
		end
		hubEnabled, hubBig = true, false
	elseif showPrize and sector then
		-- Two lines, because a circle is not a row: "2 POTIONS" -> "2\nPOTIONS".
		hubText = (prizeFace(recorded, sector):gsub(" ", "\n"))
		hubEnabled, hubBig = false, false
	elseif retryOffered then
		hubText, hubEnabled, hubBig = "RETRY", true, true
	elseif spunToday() then
		local remaining = remainingSeconds()
		hubText = "SPUN\n" .. (remaining and formatClock(remaining) or "--:--:--")
		hubEnabled, hubBig = false, false
	else
		hubText, hubEnabled, hubBig = "SPIN", true, true
	end

	-- The geometry is re-resolved rather than left describing the previous state,
	-- and it is what paints the hub: only it knows the diameter.
	applyLayout()
end

-- ── the takeover ──────────────────────────────────────────────────────────
-- "When the wheel is open, every other game UI is hidden." Every OTHER
-- ScreenGui in PlayerGui is disabled on open and put back on close -- but only
-- the ones THIS modal turned off, only if they are still there, and only if
-- they have not re-enabled themselves in the meantime. CoreGui (topbar, chat)
-- is not ours to touch; the touch movement cluster is CoreGui too and stands
-- down through UIDevice.SuppressTouchMovement instead.
local hidden = {}
local watchers = {}       -- gui -> its Enabled watcher, live only while taken over
local childAddedConn = nil
local takenOver = false

local function hideOther(other: Instance)
	if other == gui or not other:IsA("ScreenGui") then return end
	-- `~= nil`, not truthiness: a gui that was ALREADY off is remembered as
	-- false so close leaves it off.
	if hidden[other] ~= nil then return end
	hidden[other] = other.Enabled
	other.Enabled = false
	-- A gui that switches ITSELF back on while the wheel is up is switched off
	-- again and remembered as wanting to be on. Measured in Studio 2026-09-16:
	-- NoiseReporter's StaminaGui re-enables itself on every layout pass, and it
	-- is where the lobby's touch RUN button lives -- so without this the one
	-- control the takeover exists to hide was the one that stayed on screen.
	watchers[other] = other:GetPropertyChangedSignal("Enabled"):Connect(function()
		if takenOver and other.Enabled then
			hidden[other] = true
			other.Enabled = false
		end
	end)
end

local function takeOver()
	takenOver = true
	for _, child in ipairs(playerGui:GetChildren()) do hideOther(child) end
	-- A ResetOnSpawn clone re-parents itself into PlayerGui without asking.
	childAddedConn = playerGui.ChildAdded:Connect(hideOther)
end

local function handBack()
	takenOver = false
	if childAddedConn then
		childAddedConn:Disconnect()
		childAddedConn = nil
	end
	for _, connection in pairs(watchers) do connection:Disconnect() end
	table.clear(watchers)
	for other, wasEnabled in pairs(hidden) do
		if wasEnabled and other.Parent ~= nil and other.Enabled == false then
			other.Enabled = true
		end
	end
	table.clear(hidden)
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
		GuiService.SelectedObject = hub.Active and hub or closeButton
	end

	function blurModal()
		ContextActionService:UnbindAction(ACTION)
		if GuiService.SelectedObject == hub or GuiService.SelectedObject == closeButton then
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

	-- AUDIT_FIX_20260924: a pad picked up while the wheel is already open takes
	-- focus too, the way the terminal does; focusModal checks for the pad.
	UserInputService.LastInputTypeChanged:Connect(function()
		if shade.Visible and GuiService.SelectedObject == nil and not GuiService.MenuIsOpen then
			focusModal()
		end
	end)
end

function closeModal()
	if not shade.Visible then return end
	shade.Visible = false
	-- Nobody is watching the replay, so it is over. The prize was banked before
	-- the animation started; only the garnish is being skipped.
	finishSpin()
	-- AUDIT_FIX_20260924: hand back BEFORE unpublishing, so an owner that yields
	-- to screen-owning modals re-syncs AFTER the restore in either signal mode.
	handBack()
	player:SetAttribute("LuckyWheelOpen", nil)
	-- Suppression is SHARED. Derive the request from the complete published
	-- modal set rather than letting the last caller win -- exactly as
	-- ZyntraStore.setMainVisible does.
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	blurModal()
end

function openModal()
	if shade.Visible or blockedFromOpening() then return end
	retryOffered = false
	-- BEFORE the shade is drawn, so nothing flashes underneath it.
	takeOver()
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

hub.Activated:Connect(function()
	-- A tap while the disc is turning SKIPS. This is the whole reason the hub
	-- stays Active during a spin.
	if spinning then finishSpin() return end
	if pendingSpin or pendingClaim or not hub.Active or #sectors == 0 then return end
	local owed = pendingPrize()
	if owed then
		-- COLLECT PRIZE. One request in flight; a second tap re-asks nothing. The
		-- recovery from silence is a RE-READ (RETRY re-enters here), never a
		-- local grant.
		pendingClaim = true
		retryOffered = false
		awaitingClaim = tonumber(owed.Serial)
		claimSerial += 1
		local serial = claimSerial
		actionRemote:FireServer("ClaimWheelPrize")
		render()
		task.delay(ACTION_TIMEOUT, function()
			if not pendingClaim or claimSerial ~= serial then return end
			pendingClaim = false
			awaitingClaim = nil
			retryOffered = true
			refreshProfile()
			render()
		end)
		return
	end
	if spunToday() then return end
	pendingSpin = true
	retryOffered = false
	pendingSerial += 1
	local serial = pendingSerial
	actionRemote:FireServer("SpinDailyWheel")
	render()
	task.delay(ACTION_TIMEOUT, function()
		-- No answer at all. The recovery is a RE-READ, never a local grant.
		if not pendingSpin or pendingSerial ~= serial then return end
		pendingSpin = false
		retryOffered = true
		refreshProfile()
		render()
	end)
end)

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
-- A respawn destroys and re-clones every ResetOnSpawn gui in PlayerGui, so the
-- takeover has to end before that happens rather than hand back to a tree that
-- is no longer the one it hid.
player.CharacterAdded:Connect(function()
	if shade.Visible then closeModal() end
end)

UIDevice.Changed:Connect(applyLayout)

RunService.Heartbeat:Connect(function(delta)
	clockAccum += delta
	-- 1 Hz, and only while the wheel is on screen: a countdown redrawn every
	-- frame is 59 wasted string builds a second, and one redrawn behind a closed
	-- modal is 60.
	if clockAccum < 1 then return end
	clockAccum = 0
	if not shade.Visible then return end
	render()
	if remainingSeconds() == 0 and spunToday() and not rollAsked then
		-- The UTC day just rolled. The server owns the new counters, so this
		-- asks for them rather than zeroing anything itself.
		rollAsked = true
		refreshProfile()
	end
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

render()
refreshProfile()
