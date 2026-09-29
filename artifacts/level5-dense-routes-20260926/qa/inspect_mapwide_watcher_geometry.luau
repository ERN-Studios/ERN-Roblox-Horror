-- Read-only geometric inspection. No actors, players, cameras, attributes or
-- animation tracks are moved/created. Candidate viewpoints are mathematical
-- probes, NOT claimed gameplay or actual participant visibility evidence.
local Inspect={}
local function xyz(v) return {v.X,v.Y,v.Z} end
function Inspect.Run(world)
	world=world or workspace:FindFirstChild("Level 5 Generated World")
	assert(world and world:IsDescendantOf(workspace),"Inspect the actual built world in Workspace")
	local anchors=assert(world:FindFirstChild("WindowWatcherAnchors"),"Map-wide anchors missing")
	local architecture=assert(world:FindFirstChild("Level5_IndoorSuburbs"),"Architecture missing")
	local excluded={anchors}
	local actorFolder=world:FindFirstChild("Level5WindowWatcherEncounters")
	if actorFolder then table.insert(excluded,actorFolder) end
	for _,player in ipairs(game:GetService("Players"):GetPlayers()) do
		if player.Character then table.insert(excluded,player.Character) end
	end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=excluded
	local report={kind="native read-only structural probes",anchors={},districts={},failures={},rayCount=0,
		limitations={"Probe positions are not player movement or a connected-route test",
			"Head/HRP look is a broad direction proxy, not actual camera frustum",
			"Known clip depth bound does not prove all native skinned vertices clear every furnishing"}}
	local function ray(origin,direction,filter)
		report.rayCount+=1
		return workspace:Raycast(origin,direction,filter or params)
	end
	local function issue(record,message)
		table.insert(record.failures,message);table.insert(report.failures,record.name..": "..message)
	end
	local ordered=anchors:GetChildren();table.sort(ordered,function(a,b) return a.Name<b.Name end)
	for _,anchor in ipairs(ordered) do
		local record={name=anchor.Name,district=anchor:GetAttribute("District"),failures={},viewpoints={}}
		table.insert(report.anchors,record)
		local reference=anchor:FindFirstChild("WindowGlass")
		local pane=reference and reference:IsA("ObjectValue") and reference.Value
		local floor=anchor:GetAttribute("FloorCFrame")
		local depth=anchor:GetAttribute("PawnDepth")
		if not anchor:IsA("BasePart") or anchor:GetAttribute("Level5WindowWatcherAnchor")~=true
			or not pane or not pane:IsA("BasePart") or not pane:IsDescendantOf(architecture)
			or typeof(floor)~="CFrame" or type(depth)~="number" then issue(record,"invalid pane/floor/depth");continue end
		local relative=pane.CFrame:ToObjectSpace(floor)
		if (relative.Position-Vector3.new(0,-6.55,0)).Magnitude>.02
			or relative.LookVector:Dot(Vector3.new(0,0,-1))<.9999 or floor.UpVector.Y<.9999 then
			issue(record,"floor does not match agreed pane-local frame")
		end
		record.pane=pane:GetFullName();record.paneSize=xyz(pane.Size)
		record.pawnDepth=depth;record.minimumTapPaneClearance=depth-1.745002-pane.Size.Z*.5
		if pane.Size.X<6 or pane.Size.Y<7.19 or pane.Material~=Enum.Material.Glass or not pane.CanQuery then
			issue(record,"nonstandard queryable house pane")
		end
		if record.minimumTapPaneClearance<.04 then issue(record,"tap depth intersects or nearly touches thick pane") end
		local pose=(floor*CFrame.new(1.1,0,depth))
		record.actorFloor=xyz(pose.Position)
		local support=ray(pose.Position+Vector3.new(0,.5,0),Vector3.new(0,-1.25,0))
		record.support=support and support.Instance:GetFullName() or "NONE"
		record.supportError=support and math.abs(support.Position.Y-pose.Position.Y) or -1
		if not support or not support.Instance.CanCollide or record.supportError>.15 then issue(record,"actor floor unsupported") end
		local target=pose:PointToWorldSpace(Vector3.new(0,7.45,-.37))
		record.estimatedFace=xyz(target)
		local insideParams=RaycastParams.new();insideParams.FilterType=Enum.RaycastFilterType.Exclude
		local innerExcluded=table.clone(excluded);table.insert(innerExcluded,pane)
		insideParams.FilterDescendantsInstances=innerExcluded
		-- Up to 25 front-side stations; retain the first three supported clear
		-- sightlines. Vertical rays sample actual floors rather than assuming
		-- that any point in the map envelope is a walkable surface.
		for _,distance in ipairs({12,22,36,60,96}) do
			for _,x in ipairs({1.1,-6,6,-12,12}) do
				if #record.viewpoints>=3 then break end
				local approximate=floor:PointToWorldSpace(Vector3.new(x,4,-distance))
				-- Upper panes may legitimately be watched from a lower courtyard.
				-- This still requires actual support and an unobstructed pane ray.
				local foot=ray(approximate,Vector3.new(0,-128,0))
				if not foot or not foot.Instance.CanCollide or foot.Normal.Y<.75 then continue end
				local clear=true
				for _,offset in ipairs({Vector3.new(0,0,0),Vector3.new(1.2,0,0),Vector3.new(-1.2,0,0)}) do
					if ray(foot.Position+offset+Vector3.new(0,.1,0),Vector3.new(0,5.8,0)) then clear=false;break end
				end
				if not clear then continue end
				local eye=foot.Position+Vector3.new(0,5,0)
				local delta=target-eye
				if delta.Magnitude<3 or delta.Magnitude>145 or pane.CFrame:PointToObjectSpace(eye).Z>=-.8 then continue end
				local first=ray(eye,delta)
				if not first or first.Instance~=pane then continue end
				local behind=first.Position+delta.Unit*.01
				if ray(behind,target-behind,insideParams) then continue end
				table.insert(record.viewpoints,{root=xyz(foot.Position+Vector3.new(0,3,0)),eye=xyz(eye),look=xyz(delta.Unit),
					distance=delta.Magnitude,floor=foot.Instance:GetFullName(),throughActualPane=true,interiorUnobstructed=true})
			end
			if #record.viewpoints>=3 then break end
		end
		local district=record.district or "UNKNOWN"
		local summary=report.districts[district] or {anchorCount=0,withSupportedSightline=0}
		report.districts[district]=summary;summary.anchorCount+=1
		if #record.viewpoints>0 then summary.withSupportedSightline+=1 end
		if #record.viewpoints==0 then issue(record,"no supported clear front-side viewpoint in bounded probe grid") end
	end
	for _,initial in ipairs({"A","B","C","D","E","F","G","H"}) do
		local count=0
		for name,summary in pairs(report.districts) do
			if name:sub(1,2)==initial.."_" then count+=summary.withSupportedSightline end
		end
		if count==0 then table.insert(report.failures,"district "..initial.." has no verified supported sightline") end
	end
	report.anchorCount=#ordered
	report.pass=#report.failures==0
	return report
end
return Inspect
