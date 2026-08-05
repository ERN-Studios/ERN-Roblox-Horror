-- Level 3 Lighting Controller
-- Client-side grade for the Sunken Leisure Complex, mirroring the Level 2
-- controller's ownership pattern. Level 3 is deliberately BRIGHT: the
-- reference photos are sunlit liminal poolrooms — no fog, high ambient bounce,
-- warm natural daylight filling every room, turquoise water.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("Level 3 State", 30)

local grade = Lighting:FindFirstChild("Level 3 Client Color Grade") or Instance.new("ColorCorrectionEffect")
grade.Name = "Level 3 Client Color Grade"
grade.Parent = Lighting

local bloom = Lighting:FindFirstChild("Level 3 Client Bloom") or Instance.new("BloomEffect")
bloom.Name = "Level 3 Client Bloom"
bloom.Parent = Lighting

local lastApplied = 0

local function active()
	return workspace:GetAttribute("SelectedLevel") == 3
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and workspace:GetAttribute("Level3LightingOwnedByController") == true
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
	Lighting.Ambient = Color3.fromRGB(92, 88, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 101, 82)
	Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
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
	local mode = state and state:GetAttribute("Level3_LightingMode") or "NORMAL"
	-- Bright, airy, NO fog. High ambient is what makes the light feel like it
	-- bounces around the tiled rooms; the skylight SurfaceLights (Shadows on)
	-- paint the sun shafts on top of it.
	Lighting.ClockTime = 12
	Lighting.FogColor = Color3.fromRGB(235, 230, 208)
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 224)
	Lighting.ColorShift_Bottom = Color3.fromRGB(196, 206, 188)
	if mode == "EXIT_OPEN" then
		Lighting.Brightness = 2.6
		Lighting.Ambient = Color3.fromRGB(158, 160, 140)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 154, 136)
		grade.Brightness = .07
		grade.Contrast = .03
		grade.Saturation = .03
		grade.TintColor = Color3.fromRGB(238, 255, 240)
		bloom.Intensity = .3
	else
		Lighting.Brightness = 2.4
		Lighting.Ambient = Color3.fromRGB(150, 146, 126)
		Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 120)
		grade.Brightness = .05
		grade.Contrast = .03
		grade.Saturation = .02
		grade.TintColor = Color3.fromRGB(255, 248, 222)
		bloom.Intensity = .26
	end
	bloom.Size = 30
	bloom.Threshold = 1.05
	lastApplied = os.clock()
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(apply)
workspace:GetAttributeChangedSignal("Level3LightingOwnedByController"):Connect(apply)
player:GetAttributeChangedSignal("InRound"):Connect(apply)
player:GetAttributeChangedSignal("Escaped"):Connect(apply)
if state then
	state:GetAttributeChangedSignal("Level3_LightingMode"):Connect(apply)
end
RunService.Heartbeat:Connect(function()
	if active() and os.clock() - lastApplied > .75 then apply() end
end)

apply()
