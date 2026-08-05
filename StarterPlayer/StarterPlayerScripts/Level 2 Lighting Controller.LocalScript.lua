local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("Level 2 State")

local grade = Lighting:FindFirstChild("Level 2 Client Color Grade") or Instance.new("ColorCorrectionEffect")
grade.Name = "Level 2 Client Color Grade"
grade.Parent = Lighting

local bloom = Lighting:FindFirstChild("Level 2 Client Bloom") or Instance.new("BloomEffect")
bloom.Name = "Level 2 Client Bloom"
bloom.Parent = Lighting

local lastApplied = 0

local function active()
	return workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
		and workspace:GetAttribute("Level2LightingOwnedByController") == true
end

local function apply()
	if not active() then
		grade.Enabled = false
		bloom.Enabled = false
		return
	end
	grade.Enabled = true
	bloom.Enabled = true
	local mode = state:GetAttribute("Level2_LightingMode") or "NORMAL"
	Lighting.ClockTime = 10.7
	Lighting.FogColor = Color3.fromRGB(207, 205, 178)
	Lighting.FogStart = 95
	Lighting.FogEnd = mode == "EXIT_OPEN" and 650 or 520
	Lighting.EnvironmentDiffuseScale = .5
	Lighting.EnvironmentSpecularScale = .6
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.fromRGB(255, 247, 213)
	Lighting.ColorShift_Bottom = Color3.fromRGB(70, 85, 77)
	if mode == "EXIT_OPEN" then
		Lighting.Brightness = 1.85
		Lighting.Ambient = Color3.fromRGB(112, 112, 96)
		Lighting.OutdoorAmbient = Color3.fromRGB(88, 92, 82)
		grade.Brightness = .035
		grade.Contrast = .035
		grade.Saturation = -.05
		grade.TintColor = Color3.fromRGB(231, 255, 235)
		bloom.Intensity = .2
	else
		Lighting.Brightness = 1.62
		Lighting.Ambient = Color3.fromRGB(99, 99, 85)
		Lighting.OutdoorAmbient = Color3.fromRGB(78, 82, 74)
		grade.Brightness = .015
		grade.Contrast = .055
		grade.Saturation = -.08
		grade.TintColor = Color3.fromRGB(247, 239, 203)
		bloom.Intensity = .13
	end
	bloom.Size = 25
	bloom.Threshold = 1.15
	lastApplied = os.clock()
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(apply)
workspace:GetAttributeChangedSignal("Level2LightingOwnedByController"):Connect(apply)
player:GetAttributeChangedSignal("InRound"):Connect(apply)
state:GetAttributeChangedSignal("Level2_LightingMode"):Connect(apply)
RunService.Heartbeat:Connect(function()
	if active() and os.clock() - lastApplied > .75 then apply() end
end)

apply()
