-- GameManager
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "GameManager"
-- Forces first person, builds the lobby room, and runs the round loop:
-- intermission → teleport party into the maze → one life each →
-- everyone dead = lose, timer runs out with survivors = win → back to lobby.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local status = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")

-- ── tuning ────────────────────────────────────────────────
local MIN_PLAYERS  = 1     -- raise to 2+ for real multiplayer rounds
local INTERMISSION = 15    -- seconds in lobby between rounds
local ROUND_TIME   = 300   -- survive this many seconds to win
-- ──────────────────────────────────────────────────────────

-- ── force first person ────────────────────────────────────
local function setupPlayer(p)
	p.CameraMode = Enum.CameraMode.LockFirstPerson
end
Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end

-- ── lobby room (floating high above the maze) ─────────────
local LOBBY_POS = Vector3.new(0, 300, 0)

local lobby = Instance.new("Model")
lobby.Name = "Lobby"

local function lpart(size, offset, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Position = LOBBY_POS + offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = lobby
	return p
end

local GREY  = Color3.fromRGB(60, 60, 64)
local DARK  = Color3.fromRGB(38, 38, 42)

lpart(Vector3.new(60, 2, 60), Vector3.new(0, -1, 0), DARK, Enum.Material.Concrete)   -- floor
lpart(Vector3.new(60, 2, 60), Vector3.new(0, 15, 0), DARK, Enum.Material.Concrete)   -- ceiling
lpart(Vector3.new(60, 14, 2), Vector3.new(0, 7, -29), GREY, Enum.Material.Concrete)  -- walls
lpart(Vector3.new(60, 14, 2), Vector3.new(0, 7, 29), GREY, Enum.Material.Concrete)
lpart(Vector3.new(2, 14, 60), Vector3.new(-29, 7, 0), GREY, Enum.Material.Concrete)
lpart(Vector3.new(2, 14, 60), Vector3.new(29, 7, 0), GREY, Enum.Material.Concrete)

local lampPart = lpart(Vector3.new(4, 0.4, 4), Vector3.new(0, 13.6, 0),
	Color3.fromRGB(255, 250, 230), Enum.Material.Neon)
local lamp = Instance.new("PointLight")
lamp.Brightness = 1.2
lamp.Range = 45
lamp.Color = Color3.fromRGB(255, 240, 210)
lamp.Parent = lampPart

lobby.Parent = workspace

-- the ONLY SpawnLocation in the game → everyone spawns/respawns in the lobby
local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "LobbySpawn"
spawnPad.Size = Vector3.new(12, 1, 12)
spawnPad.Position = LOBBY_POS + Vector3.new(0, 0.5, 0)
spawnPad.Anchored = true
spawnPad.Color = Color3.fromRGB(90, 90, 96)
spawnPad.Material = Enum.Material.Concrete
spawnPad.Neutral = true
spawnPad.Duration = 0
spawnPad.Parent = workspace

-- ── round loop ────────────────────────────────────────────
task.spawn(function()
	local mazeStart = workspace:WaitForChild("MazeStart", 60)
	local entityStart = workspace:WaitForChild("EntityStart", 60)
	local entity = workspace:WaitForChild("Entity", 60)

	if not mazeStart then
		warn("GameManager: MazeStart marker not found — is MazeGenerator running?")
		return
	end

	while true do
		-- wait for enough players
		if #Players:GetPlayers() < MIN_PLAYERS then
			status:FireAllClients("waiting")
			repeat task.wait(1) until #Players:GetPlayers() >= MIN_PLAYERS
		end

		-- intermission countdown
		for t = INTERMISSION, 1, -1 do
			status:FireAllClients("intermission", t)
			task.wait(1)
		end

		-- gather the party
		local participants = {}
		local alive = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local hum = char and char:FindFirstChild("Humanoid")
			if char and hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then
				table.insert(participants, p)
				alive[p] = true
			end
		end

		if #participants > 0 then
			local aliveCount = #participants
			local conns = {}

			-- reset the entity to its corner
			if entity and entity.PrimaryPart and entityStart then
				entity:PivotTo(entityStart.CFrame + Vector3.new(0, 5, 0))
			end

			-- teleport the party in, slightly spread out
			for i, p in ipairs(participants) do
				local offset = Vector3.new(
					((i - 1) % 4) * 5 - 7.5, 4,
					math.floor((i - 1) / 4) * 5)
				p.Character:PivotTo(mazeStart.CFrame + offset)

				-- one life: track deaths
				local hum = p.Character:FindFirstChild("Humanoid")
				table.insert(conns, hum.Died:Connect(function()
					if alive[p] then
						alive[p] = nil
						aliveCount -= 1
						status:FireAllClients("death", p.Name, aliveCount)
					end
				end))
			end

			-- leaving the game counts as dying
			table.insert(conns, Players.PlayerRemoving:Connect(function(p)
				if alive[p] then
					alive[p] = nil
					aliveCount -= 1
					status:FireAllClients("death", p.Name, aliveCount)
				end
			end))

			status:FireAllClients("start", ROUND_TIME)

			-- run the round
			local result = "win"
			local endTime = os.clock() + ROUND_TIME
			while os.clock() < endTime do
				if aliveCount <= 0 then
					result = "lose"
					break
				end
				status:FireAllClients("timer",
					math.ceil(endTime - os.clock()), aliveCount)
				task.wait(1)
			end
			if aliveCount <= 0 then result = "lose" end

			for _, c in ipairs(conns) do c:Disconnect() end
			status:FireAllClients(result)
			task.wait(5)

			-- everyone back to the lobby
			for _, p in ipairs(Players:GetPlayers()) do
				p:LoadCharacter()
			end
			task.wait(1)
		end
	end
end)
