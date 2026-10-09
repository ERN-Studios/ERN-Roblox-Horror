-- Level 4 cinema (Blender build): touch doors.
-- Every Model in this folder with a "Hinge" and a "Leaf" is one door. A door that has floor on both sides
-- (a room behind it) swings AWAY from whoever touches it (owner, 2026-10-02): a light touch opens it a little,
-- walking on keeps pushing it open, a hit at speed throws it wide and fast, and it eases shut on its own once
-- nobody touches it or stands in its swing. A door with no floor behind it (the street doors) stays welded shut.
-- A split double door is two such Models (one Hinge + Leaf each); each half swings away from its pusher.
-- Angles: a positive HingeConstraint angle turns the leaf counter-clockwise seen from above, which moves its tip
-- towards Y x (tip - hinge); so a pusher on that side drives the angle down and vice versa.
local Players = game:GetService("Players")

local doorsFolder = script.Parent
local model = doorsFolder.Parent
local collision = model:WaitForChild("Collision")

local TICK = 0.05             -- seconds between contact checks
local REACH = 0.45            -- studs the contact box reaches past the leaf collider on every side
local TOUCH_EXTENT = 32       -- degrees a standing touch opens the door
local SPEED_EXTENT = 3.6      -- extra degrees per stud/s the pusher moves into the leaf
local PUSH_STEP = 14          -- degrees a door keeps opening per check while someone keeps pushing it
local HIT_MAX = 105           -- widest a hard hit may throw it (the hinge limit is 110)
local CLOSE_DELAY = 1.1       -- seconds without contact (and an empty swing) before it closes
local ACTIVE_RANGE = 30       -- only doors this close to a character are checked
local doors = {}

local function hasFloor(at)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { collision }
	local hit = workspace:Raycast(at, Vector3.new(0, -14, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

for _, door in doorsFolder:GetChildren() do
	local hingePart = door:IsA("Model") and door:FindFirstChild("Hinge")
	local leaf = door:IsA("Model") and door:FindFirstChild("Leaf")
	local hinge = hingePart and hingePart:FindFirstChildOfClass("HingeConstraint")
	if hinge and leaf then
		local along = flat(leaf.Position - hingePart.Position)
		local width = along.Magnitude * 2
		along = along.Unit
		local normal = Vector3.yAxis:Cross(along)
		local centre = leaf.Position
		local roomBehind = hasFloor(centre + normal * 5 + Vector3.yAxis * 2)
			and hasFloor(centre - normal * 5 + Vector3.yAxis * 2)
		door:SetAttribute("PushDoor", roomBehind)
		if roomBehind then
			pcall(function() leaf:SetNetworkOwner(nil) end)
			table.insert(doors, {
				model = door, hinge = hinge, hingePart = hingePart, leaf = leaf,
				along0 = along, normal0 = normal, width = width, height = leaf.Size.Y,
				maxAngle = math.max(door:GetAttribute("OpenAngle") or 95, 60),
				fixed = door:GetAttribute("FixedOpenAngle"),
				nonBlocking = door:GetAttribute("NonBlockingWhenOpen") == true,
				lastTouch = -math.huge, target = 0,
			})
		else
			hinge.Enabled = false
			leaf.Anchored = true
		end
	end
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

-- live characters: { {character, root} }
local function characters()
	local list, models = {}, {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root then
			table.insert(list, { character, root })
			table.insert(models, character)
		end
	end
	return list, models
end

-- true while a character stands inside the sector the leaf sweeps between closed and its current angle
local function inSwing(d, roots)
	local hingePos = d.hingePart.Position
	local cur = d.hinge.CurrentAngle
	local lo, hi = math.min(0, cur) - 12, math.max(0, cur) + 12
	for _, root in roots do
		local r = flat(root.Position - hingePos)
		if r.Magnitude < d.width + 1.6 and math.abs(root.Position.Y - d.leaf.Position.Y) < d.height / 2 + 3 then
			local phi = math.deg(math.atan2(r:Dot(d.normal0), r:Dot(d.along0)))
			if phi >= lo and phi <= hi then return true end
		end
	end
	return false
end

local function drive(d, target, speed)
	d.target = target
	d.hinge.AngularSpeed = speed
	d.hinge.TargetAngle = target
	if d.nonBlocking and target ~= 0 then d.leaf.CanCollide = false end
end

while model:IsDescendantOf(workspace) do
	local now = time()        -- game time; os.clock() is CPU time and runs ~4x slow on a Studio server
	local chars, models = characters()
	overlap.FilterDescendantsInstances = models
	local roots = {}
	for _, c in chars do table.insert(roots, c[2]) end
	for _, d in doors do
		local near = false
		for _, root in roots do
			if (root.Position - d.leaf.Position).Magnitude < ACTIVE_RANGE then near = true; break end
		end
		if near then
			-- contact: any character part inside the leaf's box grown by REACH
			local touching = workspace:GetPartBoundsInBox(d.leaf.CFrame, d.leaf.Size + Vector3.one * (2 * REACH), overlap)
			local pusherRoot
			for _, part in touching do
				for _, c in chars do
					if part:IsDescendantOf(c[1]) then pusherRoot = c[2]; break end
				end
				if pusherRoot then break end
			end
			if pusherRoot then
				d.lastTouch = now
				local tip = flat(d.leaf.Position - d.hingePart.Position).Unit
				local n = Vector3.yAxis:Cross(tip)                     -- the way the tip moves as the angle grows
				local side = if flat(pusherRoot.Position - d.leaf.Position):Dot(n) >= 0 then 1 else -1
				local dir = -side                                       -- away from the pusher
				local into = math.max(0, -side * flat(pusherRoot.AssemblyLinearVelocity):Dot(n))
				local cur = d.hinge.CurrentAngle
				local extent
				if d.fixed then
					extent = math.abs(d.fixed)
				else
					extent = math.min(HIT_MAX, math.max(TOUCH_EXTENT + SPEED_EXTENT * into,
						if cur * dir > 0 then math.abs(cur) + PUSH_STEP else 0))
					if into < 10 then extent = math.min(extent, d.maxAngle) end   -- only a real hit goes past the stop
				end
				local target = dir * extent
				-- never pull an open door back towards the person pushing it further open
				if d.target * dir > 0 and math.abs(d.target) > extent then target = d.target end
				local tipSpeed = math.clamp(6 + 0.9 * into, 6, 26)    -- studs/s at the leaf's tip
				drive(d, target, math.clamp(tipSpeed / (d.width * 0.5) , 0.8, 7))
			elseif d.target ~= 0 and now - d.lastTouch >= CLOSE_DELAY and not inSwing(d, roots) then
				drive(d, 0, math.min(1.3, 8 / d.width))
			end
		elseif d.target ~= 0 and now - d.lastTouch >= CLOSE_DELAY then
			drive(d, 0, math.min(1.3, 8 / d.width))
		end
		if d.target == 0 and d.nonBlocking and math.abs(d.hinge.CurrentAngle) < 2 then
			d.leaf.CanCollide = true
		end
	end
	task.wait(TICK)
end

