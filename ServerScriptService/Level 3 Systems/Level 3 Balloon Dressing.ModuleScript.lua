--!strict
-- Seeded, round-owned additions using the existing Blender BalloonCluster.
-- Every balloon remains visual only. The full cardinal door cross, CD/table
-- interactions and existing service-furniture envelopes stay clear.
local Dressing = {}

local CLEAR_HALF = 7
local WALL_INSET = 1.1
local MAX_CLUSTERS = 160
local CLUSTER_WIDTH = 2.21
local CLUSTER_DEPTH = 1.22
local CLUSTER_HEIGHT = 7.95
local CLUSTER_CHUNKS = 5
local CLUSTER_TRIANGLES = 684
local DENSITIES = {"Sparse", "Medium", "Dense"}

-- A local generator keeps decoration independent of gameplay's random stream.
-- All intermediate integers fit exactly in a double.
local function randomFor(seed: number, label: string)
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	for i = 1, #label do state = (state * 31 + string.byte(label, i)) % 2147483647 end
	if state == 0 then state = 1 end
	return function(minimum: number?, maximum: number?): number
		state = (state * 16807) % 2147483647
		local fraction = (state - 1) / 2147483646
		return if minimum and maximum then minimum + (maximum - minimum) * fraction else fraction
	end
end

local function integer(random, minimum: number, maximum: number): number
	return math.min(maximum, math.floor(random(minimum, maximum + 1)))
end

local function overlaps(a, b, padding: number?): boolean
	return math.abs(a.x - b.x) < a.hx + b.hx + (padding or 0)
		and math.abs(a.z - b.z) < a.hz + b.hz + (padding or 0)
end

local function safe(rect, room, blocked): boolean
	if math.abs(rect.x) + rect.hx > room.W * .5 - WALL_INSET
		or math.abs(rect.z) + rect.hz > room.D * .5 - WALL_INSET then return false end
	if math.abs(rect.x) - rect.hx < CLEAR_HALF
		or math.abs(rect.z) - rect.hz < CLEAR_HALF then return false end
	for _, obstacle in ipairs(blocked) do
		if overlaps(rect, obstacle, .45) then return false end
	end
	return true
end

