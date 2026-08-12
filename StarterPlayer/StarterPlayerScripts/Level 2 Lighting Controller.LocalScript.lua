-- Level 2 Lighting Controller
-- Client-side grade for the Sunken Leisure Complex, mirroring the Level 2
-- controller's ownership pattern. Level 2 is deliberately BRIGHT: the
-- reference photos are sunlit liminal poolrooms — no fog, high ambient bounce,
-- warm natural daylight filling every room, turquoise water.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("Level 2 State", 30)

local grade = Lighting:FindFirstChild("Level 2 Client Color Grade") or Instance.new("ColorCorrectionEffect")
grade.Name = "Level 2 Client Color Grade"
grade.Parent = Lighting

local bloom = Lighting:FindFirstChild("Level 2 Client Bloom") or Instance.new("BloomEffect")
bloom.Name = "Level 2 Client Bloom"
bloom.Parent = Lighting

-- Level 2 owns its post-processing while active. Preserve inherited place
-- effects so leaving the level restores the lobby/Level 1 exactly.
local inheritedBloom = Lighting:FindFirstChild("Bloom")
if inheritedBloom == bloom then inheritedBloom = nil end
local inheritedBloomEnabled = inheritedBloom and inheritedBloom.Enabled
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local inheritedAtmosphereDensity = atmosphere and atmosphere.Density
local inheritedExposure = Lighting.ExposureCompensation
local inheritedDiffuse = Lighting.EnvironmentDiffuseScale
local inheritedSpecular = Lighting.EnvironmentSpecularScale
local inheritedGlobalShadows = Lighting.GlobalShadows

local lastApplied = 0

local function active()
	return workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and workspace:GetAttribute("Level2LightingOwnedByController") == true
end

-- The place's own daylight, restored the moment this controller lets go —
-- an escapee stepping into the courtyard, a death, or the round ending must
-- never inherit the interior fog.
local wasActive = false
local function restoreDaylight()
	Lighting.ClockTime = 14
	Lighting.FogColor = Color3.fromRGB(192, 192, 192)
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = inheritedExposure
	Lighting.EnvironmentDiffuseScale = inheritedDiffuse
	Lighting.EnvironmentSpecularScale = inheritedSpecular
	Lighting.GlobalShadows = inheritedGlobalShadows
	Lighting.Ambient = Color3.fromRGB(92, 88, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 101, 82)
	Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	if inheritedBloom and inheritedBloom.Parent then
		inheritedBloom.Enabled = inheritedBloomEnabled
	end
	if atmosphere and atmosphere.Parent and inheritedAtmosphereDensity then
		atmosphere.Density = inheritedAtmosphereDensity
	end
end

local function apply()
	if not active() then
		grade.Enabled = false
		bloom.Enabled = false
		if wasActive then
			wasActive = false
			restoreDaylight()
		end
		return
	end
	wasActive = true
	grade.Enabled = true
	bloom.Enabled = true
	if inheritedBloom and inheritedBloom.Parent then inheritedBloom.Enabled = false end
	if atmosphere and atmosphere.Parent then atmosphere.Density = .16 end
	local mode = state and state:GetAttribute("Level2_LightingMode") or "NORMAL"

	-- Preserve the bright liminal-pool identity without clipping white tiles.
	-- Near-black color shifts add only a subtle cast; mid-gray shifts washed the
	-- entire frame out. One restrained bloom replaces the inherited double bloom.
	Lighting.ClockTime = 12
	Lighting.FogColor = Color3.fromRGB(218, 222, 207)
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
	Lighting.EnvironmentDiffuseScale = .62
	Lighting.EnvironmentSpecularScale = .58
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.fromRGB(18, 14, 8)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 5, 6)
	if mode == "EXIT_OPEN" then
		Lighting.Brightness = 1.56
		Lighting.ExposureCompensation = -.16
		Lighting.Ambient = Color3.fromRGB(92, 92, 80)
		Lighting.OutdoorAmbient = Color3.fromRGB(94, 96, 82)
		grade.Brightness = 0
		grade.Contrast = .075
		grade.Saturation = 0
		grade.TintColor = Color3.fromRGB(238, 255, 240)
		bloom.Intensity = .11
	else
		Lighting.Brightness = 1.42
		Lighting.ExposureCompensation = -.22
		Lighting.Ambient = Color3.fromRGB(82, 80, 70)
		Lighting.OutdoorAmbient = Color3.fromRGB(86, 86, 74)
		grade.Brightness = -.015
		grade.Contrast = .085
		grade.Saturation = -.02
		grade.TintColor = Color3.fromRGB(247, 242, 222)
		bloom.Intensity = .085
	end
	bloom.Size = 24
	bloom.Threshold = 1.35
	lastApplied = os.clock()
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(apply)
workspace:GetAttributeChangedSignal("Level2LightingOwnedByController"):Connect(apply)
player:GetAttributeChangedSignal("InRound"):Connect(apply)
player:GetAttributeChangedSignal("Escaped"):Connect(apply)
if state then
	state:GetAttributeChangedSignal("Level2_LightingMode"):Connect(apply)
end
RunService.Heartbeat:Connect(function()
	if active() and os.clock() - lastApplied > .75 then apply() end
end)

apply()
