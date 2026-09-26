-- Read-only snapshot inspection. Returns data; never moves characters or changes geometry.
local QA = {}
local V = Vector3.new
local EXPECTED_CLUES = {
	"rbxassetid://129034114315469", "rbxassetid://82053429341504",
	"rbxassetid://98028147005436", "rbxassetid://73277763916471",
}
local function vector(value) return typeof(value) == "Vector3" end
local function xyz(v)
	return {math.round(v.X*1000)/1000, math.round(v.Y*1000)/1000, math.round(v.Z*1000)/1000}
end
local function path(object) return object and object:GetFullName() or nil end

function QA.Inspect(options)
	options = options or {}
	local started = os.clock()
	local world = options.World or workspace:FindFirstChild("Level 5 Generated World")
	local report = {version = "2026-09-26.expansion-static.1", context = game:GetService("RunService"):IsClient() and "Client" or "Server",
		status = "INCOMPLETE", failures = 0, warnings = 0, issues = {}, issueRowsOmitted = 0, counts = {}, zones = {}, gates = {}, clues = {},
		scope = "Read-only collision rays and instance metadata from one snapshot; no character walking, full-volume sweep or device performance proof",
		unverified = {"actual character traversal", "full-volume collision clearance", "all-device performance", "complete visual appearance"}}
	local maxRows = math.clamp(options.MaxIssueRows or 70, 1, 200)
	local maxRays = math.clamp(options.MaxRays or 12000, 100, 50000)
	local maxSeconds = math.clamp(options.MaxSeconds or 18, 1, 60)
	local limited = false
	local rays = 0
	local function issue(severity, code, object, position, detail)
		if severity == "FAIL" then report.failures += 1 else report.warnings += 1 end
		if #report.issues < maxRows then
			table.insert(report.issues, {severity = severity, code = code, path = path(object), position = position and xyz(position) or nil, detail = detail})
		else report.issueRowsOmitted += 1 end
	end
	local function requireCheck(ok, code, object, position, detail)
		if not ok then issue("FAIL", code, object, position, detail) end
		return ok
	end
	if not requireCheck(world and world:IsA("Model") and world.Parent == workspace, "WORLD_MISSING", world, nil, "Inspect an actual generated round") then
		report.status = "FAIL"; return report
	end
	local root = world:FindFirstChild("Level5_IndoorSuburbs")
	local origin = options.Origin or world:GetAttribute("Origin") or world:GetAttribute("Level5_Origin")
	if not requireCheck(root and root:IsA("Model"), "ARCHITECTURE_MISSING", world, nil)
		or not requireCheck(vector(origin), "ORIGIN_REQUIRED", world, nil, "Pass the build's real world Origin Vector3; no guessed Adapter manifest") then
		report.status = "FAIL"; return report
	end
	report.origin = xyz(origin); report.architectureVersion = root:GetAttribute("ArchitectureVersion")
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {world}; params.RespectCanCollide = true
	local function cast(from, direction)
		if limited then return nil, false end
		if rays >= maxRays or os.clock()-started > maxSeconds then limited = true; return nil, false end
		rays += 1; return workspace:Raycast(from, direction, params), true
	end
	local function budget() return not limited and os.clock()-started <= maxSeconds end
	local zones, homes, clueHomes = {}, {}, {}
	local counts = {baseParts = 0, lights = 0, windows = 0, surfaceGuis = 0, houses = 0, openHomes = 0, closedHomes = 0,
		houseLights = 0, houseNeon = 0, entryRays = 0, floorRays = 0, headroomRays = 0, boundaryRays = 0, doorRays = 0,
		homesInspected = 0, clientClueImagesLoaded = 0}
	report.counts = counts
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") then counts.baseParts += 1 end
		if object:IsA("Light") then counts.lights += 1 end
		if object:IsA("SurfaceGui") then counts.surfaceGuis += 1 end
		if object:IsA("Model") and object:IsDescendantOf(root) then
			local lo, hi = object:GetAttribute("ZoneMin"), object:GetAttribute("ZoneMax")
			if lo ~= nil or hi ~= nil then
				if requireCheck(vector(lo) and vector(hi), "INVALID_ZONE_BOUNDS", object, nil) then
					table.insert(zones, {model = object, lo = lo, hi = hi, ceiling = object:GetAttribute("CeilingHeight")})
				end
			end
			if object:GetAttribute("HouseFloorFrame") ~= nil then
				table.insert(homes, object); counts.houses += 1
				if object:GetAttribute("Enterable") == true then counts.openHomes += 1 else counts.closedHomes += 1 end
			end
			local clue = object:GetAttribute("PuzzleClueIndex")
			if clue ~= nil then
				if requireCheck(type(clue)=="number" and clue%1==0 and clue>=1 and clue<=4 and not clueHomes[clue], "INVALID_CLUE_INDEX", object, nil, tostring(clue)) then clueHomes[clue]=object end
			end
		end
		if object:IsA("BasePart") and object:IsDescendantOf(root)
			and (object.Name == "WindowGlass" or object:GetAttribute("Level5TintedWindow") == true) then
			counts.windows += 1
			local expected = Color3.fromRGB(87,102,102)
			local tintError = math.max(math.abs(object.Color.R-expected.R),math.abs(object.Color.G-expected.G),math.abs(object.Color.B-expected.B))
			requireCheck(object.Material == Enum.Material.Glass and object:GetAttribute("Level5TintedWindow") == true
				and math.abs(object.Transparency-.2) < .001 and tintError < .005 and object.Reflectance < .001,
				"NONSTANDARD_WINDOW", object, object.Position, "Expected dark Glass RGB87/102/102, transparency0.2, reflectance0")
		end
	end
	table.sort(zones, function(a,b) return a.lo.Z < b.lo.Z end)
	requireCheck(#zones == 8, "ZONE_COUNT", root, nil, "Expected8; actual"..#zones)
	for i,z in ipairs(zones) do
		requireCheck(z.hi.X>z.lo.X and z.hi.Y>z.lo.Y and z.hi.Z>z.lo.Z and type(z.ceiling)=="number" and math.abs(z.ceiling-z.hi.Y)<.01,
			"ZONE_DIMENSIONS",z.model,nil)
		if i>1 then requireCheck(math.abs(zones[i-1].hi.Z-z.lo.Z)<.1,"SECTION_BOUNDARY_GAP",z.model,origin+V(0,0,z.lo.Z)) end
		table.insert(report.zones,{name=z.model.Name,min=xyz(z.lo),max=xyz(z.hi),ceiling=z.ceiling})
	end
	-- Every actual house: lighting policy. Open houses: sampled first entry lane/floor/head clearance.
	for _,home in ipairs(homes) do
		if not budget() then limited=true; break end
		for _,object in ipairs(home:GetDescendants()) do
			if object:IsA("Light") then counts.houseLights+=1;issue("FAIL","INDIVIDUAL_HOUSE_LIGHT",object,nil,"House-local lights are disallowed, including disabled ones") end
			if object:IsA("BasePart") and object.Material==Enum.Material.Neon then counts.houseNeon+=1;issue("FAIL","LUMINOUS_HOUSE_PART",object,object.Position) end
		end
		local frame=home:GetAttribute("HouseFloorFrame")
		local size=home:GetAttribute("HouseRoomSize") or home:GetAttribute("RoomSize")
		if home:GetAttribute("Enterable")==true then
			if requireCheck(typeof(frame)=="CFrame" and vector(size) and size.X>5 and size.Y>6 and size.Z>5,"OPEN_HOME_METADATA",home,nil) then
				requireCheck(frame.UpVector.Y>.999,"TILTED_ENTERABLE_HOME",home,frame.Position,"Playable interior should have an upright floor frame")
				-- Six entry rays sample a 2.5-stud-wide lane at torso and head heights, crossing the facade.
				for _,x in ipairs({-1.25,0,1.25}) do
					for _,y in ipairs({2.2,5.3}) do
						local a=frame:PointToWorldSpace(V(x,y,-1.7)); local b=frame:PointToWorldSpace(V(x,y,math.min(3.8,size.Z-1)))
						local hit,did=cast(a,b-a)
						if did then
							counts.entryRays+=1
							if hit then issue("FAIL","BLOCKED_OPEN_HOME_ENTRY",hit.Instance,hit.Position,"Entry lane of "..home:GetFullName()) end
						end
					end
				end
				for _,z in ipairs({-.9,.8,2.5,math.min(5.5,size.Z-1)}) do
					local floorPoint=frame:PointToWorldSpace(V(0,0,z))
					local hit,did=cast(floorPoint+frame.UpVector*.7,-frame.UpVector*1.6)
					if did then
						counts.floorRays+=1
						if not hit then issue("FAIL","OPEN_HOME_FLOOR_GAP",home,floorPoint,z<0 and "Immediately outside entrance" or "Interior entry lane")
						elseif math.abs(frame:PointToObjectSpace(hit.Position).Y)>.2 then
							issue("WARN","RAISED_OR_LOWERED_ENTRY_SURFACE",hit.Instance,hit.Position,"Expected floor of "..home:GetFullName())
						end
					end
					local top,checked=cast(floorPoint+frame.UpVector*.25,frame.UpVector*5.9)
					if checked then
						counts.headroomRays+=1
						if top then issue(z<=2.5 and "FAIL" or "WARN","ENTRY_HEADROOM_OBSTRUCTION",top.Instance,top.Position,"Vertical sample in "..home:GetFullName()) end
					end
				end
				counts.homesInspected+=1
			end
		end
	end
	for index=1,4 do
		local home=clueHomes[index]
		if requireCheck(home~=nil,"MISSING_CLUE_HOME",root,nil,"Clue"..index) then
			local frame=home:GetAttribute("HouseFloorFrame")
			requireCheck(home:GetAttribute("Enterable")==true,"CLUE_HOME_CLOSED",home,nil)
			if typeof(frame)=="CFrame" then requireCheck(math.abs(frame.Position.Y-origin.Y)<.25,"CLUE_NOT_GROUND_LEVEL",home,frame.Position) end
			local marker=home:FindFirstChild("PuzzleClueSurface",true)
			local gui=marker and marker:FindFirstChild("Level5ColourClue")
			local row={index=index,home=path(home),marker=path(marker)};table.insert(report.clues,row)
			if requireCheck(marker and marker:IsA("BasePart") and gui and gui:IsA("SurfaceGui"),"MISSING_CLUE_SURFACE",home,nil) then
				requireCheck(marker.Transparency==1 and not marker.CanCollide and not marker.CanQuery,"CLUE_CARRIER_NOT_INVISIBLE",marker,marker.Position)
				requireCheck(gui.Enabled and not gui.AlwaysOnTop and gui.Face==Enum.NormalId.Front,"CLUE_GUI_FACE",gui,marker.Position)
				if typeof(frame)=="CFrame" then requireCheck(marker.CFrame.LookVector:Dot(frame.LookVector)>.999,"CLUE_FACING_AWAY_FROM_ROOM",marker,marker.Position) end
				local images=0
				for _,object in ipairs(gui:GetDescendants()) do
					if object:IsA("GuiObject") then requireCheck(object.BackgroundTransparency>=.999,"OPAQUE_CLUE_POSTER_BACKGROUND",object,marker.Position) end
					if object:IsA("ImageLabel") or object:IsA("ImageButton") then
						images+=1;row.image=object.Image
						requireCheck(object.Image==(options.ExpectedClueAssets or EXPECTED_CLUES)[index],"WRONG_CLUE_IMAGE",object,marker.Position,object.Image)
						if report.context=="Client" then
							row.imageLoaded=object.IsLoaded
							if object.IsLoaded then counts.clientClueImagesLoaded+=1 else issue("WARN","CLUE_IMAGE_NOT_LOADED_YET",object,marker.Position,object.Image) end
						else row.imageLoaded="Client check required; SurfaceGui itself has no IsLoaded property" end
					end
				end
				requireCheck(images==1,"CLUE_IMAGE_COUNT",gui,marker.Position,"Expected1; actual"..images)
			end
		end
	end
	local gatesOwner=world:FindFirstChild("Level5SectionProgression")
	requireCheck(gatesOwner~=nil,"GATE_OWNER_MISSING",world,nil)
	local gateCount=0
	if gatesOwner then for _,gate in ipairs(gatesOwner:GetChildren()) do if gate:IsA("Model") and gate:GetAttribute("GateIndex")~=nil then gateCount+=1 end end end
	requireCheck(gateCount==7,"GATE_COUNT",gatesOwner or world,nil,"Expected7; actual"..gateCount)
	for index=1,math.min(7,#zones) do
		if not budget() then limited=true;break end
		local zone=zones[index];local gate=gatesOwner and gatesOwner:FindFirstChild("SectionGate"..index)
		local boundary=zone.hi.Z
		local row={index=index,z=boundary,unlocked=gate and gate:GetAttribute("Unlocked"),fullyOpen=gate and gate:GetAttribute("FullyOpen"),rays=0}
		table.insert(report.gates,row)
		if requireCheck(gate~=nil,"SECTION_GATE_MISSING",gatesOwner or world,origin+V(0,0,boundary),"Gate"..index) then
			local fullyOpen=gate:GetAttribute("FullyOpen")==true
			local moving=gate:GetAttribute("Unlocked")==true and not fullyOpen
			if moving then issue("WARN","GATE_TWEEN_IN_PROGRESS",gate,origin+V(0,0,boundary),"Door-area assertions deferred until settled") end
			for _,side in ipairs({-1,1}) do
				local leaf=gate:FindFirstChild("SlidingLeaf"..side)
				if requireCheck(leaf and leaf:IsA("BasePart"),"DOOR_LEAF_MISSING",gate,nil,tostring(side)) and not moving then
					requireCheck(fullyOpen and not leaf.CanCollide or not fullyOpen and leaf.CanCollide,"DOOR_COLLISION_STATE",leaf,leaf.Position)
				end
			end
			if not moving then
				for _,x in ipairs({-10.3,-6,-2,0,2,6,10.3}) do for _,y in ipairs({.35,3,6,10,13.4}) do
					local at=origin+V(x,y,boundary);local hit,did=cast(at-V(0,0,1.8),V(0,0,3.6))
					if did then
						counts.doorRays+=1;row.rays+=1
						if fullyOpen and hit then issue("FAIL","OPEN_GATE_PASSAGE_BLOCKED",hit.Instance,hit.Position,"Gate"..index)
						elseif not fullyOpen and not hit then issue("FAIL","CLOSED_GATE_COVERAGE_GAP",gate,at) end
					end
				end end
			end
			-- Sample each side's actual zone envelope separately, avoiding invented max-width/max-height corners.
			for _,sideZone in ipairs({zone,zones[index+1]}) do
				if sideZone then
					local height=sideZone.hi.Y-sideZone.lo.Y
					for _,fraction in ipairs({.02,.15,.3,.5,.7,.85,.98}) do
						local x=sideZone.lo.X+(sideZone.hi.X-sideZone.lo.X)*fraction
						for _,y in ipairs({sideZone.lo.Y+.5,3,8,13.4,15.5,sideZone.lo.Y+height*.5,sideZone.hi.Y-.5}) do
							if y>sideZone.lo.Y and y<sideZone.hi.Y and not (math.abs(x)<11 and y>0 and y<14) then
								local at=origin+V(x,y,boundary);local hit,did=cast(at-V(0,0,1.8),V(0,0,3.6))
								if did then
									counts.boundaryRays+=1;row.rays+=1
									if not hit then issue("FAIL","SECTION_BOUNDARY_HOLE",sideZone.model,at,"Outside the22x14 doorway at gate"..index) end
								end
							end
						end
					end
				end
			end
		end
	end
	local budgets=options.ReviewBudgets or {baseParts=40000,lights=750,surfaceGuis=250}
	report.reviewBudgets=budgets
	for key,limit in pairs(budgets) do
		if type(limit)=="number" and counts[key] and counts[key]>limit then issue("WARN","REVIEW_BUDGET_EXCEEDED",root,nil,key.."="..counts[key].." > "..limit.."; review threshold, not a proven device limit") end
	end
	if report.context~="Client" then table.insert(report.unverified,"client clue ImageLabel.IsLoaded") end
	if limited then issue("WARN","INSPECTION_BUDGET_REACHED",root,nil,"Some geometry samples omitted; raise bounded limits for a follow-up if needed") end
	report.rayCount=rays;report.elapsedSeconds=os.clock()-started;report.limited=limited
	report.status=report.failures>0 and "FAIL" or (limited and "INCOMPLETE" or "PASS_STATIC_SAMPLED_CHECKS")
	return report
end
return QA
