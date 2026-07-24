-- FlashlightController
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "FlashlightController"
-- F toggles the flashlight. State is reported to the server via ToggleFlashlight
-- (this version already includes the remote-event fix — no BoolValue on the client).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local player = Players.LocalPlayer

local light
local on = false

local function build(char)
	local head = char:WaitForChild("Head")

	light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Brightness = 3
	light.Range = 60
	light.Angle = 45
	light.Color = Color3.fromRGB(255, 244, 214)
	light.Shadows = true
	light.Enabled = false
	light.Face = Enum.NormalId.Front
	light.Parent = head

	on = false
	remote:FireServer(false)
end

local function toggle()
	if not light then return end
	on = not on
	light.Enabled = on
	remote:FireServer(on)
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then toggle() end
end)

if player.Character then build(player.Character) end
player.CharacterAdded:Connect(build)
