-- Passive intermittent Window Watcher; one prepared rig, three real windows.
-- No AI, damage, chase, sounds, rewards, movement/pathfinding or delayed tasks.
-- Start only from the existing developer-only Level 5 round adapter.
-- Import contract: bottom pivot, 8 studs tall, facing local -Z. Mesh/rest bones
-- AND animation translations must share the import scale (~3.333 studs/metre).
-- Never fix this by scaling only MeshPart.Size. Verify native animated extrema.
local Encounters = {}
local VERSION = "2026-09-25.intermittent.1"
local FOLDER_NAME = "Level5WindowWatcherEncounters"
local OWNED = "Level5WindowWatcherOwned"
local active = setmetatable({}, {__mode="k"})
local poses = {
	{anchor="FarUpperWindow",clip="WatchingIdle",depth=.95},
	{anchor="MiddleCourtWindow",clip="SlowWindowLean",depth=.95},
	-- Final baked tap minimum Z -1.745002; rear pane surface is +.07.
	{anchor="NearGroundWindow",clip="GlassTap",depth=1.90},
}

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
		local choices={}
		for _,index in ipairs(candidates) do
			if index~=state.last then table.insert(choices,index) end
		end
		-- Reuse only if this is the sole currently visible window. Whenever two
		-- or more are eligible, consecutive appearances use different windows.
		if #choices==0 then choices=candidates end
		local index=choices[math.floor(unit()*#choices)+1]
		state.visible=index;state.last=index;state.due=nil
		state.duration=between(8,14);state.ends=now+state.duration;state.revealed=false;state.count+=1
		return {kind="show",index=index,endsAt=state.ends,count=state.count}
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
	local architecture=world:FindFirstChild("Level5_IndoorSuburbs")
	local district=architecture and architecture:FindFirstChild("F_BayWindowCanyon")
	local anchors=district and district:FindFirstChild("WindowWatcherAnchors")
	if not anchors then return failure("F's WindowWatcherAnchors are missing") end
	local prepared={}
	for _,pose in ipairs(poses) do
		local anchor=anchors:FindFirstChild(pose.anchor)
		local reference=anchor and anchor:FindFirstChild("WindowGlass")
		local pane=reference and reference:IsA("ObjectValue") and reference.Value
		local animation=animations:FindFirstChild(pose.clip)
		if not anchor or not anchor:IsA("BasePart") or anchor:GetAttribute("Level5WindowWatcherAnchor")~=true
			or not pane or not pane:IsA("BasePart") or not pane:IsDescendantOf(district)
			or pane:GetAttribute("Level5TintedWindow")~=true or pane.Material~=Enum.Material.Glass then
			return failure("invalid real glass/anchor: "..pose.anchor)
		end
		if not animation or not animation:IsA("Animation")
			or not string.match(animation.AnimationId,"^rbxassetid://[1-9]%d*$") then
			return failure("missing published AnimationId: "..pose.clip)
		end
		table.insert(prepared,{pose=pose,pane=pane,animation=animation})
	end
	-- Everything above is read-only. An installation failure below destroys its
	-- sole unpublished/hidden clone and disconnects every connection.
	local folder=Instance.new("Folder")
	folder.Name=FOLDER_NAME;folder:SetAttribute(OWNED,true)
	folder:SetAttribute("Version",VERSION);folder:SetAttribute("PassiveOnly",true)
	folder:SetAttribute("Visible",false);folder:SetAttribute("AppearanceCount",0)
	local random=Random.new()
	local schedule=Encounters.NewSchedule(function() return random:NextNumber() end)
	local state={connections={},tracks={},visuals={},effects={},cleaned=false,actor=nil,pending=nil,
		current=nil,schedule=schedule,folder=folder,loadingSince=os.clock()}
	local function setVisible(visible)
		for _,entry in ipairs(state.visuals) do entry.object.Transparency=visible and entry.original or 1 end
		for _,entry in ipairs(state.effects) do entry.object.Enabled=visible and entry.original or false end
		folder:SetAttribute("Visible",visible)
	end
	local function hide()
		state.pending=nil;state.current=nil
		setVisible(false)
		for _,track in ipairs(state.tracks) do track:Stop(0) end
		folder:SetAttribute("ActiveWindow",nil)
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
		actor:PivotTo(prepared[1].pane.CFrame*CFrame.new(1.1,-6.55,prepared[1].pose.depth))
		folder.Parent=world -- official Animator loading requires ancestry in Workspace
		active[world]=state
		table.insert(state.connections,world.Destroying:Connect(function() cleanup(false) end))
		table.insert(state.connections,folder.Destroying:Connect(function() cleanup(true) end))
		table.insert(state.connections,world.AncestryChanged:Connect(function()
			if not world:IsDescendantOf(workspace) then cleanup(false) end
		end))
		for _,entry in ipairs(prepared) do
			local track=animator:LoadAnimation(entry.animation)
			table.insert(state.tracks,track)
			track.Looped=true;track.Priority=Enum.AnimationPriority.Idle
		end
		folder:SetAttribute("Status","LOADING_ANIMATIONS")
		world:SetAttribute("WindowWatcherError",nil)
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
			local nearby={}
			if workspace:GetAttribute("SelectedLevel")==5 and workspace:GetAttribute("RoundActive")==true then
				local roster=options.GetParticipants()
				assert(type(roster)=="table","GetParticipants must synchronously return a player array")
				for _,player in ipairs(roster) do
					if typeof(player)=="Instance" and player:IsA("Player") and player.Parent==Players
						and player:GetAttribute("InRound")==true and player:GetAttribute("Escaped")~=true
						and player:GetAttribute("Spectating")~=true then
						local character=player.Character
						local humanoid=character and character:FindFirstChildOfClass("Humanoid")
						local root=character and character:FindFirstChild("HumanoidRootPart")
						if humanoid and humanoid.Health>0 and root and root:IsA("BasePart") then
							local relative=root.Position-options.Origin
							if math.abs(relative.X)<=160 and relative.Z>=776 and relative.Z<=1036
								and relative.Y>=-10 and relative.Y<=70 then
								table.insert(nearby,{character=character,eye=root.Position+Vector3.new(0,2,0)})
							end
						end
					end
				end
			end
			local candidates={}
			-- Rays run only when a hidden watcher is due, never every frame and
			-- never while the entity is visible. At most 3 rays per participant.
			if #nearby>0 and schedule.IsDue(now) then
				local excluded={folder}
				for _,entry in ipairs(nearby) do table.insert(excluded,entry.character) end
				local params=RaycastParams.new()
				params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=excluded
				for index,entry in ipairs(prepared) do
					assert(entry.pane:IsDescendantOf(district),"watcher window removed during round")
					local target=entry.pane.CFrame:PointToWorldSpace(Vector3.new(1.1,.5,-.08))
					for _,viewer in ipairs(nearby) do
						local delta=target-viewer.eye
						local outside=entry.pane.CFrame:PointToObjectSpace(viewer.eye).Z<-.8
						if outside and delta.Magnitude>=3 and delta.Magnitude<=145 then
							local hit=workspace:Raycast(viewer.eye,delta,params)
							if not hit or hit.Instance==entry.pane then table.insert(candidates,index);break end
						end
					end
				end
			end
			local event=schedule.Step(now,#nearby>0,candidates)
			if event and event.kind=="hide" then hide();folder:SetAttribute("Status","HIDDEN")
			elseif event and event.kind=="show" then
				hide()
				local entry=prepared[event.index]
				actor:PivotTo(entry.pane.CFrame*CFrame.new(1.1,-6.55,entry.pose.depth))
				actor:SetAttribute("WindowAnchor",entry.pose.anchor)
				actor:SetAttribute("PreviewClip",entry.pose.clip)
				state.tracks[event.index]:Play(0,1,1)
				state.current=event.index
				-- Let the Animator evaluate while hidden: no imported bind/A-pose flash.
				state.pending=now+.15
				folder:SetAttribute("ActiveWindow",entry.pose.anchor)
				folder:SetAttribute("AppearanceCount",event.count)
			end
			if state.pending and now>=state.pending then
				state.pending=nil;setVisible(true);schedule.MarkRevealed(now)
				folder:SetAttribute("Status","VISIBLE")
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
	return {ok=true,folder=folder,version=VERSION,actorCount=1,assetPlaybackVerified=false,
		note="One hidden rig installed; animation delivery, native bone motion and client visibility still require QA."}
end

return Encounters
