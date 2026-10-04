-- Lobby DJ (2026-10-04, owner request). The DJ console on the lobby stage is a working booth for the team.
--   WHO: DevAccess.IsLevel6PreviewAllowed (the developer allowlist plus the owner's own account). Everyone else
--   sees and hears the result, nothing more; every request is checked again here.
--   WHAT: five instrumental tracks (ElevenLabs, assets/lobby-dj-20261004). The server only publishes WHICH track
--   is on and when it started (workspace attributes LobbyDJTrack / LobbyDJStartedAt / LobbyDJBy, and the list as
--   LobbyDJTracks); each client plays it itself, in step, and honours its own lobby-music setting.
--   DJ MODE: the caller is stood behind the console and gets a headset (a few welded parts on the Head). The
--   server only marks the player (`LobbyDJMode`, replicated); every client poses that character itself (Lobby DJ
--   Client: each frame it turns the limb joints' Transform a little further, after the Animate script).
-- This script took over the retired, disabled `Level4RenovationBoot`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))

local TRACKS = {
	{Title = "Neon Transit", Genre = "SYNTHWAVE", Id = 100118588472977},
	{Title = "Midnight Mall", Genre = "SYNTHWAVE", Id = 91861536067818},
	{Title = "VHS Sunrise", Genre = "SYNTHWAVE", Id = 121661472960006},
	{Title = "Level Up 96", Genre = "EURODANCE", Id = 127095326589213},
	{Title = "Hands Up Arcade", Genre = "EURODANCE", Id = 129281139879903},
}
local PROMPT_NAME = "LobbyDJPrompt"
local REACH = 26

local remote = ReplicatedStorage:FindFirstChild("LobbyDJ")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "LobbyDJ"
	remote.Parent = ReplicatedStorage
end
workspace:SetAttribute("LobbyDJTracks", HttpService:JSONEncode(TRACKS))
workspace:SetAttribute("LobbyDJTrack", 0)

local function allowed(player)
	local ok, result = pcall(DevAccess.IsLevel6PreviewAllowed, player)
	return ok and result == true and workspace:GetAttribute("ReservedRoundServer") ~= true
end

local function console()
	local lobby = workspace:FindFirstChild("LobbyReimaginedPreview")
	local visuals = lobby and lobby:FindFirstChild("BlenderVisuals", true)
	local found = visuals and visuals:FindFirstChild("DJConsole")
	if found and not found:IsA("BasePart") then found = found:FindFirstChildWhichIsA("BasePart", true) end
	return found, lobby
end

-- where the DJ stands: behind the console, on the side away from the lobby's middle, facing the room
local function booth()
	local desk, lobby = console()
	if not desk then return nil end
	local away = (desk.Position - lobby:GetPivot().Position) * Vector3.new(1, 0, 1)
	away = away.Magnitude > 1 and away.Unit or Vector3.zAxis
	local feet = desk.Position + away * 2.9 - Vector3.new(0, desk.Size.Y / 2, 0)
	return desk, feet, -away
end

local function nearBooth(player)
	local desk = console()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return desk ~= nil and root ~= nil and (root.Position - desk.Position).Magnitude <= REACH
end

local function ensurePrompt()
	local desk = console()
	if not desk or desk:FindFirstChild(PROMPT_NAME) then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText, prompt.ObjectText = "OPEN", "DJ BOOTH"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 11, false
	prompt.Parent = desk
	prompt.Triggered:Connect(function(player)
		if allowed(player) then remote:FireClient(player, "open") end
	end)
end

-- DJ mode ------------------------------------------------------------------------------------------------
local djs = {}       -- player -> {character, joints = {motor -> original C0}, headset, speed, jump, phase}

local function headset(character)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return nil end
	local model = Instance.new("Model")
	model.Name = "DJHeadset"
	local half = math.min(head.Size.X, 1.3) / 2 + 0.06
	local function piece(name, size, offset, colour, material, shape)
		local part = Instance.new("Part")
		part.Name, part.Size, part.Color, part.Material = name, size, colour, material
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless, part.CastShadow = false, false, false, true, false
		if shape then part.Shape = shape end
		part.CFrame = head.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head, part
		weld.Parent = part
		part.Parent = model
	end
	local black, glow = Color3.fromRGB(16, 16, 20), Color3.fromRGB(70, 230, 255)
	piece("Band", Vector3.new(half * 2 + 0.1, 0.12, 0.3), CFrame.new(0, half + 0.08, 0), black, Enum.Material.SmoothPlastic)
	for _, side in ipairs({-1, 1}) do
		piece("Arm", Vector3.new(0.1, half + 0.1, 0.26), CFrame.new(side * (half + 0.02), (half + 0.1) / 2 - 0.02, 0), black, Enum.Material.SmoothPlastic)
		piece("Cup", Vector3.new(0.24, 0.62, 0.62), CFrame.new(side * (half + 0.1), -0.02, 0), black, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		piece("Ring", Vector3.new(0.06, 0.3, 0.3), CFrame.new(side * (half + 0.24), -0.02, 0), glow, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
	model.Parent = character
	return model
end

local function stopDJ(player)
	local state = djs[player]
	if not state then return end
	djs[player] = nil
	if state.headset then state.headset:Destroy() end
	local humanoid = state.character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.WalkSpeed, humanoid.JumpPower = state.speed, state.jump end
	if player.Parent == Players then player:SetAttribute("LobbyDJMode", nil) end
end

local function startDJ(player)
	if djs[player] then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local desk, feet, facing = booth()
	if not root or not desk or humanoid.Health <= 0 or player:GetAttribute("InRound") == true then return end
	for other in pairs(djs) do stopDJ(other) end                       -- one DJ at the decks
	local state = {character = character, speed = humanoid.WalkSpeed, jump = humanoid.JumpPower}
	state.headset = headset(character)
	humanoid.WalkSpeed, humanoid.JumpPower = 0, 0
	root.AssemblyLinearVelocity = Vector3.zero
	local stand = feet + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	character:PivotTo(CFrame.lookAt(stand, stand + facing))
	djs[player] = state
	player:SetAttribute("LobbyDJMode", true)
	humanoid.Died:Once(function() stopDJ(player) end)
end

RunService.Heartbeat:Connect(function()
	for player, state in pairs(djs) do
		if player.Parent ~= Players or player.Character ~= state.character or not state.character.Parent
			or player:GetAttribute("InRound") == true then
			stopDJ(player)
		end
	end
end)

local nextUse = {}
remote.OnServerEvent:Connect(function(player, action, value)
	if not allowed(player) or (nextUse[player] or 0) > os.clock() then return end
	nextUse[player] = os.clock() + 0.25
	if action == "play" then
		if type(value) ~= "number" or value % 1 ~= 0 or not TRACKS[value] or TRACKS[value].Id == 0 then return end
		workspace:SetAttribute("LobbyDJBy", player.DisplayName)
		workspace:SetAttribute("LobbyDJStartedAt", workspace:GetServerTimeNow())
		workspace:SetAttribute("LobbyDJTrack", value)
	elseif action == "stop" then
		workspace:SetAttribute("LobbyDJTrack", 0)
	elseif action == "dj" then
		if value == true and nearBooth(player) then startDJ(player) else stopDJ(player) end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	stopDJ(player)
	nextUse[player] = nil
end)

task.spawn(function()
	while true do
		ensurePrompt()
		task.wait(2)
	end
end)