-- This number-only planner is also used by offline clearance verification.
function Dressing.Plan(room, seed: number, density: string, obstacles)
	assert(type(room.W) == "number" and type(room.D) == "number", "Room dimensions required")
	local random = randomFor(seed, tostring(room.Id) .. ":balloons:" .. density)
	local target = if density == "Dense" then integer(random, 7, 9)
		elseif density == "Medium" then integer(random, 3, 4) else integer(random, 1, 2)
	local remaining = target
	local placements = {}
	local bundles = {}
	local blocked = table.clone(obstacles or {})
	local height = tonumber(room.H) or 12
	local groupGoal = if density == "Dense" then integer(random, 3, 4)
		elseif density == "Medium" then 2 else 1
	for groupIndex = 1, groupGoal do
		local members = math.ceil(remaining / (groupGoal - groupIndex + 1))
		local floating = random() < .30
		-- Floaters lose only the weight chunk after cloning. Their strings end
		-- above player head height; tethered bundles retain the authored weight.
		local floatScaleMax = math.min(.69, (height - 7.15 - .5) / (CLUSTER_HEIGHT*1.04))
		if floatScaleMax < .4 then floating = false end
		local scale = if floating then random(.4, math.max(.4, floatScaleMax)) else random(.87, 1.08)
		local yaw = random(-math.pi, math.pi)
		local spacing = 1.55 * scale
		local offsets = if members == 1 then {{x=0,z=0}}
			elseif members == 2 then {{x=-spacing*.5,z=0},{x=spacing*.5,z=.28*scale}}
			else {{x=-spacing*.55,z=-spacing*.3},{x=spacing*.55,z=-spacing*.3},{x=0,z=spacing*.55}}
		local planned = nil
		for _ = 1, 64 do
			local sx = if random() < .5 then -1 else 1
			local sz = if random() < .5 then -1 else 1
			local maxX, maxZ = room.W*.5-4.5, room.D*.5-4.5
			if maxX < 12 or maxZ < 12 then break end
			local alongX = random() < .5
			local centerX = sx * (if alongX then random(math.max(12,maxX-2),maxX) else random(12,maxX))
			local centerZ = sz * (if alongX then random(12,maxZ) else random(math.max(12,maxZ-2),maxZ))
			local memberPlans = {}
			local bundleRects = {}
			local fits = true
			for memberIndex, offset in ipairs(offsets) do
				local memberYaw = yaw + random(-.3,.3)
				local memberScale = scale * random(.96,1.04)
				local x = centerX + offset.x*math.cos(yaw) - offset.z*math.sin(yaw)
				local z = centerZ + offset.x*math.sin(yaw) + offset.z*math.cos(yaw)
				local hx = (math.abs(math.cos(memberYaw))*CLUSTER_WIDTH + math.abs(math.sin(memberYaw))*CLUSTER_DEPTH)*memberScale*.5
				local hz = (math.abs(math.sin(memberYaw))*CLUSTER_WIDTH + math.abs(math.cos(memberYaw))*CLUSTER_DEPTH)*memberScale*.5
				local rect = {x=x,z=z,hx=hx+.15,hz=hz+.15}
				if not safe(rect, room, blocked) then fits = false break end
				table.insert(bundleRects, rect)
				table.insert(memberPlans, {x=x,z=z,
					y=if floating then height-CLUSTER_HEIGHT*memberScale-.5 else 0,
					Yaw=memberYaw,Scale=memberScale,Floating=floating,
					Bundle=groupIndex,Member=memberIndex,Footprint=rect})
			end
			if fits then planned = {Members=memberPlans,Rects=bundleRects} break end
		end
		if planned then
			table.insert(bundles, {Index=groupIndex,Clusters=#planned.Members,Floating=floating})
			for _, placement in ipairs(planned.Members) do table.insert(placements, placement) end
			for _, rect in ipairs(planned.Rects) do table.insert(blocked, rect) end
			remaining -= #planned.Members
		end
	end
	return {Density=density,TargetClusters=target,Placements=placements,Bundles=bundles,
		SkippedClusters=target-#placements}
end

function Dressing.AssignDensities(rooms, seed: number)
	local order = {}
	for _, room in ipairs(rooms) do
		if room.Id ~= "Arrival" and room.Role ~= "Arrival" and room.Kind ~= "Exit" and room.Role ~= "Exit" then
			table.insert(order, room)
		end
	end
	local random = randomFor(seed, "level6-balloon-density")
	for i = #order, 2, -1 do
		local other = integer(random, 1, i)
		order[i], order[other] = order[other], order[i]
	end
	local assignment = {}
	for index, room in ipairs(order) do assignment[room.Id] = DENSITIES[(index-1)%3+1] end
	return assignment
end

local function footprint(object: BasePart, base: Vector3, padding: number?)
	local cf, size = object.CFrame, object.Size
	return {x=object.Position.X-base.X,z=object.Position.Z-base.Z,
		hx=(math.abs(cf.RightVector.X)*size.X+math.abs(cf.UpVector.X)*size.Y+math.abs(cf.LookVector.X)*size.Z)*.5+(padding or 0),
		hz=(math.abs(cf.RightVector.Z)*size.X+math.abs(cf.UpVector.Z)*size.Y+math.abs(cf.LookVector.Z)*size.Z)*.5+(padding or 0)}
end

local function tagged(object: Instance, suffix: string): boolean
	return object:GetAttribute("Level3_"..suffix) == true
end

local function collectBlocked(objects, room, base: Vector3)
	local blocked = {}
	for _, object in ipairs(objects) do
		if not object:IsA("BasePart") then continue end
		local relativeY = object.Position.Y - base.Y
		local padding = nil
		if tagged(object,"HideTableAnchor") then padding = 4.5
		elseif tagged(object,"CDTableSocket") or tagged(object,"TableCollision") then padding = 3.5
		elseif tagged(object,"ManagerFurnitureNavExclusion") then padding = .25
		elseif object.CanCollide and object.Size.Y > 1 and relativeY < 8 and relativeY + object.Size.Y*.5 > 0 then padding = .55
		end
		if padding then
			local rect = footprint(object, base, padding)
			if math.abs(rect.x)-rect.hx < room.W*.5 and math.abs(rect.z)-rect.hz < room.D*.5 then
				table.insert(blocked, rect)
			end
		end
		if object:GetAttribute("Level3_KitAsset") == "BalloonCluster" then
			-- The original dressing uses an invisible .05-stud carrier. Read its
			-- actual authored chunk extents, not the carrier's tiny footprint.
			local scale = object:GetAttribute("Level3_KitScale") or Vector3.one
			local rect = {x=object.Position.X-base.X,z=object.Position.Z-base.Z,
				hx=1.35*math.max(scale.X,scale.Z),hz=1.35*math.max(scale.X,scale.Z)}
			if math.abs(rect.x) < room.W*.5 and math.abs(rect.z) < room.D*.5 then table.insert(blocked,rect) end
		end
	end
	return blocked
end

function Dressing.ApplyBalloons(manifest, helper)
	assert(manifest.World and manifest.World:GetAttribute("Level3BuildOwned") == true, "Level 3 owned world required")
	assert(type(helper.Place) == "function" and typeof(helper.WorldOrigin) == "Vector3", "Blender placement helper required")
	assert(not manifest.World:FindFirstChild("Level 3 Varied Balloon Dressing"), "Balloon additions already applied")
	local size = helper.AssetSize("BalloonCluster")
	assert(math.abs(size.X-CLUSTER_WIDTH)<.01 and math.abs(size.Y-CLUSTER_HEIGHT)<.01
		and math.abs(size.Z-CLUSTER_DEPTH)<.01, "Blender balloon dimensions changed; revalidate placement")
	local layout, world = manifest.Layout, manifest.World
	local seed = tonumber(layout.ResolvedSeed) or 1
	local assignment = Dressing.AssignDensities(layout.Rooms, seed)
	local owner = Instance.new("Folder")
	owner.Name = "Level 3 Varied Balloon Dressing"
	owner:SetAttribute("Level3_BalloonDressingOwned", true)
	owner:SetAttribute("Level3_ResolvedSeed", seed)
	owner.Parent = world
	local objects = world:GetDescendants()
	local report = {Version="seeded-blender-balloons-1",Seed=seed,Rooms=0,
		Clusters=0,Balloons=0,Bundles=0,GroundedClusters=0,CeilingClusters=0,
		MeshParts=0,Triangles=0,SkippedClusters=0,
		MaxClusters=MAX_CLUSTERS,MaxMeshParts=MAX_CLUSTERS*CLUSTER_CHUNKS,
		DensityRooms={Sparse=0,Medium=0,Dense=0},RoomPlans={},CenterCrossWidth=CLEAR_HALF*2}
	for roomIndex, room in ipairs(layout.Rooms) do
		local density = assignment[room.Id]
		local roomModel = manifest.Rooms[room.Id]
		if not density or not roomModel then continue end
		local base = helper.WorldOrigin + Vector3.new(room.X,0,room.Z)
		local blocked = collectBlocked(objects, room, base)
		local plan = Dressing.Plan(room, seed, density, blocked)
		local group = Instance.new("Folder")
		group.Name = tostring(room.Id).." | "..density.." Balloons"
		group:SetAttribute("Level3_RoomId",room.Id)
		group:SetAttribute("Level3_BalloonDensity",density)
		group.Parent = owner
		local roomRecord = {RoomId=room.Id,Density=density,TargetClusters=plan.TargetClusters,
			Clusters=0,Bundles=#plan.Bundles,GroundedClusters=0,CeilingClusters=0,
			SkippedClusters=plan.SkippedClusters,BlockedEnvelopes=#blocked,Positions={}}
		report.Rooms += 1
		report.DensityRooms[density] += 1
		report.Bundles += #plan.Bundles
		for _, placement in ipairs(plan.Placements) do
			if report.Clusters >= MAX_CLUSTERS then roomRecord.SkippedClusters += 1 continue end
			local cf = CFrame.new(base + Vector3.new(placement.x,placement.y,placement.z))
				* CFrame.Angles(0,placement.Yaw,0)
			local cluster = helper.Place("BalloonCluster",cf,group,{Scale=placement.Scale,Collidable=false})
			cluster.Name = string.format("Blender %s Balloon Bundle %02d-%02d",density,placement.Bundle,placement.Member)
			cluster:SetAttribute("Level3_AddedBalloonCluster",true)
			cluster:SetAttribute("Level3_RoomId",room.Id)
			cluster:SetAttribute("Level3_BalloonDensity",density)
			cluster:SetAttribute("Level3_BalloonBundle",placement.Bundle)
			cluster:SetAttribute("Level3_CeilingBalloons",placement.Floating)
			for _, part in ipairs(cluster:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide=false part.CanTouch=false part.CanQuery=false part.CastShadow=false
					if placement.Floating and part.Name:match("__red_plastic$") then
						part.Transparency=1
						part:SetAttribute("Level3_CeilingBalloonWeightSuppressed",true)
					end
				end
			end
			report.Clusters += 1
			report.Balloons += 3
			report.MeshParts += CLUSTER_CHUNKS
			report.Triangles += CLUSTER_TRIANGLES
			roomRecord.Clusters += 1
			local typeKey = if placement.Floating then "CeilingClusters" else "GroundedClusters"
			report[typeKey] += 1 roomRecord[typeKey] += 1
			table.insert(roomRecord.Positions,{placement.x,placement.y,placement.z,placement.Scale,placement.Bundle})
		end
		report.SkippedClusters += roomRecord.SkippedClusters
		group:SetAttribute("Level3_BalloonClusterCount",roomRecord.Clusters)
		table.insert(report.RoomPlans,roomRecord)
		if roomIndex%4 == 0 then task.wait() end
	end
	world:SetAttribute("Level3_AddedBalloonClusterCount",report.Clusters)
	world:SetAttribute("Level3_AddedBalloonCount",report.Balloons)
	world:SetAttribute("Level3_AddedBalloonBundleCount",report.Bundles)
	world:SetAttribute("Level3_BalloonSparseRoomCount",report.DensityRooms.Sparse)
	world:SetAttribute("Level3_BalloonMediumRoomCount",report.DensityRooms.Medium)
	world:SetAttribute("Level3_BalloonDenseRoomCount",report.DensityRooms.Dense)
	world:SetAttribute("Level3_BalloonDecorationSeed",seed)
	return {Owner=owner,Report=report}
end

return Dressing
