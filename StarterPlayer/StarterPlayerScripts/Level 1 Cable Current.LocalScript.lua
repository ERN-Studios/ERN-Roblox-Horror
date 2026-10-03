-- Level 1 Cable Current
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → LocalScript named
--             "Level 1 Cable Current"
--
-- A visible electrical current running along the circuit cables PuzzleManager
-- lays between each fuse box and its paired lever. Purely a picture of state
-- the server already owns; it reads nothing the player could not see and
-- changes nothing about the puzzle.
--
--   • before its box is powered, the current runs TOWARD the fuse box, so the
--     cable answers "where do I take this fuse?" from anywhere in the maze.
--   • the instant that box is powered the server sets Powered on the circuit
--     and the current REVERSES: out of the box, back past the elevator, and on
--     to the lever — the route the objectives column has just asked for in
--     words ("FOLLOW THE CURRENT TO A LEVER").
--
-- ONE Heartbeat and one small Neon bead per pulse — at most twelve parts on a
-- six-player round — rather than a tween or a colour write per cable segment.
-- A full maze lays several hundred ObjectiveCable parts per circuit, and a
-- per-segment animation is several hundred property writes a frame for a visual
-- a moving point renders exactly.
--
-- ACCESSIBILITY: ReduceFlashing. There is no blink here at any setting — a bead
-- travelling at a constant speed never turns anything on and off — but the
-- setting still halves the speed and drops to a single pulse per circuit, so
-- the effect reads as a slow glide rather than a train of lights crossing the
-- edge of vision.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ── tuning ────────────────────────────────────────────────
local SPEED = 26              -- studs/second a pulse travels
local PULSES = 2              -- pulses in flight per circuit
local REDUCED_SPEED = 13      -- ReduceFlashing: a glide, not a procession
local REDUCED_PULSES = 1
local BEAD_SIZE = 0.55        -- the cable itself is 0.34 x 0.09
local RESCAN_INTERVAL = 0.4   -- at most one rebuild this often while building
-- ──────────────────────────────────────────────────────────

local function active()
	local level = workspace:GetAttribute("SelectedLevel")
	return (level == 1 or level == nil)
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("InRound") == true
end

local holder            -- client-only Folder; never replicates, never swept
local watchedFolder     -- the PuzzleItems folder the cached circuits came from
local folderConnection
local circuits = {}     -- ordered list of per-circuit state
local dirty = true
local nextScan = 0

-- Both ends of one cable part in world space. A riser runs along its own Y and
-- says so with the Vertical attribute; everything else runs along its Z, and
-- its CFrame was built looking at the end the route leaves by. Inferring the
-- axis from Size instead would misread the shortest bevel joiners, which are
-- the same handful of studs long as the shortest risers.
local function endpoints(part)
	local half, axis
	if part:GetAttribute("Vertical") then
		half, axis = part.Size.Y * 0.5, part.CFrame.UpVector
	else
		half, axis = part.Size.Z * 0.5, part.CFrame.LookVector
	end
	local offset = axis * half
	return part.Position - offset, part.Position + offset
end

