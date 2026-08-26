--!strict
-- Level 3 Music Sequence Controller
-- Owns one authoritative server clock that begins with the team's first CD
-- collection, then drives the five-second warning, the 2:30 blackout while the
-- song finishes, the final 30-second Mall Manager hunt, and the uneven
-- fluorescent recovery before the next synchronized song cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local HidingController = require(script.Parent:WaitForChild("Level 3 Hiding Controller"))

local Controller = {}

local session: {
	Generation: number,
	World: Model,
	StartServerTime: number?,
	Phase: string,
	Connection: RBXScriptConnection?,
	RoundConnection: RBXScriptConnection?,
	Cycle: number,
	BlackoutScreamTriggered: boolean,
	FurnitureRecords: {any},
	FurnitureState: string,
	FlashlightsSuppressed: boolean,
}? = nil

local function stateFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then existing:Destroy() end
	local created = Instance.new("Folder")
	created.Name = Configuration.StateFolderName
	created.Parent = ReplicatedStorage
	return created
end

local function setBlackout(active: boolean, untilTime: number)
	local state = stateFolder()
	state:SetAttribute("Level3_BlackoutActive", active)
	state:SetAttribute("Level3_BlackoutUntilServerTime", if active then untilTime else 0)
	workspace:SetAttribute("Level3BlackoutActive", active)
end

local function setPreBlackout(active: boolean, startedAt: number, untilTime: number)
	local state = stateFolder()
	state:SetAttribute("Level3_PreBlackoutActive", active)
	state:SetAttribute("Level3_PreBlackoutStartedAtServerTime", if active then startedAt else 0)
	state:SetAttribute("Level3_PreBlackoutUntilServerTime", if active then untilTime else 0)
	workspace:SetAttribute("Level3PreBlackoutActive", active)
end

local function setHunt(active: boolean)
	local state = stateFolder()
	state:SetAttribute("Level3_MallManagerHuntActive", active)
	workspace:SetAttribute("Level3MallManagerHuntActive", active)
end

local function setRecoveryFlicker(active: boolean, startedAt: number, untilTime: number)
	local state = stateFolder()
	state:SetAttribute("Level3_RecoveryFlickerActive", active)
	state:SetAttribute("Level3_RecoveryFlickerStartedAtServerTime", if active then startedAt else 0)
	state:SetAttribute("Level3_RecoveryFlickerUntilServerTime", if active then untilTime else 0)
	workspace:SetAttribute("Level3RecoveryFlickerActive", active)
end

local function setFlashlightsSuppressed(activeSession: any, active: boolean)
	active = active == true
	if activeSession.FlashlightsSuppressed == active then return end
	activeSession.FlashlightsSuppressed = active
	stateFolder():SetAttribute("Level3_FlashlightsSuppressed", active)
	workspace:SetAttribute("Level3FlashlightsSuppressed", active)
end

local function publishFurnitureState(stateName: string)
	local removed = stateName == "REMOVED"
	local collisionSuppressed = stateName ~= "RESTORED"
	local state = stateFolder()
	state:SetAttribute("Level3_FurnitureTemporarilyRemoved", removed)
	state:SetAttribute("Level3_FurnitureCollisionSuppressed", collisionSuppressed)
	workspace:SetAttribute("Level3FurnitureTemporarilyRemoved", removed)
	workspace:SetAttribute("Level3FurnitureCollisionSuppressed", collisionSuppressed)
end

