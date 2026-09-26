-- Client-only guard for the exact owned Window Watcher. Official server Animator
-- playback/timing stays authoritative. Never exposes a loaded-but-unevaluated
-- bind pose to late joiners; no camera, Bone.Transform or server state writes.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ContentProvider=game:GetService("ContentProvider")
assert(RunService:IsClient(),"WindowWatcherVisualClient must run on the client")
local SHA="cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"
local IDS={WatchingIdle="rbxassetid://123386867650430",SlowWindowLean="rbxassetid://85635358459792",GlassTap="rbxassetid://85948818863545"}
local NAMES={"Root","Hips","LeftUpLeg","LeftLeg","LeftFoot","LeftToeBase","RightUpLeg","RightLeg","RightFoot","RightToeBase",
	"Spine02","Spine01","Spine","LeftShoulder","LeftArm","LeftForeArm","LeftHand","RightShoulder","RightArm","RightForeArm","RightHand",
	"neck","Head","head_end","headfront"}
local expected={};for _,name in ipairs(NAMES) do expected[name]=true end
local owned={}
local renderConnection,discoveryConnection,destroyConnection
local frameNumber=0
local stopped=false
local preloadThread,preloadTimeout,preloadDone
local preloadObjects={}

local function diagnostic(actor,key,value)
	if actor:GetAttribute(key)~=value then actor:SetAttribute(key,value) end
end
local function inScope(actor)
	if not actor or not actor:IsA("Model") or actor.Name~="WindowWatcher"
		or actor:GetAttribute("Level5WindowWatcherOwned")~=true or actor:GetAttribute("SourceGlbSha256")~=SHA then return false end
	local owner=actor.Parent;local world=owner and owner.Parent
	return owner and owner.Name=="Level5WindowWatcherEncounters" and owner:GetAttribute("Level5WindowWatcherOwned")==true
		and world and world.Name=="Level 5 Generated World" and world:GetAttribute("Level5_MapOnly")==true and world.Parent==workspace
end
local function localVisibility(state,reveal)
	for part,original in pairs(state.parts) do
		if part.Parent then part.LocalTransparencyModifier=reveal and original or 1 end
	end
end
local function release(actor,state)
	localVisibility(state,true)
	owned[actor]=nil
	if actor.Parent then
		diagnostic(actor,"WindowWatcherVisualReady",false)
		diagnostic(actor,"WindowWatcherVisualStatus","DETACHED")
	end
end
local function captureRig(actor,state)
	local bones,seen,partCount={}, {},0
	for _,object in ipairs(actor:GetDescendants()) do
		if object:IsA("BasePart") then
			partCount+=1
			if state.parts[object]==nil then state.parts[object]=object.LocalTransparencyModifier end
			object.LocalTransparencyModifier=1
		elseif object:IsA("Bone") then
			if not expected[object.Name] or seen[object.Name] then return nil,"Unexpected or duplicate Bone: "..object.Name end
			seen[object.Name]=true;table.insert(bones,object)
		end
	end
	if partCount>1 then return nil,"Expected the exact one-mesh Watcher rig" end
	if partCount~=1 or #bones~=25 then return nil,nil end -- streaming may still be delivering the exact rig
	state.bones=bones
	return bones,nil
end
local function poseEvaluated(bones)
	for _,bone in ipairs(bones) do
		local transform=bone.Transform
		local _,angle=transform:ToAxisAngle()
		if transform.Position.Magnitude>.0001 or math.abs(angle)>.0001 then return true end
	end
	return false
end
local function resetTrack(state)
	state.track=nil;state.clip=nil;state.qualified=false;state.firstFrame=nil;state.firstTime=nil
end
local function update(actor,state)
	if not inScope(actor) then release(actor,state);return end
	local owner=actor.Parent
	local bones=state.bones
	if bones then for _,bone in ipairs(bones) do if not bone:IsDescendantOf(actor) then bones=nil;state.bones=nil;break end end end
	local rigError
	if not bones then bones,rigError=captureRig(actor,state) end
	if not bones then
		localVisibility(state,false);resetTrack(state)
		diagnostic(actor,"WindowWatcherVisualReady",false)
		diagnostic(actor,"WindowWatcherVisualError",rigError)
		diagnostic(actor,"WindowWatcherVisualStatus",rigError and "INVALID_RIG" or "WAITING_FOR_RIG")
		return
	end
	local controller=actor:FindFirstChildOfClass("AnimationController")
	local animator=controller and controller:FindFirstChildOfClass("Animator")
	local clip=actor:GetAttribute("PreviewClip")
	local wanted=IDS[clip]
	local track,count=nil,0
	if animator and wanted then
		for _,candidate in ipairs(animator:GetPlayingAnimationTracks()) do
			if candidate.IsPlaying and candidate.WeightCurrent>.0001 then
				count+=1
				if candidate.Animation and candidate.Animation.AnimationId==wanted and candidate.Length>0 then track=candidate end
			end
		end
	end
	local ready=false
	if track and count==1 then
		if state.track~=track or state.clip~=clip then
			state.track=track;state.clip=clip;state.firstFrame=frameNumber;state.firstTime=track.TimePosition;state.qualified=false
		end
		local evaluated=poseEvaluated(bones)
		if frameNumber>state.firstFrame and math.abs(track.TimePosition-state.firstTime)>.000001 and evaluated then state.qualified=true end
		ready=state.qualified and evaluated
	else resetTrack(state) end
	local visible=owner:GetAttribute("Visible")==true
	local gazeHidden=actor:GetAttribute("WindowWatcherGazeHidden")==true
	localVisibility(state,visible and ready and not gazeHidden)
	diagnostic(actor,"WindowWatcherVisualReady",ready)
	diagnostic(actor,"WindowWatcherVisualError",nil)
	diagnostic(actor,"WindowWatcherVisualStatus",ready and (gazeHidden and "GAZE_HIDDEN" or (visible and "VISIBLE" or "POSE_READY_HIDDEN")) or "WAITING_FOR_TRACK")
