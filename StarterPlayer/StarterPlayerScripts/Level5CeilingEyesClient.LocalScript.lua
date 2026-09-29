-- Local visual tracking for the fixed exit-ceiling eye pairs. No remotes,
-- damage, camera/FOV, lighting or server-owned geometry position changes.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
assert(RunService:IsClient(),"Level5CeilingEyesClient must run locally")
local player=Players.LocalPlayer
local MAX_RIGS=64
local MAX_TARGET_DISTANCE=250
local SELECT_INTERVAL=.1
local DISCOVERY_INTERVAL=.5
local SMOOTH_RATE=8
local V=Vector3.new
local state={world=nil,folder=nil,rigs={},active=false,stopped=false,selectElapsed=0,discoverElapsed=DISCOVERY_INTERVAL}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e7 end
local function vector(v) return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function frame(cf)
	if typeof(cf)~="CFrame" then return false end
	for _,n in ipairs({cf:GetComponents()}) do if not finite(n) then return false end end
	return true
end
local function diagnostic(object,key,value)
	if object and object.Parent and object:GetAttribute(key)~=value then object:SetAttribute(key,value) end
end
local function contains(point,lo,hi)
	return vector(point) and point.X>=lo.X and point.X<=hi.X and point.Y>=lo.Y and point.Y<=hi.Y and point.Z>=lo.Z and point.Z<=hi.Z
end
-- BEGIN PURE TARGET_SELECTION
local function chooseTarget(candidates,currentId,loads,index)
	local nearest=math.huge
	for _,candidate in ipairs(candidates) do nearest=math.min(nearest,candidate.distance) end
	local winner,best=nil,math.huge
	for _,candidate in ipairs(candidates) do
		-- Keep each pair oriented toward nearby people. The assignment penalty
		-- distributes similar-distance group members across different eye pairs;
		-- it never recruits a far player just to equalize a global count.
		if candidate.distance<=nearest+48 then
			local cost=candidate.distance+(loads[candidate.userId] or 0)*6
				-(candidate.userId==currentId and 8 or 0)+((index*37+candidate.userId%29)%17)*.03
			if cost<best or cost==best and winner and candidate.userId<winner.userId then winner,best=candidate,cost end
		end
	end
	return winner
end
-- END PURE TARGET_SELECTION
local function intact(entry)
	if not entry.rig.Parent or not state.folder or entry.rig.Parent~=state.folder
		or not entry.rig.PrimaryPart or not entry.rig.PrimaryPart:IsDescendantOf(entry.rig) then return false end
	for part in pairs(entry.rest) do if part.Parent~=entry.rig then return false end end
	return true
end
local function restore(entry)
	if intact(entry) then
		-- Reapply authored local frames once, also repairing a partial stream-in
		-- that delivered new parts after old client-only rotations.
		for part,localFrame in pairs(entry.rest) do part.CFrame=entry.home*localFrame end
		entry.rig:PivotTo(entry.home)
	end
	entry.current=entry.home;entry.target=nil;entry.targetId=0
	diagnostic(entry.rig,"TargetUserId",0)
end
local function clear()
	for _,entry in ipairs(state.rigs) do restore(entry) end
	table.clear(state.rigs)
	diagnostic(state.folder,"TrackingActive",false)
	diagnostic(state.folder,"TrackingReadyCount",0)
	diagnostic(state.folder,"TrackingStatus","DETACHED")
	state.world=nil;state.folder=nil;state.active=false
end
local function currentFolder()
	local world=workspace:FindFirstChild("Level 5 Generated World")
	if not world or world:GetAttribute("Level5_MapOnly")~=true then return nil,nil end
	local architecture=world:FindFirstChild("Level5_IndoorSuburbs")
	local lastHouse=architecture and architecture:FindFirstChild("H_LastHouse")
	local folder=lastHouse and lastHouse:FindFirstChild("ExitCeilingEyes")
	return world,folder
