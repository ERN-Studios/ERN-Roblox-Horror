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
local ELEVATOR_TIME = 19    -- seconds with doors shut before each round (matches the elevator sound length)
-- (no round timer — the round ends only when the puzzle is solved or all die)
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
		-- retract 3.6 (not the full 4) so the thicker doors don't clip the frame
		TweenService:Create(doorL, info, { CFrame = closedL * CFrame.new(0, 0, -3.6) }):Play()
		TweenService:Create(doorR, info, { CFrame = closedR * CFrame.new(0, 0, 3.6) }):Play()
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

		-- reset the entity to its corner, feet on the floor (whatever its size)
		if entity and entity.PrimaryPart and entityStart then
			local bbox, size = entity:GetBoundingBox()
			local pivot = entity:GetPivot()
			local bottomToPivot = pivot.Y - (bbox.Y - size.Y / 2)
			entity:PivotTo(CFrame.new(entityStart.CFrame.X, 0.5 + bottomToPivot, entityStart.CFrame.Z))
		end

		-- one life: track deaths
		for _, p in ipairs(participants) do
			local hum = p.Character:FindFirstChild("Humanoid")
			table.insert(conns, hum.Died:Connect(function()
				if alive[p] then
					alive[p] = nil
					aliveCount -= 1
					-- pass the kill POSITION so everyone hears a positional scream
					local ch = p.Character
					local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
					status:FireAllClients("death", p.Name, hrp and hrp.Position or nil)
				end
			end))
		end

		-- leaving the game counts as dying
		table.insert(conns, Players.PlayerRemoving:Connect(function(p)
			if alive[p] then
				alive[p] = nil
				aliveCount -= 1
				status:FireAllClients("death", p.Name, nil) -- left the game: no scream
			end
		end))

		-- doors shut: countdown while the maze loads/streams in
		for t = ELEVATOR_TIME, 1, -1 do
			status:FireAllClients("elevator", t)
			task.wait(1)
		end
		elevator.open()

		-- hand the round to PuzzleManager (spawns fuses/boxes/levers/exit)
		workspace:SetAttribute("PuzzleWon", false)
		workspace:SetAttribute("RoundActive", true)

		status:FireAllClients("start")

		-- the round ends ONLY when the puzzle is solved (win) or everyone is
		-- dead (lose) — there is no time limit
		local result
		while true do
			if workspace:GetAttribute("PuzzleWon") then result = "win" break end
			if aliveCount <= 0 then result = "lose" break end
			task.wait(0.5)
		end

		-- round over: tear down the puzzle and reset all shared state
		workspace:SetAttribute("RoundActive", false)
		workspace:SetAttribute("LightMode", "NORMAL")
		workspace:SetAttribute("FlickerBoost", 0)
		workspace:SetAttribute("EntitySpeedMul", 1)

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
