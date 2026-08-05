-- Level 3 Lighting Controller
-- Client-side grade for the Sunken Leisure Complex, mirroring the Level 2
-- controller's ownership pattern. Aims for the reference-photo mood: warm
-- cream haze, soft daylight-through-tiles, no visible sky, turquoise water.

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
		and workspace:GetAttribute("Level3LightingOwnedByController") == true
end

local function apply()
	if not active() then
		grade.Enabled = false
		bloom.Enabled = false
		return
	end
	grade.Enabled = true
	bloom.Enabled = true
	local mode = state and state:GetAttribute("Level3_LightingMode") or "NORMAL"
	Lighting.ClockTime = 12
	Lighting.FogColor = Color3.fromRGB(222, 216, 190)
	Lighting.FogStart = 110
	Lighting.FogEnd = mode == "EXIT_OPEN" and 720 or 560
	Lighting.EnvironmentDiffuseScale = .5
	Lighting.EnvironmentSpecularScale = .6
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.fromRGB(255, 248, 216)
	Lighting.ColorShift_Bottom = Color3.fromRGB(76, 88, 80)
	if mode == "EXIT_OPEN" then
		Lighting.Brightness = 1.9
		Lighting.Ambient = Color3.fromRGB(116, 116, 98)
		Lighting.OutdoorAmbient = Color3.fromRGB(90, 94, 84)
		grade.Brightness = .04
		grade.Contrast = .04
		grade.Saturation = -.04
		grade.TintColor = Color3.fromRGB(232, 255, 236)
		bloom.Intensity = .22
	else
		Lighting.Brightness = 1.7
		Lighting.Ambient = Color3.fromRGB(104, 102, 88)
		Lighting.OutdoorAmbient = Color3.fromRGB(82, 84, 76)
		grade.Brightness = .02
		grade.Contrast = .05
		grade.Saturation = -.06
		grade.TintColor = Color3.fromRGB(250, 242, 210)
		bloom.Intensity = .16
	end
	bloom.Size = 26
	bloom.Threshold = 1.12
	lastApplied = os.clock()
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(apply)
workspace:GetAttributeChangedSignal("Level3LightingOwnedByController"):Connect(apply)
player:GetAttributeChangedSignal("InRound"):Connect(apply)
if state then
	state:GetAttributeChangedSignal("Level3_LightingMode"):Connect(apply)
end
RunService.Heartbeat:Connect(function()
	if active() and os.clock() - lastApplied > .75 then apply() end
end)

apply()
