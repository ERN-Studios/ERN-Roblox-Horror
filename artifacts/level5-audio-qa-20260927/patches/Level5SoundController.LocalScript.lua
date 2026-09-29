-- Level 5 only: authored ambience, household locks and quiet Window Watcher cues.
-- Twelve reusable client Sounds; no sound/part is added to the generated world.
-- Existing footstep/flashlight owners and all server gameplay remain untouched.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local HttpService=game:GetService("HttpService")
local ContentProvider=game:GetService("ContentProvider")
local GuiService=game:GetService("GuiService")
local UIS=game:GetService("UserInputService")
local Catalog=require(RS:WaitForChild("Level5AudioCatalog"))
local Logic=require(RS:WaitForChild("Level5AudioLogic"))
local Outage=require(RS:WaitForChild("Level5OutageLogic"))
local UIDevice=require(RS:WaitForChild("UIDevice"))
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local SHA="cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"
local voices,connections={},{}
local world,worldGeneration,session,soundFolder,emitterFolder,poolCamera
local schedule,encodedSchedule
local uiEvent,uiConnection
local elapsed=0
local stopped=false
local function diagnostic(key,value)
	if script:GetAttribute(key)~=value then script:SetAttribute(key,value) end
end
local function connect(signal,callback)
	table.insert(connections,signal:Connect(callback))
end
local function stopVoice(key)
	local voice=voices[key]
	if voice then voice.sound.Volume=0;voice.sound:Stop();voice.expiresAt=nil end
end
local function destroyPool()
	for _,voice in pairs(voices) do voice.sound:Stop() end
	table.clear(voices)
	if soundFolder then soundFolder:Destroy() end
	if emitterFolder then emitterFolder:Destroy() end
	soundFolder,emitterFolder,poolCamera=nil,nil,nil
	diagnostic("AudioVoiceCount",0);diagnostic("AudioLoadedCount",0)
end
local function detach()
	destroyPool();world,worldGeneration,session=nil,nil,nil
	schedule,encodedSchedule=nil,nil
	diagnostic("AudioActive",false);diagnostic("AudioWatcherIntensity",0)
	diagnostic("AudioPhase","INACTIVE");diagnostic("AudioExempt",false)
end
local function createPool(camera)
	destroyPool()
	soundFolder=Instance.new("Folder");soundFolder.Name="Level5LocalAudio";soundFolder.Parent=SoundService
	emitterFolder=Instance.new("Folder");emitterFolder.Name="Level5LocalAudioEmitters";emitterFolder.Parent=camera
	poolCamera=camera
	local preload={};local count=0
	for key,cue in pairs(Catalog) do
		local emitter
		if cue.Spatial then
			emitter=Instance.new("Part");emitter.Name=key.."Emitter";emitter.Size=Vector3.new(.05,.05,.05)
			emitter.Anchored=true;emitter.Transparency=1;emitter.CanCollide=false
			emitter.CanQuery=false;emitter.CanTouch=false;emitter.CastShadow=false;emitter.Parent=emitterFolder
		end
		local sound=Instance.new("Sound");sound.Name=key;sound.Volume=0
		sound.Looped=cue.Looped==true;sound.SoundId=Logic.AssetId(cue.AssetId) or ""
		sound.RollOffMode=Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance=cue.MinDistance or 5;sound.RollOffMaxDistance=cue.MaxDistance or 100
		sound.Parent=emitter or soundFolder
		voices[key]={sound=sound,emitter=emitter,cue=cue,lastPlayed=-math.huge}
		if sound.SoundId~="" then table.insert(preload,sound) end
		count+=1
	end
	assert(count<=16,"Level 5 audio voice budget exceeded")
	diagnostic("AudioVoiceCount",count)
	-- Never block level entry or queue a delayed gameplay event behind a download.
	-- Missing/moderated audio stays silent. Loops retry only after IsLoaded=true.
	if #preload>0 then task.spawn(function() pcall(ContentProvider.PreloadAsync,ContentProvider,preload) end) end
end
local function playableVoice(key,position)
	local voice=voices[key]
	if not world or not session or not voice or voice.sound.SoundId=="" or not voice.sound.IsLoaded then return nil end
	if os.clock()-voice.lastPlayed<(voice.cue.Cooldown or .05) then return nil end
	if voice.emitter then
		if typeof(position)~="Vector3" or not poolCamera then return nil end
		if (position-poolCamera.CFrame.Position).Magnitude>voice.sound.RollOffMaxDistance then return nil end
	end
	return voice
end
local function play(key,position)
	local voice=playableVoice(key,position);if not voice then return false end
	local now=os.clock()
	if voice.emitter then
		voice.emitter.CFrame=CFrame.new(position)
	end
	voice.lastPlayed=now;voice.expiresAt=now+(voice.cue.Duration or 5)+.5
	voice.sound:Stop();voice.sound.TimePosition=0;voice.sound.PlaybackSpeed=1
	voice.sound.Volume=voice.cue.Volume;voice.sound:Play()
	diagnostic("AudioLastCue",key)
	diagnostic("AudioCueCount",(script:GetAttribute("AudioCueCount") or 0)+1)
	return true