end
local function ensureRenderConnection()
	if renderConnection or stopped then return end
	renderConnection=RunService.RenderStepped:Connect(function()
		frameNumber+=1
		for actor,state in pairs(owned) do
			local ok,detail=pcall(update,actor,state)
			if not ok then
				localVisibility(state,false);resetTrack(state)
				diagnostic(actor,"WindowWatcherVisualReady",false)
				diagnostic(actor,"WindowWatcherVisualStatus","ERROR")
				diagnostic(actor,"WindowWatcherVisualError",tostring(detail))
			end
		end
		if not next(owned) then renderConnection:Disconnect();renderConnection=nil end
	end)
end
local function discover(object)
	if stopped then return end
	local actor=object
	while actor and actor~=workspace do
		if inScope(actor) then
			local state=owned[actor]
			if not state then
				state={parts={}};owned[actor]=state
				diagnostic(actor,"WindowWatcherVisualReady",false)
				diagnostic(actor,"WindowWatcherVisualStatus","WAITING_FOR_RIG")
				captureRig(actor,state) -- hide synchronously, before the next render
			else state.bones=nil end -- a streamed descendant invalidates the cached exact bone set
			ensureRenderConnection();return
		end
		actor=actor.Parent
	end
end

-- Discover before prefetching so an already visible late-join actor is hidden
-- immediately; server-created Animators still play independently of this guard.
discoveryConnection=workspace.DescendantAdded:Connect(discover)
for _,object in ipairs(workspace:GetDescendants()) do
	if object:IsA("Model") and object.Name=="WindowWatcher" then discover(object) end
end

local function destroyPreloadObjects()
	for _,animation in ipairs(preloadObjects) do animation:Destroy() end
	table.clear(preloadObjects)
end
local function cancel(thread)
	if thread and coroutine.status(thread)~="dead" then pcall(task.cancel,thread) end
end
script:SetAttribute("WindowWatcherVisualPreloadStatus","LOADING")
for name,id in pairs(IDS) do
	local animation=Instance.new("Animation");animation.Name=name;animation.AnimationId=id
	table.insert(preloadObjects,animation)
end
preloadThread=task.spawn(function()
	local failed={}
	local ok,detail=pcall(function()
		ContentProvider:PreloadAsync(preloadObjects,function(id,status)
			if status~=Enum.AssetFetchStatus.Success then table.insert(failed,tostring(id)..": "..tostring(status)) end
		end)
	end)
	if stopped or preloadDone then return end
	preloadDone=true;cancel(preloadTimeout)
	script:SetAttribute("WindowWatcherVisualPreloadStatus",ok and (#failed==0 and "READY" or "PARTIAL") or "ERROR")
	script:SetAttribute("WindowWatcherVisualPreloadError",not ok and tostring(detail) or (#failed>0 and table.concat(failed,"; ") or nil))
	destroyPreloadObjects()
end)
if not preloadDone then
	preloadTimeout=task.delay(20,function()
		if stopped or preloadDone then return end
		preloadDone=true;cancel(preloadThread);destroyPreloadObjects()
		script:SetAttribute("WindowWatcherVisualPreloadStatus","TIMED_OUT")
		script:SetAttribute("WindowWatcherVisualPreloadError","Prefetch exceeded 20 seconds; the guard still waits for real track readiness")
	end)
end
destroyConnection=script.Destroying:Connect(function()
	if stopped then return end
	stopped=true;cancel(preloadThread);cancel(preloadTimeout);destroyPreloadObjects()
	if discoveryConnection then discoveryConnection:Disconnect() end
	if renderConnection then renderConnection:Disconnect();renderConnection=nil end
	for actor,state in pairs(owned) do release(actor,state) end
	if destroyConnection then destroyConnection:Disconnect() end
end)
