--!strict
-- Level 4 Lighting Controller
--
-- The Quiet Suburbs open on a warm, still afternoon and get colder and hazier
-- while the neighbourhood is dangerous. Two graded states, tweened between --
-- there is no flicker and no strobe anywhere in Level 4, which is deliberate:
-- Level 3 already owns the blackout, and this level's tension is supposed to
-- come from what you can still see.
--
-- THE READABILITY FLOOR IS LOAD-BEARING. Configuration.Lighting.MinimumBrightness
-- is the number that keeps this playable on a phone in daylight, and nothing
-- here may drive Lighting.Brightness under it in any state. The danger grade is
-- COLDER AND FOGGIER, never darker to the point of guesswork.
--
-- Every global Lighting property this file touches is captured on entry and
-- restored on exit, the way the Level 3 controller does it.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local LEVEL = 4
local STATE_FOLDER_NAME = "Level 4 State"

local Configuration = {
	-- Mirrors ServerScriptService."Level 4 Systems"."Level 4 Configuration".Lighting.
	-- A LocalScript cannot require a ServerScriptService module, so the numbers
	-- are restated here and the Level 4 Test Suite asserts the two agree.
	CalmClockTime = 16.4,
	CalmBrightness = 2.6,
	CalmAmbient = Color3.fromRGB(122, 116, 104),
	CalmOutdoorAmbient = Color3.fromRGB(150, 146, 134),
	CalmFogColor = Color3.fromRGB(206, 206, 198),
	CalmFogStart = 180,
	CalmFogEnd = 900,
	DangerClockTime = 17.6,
	DangerBrightness = 1.9,
	DangerAmbient = Color3.fromRGB(96, 102, 114),
	DangerOutdoorAmbient = Color3.fromRGB(112, 122, 136),
	DangerFogColor = Color3.fromRGB(150, 158, 168),
	DangerFogStart = 70,
	DangerFogEnd = 380,
	MinimumBrightness = 1.6,
	TransitionSeconds = 3.5,
}

type Snapshot = {
	Brightness: number, ClockTime: number, Ambient: Color3, OutdoorAmbient: Color3,
	FogColor: Color3, FogStart: number, FogEnd: number,
	ColorShift_Top: Color3, EnvironmentDiffuseScale: number, GlobalShadows: boolean,
	ExposureCompensation: number,
}

local snapshot: Snapshot? = nil
local active = false
local tweens: {Tween} = {}
local lastDanger: boolean? = nil

local function stateFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return folder and folder:IsA("Folder") and folder or nil
end

local function cancelTweens()
	for _, tween in ipairs(tweens) do
		if tween.PlaybackState == Enum.PlaybackState.Playing then tween:Cancel() end
	end
	table.clear(tweens)
end

local function capture(): Snapshot
	return {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogColor = Lighting.FogColor,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		ColorShift_Top = Lighting.ColorShift_Top,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		GlobalShadows = Lighting.GlobalShadows,
		ExposureCompensation = Lighting.ExposureCompensation,
	}
end

local function applyGoal(goal: {[string]: any}, seconds: number)
	cancelTweens()
	-- The floor, applied where it cannot be forgotten: whatever the goal says,
	-- the brightness that actually reaches Lighting is never under the minimum.
	goal.Brightness = math.max(goal.Brightness, Configuration.MinimumBrightness)
	if seconds <= 0 then
		for key, value in pairs(goal) do (Lighting :: any)[key] = value end
		return
	end
	local tween = TweenService:Create(Lighting,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), goal)
	table.insert(tweens, tween)
	tween:Play()
end

local function grade(danger: boolean, instant: boolean)
	local c = Configuration
	local goal = danger and {
		Brightness = c.DangerBrightness,
		ClockTime = c.DangerClockTime,
		Ambient = c.DangerAmbient,
		OutdoorAmbient = c.DangerOutdoorAmbient,
		FogColor = c.DangerFogColor,
		FogStart = c.DangerFogStart,
		FogEnd = c.DangerFogEnd,
	} or {
		Brightness = c.CalmBrightness,
		ClockTime = c.CalmClockTime,
		Ambient = c.CalmAmbient,
		OutdoorAmbient = c.CalmOutdoorAmbient,
		FogColor = c.CalmFogColor,
		FogStart = c.CalmFogStart,
		FogEnd = c.CalmFogEnd,
	}
	-- ReduceFlashing lengthens the transition rather than shortening it: the
	-- shift is already slow, and the accessibility request is "no sudden
	-- change", not "no change".
	local reduce = player:GetAttribute("ReduceFlashing") == true
	applyGoal(goal, instant and 0 or (c.TransitionSeconds * (reduce and 1.6 or 1)))
end

local function dangerNow(): boolean
	local folder = stateFolder()
	if not folder then return false end
	local neighbour = folder:GetAttribute("Level4_NeighbourState")
	if neighbour == "ALERT" or neighbour == "CHASE" then return true end
	return (tonumber(folder:GetAttribute("Level4_UnsafeHouses")) or 0) > 0
end

local function enter()
	if active then return end
	active = true
	snapshot = capture()
	lastDanger = nil
	-- One flat, artificial sky. GlobalShadows stays ON: the level is a bright
	-- outdoor space and the house shadows are most of what makes the blockout
	-- readable at all.
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.ExposureCompensation = 0
	grade(false, true)
end

local function leave()
	if not active then return end
	active = false
	cancelTweens()
	local saved = snapshot
	snapshot = nil
	lastDanger = nil
	if not saved then return end
	for key, value in pairs(saved) do (Lighting :: any)[key] = value end
end

local function sync()
	-- Wait for the server's ownership flag: entering before it captures a
	-- snapshot of whatever grade RoundUI was still writing.
	if workspace:GetAttribute("SelectedLevel") ~= LEVEL
		or workspace:GetAttribute("Level4LightingOwnedByController") ~= true then
		leave()
		return
	end
	enter()
	local danger = dangerNow()
	if danger ~= lastDanger then
		lastDanger = danger
		grade(danger, false)
	end
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(sync)

-- A two-per-second poll rather than an attribute listener per key: the state
-- folder is replaced wholesale when a round is rebuilt, so a listener bound to
-- yesterday's folder would quietly stop reporting.
task.spawn(function()
	while true do
		local ok, problem = pcall(sync)
		if not ok then warn("[Level 4] lighting sync failed: " .. tostring(problem)) end
		task.wait(0.5)
	end
end)

-- A client that leaves mid-round must not take the suburb's sky with it into
-- the lobby.
player.CharacterAdded:Connect(function()
	if workspace:GetAttribute("SelectedLevel") ~= LEVEL then leave() end
end)

sync()
