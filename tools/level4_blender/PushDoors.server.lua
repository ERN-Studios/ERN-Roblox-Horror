-- Level 4 cinema (Blender build): push doors.
-- Every Model in this folder with a "Hinge" and a "Leaf" is one door. A door that has floor on both
-- sides (a room behind it) swings AWAY from whoever walks into it and eases shut once its swing area
-- is empty. A door with no floor behind it (the street doors) stays shut and does not move.
-- A split double door is two such Models (one Hinge + Leaf each); each half swings away from its pusher.
local Players = game:GetService("Players")

local doorsFolder = script.Parent
local model = doorsFolder.Parent
local collision = model:WaitForChild("Collision")
local PUSH_DEPTH = 3.2        -- studs in front of / behind the closed leaf that count as "walking into it"
local SIDE_MARGIN = 1.0       -- studs past the leaf's edges
local CLOSE_DELAY = 1.4
local doors = {}

local function hasFloor(at)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { collision }
	local hit = workspace:Raycast(at, Vector3.new(0, -14, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end

for _, door in doorsFolder:GetChildren() do
	local hingePart = door:IsA("Model") and door:FindFirstChild("Hinge")
	local leaf = door:IsA("Model") and door:FindFirstChild("Leaf")
	local hinge = hingePart and hingePart:FindFirstChildOfClass("HingeConstraint")
	if hinge and leaf then
		-- closed frame: X runs from the hinge along the leaf, Z is the leaf's normal
		local along = leaf.Position - hingePart.Position
		along = Vector3.new(along.X, 0, along.Z)
		local width = along.Magnitude * 2
		along = along.Unit
		local normal = Vector3.yAxis:Cross(along)            -- side the leaf tip moves to for a positive angle
		local closed = CFrame.fromMatrix(Vector3.new(hingePart.Position.X, leaf.Position.Y, hingePart.Position.Z),
			along, Vector3.yAxis, -normal)
		local centre = leaf.Position
		local roomBehind = hasFloor(centre + normal * 5 + Vector3.yAxis * 2)
			and hasFloor(centre - normal * 5 + Vector3.yAxis * 2)
		door:SetAttribute("PushDoor", roomBehind)
		if roomBehind then
			pcall(function() leaf:SetNetworkOwner(nil) end)
			table.insert(doors, { model = door, hinge = hinge, leaf = leaf, closed = closed, width = width,
				height = leaf.Size.Y, open = false, lastSeen = -math.huge,
				angle = door:GetAttribute("OpenAngle") or 95,
				fixed = door:GetAttribute("FixedOpenAngle"),
				nonBlocking = door:GetAttribute("NonBlockingWhenOpen") == true })
		else
			-- no room behind: weld the leaf shut
			hinge.Enabled = false
			leaf.Anchored = true
		end
	end
end

-- (side, near): side is which side of the closed leaf a character walking into it is on (nil when nobody
-- is); near is true while anyone stands inside the leaf's swing arc, which holds an open door open
local function pusher(d)
	local near = false
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			local p = d.closed:PointToObjectSpace(root.Position)
			if math.abs(p.Y) < d.height / 2 + 3 then
				if p.X > -SIDE_MARGIN and p.X < d.width + SIDE_MARGIN and math.abs(p.Z) < PUSH_DEPTH then
					return (if p.Z < 0 then 1 else -1), true   -- -Z is the positive-angle side
				end
				if p.X * p.X + p.Z * p.Z < (d.width + 2) ^ 2 then near = true end
			end
		end
	end
	return nil, near
end

local function swing(d, open, side)
	d.open = open
	if open and d.nonBlocking then d.leaf.CanCollide = false end
	-- Keep wider single leaves near the old half-leaf tip speed (studs/second).
	d.hinge.AngularSpeed = if open then math.min(3.2, 14 / d.width) else math.min(1.1, 7 / d.width)
	-- a player on the positive side pushes the leaf to the negative side, and vice versa
	d.hinge.TargetAngle = if open then (d.fixed or d.angle * -side) else 0
end

while model:IsDescendantOf(workspace) do
	local now = time()        -- game time; os.clock() is CPU time and runs ~4x slow on a Studio server
	for _, d in doors do
		local side, near = pusher(d)
		if side or (near and d.open) then
			d.lastSeen = now
			if side and not d.open then swing(d, true, side) end
		elseif d.open and now - d.lastSeen >= CLOSE_DELAY then
			swing(d, false)
		end
		if not d.open and d.nonBlocking and math.abs(d.hinge.CurrentAngle) < 2 then
			d.leaf.CanCollide = true
		end
	end
	task.wait(0.1)
end
