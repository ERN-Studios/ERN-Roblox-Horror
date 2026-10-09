-- Round HUD (StarterPlayerScripts."Round HUD") -- the cross-level body-state driver (owner, 2026-10-08).
--
-- HUD_B3: artifacts/hud-final-20261008/b3/B3-DESIGN.md section 6 and its critic findings K3-K16;
-- BUILD-PLAN 1.1, 02 and 03. Two elements, neither with an owner of its own:
--   * the chase edge (02 A, reduced flashing): four static Coral bands in the ScreenGui RoundHudThreat
--     (DisplayOrder 20), on while BeingChased == true outside Level 2;
--   * the sneak / loud marker (03 C; adrenaline is never drawn): HUD_PC/NoiseMarker in the RoundHud gui, one of
--     GRACE > HIDDEN > LOUD > SNEAKING, centred above the stamina bar (NoiseReporter owns the bar).
-- It is also RoundHud.Clear()'s first caller, on InRound true -> false (D17). B5 adds the feed here.
--
-- Reads (never writes): Player InRound, Spectating, Escaped, BeingChased, Level3_Hiding, Level4_Hidden,
-- Level4CardOpen, PlayerProtectionActive / ExpiresAt / Source, and the client-local MoveNoise that
-- NoiseReporter's applySpeed publishes ("walk" | "sprint" | "crouch"); workspace RoundActive and
-- SelectedLevel. ASCII-only source: install_new_scripts embeds it with json.dumps.

local Players, RS = game:GetService("Players"), game:GetService("ReplicatedStorage")
local RunService, TweenService = game:GetService("RunService"), game:GetService("TweenService")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local player = Players.LocalPlayer
if not game:IsLoaded() then game.Loaded:Wait() end
-- HUD_B3: no waits on templates (B2 critic C3); a missing one is RoundHud's warning by path.
local hudModule, shopUI = RS:FindFirstChild("RoundHud"), RS:FindFirstChild("ZyntraShopUI")
local binderModule = shopUI and shopUI:FindFirstChild("ShopBinder")
if not (hudModule and binderModule) then warn("[Round HUD] RoundHud or ShopBinder is missing: nothing drawn") return end
local Hud, Binder = require(hudModule), require(binderModule)
local P = Binder.Palette

-- == B3 chase edge (02 A, reduced flashing; owner, 2026-10-08) ==
-- HUD_B3: the approved frames' depth (D1): side bands 0.146 of the width, top and bottom 0.185 of the
-- height, pure Scale. Static at 0.8 for every player: the picked variant already IS the reduced one,
-- so no accessibility setting is consulted and nothing here depends on a clock (D2). Order 20 sits
-- under the touch cells, Level 3's hide shade and RoundUI, on purpose.
local EDGE_SIDE, EDGE_TOP_BOTTOM = 0.146, 0.185
local EDGE_ALPHA, EDGE_FADE_IN, EDGE_FADE_OUT = 0.8, 0.18, 0.4

local threat = Instance.new("ScreenGui")
threat.Name = "RoundHudThreat"
threat.DisplayOrder = 20
threat.ResetOnSpawn = false
threat.IgnoreGuiInset = true
threat.ScreenInsets = Enum.ScreenInsets.None -- full screen, under the notch too
threat.Parent = player:WaitForChild("PlayerGui")

