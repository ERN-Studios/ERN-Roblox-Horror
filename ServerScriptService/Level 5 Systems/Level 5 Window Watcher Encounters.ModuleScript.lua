-- Passive intermittent Window Watcher; one prepared rig, curated windows in all eight districts.
-- No AI, damage, chase, sounds, rewards, movement/pathfinding or delayed tasks.
-- Start only from the existing developer-only Level 5 round adapter.
-- Import contract: bottom pivot, 8 studs tall, facing local -Z. Mesh/rest bones
-- AND animation translations must share the import scale (~3.333 studs/metre).
-- Never fix this by scaling only MeshPart.Size. Verify native animated extrema.
local Encounters = {}
local VERSION = "2026-09-26.mapwide.1"
local FOLDER_NAME = "Level5WindowWatcherEncounters"
local OWNED = "Level5WindowWatcherOwned"
local active = setmetatable({}, {__mode="k"})
local SOURCE_SHA = "cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"
local poses = {
	{clip="WatchingIdle",depth=.95,id="rbxassetid://123386867650430"},
	{clip="SlowWindowLean",depth=.95,id="rbxassetid://85635358459792"},
	-- Actual baked tap minimum Z -1.745002; pane rear surface is +.07.
	{clip="GlassTap",depth=1.90,id="rbxassetid://85948818863545"},
}
local MAX_DISTANCE=145
local MIN_VIEW_DOT=math.cos(math.rad(70)) -- server Head/HRP facing, not a camera assertion
local MAX_RAYS_PER_SCAN=96
local MAX_WINDOWS_PER_SCAN=24
local SCAN_INTERVAL=.75

local function finite(value)
	return type(value)=="number" and value==value and math.abs(value)<math.huge
end

-- Pure selection helpers use the same bounds and weighting as native Start.
-- A general view cone is intentional: players need not center the exact eyes.
function Encounters.ViewQuality(distance,facingDot,paneLocalZ)
	if not finite(distance) or not finite(facingDot) or not finite(paneLocalZ)
		or distance<3 or distance>MAX_DISTANCE or facingDot<MIN_VIEW_DOT or paneLocalZ>=-.8 then return nil end
	local alignment=math.clamp((facingDot-MIN_VIEW_DOT)/(1-MIN_VIEW_DOT),0,1)
	return .5+.35*alignment+.15*(1-distance/MAX_DISTANCE)
end

function Encounters.CandidateScore(viewerCount,totalQuality)
	if not finite(viewerCount) or viewerCount<1 or viewerCount%1~=0 or not finite(totalQuality) or totalQuality<=0 then return 0 end
	-- Every additional confirmed onlooker raises weight more than any one
	-- viewer's angle/range adjustment. Distinct living roster members only.
	return viewerCount*viewerCount+math.clamp(totalQuality/viewerCount,.5,1)-1
end

