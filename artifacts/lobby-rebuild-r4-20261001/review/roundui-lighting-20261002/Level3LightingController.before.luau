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
-- enforceBlackout used to walk the WHOLE generated mall on every throttled
-- Heartbeat -- 12.5 times a second for the ~52 s of each blackout that is not
-- the scream, and then continuously for the rest of the round once five CDs
-- unlock the exit. It is a sweep, not a tick: nothing changes between passes
-- unless the world does.
--
-- `blackoutSweptUnlocked` holds the exitUnlocked() value the last full sweep
-- ran for, and `nil` means a sweep is due now. Everything on THIS client that
-- can put a lit fixture back -- a fresh baseline, a late-streamed Light, the
-- end of a flicker pass -- writes nil here, so those cases are corrected on the
-- very next tick rather than eventually.
--
-- The interval is what covers the writers this client cannot see coming.
-- `Level 3 Objective Controller` is a SERVER module and it writes Lights inside
-- the same world (`slot.Light.Enabled = active` as CDs go into the VCR, and
-- restoreModule putting a module's Enabled/Brightness back); those arrive as
-- replicated property changes on instances that already exist, so they fire no
-- DescendantAdded and nothing local marks the sweep due. The old code hid that
-- behind brute force. This is still a poll -- deliberately -- but at 2 passes a
-- second instead of 12.5, which is where the cost was.
local BLACKOUT_SWEEP_SAFETY_INTERVAL = 0.5
local blackoutSweptUnlocked: boolean? = nil
local blackoutSweptAt = 0
local blackoutFlickerPulse = -1
local preBlackoutApplied = false
local preBlackoutFlickerPulse = -1
local recoveryFlickerApplied = false
local recoveryFlickerPulse = -1
local BLACKOUT_SCREAM_DURATION = 8.071836735
-- PHOTOSENSITIVITY. updateBlackoutFlicker computes ONE `lit` for the whole mall
-- and applies it to every fixture at once, so each pulse is a full-screen
-- luminance flip. The hash lights ~4 of every 11 pulses plus every 13th -- up
-- to ~0.45 flashes per pulse -- and the published guidance is no more than
-- three flashes a second over a large area, so the interval floor is
-- 0.45 / 3 = 0.15 s. This was 0.085 (about 4.5 flashes a second, over the
-- threshold every blackout and again every 3.5 minutes for the whole level);
-- 0.17 keeps a margin and still reads as a violent stutter rather than a fade.
--
-- The other two passes keep their authored cadence on purpose:
-- updatePreBlackoutFlicker and updateRecoveryFlicker fold the light INDEX into
-- their hash, so they are desynchronised per-fixture flicker and their
-- aggregate luminance is comparatively smooth. What they do gain is the
-- ReduceFlashing floor below.
local BLACKOUT_FLICKER_INTERVAL = 0.17
local PRE_BLACKOUT_FLICKER_INTERVAL = 0.09
local RECOVERY_FLICKER_INTERVAL = 0.085
-- ReduceFlashing does not gate the strobe slower still, it REPLACES it: no
-- fixture is switched off, no material is swapped, and the mall breathes
-- between this floor and full over REDUCED_FLASH_PERIOD seconds. The darkness
-- and the scream timing are untouched; only the on/off edge is gone.
local REDUCED_FLASH_FLOOR = 0.4
local REDUCED_FLASH_PERIOD = 1.1
local DEFAULT_COMPLETION_DIM_DURATION = 5.5
local completionFadeActive = false
local completionFadeEndsAtServerTime = 0
script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
script:SetAttribute("Level3_BlackoutScreamFlickerPulse", -1)
script:SetAttribute("Level3_PreBlackoutFlickerActive", false)
script:SetAttribute("Level3_PreBlackoutFlickerPulse", -1)
script:SetAttribute("Level3_RecoveryFlickerActive", false)
script:SetAttribute("Level3_RecoveryFlickerPulse", -1)
script:SetAttribute("Level3_CompletionBlackoutActive", false)
script:SetAttribute("Level3_CompletionDimActive", false)
script:SetAttribute("Level3_CompletionDimProgress", 0)
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

-- The player's own accessibility switch, read LIVE rather than cached: the
-- Zyntra terminal writes it mid-round and the very next pulse has to honour it.
local function reduceFlashing(): boolean
	return player:GetAttribute("ReduceFlashing") == true
end

-- LEVEL3_COMPLETION_BLACKOUT_GUIDE_20260821
local function blackoutRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level3_BlackoutActive")
	if value == nil then value = workspace:GetAttribute("Level3BlackoutActive") end
	-- Five CDs permanently hand lighting ownership to the exit breadcrumb mode;
	-- the normal music timeline may enter DONE, but it cannot relight the mall.
	return value == true or exitUnlocked()
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
	-- A fresh baseline is a fresh world, so the next enforceBlackout sweeps it.
	blackoutSweptUnlocked = nil
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
	blackoutSweptUnlocked = nil
	blackoutFlickerPulse = -1
	preBlackoutFlickerPulse = -1
	recoveryFlickerPulse = -1
	completionFadeActive = false
	completionFadeEndsAtServerTime = 0
	blackoutApplied = false
	preBlackoutApplied = false
	recoveryFlickerApplied = false
	script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
	script:SetAttribute("Level3_BlackoutScreamFlickerPulse", -1)
	script:SetAttribute("Level3_PreBlackoutFlickerActive", false)
	script:SetAttribute("Level3_PreBlackoutFlickerPulse", -1)
	script:SetAttribute("Level3_RecoveryFlickerActive", false)
	script:SetAttribute("Level3_RecoveryFlickerPulse", -1)
	script:SetAttribute("Level3_CompletionDimActive", false)
	script:SetAttribute("Level3_CompletionDimProgress", 0)
	script:SetAttribute("Level3_CompletionBlackoutActive", false)
end

local function enforceBlackout()
	-- ON CHANGE, or on the safety interval -- never once per throttled frame.
	-- Both non-flicker paths in updateBlackoutFlicker land here every 0.08 s and
	-- everything below is idempotent, so a pass whose inputs have not moved is
	-- pure waste. exitUnlocked() is the guard as well as an input: it is the only
	-- thing the published attributes at the foot of this function vary on, so a
	-- mid-blackout unlock re-sweeps without any extra signal being wired up.
	local unlocked = exitUnlocked()
	-- SERVER TIME, like every other bound in this file's blackout logic. Roblox's
	-- os.clock() is CPU time, not wall time, so a 0.5 s deadline written against
	-- it stretches on a loaded client -- and this deadline is the worst-case
	-- window in which a fixture the SERVER relit (the Objective Controller's VCR
	-- slot indicators) stays visible through the blackout. os.clock is fine at
	-- :763/:987 below, where the drift is a feel value; it is not fine here.
	local now = workspace:GetServerTimeNow()
	if blackoutSweptUnlocked == unlocked
		and now - blackoutSweptAt < BLACKOUT_SWEEP_SAFETY_INTERVAL then
		return
	end
	blackoutSweptUnlocked = unlocked
	blackoutSweptAt = now
	-- Streaming can deliver fixtures after the initial baseline snapshot. Sweep
	-- the authoritative live world so completion can never leave a late light on.
	if boundWorld then
		for _, descendant in ipairs(boundWorld:GetDescendants()) do
			if descendant:IsA("Light") then
				descendant.Enabled = false
				descendant.Brightness = 0
				local parent = descendant.Parent
				if parent and parent:IsA("BasePart") then
					parent.Material = Enum.Material.SmoothPlastic
					parent.Color = Color3.fromRGB(13, 14, 15)
				end
			end
		end
	end
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
	completionFadeActive = false
	script:SetAttribute("Level3_CompletionDimActive", false)
	script:SetAttribute("Level3_CompletionDimProgress", if unlocked then 1 else 0)
	script:SetAttribute("Level3_CompletionBlackoutActive", unlocked)
	script:SetAttribute("Level3_BlackoutScreamFlickerActive", false)
end

local function completionTiming(): (number, number, number)
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level3_CompletionDimStartedAtServerTime")
	if type(startValue) ~= "number" or startValue <= 0 then
		startValue = state and state:GetAttribute("Level3_CompletionSongStartServerTime")
	end
	local durationValue = state and state:GetAttribute("Level3_CompletionDimDuration")
	local duration = if type(durationValue) == "number" and durationValue > .1
		then durationValue else DEFAULT_COMPLETION_DIM_DURATION
	local now = workspace:GetServerTimeNow()
	local startedAt = if type(startValue) == "number" and startValue > 0 then startValue else now
	return startedAt, duration, math.clamp((now - startedAt) / duration, 0, 1)
end

local function beginCompletionFade()
	local startedAt, duration, progress = completionTiming()
	local remaining = math.max(0, duration * (1 - progress))
	completionFadeActive = remaining > .04
	completionFadeEndsAtServerTime = startedAt + duration
	script:SetAttribute("Level3_CompletionDimActive", completionFadeActive)
	script:SetAttribute("Level3_CompletionDimProgress", progress)
	script:SetAttribute("Level3_CompletionBlackoutActive", false)

	local dark = Color3.fromRGB(13, 14, 15)
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = record.Enabled
			record.Light.Brightness = record.Brightness * (1 - progress)
			if completionFadeActive then tween(record.Light, remaining, {Brightness = 0}) end
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = record.Material
			record.Part.Color = record.Color:Lerp(dark, progress)
			if completionFadeActive then tween(record.Part, remaining, {Color = dark}) end
		end
	end

	colorGrade.Enabled = true
	bloom.Enabled = false
	local targetBrightness = .04
	local targetExposure = -.85
	local targetAmbient = Color3.fromRGB(0, 0, 0)
	local targetFog = Color3.fromRGB(2, 3, 4)
	Lighting.Brightness = Lighting.Brightness + (targetBrightness - Lighting.Brightness) * progress
	Lighting.ExposureCompensation = Lighting.ExposureCompensation
		+ (targetExposure - Lighting.ExposureCompensation) * progress
	Lighting.Ambient = Lighting.Ambient:Lerp(targetAmbient, progress)
	Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(targetAmbient, progress)
	Lighting.ColorShift_Top = Lighting.ColorShift_Top:Lerp(Color3.new(0, 0, 0), progress)
	Lighting.ColorShift_Bottom = Lighting.ColorShift_Bottom:Lerp(Color3.new(0, 0, 0), progress)
	Lighting.EnvironmentDiffuseScale *= 1 - progress
	Lighting.EnvironmentSpecularScale += (.02 - Lighting.EnvironmentSpecularScale) * progress
	Lighting.FogColor = Lighting.FogColor:Lerp(targetFog, progress)
	Lighting.FogStart += (14 - Lighting.FogStart) * progress
	Lighting.FogEnd += (115 - Lighting.FogEnd) * progress
	colorGrade.Brightness += (-.08 - colorGrade.Brightness) * progress
	colorGrade.Contrast += (.13 - colorGrade.Contrast) * progress
	colorGrade.Saturation += (-.32 - colorGrade.Saturation) * progress
	colorGrade.TintColor = colorGrade.TintColor:Lerp(Color3.fromRGB(104, 122, 132), progress)
	if completionFadeActive then
		tween(Lighting, remaining, {
			Brightness = targetBrightness,
			ExposureCompensation = targetExposure,
			Ambient = targetAmbient,
			OutdoorAmbient = targetAmbient,
			ColorShift_Top = Color3.new(0, 0, 0),
			ColorShift_Bottom = Color3.new(0, 0, 0),
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = .02,
			FogColor = targetFog,
			FogStart = 14,
			FogEnd = 115,
		})
		tween(colorGrade, remaining, {
			Brightness = -.08,
			Contrast = .13,
			Saturation = -.32,
			TintColor = Color3.fromRGB(104, 122, 132),
		})
	else
		enforceBlackout()
	end
end

local function updateBlackoutFlicker()
	if not blackoutApplied then return end
	if exitUnlocked() then
		local _, duration, progress = completionTiming()
		script:SetAttribute("Level3_CompletionDimProgress", progress)
		if completionFadeActive
			and workspace:GetServerTimeNow() < completionFadeEndsAtServerTime - .01
			and progress < 1 then
			return
		end
		if duration > 0 then enforceBlackout() end
		return
	end
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
			-- The pass that just ended left fixtures lit, so the sweep below has
			-- real work to do -- exactly once.
			blackoutSweptUnlocked = nil
			script:SetAttribute("Level3_BlackoutScreamFlickerPulse", -1)
		end
		enforceBlackout()
		return
	end

	local pulse = math.floor(elapsed / BLACKOUT_FLICKER_INTERVAL)
	if reduceFlashing() then
		-- A smooth swell, never a full-scene on/off: every fixture keeps its own
		-- material and colour and none of them reaches zero, so the scream still
		-- lands as a wave of darkness with no strobe edge in it. Written every
		-- throttled frame rather than once per pulse, because the whole point is
		-- that it is continuous.
		local level = REDUCED_FLASH_FLOOR + (1 - REDUCED_FLASH_FLOOR)
			* (.5 - .5 * math.cos(elapsed * (math.pi * 2) / REDUCED_FLASH_PERIOD))
		for _, record in ipairs(blackoutLights) do
			if record.Light.Parent then
				record.Light.Enabled = record.Enabled
				record.Light.Brightness = record.Brightness * level
			end
		end
		for _, record in ipairs(blackoutParts) do
			if record.Part.Parent then
				record.Part.Material = record.Material
				record.Part.Color = Color3.fromRGB(13, 14, 15):Lerp(record.Color, level)
			end
		end
		-- Not -1, so the branch above knows a pass has touched the world and marks
		-- the sweep due when the scream ends.
		blackoutFlickerPulse = pulse
		script:SetAttribute("Level3_BlackoutScreamFlickerActive", true)
		script:SetAttribute("Level3_BlackoutScreamFlickerPulse", pulse)
		return
	end
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
	-- This pass is already desynchronised per fixture, so it is not the
	-- whole-screen strobe the scream is. ReduceFlashing still takes the on/off
	-- EDGE out of it: an unlit fixture dips to this fraction of its baseline and
	-- keeps its material instead of snapping to black.
	local dimFloor = if reduceFlashing() then REDUCED_FLASH_FLOOR else 0
	for index, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			local hash = ((pulse * 43 + index * 19 + serial * 11) % 100) / 100
			local surge = (pulse + index * 3) % 17 == 0
			local lit = record.Enabled and (hash > offChance or surge)
			record.Light.Enabled = lit or (dimFloor > 0 and record.Enabled)
			record.Light.Brightness = if lit
				then record.Brightness * (surge and 1.35 or math.max(.28, 1 - progress * .48))
				else record.Brightness * dimFloor
		end
	end
	for index, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			local hash = ((pulse * 31 + index * 23 + serial * 7) % 100) / 100
			local lit = hash > offChance or (pulse + index) % 19 == 0
			record.Part.Material = if lit or dimFloor > 0
				then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color
				else Color3.fromRGB(22, 22, 20):Lerp(record.Color, dimFloor)
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
	-- Same rule as the pre-blackout pass: desynchronised already, so the cadence
	-- stands, but ReduceFlashing removes the snap to black.
	local dimFloor = if reduceFlashing() then REDUCED_FLASH_FLOOR else 0
	for index, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			local turnOnAt = .10 + (((index * 37) % 67) / 100)
			local sputter = ((pulse * 29 + index * 17) % 13) < 3
			local lit = record.Enabled and (progress >= .94 or (progress >= turnOnAt and not sputter))
			record.Light.Enabled = lit or (dimFloor > 0 and record.Enabled)
			record.Light.Brightness = if lit
				then record.Brightness * math.min(1, .55 + progress * .55)
				else record.Brightness * dimFloor
		end
	end
	for index, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			local turnOnAt = .08 + (((index * 41) % 71) / 100)
			local sputter = ((pulse * 23 + index * 13) % 11) < 2
			local lit = progress >= .94 or (progress >= turnOnAt and not sputter)
			record.Part.Material = if lit or dimFloor > 0
				then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color
				else Color3.fromRGB(13, 14, 15):Lerp(record.Color, dimFloor)
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
	-- The pre-blackout branch above deliberately keeps its clean baseline, so
	-- captureWorldLightBaseline did not run on that path and nothing else has
	-- marked the sweep due.
	blackoutSweptUnlocked = nil
	cancelTweens()
	if exitUnlocked() then
		beginCompletionFade()
		return
	end
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
			if world ~= boundWorld or not descendant:IsDescendantOf(world) then return end
			tryAddFixture(descendant)
			if blackoutApplied and descendant:IsA("Light") then
				-- UNGATED, unlike the completion handling below it. A Light that
				-- streams in during an ORDINARY blackout is exactly the case
				-- enforceBlackout's sweep exists for, and marking the sweep due here
				-- is what lets that sweep stop running every frame the rest of the
				-- time. It costs one boolean write per late fixture.
				blackoutSweptUnlocked = nil
			end
			if blackoutApplied and exitUnlocked() and descendant:IsA("Light") then
				local _, duration, progress = completionTiming()
				local remaining = duration * (1 - progress)
				local parent = descendant.Parent
				if completionFadeActive and remaining > .04 then
					local baseline = descendant.Brightness
					descendant.Brightness = baseline * (1 - progress)
					tween(descendant, remaining, {Brightness = 0})
					if parent and parent:IsA("BasePart") then
						local dark = Color3.fromRGB(13, 14, 15)
						parent.Color = parent.Color:Lerp(dark, progress)
						tween(parent, remaining, {Color = dark})
					end
				else
					descendant.Enabled = false
					descendant.Brightness = 0
					if parent and parent:IsA("BasePart") then
						parent.Material = Enum.Material.SmoothPlastic
						parent.Color = Color3.fromRGB(13, 14, 15)
					end
				end
			end
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
