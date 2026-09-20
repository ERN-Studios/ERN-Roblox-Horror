-- Server-only geometry for returning to a death location. A void/wall death
-- falls back to nearby solid ground, then the round's last known safe position.
local Players = game:GetService("Players")
local Placement = {}

local function standingHeight(root, humanoid)
	local leg = root.Parent:FindFirstChild("Left Leg")
	return root.Size.Y * .5 + humanoid.HipHeight
		+ (humanoid.RigType == Enum.HumanoidRigType.R6 and leg and leg.Size.Y or 0)
end

local function filters(character)
	local excluded = {character}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character ~= character then
			table.insert(excluded, player.Character)
		end
	end
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = excluded
	ray.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = excluded
	overlap.RespectCanCollide = true
	return ray, overlap
end

local function lethalPitFloor(position)
	local zones = workspace:FindFirstChild("PitZones")
	if not zones then return false end
	for _, zone in ipairs(zones:GetChildren()) do
		if zone.Name == "Zone" and zone:IsA("BasePart") then
			local offset = zone.CFrame:PointToObjectSpace(position)
			if math.abs(offset.X) <= zone.Size.X * .5 and math.abs(offset.Z) <= zone.Size.Z * .5
				and offset.Y < -4 then return true end
		end
	end
	return false
end

local function safeFrame(root, humanoid, frame, ray, overlap, isFree)
	if typeof(frame) ~= "CFrame" then return nil end
	local p = frame.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z
		or math.abs(p.X) > 1000000 or math.abs(p.Y) > 1000000 or math.abs(p.Z) > 1000000 then return nil end
	local height = standingHeight(root, humanoid)
	local floor = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -(height + 8), 0), ray)
	if not floor or floor.Normal.Y < .85 or not floor.Instance.Anchored
		or lethalPitFloor(floor.Position) then return nil end
	local y = floor.Position.Y + height + .12
	-- Keep the exact root height if it was already standing above the floor.
	if p.Y >= y and p.Y <= y + 1 then y = p.Y end
	local position = Vector3.new(p.X, y, p.Z)
	if isFree and not isFree(position) then return nil end
	-- Require support under the whole footprint, not just a pit's thin edge.
	for _, offset in ipairs({Vector3.new(-.9, 0, -.9), Vector3.new(.9, 0, -.9),
		Vector3.new(-.9, 0, .9), Vector3.new(.9, 0, .9)}) do
		local support = workspace:Raycast(floor.Position + offset + Vector3.new(0, .8, 0), Vector3.new(0, -1.6, 0), ray)
		if not support or support.Normal.Y < .85 or not support.Instance.Anchored then return nil end
	end
	local clearanceHeight = math.max(4.8, height + root.Size.Y * .5 + 1.5)
	local center = Vector3.new(position.X, floor.Position.Y + .2 + clearanceHeight * .5, position.Z)
	if #workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(2.8, clearanceHeight, 2.8), overlap) > 0 then return nil end
	local facing = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
	if facing.Magnitude < .01 then facing = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(position, position + facing.Unit)
end

function Placement.At(root, humanoid, frame, isFree)
	local ray, overlap = filters(root.Parent)
	return safeFrame(root, humanoid, frame, ray, overlap, isFree)
end

function Placement.Resolve(root, humanoid, deathFrame, lastSafeFrame, isFree)
	local ray, overlap = filters(root.Parent)
	if deathFrame then
		local exact = safeFrame(root, humanoid, deathFrame, ray, overlap, isFree)
		if exact then return exact end
		for _, radius in ipairs({4, 8, 12}) do
			for step = 0, 7 do
				local angle = step * math.pi / 4
				local frame = deathFrame + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local nearby = safeFrame(root, humanoid, frame, ray, overlap, isFree)
				if nearby then return nearby end
			end
		end
	end
	if deathFrame and lastSafeFrame and math.abs(deathFrame.Y - lastSafeFrame.Y) > 6 then
		local surface = deathFrame + Vector3.new(0, lastSafeFrame.Y - deathFrame.Y, 0)
		-- A falling death has no safe floor at its recorded depth. Search at the
		-- most recent walkable height before returning to that older position.
		return Placement.Resolve(root, humanoid, surface, lastSafeFrame, isFree)
	end
	return safeFrame(root, humanoid, lastSafeFrame, ray, overlap, isFree)
end

return table.freeze(Placement)
