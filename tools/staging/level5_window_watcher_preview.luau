-- Passive poses for the explicitly enabled Level 5 developer map preview.
-- Stage only after Architecture.Build has produced its real glass/anchors.
-- No AI, combat, sounds, movement loop, waits, delayed work or service mutation.
--
-- Import contract: WindowWatcherRig has an 8-stud prepared height, a pivot at
-- its floor/bottom origin, and looks along local -Z. This module never ScaleTo's
-- a model. Mesh, bind/rest bone offsets AND animation translation keys must
-- share the import scale (~3.333 studs/metre); scaling MeshPart.Size alone does
-- not establish that contract. Native pose checks must verify the loaded clips
-- keep feet on the floor and fingertips behind the pane throughout their loops.
-- The animation's skinned vertices can move beyond an unanimated mesh bound.
local Preview = {}
local ServerStorage = game:GetService("ServerStorage")

local FOLDER_NAME = "Level5WindowWatcherPreview"
local OWNED = "Level5WindowWatcherPreviewOwned"
local VERSION = "2026-09-25.1"
local active = setmetatable({}, {__mode = "k"})
local poses = {
	{anchor="FarUpperWindow",clip="WatchingIdle",depth=.95},
	{anchor="MiddleCourtWindow",clip="SlowWindowLean",depth=.95},
	-- Final baked tap reaches -1.745002 studs at an 8-stud height.
	-- Provisional 1.90 depth leaves +.154998 inside pane space; verify natively.
	{anchor="NearGroundWindow",clip="GlassTap",depth=1.90},
}

local function failure(message)
	return {ok=false,actorCount=0,error="[Level 5 Window Watcher] "..tostring(message)}
end

function Preview.Cleanup(world: Instance)
	local state = active[world]
	if state then state.cleanup() end
end

