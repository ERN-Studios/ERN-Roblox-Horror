-- QA-only render timing. Reads native client state and observes RenderStepped; no quality/camera/world changes.
local QA = {}
local function rounded(n) return math.round(n*100)/100 end
local function memory()
	local ok,value=pcall(function() return game:GetService("Stats"):GetTotalMemoryUsageMb() end)
	return ok and rounded(value) or nil
end
local function counts(world)
	local result={instances=0,baseParts=0,lights=0,enabledLights=0,meshParts=0,surfaceGuis=0,decals=0}
	if not world then return result end
	for _,object in ipairs(world:GetDescendants()) do
		result.instances+=1
		if object:IsA("BasePart") then result.baseParts+=1 end
		if object:IsA("MeshPart") then result.meshParts+=1 end
		if object:IsA("Light") then result.lights+=1;if object.Enabled then result.enabledLights+=1 end end
		if object:IsA("SurfaceGui") then result.surfaceGuis+=1 end
		if object:IsA("Decal") then result.decals+=1 end
	end
	return result
end
function QA.Start(options)
	options=options or {}
	local RunService=game:GetService("RunService")
	assert(RunService:IsClient() and RunService:IsRunning(),"Use the real running native client")
	local player=assert(game:GetService("Players").LocalPlayer,"LocalPlayer missing")
	local world=options.World or workspace:FindFirstChild("Level 5 Generated World")
	assert(world and world.Parent==workspace,"Wait for the current generated world")
	local seconds=math.clamp(options.Seconds or 15,5,45)
	local camera=workspace.CurrentCamera
	local viewport=camera and camera.ViewportSize or Vector2.zero
	local char=player.Character;local root=char and char:FindFirstChild("HumanoidRootPart")
	local quality
	pcall(function() quality=tostring(UserSettings():GetService("UserGameSettings").SavedQualityLevel) end)
	local report={version="2026-09-26.client-render.1",status="SAMPLING",context=RunService:IsStudio() and "Studio native client" or "Published client",
		requestedSeconds=seconds,viewport={viewport.X,viewport.Y},quality=quality,worldCountsStart=counts(world),memoryMbStart=memory(),
		startPosition=root and {root.Position.X,root.Position.Y,root.Position.Z} or nil,
		scope="Observed RenderStepped intervals on this client/view; timing includes Studio/OS load and is not a GPU profiler or physical-mobile benchmark",
		unverified={"physical mobile/tablet","multiplayer server load","unvisited views","published-server asset permissions"}}
	local frames={};local sum=0;local maximum=0;local over33=0;local over50=0;local over100=0
	local started=os.clock();local finished=false;local connection;local api={}
	local function finish(reason,status)
		if finished then return end;finished=true
		if connection then connection:Disconnect() end
		local elapsed=os.clock()-started
		report.status=status or "COMPLETE_MEASUREMENT";report.reason=reason;report.wallSeconds=rounded(elapsed)
		report.frames=#frames;report.renderIntervalSeconds=rounded(sum);report.memoryMbEnd=memory();report.worldCountsEnd=counts(world)
		if #frames>0 and sum>0 then
			table.sort(frames)
			local function percentile(q) return rounded(frames[math.clamp(math.ceil(#frames*q),1,#frames)]*1000) end
			report.fps=#frames/sum;report.meanFrameMs=rounded(sum/#frames*1000);report.p50FrameMs=percentile(.5)
			report.p95FrameMs=percentile(.95);report.p99FrameMs=percentile(.99);report.maxFrameMs=rounded(maximum*1000)
			report.framesOver33_3Ms=over33;report.framesOver50Ms=over50;report.framesOver100Ms=over100
			report.percentOver33_3Ms=rounded(over33/#frames*100)
		else report.status="INCOMPLETE_NO_FRAMES" end
		local currentCamera=workspace.CurrentCamera
		report.endViewport=currentCamera and {currentCamera.ViewportSize.X,currentCamera.ViewportSize.Y} or nil
		local r=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		report.endPosition=r and {r.Position.X,r.Position.Y,r.Position.Z} or nil
		if type(options.OnFinished)=="function" then local ok,err=pcall(options.OnFinished,report);if not ok then report.callbackError=tostring(err) end end
	end
	function api.GetReport() return report end
	function api.Stop() finish("Explicit stop before scheduled completion","INCOMPLETE_STOPPED_EARLY") end
	connection=RunService.RenderStepped:Connect(function(dt)
		if finished then return end
		if world.Parent~=workspace or player.Character~=char then finish("World or character changed","INCOMPLETE_CONTEXT_CHANGED");return end
		if dt>0 and dt<math.huge and dt==dt then
			table.insert(frames,dt);sum+=dt;maximum=math.max(maximum,dt)
			if dt>1/30 then over33+=1 end;if dt>.05 then over50+=1 end;if dt>.1 then over100+=1 end
		end
		report.framesSoFar=#frames;report.secondsSoFar=rounded(os.clock()-started)
		if os.clock()-started>=seconds then finish("Scheduled sampling interval ended")
		elseif #frames>=20000 then finish("Bounded sample count reached","INCOMPLETE_SAMPLE_LIMIT") end
	end)
	return api
end
return QA
