-- Level 4 Lighting Controller (LocalScript in StarterPlayerScripts; installed 2026-10-01).
-- Client-side interior grade for the Blender cinema (Workspace."Level 4 Cinema Blender"), modelled on the
-- Level 2 controller: while the local character stands inside the model's stored bounds (BoundsCenter /
-- BoundsSize, set by tools/level4_blender/place.luau) it applies the "Synthwave Grid" grade (owner pick
-- 2026-09-30: deep blacks, magenta/cyan neon that blooms, a slight purple haze), designed for
-- LightingStyle Realistic (the fixtures are real local lights with shadows), and it restores exactly what it
-- found when the character leaves, dies or the model goes away.
-- It publishes the client-local player attribute Level4LightingOwned. RoundUI re-applies the lobby grade every
-- 0.5 s and must stand down on it; the block to add at the top of RoundUI's applyPlayerLighting(), right after
-- `local isLevelThree = ...` (no new top-level local: RoundUI sits at the 200-register limit; run the compile
-- probe after):
--  if player:GetAttribute("Level4LightingOwned") == true then
--   lobbyGrade.Enabled = false
--   if mazeGrade then mazeGrade.Enabled = false end
--   return
--  end
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local MODEL_NAME = "Level 4 Cinema Blender"
local OWNED_ATTRIBUTE = "Level4LightingOwned"
local CHECK_INTERVAL = 0.25
local REAPPLY_INTERVAL = 0.75

-- dark interior lit only by the fixtures; exposure independent of ClockTime. Ambient is a violet near-black so the
-- dead stretches read as dark but never as a flat void.
local GRADE = {
	ClockTime = 0,
	Brightness = 0,
	Ambient = Color3.fromRGB(26, 20, 34),     -- play-tested 2026-10-01: (9,6,14) left whole rooms unreadable
	OutdoorAmbient = Color3.fromRGB(0, 0, 0),
	ColorShift_Top = Color3.fromRGB(0, 0, 0),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0.25,
	EnvironmentSpecularScale = 0.9,   -- neon picked up in the lacquer, chrome and wet floor
	ExposureCompensation = 0.7,
	ShadowSoftness = 0.25,
	GlobalShadows = true,
}
local ATMOSPHERE = {
	Density = 0.28,
	Haze = 1.2,
	Glare = 0,
	Offset = 0,
	Color = Color3.fromRGB(42, 24, 60),
	Decay = Color3.fromRGB(14, 8, 24),
}
local GRADE_EFFECT = { Brightness = -0.02, Contrast = 0.16, Saturation = 0.06, TintColor = Color3.fromRGB(246, 236, 255) }
local BLOOM = { Intensity = 0.65, Size = 28, Threshold = 1.0 }
local DEPTH = { FarIntensity = 0.08, FocusDistance = 14, InFocusRadius = 45, NearIntensity = 0 }

local function effect(className, name, props, parent)
	local e = parent:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in props do e[k] = v end
	e.Enabled = false
	e.Parent = parent
	return e
end

local grade = effect("ColorCorrectionEffect", "Level 4 Client Color Grade", GRADE_EFFECT, Lighting)
local bloom = effect("BloomEffect", "Level 4 Client Bloom", BLOOM, Lighting)
local depth = effect("DepthOfFieldEffect", "Level 4 Client Depth", DEPTH, workspace.CurrentCamera or Lighting)
local ours = { [grade] = true, [bloom] = true, [depth] = true }

local saved = nil        -- what the place had when we took over; nil while inactive
local applying = false

local function inside()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.Health > 0 and humanoid.RootPart
	local model = workspace:FindFirstChild(MODEL_NAME)
	local centre = model and model:GetAttribute("BoundsCenter")
	local size = model and model:GetAttribute("BoundsSize")
	if not (root and typeof(centre) == "Vector3" and typeof(size) == "Vector3") then return false end
	local d = root.Position - centre
	return math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2
end

local function inheritedEffects()
	local list = {}
	for _, e in Lighting:GetChildren() do
		if not ours[e] and (e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect")
			or e:IsA("DepthOfFieldEffect")) then
			table.insert(list, e)
		end
	end
	return list
end

local function take()
	saved = { lighting = {}, effects = {} }
	for k in GRADE do saved.lighting[k] = Lighting[k] end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		saved.atmosphere = atmosphere
		saved.atmosphereProps = {}
		for k in ATMOSPHERE do saved.atmosphereProps[k] = atmosphere[k] end
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "Level 4 Client Atmosphere"
		saved.createdAtmosphere = atmosphere
		atmosphere.Parent = Lighting
	end
end

local function apply()
	applying = true
	for k, v in GRADE do Lighting[k] = v end
	local atmosphere = saved.atmosphere or saved.createdAtmosphere
	if atmosphere and atmosphere.Parent then
		for k, v in ATMOSPHERE do atmosphere[k] = v end
	end
	for _, e in inheritedEffects() do                  -- inherited Bloom / SunRays / grades (LobbyLocalGrade) are suppressed
		if saved.effects[e] == nil then saved.effects[e] = e.Enabled end
		e.Enabled = false
	end
	if workspace.CurrentCamera and depth.Parent ~= workspace.CurrentCamera then depth.Parent = workspace.CurrentCamera end
	grade.Enabled, bloom.Enabled, depth.Enabled = true, true, true
	applying = false
end

local function release()
	grade.Enabled, bloom.Enabled, depth.Enabled = false, false, false
	for k, v in saved.lighting do Lighting[k] = v end
	if saved.atmosphere and saved.atmosphere.Parent then
		for k, v in saved.atmosphereProps do saved.atmosphere[k] = v end
	end
	if saved.createdAtmosphere then saved.createdAtmosphere:Destroy() end
	for e, enabled in saved.effects do
		if e.Parent then e.Enabled = enabled end
	end
	saved = nil
end

-- a server Lighting write that lands while we own the grade is put back at once (not on the next pass)
Lighting.Changed:Connect(function(prop)
	local want = GRADE[prop]
	if saved and not applying and want ~= nil and Lighting[prop] ~= want then
		if typeof(want) == "number" and math.abs(Lighting[prop] - want) < 1e-4 then return end
		Lighting[prop] = want
	end
end)

local lastCheck, lastApply = 0, 0
local function step()
	local now = time()
	if now - lastCheck < CHECK_INTERVAL then return end
	lastCheck = now
	local want = inside()
	if want and not saved then
		take()
		apply()
		lastApply = now
		player:SetAttribute(OWNED_ATTRIBUTE, true)
	elseif not want and saved then
		release()
		player:SetAttribute(OWNED_ATTRIBUTE, false)
	elseif want and now - lastApply >= REAPPLY_INTERVAL then
		apply()
		lastApply = now
	end
end

RunService.Heartbeat:Connect(step)
player.CharacterRemoving:Connect(function()
	if saved then
		release()
		player:SetAttribute(OWNED_ATTRIBUTE, false)
	end
end)