-- The ordered points of one half of a circuit. Parts arrive in SegmentIndex
-- order, which PuzzleManager emits in the order the route is travelled; each
-- part then contributes the endpoint FURTHER from where the walk stands, so a
-- riser the route descends is still travelled downward.
local function polyline(parts)
	local points, cursor = {}, nil
	for _, part in ipairs(parts) do
		local a, b = endpoints(part)
		if cursor then
			if (b - cursor).Magnitude < (a - cursor).Magnitude then a, b = b, a end
		else
			points[1] = a
		end
		points[#points + 1] = b
		cursor = b
	end
	return points
end

-- Points plus the cumulative distance to each of them, which is what lets a
-- pulse travel at a constant speed over segments that differ by two orders of
-- magnitude in length (a 0.3-stud bevel joiner and a 24-stud corridor run).
local function measured(points)
	local dist = {}
	dist[1] = 0
	for i = 2, #points do
		dist[i] = dist[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return { points = points, dist = dist, length = dist[#points] or 0 }
end

local function buildCircuit(circuit)
	local split = tonumber(circuit:GetAttribute("BoxBranchEnd")) or 0
	local boxParts, leverParts = {}, {}
	for _, child in ipairs(circuit:GetChildren()) do
		local index = child.Name == "ObjectiveCable"
			and tonumber(child:GetAttribute("SegmentIndex"))
		if index then
			table.insert(index <= split and boxParts or leverParts, child)
		end
	end
	if #boxParts == 0 then return nil end
	local function bySegment(a, b)
		return (a:GetAttribute("SegmentIndex") or 0) < (b:GetAttribute("SegmentIndex") or 0)
	end
	table.sort(boxParts, bySegment)
	table.sort(leverParts, bySegment)

	-- Unpowered: the elevator witness point out to the fuse box.
	local boxPoints = polyline(boxParts)
	-- Powered: the same half walked backwards — out of the box, past the
	-- elevator — and then straight on down the lever half. Both halves were laid
	-- from the one witness point, so the reversed box half ends where the lever
	-- half begins and the two join without a seam.
	local leverPoints = polyline(leverParts)
	local poweredPoints = {}
	for i = #boxPoints, 1, -1 do poweredPoints[#poweredPoints + 1] = boxPoints[i] end
	for i = 2, #leverPoints do poweredPoints[#poweredPoints + 1] = leverPoints[i] end

	return {
		model = circuit,
		toBox = measured(boxPoints),
		toLever = measured(poweredPoints),
		colour = circuit:GetAttribute("CircuitColor") or Color3.new(1, 1, 1),
		powered = nil, -- unknown: the first pass places the beads
		travelled = 0, -- per circuit: one box being powered must not restart five
		beads = {},
	}
end

local function clear()
	if folderConnection then folderConnection:Disconnect() end
	folderConnection = nil
	watchedFolder = nil
	if holder then holder:Destroy() end
	holder = nil
	table.clear(circuits)
	dirty = true
end

local function rescan()
	local folder = workspace:FindFirstChild("PuzzleItems")
	if folder ~= watchedFolder then
		if folderConnection then folderConnection:Disconnect() end
		watchedFolder = folder
		-- Cable parts stream in over the whole build. Each arrival only marks the
		-- cache stale; the rebuild itself is rate limited, so a several-hundred
		-- part circuit costs a handful of sorts, not one per part.
		folderConnection = folder and folder.DescendantAdded:Connect(function()
			dirty = true
		end)
	end
	if holder then holder:Destroy() end
	holder = nil
	table.clear(circuits)
	if not folder then return end

	local camera = workspace.CurrentCamera
	if not camera then return end
	holder = Instance.new("Folder")
	holder.Name = "Level1CableCurrent"
	holder.Parent = camera

	local pulses = (player:GetAttribute("ReduceFlashing") == true)
		and REDUCED_PULSES or PULSES
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name:sub(1, 12) == "CircuitCable" then
			local state = buildCircuit(child)
			if state then
				for index = 1, pulses do
					local bead = Instance.new("Part")
					bead.Name = "CableCurrentPulse"
					bead.Shape = Enum.PartType.Ball
					bead.Size = Vector3.new(BEAD_SIZE, BEAD_SIZE, BEAD_SIZE)
					bead.Anchored = true
					bead.CanCollide = false
					bead.CanQuery = false
					bead.CanTouch = false
					bead.CastShadow = false
					bead.Material = Enum.Material.Neon
					bead.Color = state.colour
					bead.Parent = holder
					-- Evenly spaced round the route, so the cable reads as a
					-- continuous flow rather than one lonely dot.
					table.insert(state.beads, { part = bead, offset = (index - 1) / pulses, i = 1 })
				end
				table.insert(circuits, state)
			end
		end
	end
end

-- Where a pulse sits, `travelled` studs along `path`. The walk carries its own
-- index forward instead of searching the whole polyline every frame; it only
-- restarts when the pulse wraps or the path underneath it changes.
local function pointAt(path, travelled, bead)
	local dist, points = path.dist, path.points
	local last = #points
	if last < 2 then return points[1] end
	local i = bead.i
	if i >= last or i < 1 or dist[i] > travelled then i = 1 end
	while i < last - 1 and dist[i + 1] <= travelled do i += 1 end
	bead.i = i
	local span = dist[i + 1] - dist[i]
	local t = span > 1e-4 and math.clamp((travelled - dist[i]) / span, 0, 1) or 0
	local a, b = points[i], points[i + 1]
	return a + (b - a) * t
end

RunService.Heartbeat:Connect(function(dt)
	if not active() then
		if holder or watchedFolder then clear() end
		return
	end
	local now = os.clock()
	if (dirty or not holder) and now >= nextScan then
		nextScan = now + RESCAN_INTERVAL
		dirty = false
		rescan()
	end
	if #circuits == 0 then return end

	local reduce = player:GetAttribute("ReduceFlashing") == true
	local step = dt * (reduce and REDUCED_SPEED or SPEED)
	for _, state in ipairs(circuits) do
		local powered = state.model:GetAttribute("Powered") == true
		if powered ~= state.powered then
			state.powered = powered
			-- Restart THIS circuit's run so the reversal reads as one: the current
			-- leaves the box that was just powered, rather than continuing from
			-- wherever its old pulse happened to be. The other circuits are not
			-- touched — one player's box is not everyone's.
			state.travelled = 0
			for _, bead in ipairs(state.beads) do bead.i = 1 end
		else
			state.travelled += step
		end
		local path = powered and state.toLever or state.toBox
		if path.length > 1 then
			for _, bead in ipairs(state.beads) do
				local s = (state.travelled + bead.offset * path.length) % path.length
				bead.part.Position = pointAt(path, s, bead)
			end
		end
	end
end)

player:GetAttributeChangedSignal("ReduceFlashing"):Connect(function()
	-- The pulse COUNT is fixed when the beads are made, so the setting takes a
	-- rebuild rather than a branch in the loop. It changes about once a career.
	dirty = true
	nextScan = 0
end)

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true then clear() end
end)
