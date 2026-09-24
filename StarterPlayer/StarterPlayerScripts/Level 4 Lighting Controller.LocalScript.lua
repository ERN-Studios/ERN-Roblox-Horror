--!strict
-- Level 4 Lighting Controller
--
-- The Quiet Suburbs open in a high, even yellow-green haze -- one enormous
-- indoor room under an artificial ceiling -- and get colder and hazier
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
	CalmClockTime = 13.2,
	CalmBrightness = 2.2,
	CalmAmbient = Color3.fromRGB(132, 128, 100),
	CalmOutdoorAmbient = Color3.fromRGB(160, 158, 122),
	CalmFogColor = Color3.fromRGB(198, 196, 158),
	CalmFogStart = 160,
	CalmFogEnd = 1100,
	CalmAtmosphereDensity = 0.27,
	CalmAtmosphereHaze = 2.6,
	CalmAtmosphereColor = Color3.fromRGB(204, 198, 140),
	CalmAtmosphereDecay = Color3.fromRGB(186, 176, 112),
	DangerClockTime = 14.2,
	DangerBrightness = 1.8,
	DangerAmbient = Color3.fromRGB(100, 108, 104),
	DangerOutdoorAmbient = Color3.fromRGB(118, 128, 120),
	DangerFogColor = Color3.fromRGB(150, 160, 146),
	DangerFogStart = 60,
	DangerFogEnd = 420,
	DangerAtmosphereDensity = 0.31,
	DangerAtmosphereHaze = 2.2,
	DangerAtmosphereColor = Color3.fromRGB(162, 172, 158),
	DangerAtmosphereDecay = Color3.fromRGB(118, 130, 122),
	AtmosphereOffset = 0,
	AtmosphereGlare = 0,
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
-- ARRIVAL_SLICE_20260923. The place's Atmosphere, when it has one, overrides
-- every Fog value above and hazes the artificial ceiling into the sky. It is
-- graded with the rest and restored on exit, captured separately because it
-- is an instance, not a Lighting property.
local ATMOSPHERE_KEYS = {"Density", "Offset", "Color", "Decay", "Glare", "Haze"}
local atmosphere: Atmosphere? = nil
local atmosphereSnapshot: {[string]: any}? = nil
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

local function tweenTo(target: Instance, goal: {[string]: any}, seconds: number)
	if seconds <= 0 then
		for key, value in pairs(goal) do (target :: any)[key] = value end
		return
	end
	local tween = TweenService:Create(target,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), goal)
	table.insert(tweens, tween)
	tween:Play()
end

local function applyGoal(goal: {[string]: any}, air: {[string]: any}, seconds: number)
	cancelTweens()
	-- The floor, applied where it cannot be forgotten: whatever the goal says,
	-- the brightness that actually reaches Lighting is never under the minimum.
	goal.Brightness = math.max(goal.Brightness, Configuration.MinimumBrightness)
	tweenTo(Lighting, goal, seconds)
	if atmosphere and atmosphere.Parent == Lighting then tweenTo(atmosphere, air, seconds) end
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
	local air = {
		Density = danger and c.DangerAtmosphereDensity or c.CalmAtmosphereDensity,
		Haze = danger and c.DangerAtmosphereHaze or c.CalmAtmosphereHaze,
		Color = danger and c.DangerAtmosphereColor or c.CalmAtmosphereColor,
		Decay = danger and c.DangerAtmosphereDecay or c.CalmAtmosphereDecay,
		Offset = c.AtmosphereOffset,
		Glare = c.AtmosphereGlare,
	}
	-- ReduceFlashing lengthens the transition rather than shortening it: the
	-- shift is already slow, and the accessibility request is "no sudden
	-- change", not "no change".
	local reduce = player:GetAttribute("ReduceFlashing") == true
	applyGoal(goal, air, instant and 0 or (c.TransitionSeconds * (reduce and 1.6 or 1)))
end

-- The house the subject is standing in, by the same InteriorVolume box the
-- server's IsSheltered uses. Nil in the street.
local function houseAround(root: BasePart): Model?
	local world = workspace:FindFirstChild("Level 4 Generated World")
	if not world then return nil end
	for _, child in ipairs(world:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Level4_HouseState") ~= nil then
			local volume = child:FindFirstChild("InteriorVolume")
			if volume and volume:IsA("BasePart") then
				local offset = volume.CFrame:PointToObjectSpace(root.Position)
				local half = volume.Size * 0.5
				if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
					return child
				end
			end
		end
	end
	return nil
end

-- CALM_ARRIVAL_20260922. Danger is what threatens THIS player: the Neighbour
-- alerted on or chasing them, or the house they are standing in going bad. A
-- warned house three streets away used to hold the whole sky cold for the rest
-- of the round; it no longer counts, and the grade returns to calm when the
-- threat ends.
local function dangerNow(): boolean
	local folder = stateFolder()
	if not folder then return false end
	local subject = player
	local spectating = player:GetAttribute("SpectateTargetUserId")
	if player:GetAttribute("Spectating") == true and type(spectating) == "number" then
		subject = game:GetService("Players"):GetPlayerByUserId(spectating) or player
	end
	local neighbour = folder:GetAttribute("Level4_NeighbourState")
	if (neighbour == "ALERT" or neighbour == "CHASE")
		and folder:GetAttribute("Level4_NeighbourTargetUserId") == subject.UserId then
		return true
	end
	local character = subject.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local house = houseAround(root)
		local state = house and house:GetAttribute("Level4_HouseState")
		if state == "WARNED" or state == "DANGEROUS" then return true end
	end
	return false
end

local function enter()
	if active then return end
	active = true
	snapshot = capture()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local saved = {}
		for _, key in ipairs(ATMOSPHERE_KEYS) do saved[key] = (atmosphere :: any)[key] end
		atmosphereSnapshot = saved
	end
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
	local air, airSaved = atmosphere, atmosphereSnapshot
	atmosphere, atmosphereSnapshot = nil, nil
	if air and airSaved and air.Parent then
		for key, value in pairs(airSaved) do (air :: any)[key] = value end
	end
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
