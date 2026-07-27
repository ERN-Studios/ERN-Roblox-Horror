-- SpectateController  (v2 — full first-person POV of a teammate + their flashlight)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "SpectateController"
--
-- When you die during a round you FULLY take a living teammate's POV: locked
-- first person from their eyes (no free-look), and you see THEIR flashlight beam
-- (your own is off). Q / E cycle between survivors. Clears when you respawn.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
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
label.Font = Enum.Font.Gotham
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(220, 220, 220)
label.Visible = false
label.Text = ""
label.Parent = gui
local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 6); lc.Parent = label

local spectating = false
local targets = {}
local idx = 1
local spectated = nil -- the player whose POV we're in
local hidden = nil    -- character whose parts we've hidden locally

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

-- borrowed flashlight: mirrors the spectated player's beam from their viewpoint
-- (their FlashlightOn flag is a replicated BoolValue on their character)
local beamMount = Instance.new("Part")
beamMount.Name = "SpectateBeam"
beamMount.Size = Vector3.new(0.2, 0.2, 0.2)
beamMount.Anchored = true
beamMount.CanCollide = false
beamMount.CanQuery = false
beamMount.Transparency = 1
local core = Instance.new("SpotLight")
core.Brightness = 5; core.Range = 35; core.Angle = 32
core.Color = Color3.fromRGB(255, 244, 214); core.Shadows = true
core.Face = Enum.NormalId.Front; core.Enabled = false; core.Parent = beamMount
local spill = Instance.new("SpotLight")
spill.Brightness = 1; spill.Range = 45; spill.Angle = 75
spill.Color = Color3.fromRGB(255, 240, 205); spill.Shadows = false
spill.Face = Enum.NormalId.Front; spill.Enabled = false; spill.Parent = beamMount

local function unhide()
	if hidden then
		for _, d in ipairs(hidden:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
		hidden = nil
	end
end

local function watch(i)
	targets = livingOthers()
	if #targets == 0 then
		spectated = nil
		unhide()
		label.Text = "Spectating — no survivors left"
		return
	end
	idx = ((i - 1) % #targets) + 1
	if spectated ~= targets[idx] then unhide() end -- reveal the previous body
	spectated = targets[idx]
	label.Text = "POV: " .. spectated.Name .. "   (Q / E to switch)"
end

-- drive the POV camera + borrowed flashlight every frame while spectating
RunService.RenderStepped:Connect(function()
	if not (spectating and spectated) then return end
	local cam = workspace.CurrentCamera
	local char = spectated.Character
	local head = char and char:FindFirstChild("Head")
	if not (cam and head) then return end

	-- lock to their eyes + look direction (no free-look)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = head.CFrame

	-- hide their body locally so it doesn't fill the screen (true first person)
	if hidden ~= char then unhide(); hidden = char end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
	end

	-- mirror their flashlight from the shared viewpoint
	if beamMount.Parent ~= cam then beamMount.Parent = cam end
	beamMount.CFrame = cam.CFrame
	local fo = char:FindFirstChild("FlashlightOn")
	local on = fo ~= nil and fo.Value
	core.Enabled = on
	spill.Enabled = on
end)

local function startSpectate()
	if spectating or not workspace:GetAttribute("RoundActive") then return end
	spectating = true
	label.Visible = true
	watch(1)
end

local function stopSpectate()
	spectating = false
	spectated = nil
	label.Visible = false
	unhide()
	core.Enabled = false; spill.Enabled = false
	beamMount.Parent = nil
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		if hum then cam.CameraSubject = hum end
	end
end

local function onChar(char)
	stopSpectate() -- fresh body → back to your own view
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
			local hum = spectated and spectated.Character
				and spectated.Character:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then watch(idx) end
		end
	end
end)
