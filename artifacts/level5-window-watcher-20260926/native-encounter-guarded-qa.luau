-- Guard-aware native Play-mode observer (the original failure report is preserved).
-- Client render safety is checked every render; server invariants stay unchanged.
-- Native Play-mode observer. Execute this source as a module, then call Start.
-- The SAME observer runs on server and client; each context writes its own
-- temporary QA folder. It never modifies an actor, track, roster, clock, RNG,
-- player position, production attribute or production callback.
-- Root must enter via Level5DevStart/normal queue and perform normal cleanup.
local QA={}
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local ORIGIN=Vector3.new(17000,24,0)
local WORLD="Level 5 Generated World"
local OWNER="Level5WindowWatcherEncounters"
local IDS={WatchingIdle="rbxassetid://123386867650430",SlowWindowLean="rbxassetid://85635358459792",GlassTap="rbxassetid://85948818863545"}
local SPEC={
	FarUpperWindow={clip="WatchingIdle",depth=.95,length=6},
	MiddleCourtWindow={clip="SlowWindowLean",depth=.95,length=5},
	NearGroundWindow={clip="GlassTap",depth=1.90,length=4},
}
local function components(frame) return {frame:GetComponents()} end
local function errorBetween(a,b)
	local x,y=components(a),components(b);local maximum=0
	for i=1,12 do maximum=math.max(maximum,math.abs(x[i]-y[i])) end
	return maximum
end
local function vec(value) return {value.X,value.Y,value.Z} end
local function countKeys(values) local count=0;for _ in pairs(values) do count+=1 end;return count end

