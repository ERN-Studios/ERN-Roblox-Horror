local H=game:GetService("HttpService")
local Audit=(function()
-- Read-only native probes. Does not generate geometry, move actors/cameras,
-- open gates, change properties, create Instances or claim character traversal.
local Audit={}
local V=Vector3.new
local function xyz(v) return {v.X,v.Y,v.Z} end
local function name(v) return v and v:GetFullName() or nil end
local function opaque(hit)
	return hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
		and hit.Instance.Transparency<.05 and hit.Instance.Material~=Enum.Material.Glass
end
function Audit.Run(world,manifest,options)
	options=options or {}
	assert(world and world:IsDescendantOf(workspace),"Supply the actual generated world")
	assert(type(manifest)=="table" and typeof(manifest.Origin)=="Vector3","Supply the actual Adapter.GetManifest()")
	local root=assert(world:FindFirstChild("Level5_IndoorSuburbs"),"Architecture missing")
	local started=os.clock()
	local report={version="2026-09-26.dense-routes.2",observedAtUtc=DateTime.now():ToIsoDate(),context=game:GetService("RunService"):IsClient() and "Client" or "Server",
		failures=0,warnings=0,issues={},omittedIssues=0,issueCounts={},issuesByCode={},omittedByCode={},counts={},gates={},clues={},routes={},shell={},anchorDistricts={},
		limitations={"Bounded structural rays, not actual walking, full-volume sweeps or visual inspection",
			"Closed and fully open gate states require separate snapshots; moving gates are incomplete",
			"Probe lanes do not prove global navigability or multiplayer/device performance"}}
	local maxRays=math.clamp(options.MaxRays or 22000,100,50000)
	local maxSeconds=math.clamp(options.MaxSeconds or 22,1,50)
	local maxIssues=math.clamp(options.MaxIssues or 100,10,300)
	local maxIssuesPerCode=math.clamp(options.MaxIssuesPerCode or 200,20,500)
	local limited=false
	local function issue(severity,code,object,point,detail)
		if severity=="FAIL" then report.failures+=1 else report.warnings+=1 end
		local row={severity=severity,code=code,object=name(object),position=point and xyz(point),detail=detail}
		report.issueCounts[code]=(report.issueCounts[code] or 0)+1
		report.issuesByCode[code]=report.issuesByCode[code] or {}
		if #report.issuesByCode[code]<maxIssuesPerCode then table.insert(report.issuesByCode[code],row)
		else report.omittedByCode[code]=(report.omittedByCode[code] or 0)+1 end
		if #report.issues<maxIssues then table.insert(report.issues,row) else report.omittedIssues+=1 end
	end
	local function check(condition,code,object,point,detail)
		if not condition then issue("FAIL",code,object,point,detail) end
		return condition
	end
	local c={descendants=0,parts=0,lights=0,windows=0,homes=0,enterableHomes=0,houseLights=0,houseNeon=0,
		rays=0,shellRays=0,shellOriginsChecked=0,shellOriginsInside=0,routeSamples=0,routeSegments=0,expectedLockedGateHits=0,gateRays=0,clueSamples=0}
	report.counts=c
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={world};params.RespectCanCollide=true
	local shellParams=RaycastParams.new();shellParams.FilterType=Enum.RaycastFilterType.Include;shellParams.RespectCanCollide=true
	local function ray(from,direction,filter)
		if c.rays>=maxRays or os.clock()-started>=maxSeconds then limited=true;return nil,false end
		c.rays+=1;return workspace:Raycast(from,direction,filter or params),true
	end
	local function gateAncestor(object)
		local p=object
		while p and p~=world do
			if p:IsA("Model") and p:GetAttribute("GateIndex") then return p end
			p=p.Parent
		end
	end
	local function allowedClosedGate(hit)
		local gate=hit and gateAncestor(hit.Instance)
		return gate and gate:GetAttribute("FullyOpen")~=true
	end
	local homes,firstClues,enclosures={},{},{}
	for _,v in ipairs(world:GetDescendants()) do
		c.descendants+=1
		if v:IsA("BasePart") then c.parts+=1 end
		if v:IsA("Light") then c.lights+=1 end
		if v:IsA("Model") and v:IsDescendantOf(root) then
			if v.Name=="Enclosure" then table.insert(enclosures,v) end
			if v:GetAttribute("HouseFloorFrame") then
				table.insert(homes,v);c.homes+=1
				if v:GetAttribute("Enterable")==true then c.enterableHomes+=1 end
			end
			if v:GetAttribute("PuzzleClueIndex") then table.insert(firstClues,v) end
		end
		if v:IsA("BasePart") and v:IsDescendantOf(root) and (v.Name=="WindowGlass" or v:GetAttribute("Level5TintedWindow")) then
			c.windows+=1
			local tint=Color3.fromRGB(87,102,102)
			check(v.Material==Enum.Material.Glass and v:GetAttribute("Level5TintedWindow")==true and math.abs(v.Transparency-.2)<.001
				and math.max(math.abs(v.Color.R-tint.R),math.abs(v.Color.G-tint.G),math.abs(v.Color.B-tint.B))<.005 and v.Reflectance<.001,
				"WINDOW_STANDARD",v,v.Position,"Expected dark tinted Glass; no luminous pane")
		end
	end
	check(c.descendants<=(options.MaxDescendants or 28000),"DESCENDANT_BUDGET",world,nil,tostring(c.descendants))
	check(#enclosures==8,"ENCLOSURE_COUNT",root,nil,tostring(#enclosures))
	shellParams.FilterDescendantsInstances=enclosures
	local opaqueShellBoxes={}
	for _,enclosure in ipairs(enclosures) do for _,part in ipairs(enclosure:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide and part.Transparency<.05 and part.Material~=Enum.Material.Glass then
			table.insert(opaqueShellBoxes,{part=part,frame=part.CFrame,half=part.Size*.5})
		end
	end end
	for _,home in ipairs(homes) do
		for _,v in ipairs(home:GetDescendants()) do
			if v:IsA("Light") then c.houseLights+=1;issue("FAIL","HOUSE_LIGHT",v,nil) end
			if v:IsA("BasePart") and v.Material==Enum.Material.Neon then c.houseNeon+=1;issue("FAIL","HOUSE_NEON",v,v.Position) end
		end
	end
	local zones=manifest.Zones or {}
	check(#zones==8,"ZONE_COUNT",root,nil,tostring(#zones))
	local gates=manifest.SectionGates or {}
	check(#gates==7,"GATE_MANIFEST_COUNT",world,nil,tostring(#gates))
	local origin=manifest.Origin
	-- Both wall normals at every corner and dense ceiling-edge stations. Only
	-- enclosing structural shells qualify; a nearby house cannot mask a hole.
	local function shellRay(zone,label,from,dir)
		if limited then return end
		-- A ray originating inside a thick part may ignore that containing
		-- part. Treat bad origins as a QA failure, never an architectural hole.
		c.shellOriginsChecked+=1
		for _,box in ipairs(opaqueShellBoxes) do
			local p=box.frame:PointToObjectSpace(from)
			if math.abs(p.X)<box.half.X-.001 and math.abs(p.Y)<box.half.Y-.001 and math.abs(p.Z)<box.half.Z-.001 then
				c.shellOriginsInside+=1;issue("FAIL","QA_ORIGIN_INSIDE_SHELL",box.part,from,label);return
			end
		end
		local hit,did=ray(from,dir,shellParams)
		if did then c.shellRays+=1;check(opaque(hit),"OPAQUE_SHELL_GAP",zone.Model,from,label..(hit and " hit "..name(hit.Instance) or " hit nothing")) end
	end
	for index,zone in ipairs(zones) do
		if options.SkipShell then break end
		if limited then break end
		local lo,hi=zone.Min,zone.Max
		if not check(typeof(lo)=="Vector3" and typeof(hi)=="Vector3","ZONE_BOUNDS",zone.Model,nil) then continue end
		table.insert(report.shell,{zone=zone.Name,min=xyz(lo),max=xyz(hi)})
		for _,xside in ipairs({-1,1}) do for _,zside in ipairs({-1,1}) do
			local x=xside<0 and lo.X or hi.X;local z=zside<0 and lo.Z or hi.Z
			for _,y in ipairs({lo.Y+.2,lo.Y+(hi.Y-lo.Y)*.5,hi.Y-2}) do
				local at=origin+V(x-xside*8,y,z-zside*8)
				shellRay(zone,"corner side",at,V(xside*20,0,0))
				shellRay(zone,"corner end",at,V(0,0,zside*20))
				shellRay(zone,"corner diagonal",at,V(xside*20,0,zside*20))
			end
			local at=origin+V(x-xside*8,hi.Y-8,z-zside*8)
			shellRay(zone,"ceiling corner",at,V(0,20,0))
			shellRay(zone,"ceiling corner diagonal",at,V(xside*20,20,zside*20))
		end end
		local edgeSteps=math.min(30,math.max(8,math.ceil(math.max(hi.X-lo.X,hi.Z-lo.Z)/20)))
		for step=0,edgeSteps do
			local fraction=(step+.01)/(edgeSteps+.02)
			local x=math.clamp(lo.X+(hi.X-lo.X)*fraction,lo.X+8,hi.X-8)
			local z=math.clamp(lo.Z+(hi.Z-lo.Z)*fraction,lo.Z+8,hi.Z-8)
			for _,side in ipairs({-1,1}) do
				local edgeX=side<0 and lo.X or hi.X;local edgeZ=side<0 and lo.Z or hi.Z
				local along=origin+V(edgeX-side*8,hi.Y-8,z)
				local across=origin+V(x,hi.Y-8,edgeZ-side*8)
				shellRay(zone,"ceiling long edge",along,V(0,20,0))
				shellRay(zone,"ceiling long edge diagonal",along,V(side*20,20,0))
				shellRay(zone,"ceiling short edge",across,V(0,20,0))
				shellRay(zone,"ceiling short edge diagonal",across,V(0,20,side*20))
				for _,y in ipairs({lo.Y+.3,lo.Y+(hi.Y-lo.Y)*.5,hi.Y-2}) do
					shellRay(zone,"side wall edge",origin+V(edgeX-side*8,y,z),V(side*20,0,0))
					local gateIndex=side>0 and index or index-1
					local opening=gates[gateIndex]
					local point=origin+V(x,y,edgeZ)
					local localPoint=opening and typeof(opening.Frame)=="CFrame" and opening.Frame:PointToObjectSpace(point)
					local skip=localPoint and math.abs(localPoint.X)<11.05 and localPoint.Y>-.05 and localPoint.Y<14.05
					if index==8 and side>0 and math.abs(x)<4.7 and y<11.05 then skip=true end -- authored final descent mouth
					if not skip then shellRay(zone,"end wall seam",origin+V(x,y,edgeZ-side*8),V(0,0,side*20)) end
				end
			end
		end
	end
	if options.SkipShell then issue("WARN","SHELL_SKIPPED",root,nil,"Explicit diagnostic option; shell coverage not evaluated") end
	local owner=world:FindFirstChild("Level5SectionProgression")
	check(owner~=nil,"PROGRESSION_OWNER",world,nil)
	for index,spec in ipairs(gates) do
		if limited then break end
		local gate=owner and owner:FindFirstChild("SectionGate"..index)
		if not check(gate and typeof(spec.Frame)=="CFrame" and typeof(spec.Approach)=="Vector3" and typeof(spec.Departure)=="Vector3","GATE_CONTRACT",gate,nil,tostring(index)) then continue end
		local unlocked,fullyOpen=gate:GetAttribute("Unlocked")==true,gate:GetAttribute("FullyOpen")==true
		local moving=unlocked and not fullyOpen
		local row={index=index,unlocked=unlocked,fullyOpen=fullyOpen,moving=moving,position=xyz(spec.Frame.Position),rays=0}
		table.insert(report.gates,row)
		check(spec.Frame:PointToObjectSpace(spec.Approach).Z<0 and spec.Frame:PointToObjectSpace(spec.Departure).Z>0,"GATE_DIRECTION",gate,spec.Frame.Position)
		if moving then issue("WARN","GATE_TRANSITIONAL",gate,spec.Frame.Position,"Rerun after tween; this state cannot prove either settled coverage") end
		for _,side in ipairs({-1,1}) do
			local leaf=gate:FindFirstChild("SlidingLeaf"..side)
			if check(leaf and leaf:IsA("BasePart"),"MISSING_LEAF",gate,nil,tostring(side)) and not moving then
				check(leaf.CanCollide==not fullyOpen and leaf.CanQuery==not fullyOpen,"LEAF_COLLISION_STATE",leaf,leaf.Position)
			end
		end
		if not moving then
			for _,x in ipairs({-10.3,-6,-2,0,2,6,10.3}) do for _,y in ipairs({.35,3,6,10,13.4}) do
				for _,side in ipairs({-1,1}) do
					local from=spec.Frame:PointToWorldSpace(V(x,y,side*1.8));local dir=spec.Frame:VectorToWorldSpace(V(0,0,-side*3.6))
					local hit,did=ray(from,dir)
					if did then
						row.rays+=1;c.gateRays+=1
						check(fullyOpen and hit==nil or not fullyOpen and opaque(hit) and hit.Instance:IsDescendantOf(gate),fullyOpen and "OPEN_GATE_BLOCKED" or "LOCKED_GATE_GAP",gate,from,hit and name(hit.Instance))
					end
				end
			end end
		end
	end
	-- Root-height route points. Straight subsegment rays reveal only sampled
	-- lanes; locked progression leaves are expected obstructions, never ignored.
	local function standing(point,label,allowGate)
		local foot=point-V(0,3,0)
		local support,did=ray(point+V(0,1,0),V(0,-6,0))
		if not did then return false end
		local good=support and support.Instance.CanCollide and support.Normal.Y>.7 and math.abs(support.Position.Y-foot.Y)<=1.25
		if not good then issue("FAIL","ROUTE_FLOOR_PROBE",support and support.Instance or world,point,label);return false end
		for _,offset in ipairs({V(0,0,0),V(.85,0,0),V(-.85,0,0),V(0,0,.85),V(0,0,-.85)}) do
			local hit,cast=ray(support.Position+offset+V(0,.2,0),V(0,5.5,0))
			if cast and hit then
				if allowGate and allowedClosedGate(hit) then c.expectedLockedGateHits+=1
				else issue("FAIL","ROUTE_HEADROOM_PROBE",hit.Instance,hit.Position,label);good=false end
			end
		end
		return good
	end
	local route=manifest.RouteWaypoints or {}
	check(#route>=8,"ROUTE_WAYPOINTS_MISSING",world,nil,"Expected ordered world root-height RouteWaypoints")
	report.routes.waypoints=#route
	for index,point in ipairs(route) do
		if limited then break end
		if not check(typeof(point)=="Vector3","INVALID_ROUTE_POINT",world,nil,tostring(index)) then continue end
		local previous=route[index-1]
		if not previous then standing(point,"route start",true);c.routeSamples+=1 else
			local distance=(point-previous).Magnitude
			local steps=math.max(1,math.ceil(distance/5))
			if steps>100 then issue("FAIL","ROUTE_SEGMENT_UNBOUNDED",world,point,"Add intermediate waypoints");continue end
			local last=previous
			for step=1,steps do
				if limited then break end
				local current=previous:Lerp(point,step/steps)
				standing(current,"route "..index.." sample "..step,true);c.routeSamples+=1
				local planar=current-last;planar=V(planar.X,0,planar.Z)
				local sideways=planar.Magnitude>.001 and V(-planar.Z,0,planar.X).Unit or V(1,0,0)
				for _,x in ipairs({-.85,0,.85}) do for _,height in ipairs({-.8,2.3}) do
					local from=last+sideways*x+V(0,height,0)
					local hit,did=ray(from,current-last)
					if did and hit then
						if allowedClosedGate(hit) then c.expectedLockedGateHits+=1
						else issue("FAIL","ROUTE_SEGMENT_PROBE_BLOCKED",hit.Instance,hit.Position,"Segment "..index) end
					end
				end end
				last=current
			end
			c.routeSegments+=1
		end
	end
	-- Verify home entry and viewing support for all first and later clue panels.
	local clues={}
	for _,home in ipairs(firstClues) do table.insert(clues,{gate=1,slot=home:GetAttribute("PuzzleClueIndex"),home=home,carrier=home:FindFirstChild("PuzzleClueSurface",true)}) end
	if owner then for _,model in ipairs(owner:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("PuzzleGateIndex") then
			local source=model:FindFirstChild("SourceHome")
			table.insert(clues,{gate=model:GetAttribute("PuzzleGateIndex"),slot=model:GetAttribute("PuzzleClueSlot"),home=source and source:IsA("ObjectValue") and source.Value,carrier=model:FindFirstChild("HintSurface")})
		end
	end end
	local clueCounts={}
	for _,clue in ipairs(clues) do
		if limited then break end
		clueCounts[clue.gate]=(clueCounts[clue.gate] or 0)+1
		local home,carrier=clue.home,clue.carrier
		local row={gate=clue.gate,slot=clue.slot,home=name(home),carrier=name(carrier)};table.insert(report.clues,row)
		if not check(home and home:IsDescendantOf(root) and home:GetAttribute("Enterable")==true and carrier and carrier:IsA("BasePart"),"CLUE_HOME_OR_CARRIER",home,nil) then continue end
		local frame,size=home:GetAttribute("HouseFloorFrame"),home:GetAttribute("HouseRoomSize")
		if not check(typeof(frame)=="CFrame" and typeof(size)=="Vector3","CLUE_HOME_FRAME",home,nil) then continue end
		check(math.abs(frame.Position.Y-origin.Y)<.2,"CLUE_NOT_GROUND_LEVEL",home,frame.Position)
		local gui=carrier:FindFirstChildWhichIsA("SurfaceGui")
		check(gui and gui.Enabled and gui.Face==Enum.NormalId.Front and not gui.AlwaysOnTop,"CLUE_GUI",carrier,carrier.Position)
		check(carrier.CFrame.LookVector:Dot(frame.LookVector)>.999,"CLUE_FACES_AWAY",carrier,carrier.Position)
		check(not carrier.CanCollide and not carrier.CanQuery,"CLUE_CARRIER_COLLISION",carrier,carrier.Position)
		for _,x in ipairs({-1,0,1}) do for _,y in ipairs({2.2,5.3}) do
			local from=frame:PointToWorldSpace(V(x,y,-1.5));local hit,did=ray(from,frame:VectorToWorldSpace(V(0,0,5)))
			if did then check(hit==nil,"CLUE_ENTRY_LANE_BLOCKED",hit and hit.Instance or home,from) end
		end end
		-- Three possible supported viewing stations; test sight to actual carrier.
		row.supportedViewpoints={}
		row.connectedEntryLanes=0
		for _,x in ipairs({0,-3,3}) do
			local point=frame:PointToWorldSpace(V(x,3,size.Z-6))
			local foot,did=ray(point+V(0,1,0),V(0,-6,0))
			if did and foot and foot.Normal.Y>.7 and math.abs(foot.Position.Y-(home:GetAttribute("ActualFloorTopY") or frame.Position.Y))<.2 then
				local ceiling=ray(foot.Position+V(0,.2,0),V(0,5.5,0))
				local eye=foot.Position+V(0,5,0)
				local hit=ray(eye,carrier.Position-eye)
				if not ceiling and not hit then
					table.insert(row.supportedViewpoints,xyz(point))
					local lane={frame:PointToWorldSpace(V(0,3,-1.5)),frame:PointToWorldSpace(V(0,3,3)),frame:PointToWorldSpace(V(x,3,3)),point}
					local clear=true
					for index=2,#lane do
						local a,b=lane[index-1],lane[index]
						local planar=b-a;planar=V(planar.X,0,planar.Z)
						local across=planar.Magnitude>.001 and V(-planar.Z,0,planar.X).Unit or frame.RightVector
						for _,side in ipairs({-.65,0,.65}) do for _,height in ipairs({-.8,2.3}) do
							local obstruction,checked=ray(a+across*side+V(0,height,0),b-a)
							if not checked or obstruction then clear=false end
						end end
						local steps=math.max(1,math.ceil((b-a).Magnitude/4))
						for step=1,steps do
							local position=a:Lerp(b,step/steps)
							local support,checked=ray(position+V(0,1,0),V(0,-6,0))
							if not checked or not support or support.Normal.Y<.7 or (support.Position.Y<frame.Position.Y-.2 or support.Position.Y>math.max(frame.Position.Y,home:GetAttribute("ActualFloorTopY") or frame.Position.Y)+.2) then clear=false end
						end
					end
					if clear then row.connectedEntryLanes+=1 end
				end
			end
			c.clueSamples+=1
		end
		check(#row.supportedViewpoints>0,"CLUE_VIEW_PROBES_BLOCKED",home,carrier.Position,"No supported station in bounded three-point sample; actual route not proven")
		check(row.connectedEntryLanes>0,"CLUE_ENTRY_TO_VIEW_PROBES_BLOCKED",home,carrier.Position,"No sampled supported lane from doorway to viewing station; this is not a full navigation search")
	end
	for gate,expected in ipairs({4,1,3,1,1,1,1}) do check(clueCounts[gate]==expected,"CLUE_COUNT",owner,nil,"Gate "..gate..": "..tostring(clueCounts[gate]).." expected "..expected) end
	-- Separate reusable inspector checks real pane rays and supporting rooms.
	local watcher=world:FindFirstChild("WindowWatcherAnchors")
	check(watcher~=nil,"WATCHER_ANCHORS_MISSING",world,nil)
	if watcher then for _,anchor in ipairs(watcher:GetChildren()) do
		local district=anchor:GetAttribute("District") or "UNKNOWN"
		report.anchorDistricts[district]=(report.anchorDistricts[district] or 0)+1
		check(anchor:GetAttribute("Level5WindowWatcherAnchor")==true,"WATCHER_ANCHOR_FLAG",anchor,nil)
	end end
	for _,zone in ipairs(zones) do check((report.anchorDistricts[zone.Name] or 0)>0,"WATCHER_DISTRICT_MISSING",zone.Model,nil) end
	if options.WatcherInspector and not limited then
		report.watcherGeometry=options.WatcherInspector.Run(world)
		check(report.watcherGeometry.pass==true,"WATCHER_GEOMETRY_FAILED",watcher,nil,"See watcherGeometry.failures")
	else issue("WARN","WATCHER_LOS_NOT_RUN",watcher,nil,"Pass the companion inspector as options.WatcherInspector") end
	report.limited=limited;report.durationSeconds=os.clock()-started
	report.status=limited and "INCOMPLETE" or report.failures>0 and "FAIL" or report.warnings>0 and "PASS_WITH_LIMITATIONS" or "PASS"
	report.pass=not limited and report.failures==0
	return report
end
return Audit

end)()
local Watcher=(function()
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
		if (relative.Position-Vector3.new(0,-6.55+(anchor:GetAttribute("SurfaceLift") or 0),0)).Magnitude>.02
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

end)()
local ok,result=xpcall(function()
 local world=assert(workspace:FindFirstChild("Level 5 Generated World"))
 local manifest=assert(require(game.ServerScriptService["Level 5 Systems"]["Level 5 Round Adapter"]).GetManifest())
 return Audit.Run(world,manifest,{MaxDescendants=30000,MaxSeconds=45,MaxRays=30000,WatcherInspector=Watcher})
end,debug.traceback)
if not ok then result={pass=false,error=result} end
script:SetAttribute("Report",H:JSONEncode(result))
script:SetAttribute("Summary",H:JSONEncode({pass=result.pass,failures=result.failures,counts=result.counts,issues=result.issueCounts,error=result.error}))