end
local function loop(key,gain,dt,speed,immediateSilence)
	local voice=voices[key];if not voice then return end
	local sound=voice.sound
	local target=math.clamp(gain,0,1)*voice.cue.Volume
	if immediateSilence and target==0 then stopVoice(key);return end
	if sound.SoundId=="" or not sound.IsLoaded then sound.Volume=0;return end
	sound.PlaybackSpeed=speed or 1
	sound.Volume+=(target-sound.Volume)*(1-math.exp(-math.min(dt,.2)*5))
	if target>0 and not sound.IsPlaying then sound:Play() end
	if target==0 and sound.Volume<.001 then stopVoice(key) end
end
local function participant()
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	return workspace:GetAttribute("SelectedLevel")==5 and workspace:GetAttribute("RoundActive")==true
		and player:GetAttribute("InRound")==true and player:GetAttribute("Escaped")~=true
		and player:GetAttribute("Spectating")~=true and player:GetAttribute("RoundEntryControlsReady")==true
		and humanoid and humanoid.Health>0 and root and root:IsA("BasePart") and root or nil
end
local function inside(point,minName,maxName)
	local a,b=world:GetAttribute(minName),world:GetAttribute(maxName)
	return typeof(a)=="Vector3" and typeof(b)=="Vector3"
		and Outage.ContainsPoint(point.X,point.Y,point.Z,a.X,a.Y,a.Z,b.X,b.Y,b.Z)
end
local function exemption(point)
	-- Same authoritative bounds and unknown-metadata policy as the lighting owner.
	for _,name in ipairs({"Level5OutageExemptMin","Level5OutageExemptMax","Level5OutageExitMin","Level5OutageExitMax"}) do
		if typeof(world:GetAttribute(name))~="Vector3" then return true end
	end
	return inside(point,"Level5OutageExemptMin","Level5OutageExemptMax")
		or inside(point,"Level5OutageExitMin","Level5OutageExitMax")
end
local function bindUI()
	local gui=playerGui:FindFirstChild("Level5ColourLockGui")
	local candidate=gui and gui:GetAttribute("Level5ProgressionOwned")==true and gui:FindFirstChild("Level5AudioCue") or nil
	if candidate and not candidate:IsA("BindableEvent") then candidate=nil end
	if candidate==uiEvent then return end
	if uiConnection then uiConnection:Disconnect();uiConnection=nil end
	uiEvent=candidate
	if candidate then uiConnection=candidate.Event:Connect(function(key)
		if stopped or not world or not participant() or player:GetAttribute("Level5ColourLockOpen")~=true then return end
		if key=="puzzle_click" or key=="puzzle_reject" then play(key) end
	end) end
end
local function updateGates()
	local owner=world:FindFirstChild("Level5SectionProgression")
	if not owner or owner:GetAttribute("Level5ProgressionOwned")~=true then return end
	for index=1,7 do
		local gate=owner:FindFirstChild("SectionGate"..index)
		if gate and gate:IsA("Model") and gate:GetAttribute("Level5ProgressionOwned")==true then
			local unlocked=gate:GetAttribute("Unlocked")
			-- A missing attribute is incomplete replication, not a locked gate.
			if type(unlocked)=="boolean" then
				local opened,unlockCue=Logic.Gate(session,index,gate,unlocked,gate:GetAttribute("OpenReason"),os.clock())
				if opened or unlockCue then
					local frame=gate:GetAttribute("GateFrame")
					local lock=gate:FindFirstChild("ColourPadlock")
					local position=lock and lock:IsA("BasePart") and lock.Position or typeof(frame)=="CFrame" and frame.Position
					if position then
						if unlockCue then play("puzzle_unlock",position) end
						if opened then play("sliding_gate",position) end
					end
				end
			end
		else
			-- Keep no stale Instance reference across streaming. The next model is a baseline.
			session.gates[index]=nil
		end
	end
