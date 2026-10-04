-- Level 6 Dev ESP (2026-10-04, owner request). In the Indoor Playground a developer sees the Counter (the doll)
-- every other player in the level and the party easter egg's button through walls: an always-on-top outline and a name with the distance.
-- It replaces the CD ESP this script drew for the retired generated Level 6 world.
--   WHO: DevAccess.IsLevel6PreviewAllowed (the developer list plus the owner's account). Local presentation only:
--   nothing here asks the server for anything, and nothing replicates.
--   ON/OFF: it follows the DEV terminal's ESP switch (`DevEspEnabled`, set in the lobby; on by default), and K
--   toggles it inside the level, where the terminal does not open.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
if not DevAccess.IsLevel6PreviewAllowed(player) then return end

local WORLD_NAME, DOLL_NAME = "Level 6 Indoor Playground", "Level 6 Counting Child"
local IN_LEVEL = "Level6PlaygroundPreview"
local ENTITY_COLOUR, PLAYER_COLOUR = Color3.fromRGB(255, 70, 70), Color3.fromRGB(70, 230, 255)
local BUTTON_COLOUR = Color3.fromRGB(255, 220, 60)      -- the party easter egg's button (`L6PartyButton`)
local on = player:GetAttribute("DevEspEnabled") ~= false
player:GetAttributeChangedSignal("DevEspEnabled"):Connect(function()
	on = player:GetAttribute("DevEspEnabled") ~= false
end)

local function inLevel(who)
	return who:GetAttribute(IN_LEVEL) == true and who:GetAttribute("Level5VoidRound") ~= true
end

local holder = Instance.new("Folder")
holder.Name = "Level6DevESP"
local marks = {}        -- subject (Model) -> {highlight, label, text}
local function mark(subject, colour)
	local found = marks[subject]
	if found then return found end
	local highlight = Instance.new("Highlight")
	highlight.Adornee = subject
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor, highlight.OutlineColor = colour, colour
	highlight.FillTransparency, highlight.OutlineTransparency = 0.72, 0
	highlight.Parent = holder
	local label = Instance.new("BillboardGui")
	label.AlwaysOnTop, label.Size, label.StudsOffsetWorldSpace = true, UDim2.fromOffset(190, 34), Vector3.new(0, 4.2, 0)
	label.LightInfluence, label.MaxDistance = 0, 2000
	local text = Instance.new("TextLabel")
	text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	text.Font, text.TextSize, text.TextColor3 = Enum.Font.GothamBold, 14, colour
	text.TextStrokeTransparency = 0.35
	text.Parent = label
	label.Parent = holder
	found = {highlight = highlight, label = label, text = text}
	marks[subject] = found
	return found
end
local function clear(subject)
	local found = marks[subject]
	if not found then return end
	found.highlight:Destroy()
	found.label:Destroy()
	marks[subject] = nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.K or not inLevel(player) then return end
	on = not on
end)

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.15 then return end
	elapsed = 0
	local active = on and inLevel(player)
	holder.Parent = active and workspace.CurrentCamera or nil
	local wanted = {}
	if active then
		local own = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = own and own.Position or workspace.CurrentCamera.CFrame.Position
		local function show(subject, name, colour)
			local part = subject:IsA("BasePart") and subject or subject:FindFirstChild("HumanoidRootPart") or subject.PrimaryPart
				or subject:FindFirstChildWhichIsA("BasePart", true)
			if not part then return end
			local found = mark(subject, colour)
			found.label.Adornee = part
			found.text.Text = string.format("%s  ·  %d studs", name, (part.Position - from).Magnitude)
			wanted[subject] = true
		end
		local world = workspace:FindFirstChild(WORLD_NAME)
		local doll = world and world:FindFirstChild(DOLL_NAME)
		if doll and doll:IsA("Model") then show(doll, "THE COUNTER", ENTITY_COLOUR) end
		local partyButton = world and world:FindFirstChild("L6PartyButton")
		if partyButton and partyButton:IsA("BasePart") then show(partyButton, "PARTY BUTTON", BUTTON_COLOUR) end
		for _, other in ipairs(Players:GetPlayers()) do
			local character = other.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if other ~= player and humanoid and humanoid.Health > 0 and inLevel(other) then
				show(character, other.DisplayName, PLAYER_COLOUR)
			end
		end
	end
	for subject in pairs(marks) do
		if not wanted[subject] or not subject.Parent then clear(subject) end
	end
end)