function Encounters.ChooseCandidate(candidates,last,randomUnit)
	local all,alternatives={},{}
	for _,entry in ipairs(candidates) do
		local index=type(entry)=="table" and entry.index or entry
		local score=type(entry)=="table" and entry.score or 1
		if finite(index) and index>=1 and index%1==0 and finite(score) and score>0 then
			local candidate={index=index,score=score,viewers=type(entry)=="table" and entry.viewers or 1}
			table.insert(all,candidate)
			if index~=last then table.insert(alternatives,candidate) end
		end
	end
	local choices=#alternatives>0 and alternatives or all
	if #choices==0 then return nil end
	local total=0;for _,entry in ipairs(choices) do total+=entry.score end
	local threshold=math.clamp(randomUnit,0,.999999999)*total
	local cumulative=0
	for _,entry in ipairs(choices) do
		cumulative+=entry.score
		if threshold<cumulative then return entry.index,entry end
	end
	return choices[#choices].index,choices[#choices]
end

-- Pure scheduling core: the same code is exercised by the deterministic CLI
-- harness. The caller supplies monotonically increasing seconds and candidates.
-- No timers can outlive the owner: Stop makes every future Step inert.
function Encounters.NewSchedule(randomUnit)
	assert(type(randomUnit)=="function", "randomUnit callback required")
	local state={visible=nil,last=nil,due=nil,ends=nil,duration=nil,revealed=false,stopped=false,count=0}
	local function unit() return math.clamp(randomUnit(),0,.999999999) end
	local function between(low,high) return low+(high-low)*unit() end
	local schedule={}
	function schedule.IsDue(now)
		return not state.stopped and not state.visible and state.due~=nil and now>=state.due
	end
	function schedule.Step(now,hasAudience,candidates)
		if state.stopped then return nil end
		if not hasAudience then
			local wasVisible=state.visible~=nil
			state.visible=nil;state.ends=nil;state.due=nil
			return wasVisible and {kind="hide",reason="audience-left"} or nil
		end
		if state.visible then
			if now<state.ends then return nil end
			state.visible=nil;state.ends=nil;state.due=now+between(18,35)
			return {kind="hide",reason="duration",nextAt=state.due}
		end
		if state.due==nil then state.due=now+between(2,4);return nil end
		if now<state.due or #candidates==0 then return nil end
		local index,selected=Encounters.ChooseCandidate(candidates,state.last,unit())
		if not index then return nil end
		state.visible=index;state.last=index;state.due=nil
		state.duration=between(8,14);state.ends=now+state.duration;state.revealed=false;state.count+=1
		return {kind="show",index=index,endsAt=state.ends,count=state.count,viewers=selected.viewers,score=selected.score}
	end
	function schedule.MarkRevealed(now)
		if not state.stopped and state.visible and not state.revealed then
			state.revealed=true;state.ends=now+state.duration
		end
	end
	function schedule.Stop()
		if state.stopped then return nil end
		local wasVisible=state.visible~=nil
		state.stopped=true;state.visible=nil;state.ends=nil;state.due=nil
		return wasVisible and {kind="hide",reason="stopped"} or nil
	end
	function schedule.Snapshot()
		return {visible=state.visible,last=state.last,due=state.due,ends=state.ends,
			stopped=state.stopped,count=state.count}
	end
	return schedule
end

local function failure(message)
	return {ok=false,error="[Level 5 Window Watcher] "..tostring(message)}
end

function Encounters.Cleanup(world)
	local state=active[world]
	if state then state.cleanup(false) end
end

function Encounters.Start(world,options)
	options=options or {}
	local RunService=game:GetService("RunService")
	local ServerStorage=game:GetService("ServerStorage")
	local Players=game:GetService("Players")
	if not RunService:IsServer() or not RunService:IsRunning() then
		return failure("encounters require a running server")
	end
	if typeof(world)~="Instance" or not world:IsA("Model")
		or world.Name~="Level 5 Generated World" or world:GetAttribute("Level5_MapOnly")~=true
		or workspace:GetAttribute("Level5DevEnabled")~=true or not world:IsDescendantOf(workspace) then
		return failure("requires the enabled Level 5 developer map preview in Workspace")
	end
	if typeof(options.Origin)~="Vector3" or type(options.GetParticipants)~="function" then
		return failure("Origin and a synchronous GetParticipants callback are required")
	end
	if active[world] or world:FindFirstChild(FOLDER_NAME) then
		return failure("encounter owner already exists; existing content was preserved")
	end
	local source=ServerStorage:FindFirstChild("Level5WindowWatcher")
	local template=source and source:FindFirstChild("WindowWatcherRig")
	local animations=source and source:FindFirstChild("Animations")
	if not template or not template:IsA("Model") or not template.Archivable or not animations then
		return failure("missing archivable WindowWatcherRig or sibling Animations")
	end
	if template:GetAttribute("SourceGlbSha256")~=SOURCE_SHA then return failure("prepared rig source SHA changed") end
	local architecture=world:FindFirstChild("Level5_IndoorSuburbs")
	local anchors=world:FindFirstChild("WindowWatcherAnchors")
	if not architecture or not anchors then return failure("map-wide WindowWatcherAnchors are missing") end
	for _,pose in ipairs(poses) do
		local animation=animations:FindFirstChild(pose.clip)
		if not animation or not animation:IsA("Animation") or animation.AnimationId~=pose.id then
			return failure("missing verified permanent AnimationId: "..pose.clip)
		end
	end
	local prepared,districts,names={},{},{}
	local anchorList=anchors:GetChildren()
	table.sort(anchorList,function(a,b) return a.Name<b.Name end)
	if #anchorList>128 then return failure("curated anchor budget exceeds 128") end
	local supportParams=RaycastParams.new()
	supportParams.FilterType=Enum.RaycastFilterType.Exclude;supportParams.FilterDescendantsInstances={anchors}
	for _,anchor in ipairs(anchorList) do
		local reference=anchor:FindFirstChild("WindowGlass")
		local pane=reference and reference:IsA("ObjectValue") and reference.Value
		local districtName=anchor:GetAttribute("District")
		local district=type(districtName)=="string" and architecture:FindFirstChild(districtName)
		local initial=type(districtName)=="string" and districtName:match("^([A-H])_")
		local floor=anchor:GetAttribute("FloorCFrame")
		local depth=anchor:GetAttribute("PawnDepth")
		if not anchor:IsA("BasePart") or anchor:GetAttribute("Level5WindowWatcherAnchor")~=true or names[anchor.Name]
			or not initial or not district or not pane or not pane:IsA("BasePart") or not pane:IsDescendantOf(district)
			or pane.Material~=Enum.Material.Glass or pane:GetAttribute("Level5TintedWindow")~=true or not pane.CanQuery
			or pane.Size.X<6 or pane.Size.Y<7.19 or pane.Size.Z>.5
			or typeof(floor)~="CFrame" or not finite(depth) or depth<1.90 or depth>4
			or depth-1.745002-pane.Size.Z*.5<.04 then
			return failure("invalid supported glass/anchor: "..anchor.Name)
		end
		local relative=pane.CFrame:ToObjectSpace(floor)
		if (relative.Position-Vector3.new(0,-6.55,0)).Magnitude>.02
			or relative.LookVector:Dot(Vector3.new(0,0,-1))<.9999 or floor.UpVector.Y<.9999 then
			return failure("floor frame must share pane rotation and sit 6.55 studs below its center: "..anchor.Name)
		end
		-- Validate the two actual actor depth extrema without changing geometry.
		for _,testDepth in ipairs({math.max(depth,.95),math.max(depth,1.90)}) do
			local position=(floor*CFrame.new(1.1,0,testDepth)).Position
			local support=workspace:Raycast(position+Vector3.new(0,.5,0),Vector3.new(0,-1.25,0),supportParams)
			if not support or not support.Instance.CanCollide or math.abs(support.Position.Y-position.Y)>.15 then
				return failure("unsupported actor feet: "..anchor.Name)
			end
		end
		names[anchor.Name]=true;districts[initial]=true
		table.insert(prepared,{anchor=anchor,pane=pane,floor=floor,depth=depth,district=districtName})
	end
	for _,initial in ipairs({"A","B","C","D","E","F","G","H"}) do
		if not districts[initial] then return failure("no valid supported house window in district "..initial) end
	end
	-- Everything above is read-only. An installation failure below destroys its
	-- sole unpublished/hidden clone and disconnects every connection.
	local folder=Instance.new("Folder")
	folder.Name=FOLDER_NAME;folder:SetAttribute(OWNED,true)
	folder:SetAttribute("Version",VERSION);folder:SetAttribute("PassiveOnly",true)
	folder:SetAttribute("Visible",false);folder:SetAttribute("AppearanceCount",0)
	folder:SetAttribute("AnchorCount",#prepared);folder:SetAttribute("DistrictCount",8)
	folder:SetAttribute("ViewDirectionSource","Server Head/HRP facing; 70 degree half-cone")
	local random=Random.new()
	local schedule=Encounters.NewSchedule(function() return random:NextNumber() end)
	local state={connections={},tracks={},visuals={},effects={},cleaned=false,actor=nil,pending=nil,
		current=nil,schedule=schedule,folder=folder,loadingSince=os.clock(),scanCursor=1,lastScan=-math.huge,lastPose=nil}
	local function setVisible(visible)
		for _,entry in ipairs(state.visuals) do entry.object.Transparency=visible and entry.original or 1 end
		for _,entry in ipairs(state.effects) do entry.object.Enabled=visible and entry.original or false end
		folder:SetAttribute("Visible",visible)
	end
	local function hide()
		state.pending=nil;state.current=nil
		setVisible(false)
		for _,track in ipairs(state.tracks) do track:Stop(0) end
		folder:SetAttribute("ActiveWindow",nil);folder:SetAttribute("ActiveDistrict",nil)
	end
	local function cleanup(folderAlreadyDestroying)
		if state.cleaned then return end
		state.cleaned=true;active[world]=nil;schedule.Stop();state.pending=nil
		for _,connection in ipairs(state.connections) do connection:Disconnect() end
		table.clear(state.connections)
		for _,track in ipairs(state.tracks) do
			pcall(function() track:Stop(0) end);pcall(function() track:Destroy() end)
		end
		table.clear(state.tracks)
		if not folderAlreadyDestroying then folder:Destroy() end
		table.clear(state.visuals)
		table.clear(state.effects)
		state.actor=nil
	end
	state.cleanup=cleanup
	local function failRuntime(message)
		local detail="[Level 5 Window Watcher] "..tostring(message)
		pcall(function() world:SetAttribute("WindowWatcherError",detail) end)
		warn(detail);cleanup(false)
	end
	local ok,err=xpcall(function()
		local actor=assert(template:Clone(),"prepared rig clone failed")
		actor.Parent=folder;actor.Name="WindowWatcher";state.actor=actor
		actor:SetAttribute(OWNED,true);actor:SetAttribute("PassiveOnly",true)
		local activePane=actor:FindFirstChild("ActiveWindowGlass")
		assert(not activePane,"template contains conflicting ActiveWindowGlass")
		activePane=Instance.new("ObjectValue");activePane.Name="ActiveWindowGlass";activePane.Parent=actor
		local parts,controllers,controller=0,0,nil
		for _,object in ipairs(actor:GetDescendants()) do
			if object:IsA("BaseScript") or object:IsA("Sound") then object:Destroy()
			elseif object:IsA("Humanoid") then error("passive rig must use AnimationController")
			elseif object:IsA("BasePart") then
				parts+=1;object.Anchored=true
				object.CanCollide=false;object.CanTouch=false;object.CanQuery=false
				table.insert(state.visuals,{object=object,original=object.Transparency})
				object.Transparency=1
			elseif object:IsA("Decal") or object:IsA("Texture") then
				table.insert(state.visuals,{object=object,original=object.Transparency})
				object.Transparency=1
			elseif object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("Light") then
				-- Authored white eyes follow the animated head. Preserve the
				-- template's light tuning; never draw an eye through opaque walls.
				if object:IsA("BillboardGui") or object:IsA("SurfaceGui") then object.AlwaysOnTop=false end
				table.insert(state.effects,{object=object,original=object.Enabled})
				object.Enabled=false
			elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
				object.Enabled=false
			elseif object:IsA("AnimationController") then controllers+=1;controller=object end
		end
		assert(parts>0 and controllers<=1,"prepared rig needs BaseParts and at most one AnimationController")
		if not controller then
			controller=Instance.new("AnimationController");controller.Parent=actor
		end
		local animator=controller:FindFirstChildOfClass("Animator")
		if not animator then animator=Instance.new("Animator");animator.Parent=controller end
		local animatorCount=0
		for _,child in ipairs(controller:GetChildren()) do if child:IsA("Animator") then animatorCount+=1 end end
		assert(animatorCount==1,"prepared rig has multiple Animators")
		actor:PivotTo(prepared[1].floor*CFrame.new(1.1,0,math.max(prepared[1].depth,1.90)))
		folder.Parent=world -- official Animator loading requires ancestry in Workspace
		active[world]=state
		table.insert(state.connections,world.Destroying:Connect(function() cleanup(false) end))
		table.insert(state.connections,folder.Destroying:Connect(function() cleanup(true) end))
		table.insert(state.connections,world.AncestryChanged:Connect(function()
			if not world:IsDescendantOf(workspace) then cleanup(false) end
		end))
		for _,pose in ipairs(poses) do
			local track=animator:LoadAnimation(animations:FindFirstChild(pose.clip))
			table.insert(state.tracks,track)
			track.Looped=true;track.Priority=Enum.AnimationPriority.Idle
		end
		folder:SetAttribute("Status","LOADING_ANIMATIONS")
		world:SetAttribute("WindowWatcherError",nil)
		-- All scan decisions remain server-owned; no client-selected spawn or
		-- camera payload remote exists. Direction is a broad body/head proxy.
		local function collectViewers()
			local viewers,seen={},{ }
			if workspace:GetAttribute("SelectedLevel")~=5 or workspace:GetAttribute("RoundActive")~=true then return viewers end
			local roster=options.GetParticipants()
			assert(type(roster)=="table","GetParticipants must synchronously return a player array")
			for _,player in ipairs(roster) do
				if not seen[player] and typeof(player)=="Instance" and player:IsA("Player") and player.Parent==Players
					and player:GetAttribute("InRound")==true and player:GetAttribute("Escaped")~=true
					and player:GetAttribute("Spectating")~=true then
					seen[player]=true
					local character=player.Character
					local humanoid=character and character:FindFirstChildOfClass("Humanoid")
					local root=character and character:FindFirstChild("HumanoidRootPart")
					local head=character and character:FindFirstChild("Head")
					if humanoid and humanoid.Health>0 and root and root:IsA("BasePart") then
						local observer=head and head:IsA("BasePart") and head or root
						local eye=head and head:IsA("BasePart") and head.Position or root.Position+Vector3.new(0,2,0)
						local nearby=false
						for _,entry in ipairs(prepared) do
							if (entry.pane.Position-eye).Magnitude<=MAX_DISTANCE+10 then nearby=true;break end
						end
						if nearby then table.insert(viewers,{character=character,eye=eye,look=observer.CFrame.LookVector}) end
					end
				end
			end
			return viewers
		end
		local function getParams(viewers)
			local excluded={folder,anchors}
			for _,viewer in ipairs(viewers) do table.insert(excluded,viewer.character) end
			local params=RaycastParams.new()
			params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=excluded
			return params,excluded
		end
		local function viewersFor(entry,viewers,params,excluded,budget)
			local count,quality,rays=0,0,0
			if not entry.pane:IsDescendantOf(architecture) or not entry.anchor:IsDescendantOf(anchors) then return 0,0,0 end
			-- Curated anchors support all clips. The face point is behind the
			-- actual pane, not a target in empty space in front of a wall.
			local target=(entry.floor*CFrame.new(1.1,0,math.max(entry.depth,1.90))):PointToWorldSpace(Vector3.new(0,7.45,-.37))
			for _,viewer in ipairs(viewers) do
				local delta=target-viewer.eye
				local distance=delta.Magnitude
				local score=distance>0 and Encounters.ViewQuality(distance,viewer.look:Dot(delta.Unit),entry.pane.CFrame:PointToObjectSpace(viewer.eye).Z)
				if score and rays+2<=budget then
					rays+=1
					local hit=workspace:Raycast(viewer.eye,delta,params)
					if hit and hit.Instance==entry.pane then
						local insideParams=RaycastParams.new()
						insideParams.FilterType=Enum.RaycastFilterType.Exclude
						local insideExcluded=table.clone(excluded);table.insert(insideExcluded,entry.pane)
						insideParams.FilterDescendantsInstances=insideExcluded
						local start=hit.Position+delta.Unit*.01
						rays+=1
						if not workspace:Raycast(start,target-start,insideParams) then count+=1;quality+=score end
					end
				end
			end
			return count,quality,rays
		end
		local function scanCandidates(viewers)
			local params,excluded=getParams(viewers)
			local candidates={}
			local checked,rays,windowsRayed=0,0,0
			while checked<#prepared and windowsRayed<MAX_WINDOWS_PER_SCAN and rays+2<=MAX_RAYS_PER_SCAN do
				local index=state.scanCursor
				state.scanCursor=index%#prepared+1;checked+=1
				local count,quality,used=viewersFor(prepared[index],viewers,params,excluded,MAX_RAYS_PER_SCAN-rays)
				rays+=used;if used>0 then windowsRayed+=1 end
				if count>0 then table.insert(candidates,{index=index,score=Encounters.CandidateScore(count,quality),viewers=count}) end
			end
			folder:SetAttribute("SelectionRaysLast",rays);folder:SetAttribute("SelectionWindowsLast",checked)
			folder:SetAttribute("EligibleWindowsLast",#candidates)
			return candidates
		end
		local ready=false
		local elapsed=0
		local function step(now)
			if state.cleaned then return end
			if workspace:GetAttribute("Level5DevEnabled")~=true then cleanup(false);return end
			if not ready then
				local loaded=true
				for _,track in ipairs(state.tracks) do if track.Length<=0 then loaded=false;break end end
				if not loaded then
					if now-state.loadingSince>20 then failRuntime("animation load timeout; verify ownership/permissions") end
					return
				end
				ready=true;folder:SetAttribute("Status","WAITING_FOR_PARTICIPANTS")
			end
			local nearby=collectViewers()
			local candidates={}
			-- Hidden due scans are bounded and round-robin. No global ray fan
			-- every render frame; at most 96 rays per .75s selection scan.
			if #nearby>0 and schedule.IsDue(now) and now-state.lastScan>=SCAN_INTERVAL then
				state.lastScan=now;candidates=scanCandidates(nearby)
			end
			local event=schedule.Step(now,#nearby>0,candidates)
			if event and event.kind=="hide" then hide();folder:SetAttribute("Status","HIDDEN")
			elseif event and event.kind=="show" then
				hide()
				local entry=prepared[event.index]
				-- Rotate all three authored gestures independently of the chosen
				-- district/window, without replaying the previous gesture.
				local poseChoices={}
				for index=1,#poses do if index~=state.lastPose then table.insert(poseChoices,index) end end
				local poseIndex=poseChoices[random:NextInteger(1,#poseChoices)]
				state.lastPose=poseIndex
				local pose=poses[poseIndex]
				actor:PivotTo(entry.floor*CFrame.new(1.1,0,math.max(entry.depth,pose.depth)))
				activePane.Value=entry.pane
				actor:SetAttribute("WindowAnchor",entry.anchor.Name)
				actor:SetAttribute("WindowDistrict",entry.district)
				actor:SetAttribute("PreviewClip",pose.clip)
				state.tracks[poseIndex]:Play(0,1,1)
				state.current=event.index
				-- Let the official Animator evaluate while hidden. The client
				-- readiness guard independently prevents a late-load bind flash.
				state.pending=now+.15
				folder:SetAttribute("ActiveWindow",entry.anchor.Name)
				folder:SetAttribute("ActiveDistrict",entry.district)
				folder:SetAttribute("SelectedViewerCount",event.viewers)
				folder:SetAttribute("SelectedScore",event.score)
				folder:SetAttribute("AppearanceCount",event.count)
			end
			if state.pending and now>=state.pending then
				-- Revalidate after warm-up: a participant may turn a corner before
				-- the skin is ready. Never reveal solely on a stale sightline.
				local params,excluded=getParams(nearby)
				local viewers,_,rays=viewersFor(prepared[state.current],nearby,params,excluded,MAX_RAYS_PER_SCAN)
				folder:SetAttribute("RevealRaysLast",rays)
				if viewers<1 then
					schedule.Step(now,false,{}) -- clears this unrevealed attempt
					hide();folder:SetAttribute("Status","WAITING_FOR_SIGHT")
				else
					state.pending=nil;setVisible(true);schedule.MarkRevealed(now)
					folder:SetAttribute("VisibleViewerCountAtReveal",viewers)
					folder:SetAttribute("Status","VISIBLE")
				end
			end
		end
		table.insert(state.connections,RunService.Heartbeat:Connect(function(dt)
			if state.cleaned then return end
			elapsed+=dt;if elapsed<.25 then return end;elapsed=0
			local success,detail=xpcall(function() step(os.clock()) end,debug.traceback)
			if not success then failRuntime(detail) end
		end))
	end,debug.traceback)
	if not ok then cleanup(false);return failure(err) end
	return {ok=true,folder=folder,version=VERSION,actorCount=1,anchorCount=#prepared,districtCount=8,assetPlaybackVerified=false,
		note="One hidden rig installed; animation delivery, native bone motion and client visibility still require QA."}
end

return Encounters
