local Players = game:GetService("Players")
local doorsFolder = script.Parent
local model = doorsFolder.Parent
local doors = {}
for _, zone in doorsFolder:GetChildren() do
	if zone:IsA("BasePart") and zone:GetAttribute("AutoDoorZone") then
		local hinges = {}
		for _, ref in zone:GetChildren() do
			if ref:IsA("ObjectValue") and ref.Name == "DoorHinge"
				and ref.Value and ref.Value:IsA("HingeConstraint") then
				local hinge = ref.Value
				table.insert(hinges, hinge)
				local leaf = hinge.Attachment1 and hinge.Attachment1.Parent
				if leaf and leaf:IsA("BasePart") then
					pcall(function() leaf:SetNetworkOwner(nil) end)
				end
			end
		end
		assert(#hinges > 0, "Auto door has no hinge: " .. zone:GetFullName())
		table.insert(doors, { zone = zone, hinges = hinges, open = false,
			side = 1, lastSeen = -math.huge })
	end
end
local function occupant(zone)
	local half = zone.Size * 0.5
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root then
				local p = zone.CFrame:PointToObjectSpace(root.Position)
				if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y
					and math.abs(p.Z) <= half.Z then
					return true, (if p.Z < 0 then 1 else -1)
				end
			end
		end
	end
	return false, nil
end
local function setOpen(door, open, approachSide)
	if door.open == open then return end
	door.open = open
	if open then door.side = approachSide or 1 end
	for _, hinge in door.hinges do
		if hinge.Parent then
			local leaf = hinge.Attachment1 and hinge.Attachment1.Parent
			if open and hinge:GetAttribute("NonBlockingWhenOpen") and leaf then
				leaf.CanCollide = false
			end
			hinge.AngularSpeed = if open then 3 else 0.65
			hinge.TargetAngle = if open then
				(hinge:GetAttribute("FixedOpenAngle")
					or (hinge:GetAttribute("OpenAngle") or 95) * door.side) else 0
		end
	end
end
while model:IsDescendantOf(workspace) do
	local now = os.clock()
	for _, door in doors do
		local present, side = occupant(door.zone)
		if present then
			door.lastSeen = now
			setOpen(door, true, side)
		elseif door.open and now - door.lastSeen >= 1.4 then
			setOpen(door, false)
		end
		if not door.open then
			for _, hinge in door.hinges do
				if hinge:GetAttribute("NonBlockingWhenOpen")
					and math.abs(hinge.CurrentAngle) < 2 then
					local leaf = hinge.Attachment1 and hinge.Attachment1.Parent
					if leaf then leaf.CanCollide = true end
				end
			end
		end
	end
	task.wait(0.1)
end
