-- Focused, read-only native structural probes for the F atrium revision.
-- No actors/cameras/gates/geometry/properties/Instances are created or modified.
local Audit={}
local V=Vector3.new
local function xyz(v) return {v.X,v.Y,v.Z} end
local function path(v) return v and v:GetFullName() or nil end
local function opaque(hit)
	return hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
		and hit.Instance.Transparency<.05 and hit.Instance.Material~=Enum.Material.Glass
end
function Audit.Run(world,manifest,options)
	options=options or {}
	assert(world and world:IsDescendantOf(workspace),"Supply the built runtime world")
	assert(type(manifest)=="table" and typeof(manifest.Origin)=="Vector3","Supply Adapter.GetManifest()")
	local origin=manifest.Origin
	local architecture=assert(world:FindFirstChild("Level5_IndoorSuburbs"),"Architecture missing")
	local F=assert(architecture:FindFirstChild("F_BayWindowCanyon"),"F district missing")
	local enclosure=assert(F:FindFirstChild("Enclosure"),"F enclosure missing")
	local owner=world:FindFirstChild("Level5SectionProgression")
	local started=os.clock()
	local report={version="2026-09-26.atrium-focused.1",observedAtUtc=DateTime.now():ToIsoDate(),
		context=game:GetService("RunService"):IsClient() and "Client" or "Server",scope=F:GetFullName(),
		failures=0,warnings=0,issueCounts={},issuesByCode={},counts={rays=0,parts=0,windows=0,homes=0,enterableHomes=0},
		routes={},gates={},pit={},clue={},limitations={
			"Finite support and clearance rays are not actual character traversal or a full-volume sweep",
			"Pit floor sampling is bounded; it cannot prove absence of every sub-grid crack",
			"Gate closed and open states require separate snapshots; transitional gates are incomplete",
			"Watcher viewpoints are structural probes, not actual participant or multiplayer visibility",
			"Only F, its boundary gates, its clue and its three Watcher windows are evaluated"}}
	local count=report.counts
	local maxRays=options.MaxRays or 16000
	local maxSeconds=options.MaxSeconds or 25
	local limited=false
	local function issue(severity,code,object,at,detail)
		if severity=="FAIL" then report.failures+=1 else report.warnings+=1 end
		report.issueCounts[code]=(report.issueCounts[code] or 0)+1
		local rows=report.issuesByCode[code] or {};report.issuesByCode[code]=rows
		if #rows<200 then table.insert(rows,{severity=severity,object=path(object),at=at and xyz(at),detail=detail}) end
	end
	local function check(good,code,object,at,detail)
		if not good then issue("FAIL",code,object,at,detail) end
		return good
	end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={world};params.RespectCanCollide=true
	local shellParams=RaycastParams.new();shellParams.FilterType=Enum.RaycastFilterType.Include
	shellParams.FilterDescendantsInstances={enclosure};shellParams.RespectCanCollide=true
	local function ray(at,delta,filter)
		if count.rays>=maxRays or os.clock()-started>maxSeconds then limited=true;return nil,false end
		count.rays+=1
		return workspace:Raycast(at,delta,filter or params),true
	end
	local function closedGate(hit)
		local p=hit and hit.Instance
		while p and p~=world do
			if p:IsA("Model") and (p:GetAttribute("GateIndex")==5 or p:GetAttribute("GateIndex")==6) then
				return p:GetAttribute("FullyOpen")~=true
			end
			p=p.Parent
		end
		return false
	end
	local shellBoxes={}
	for _,p in ipairs(enclosure:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide and p.Transparency<.05 then
			table.insert(shellBoxes,{part=p,cf=p.CFrame,half=p.Size*.5})
		end
	end
	local function insideShell(at)
		for _,box in ipairs(shellBoxes) do
			local q=box.cf:PointToObjectSpace(at)
			if math.abs(q.X)<box.half.X-.001 and math.abs(q.Y)<box.half.Y-.001 and math.abs(q.Z)<box.half.Z-.001 then return box.part end
		end
	end
	local function shellRay(label,at,delta)
		if limited then return end
		local containing=insideShell(at)
		if containing then issue("FAIL","QA_ORIGIN_INSIDE_SHELL",containing,at,label);return end
		local hit,did=ray(at,delta,shellParams)
		if did then check(opaque(hit),"F_SHELL_GAP",hit and hit.Instance or enclosure,at,label) end
	end
	local homes={}
	for _,p in ipairs(F:GetDescendants()) do
		if p:IsA("BasePart") then count.parts+=1 end
		if p:IsA("Model") and typeof(p:GetAttribute("HouseFloorFrame"))=="CFrame" then
			table.insert(homes,p);count.homes+=1
			if p:GetAttribute("Enterable")==true then count.enterableHomes+=1 end
		end
		if p:IsA("BasePart") and (p.Name=="WindowGlass" or p:GetAttribute("Level5TintedWindow")) then
			count.windows+=1;local tint=Color3.fromRGB(87,102,102)
			check(p:GetAttribute("Level5TintedWindow")==true and p.Material==Enum.Material.Glass
				and math.abs(p.Transparency-.2)<.001 and p.Reflectance<.001
				and math.max(math.abs(p.Color.R-tint.R),math.abs(p.Color.G-tint.G),math.abs(p.Color.B-tint.B))<.005,
				"F_WINDOW_STANDARD",p,p.Position)
		end
	end
	for _,home in ipairs(homes) do for _,p in ipairs(home:GetDescendants()) do
		if p:IsA("Light") then issue("FAIL","F_HOUSE_LIGHT",p,nil) end
		if p:IsA("BasePart") and p.Material==Enum.Material.Neon then issue("FAIL","F_HOUSE_NEON",p,p.Position) end
	end end
	local pitBounds=options.FAtriumPitBounds or (manifest.FAtriumPitBounds and manifest.FAtriumPitBounds.Space=="local" and manifest.FAtriumPitBounds)
	if not pitBounds then
		local lo,hi=F:GetAttribute("PitMin"),F:GetAttribute("PitMax")
		if typeof(lo)=="Vector3" and typeof(hi)=="Vector3" then pitBounds={Min=lo,Max=hi} end
	end
	local pitLo,pitHi=pitBounds and pitBounds.Min,pitBounds and pitBounds.Max
	local validPit=check(typeof(pitLo)=="Vector3" and typeof(pitHi)=="Vector3" and pitLo.X<pitHi.X and pitLo.Y<pitHi.Y and pitLo.Z<pitHi.Z,
		"PIT_METADATA_MISSING",F,nil,"Expected LOCAL physical sump bounds, floor Min.Y and lower enclosure top Max.Y")
	local lo=F:GetAttribute("DistrictMin");local hi=F:GetAttribute("DistrictMax")
	if check(typeof(lo)=="Vector3" and typeof(hi)=="Vector3","F_BOUNDS_MISSING",F,nil) then
		local bottom=validPit and math.min(lo.Y,pitLo.Y) or lo.Y
		for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
			local x=sx<0 and lo.X or hi.X;local z=sz<0 and lo.Z or hi.Z
			for _,y in ipairs({bottom+.4,(bottom+hi.Y)/2,hi.Y-2}) do
				local at=origin+V(x-sx*8,y,z-sz*8)
				shellRay("corner side",at,V(sx*20,0,0));shellRay("corner end",at,V(0,0,sz*20))
				shellRay("corner diagonal",at,V(sx*20,0,sz*20))
			end
		end end
		for step=0,24 do
			local f=(step+.5)/25
			local x=lo.X+8+(hi.X-lo.X-16)*f;local z=lo.Z+8+(hi.Z-lo.Z-16)*f
			for _,side in ipairs({-1,1}) do
				local edgeX=side<0 and lo.X or hi.X;local edgeZ=side<0 and lo.Z or hi.Z
				shellRay("ceiling long edge",origin+V(edgeX-side*8,hi.Y-8,z),V(side*12,20,0))
				shellRay("ceiling short edge",origin+V(x,hi.Y-8,edgeZ-side*8),V(0,20,side*12))
				for _,y in ipairs({bottom+.5,hi.Y/2,hi.Y-2}) do
					shellRay("long wall",origin+V(edgeX-side*8,y,z),V(side*20,0,0))
				end
			end
		end
	end
	-- Landmark returns local vectors, but Architecture exposes WORLD manifest
	-- routes. Explicit option overrides are LOCAL; normalize once at this boundary.
	local function routeInput(key)
		if options[key] then return options[key] end
		local points=manifest[key]
		if type(points)~="table" then return nil end
		local result={}
		for _,p in ipairs(points) do table.insert(result,typeof(p)=="Vector3" and p-origin or p) end
		return result
	end
	local function standing(point,label,allowGate)
		local hit,did=ray(point+V(0,1,0),V(0,-6,0))
		if not did then return false end
		if not hit or not hit.Instance.CanCollide or hit.Normal.Y<.7 or math.abs(hit.Position.Y-(point.Y-3))>1.25 then
			issue("FAIL","F_ROUTE_SUPPORT",hit and hit.Instance or F,point,label);return false
		end
		for _,offset in ipairs({V(0,0,0),V(.85,0,0),V(-.85,0,0),V(0,0,.85),V(0,0,-.85)}) do
			local obstruction,cast=ray(hit.Position+offset+V(0,.2,0),V(0,5.5,0))
			if cast and obstruction then
				if allowGate and closedGate(obstruction) then count.expectedClosedGateHits=(count.expectedClosedGateHits or 0)+1
				else issue("FAIL","F_ROUTE_HEADROOM",obstruction.Instance,obstruction.Position,label) end
			end
		end
		return true
	end
	local function routeProbe(label,localPoints,allowGate)
		local row={name=label,waypoints=type(localPoints)=="table" and #localPoints or 0,samples=0,segments=0,points={}}
		table.insert(report.routes,row)
		if not check(type(localPoints)=="table" and #localPoints>=2,"F_ROUTE_MISSING",F,nil,label) then return end
		local previous=nil
		for index,p in ipairs(localPoints) do
			if limited then break end
			if not check(typeof(p)=="Vector3","F_ROUTE_POINT_INVALID",F,nil,label.." "..index) then previous=nil;continue end
			local point=origin+p;table.insert(row.points,xyz(point))
			if not previous then standing(point,label.." start",allowGate);row.samples+=1 else
				local distance=(point-previous).Magnitude
				local steps=math.max(1,math.ceil(distance/4))
				if steps>120 then issue("FAIL","F_ROUTE_SEGMENT_TOO_LONG",F,point,label);previous=point;continue end
				local last=previous
				for step=1,steps do
					if limited then break end
					local current=previous:Lerp(point,step/steps)
					standing(current,label.." "..index..":"..step,allowGate);row.samples+=1
					local delta=current-last;local flat=V(delta.X,0,delta.Z)
					local across=flat.Magnitude>.001 and V(-flat.Z,0,flat.X).Unit or V(1,0,0)
					for _,side in ipairs({-.85,0,.85}) do for _,height in ipairs({-.8,2.3}) do
						local obstruction,did=ray(last+across*side+V(0,height,0),delta)
						if did and obstruction then
							if allowGate and closedGate(obstruction) then count.expectedClosedGateHits=(count.expectedClosedGateHits or 0)+1
							else issue("FAIL","F_ROUTE_BLOCKED",obstruction.Instance,obstruction.Position,label.." segment "..index) end
						end
					end end
					last=current
				end
				row.segments+=1
			end
			previous=point
		end
	end
	local mainRoute=routeInput("FRouteWaypoints")
	local rescue=routeInput("FRescueRouteWaypoints")
	routeProbe("F main route",mainRoute,true)
	routeProbe("F lower rescue route",rescue,false)
	if validPit and type(rescue)=="table" and #rescue>=2 then
		check(math.abs(rescue[1].Y-3-pitLo.Y)<1.25,"RESCUE_START_NOT_PIT_FLOOR",F,origin+rescue[1])
		local endpoint=rescue[#rescue];local nearest=math.huge
		for index=2,#(mainRoute or {}) do
			local a,b=mainRoute[index-1],mainRoute[index];local d=b-a
			local alpha=d.Magnitude>.001 and math.clamp((endpoint-a):Dot(d)/d:Dot(d),0,1) or 0
			nearest=math.min(nearest,(endpoint-(a+d*alpha)).Magnitude)
		end
		report.pit.rescueToMainDistance=nearest==math.huge and -1 or nearest
		check(nearest<=3,"RESCUE_DISCONNECTED_FROM_MAIN_ROUTE",F,origin+endpoint,tostring(nearest))
	end
	if validPit then
		report.pit.min=xyz(pitLo);report.pit.max=xyz(pitHi);report.pit.floorSamples=0;report.pit.rimSamples=0
		local pitFloors={}
		for _,p in ipairs(F:GetDescendants()) do if p:IsA("BasePart") and p.Name=="PitFloor" then table.insert(pitFloors,p) end end
		check(#pitFloors>0,"PIT_FLOOR_MISSING",F,nil)
		local pitFloorParams=RaycastParams.new();pitFloorParams.FilterType=Enum.RaycastFilterType.Include
		pitFloorParams.FilterDescendantsInstances=pitFloors;pitFloorParams.RespectCanCollide=true
		local nx=math.max(2,math.ceil((pitHi.X-pitLo.X)/8));local nz=math.max(2,math.ceil((pitHi.Z-pitLo.Z)/8))
		if check(nx*nz<=4000,"PIT_GRID_TOO_LARGE",F,nil,tostring(nx*nz)) then
			for ix=0,nx do for iz=0,nz do
				if limited then break end
				local x=pitLo.X+.15+(pitHi.X-pitLo.X-.3)*ix/nx
				local z=pitLo.Z+.15+(pitHi.Z-pitLo.Z-.3)*iz/nz
				-- Inspect the actual lower backing floor, not a stair/ledge that
				-- could conceal a hole beneath it. Higher objects are excluded.
				local at=origin+V(x,pitLo.Y+2,z)
				local hit,did=ray(at,V(0,-5,0),pitFloorParams)
				if did then
					report.pit.floorSamples+=1
					check(opaque(hit) and hit.Normal.Y>.7 and hit.Position.Y>=origin.Y+pitLo.Y-.1,
						"PIT_FLOOR_GAP",hit and hit.Instance or F,at)
				end
			end end
		end
		-- Only the physical sump floor-to-wall-top band is enclosed here.
		-- Above Max.Y, authored doorways and ledges intentionally replace walls.
		-- Origins are eight studs inside the physical perimeter, not void edges.
		for _,axis in ipairs({"X","Z"}) do
			local amin=axis=="X" and pitLo.X or pitLo.Z;local amax=axis=="X" and pitHi.X or pitHi.Z
			local bmin=axis=="X" and pitLo.Z or pitLo.X;local bmax=axis=="X" and pitHi.Z or pitHi.X
			local steps=math.max(2,math.ceil((bmax-bmin)/12))
			for i=0,steps do for _,side in ipairs({-1,1}) do for _,fraction in ipairs({.12,.5,.88}) do
				local a=(side<0 and amin or amax)-side*8
				local b=bmin+8+(bmax-bmin-16)*i/steps
				local y=pitLo.Y+(pitHi.Y-pitLo.Y)*fraction
				local at=origin+(axis=="X" and V(a,y,b) or V(b,y,a))
				local delta=axis=="X" and V(side*20,0,0) or V(0,0,side*20)
				local hit,did=ray(at,delta)
				if did then report.pit.rimSamples+=1;check(opaque(hit),"PIT_SIDE_GAP",hit and hit.Instance or F,at,axis.." lower rim") end
			end end end
		end
	end
	-- Preserve both original progression boundaries. Settled door coverage is
	-- separate from the permanent foundation that closes a below-ground bypass.
	for _,item in ipairs({{index=5,localPosition=V(-120,0,1596)},{index=6,localPosition=V(178,0,2076)}}) do
		local spec=manifest.SectionGates and manifest.SectionGates[item.index]
		local gate=owner and owner:FindFirstChild("SectionGate"..item.index)
		if not check(spec and typeof(spec.Frame)=="CFrame" and gate,"F_GATE_MISSING",gate,nil,tostring(item.index)) then continue end
		local localPosition=spec.Frame.Position-origin
		check((localPosition-item.localPosition).Magnitude<.01,"F_GATE_MOVED",gate,spec.Frame.Position)
		check(spec.Frame.LookVector:Dot(V(0,0,-1))>.9999 and spec.Frame.UpVector.Y>.9999,"F_GATE_ROTATED",gate,spec.Frame.Position)
		check(typeof(spec.Approach)=="Vector3" and typeof(spec.Departure)=="Vector3"
			and (spec.Approach-(origin+item.localPosition+V(0,3,-12))).Magnitude<.01
			and (spec.Departure-(origin+item.localPosition+V(0,3,12))).Magnitude<.01,"F_GATE_APPROACH_MOVED",gate,spec.Frame.Position)
		local unlocked,opened=gate:GetAttribute("Unlocked")==true,gate:GetAttribute("FullyOpen")==true
		local moving=unlocked and not opened
		local row={index=item.index,fullyOpen=opened,unlocked=unlocked,moving=moving,doorRays=0,foundationRays=0}
		table.insert(report.gates,row)
		if moving then issue("WARN","F_GATE_TRANSITIONAL",gate,nil,"Rerun after tween") else
			for _,sign in ipairs({-1,1}) do
				local leaf=gate:FindFirstChild("SlidingLeaf"..sign)
				check(leaf and leaf:IsA("BasePart") and leaf.CanCollide==not opened and leaf.CanQuery==not opened,"F_GATE_LEAF_STATE",leaf,nil)
			end
			for _,x in ipairs({-10.3,-6,-2,0,2,6,10.3}) do for _,y in ipairs({.35,3,6,10,13.4}) do
				local at=spec.Frame:PointToWorldSpace(V(x,y,-1.8));local hit,did=ray(at,spec.Frame:VectorToWorldSpace(V(0,0,3.6)))
				if did then
					row.doorRays+=1
					check(opened and hit==nil or not opened and opaque(hit) and hit.Instance:IsDescendantOf(gate),opened and "F_OPEN_GATE_BLOCKED" or "F_LOCKED_GATE_GAP",gate,at)
				end
			end end
		end
		if validPit then
			for _,x in ipairs({-10.3,-6,0,6,10.3}) do
				for y=pitLo.Y+.5,-.5,3 do
					local at=spec.Frame:PointToWorldSpace(V(x,y,-8));local direction=spec.Frame:VectorToWorldSpace(V(0,0,20))
					local containing=insideShell(at)
					if containing then issue("FAIL","QA_ORIGIN_INSIDE_SHELL",containing,at,"gate foundation") else
						local hit,did=ray(at,direction,shellParams)
						if did then row.foundationRays+=1;check(opaque(hit),"UNDER_GATE_BYPASS",gate,at,"Expected permanent F foundation below gate") end
					end
				end
			end
		end
	end
	-- The television clue must be inside an enterable F home, with a real
	-- unobstructed doorway and at least one supported route to read its panel.
	local clue=owner and owner:FindFirstChild("SectionPuzzleClue_6_1")
	local reference=clue and clue:FindFirstChild("SourceHome")
	local home=reference and reference:IsA("ObjectValue") and reference.Value
	local carrier=clue and clue:FindFirstChild("HintSurface")
	if check(home and home:IsDescendantOf(F) and home:GetAttribute("Enterable")==true and carrier and carrier:IsA("BasePart"),"F_CLUE6_MISSING",home,nil) then
		local frame,size=home:GetAttribute("HouseFloorFrame"),home:GetAttribute("HouseRoomSize")
		report.clue.home=path(home);report.clue.carrier=path(carrier)
		if check(typeof(frame)=="CFrame" and typeof(size)=="Vector3","F_CLUE6_HOME_FRAME",home,nil) then
			local gui=carrier:FindFirstChildWhichIsA("SurfaceGui")
			check(gui and gui.Enabled and gui.Face==Enum.NormalId.Front and not gui.AlwaysOnTop,"F_CLUE6_GUI",carrier,carrier.Position)
			check(carrier.CFrame.LookVector:Dot(frame.LookVector)>.999,"F_CLUE6_ORIENTATION",carrier,carrier.Position)
			check(not carrier.CanCollide and not carrier.CanQuery,"F_CLUE6_COLLISION",carrier,carrier.Position)
			local route={}
			for _,p in ipairs({V(0,3,-3),V(0,3,3),V(0,3,size.Z-6)}) do table.insert(route,frame:PointToWorldSpace(p)-origin) end
			routeProbe("Clue6 doorway to panel",route,false)
			local eye=frame:PointToWorldSpace(V(0,5,size.Z-6))
			local hit,did=ray(eye,carrier.Position-eye)
			if did then check(hit==nil,"F_CLUE6_VIEW_BLOCKED",hit and hit.Instance or home,eye) end
			report.clue.readRoot=xyz(origin+route[#route])
		end
	end
	local clueRoute=routeInput("FClueRouteWaypoints")
	if clueRoute then routeProbe("F main route to clue6",clueRoute,false)
	else issue("WARN","F_CLUE6_GLOBAL_ROUTE_UNPROVEN",home,nil,"No explicit main-route to home doorway chain; interior lane alone cannot establish global access") end
	if options.WatcherInspector then
		report.watcher=options.WatcherInspector.Run(world)
		for _,message in ipairs(report.watcher.failures or {}) do issue("FAIL","F_WATCHER_GEOMETRY",F,nil,message) end
	else issue("WARN","F_WATCHER_NOT_RUN",F,nil,"Supply focused WatcherInspector") end
	report.limited=limited;report.durationSeconds=os.clock()-started
	if limited then issue("FAIL","QA_BUDGET_EXHAUSTED",F,nil,"Native audit incomplete") end
	report.pass=report.failures==0 and not limited
	report.status=report.pass and "PASS" or "FAIL"
	return report
end
return Audit