end
local function discover()
	local world,folder=currentFolder()
	if state.folder~=folder or state.world~=world then clear();state.world=world;state.folder=folder end
	if not folder then return end
	local old={};for _,entry in ipairs(state.rigs) do old[entry.rig]=entry end
	local nextRigs,seen={},{}
	for _,rig in ipairs(folder:GetChildren()) do
		if #nextRigs>=MAX_RIGS then break end
		if not rig:IsA("Model") or rig:GetAttribute("Level5CeilingEye")~=true then continue end
		local home,index=rig:GetAttribute("HomeCFrame"),rig:GetAttribute("EyeIndex")
		if not frame(home) or not finite(index) or index%1~=0 or index<1 or index>MAX_RIGS or seen[index]
			or rig:GetAttribute("ExpectedPartCount")~=4 or rig:GetAttribute("ExpectedMeshCount")~=4 or not rig.PrimaryPart then continue end
		local rest={};local partCount=0;local valid=true
		for _,part in ipairs(rig:GetChildren()) do
			if part:IsA("BasePart") then
				partCount+=1;local localFrame=part:GetAttribute("HomeLocalCFrame")
				local mesh=part:FindFirstChild("EyeEllipsoid")
				if not frame(localFrame) or not part.Anchored or part.CanCollide or part.CanTouch or part.CanQuery
					or not mesh or not mesh:IsA("SpecialMesh") or mesh.MeshType~=Enum.MeshType.Sphere then valid=false;break end
				rest[part]=localFrame
			end
		end
		if not valid or partCount~=4 then continue end
		seen[index]=true
		local entry=old[rig]
		local changed=not entry or entry.home~=home
		if entry and not changed then
			for part,cf in pairs(rest) do if entry.rest[part]~=cf then changed=true;break end end
		end
		if changed then
			if entry then restore(entry) end
			entry={rig=rig,home=home,current=home,index=index,rest=rest,target=nil,targetId=0}
			restore(entry)
		end
		old[rig]=nil;table.insert(nextRigs,entry)
	end
	for _,entry in pairs(old) do restore(entry) end
	table.sort(nextRigs,function(a,b) return a.index<b.index end)
	state.rigs=nextRigs
	diagnostic(folder,"TrackingReadyCount",#nextRigs)
	diagnostic(folder,"TrackingControllerVersion","2026-09-26.1")
	diagnostic(folder,"TrackingStatus",#nextRigs==0 and "WAITING_FOR_RIGS" or (state.active and "TRACKING" or "REST"))
end
local function livingParticipant(subject,lo,hi)
	if subject:GetAttribute("InRound")~=true or subject:GetAttribute("Escaped")==true
		or subject:GetAttribute("Spectating")==true then return nil end
	local character=subject.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local head=character and character:FindFirstChild("Head")
	if not humanoid or humanoid.Health<=0 or not root or not root:IsA("BasePart")
		or not head or not head:IsA("BasePart") or not contains(root.Position,lo,hi) then return nil end
	return {userId=subject.UserId,head=head,humanoid=humanoid,character=character}
end
local function region()
	local folder=state.folder
	if not folder or not folder:IsDescendantOf(workspace) then return nil,nil end
	local lo,hi=folder:GetAttribute("TrackingBoundsMin"),folder:GetAttribute("TrackingBoundsMax")
	if not vector(lo) or not vector(hi) or lo.X>=hi.X or lo.Y>=hi.Y or lo.Z>=hi.Z
		or (hi-lo).Magnitude>1000 then return nil,nil end
	return lo,hi
end
local function selectTargets(lo,hi)
	local people={}
	for _,subject in ipairs(Players:GetPlayers()) do
		local person=livingParticipant(subject,lo,hi)
		if person then table.insert(people,person) end
	end
	table.sort(people,function(a,b) return a.userId<b.userId end)
	local loads={}
	for _,entry in ipairs(state.rigs) do
		local candidates={}
		for _,person in ipairs(people) do
			local distance=(person.head.Position-entry.home.Position).Magnitude
			if distance>=1 and distance<=MAX_TARGET_DISTANCE then
				table.insert(candidates,{userId=person.userId,distance=distance,head=person.head,humanoid=person.humanoid,character=person.character})
			end
		end
		local selected=chooseTarget(candidates,entry.targetId,loads,entry.index)
		entry.target=selected;entry.targetId=selected and selected.userId or 0
		if selected then loads[selected.userId]=(loads[selected.userId] or 0)+1 end
		diagnostic(entry.rig,"TargetUserId",entry.targetId)
	end
	diagnostic(state.folder,"TrackingParticipantCount",#people)
end
local function step(dt)
	state.discoverElapsed+=dt
	if state.discoverElapsed>=DISCOVERY_INTERVAL then state.discoverElapsed=0;discover() end
	local lo,hi=region()
	local active=lo~=nil and workspace:GetAttribute("SelectedLevel")==5 and workspace:GetAttribute("RoundActive")==true
		and livingParticipant(player,lo,hi)~=nil
	if not active then
		if state.active then
			for _,entry in ipairs(state.rigs) do restore(entry) end
			diagnostic(state.folder,"TrackingActive",false);diagnostic(state.folder,"TrackingParticipantCount",0)
			diagnostic(state.folder,"TrackingStatus","REST")
		end
		state.active=false;state.selectElapsed=SELECT_INTERVAL
		return
	end
	state.active=true;state.selectElapsed+=dt
	diagnostic(state.folder,"TrackingActive",true)
	diagnostic(state.folder,"TrackingStatus",#state.rigs>0 and "TRACKING" or "WAITING_FOR_RIGS")
	if state.selectElapsed>=SELECT_INTERVAL then state.selectElapsed=0;selectTargets(lo,hi) end
	local alpha=1-math.exp(-SMOOTH_RATE*math.min(dt,.1))
	for _,entry in ipairs(state.rigs) do
		if not intact(entry) then state.discoverElapsed=DISCOVERY_INTERVAL;continue end
		local wanted=entry.home
		local target=entry.target
		if target and target.head:IsDescendantOf(workspace) and target.humanoid.Health>0 then
			local delta=target.head.Position-entry.home.Position
			if delta.Magnitude>=1 and delta.Magnitude<=MAX_TARGET_DISTANCE then
				local up=entry.home.UpVector
				if math.abs(delta.Unit:Dot(up))>.98 then up=V(0,0,1);if math.abs(delta.Unit:Dot(up))>.98 then up=V(1,0,0) end end
				wanted=CFrame.lookAt(entry.home.Position,target.head.Position,up)
			end
		end
		local interpolated=entry.current:Lerp(wanted,alpha)
		-- Pin the mount even after interpolation; only rotation is owned here.
		local nextFrame=CFrame.new(entry.home.Position)*interpolated.Rotation
		local _,difference=entry.current:ToObjectSpace(nextFrame):ToAxisAngle()
		if math.abs(difference)>.00005 then entry.rig:PivotTo(nextFrame);entry.current=nextFrame end
	end
end
local renderConnection
renderConnection=RunService.RenderStepped:Connect(function(dt)
	if state.stopped then return end
	local ok,err=pcall(step,dt)
	if not ok then
		diagnostic(script,"TrackingError",tostring(err))
		clear();state.discoverElapsed=DISCOVERY_INTERVAL
	end
end)
script.Destroying:Connect(function()
	if state.stopped then return end;state.stopped=true
	if renderConnection then renderConnection:Disconnect() end
	clear()
end)
