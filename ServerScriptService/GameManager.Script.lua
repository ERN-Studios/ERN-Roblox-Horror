-- GameManager  (v3 — elevator-only, no lobby)
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "GameManager"
-- REPLACES the old GameManager entirely — paste over the old contents.
--
-- You spawn INSIDE the elevator. Doors shut → countdown → doors open → round.
-- One life: dead players stay dead (free camera) until the round ends, then
-- everyone respawns in the elevator for the next round.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local status = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")

-- ── tuning ────────────────────────────────────────────────
local MIN_PLAYERS   = 1     -- raise to 2+ for real multiplayer rounds
local ELEVATOR_TIME = 12    -- seconds with doors shut before each round
local ROUND_TIME    = 300   -- survive this many seconds to win
-- ──────────────────────────────────────────────────────────

Players.CharacterAutoLoads = false -- we control every (re)spawn

local spawnReady = false
local inRound = {} -- participants locked out of respawning until round end

-- first person while alive, free camera while dead; jumping disabled
local function onCharacter(p, char)
	p.CameraMode = Enum.CameraMode.LockFirstPerson
	local hum = char:WaitForChild("Humanoid")
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.Died:Connect(function()
		p.CameraMode = Enum.CameraMode.Classic
		if not inRound[p] then
			-- died outside a round (e.g. reset button) → just respawn
			task.delay(3, function()
				if p.Parent then p:LoadCharacter() end
			end)
		end
	end)
end

local function setupPlayer(p)
	p.CharacterAdded:Connect(function(char) onCharacter(p, char) end)
	task.spawn(function()
		repeat task.wait(0.2) until spawnReady
		if p.Parent and not p.Character then p:LoadCharacter() end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end

-- ── elevator doors (the elevator itself is built by MazeGenerator) ──
local function connectElevator()
	local model = workspace:WaitForChild("Elevator", 60)
	if not model then return nil end
	local doorL = model:WaitForChild("DoorL")
	local doorR = model:WaitForChild("DoorR")

	local closedL, closedR = doorL.CFrame, doorR.CFrame
	local info = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

	local api = {}
	function api.open()
		TweenService:Create(doorL, info, { CFrame = closedL * CFrame.new(0, 0, -4) }):Play()
		TweenService:Create(doorR, info, { CFrame = closedR * CFrame.new(0, 0, 4) }):Play()
	end
	function api.close()
		TweenService:Create(doorL, info, { CFrame = closedL }):Play()
		TweenService:Create(doorR, info, { CFrame = closedR }):Play()
	end
	return api
end

-- ── round loop ────────────────────────────────────────────
task.spawn(function()
	local mazeStart = workspace:WaitForChild("MazeStart", 60)
	local entityStart = workspace:WaitForChild("EntityStart", 60)
	local entity = workspace:WaitForChild("Entity", 60)

	if not mazeStart then
		warn("GameManager: MazeStart marker not found — is MazeGenerator running?")
		return
	end

	local elevator = connectElevator()
	if not elevator then
		warn("GameManager: Elevator model not found — is MazeGenerator v4 pasted in?")
		return
	end
	spawnReady = true -- players may now (re)spawn — inside the closed cabin

	while true do
		-- wait for enough players
		if #Players:GetPlayers() < MIN_PLAYERS then
			status:FireAllClients("waiting")
			repeat task.wait(1) until #Players:GetPlayers() >= MIN_PLAYERS
		end

		-- gather the party (everyone alive is standing in the elevator)
		local participants = {}
		local alive = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local hum = char and char:FindFirstChild("Humanoid")
			if char and hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then
				table.insert(participants, p)
				alive[p] = true
				inRound[p] = true
			end
		end

		if #participants == 0 then
			task.wait(1)
			continue
		end

		local aliveCount = #participants
		local conns = {}

		-- reset the entity to its corner
		if entity and entity.PrimaryPart and entityStart then
			entity:PivotTo(entityStart.CFrame + Vector3.new(0, 5, 0))
		end

		-- one life: track deaths
		for _, p in ipairs(participants) do
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

		-- doors shut: countdown while the maze loads/streams in
		for t = ELEVATOR_TIME, 1, -1 do
			status:FireAllClients("elevator", t)
			task.wait(1)
		end
		elevator.open()

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

		-- everyone (including the dead) respawns in the elevator, doors shut
		inRound = {}
		for _, p in ipairs(Players:GetPlayers()) do
			p:LoadCharacter()
		end
		task.wait(0.5)
		elevator.close()
		task.wait(1.6) -- let the doors finish closing before the next countdown
	end
end)
