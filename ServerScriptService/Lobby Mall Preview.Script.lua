-- Lobby Mall Preview (2026-10-12, owner request). MALL_PREVIEW_20261012.
--   The mall lobby (Workspace.LobbyMallPreview, built by tools/lobby_mall/import_mall.py) is not the lobby yet: it is
--   a preview for three accounts (DevAccess.IsMallPreviewAllowed). Standing in Workspace it cost every player about
--   2,000 parts, 45 lights and a hundred signs they could never reach, and every server 18 more queue stations.
--   So this script PARKS it in ServerStorage the moment a server starts, before anybody has joined: nothing of it is
--   sent to a client and none of its systems run. A round server has no use for it at all and deletes it.
--   THE WAY IN: a prompt six studs in front of the lobby's spawn (no further: the game's prompt plate is not drawn
--   more than MaxActivationDistance + 8 studs from the CAMERA, which rides 12 behind the body), `MallPreviewPrompt` (E). Everybody else's client switches the
--   prompt off (Shop Display Client), and the request is checked again here. It brings the mall out, has the
--   visitor's client stream the arrival hall while their body is held there, and lets them go on the mall's spawn point.
--   THE WAY BACK: `MallReturnPrompt` by the mall's dead entrance doors, or dying (the lobby respawns everybody in
--   the real lobby).
--   When nobody has been in or near the mall for PARK_AFTER seconds it is parked again. Parked or not, the model
--   is the same instance, so what other scripts keep in it (the leaderboard sheets, the shop crates) stays put;
--   GameManager's queue stations 201-224 are bound when it comes out and retired when it goes back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local ServerKind = require(script.Parent:WaitForChild("ServerKind"))

local PARK_AFTER, NEAR = 45, 60

local mall = workspace:FindFirstChild("LobbyMallPreview")
if not (mall and mall:IsA("Model")) then return end
mall.Parent = ServerStorage                 -- first, before anything that can wait
if ServerKind.IsRoundServer() then
	mall:Destroy()
	return
end
workspace:SetAttribute("MallPreview", "MALL_PREVIEW_20261012")

local anchors = mall:WaitForChild("Anchors")
local arrival = anchors:WaitForChild("Spawn")
local lastSeen, nextUse = os.clock(), {}

local function living(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or humanoid.Health <= 0 or player:GetAttribute("InRound") == true
		or player:GetAttribute("TunnelReachHeld") == true or player:GetAttribute("LobbyDJMode") == true then return nil end
	return character, root
end

local function host(name, cframe, parent)
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame, part.Transparency = name, Vector3.new(1, 1, 1), cframe, 1
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Parent = parent
	return part
end

local function prompt(part, name, action, object, run)
	local item = Instance.new("ProximityPrompt")
	item.Name, item.ActionText, item.ObjectText = name, action, object
	item.KeyboardKeyCode, item.HoldDuration = Enum.KeyCode.E, 0.35
	item.MaxActivationDistance, item.RequiresLineOfSight = 13, false
	item.Parent = part
	item.Triggered:Connect(function(player)
		if not DevAccess.IsMallPreviewAllowed(player) or (nextUse[player] or 0) > os.clock() then return end
		nextUse[player] = os.clock() + 2
		run(player)
	end)
end

local function carry(player, at, facing)
	local character, root = living(player)
	if not character then return end
	-- The floor at the other end has to be on the visitor's client before the body is let go there. A stream request
	-- with a time limit was not enough when the mall had only just come out of storage: in play on 2026-10-12 the
	-- visitor arrived before it and fell out of the world. So the body is HELD at the destination while its
	-- surroundings arrive, and let go after.
	root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	root.Anchored = true
	character:PivotTo(CFrame.lookAt(at, at + facing))
	pcall(function() player:RequestStreamAroundAsync(at, 15) end)
	task.wait(0.4)
	if root.Parent then
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		root.Anchored = false
	end
end

local function visit(player)
	if not living(player) then return end
	lastSeen = os.clock()
	if mall.Parent ~= workspace then mall.Parent = workspace end
	carry(player, arrival.Position + Vector3.new(0, 3.2, 0), Vector3.zAxis)          -- looking down the concourse
end

local function leave(player)
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	if not (spawn and spawn:IsA("BasePart") and living(player)) then return end
	carry(player, spawn.Position + Vector3.new(0, 3.2, 0), spawn.CFrame.LookVector * Vector3.new(1, 0, 1))
end

prompt(host("MallReturn", CFrame.new(arrival.Position + Vector3.new(0, 3.5, -24)), anchors),
	"MallReturnPrompt", "BACK TO THE LOBBY", "MALL PREVIEW", leave)

-- In front of the spawn pad of the lobby players really stand in. GameManager builds the first lobby, then moves
-- its pad into the revised lobby, and a Studio Level 3 round parks the whole thing: the prompt FOLLOWS the pad (a
-- part's CFrame raises no changed signal, and the readiness attribute can be a stale `true` saved in the place: on
-- 2026-10-12 the prompt was left 343 studs away at the pad's first position).
local door
local function followSpawn()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	if not (spawn and spawn:IsA("BasePart")) then return end
	local at = spawn.CFrame * CFrame.new(3.5, 3, -6)
	if not door then
		door = host("MallPreviewDoor", at, workspace)
		prompt(door, "MallPreviewPrompt", "SEE THE NEW LOBBY", "MALL PREVIEW (DEV)", visit)
	elseif door.CFrame ~= at then
		door.CFrame = at
	end
end
task.spawn(function()
	for _ = 1, 240 do          -- closely while the server starts, then with the parking pass below
		followSpawn()
		task.wait(0.5)
	end
end)

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)

while true do
	task.wait(5)
	followSpawn()
	if mall.Parent == workspace then
		local low, high = mall:GetAttribute("BoundsMin"), mall:GetAttribute("BoundsMax")
		local someone = typeof(low) ~= "Vector3" or typeof(high) ~= "Vector3" or workspace:GetAttribute("MallPreviewStay") == true
		if not someone then
			for _, player in ipairs(Players:GetPlayers()) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local at = root and root.Position
				if at and at.X > low.X - NEAR and at.X < high.X + NEAR and at.Z > low.Z - NEAR and at.Z < high.Z + NEAR
					and at.Y > low.Y - NEAR and at.Y < high.Y + NEAR then
					someone = true
					break
				end
			end
		end
		if someone then
			lastSeen = os.clock()
		elseif os.clock() - lastSeen > PARK_AFTER then
			mall.Parent = ServerStorage
		end
	end
end
