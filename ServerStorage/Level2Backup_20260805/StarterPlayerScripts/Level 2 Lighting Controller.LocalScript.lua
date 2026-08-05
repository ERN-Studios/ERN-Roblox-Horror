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
	Lighting.FogColor = Color3.fromRGB(218, 219, 207)
	Lighting.FogStart = 180
	Lighting.FogEnd = mode == "EXIT_OPEN" and 900 or 780
	Lighting.EnvironmentDiffuseScale = .64
	Lighting.EnvironmentSpecularScale = .64
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.fromRGB(255, 252, 239)
	Lighting.ColorShift_Bottom = Color3.fromRGB(103, 115, 108)
	if mode == "EXIT_OPEN" then
		Lighting.Brightness = 2.15
		Lighting.Ambient = Color3.fromRGB(132, 132, 120)
		Lighting.OutdoorAmbient = Color3.fromRGB(116, 122, 114)
		grade.Brightness = .03
		grade.Contrast = .018
		grade.Saturation = -.025
		grade.TintColor = Color3.fromRGB(241, 255, 245)
		bloom.Intensity = .11
	else
		Lighting.Brightness = 1.95
		Lighting.Ambient = Color3.fromRGB(118, 118, 108)
		Lighting.OutdoorAmbient = Color3.fromRGB(102, 108, 102)
		grade.Brightness = .018
		grade.Contrast = .025
		grade.Saturation = -.035
		grade.TintColor = Color3.fromRGB(255, 252, 239)
		bloom.Intensity = .08
	end
	bloom.Size = 24
	bloom.Threshold = 1.35
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
