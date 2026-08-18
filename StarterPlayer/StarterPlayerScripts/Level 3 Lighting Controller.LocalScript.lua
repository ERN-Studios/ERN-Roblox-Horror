--!strict
-- Level 3 Lighting Controller
-- A readable, artificial mall/service-space grade with sparse fluorescent
-- instability. All global Lighting properties are captured and restored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local random = Random.new()

local LEVEL = 3
local WORLD_NAME = "Level 3 Generated World"
local STATE_FOLDER_NAME = "Level 3 State"
local MAX_FLICKER_FIXTURES = 10

type LightingSnapshot = {
	Brightness: number,
	ClockTime: number,
	ExposureCompensation: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ColorShiftTop: Color3,
	ColorShiftBottom: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
	ShadowSoftness: number,
	GlobalShadows: boolean,
}

type FixtureRecord = {
	Part: BasePart,
	Light: SurfaceLight,
	Brightness: number,
	Enabled: boolean,
	NextAt: number,
	RestoreAt: number,
	Pulse: number,
	NextPulseAt: number,
}

type SuppressedEffect = {
	Effect: PostEffect,
	Enabled: boolean,
}

type BlackoutLightRecord = {
	Light: Light,
	Enabled: boolean,
	Brightness: number,
}

type BlackoutPartRecord = {
	Part: BasePart,
	Material: Enum.Material,
	Color: Color3,
}

local grade = Lighting:FindFirstChild("Level3ClientColorGrade")
if not (grade and grade:IsA("ColorCorrectionEffect")) then
	if grade then grade:Destroy() end
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "Level3ClientColorGrade"
	grade.Parent = Lighting
end
local colorGrade = grade :: ColorCorrectionEffect
colorGrade.Enabled = false

local bloomObject = Lighting:FindFirstChild("Level3ClientBloom")
if not (bloomObject and bloomObject:IsA("BloomEffect")) then
	if bloomObject then bloomObject:Destroy() end
	bloomObject = Instance.new("BloomEffect")
	bloomObject.Name = "Level3ClientBloom"
	bloomObject.Parent = Lighting
end
local bloom = bloomObject :: BloomEffect
bloom.Enabled = false

local snapshot: LightingSnapshot? = nil
local active = false
local transitionSerial = 0
local tweens: {Tween} = {}
local lastExitUnlocked: boolean? = nil
local suppressedEffects: {SuppressedEffect} = {}

local fixtures: {FixtureRecord} = {}
local fixtureByPart: {[BasePart]: FixtureRecord} = {}
local boundWorld: Model? = nil
local worldAddedConnection: RBXScriptConnection? = nil
local worldRemovingConnection: RBXScriptConnection? = nil
local blackoutApplied = false
local blackoutLights: {BlackoutLightRecord} = {}
local blackoutParts: {BlackoutPartRecord} = {}
local blackoutPartSeen: {[BasePart]: boolean} = {}
local blackoutFlickerPulse = -1
local preBlackoutApplied = false
local preBlackoutFlickerPulse = -1
local recoveryFlickerApplied = false
local recoveryFlickerPulse = -1
local BLACKOUT_SCREAM_DURATION = 8.071836735
local BLACKOUT_FLICKER_INTERVAL = 0.085
local PRE_BLACKOUT_FLICKER_INTERVAL = 0.09
local RECOVERY_FLICKER_INTERVAL = 0.085
script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
script:SetAttribute("Level3_BlackoutScreamFlickerPulse", -1)
script:SetAttribute("Level3_PreBlackoutFlickerActive", false)
script:SetAttribute("Level3_PreBlackoutFlickerPulse", -1)
script:SetAttribute("Level3_RecoveryFlickerActive", false)
script:SetAttribute("Level3_RecoveryFlickerPulse", -1)
local applyLevelGrade: (boolean) -> ()

local function cancelTweens()
	for _, tween in ipairs(tweens) do tween:Cancel() end
	table.clear(tweens)
end

local function tween(instance: Instance, duration: number, goals: {[string]: any})
	local object = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	table.insert(tweens, object)
	object:Play()
end

local function captureLighting(): LightingSnapshot
	return {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		ExposureCompensation = Lighting.ExposureCompensation,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ColorShiftTop = Lighting.ColorShift_Top,
		ColorShiftBottom = Lighting.ColorShift_Bottom,
		FogColor = Lighting.FogColor,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
		ShadowSoftness = Lighting.ShadowSoftness,
		GlobalShadows = Lighting.GlobalShadows,
	}