function QA.Start(options)
	options=options or {}
	assert(RunService:IsStudio() and RunService:IsRunning(),"Run native QA during Studio Play")
	local context=RunService:IsServer() and "Server" or "Client"
	local suffix=context=="Client" and "_"..tostring(Players.LocalPlayer and Players.LocalPlayer.UserId or 0) or ""
	local name="WindowWatcherGuardedQA_"..context..suffix
	assert(not workspace:FindFirstChild(name),"Remove only the previous temporary QA folder before rerunning")
	local duration=math.clamp(tonumber(options.Duration) or 150,10,180)
	local world=assert(workspace:FindFirstChild(WORLD),"Enter Level 5 first; no QA-generated world")
	local architecture=assert(world:FindFirstChild("Level5_IndoorSuburbs"),"Architecture missing")
	local district=assert(architecture:FindFirstChild("F_BayWindowCanyon"),"F missing")
	local anchors=assert(district:FindFirstChild("WindowWatcherAnchors"),"Anchors missing")
	local owner=assert(world:FindFirstChild(OWNER),"Permanent encounter integration missing")
	local actor=assert(owner:FindFirstChild("WindowWatcher"),"Permanent rig clone missing")
	local controller=assert(actor:FindFirstChildOfClass("AnimationController"),"AnimationController missing")
	local animator=assert(controller:FindFirstChildOfClass("Animator"),"Official Animator missing")
	local folder=Instance.new("Folder");folder.Name=name
	folder:SetAttribute("TemporaryWindowWatcherQA",true);folder:SetAttribute("Status","RUNNING")
	local output=Instance.new("StringValue");output.Name="Report";output.Parent=folder;folder.Parent=workspace
	local started=os.clock()
	local report={version="2026-09-26.native.guarded.1",context=context,status="RUNNING",durationLimit=duration,
		worldGeneration=world:GetAttribute("Level5_Generation"),failures={},warnings={},appearances={},clips={},
		anchors={},cleanup={observed=false},checks={},observedSamples=0,mutationScope="temporary QA report folder only",
		unverified={"skinned vertex/glass intersection","visual eye filtering and appearance","published-server asset permission"}}
	local state={connections={},done=false,seenFailures={},seenWarnings={},current=nil,lastVisible=false,lastHidden=nil,
		firstAudience=nil,firstEligible=nil,audienceLeft=nil,worldGoneAt=nil,trackRefs={},seenTracks={},lastWrite=0,
		startedVisible=owner:GetAttribute("Visible")==true,rawBones={},previousTrackTimes={},sampleAccumulator=0,
		visualMismatchSince=nil,eligibleThroughoutHidden=true,guardRenderFrame=0,guardTrackTimes={},
		guardAdvances={},guardRenderBinding=nil,clientDisplayed=false}
	local function failure(text)
		if not state.seenFailures[text] then state.seenFailures[text]=true;table.insert(report.failures,text) end
	end
	local function warning(text)
		if not state.seenWarnings[text] then state.seenWarnings[text]=true;table.insert(report.warnings,text) end
	end
	local function disconnectRender()
		if state.guardRenderBinding then RunService:UnbindFromRenderStep(state.guardRenderBinding);state.guardRenderBinding=nil end
	end
	local function write()
		report.elapsed=math.round((os.clock()-started)*1000)/1000
		output.Value=HttpService:JSONEncode(report)
	end
	local function finish(reason)
		if state.done then return end
		state.done=true;disconnectRender()
		for _,connection in ipairs(state.connections) do connection:Disconnect() end
		table.clear(state.connections)
		report.finishReason=reason;report.cleanup.observerConnectionsDisconnected=true
		local covered=0
		for _,clip in pairs(report.clips) do
			if clip.visibleSamples>=10 and clip.maxBoneTransformDelta>0.00001 and clip.trackTimeAdvanced
				and (context=="Server" or (clip.officialIdVerified==true and (clip.displayedRenderFrames or 0)>=10)) then covered+=1 end
		end
		report.coverage={animatedClips=covered,requiredClips=3,completeAppearances=0}
		for _,appearance in ipairs(report.appearances) do
			if appearance.duration and not appearance.partial and not appearance.interrupted then report.coverage.completeAppearances+=1 end
		end
		if #report.failures>0 then report.status="FAIL"
		elseif covered<3 or not report.cleanup.observed then report.status="INCOMPLETE"
		else report.status="PASS_OBSERVED_CHECKS" end
		folder:SetAttribute("Status",report.status);write()
	end
	local bones={}
	for _,object in ipairs(actor:GetDescendants()) do
		if object:IsA("Bone") then table.insert(bones,object)
		elseif object:IsA("BaseScript") or object:IsA("Sound") or object:IsA("Humanoid") then
			failure("Unexpected active class in passive rig: "..object.ClassName)
		elseif object:IsA("Light") or object:IsA("BillboardGui") then
			warning("Legacy eye object present; final package expects skin emission: "..object:GetFullName())
		end
	end
	report.checks.boneCount=#bones
	if #bones~=25 then failure("Expected the exact 25-bone rig") end
	local primary=actor.PrimaryPart
	if not primary or not primary:IsA("MeshPart") then failure("PrimaryPart is not the real MeshPart")
	else
		report.checks.mesh={meshId=primary.MeshId,size=vec(primary.Size),nativeMeshSize=vec(primary.MeshSize),
			pivotOffset=components(primary.PivotOffset),sizeError=(primary.Size-primary.MeshSize).Magnitude}
		if (primary.Size-primary.MeshSize).Magnitude>.001 then failure("MeshPart.Size differs from native mesh dimensions") end
		if tostring(primary.MeshId):match("(%d+)$")~="138178192370575" then failure("Unexpected persistent mesh ID") end
		local appearance=primary:FindFirstChildOfClass("SurfaceAppearance")
		if not appearance then failure("Real white-eye SurfaceAppearance missing")
		else
			local ok,material=pcall(function()
				return {colorMap=appearance.ColorMap,mask=tostring(appearance.EmissiveMaskContent),
					strength=appearance.EmissiveStrength,tint={appearance.EmissiveTint.R,appearance.EmissiveTint.G,appearance.EmissiveTint.B},
					maskSha=appearance:GetAttribute("WindowWatcherEmissionMaskSha256")}
			end)
			if ok then report.checks.eyeMaterial=material
				if material.strength<=0 then failure("Eye emission is disabled") end
				for _,channel in ipairs(material.tint) do if math.abs(channel-1)>.001 then failure("Eye emission is not white") end end
			else failure("Cannot inspect native eye emission: "..tostring(material)) end
		end
	end
	-- This runs after the production visibility guard's known render priority.
	-- Unlike the slow spatial observer, it catches a single rendered bad frame.
	local guardReport={renderFrames=0,serverVisibleFrames=0,displayedFrames=0,warmupHiddenFrames=0,
		hiddenReadyFrames=0,displayedWithoutObservedTimeAdvance=0,clips={}}
	if context=="Client" then report.clientGuard=guardReport end
	local function ensureClip(name)
		local clip=report.clips[name]
		if not clip then
			clip={visibleSamples=0,maxBoneTransformDelta=0,movingBones={},trackTimeAdvanced=false,trackPositions={}}
			report.clips[name]=clip
		end
		return clip
	end
	local function renderProbe()
		if state.done or not world:IsDescendantOf(workspace) or not actor:IsDescendantOf(world) then return end
		state.guardRenderFrame+=1;guardReport.renderFrames+=1
		local visible=owner:GetAttribute("Visible")==true
		local clipName=actor:GetAttribute("PreviewClip")
		local displayed=false
		for _,part in ipairs(actor:GetDescendants()) do
			if part:IsA("BasePart") then
				local effective=1-(1-part.Transparency)*(1-part.LocalTransparencyModifier)
				if effective<.99 then displayed=true end
			end
		end
		state.clientDisplayed=displayed
		local ready=actor:GetAttribute("WindowWatcherVisualReady")==true
		local status=actor:GetAttribute("WindowWatcherVisualStatus")
		local guardError=actor:GetAttribute("WindowWatcherVisualError")
		if guardError then failure("Client visibility guard error: "..tostring(guardError)) end
		local tracks=animator:GetPlayingAnimationTracks()
		local weighted,matching=0,nil
		for _,track in ipairs(tracks) do
			if not state.seenTracks[track] then state.seenTracks[track]=true;table.insert(state.trackRefs,track) end
			if track.IsPlaying and track.WeightCurrent>.0001 then
				weighted+=1
				if track.Animation and track.Animation.AnimationId==IDS[clipName] and track.Length>0 then matching=track end
			end
		end
		local advanced=false
		if matching then
			local previous=state.guardTrackTimes[matching]
			if previous and previous.clip==clipName and math.abs(matching.TimePosition-previous.time)>.000001 then
				state.guardAdvances[matching]=true
			end
			state.guardTrackTimes[matching]={clip=clipName,time=matching.TimePosition}
			advanced=state.guardAdvances[matching]==true
		else
			table.clear(state.guardTrackTimes);table.clear(state.guardAdvances)
		end
		local posed=false
		for _,bone in ipairs(bones) do
			local transform=bone.Transform
			local _,angle=transform:ToAxisAngle()
			if transform.Position.Magnitude>.0001 or math.abs(angle)>.0001 then posed=true;break end
		end
		guardReport.latest={serverVisible=visible,displayed=displayed,ready=ready,status=status,clip=clipName,
			weightedTrackCount=weighted,matchingOfficialTrack=matching~=nil,poseEvaluated=posed,
			timeAdvancedObserved=advanced,transparency=primary and primary.Transparency,
			localTransparencyModifier=primary and primary.LocalTransparencyModifier}
		if visible then
			guardReport.serverVisibleFrames+=1
			if not displayed then
				guardReport.warmupHiddenFrames+=1
				if ready then guardReport.hiddenReadyFrames+=1 end
				if clipName then local clip=ensureClip(clipName);clip.warmupHiddenRenderFrames=(clip.warmupHiddenRenderFrames or 0)+1 end
			end
		end
		if displayed then
			guardReport.displayedFrames+=1
			if not visible then failure("Client rendered actor while server visibility is false") end
			if not ready or status~="VISIBLE" then failure("Client rendered actor before visibility guard was ready") end
			if weighted~=1 or not matching then failure("Client rendered actor without one loaded playing weighted official clip") end
			if not posed then failure("Client rendered actor before native Bone.Transform pose evaluation") end
			if matching and matching.TimePosition<=.000001 and not advanced then
				failure("Client rendered actor before its official track time advanced")
			end
			if not advanced then
				-- Starting QA mid-appearance cannot recover an earlier frame. Keep
				-- the sample explicit; coverage still requires independently
				-- observed advancement and real skin motion for every clip.
				guardReport.displayedWithoutObservedTimeAdvance+=1
			end
			if clipName then
				local clip=ensureClip(clipName)
				clip.displayedRenderFrames=(clip.displayedRenderFrames or 0)+1
				clip.officialIdVerified=weighted==1 and matching~=nil
				clip.guardObservedTrackAdvance=clip.guardObservedTrackAdvance or advanced
			end
		end
	end
	local panes={}
	for name,spec in pairs(SPEC) do
		local anchor=anchors:FindFirstChild(name)
		local reference=anchor and anchor:FindFirstChild("WindowGlass")
		local pane=reference and reference:IsA("ObjectValue") and reference.Value
		if not pane or not pane:IsA("BasePart") then failure("Actual pane missing: "..name)
		else
			panes[name]=pane
			local pivot=pane.CFrame*CFrame.new(1.1,-6.55,spec.depth)
			local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances={actor,folder}
			local support=workspace:Raycast(pivot.Position+Vector3.new(0,.5,0),Vector3.new(0,-1.25,0),params)
			report.anchors[name]={pane=pane:GetFullName(),size=vec(pane.Size),relativePosition=vec(pane.Position-ORIGIN),
				expectedPivot=components(pivot),support=support and support.Instance:GetFullName() or "NONE",
				floorError=support and math.abs(support.Position.Y-pivot.Position.Y) or -1}
			if not support or math.abs(support.Position.Y-pivot.Position.Y)>.12 then failure("Actor floor/pivot mismatch: "..name) end
			if pane.Material~=Enum.Material.Glass or pane:GetAttribute("Level5TintedWindow")~=true then failure("Nonstandard pane: "..name) end
		end
	end
	local function audienceAndCandidates()
		local viewers={}
		if workspace:GetAttribute("SelectedLevel")==5 and workspace:GetAttribute("RoundActive")==true then
			for _,player in ipairs(Players:GetPlayers()) do
				local character=player.Character
				local humanoid=character and character:FindFirstChildOfClass("Humanoid")
				local root=character and character:FindFirstChild("HumanoidRootPart")
				if player:GetAttribute("InRound")==true and player:GetAttribute("Escaped")~=true
					and player:GetAttribute("Spectating")~=true and humanoid and humanoid.Health>0 and root then
					local relative=root.Position-ORIGIN
					if math.abs(relative.X)<=160 and relative.Z>=776 and relative.Z<=1036 and relative.Y>=-10 and relative.Y<=70 then
						table.insert(viewers,{character=character,eye=root.Position+Vector3.new(0,2,0)})
					end
				end
			end
		end
		local eligible={}
		local excluded={actor,folder};for _,viewer in ipairs(viewers) do table.insert(excluded,viewer.character) end
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=excluded
		for name,pane in pairs(panes) do
			local target=pane.CFrame:PointToWorldSpace(Vector3.new(1.1,.5,-.08))
			for _,viewer in ipairs(viewers) do
				local delta=target-viewer.eye
				if pane.CFrame:PointToObjectSpace(viewer.eye).Z<-.8 and delta.Magnitude>=3 and delta.Magnitude<=145 then
					local hit=workspace:Raycast(viewer.eye,delta,params)
					if not hit or hit.Instance==pane then eligible[name]=true;break end
				end
			end
		end
		return #viewers,eligible
	end
	local function endAppearance(now,reason,interrupted)
		local appearance=state.current;if not appearance then return end
		appearance.duration=now-appearance.startedAt;appearance.endReason=reason;appearance.interrupted=interrupted
		if not interrupted and not appearance.partial and (appearance.duration<7.8 or appearance.duration>14.7) then
			failure("Visibility duration outside 8-14s plus sampling tolerance: "..appearance.window)
		end
		state.current=nil;state.lastHidden=now;state.eligibleThroughoutHidden=true
	end
	local function sample(now)
		report.observedSamples+=1
		if not world:IsDescendantOf(workspace) then
			if not state.worldGoneAt then
				state.worldGoneAt=now;endAppearance(now,"normal-world-removal",true)
				report.cleanup.removedAt=now
			end
			if now-state.worldGoneAt>=3 then
				local aliveTracks=0
				for _,track in ipairs(state.trackRefs) do
					local ok,playing=pcall(function() return track.IsPlaying end)
					if ok and playing then aliveTracks+=1 end
				end
				report.cleanup.observed=true;report.cleanup.oldOwnerParentNil=owner.Parent==nil
				report.cleanup.oldActorParentNil=actor.Parent==nil;report.cleanup.oldPlayingTracks=aliveTracks
				report.cleanup.newWorldPresent=workspace:FindFirstChild(WORLD)~=nil
				if owner.Parent~=nil or actor.Parent~=nil or aliveTracks>0 then failure("Old actor/owner/track survived world cleanup") end
				finish("normal-round-world-cleanup")
			end
			return
		end
		local runtimeError=world:GetAttribute("WindowWatcherError")
		if runtimeError then failure("Production runtime error: "..tostring(runtimeError)) end
		if owner.Parent~=world then failure("Encounter owner removed while Level 5 world remains");finish("owner-removed");return end
		local modelCount=0
		for _,child in ipairs(owner:GetChildren()) do if child:IsA("Model") then modelCount+=1 end end
		if modelCount~=1 then failure("Expected exactly one runtime actor, got "..modelCount) end
		local visible=owner:GetAttribute("Visible")==true
		local viewerCount,candidates=audienceAndCandidates()
		if not visible and not next(candidates) then state.eligibleThroughoutHidden=false end
		report.latest={status=owner:GetAttribute("Status"),visible=visible,audience=viewerCount,candidates=candidates}
		if viewerCount>0 then state.firstAudience=state.firstAudience or now;state.audienceLeft=nil
		elseif not state.audienceLeft then state.audienceLeft=now end
		if next(candidates) then state.firstEligible=state.firstEligible or now end
		if visible and state.audienceLeft and now-state.audienceLeft>.65 then failure("Watcher remains visible after last audience left") end
		local visibleParts=0
		for _,part in ipairs(actor:GetDescendants()) do
			if part:IsA("BasePart") then
				if part.CanCollide or part.CanTouch or part.CanQuery or not part.Anchored then failure("Runtime actor is not passive/anchored") end
				if part.Transparency<.99 then visibleParts+=1 end
			end
		end
		local visualMismatch=(visible and visibleParts==0) or (not visible and visibleParts>0)
		if context=="Client" then
			-- Transparency is replicated intent; effective display also includes
			-- LocalTransparencyModifier. Warm-up hiding is correct, not a failure.
			local displayedParts=0
			for _,part in ipairs(actor:GetDescendants()) do
				if part:IsA("BasePart") and 1-(1-part.Transparency)*(1-part.LocalTransparencyModifier)<.99 then displayedParts+=1 end
			end
			report.latest.displayedParts=displayedParts
			report.latest.guardReady=actor:GetAttribute("WindowWatcherVisualReady")
			report.latest.guardStatus=actor:GetAttribute("WindowWatcherVisualStatus")
			visualMismatch=not visible and displayedParts>0
		end
		if visualMismatch then
			report.checks.visualMismatchSamples=(report.checks.visualMismatchSamples or 0)+1
			state.visualMismatchSince=state.visualMismatchSince or now
			-- Report all transients, but allow property/attribute replication to
			-- settle on the client before declaring a sustained rendering failure.
			if now-state.visualMismatchSince>.5 then failure("Visibility flag and actual mesh disagree for >0.5 seconds") end
		else state.visualMismatchSince=nil end
		if visible and not state.lastVisible then
			local window=owner:GetAttribute("ActiveWindow")
			local appearance={window=window,clip=actor:GetAttribute("PreviewClip"),startedAt=now,
				partial=state.startedVisible and #report.appearances==0,candidatesAtReveal=candidates,
				appearanceCount=owner:GetAttribute("AppearanceCount")}
			if state.lastHidden then
				appearance.hiddenGap=now-state.lastHidden
				-- A no-audience interruption resets the first-encounter delay.
				local previous=report.appearances[#report.appearances]
				if previous and not previous.interrupted and appearance.hiddenGap<17.8 then failure("Cooldown shorter than 18 seconds") end
				if previous and not previous.interrupted and state.eligibleThroughoutHidden and appearance.hiddenGap>35.8 then
					failure("Cooldown exceeds 35 seconds despite continuously visible eligible windows")
				end
				if previous and previous.window==window and countKeys(candidates)>1 then
					warning("Same window despite alternatives at observer sample; inspect selection/reveal timing")
				end
			elseif state.firstEligible and not appearance.partial then appearance.firstEligibleDelay=now-state.firstEligible end
			local spec=SPEC[window];local pane=panes[window]
			if not spec or not pane then failure("Unknown selected window")
			else
				appearance.pivotError=errorBetween(actor:GetPivot(),pane.CFrame*CFrame.new(1.1,-6.55,spec.depth))
				if appearance.pivotError>.003 then failure("Real actor pivot mismatch: "..window) end
				if appearance.clip~=spec.clip then failure("Window plays wrong clip: "..window) end
			end
			table.insert(report.appearances,appearance);state.current=appearance;state.rawBones={};state.previousTrackTimes={}
		elseif not visible and state.lastVisible then
			endAppearance(now,viewerCount==0 and "audience-left" or "scheduled-hide",viewerCount==0)
		end
		state.lastVisible=visible
		local tracks=animator:GetPlayingAnimationTracks()
		for _,track in ipairs(tracks) do
			if not state.seenTracks[track] then state.seenTracks[track]=true;table.insert(state.trackRefs,track) end
		end
		if visible and state.current then
			local name=state.current.clip or "UNKNOWN"
			local clip=ensureClip(name)
			if context=="Client" then
				clip.serverVisibleSamples=(clip.serverVisibleSamples or 0)+1
				if not state.clientDisplayed then
					clip.warmupHiddenSamples=(clip.warmupHiddenSamples or 0)+1
					return -- loaded checks and skin-motion coverage apply to real display
				end
			end
			clip.visibleSamples+=1
			if #tracks~=1 and now-state.current.startedAt>.5 then failure("Visible actor must have exactly one playing official track") end
			for _,track in ipairs(tracks) do
				clip.animationId=track.Animation and track.Animation.AnimationId or "MISSING"
				clip.length=track.Length;clip.looped=track.Looped;clip.playing=track.IsPlaying
				local previousTime=state.previousTrackTimes[track]
				if previousTime and math.abs(track.TimePosition-previousTime)>.001 then clip.trackTimeAdvanced=true end
				state.previousTrackTimes[track]=track.TimePosition
				if #clip.trackPositions<12 then table.insert(clip.trackPositions,{sample=now,time=track.TimePosition}) end
				if track.Length<=0 then failure("Visible official track is not loaded") end
				if not track.Looped then failure("Complete gesture should loop during encounter") end
			end
			for _,bone in ipairs(bones) do
				local previous=state.rawBones[bone]
				if not previous then state.rawBones[bone]=bone.Transform
				else
					local delta=errorBetween(previous,bone.Transform)
					clip.maxBoneTransformDelta=math.max(clip.maxBoneTransformDelta,delta)
					if delta>.00001 then clip.movingBones[bone.Name]=true end
				end
			end
		end
	end
	table.insert(state.connections,folder.Destroying:Connect(function()
		if state.done then return end
		state.done=true;disconnectRender();for _,connection in ipairs(state.connections) do connection:Disconnect() end
		table.clear(state.connections)
	end))
	if context=="Client" then
		state.guardRenderBinding=name.."_RenderSafety"
		RunService:BindToRenderStep(state.guardRenderBinding,Enum.RenderPriority.Last.Value+1,function()
			local ok,detail=xpcall(renderProbe,debug.traceback)
			if not ok then failure("Render observer error: "..tostring(detail));finish("render-observer-error") end
		end)
	end
	table.insert(state.connections,RunService.Heartbeat:Connect(function(dt)
		if state.done then return end
		state.sampleAccumulator+=dt;if state.sampleAccumulator<.1 then return end;state.sampleAccumulator=0
		local now=os.clock()-started
		local ok,detail=xpcall(function() sample(now) end,debug.traceback)
		if not ok then failure("Observer error: "..tostring(detail));finish("observer-error");return end
		if state.done then return end
		if now-state.lastWrite>=1 then state.lastWrite=now;write() end
		if now>=duration then finish("bounded-observation-timeout") end
	end))
	write()
	return {started=true,context=context,reportPath=folder:GetFullName()..".Report",durationLimit=duration,
		instruction="Move through real F viewpoints; let production timing run; use normal Back to Lobby before timeout."}
end

return QA