end
local function updateWatcher(camera,dt)
	local owner=world:FindFirstChild("Level5WindowWatcherEncounters")
	local actor=owner and owner:FindFirstChild("WindowWatcher")
	local gaze=script.Parent:FindFirstChild("WindowWatcherGazeClient")
	local present=owner and owner:GetAttribute("Level5WindowWatcherOwned")==true and actor and actor:IsA("Model")
		and actor:GetAttribute("Level5WindowWatcherOwned")==true and actor:GetAttribute("SourceGlbSha256")==SHA
		and gaze and gaze:IsA("LocalScript") and gaze.Enabled==true and gaze:GetAttribute("GazeError")==nil
	local allowed=camera.CameraType==Enum.CameraType.Custom and not GuiService.MenuIsOpen
		and not UIDevice.ScreenOwningModalOpen() and not UIS:GetFocusedTextBox()
		and player:GetAttribute("DispatchBriefingOpen")~=true
	local appearance=present and owner:GetAttribute("AppearanceCount") or nil
	local coherent=present and gaze:GetAttribute("GazeAppearance")==appearance
	local hidden=present and (actor:GetAttribute("WindowWatcherGazeHidden")==true or gaze:GetAttribute("GazeHidden")==true)
	local visible=present and owner:GetAttribute("Visible")==true and actor:GetAttribute("WindowWatcherVisualReady")==true
	local lineOfSight=coherent and gaze:GetAttribute("GazeLineOfSight")==true
	local position
	if present then
		local paneRef=actor:FindFirstChild("ActiveWindowGlass")
		local pane=paneRef and paneRef:IsA("ObjectValue") and paneRef.Value
		position=pane and pane:IsA("BasePart") and pane.Position or actor:GetPivot().Position
	end
	local intensity,cues=Logic.Watcher(session,{present=coherent==true,appearance=appearance,allowed=allowed,
		visible=visible==true,hidden=hidden==true,lineOfSight=lineOfSight==true,
		glassAudible=playableVoice("watcher_glass",position)~=nil,
		breathAudible=playableVoice("watcher_breath",position)~=nil,
		recedeAudible=playableVoice("watcher_recede",position)~=nil,
		intensity=coherent and gaze:GetAttribute("GazeIntensity") or 0,
		distance=coherent and gaze:GetAttribute("GazeDistance") or nil},os.clock())
	-- Gaze intensity has a visual tail; audio stops immediately when LOS/permission
	-- is gone or the apparition hides, instead of leaking through the wall.
	loop("watcher_heartbeat",intensity*intensity,dt,1+.75*intensity,true)
	diagnostic("AudioWatcherIntensity",intensity)
	if intensity==0 then stopVoice("watcher_glass");stopVoice("watcher_breath") end
	if not coherent or not allowed or not visible or not lineOfSight then stopVoice("watcher_recede") end
	if #cues>0 and position then
		for _,key in ipairs(cues) do play(key,position) end
	end
end
local function update(dt)
	bindUI()
	local root=participant();local camera=workspace.CurrentCamera
	local nextWorld=workspace:FindFirstChild("Level 5 Generated World")
	if not root or not camera or not nextWorld or nextWorld:GetAttribute("Level5_MapOnly")~=true then
		if world or soundFolder then detach() end
		return
	end
	local generation=nextWorld:GetAttribute("Level5_Generation")
	if world~=nextWorld or worldGeneration~=generation then
		detach();world=nextWorld;worldGeneration=generation;session=Logic.New()
	end
	if not soundFolder or not soundFolder.Parent or poolCamera~=camera or not emitterFolder or not emitterFolder.Parent then createPool(camera) end
	diagnostic("AudioActive",true)
	local encoded=world:GetAttribute("Level5OutageSchedule")
	if encoded~=encodedSchedule then
		encodedSchedule=encoded;schedule=nil
		if type(encoded)=="string" then
			local ok,value=pcall(HttpService.JSONDecode,HttpService,encoded)
			if ok and Outage.ValidateSchedule(value) then schedule=value end
		end
	end
	local now=workspace:GetServerTimeNow();local exempt=exemption(root.Position)
	local phase=Outage.Phase(schedule,now)
	local power=Outage.AmbientPower(schedule,now,exempt and Outage.EXEMPT_SECTION or nil)
	local powerCue=Logic.Power(session,phase,schedule and schedule.startedAt,exempt)
	loop("room_hum",power,dt)
	loop("blackout_roomtone",exempt and 0 or 1-power,dt,1,exempt)
	if exempt then stopVoice("power_fall");stopVoice("power_restart")
	elseif powerCue then play(powerCue) end
	if phase=="BLACKOUT" then stopVoice("power_fall");stopVoice("power_restart") end
	diagnostic("AudioPhase",exempt and "NORMAL" or phase);diagnostic("AudioExempt",exempt)
	updateGates();updateWatcher(camera,dt)
	local loaded=0
	for _,voice in pairs(voices) do
		if voice.sound.SoundId~="" and voice.sound.IsLoaded then loaded+=1 end
		if voice.expiresAt and os.clock()>=voice.expiresAt then voice.sound:Stop();voice.expiresAt=nil end
	end
	diagnostic("AudioLoadedCount",loaded)
end
connect(RunService.Heartbeat,function(dt)
	if stopped then return end
	elapsed+=dt;if elapsed<.1 then return end
	local step=elapsed;elapsed=0
	local ok,detail=pcall(update,step)
	if not ok then detach();diagnostic("AudioError",tostring(detail)) else diagnostic("AudioError",nil) end
end)
connect(player.CharacterRemoving,detach)
for _,name in ipairs({"InRound","Escaped","Spectating","RoundEntryControlsReady"}) do
	connect(player:GetAttributeChangedSignal(name),function() if not participant() then detach() end end)
end
for _,name in ipairs({"SelectedLevel","RoundActive"}) do
	connect(workspace:GetAttributeChangedSignal(name),function() if not participant() then detach() end end)
end
connect(script.Destroying,function()
	stopped=true
	if uiConnection then uiConnection:Disconnect() end
	for _,connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections);detach()
end)
diagnostic("AudioActive",false);diagnostic("AudioVoiceCount",0);diagnostic("AudioCueCount",0)
