-- EntityAI
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "EntityAI"
-- REQUIRES: a model named "Entity" in Workspace with a Humanoid, a HumanoidRootPart,
--           and PrimaryPart set. All parts CanCollide = false except the root.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RS = game:GetService("ReplicatedStorage")

local NoiseRegistry = require(script.Parent:WaitForChild("NoiseRegistry"))

local entity = workspace:WaitForChild("Entity")
local humanoid = entity:WaitForChild("Humanoid")
local root = entity:WaitForChild("HumanoidRootPart")

-- put the entity in its collision group so the invisible pit-zone barriers
-- (built by MazeGenerator) stop it — and only it
do
	local PhysicsService = game:GetService("PhysicsService")
	pcall(function() PhysicsService:RegisterCollisionGroup("Entity") end)
	for _, d in ipairs(entity:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = "Entity" end
	end
	entity.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CollisionGroup = "Entity" end
	end)
end

-- ── tuning ────────────────────────────────────────────────
local SIGHT_RANGE       = 650   -- effectively unlimited — only walls and the cone stop it
local SIGHT_RANGE_LIT   = 1100  -- when the player's flashlight is on
local SIGHT_ANGLE       = math.rad(80)  -- half-angle: 160° total — human-ish vision, minus a bit
local HEAR_RANGE        = 220
local SPEED_LURK        = 8
local SPEED_INVESTIGATE = 15
local SPEED_CHASE       = 21
local SEARCH_TIME       = 12
-- ──────────────────────────────────────────────────────────

local State = { LURK = "LURK", INVESTIGATE = "INVESTIGATE",
	CHASE = "CHASE", SEARCH = "SEARCH" }

local current = State.LURK
local lastKnownPos = nil
local searchUntil = 0
local moveToken = 0

-- noise intake
local lastReport = {}
RS:WaitForChild("Remotes"):WaitForChild("ReportNoise").OnServerEvent
	:Connect(function(player, stateName)
		local now = os.clock()
		if lastReport[player] and now - lastReport[player] < 0.15 then return end
		lastReport[player] = now

		if type(stateName) ~= "string" then return end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		NoiseRegistry.Add(hrp.Position, stateName)
	end)

Players.PlayerRemoving:Connect(function(p) lastReport[p] = nil end)

-- ── pit zone awareness ────────────────────────────────────
-- MazeGenerator drops invisible markers in workspace.PitZones; the entity
-- refuses to charge straight across a hole field and routes around instead
local pitZones = {}
task.spawn(function()
	local folder = workspace:WaitForChild("PitZones", 30)
	if not folder then return end
	local function add(p)
		table.insert(pitZones, {
			minX = p.Position.X - p.Size.X / 2, maxX = p.Position.X + p.Size.X / 2,
			minZ = p.Position.Z - p.Size.Z / 2, maxZ = p.Position.Z + p.Size.Z / 2,
		})
	end
	for _, p in ipairs(folder:GetChildren()) do add(p) end
	folder.ChildAdded:Connect(add)
end)

local function inPitZone(pos)
	for _, zn in ipairs(pitZones) do
		if pos.X > zn.minX and pos.X < zn.maxX
			and pos.Z > zn.minZ and pos.Z < zn.maxZ then
			return true
		end
	end
	return false
end

local function crossesPitZone(from, to)
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 1 then return false end
	dir = dir.Unit
	for d = 4, dist, 6 do
		if inPitZone(from + dir * d) then return true end
	end
	return false
end

-- ── perception ────────────────────────────────────────────
local function sightRangeFor(char)
	local flag = char:FindFirstChild("FlashlightOn")
	return (flag and flag.Value) and SIGHT_RANGE_LIT or SIGHT_RANGE
end

local function canSee(char, hrp)
	local dir = hrp.Position - root.Position
	local dist = dir.Magnitude
	if dist > sightRangeFor(char) then return false end
	if dist < 0.1 then return true end

	-- the vision cone only limits SPOTTING you. Once chasing, awareness is
	-- 360° — you can't juke it by circling behind; only walls break the chase
	if current ~= State.CHASE then
		local fwd = root.CFrame.LookVector
		if math.acos(math.clamp(fwd:Dot(dir.Unit), -1, 1)) > SIGHT_ANGLE then
			return false
		end
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { entity }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hit = workspace:Raycast(root.Position, dir, params)
	return hit ~= nil and hit.Instance:IsDescendantOf(char)
end

local function findVisiblePlayer()
	local bestChar, bestRoot, bestDist = nil, nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")
		if hrp and hum and hum.Health > 0 and canSee(char, hrp) then
			local d = (hrp.Position - root.Position).Magnitude
			if d < bestDist then
				bestChar, bestRoot, bestDist = char, hrp, d
			end
		end
	end
	return bestChar, bestRoot
end

-- ── movement ──────────────────────────────────────────────
local function pathTo(destination, token)
	local path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = 6,
		AgentCanJump = false,
		AgentCanClimb = false,
	})

	local ok = pcall(function()
		path:ComputeAsync(root.Position, destination)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end

	for _, wp in ipairs(path:GetWaypoints()) do
		if token ~= moveToken then return false end
		humanoid:MoveTo(wp.Position)
		local reached = humanoid.MoveToFinished:Wait()
		if not reached then return false end
	end
	return true
end

local function interrupt()
	moveToken += 1
end

-- ── main loop ─────────────────────────────────────────────
task.spawn(function()
	while task.wait(0.25) do
		if humanoid.Health <= 0 then break end
		NoiseRegistry.Prune()

		local char, hrp = findVisiblePlayer()

		if char then
			if current ~= State.CHASE then
				interrupt()
				current = State.CHASE
				humanoid.WalkSpeed = SPEED_CHASE
			end
			lastKnownPos = hrp.Position
			if crossesPitZone(root.Position, hrp.Position) then
				-- never sprint straight over the holes — go around
				pathTo(hrp.Position, moveToken)
			else
				humanoid:MoveTo(hrp.Position)
			end

		elseif current == State.CHASE then
			interrupt()
			current = State.SEARCH
			searchUntil = os.clock() + SEARCH_TIME
			humanoid.WalkSpeed = SPEED_INVESTIGATE

		elseif current == State.SEARCH then
			if os.clock() >= searchUntil then
				current = State.LURK
			elseif lastKnownPos then
				local token = moveToken
				pathTo(lastKnownPos + Vector3.new(
					math.random(-25, 25), 0, math.random(-25, 25)), token)
			end

		else
			local noise = NoiseRegistry.GetBest(root.Position, HEAR_RANGE)
			if noise then
				current = State.INVESTIGATE
				humanoid.WalkSpeed = SPEED_INVESTIGATE
				pathTo(noise.pos, moveToken)
			else
				current = State.LURK
				humanoid.WalkSpeed = SPEED_LURK
				pathTo(root.Position + Vector3.new(
					math.random(-70, 70), 0, math.random(-70, 70)), moveToken)
			end
		end
	end
end)
