-- SpectateController  (v1)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "SpectateController"
--
-- When you die during a round, the camera follows a living teammate instead of
-- your corpse. Q / E cycle between survivors. Clears when you respawn (round end).

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "SpectateGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 1, -20)
label.Size = UDim2.new(0, 420, 0, 30)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.4
label.BorderSizePixel = 0
label.Font = Enum.Font.SpecialElite
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(220, 220, 220)
label.Visible = false
label.Text = ""
label.Parent = gui

local spectating = false
local targets = {}
local idx = 1

local function livingOthers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function watch(i)
	targets = livingOthers()
	if #targets == 0 then
		label.Text = "Spectating — no survivors left"
		return
	end
	idx = ((i - 1) % #targets) + 1
	local p = targets[idx]
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local cam = workspace.CurrentCamera
	if cam and hum then
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = hum
	end
	label.Text = "Spectating: " .. p.Name .. "   (Q / E to switch)"
end

local function startSpectate()
	if spectating or not workspace:GetAttribute("RoundActive") then return end
	spectating = true
	label.Visible = true
	watch(1)
end

local function stopSpectate()
	spectating = false
	label.Visible = false
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if cam and hum then cam.CameraSubject = hum end
end

local function onChar(char)
	stopSpectate() -- fresh body → normal view
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(startSpectate)
end

if player.Character then onChar(player.Character) end
player.CharacterAdded:Connect(onChar)

UIS.InputBegan:Connect(function(input, processed)
	if processed or not spectating then return end
	if input.KeyCode == Enum.KeyCode.E then
		watch(idx + 1)
	elseif input.KeyCode == Enum.KeyCode.Q then
		watch(idx - 1)
	end
end)

-- if the teammate you're watching dies or leaves, jump to another
task.spawn(function()
	while true do
		task.wait(1)
		if spectating then
			local t = targets[idx]
			local hum = t and t.Character and t.Character:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then watch(idx) end
		end
	end
end)