-- Name, AnchorPoint, Position, Size, gradient Rotation (the gradient runs screen edge -> inward). The
-- ChaseEdge* names are what UIRegression's FULLSCREEN_OVERLAYS will list (critic K6).
local bands = {}
for _, spec in ipairs({
	{"ChaseEdgeLeft", Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(EDGE_SIDE, 1), 0},
	{"ChaseEdgeRight", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(EDGE_SIDE, 1), 180},
	{"ChaseEdgeTop", Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(1, EDGE_TOP_BOTTOM), 90},
	{"ChaseEdgeBottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, EDGE_TOP_BOTTOM), 270},
}) do
	local band = Instance.new("Frame")
	band.Name = spec[1]
	band.AnchorPoint, band.Position, band.Size = spec[2], spec[3], spec[4]
	band.BackgroundColor3 = P.Coral
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.Active = false
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Rotation = spec[5]
	gradient.Parent = band
	band.Parent = threat
	table.insert(bands, band)
end

local edgeOn = false
local function setEdge(on)
	if on == edgeOn then return end
	edgeOn = on
	local info = TweenInfo.new(on and EDGE_FADE_IN or EDGE_FADE_OUT)
	for _, band in ipairs(bands) do
		TweenService:Create(band, info, {BackgroundTransparency = on and EDGE_ALPHA or 1}):Play()
	end
end
-- == end B3 chase edge ==

-- == B3 marker (03 C; owner, 2026-10-08) ==
-- HUD_B3 geometry (B3-DESIGN 2.2, pinned against NoiseReporter by test_round_hud_local):
-- MARKER_BOTTOM = BAR_BOTTOM 24 + bar root 26 + gap 4; MARKER_BOTTOM_TOUCH = BAR_BOTTOM_TOUCH 4 + 26 x 0.5
-- + 5 (the phone frame's marker at y 323..347). KIT_RIGHT is B1's PC kit row (24 + 232 + 8 + 280): on a
-- window narrower than about1424px the bar/marker move right of it; below872px Safe width they use
-- a fixed upper band centred within Safe, above the maximum kit/refusal/detector stack.
local MARKER_BOTTOM, MARKER_BOTTOM_TOUCH = 54, 22
local MARKER_BOTTOM_NARROW = 258 -- BAR_BOTTOM_NARROW 228 + root 26 + gap 4
local KIT_RIGHT, BAR_HALF = 544, 160
local PILL_LEFT, PILL_RIGHT = 20, 8 -- the Label's left edge in the template, and the pill's right pad
local LOUD_SPEED, LOUD_LINGER = 2, 0.5 -- studs/s (the drain's own threshold, D5); the K7 hysteresis
local GRACE_SECONDS = 10 -- PlayerProtection's Reentry window
local ROBOTO_MONO_EM = 1.3188 -- Roblox TextSize per design px for Roboto Mono (RoundHud's EM table)
local DOT = {GRACE = "RailTeal", HIDDEN = "RailTeal", LOUD = "Amber", SNEAKING = "RailTeal"}
-- B3-DESIGN 2.4: 100 % for 6 s on a change, then 45 % (LOUD 60 %). The key is the STATE, never the
-- grace seconds, so the countdown never re-wakes the pill (D7).
local REST = {LOUD = 0.6}

-- Mounted once, from HUD_PC on every device (HUD_Touch has no marker), at Scale 1.
local marker = {}
marker.Root, marker.Attention = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui(),
	{Name = "NoiseMarker", Attention = {Hold = 6, Rest = 0.45}})
local charW = 7.2
if marker.Root then
	local inner = marker.Root:FindFirstChildWhichIsA("GuiObject")
	marker.Soft = Binder.find(inner, "Soft")
	marker.Dot = Binder.find(inner, "Dot")
	marker.Label = Binder.text(Binder.find(inner, "Label"))
	-- HUD_B3: a re-import that lost a part draws no marker; it must not take the edge down with it.
	if not (marker.Soft and marker.Dot and marker.Label) then
		warn("[Round HUD] HUD_PC/NoiseMarker has no Soft, Dot or Label: no marker")
		marker.Root:Destroy()
		marker.Root = nil
	end
end
if marker.Root then
	-- K6: the clone keeps the mounted size, so the group can be narrowed to clip the hugged pill
	-- (scaleText reads its k from the clone, not the group) and UIRegression measures only the pill.
	marker.Root:FindFirstChildWhichIsA("GuiObject").Size = marker.Root.Size
	marker.Height = marker.Root.Size.Y.Offset
	marker.Soft.AnchorPoint = Vector2.new(0, 0.5)
	marker.Soft.Position = UDim2.fromScale(0, 0.5)
	marker.Root.AnchorPoint = Vector2.new(0, 1)
	-- K11: Roboto Mono is monospaced; one character at the size Roblox actually draws (the template's
	-- 12 px x EM, rounded: 16) is FW_M100 / 100 / chars x 16 = 7.36, not Figma's 7.22.
	local label = marker.Label
	local m100, text0, size = label:GetAttribute("FW_M100"), label:GetAttribute("FW_Text0"), label:GetAttribute("FigmaFontSize")
	local chars = type(text0) == "string" and utf8.len(text0)
	if type(m100) == "number" and type(size) == "number" and chars and chars > 0 then
		charW = m100 / (100 * chars) * math.floor(size * ROBOTO_MONO_EM + 0.5)
	end
end
UIDevice.Changed:Connect(function() marker.Dirty = true end)

local function pillWidth(text)
	return PILL_LEFT + utf8.len(text) * charW + PILL_RIGHT
end

-- Root placement for a pill W wide. PC (and gamepad): centred over the stamina bar. Touch: centred in
-- the corridor; a pill wider than the corridor and its two 8 px gutters takes the spot ProtectionHUD's
-- retired ReentryGrace notice had in ModalArea, clear of the open KIT fan (K3, B2 critic C9).
local function placeMarker(width)
	local layout = UIDevice.Layout()
	local safe, centre, bottom = layout.Safe, nil, nil
	if not layout.IsTouch then
		local narrow = safe.Right - safe.Left < KIT_RIGHT + 8 + 2 * BAR_HALF
		centre = if narrow then (safe.Left + safe.Right) / 2
			else math.max((safe.Left + safe.Right) / 2, safe.Left + KIT_RIGHT + 8 + BAR_HALF)
		bottom = safe.Bottom - (if narrow then MARKER_BOTTOM_NARROW else MARKER_BOTTOM)
		marker.Room = width <= safe.Right - safe.Left and bottom - marker.Height >= safe.Top
		if marker.Room then centre = math.clamp(centre, safe.Left + width / 2, safe.Right - width / 2) end
	elseif width <= layout.Corridor.Width + 16 then
		marker.Room = true
		centre = (layout.Corridor.Left + layout.Corridor.Right) / 2
		bottom = safe.Bottom - MARKER_BOTTOM_TOUCH
	else
		marker.Room = true
		local area = layout.ModalArea
		centre = (area.Left + area.Right) / 2
		bottom = (layout.KitFanOpen and layout.KitFan and math.min(area.Bottom, layout.KitFan.Top - 8) or area.Bottom) - 32
	end
	marker.Root.Position = UIDevice.LocalPosition(Hud.Gui(), centre - width / 2, bottom)
end

local function showMarker(state, seconds)
	if not marker.Root then return end
	if state == nil then
		if marker.State ~= nil then
			marker.State = nil
			marker.Attention:Hide()
		end
		return
	end
	local text = state
	if state == "GRACE" then
		text = "INVISIBLE TO MONSTERS \u{B7} " .. seconds .. " s"
		local layout = UIDevice.Layout()
		-- D11: the full pill (230 px) does not fit a phone's corridor (191 at 844x390).
		if layout.IsTouch and pillWidth(text) > layout.Corridor.Width then
			text = "INVISIBLE \u{B7} " .. seconds .. " s"
		end
	end
	-- Ordinary movement labels have no backing; protection/hiding keeps its notice.
	marker.Soft.BackgroundTransparency = (state == "SNEAKING" or state == "LOUD") and 1 or 0
	if text ~= marker.Text or marker.Dirty then
		marker.Text, marker.Dirty = text, false
		local width = pillWidth(text)
		marker.Label.Text = text
		marker.Soft.Size = UDim2.new(0, width, 1, 0)
		marker.Dot.BackgroundColor3 = P[DOT[state]]
		marker.Root.Size = UDim2.fromOffset(math.ceil(width), marker.Height)
		placeMarker(width)
	end
	if not marker.Room then
		marker.State = nil
		marker.Attention:Hide()
		return
	end
	if state ~= marker.State then
		marker.State = state
		marker.Attention:Show(state, false, REST[state])
	end
end

local lastFastAt = -math.huge
local function graceRemaining()
	local expires = player:GetAttribute("PlayerProtectionExpiresAt")
	-- ProtectionHUD secondsRemaining's guards, exactly, for the Reentry source only (D7).
	if player:GetAttribute("PlayerProtectionSource") ~= "Reentry" or player:GetAttribute("PlayerProtectionActive") ~= true
		or type(expires) ~= "number" or expires ~= expires or expires == math.huge or expires == -math.huge then return 0 end
	return math.clamp(expires - workspace:GetServerTimeNow(), 0, GRACE_SECONDS)
end

-- Returns the state and, for GRACE, the whole seconds left.
local function markerState(character)
	-- K7/K8: LOUD lingers 0.5 s after the last SPRINTING frame above 2 studs/s, so a corner or a
	-- stop-start never re-wakes it, and Shift just after a walk is still silent standing still (D5);
	-- the plain sum of squares, because the speed is horizontal only.
	local noise = player:GetAttribute("MoveNoise")
	local root = noise == "sprint" and character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local v = root.AssemblyLinearVelocity
		if math.sqrt(v.X * v.X + v.Z * v.Z) > LOUD_SPEED then lastFastAt = os.clock() end
	end
	local remaining = graceRemaining()
	if remaining > 0 then return "GRACE", math.ceil(remaining) end
	if player:GetAttribute("Level3_Hiding") == true or player:GetAttribute("Level4_Hidden") == true then return "HIDDEN" end
	if noise == "sprint" and os.clock() - lastFastAt < LOUD_LINGER then return "LOUD" end
	if noise == "crouch" then return "SNEAKING" end
	return nil
end
-- == end B3 marker ==

-- HUD_B3 lifecycle: one Heartbeat. The base gate (B3-DESIGN 2.3) is a living, in-round, not spectating,
-- not escaped body in an active round; the loading cover and the death card sit above order 20.
local wasInRound = false
RunService.Heartbeat:Connect(function()
	local inRound = player:GetAttribute("InRound") == true
	if wasInRound and not inRound then Hud.Clear() end -- the first caller (D17)
	wasInRound = inRound
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local base = inRound and humanoid ~= nil and humanoid.Health > 0
		and player:GetAttribute("Spectating") ~= true and player:GetAttribute("Escaped") ~= true
		and workspace:GetAttribute("RoundActive") == true
	-- Level 2 keeps the marker but never the edge (owner).
	setEdge(base and player:GetAttribute("BeingChased") == true and workspace:GetAttribute("SelectedLevel") ~= 2)
	-- K5: the touch Level 4 keypad (order 6 until B7) would sit under the marker; remove this clause in B7.
	if base and player:GetAttribute("Level4CardOpen") ~= true then
		showMarker(markerState(character))
	else
		showMarker(nil)
	end
end)

-- == B5 common RoundStatus feed ==
-- Team Objective Feed's server-owned level/serial/actor/detail gates live here after its retirement.
-- RoundUI owns teammate escape delivery; this listener never duplicates that row or own results.
do
	local lastSerial, connection = 0, nil
	local function onStatus(kind, actor, position, cause, aliveCount)
		if player:GetAttribute("InRound") ~= true then return end
		if kind == "objective" then
			local payload = actor
			if type(payload) ~= "table" or payload.Level ~= workspace:GetAttribute("SelectedLevel") then return end
			local serial = payload.Serial
			if type(serial) ~= "number" or serial ~= serial or serial == math.huge or serial <= lastSerial then return end
			lastSerial = serial
			if type(payload.Actor) ~= "string" or type(payload.Detail) ~= "string" then return end
			Hud.Feed({Kind = "TEAM", Actor = payload.Actor, Detail = payload.Detail, Key = payload.Key})
		elseif kind == "death" and type(actor) == "string" and actor ~= player.Name then
			local count = type(aliveCount) == "number" and aliveCount == aliveCount and aliveCount ~= math.huge
				and math.max(0, math.floor(aliveCount)) or nil
			Hud.Feed({Kind = "DANGER", Actor = actor,
				Detail = "is down" .. (count and (" \u{B7} " .. count .. " left") or ""), Key = "death:" .. actor})
		end
	end
	local function connectStatus()
		if connection then return end
		local remotes = RS:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("RoundStatus")
		if remote and remote:IsA("RemoteEvent") then connection = remote.OnClientEvent:Connect(onStatus) end
	end
	connectStatus()
	RS.DescendantAdded:Connect(function(node)
		if node.Name == "RoundStatus" then connectStatus() end
	end)
end
-- == end B5 common RoundStatus feed ==

-- Studio probes execute in this player's cached module instance. execute_luau's require cache is
-- separate and must never stage another RoundHud GUI or restore the wrong owner's state.
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionRoundHudProbe"
	probe.OnInvoke = function(operation, first, second, third)
		if operation == "capture" then return Hud.CaptureTestState()
		elseif operation == "restore" then return Hud.RestoreTestState(first)
		elseif operation == "setobjective" then return Hud.SetObjective(first)
		elseif operation == "feed" then return Hud.Feed(first)
		elseif operation == "caption" then return Hud.Caption(first, second, third)
		elseif operation == "snapshot" then return Hud.LastObjective()
		elseif operation == "expandobjective" then return Hud.ExpandObjectiveForTest() end
		return nil
	end
	probe.Parent = Hud.Gui()
end