local function captureFurniture(activeSession: any)
	if #activeSession.FurnitureRecords > 0 then return end
	for _, object in ipairs(activeSession.World:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_TemporaryHuntFurniture") == true then
			local visualRecords = {}
			for _, visual in ipairs(object:GetDescendants()) do
				if visual:IsA("Decal") or visual:IsA("Texture") then
					table.insert(visualRecords, {Object=visual, Transparency=visual.Transparency})
				end
			end
			table.insert(activeSession.FurnitureRecords, {
				Part=object,
				Transparency=object.Transparency,
				CanCollide=object.CanCollide,
				CanTouch=object.CanTouch,
				CanQuery=object.CanQuery,
				CastShadow=object.CastShadow,
				Visuals=visualRecords,
			})
		end
	end
end

local function setFurnitureState(activeSession: any, stateName: string)
	if activeSession.FurnitureState == stateName then return end
	if stateName ~= "RESTORED" then captureFurniture(activeSession) end
	activeSession.FurnitureState = stateName
	HidingController.SetFurnitureSuspended(stateName ~= "RESTORED")

	for _, record in ipairs(activeSession.FurnitureRecords) do
		local part = record.Part
		if part and part.Parent and part:IsA("BasePart") then
			if stateName == "REMOVED" then
				part.Transparency = 1
				part.CastShadow = false
			else
				part.Transparency = record.Transparency
				part.CastShadow = record.CastShadow
			end
			if stateName == "RESTORED" then
				part.CanCollide = record.CanCollide
				part.CanTouch = record.CanTouch
				part.CanQuery = record.CanQuery
			else
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		for _, visualRecord in ipairs(record.Visuals) do
			local visual = visualRecord.Object
			if visual and visual.Parent and (visual:IsA("Decal") or visual:IsA("Texture")) then
				visual.Transparency = if stateName == "REMOVED" then 1 else visualRecord.Transparency
			end
		end
	end

	publishFurnitureState(stateName)
	if stateName == "RESTORED" then table.clear(activeSession.FurnitureRecords) end
end

local function updateBlackoutEdges(activeSession: any, elapsed: number)
	local songEnd = Configuration.MusicSequence.DurationSeconds
	local screamStart = songEnd - Configuration.MusicSequence.BlackoutScreamLeadSeconds
	local removalStart = screamStart - Configuration.MusicSequence.FurnitureRemovalLeadSeconds
	local huntEnd = Configuration.MusicSequence.CycleEndSeconds
	local finalLockStart = huntEnd - Configuration.MusicSequence.HuntFinalFlashlightLockSeconds

	if elapsed >= removalStart and elapsed < finalLockStart then
		setFurnitureState(activeSession, "REMOVED")
	elseif elapsed >= finalLockStart and elapsed < huntEnd then
		-- Reappear for the final reveal, but remain physically absent until the
		-- Manager despawns so neither the NPC nor a player can be trapped.
		setFurnitureState(activeSession, "VISIBLE_GHOST")
	else
		setFurnitureState(activeSession, "RESTORED")
	end

	local firstLock = elapsed >= removalStart and elapsed < screamStart
	local finalLock = elapsed >= finalLockStart and elapsed < huntEnd
	setFlashlightsSuppressed(activeSession, firstLock or finalLock)
end

local function shiftBlackoutChairs(activeSession: any)
	if activeSession.ChairsShifted then return end
	activeSession.ChairsShifted = true
	local chairs = {}
	for _, object in ipairs(activeSession.World:GetDescendants()) do
		if object:IsA("BasePart") and object.Name == "Level 3 Vetted Plastic Party Chair" then
			table.insert(chairs, object)
		end
	end
	table.sort(chairs, function(a, b)
		if a.Position.X == b.Position.X then return a.Position.Z < b.Position.Z end
		return a.Position.X < b.Position.X
	end)
	local selected = {chairs[math.max(1, math.floor(#chairs * .24))],
		chairs[math.max(1, math.floor(#chairs * .57))],
		chairs[math.max(1, math.floor(#chairs * .82))]}
	for index, chair in ipairs(selected) do
		if chair and chair.Parent and chair:GetAttribute("Level3_BlackoutShifted") ~= true then
			chair.CFrame = chair.CFrame * CFrame.new((index - 2) * .55, 0, 1.15)
				* CFrame.Angles(0, math.rad(index % 2 == 0 and 18 or -14), 0)
			chair:SetAttribute("Level3_BlackoutShifted", true)
		end
	end
end

local function triggerBlackoutScream(activeSession: any)
	if activeSession.BlackoutScreamTriggered or not activeSession.StartServerTime then return end
	activeSession.BlackoutScreamTriggered = true
	local state = stateFolder()
	local screamStartedAt = activeSession.StartServerTime
		+ Configuration.MusicSequence.DurationSeconds
		- Configuration.MusicSequence.BlackoutScreamLeadSeconds
	-- Timestamp first, serial second: clients that receive the edge late can seek
	-- into the same absolute scream instead of restarting it from the beginning.
	state:SetAttribute("Level3_BlackoutScreamStartedAtServerTime", screamStartedAt)
	state:SetAttribute("Level3_BlackoutSerial",
		(state:GetAttribute("Level3_BlackoutSerial") or 0) + 1)
	local remotes = ReplicatedStorage:FindFirstChild(Configuration.RemotesFolderName)
	local event = remotes and remotes:FindFirstChild(Configuration.ClientEventName)
	if event and event:IsA("RemoteEvent") then
		event:FireAllClients({
			Type = "Sound",
			Cue = "PowerDown",
			Generation = activeSession.Generation,
		})
	end
end

local function setPhase(activeSession: any, phase: string)
	if activeSession.Phase == phase then return end
	activeSession.Phase = phase
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongPhase", phase)
	local startTime = activeSession.StartServerTime
	if phase == "PRE_BLACKOUT" and startTime then
		setBlackout(false, 0)
		setHunt(false)
		setRecoveryFlicker(false, 0, 0)
		local warningStartedAt = startTime + Configuration.MusicSequence.BlackoutStartSeconds
			- Configuration.MusicSequence.PreBlackoutFlickerSeconds
		local warningUntil = startTime + Configuration.MusicSequence.BlackoutStartSeconds
		state:SetAttribute("Level3_PreBlackoutSerial",
			(state:GetAttribute("Level3_PreBlackoutSerial") or 0) + 1)
		setPreBlackout(true, warningStartedAt, warningUntil)
	elseif phase == "BLACKOUT_SONG" and startTime then
		setPreBlackout(false, 0, 0)
		setHunt(false)
		setRecoveryFlicker(false, 0, 0)
		shiftBlackoutChairs(activeSession)
		local blackoutStartedAt = startTime + Configuration.MusicSequence.BlackoutStartSeconds
		local untilTime = startTime + Configuration.MusicSequence.CycleEndSeconds
		state:SetAttribute("Level3_BlackoutStartedAtServerTime", blackoutStartedAt)
		setBlackout(true, untilTime)
	elseif phase == "BLACKOUT_HUNT" and startTime then
		setPreBlackout(false, 0, 0)
		setRecoveryFlicker(false, 0, 0)
		local untilTime = startTime + Configuration.MusicSequence.CycleEndSeconds
		setBlackout(true, untilTime)
		-- The Manager still spawns only after the song ends. The scream edge is
		-- scheduled independently during the final three seconds of the song.
		setHunt(true)
	elseif phase == "RECOVERY_FLICKER" and startTime then
		setPreBlackout(false, 0, 0)
		setHunt(false)
		setBlackout(false, 0)
		local recoveryStartedAt = startTime + Configuration.MusicSequence.CycleEndSeconds
		setRecoveryFlicker(true, recoveryStartedAt,
			recoveryStartedAt + Configuration.MusicSequence.RecoveryFlickerSeconds)
	else
		-- Backward Studio seeks and every idle/done phase restore all timeline flags.
		setPreBlackout(false, 0, 0)
		setHunt(false)
		setRecoveryFlicker(false, 0, 0)
		setBlackout(false, 0)
		setFurnitureState(activeSession, "RESTORED")
		setFlashlightsSuppressed(activeSession, false)
	end
end

local function arm(activeSession: any)
	if activeSession.StartServerTime then return end
	if workspace:GetAttribute("SelectedLevel") ~= 3
		or workspace:GetAttribute("RoundActive") ~= true then
		setPhase(activeSession, "WAITING_FOR_ROUND")
		return
	end

	-- The normal room song must stay silent at spawn. CollectedCount is shared
	-- across the whole round and only advances for a CD's first successful pickup,
	-- so this gate starts one synchronized timeline without restarting for later CDs.
	local state = stateFolder()
	local collectedProgress = tonumber(state:GetAttribute("Level3_CDCollectedProgress")) or 0
	if collectedProgress < 1 then
		setPhase(activeSession, "WAITING_FOR_FIRST_CD")
		return
	end

	local startTime = workspace:GetServerTimeNow() + Configuration.MusicSequence.PreloadLeadSeconds
	activeSession.StartServerTime = startTime
	activeSession.Cycle += 1
	activeSession.BlackoutScreamTriggered = false
	state:SetAttribute("Level3_RoomSongCycle", activeSession.Cycle)
	state:SetAttribute("Level3_RoomSongStartServerTime", startTime)
	state:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_BlackoutStartSeconds", Configuration.MusicSequence.BlackoutStartSeconds)
	state:SetAttribute("Level3_RoomSongStopSeconds", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_PreBlackoutDuration", Configuration.MusicSequence.PreBlackoutFlickerSeconds)
	state:SetAttribute("Level3_BlackoutScreamLeadSeconds", Configuration.MusicSequence.BlackoutScreamLeadSeconds)
	state:SetAttribute("Level3_PostSongBlackoutDuration", Configuration.MusicSequence.PostSongBlackoutSeconds)
	state:SetAttribute("Level3_CycleEndSeconds", Configuration.MusicSequence.CycleEndSeconds)
	state:SetAttribute("Level3_RecoveryFlickerDuration", Configuration.MusicSequence.RecoveryFlickerSeconds)
	state:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
	state:SetAttribute("Level3_BlackoutScreamAssetId", Configuration.Audio.MallManagerBlackout)
	state:SetAttribute("Level3_BlackoutScreamStartedAtServerTime", 0)
	state:SetAttribute("Level3_BlackoutScreamDuration", Configuration.MallManager.BlackoutScreamDurationSeconds)
	state:SetAttribute("Level3_BlackoutScreamVolume", Configuration.MallManager.BlackoutScreamVolume)
	setPhase(activeSession, "ARMED")
end

local function update(activeSession: any)
	if session ~= activeSession
		or not activeSession.World.Parent
		or activeSession.World:GetAttribute("Level3_Generation") ~= activeSession.Generation then
		return
	end
	if not activeSession.StartServerTime then
		arm(activeSession)
		return
	end

	local state = stateFolder()
	local progress = tonumber(state:GetAttribute("Level3_ModuleProgress")) or 0
	local goal = tonumber(state:GetAttribute("Level3_ModuleGoal")) or Configuration.ModuleGoal
	if progress >= goal then
		setPhase(activeSession, "DONE")
		setFurnitureState(activeSession, "RESTORED")
		setFlashlightsSuppressed(activeSession, false)
		return
	end
	local elapsed = workspace:GetServerTimeNow() - activeSession.StartServerTime
	local blackoutStart = Configuration.MusicSequence.BlackoutStartSeconds
	local warningStart = blackoutStart - Configuration.MusicSequence.PreBlackoutFlickerSeconds
	local songEnd = Configuration.MusicSequence.DurationSeconds
	local screamStart = songEnd - Configuration.MusicSequence.BlackoutScreamLeadSeconds
	local huntEnd = Configuration.MusicSequence.CycleEndSeconds
	local recoveryEnd = huntEnd + Configuration.MusicSequence.RecoveryFlickerSeconds
	if elapsed < 0 then
		setPhase(activeSession, "ARMED")
	elseif elapsed < warningStart then
		setPhase(activeSession, "PLAYING")
	elseif elapsed < blackoutStart then
		setPhase(activeSession, "PRE_BLACKOUT")
	elseif elapsed < songEnd then
		setPhase(activeSession, "BLACKOUT_SONG")
		if elapsed >= screamStart then triggerBlackoutScream(activeSession) end
	elseif elapsed < huntEnd then
		setPhase(activeSession, "BLACKOUT_HUNT")
		-- Missed-frame/debug-seek safety: preserve the original T-3 timestamp.
		triggerBlackoutScream(activeSession)
	elseif elapsed < recoveryEnd then
		setPhase(activeSession, "RECOVERY_FLICKER")
	else
		setPhase(activeSession, "RESTARTING")
		activeSession.StartServerTime = nil
		arm(activeSession)
	end
	updateBlackoutEdges(activeSession, elapsed)
end

function Controller.Stop()
	local old = session
	if old then
		if old.Connection then old.Connection:Disconnect() end
		if old.RoundConnection then old.RoundConnection:Disconnect() end
		setFurnitureState(old, "RESTORED")
		setFlashlightsSuppressed(old, false)
	end
	session = nil
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongPhase", "STOPPED")
	state:SetAttribute("Level3_ReversedRoomSongAssetId", Configuration.Audio.RoomListeningSongReversed)
	state:SetAttribute("Level3_CompletionSongPitchOctave", Configuration.MusicSequence.CompletionSongPitchOctave)
	state:SetAttribute("Level3_CompletionSongVolume", Configuration.MusicSequence.CompletionSongVolume)
	state:SetAttribute("Level3_RoomSongStartServerTime", 0)
	state:SetAttribute("Level3_CompletionSongStartServerTime", 0)
	state:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_BlackoutStartSeconds", Configuration.MusicSequence.BlackoutStartSeconds)
	state:SetAttribute("Level3_RoomSongStopSeconds", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_PreBlackoutDuration", Configuration.MusicSequence.PreBlackoutFlickerSeconds)
	state:SetAttribute("Level3_BlackoutScreamLeadSeconds", Configuration.MusicSequence.BlackoutScreamLeadSeconds)
	state:SetAttribute("Level3_PostSongBlackoutDuration", Configuration.MusicSequence.PostSongBlackoutSeconds)
	state:SetAttribute("Level3_CycleEndSeconds", Configuration.MusicSequence.CycleEndSeconds)
	state:SetAttribute("Level3_RecoveryFlickerDuration", Configuration.MusicSequence.RecoveryFlickerSeconds)
	state:SetAttribute("Level3_PreBlackoutStartedAtServerTime", 0)
	state:SetAttribute("Level3_PreBlackoutUntilServerTime", 0)
	state:SetAttribute("Level3_PreBlackoutSerial", 0)
	state:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
	state:SetAttribute("Level3_BlackoutScreamAssetId", Configuration.Audio.MallManagerBlackout)
	state:SetAttribute("Level3_BlackoutScreamDuration", Configuration.MallManager.BlackoutScreamDurationSeconds)
	state:SetAttribute("Level3_BlackoutScreamVolume", Configuration.MallManager.BlackoutScreamVolume)
	state:SetAttribute("Level3_BlackoutScreamStartedAtServerTime", 0)
	state:SetAttribute("Level3_MallManagerHuntActive", false)
	state:SetAttribute("Level3_RecoveryFlickerActive", false)
	state:SetAttribute("Level3_RecoveryFlickerStartedAtServerTime", 0)
	state:SetAttribute("Level3_RecoveryFlickerUntilServerTime", 0)
	state:SetAttribute("Level3_BlackoutStartedAtServerTime", 0)
	state:SetAttribute("Level3_BlackoutSerial", 0)
	state:SetAttribute("Level3_RoomSongCycle", 0)
	setPreBlackout(false, 0, 0)
	setHunt(false)
	setRecoveryFlicker(false, 0, 0)
	setBlackout(false, 0)
end

function Controller.Start(manifest: any, generation: number)
	Controller.Stop()
	assert(type(manifest) == "table" and manifest.World and manifest.World:IsA("Model"),
		"Level 3 music sequence requires a live manifest world")
	assert(manifest.World.Parent == workspace, "Level 3 music sequence world is not live")
	assert(manifest.World:GetAttribute("Level3_Generation") == generation,
		"Level 3 music sequence generation mismatch")

	local activeSession: any = {
		Generation = generation,
		World = manifest.World,
		StartServerTime = nil,
		Phase = "STOPPED",
		Connection = nil,
		RoundConnection = nil,
		Cycle = 0,
		BlackoutScreamTriggered = false,
		FurnitureRecords = {},
		FurnitureState = "RESTORED",
		FlashlightsSuppressed = false,
	}
	session = activeSession
	local devSkip = ServerStorage:FindFirstChild("Level3DevSkipToPreBlackout")
	if devSkip and not devSkip:IsA("BindableFunction") then devSkip:Destroy(); devSkip = nil end
	if not devSkip then
		devSkip = Instance.new("BindableFunction")
		devSkip.Name = "Level3DevSkipToPreBlackout"
		devSkip.Parent = ServerStorage
	end
	(devSkip :: BindableFunction).OnInvoke = function()
		return Controller.DevSkipToPreBlackout()
	end
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongGeneration", generation)
	state:SetAttribute("Level3_RoomSongAssetId", Configuration.Audio.RoomListeningSong)
	state:SetAttribute("Level3_ReversedRoomSongAssetId", Configuration.Audio.RoomListeningSongReversed)
	state:SetAttribute("Level3_CompletionSongPitchOctave", Configuration.MusicSequence.CompletionSongPitchOctave)
	state:SetAttribute("Level3_CompletionSongVolume", Configuration.MusicSequence.CompletionSongVolume)
	state:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_BlackoutStartSeconds", Configuration.MusicSequence.BlackoutStartSeconds)
	state:SetAttribute("Level3_RoomSongStopSeconds", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_PreBlackoutDuration", Configuration.MusicSequence.PreBlackoutFlickerSeconds)
	state:SetAttribute("Level3_BlackoutScreamLeadSeconds", Configuration.MusicSequence.BlackoutScreamLeadSeconds)
	state:SetAttribute("Level3_PostSongBlackoutDuration", Configuration.MusicSequence.PostSongBlackoutSeconds)
	state:SetAttribute("Level3_CycleEndSeconds", Configuration.MusicSequence.CycleEndSeconds)
	state:SetAttribute("Level3_RecoveryFlickerDuration", Configuration.MusicSequence.RecoveryFlickerSeconds)
	state:SetAttribute("Level3_PreBlackoutStartedAtServerTime", 0)
	state:SetAttribute("Level3_PreBlackoutUntilServerTime", 0)
	state:SetAttribute("Level3_PreBlackoutSerial", 0)
	state:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
	state:SetAttribute("Level3_BlackoutScreamAssetId", Configuration.Audio.MallManagerBlackout)
	state:SetAttribute("Level3_BlackoutScreamDuration", Configuration.MallManager.BlackoutScreamDurationSeconds)
	state:SetAttribute("Level3_BlackoutScreamVolume", Configuration.MallManager.BlackoutScreamVolume)
	state:SetAttribute("Level3_BlackoutScreamStartedAtServerTime", 0)
	state:SetAttribute("Level3_MallManagerHuntActive", false)
	state:SetAttribute("Level3_RecoveryFlickerActive", false)
	state:SetAttribute("Level3_RecoveryFlickerStartedAtServerTime", 0)
	state:SetAttribute("Level3_RecoveryFlickerUntilServerTime", 0)
	state:SetAttribute("Level3_BlackoutSerial", 0)
	setPhase(activeSession, "WAITING_FOR_ROUND")
	activeSession.RoundConnection = workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
		arm(activeSession)
	end)

	local accumulated = 0
	activeSession.Connection = RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < .05 then return end
		accumulated = 0
		update(activeSession)
	end)
	arm(activeSession)
	return activeSession
end

function Controller.GetSnapshot()
	local activeSession = session
	if not activeSession then return nil end
	return {
		Generation = activeSession.Generation,
		Phase = activeSession.Phase,
		StartServerTime = activeSession.StartServerTime,
		SongDuration = Configuration.MusicSequence.DurationSeconds,
		BlackoutStart = Configuration.MusicSequence.BlackoutStartSeconds,
		PreBlackoutDuration = Configuration.MusicSequence.PreBlackoutFlickerSeconds,
		BlackoutScreamLead = Configuration.MusicSequence.BlackoutScreamLeadSeconds,
		FurnitureState = activeSession.FurnitureState,
		FlashlightsSuppressed = activeSession.FlashlightsSuppressed,
		PreBlackoutActive = stateFolder():GetAttribute("Level3_PreBlackoutActive") == true,
		BlackoutDuration = Configuration.MusicSequence.BlackoutSeconds,
		HuntActive = stateFolder():GetAttribute("Level3_MallManagerHuntActive") == true,
		RecoveryFlickerActive = stateFolder():GetAttribute("Level3_RecoveryFlickerActive") == true,
		BlackoutActive = stateFolder():GetAttribute("Level3_BlackoutActive") == true,
	}
end

function Controller.DevSkipToPreBlackout(): (boolean, string, any?)
	local activeSession = session
	if not activeSession or not activeSession.World or not activeSession.World.Parent
		or activeSession.World:GetAttribute("Level3_Generation") ~= activeSession.Generation then
		return false, "NOT_RUNNING", nil
	end
	if workspace:GetAttribute("SelectedLevel") ~= 3
		or workspace:GetAttribute("RoundActive") ~= true then
		return false, "LEVEL_3_ONLY", nil
	end
	if not activeSession.StartServerTime then return false, "NOT_ARMED", nil end
	local state = stateFolder()
	local progress = tonumber(state:GetAttribute("Level3_ModuleProgress")) or 0
	local goal = tonumber(state:GetAttribute("Level3_ModuleGoal")) or Configuration.ModuleGoal
	if progress >= goal then return false, "OBJECTIVE_COMPLETE", nil end

	local warningStart = Configuration.MusicSequence.BlackoutStartSeconds
		- Configuration.MusicSequence.PreBlackoutFlickerSeconds
	local now = workspace:GetServerTimeNow()
	local elapsed = now - activeSession.StartServerTime
	-- Forward-only and idempotent: repeat presses can never rewind or retrigger
	-- the warning, blackout, scream, or hunt.
	if elapsed >= warningStart - .02 then
		return false, "ALREADY_AT_OR_PAST_WARNING", Controller.GetSnapshot()
	end

	activeSession.StartServerTime = now - warningStart
	activeSession.Phase = "DEV_SEEK"
	state:SetAttribute("Level3_RoomSongStartServerTime", activeSession.StartServerTime)
	update(activeSession)
	return true, "SKIPPED_TO_2_25", Controller.GetSnapshot()
end

function Controller.DebugSetElapsed(elapsed: number)
	assert(RunService:IsStudio(), "DebugSetElapsed is Studio-only")
	local activeSession = assert(session, "Level 3 music sequence is not running")
	activeSession.StartServerTime = workspace:GetServerTimeNow() - math.max(0, elapsed)
	-- Debug timeline seeks must be able to traverse backward through phases;
	-- production remains strictly monotonic.
	activeSession.Phase = "DEBUG_SEEK"
	stateFolder():SetAttribute("Level3_RoomSongStartServerTime", activeSession.StartServerTime)
	update(activeSession)
	return Controller.GetSnapshot()
end

return Controller