end

local function suppressInheritedEffects()
	table.clear(suppressedEffects)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child ~= bloom and (child:IsA("BloomEffect") or child:IsA("SunRaysEffect")) then
			table.insert(suppressedEffects, {
				Effect = child,
				Enabled = child.Enabled,
			})
			child.Enabled = false
		end
	end
end

local function restoreInheritedEffects()
	for _, record in ipairs(suppressedEffects) do
		if record.Effect.Parent then record.Effect.Enabled = record.Enabled end
	end
	table.clear(suppressedEffects)
end

local function stateFolder(): Folder?
	local object = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return if object and object:IsA("Folder") then object else nil
end

local function exitUnlocked(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level3_ExitUnlocked")
	if value == nil then value = workspace:GetAttribute("Level3ExitUnlocked") end
	return value == true
end

local function blackoutRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level3_BlackoutActive")
	if value == nil then value = workspace:GetAttribute("Level3BlackoutActive") end
	return value == true
end

local function preBlackoutRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level3_PreBlackoutActive")
	if value == nil then value = workspace:GetAttribute("Level3PreBlackoutActive") end
	return value == true or (state and state:GetAttribute("Level3_RoomSongPhase") == "PRE_BLACKOUT")
end

local function recoveryFlickerRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level3_RecoveryFlickerActive")
	if value == nil then value = workspace:GetAttribute("Level3RecoveryFlickerActive") end
	return value == true or (state and state:GetAttribute("Level3_RoomSongPhase") == "RECOVERY_FLICKER")
end

local function captureWorldLightBaseline()
	table.clear(blackoutLights)
	table.clear(blackoutParts)
	table.clear(blackoutPartSeen)
	local world = boundWorld
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("Light") then
			table.insert(blackoutLights, {
				Light = descendant,
				Enabled = descendant.Enabled,
				Brightness = descendant.Brightness,
			})
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") and not blackoutPartSeen[parent] then
				blackoutPartSeen[parent] = true
				table.insert(blackoutParts, {
					Part = parent,
					Material = parent.Material,
					Color = parent.Color,
				})
			end
		end
	end
end

local function restoreBlackoutWorld()
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = record.Enabled
			record.Light.Brightness = record.Brightness
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = record.Material
			record.Part.Color = record.Color
		end
	end
	table.clear(blackoutLights)
	table.clear(blackoutParts)
	table.clear(blackoutPartSeen)
	blackoutFlickerPulse = -1
	preBlackoutFlickerPulse = -1
	recoveryFlickerPulse = -1
	blackoutApplied = false
	preBlackoutApplied = false
	recoveryFlickerApplied = false
	script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
	script:SetAttribute("Level3_BlackoutScreamFlickerPulse", -1)
	script:SetAttribute("Level3_PreBlackoutFlickerActive", false)
	script:SetAttribute("Level3_PreBlackoutFlickerPulse", -1)
	script:SetAttribute("Level3_RecoveryFlickerActive", false)
	script:SetAttribute("Level3_RecoveryFlickerPulse", -1)
end

local function enforceBlackout()
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = false
			record.Light.Brightness = 0
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = Enum.Material.SmoothPlastic
			record.Part.Color = Color3.fromRGB(13, 14, 15)
		end
	end
	script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
end

local function updateBlackoutFlicker()
	if not blackoutApplied then return end
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level3_BlackoutScreamStartedAtServerTime")
	local durationValue = state and state:GetAttribute("Level3_BlackoutScreamDuration")
	local serialValue = state and state:GetAttribute("Level3_BlackoutSerial")
	local startedAt = if type(startValue) == "number" then startValue else 0
	local duration = if type(durationValue) == "number" and durationValue > 0
		then durationValue else BLACKOUT_SCREAM_DURATION
	local elapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or elapsed < 0 or elapsed >= duration then
		if blackoutFlickerPulse ~= -1 then
			blackoutFlickerPulse = -1
			script:SetAttribute("Level3_BlackoutScreamFlickerPulse", -1)
		end
		enforceBlackout()
		return
	end

	local pulse = math.floor(elapsed / BLACKOUT_FLICKER_INTERVAL)
	if pulse == blackoutFlickerPulse then return end
	blackoutFlickerPulse = pulse
	local serial = if type(serialValue) == "number" then math.floor(serialValue) else 0
	-- Shared server-time hashing gives every client the same violent, irregular
	-- sequence without local waits drifting apart.
	local lit = ((pulse * 37 + serial * 17 + 5) % 11) < 4 or pulse % 13 == 0
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = lit and record.Enabled
			record.Light.Brightness = if lit then record.Brightness * 1.4 else 0
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = if lit then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color else Color3.fromRGB(13, 14, 15)
		end
	end
	script:SetAttribute("Level3_BlackoutScreamFlickerActive", true)
	script:SetAttribute("Level3_BlackoutScreamFlickerPulse", pulse)
end

local function normalizeSubtleFixtures()
	for _, record in ipairs(fixtures) do
		if record.Light.Parent then
			record.Light.Brightness = record.Brightness
			record.Light.Enabled = record.Enabled
		end
		if record.Part.Parent then record.Part.Material = Enum.Material.Neon end
		record.RestoreAt = 0
		record.Pulse = 0
		record.NextPulseAt = 0
	end
end

local function beginPreBlackout()
	if preBlackoutApplied or blackoutApplied or recoveryFlickerApplied then return end
	normalizeSubtleFixtures()
	captureWorldLightBaseline()
	preBlackoutApplied = true
	preBlackoutFlickerPulse = -1
	script:SetAttribute("Level3_PreBlackoutFlickerActive", true)
end

local function updatePreBlackoutFlicker()
	if not preBlackoutApplied then return end
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level3_PreBlackoutStartedAtServerTime")
	local untilValue = state and state:GetAttribute("Level3_PreBlackoutUntilServerTime")
	local serialValue = state and state:GetAttribute("Level3_PreBlackoutSerial")
	local startedAt = if type(startValue) == "number" then startValue else 0
	local untilTime = if type(untilValue) == "number" then untilValue else 0
	local duration = math.max(.1, untilTime - startedAt)
	local elapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or elapsed < 0 or elapsed >= duration then return end
	local pulse = math.floor(elapsed / PRE_BLACKOUT_FLICKER_INTERVAL)
	if pulse == preBlackoutFlickerPulse then return end
	preBlackoutFlickerPulse = pulse
	local progress = math.clamp(elapsed / duration, 0, 1)
	local serial = if type(serialValue) == "number" then math.floor(serialValue) else 0
	local offChance = .10 + progress * .67
	for index, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			local hash = ((pulse * 43 + index * 19 + serial * 11) % 100) / 100
			local surge = (pulse + index * 3) % 17 == 0
			local lit = record.Enabled and (hash > offChance or surge)
			record.Light.Enabled = lit
			record.Light.Brightness = if lit
				then record.Brightness * (surge and 1.35 or math.max(.28, 1 - progress * .48)) else 0
		end
	end
	for index, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			local hash = ((pulse * 31 + index * 23 + serial * 7) % 100) / 100
			local lit = hash > offChance or (pulse + index) % 19 == 0
			record.Part.Material = if lit then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color else Color3.fromRGB(22, 22, 20)
		end
	end
	script:SetAttribute("Level3_PreBlackoutFlickerPulse", pulse)
end

local function endPreBlackout(reapplyGrade: boolean)
	if not preBlackoutApplied then return end
	restoreBlackoutWorld()
	if reapplyGrade and active then applyLevelGrade(exitUnlocked()) end
end

local function beginRecoveryFlicker()
	if recoveryFlickerApplied then return end
	if preBlackoutApplied then endPreBlackout(false) end
	if not blackoutApplied and #blackoutLights == 0 then captureWorldLightBaseline() end
	blackoutApplied = false
	recoveryFlickerApplied = true
	recoveryFlickerPulse = -1
	script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
	script:SetAttribute("Level3_RecoveryFlickerActive", true)
	cancelTweens()
	applyLevelGrade(exitUnlocked())
end

local function updateRecoveryFlicker()
	if not recoveryFlickerApplied then return end
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level3_RecoveryFlickerStartedAtServerTime")
	local untilValue = state and state:GetAttribute("Level3_RecoveryFlickerUntilServerTime")
	local startedAt = if type(startValue) == "number" then startValue else 0
	local untilTime = if type(untilValue) == "number" then untilValue else 0
	local duration = math.max(.1, untilTime - startedAt)
	local elapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or elapsed < 0 then return end
	local progress = math.clamp(elapsed / duration, 0, 1)
	local pulse = math.floor(math.max(0, elapsed) / RECOVERY_FLICKER_INTERVAL)
	if pulse == recoveryFlickerPulse then return end
	recoveryFlickerPulse = pulse
	for index, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			local turnOnAt = .10 + (((index * 37) % 67) / 100)
			local sputter = ((pulse * 29 + index * 17) % 13) < 3
			local lit = record.Enabled and (progress >= .94 or (progress >= turnOnAt and not sputter))
			record.Light.Enabled = lit
			record.Light.Brightness = if lit then record.Brightness * math.min(1, .55 + progress * .55) else 0
		end
	end
	for index, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			local turnOnAt = .08 + (((index * 41) % 71) / 100)
			local sputter = ((pulse * 23 + index * 13) % 11) < 2
			local lit = progress >= .94 or (progress >= turnOnAt and not sputter)
			record.Part.Material = if lit then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color else Color3.fromRGB(13, 14, 15)
		end
	end
	script:SetAttribute("Level3_RecoveryFlickerPulse", pulse)
end

local function endRecoveryFlicker(reapplyGrade: boolean)
	if not recoveryFlickerApplied then return end
	restoreBlackoutWorld()
	if reapplyGrade and active then applyLevelGrade(exitUnlocked()) end
end

local function beginBlackout()
	if blackoutApplied then return end
	if recoveryFlickerApplied then endRecoveryFlicker(false) end
	if preBlackoutApplied then
		-- Keep the clean baseline captured at 2:25; never snapshot a fixture while
		-- the warning flicker has it temporarily dimmed or switched off.
		preBlackoutApplied = false
		preBlackoutFlickerPulse = -1
		script:SetAttribute("Level3_PreBlackoutFlickerActive", false)
		script:SetAttribute("Level3_PreBlackoutFlickerPulse", -1)
	else
		normalizeSubtleFixtures()
		captureWorldLightBaseline()
	end
	blackoutApplied = true
	cancelTweens()
	colorGrade.Enabled = true
	bloom.Enabled = false
	tween(Lighting, .35, {
		-- Keep the unlit world black while allowing a handheld dynamic light to
		-- survive the grade. The previous -1.55 exposure erased ~80% of its beam.
		Brightness = .04,
		ExposureCompensation = -.85,
		Ambient = Color3.fromRGB(0, 0, 0),
		OutdoorAmbient = Color3.fromRGB(0, 0, 0),
		ColorShift_Top = Color3.new(0, 0, 0),
		ColorShift_Bottom = Color3.new(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = .02,
		FogColor = Color3.fromRGB(2, 3, 4),
		FogStart = 14,
		FogEnd = 115,
	})
	tween(colorGrade, .35, {
		Brightness = -.08,
		Contrast = .13,
		Saturation = -.32,
		TintColor = Color3.fromRGB(104, 122, 132),
	})
	enforceBlackout()
end

local function endBlackout(reapplyGrade: boolean)
	if not blackoutApplied then return end
	restoreBlackoutWorld()
	if reapplyGrade and active then applyLevelGrade(exitUnlocked()) end
end

local function shouldOwnLighting(): boolean
	return workspace:GetAttribute("SelectedLevel") == LEVEL
		and workspace:GetAttribute("Level3LightingOwnedByController") == true
		and player:GetAttribute("InRound") == true
end

local function restoreFixtures()
	for _, record in ipairs(fixtures) do
		if record.Light.Parent then
			record.Light.Brightness = record.Brightness
			record.Light.Enabled = record.Enabled
		end
	end
end

local function clearFixtureRecords()
	restoreFixtures()
	table.clear(fixtures)
	table.clear(fixtureByPart)
end

local function tryAddFixture(instance: Instance)
	if #fixtures >= MAX_FLICKER_FIXTURES or not instance:IsA("BasePart") then return end
	if instance:GetAttribute("Level3_SubtleFlicker") ~= true or fixtureByPart[instance] then return end
	local light = instance:FindFirstChild("Level 3 Fluorescent Light")
	if not (light and light:IsA("SurfaceLight")) then return end
	local record: FixtureRecord = {
		Part = instance,
		Light = light,
		Brightness = light.Brightness,
		Enabled = light.Enabled,
		NextAt = os.clock() + random:NextNumber(4.5, 12),
		RestoreAt = 0,
		Pulse = 0,
		NextPulseAt = 0,
	}
	fixtureByPart[instance] = record
	table.insert(fixtures, record)
end

local function bindWorld(world: Model?)
	if world == boundWorld then return end
	if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then restoreBlackoutWorld() end
	if worldAddedConnection then worldAddedConnection:Disconnect() end
	if worldRemovingConnection then worldRemovingConnection:Disconnect() end
	worldAddedConnection = nil
	worldRemovingConnection = nil
	clearFixtureRecords()
	boundWorld = world
	if not world then return end

	for _, descendant in ipairs(world:GetDescendants()) do tryAddFixture(descendant) end
	worldAddedConnection = world.DescendantAdded:Connect(function(descendant)
		-- The builder attaches the flicker attribute immediately after parenting.
		-- Deferring one scheduler turn observes the completed fixture safely.
		task.defer(function()
			if world == boundWorld and descendant:IsDescendantOf(world) then tryAddFixture(descendant) end
		end)
	end)
	worldRemovingConnection = world.AncestryChanged:Connect(function(_, parent)
		if parent == nil and boundWorld == world then bindWorld(nil) end
	end)
end

local function refreshWorld()
	local object = workspace:FindFirstChild(WORLD_NAME)
	bindWorld(if object and object:IsA("Model") then object else nil)
end

applyLevelGrade = function(unlocked: boolean)
	lastExitUnlocked = unlocked
	cancelTweens()
	colorGrade.Enabled = true
	bloom.Enabled = true
	Lighting.GlobalShadows = true

	local tint = if unlocked then Color3.fromRGB(216, 235, 214) else Color3.fromRGB(232, 219, 184)
	local fog = if unlocked then Color3.fromRGB(93, 109, 101) else Color3.fromRGB(103, 99, 82)
	local ambient = if unlocked then Color3.fromRGB(92, 98, 94) else Color3.fromRGB(98, 91, 76)
	local outdoor = if unlocked then Color3.fromRGB(62, 69, 65) else Color3.fromRGB(66, 61, 52)

	tween(Lighting, 0.48, {
		Brightness = if unlocked then 1.64 else 1.54,
		ClockTime = 1.5,
		ExposureCompensation = if unlocked then -0.02 else -0.06,
		Ambient = ambient,
		OutdoorAmbient = outdoor,
		-- ColorShift is additive in Roblox; near-white values flatten and wash
		-- out every lit surface.  Keep it near neutral and let the dedicated
		-- color grade provide the abandoned-mall tint.
		ColorShift_Top = if unlocked then Color3.fromRGB(4, 12, 8) else Color3.fromRGB(18, 14, 8),
		ColorShift_Bottom = if unlocked then Color3.fromRGB(0, 5, 6) else Color3.fromRGB(2, 3, 0),
		FogColor = fog,
		FogStart = 72,
		FogEnd = if unlocked then 540 else 460,
		EnvironmentDiffuseScale = 0.32,
		EnvironmentSpecularScale = 0.22,
		ShadowSoftness = 0.72,
	})
	tween(colorGrade, 0.48, {
		Brightness = if unlocked then 0.012 else 0.004,
		Contrast = if unlocked then 0.040 else 0.045,
		Saturation = if unlocked then -0.045 else -0.065,
		TintColor = tint,
	})
	tween(bloom, 0.48, {
		Intensity = if unlocked then 0.11 else 0.08,
		Size = 18,
		Threshold = 1.45,
	})

	if not recoveryFlickerApplied then
		for _, record in ipairs(fixtures) do
			if record.Light.Parent then
				record.Light.Enabled = true
				record.Light.Brightness = record.Brightness
			end
		end
	end
end

local function restoreLighting()
	if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then restoreBlackoutWorld() end
	transitionSerial += 1
	local serial = transitionSerial
	local original = snapshot
	snapshot = nil
	lastExitUnlocked = nil
	cancelTweens()
	restoreFixtures()
	if not original then
		restoreInheritedEffects()
		colorGrade.Enabled = false
		bloom.Enabled = false
		return
	end

	Lighting.GlobalShadows = original.GlobalShadows
	tween(Lighting, 0.38, {
		Brightness = original.Brightness,
		ClockTime = original.ClockTime,
		ExposureCompensation = original.ExposureCompensation,
		Ambient = original.Ambient,
		OutdoorAmbient = original.OutdoorAmbient,
		ColorShift_Top = original.ColorShiftTop,
		ColorShift_Bottom = original.ColorShiftBottom,
		FogColor = original.FogColor,
		FogStart = original.FogStart,
		FogEnd = original.FogEnd,
		EnvironmentDiffuseScale = original.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = original.EnvironmentSpecularScale,
		ShadowSoftness = original.ShadowSoftness,
	})
	tween(colorGrade, 0.30, {Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1)})
	tween(bloom, 0.30, {Intensity = 0})
	task.delay(0.4, function()
		if serial ~= transitionSerial or active then return end
		restoreInheritedEffects()
		colorGrade.Enabled = false
		bloom.Enabled = false
	end)
end

local function refreshOwnership()
	local shouldBeActive = shouldOwnLighting()
	if shouldBeActive and not active then
		active = true
		transitionSerial += 1
		snapshot = captureLighting()
		suppressInheritedEffects()
		refreshWorld()
		applyLevelGrade(exitUnlocked())
	elseif not shouldBeActive and active then
		active = false
		restoreLighting()
	end
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(refreshOwnership)
workspace:GetAttributeChangedSignal("Level3LightingOwnedByController"):Connect(refreshOwnership)
workspace:GetAttributeChangedSignal("Level3ExitUnlocked"):Connect(function()
	if active and not blackoutApplied and not preBlackoutApplied and not recoveryFlickerApplied
		and lastExitUnlocked ~= exitUnlocked() then applyLevelGrade(exitUnlocked()) end
end)
player:GetAttributeChangedSignal("InRound"):Connect(refreshOwnership)
workspace.ChildAdded:Connect(function(child)
	if child.Name == WORLD_NAME then task.defer(refreshWorld) end
end)
workspace.ChildRemoved:Connect(function(child)
	if child == boundWorld then bindWorld(nil) end
end)

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.08 then return end
	accumulated = 0

	refreshOwnership()
	if not active then return end
	local wantsBlackout = blackoutRequested()
	local wantsPreBlackout = preBlackoutRequested()
	local wantsRecovery = recoveryFlickerRequested()
	if wantsBlackout then
		if recoveryFlickerApplied then endRecoveryFlicker(false) end
		beginBlackout()
		updateBlackoutFlicker()
	elseif wantsRecovery then
		beginRecoveryFlicker()
		updateRecoveryFlicker()
	elseif wantsPreBlackout then
		if blackoutApplied then endBlackout(true) end
		if recoveryFlickerApplied then endRecoveryFlicker(true) end
		beginPreBlackout()
		updatePreBlackoutFlicker()
	else
		if blackoutApplied then endBlackout(true)
		elseif preBlackoutApplied then endPreBlackout(true)
		elseif recoveryFlickerApplied then endRecoveryFlicker(true) end
	end
	local unlocked = exitUnlocked()
	if not blackoutApplied and not preBlackoutApplied and not recoveryFlickerApplied
		and unlocked ~= lastExitUnlocked then applyLevelGrade(unlocked) end

	local now = os.clock()
	for index = #fixtures, 1, -1 do
		if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then break end
		local record = fixtures[index]
		if not (record.Part.Parent and record.Light.Parent) then
			fixtureByPart[record.Part] = nil
			table.remove(fixtures, index)
		elseif record.RestoreAt > 0 and now >= record.RestoreAt then
			record.Light.Brightness = record.Brightness
			record.Part.Material = Enum.Material.Neon
			record.RestoreAt = 0
			if record.Pulse > 0 then
				record.NextPulseAt = now + random:NextNumber(0.045, 0.12)
			else
				record.NextAt = now + random:NextNumber(5.5, 16)
			end
		elseif record.RestoreAt == 0 and record.Pulse > 0 and now >= record.NextPulseAt then
			-- A failing ballast gives one or two clearly readable irregular blinks.
			record.Light.Brightness = record.Brightness * random:NextNumber(0.03, 0.18)
			record.Part.Material = Enum.Material.SmoothPlastic
			record.Pulse -= 1
			record.RestoreAt = now + random:NextNumber(0.075, 0.18)
		elseif record.RestoreAt == 0 and record.Pulse == 0 and now >= record.NextAt then
			record.Light.Brightness = record.Brightness * random:NextNumber(0.02, 0.14)
			record.Part.Material = Enum.Material.SmoothPlastic
			record.Pulse = random:NextInteger(0, 2)
			record.RestoreAt = now + random:NextNumber(0.09, 0.24)
		end
	end
end)

refreshWorld()
refreshOwnership()