function Preview.Stage(world: Instance)
	-- The adapter remains the authority for the actual developer roster. These
	-- local guards prevent accidental use for a different level/public map.
	if typeof(world)~="Instance" or not world:IsA("Model") then
		return failure("Stage requires the generated world Model")
	end
	if world.Name~="Level 5 Generated World" or world:GetAttribute("Level5_MapOnly")~=true then
		return failure("refusing a world that is not the Level 5 map-only preview")
	end
	if workspace:GetAttribute("Level5DevEnabled")~=true or not world:IsDescendantOf(workspace) then
		return failure("the enabled developer preview must be in Workspace before staging")
	end
	if active[world] then
		return failure("this world already has an active preview; call Cleanup before restaging")
	end
	if world:FindFirstChild(FOLDER_NAME) then
		return failure("preview folder name is already occupied; existing content was preserved")
	end

	local container=ServerStorage:FindFirstChild("Level5WindowWatcher")
	local template=container and container:FindFirstChild("WindowWatcherRig")
	local animations=container and container:FindFirstChild("Animations")
	if not template or not template:IsA("Model") or not template.Archivable then
		return failure("missing archivable ServerStorage.Level5WindowWatcher.WindowWatcherRig Model")
	end
	if not animations then return failure("missing sibling Animations container") end
	local architecture=world:FindFirstChild("Level5_IndoorSuburbs")
	local district=architecture and architecture:FindFirstChild("F_BayWindowCanyon")
	local anchors=district and district:FindFirstChild("WindowWatcherAnchors")
	if not anchors then return failure("F's WindowWatcherAnchors have not been built") end

	-- Validate every target/clip before cloning or publishing any actor.
	local prepared={}
	for _,pose in ipairs(poses) do
		local anchor=anchors:FindFirstChild(pose.anchor)
		local reference=anchor and anchor:FindFirstChild("WindowGlass")
		local pane=reference and reference:IsA("ObjectValue") and reference.Value
		local animation=animations:FindFirstChild(pose.clip)
		if not anchor or not anchor:IsA("BasePart") or anchor:GetAttribute("Level5WindowWatcherAnchor")~=true then
			return failure("missing tagged anchor "..pose.anchor)
		end
		if not pane or not pane:IsA("BasePart") or not pane:IsDescendantOf(district)
			or pane:GetAttribute("Level5TintedWindow")~=true or pane.Material~=Enum.Material.Glass then
			return failure("anchor "..pose.anchor.." does not reference its actual tinted glass pane")
		end
		if not animation or not animation:IsA("Animation")
			or not string.match(animation.AnimationId,"^rbxassetid://[1-9]%d*$") then
			return failure("missing published AnimationId for "..pose.clip)
		end
		table.insert(prepared,{pose=pose,pane=pane,animation=animation})
	end

	local folder=Instance.new("Folder")
	folder.Name=FOLDER_NAME
	folder:SetAttribute(OWNED,true)
	folder:SetAttribute("PreviewVersion",VERSION)
	folder:SetAttribute("PassiveAnimationOnly",true)
	local state={folder=folder,tracks={},connections={},actors={},cleaned=false}
	local function cleanup(folderAlreadyDestroying)
		if state.cleaned then return end
		state.cleaned=true
		active[world]=nil
		for _,connection in ipairs(state.connections) do connection:Disconnect() end
		table.clear(state.connections)
		for _,track in ipairs(state.tracks) do
			pcall(function() track:Stop(0) end)
			pcall(function() track:Destroy() end)
		end
		table.clear(state.tracks)
		-- Also destroys an unparented staging folder on preparation failure.
		if not folderAlreadyDestroying then folder:Destroy() end
		table.clear(state.actors)
	end
	state.cleanup=cleanup

	local ok,err=xpcall(function()
		for _,entry in ipairs(prepared) do
			local actor=assert(template:Clone(),"template clone failed")
			actor.Name=entry.pose.anchor.."_"..entry.pose.clip
			-- Parent immediately to the still-unpublished folder so any later
			-- validation failure rolls back every clone, including this one.
			actor.Parent=folder
			local controllers,parts=0,0
			local controller
			for _,object in ipairs(actor:GetDescendants()) do
				if object:IsA("BaseScript") or object:IsA("Sound") then
					-- Importer leftovers must never run or emit audio in this preview.
					object:Destroy()
				elseif object:IsA("Humanoid") then
					error("prepared passive rig must use AnimationController, not Humanoid")
				elseif object:IsA("BasePart") then
					parts+=1
					object.Anchored=true
					object.CanCollide=false;object.CanTouch=false;object.CanQuery=false
				elseif object:IsA("AnimationController") then
					controllers+=1;controller=object
				end
			end
			assert(parts>0,"prepared rig has no BaseParts")
			assert(controllers<=1,"prepared rig has multiple AnimationControllers")
			if not controller then
				controller=Instance.new("AnimationController")
				controller.Name="WindowWatcherAnimationController";controller.Parent=actor
			end
			local animator=controller:FindFirstChildOfClass("Animator")
			if not animator then animator=Instance.new("Animator");animator.Parent=controller end

			-- Window centers are exactly 6.55 studs above the house floor. The
			-- +local Z offset goes INSIDE the house; local -Z looks through glass.
			-- Offset X keeps the face away from the central window mullion.
			local frame=entry.pane.CFrame*CFrame.new(1.1,-6.55,entry.pose.depth)
			actor:PivotTo(frame)
			actor:SetAttribute(OWNED,true)
			actor:SetAttribute("WindowAnchor",entry.pose.anchor)
			actor:SetAttribute("PreviewClip",entry.pose.clip)
			actor:SetAttribute("PaneDepthStuds",entry.pose.depth)
			actor:SetAttribute("ExpectedPreparedHeightStuds",8)
			actor:SetAttribute("PreviewAnimationId",entry.animation.AnimationId)
			local paneReference=Instance.new("ObjectValue")
			paneReference.Name="SourceWindowGlass";paneReference.Value=entry.pane;paneReference.Parent=actor
			table.insert(state.actors,{model=actor,animator=animator,animation=entry.animation,
				anchor=entry.pose.anchor,clip=entry.pose.clip,depth=entry.pose.depth})
		end

		-- The server-created Animators must be in Workspace before loading.
		-- Loading/Play do not wait here for network asset delivery. Published
		-- permissions and actual bone motion are verified by native QA.
		folder.Parent=world
		active[world]=state
		table.insert(state.connections,world.Destroying:Connect(cleanup))
		table.insert(state.connections,folder.Destroying:Connect(function() cleanup(true) end))
		for _,entry in ipairs(state.actors) do
			local track=entry.animator:LoadAnimation(entry.animation)
			table.insert(state.tracks,track)
			track.Looped=true
			track.Priority=Enum.AnimationPriority.Idle
			track:Play(.2,1,1)
		end
		folder:SetAttribute("ActorCount",#state.actors)
	end,debug.traceback)
	if not ok then cleanup();return failure(err) end

	local actors={}
	for _,entry in ipairs(state.actors) do
		table.insert(actors,{anchor=entry.anchor,clip=entry.clip,depth=entry.depth,
			model=entry.model,animationId=entry.animation.AnimationId})
	end
	return {ok=true,actorCount=#actors,actors=actors,folder=folder,version=VERSION,
		assetPlaybackVerified=false,
		note="Clips started without waiting for asset delivery; inspect native replicated bone motion and scale before publishing."}
end

return Preview
