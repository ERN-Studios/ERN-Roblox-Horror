local Runner=(function()
-- Explicitly invoked native traversal observer. Loading this module does nothing.
-- Only Humanoid:MoveTo is used: no PivotTo, teleport, WalkSpeed, Jump, gate or round writes.
local Runner = {}
local active = setmetatable({}, {__mode="k"})
local function xyz(v) return {math.round(v.X*1000)/1000,math.round(v.Y*1000)/1000,math.round(v.Z*1000)/1000} end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Runner.Start(options)
	options=options or {}
	local RunService=game:GetService("RunService")
	local Players=game:GetService("Players")
	assert(RunService:IsRunning(),"Traversal requires a running native round")
	local world=options.World or workspace:FindFirstChild("Level 5 Generated World")
	assert(world and world:IsA("Model") and world.Parent==workspace,"Current generated world required")
	local player=options.Player or (options.UserId and Players:GetPlayerByUserId(options.UserId))
	assert(player and player:IsA("Player") and player.Parent==Players,"Explicit QA Player/UserId required")
	if RunService:IsClient() then assert(player==Players.LocalPlayer,"Client traversal may control only LocalPlayer") end
	assert(not active[player],"A traversal owned by this helper is already active for that player")
	local character=assert(player.Character,"QA character missing")
	local humanoid=assert(character:FindFirstChildOfClass("Humanoid"),"QA Humanoid missing")
	local root=assert(character:FindFirstChild("HumanoidRootPart"),"QA root missing")
	assert(humanoid.Health>0 and player:GetAttribute("InRound")==true and workspace:GetAttribute("SelectedLevel")==5
		and workspace:GetAttribute("RoundActive")==true,"Living active Level 5 participant required")
	assert(player:GetAttribute("RoundEntryControlsReady")==true,"Wait for the normal entry flow/controls")
	assert(player:GetAttribute("Level5ColourLockOpen")~=true,"Close the puzzle UI before traversal")
	local architecture=world:FindFirstChild("Level5_IndoorSuburbs")
	local source=options.WaypointsJSON or world:GetAttribute("MainRouteWaypointsJson") or (architecture and architecture:GetAttribute("MainRouteWaypointsJson"))
	assert(type(source)=="string" and #source<=100000,"Provide bounded MainRouteWaypointsJson or WaypointsJSON")
	local data=game:GetService("HttpService"):JSONDecode(source)
	assert(type(data)=="table" and data.space=="world" and type(data.points)=="table","Expected {space='world',points={{x,y,z},...}}")
	assert(#data.points>=2 and #data.points<=120,"Use 2–120 explicitly planned waypoints")
	local points={}
	local maxGap=math.clamp(options.MaxSegmentLength or 100,10,150)
	for index,value in ipairs(data.points) do
		assert(type(value)=="table" and #value==3 and finite(value[1]) and finite(value[2]) and finite(value[3]),"Invalid XYZ waypoint "..index)
		local point=Vector3.new(value[1],value[2],value[3]);table.insert(points,point)
		if index>1 then assert((point-points[index-1]).Magnitude<=maxGap,"Waypoint gap too long; plan smaller segments at "..index) end
	end
	local startTolerance=math.clamp(options.StartTolerance or 8,1,12)
	assert((root.Position-points[1]).Magnitude<=startTolerance,"Player is not at route start; helper never teleports")
	local maxDuration=math.clamp(options.MaxDuration or 300,10,600)
	local radius=math.clamp(options.ArrivalRadius or 2,1,3)
	-- Waypoints describe the walkable floor. The character root normally stays above it.
	local heightTolerance=math.clamp(options.HeightTolerance or 4,1,5)
	local started=os.clock()
	local report={version="2026-09-26.native-waypoints.1",status="RUNNING",playerUserId=player.UserId,worldGeneration=world:GetAttribute("Level5_Generation"),
		method="Humanoid MoveTo through supplied world-coordinate waypoints, without teleport/Jump/WalkSpeed/gate changes",
		start=xyz(root.Position),waypointCount=#points,arrivalRadius=radius,heightTolerance=heightTolerance,segments={},samples={},samplesOmitted=0,
		unverified={"paths outside supplied segments","another account/device","full-volume coverage of every interior"}}
	local connections={}
	local finished=false
	local index=1
	local segmentStart=started
	local segmentFrom=root.Position
	local lastMove=started
	local lastPosition=root.Position
	local lastTime=started
	local sampleDue=started
	local elapsed=0
	local distanceTravelled=0
	local API={}
	local function finish(status,reason)
		if finished then return end;finished=true;active[player]=nil
		for _,connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
		report.status=status;report.reason=reason;report.elapsed=os.clock()-started
		report.finalPosition=root.Parent and xyz(root.Position) or nil
		report.completedWaypoints=#report.segments;report.distanceTravelled=distanceTravelled
		if root.Parent and humanoid.Parent and humanoid.Health>0 then humanoid:MoveTo(root.Position) end
		if type(options.OnFinished)=="function" then
			local ok,detail=pcall(options.OnFinished,report)
			if not ok then report.reportCallbackError=tostring(detail) end
		end
	end
	function API.GetReport() return report end
	function API.Stop() finish("ABORTED","Explicit helper stop") end
	active[player]=API
	table.insert(connections,world.Destroying:Connect(function() finish("ABORTED","Round world destroyed") end))
	table.insert(connections,Players.PlayerRemoving:Connect(function(leaving) if leaving==player then finish("ABORTED","QA player left") end end))
	local function step(now)
		if player.Character~=character or not root.Parent or not humanoid.Parent or humanoid.Health<=0
			or player:GetAttribute("InRound")~=true or workspace:GetAttribute("SelectedLevel")~=5
			or workspace:GetAttribute("RoundActive")~=true or world.Parent~=workspace then finish("ABORTED","Character/round changed");return end
		if player:GetAttribute("RoundEntryControlsReady")~=true or player:GetAttribute("Level5ColourLockOpen")==true then finish("ABORTED","Normal controls are unavailable or the puzzle UI opened");return end
		if now-started>maxDuration then finish("INCOMPLETE","Bounded traversal duration reached");return end
		local position=root.Position
		local dt=math.max(.01,now-lastTime)
		local delta=(position-lastPosition).Magnitude
		if delta>math.max(12,humanoid.WalkSpeed*dt*3+3) then
			report.discontinuity={from=xyz(lastPosition),to=xyz(position),seconds=dt}
			finish("INVALIDATED","External discontinuous movement; cannot claim continuous walking");return
		end
		distanceTravelled+=delta;lastPosition=position;lastTime=now
		local target=points[index]
		local offset=target-position
		local remaining=Vector3.new(offset.X,0,offset.Z).Magnitude
		local heightError=math.abs(offset.Y)
		report.activeWaypoint=index;report.distanceToTarget=remaining;report.elapsed=now-started
		if now>=sampleDue then
			sampleDue=now+1
			if #report.samples<160 then table.insert(report.samples,{t=math.round((now-started)*100)/100,point=index,position=xyz(position),remaining=math.round(remaining*100)/100,state=tostring(humanoid:GetState())})
			else report.samplesOmitted+=1 end
		end
		if remaining<=radius and heightError<=heightTolerance then
			table.insert(report.segments,{index=index,target=xyz(target),arrived=xyz(position),elapsed=now-segmentStart,horizontalError=remaining,heightError=heightError})
			index+=1
			if index>#points then finish("PASS_WAYPOINT_TRAVERSAL","All supplied targets reached with normal MoveTo");return end
			segmentStart=now;segmentFrom=position;lastMove=now;humanoid:MoveTo(points[index]);return
		end
		local expected=(target-segmentFrom).Magnitude/math.max(humanoid.WalkSpeed,1)
		local timeout=math.clamp(expected*2+4,6,35)
		if now-segmentStart>timeout then
			local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances={world};params.RespectCanCollide=true
			local hit=workspace:Raycast(position,target-position,params)
			report.blocked={index=index,from=xyz(position),target=xyz(target),elapsed=now-segmentStart,
				firstRayHit=hit and hit.Instance:GetFullName() or nil,hitPosition=hit and xyz(hit.Position) or nil}
			finish("FAIL","Waypoint was not reached within its bounded movement deadline");return
		end
		-- Refresh normal MoveTo before Roblox's own eight-second expiry; do not alter target/state.
		if now-lastMove>=3 then lastMove=now;humanoid:MoveTo(target) end
	end
	table.insert(connections,RunService.Heartbeat:Connect(function(dt)
		if finished then return end;elapsed+=dt;if elapsed<.1 then return end;elapsed=0
		local ok,detail=pcall(step,os.clock())
		if not ok then report.error=tostring(detail);finish("FAIL","Observer error") end
	end))
	humanoid:MoveTo(points[1])
	return API
end
return Runner

end)()
local H=game:GetService("HttpService")
Runner.Start({World=workspace["Level 5 Generated World"],Player=game.Players.LocalPlayer,WaypointsJSON=script:GetAttribute("Waypoints"),MaxDuration=120,OnFinished=function(report)script:SetAttribute("Report",H:JSONEncode(report))end})
