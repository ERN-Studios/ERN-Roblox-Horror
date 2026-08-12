--!strict
-- Level 3 Music Sequence Controller
-- Owns one authoritative server clock for the full-room song and the exact
-- thirty-second blackout which follows it. Audio playback stays client-side so
-- every listener can receive room/corridor acoustics without timeline drift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))

local Controller = {}

local session: {
	Generation: number,
	World: Model,
	StartServerTime: number?,
	Phase: string,
	Connection: RBXScriptConnection?,
	RoundConnection: RBXScriptConnection?,
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

local function setPhase(activeSession: any, phase: string)
	if activeSession.Phase == phase then return end
	activeSession.Phase = phase
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongPhase", phase)
	if phase == "BLACKOUT" then
		-- Monotonic replicated edge: clients must hear the power-down cue even
		-- when a fast timeline correction skips over their local phase poll.
		state:SetAttribute("Level3_BlackoutSerial",
			(state:GetAttribute("Level3_BlackoutSerial") or 0) + 1)
		local startTime = activeSession.StartServerTime :: number
		local untilTime = startTime + Configuration.MusicSequence.DurationSeconds
			+ Configuration.MusicSequence.BlackoutSeconds
		state:SetAttribute("Level3_BlackoutStartedAtServerTime",
			startTime + Configuration.MusicSequence.DurationSeconds)
		setBlackout(true, untilTime)
	elseif phase == "DONE" or phase == "STOPPED" or phase == "WAITING_FOR_ROUND" then
		setBlackout(false, 0)
	end
end

local function arm(activeSession: any)
	if activeSession.StartServerTime then return end
	if workspace:GetAttribute("SelectedLevel") ~= 3
		or workspace:GetAttribute("RoundActive") ~= true then
		setPhase(activeSession, "WAITING_FOR_ROUND")
		return
	end
	local startTime = workspace:GetServerTimeNow() + Configuration.MusicSequence.PreloadLeadSeconds
	activeSession.StartServerTime = startTime
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongStartServerTime", startTime)
	state:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
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

	local elapsed = workspace:GetServerTimeNow() - activeSession.StartServerTime
	local songEnd = Configuration.MusicSequence.DurationSeconds
	local blackoutEnd = songEnd + Configuration.MusicSequence.BlackoutSeconds
	if elapsed < 0 then
		setPhase(activeSession, "ARMED")
	elseif elapsed < songEnd then
		setPhase(activeSession, "PLAYING")
	elseif elapsed < blackoutEnd then
		setPhase(activeSession, "BLACKOUT")
	else
		setPhase(activeSession, "DONE")
	end
end

function Controller.Stop()
	local old = session
	session = nil
	if old then
		if old.Connection then old.Connection:Disconnect() end
		if old.RoundConnection then old.RoundConnection:Disconnect() end
	end
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongPhase", "STOPPED")
	state:SetAttribute("Level3_RoomSongStartServerTime", 0)
	state:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
	state:SetAttribute("Level3_BlackoutStartedAtServerTime", 0)
	state:SetAttribute("Level3_BlackoutSerial", 0)
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
	}
	session = activeSession
	local state = stateFolder()
	state:SetAttribute("Level3_RoomSongGeneration", generation)
	state:SetAttribute("Level3_RoomSongAssetId", Configuration.Audio.RoomListeningSong)
	state:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	state:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
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
		BlackoutDuration = Configuration.MusicSequence.BlackoutSeconds,
		BlackoutActive = stateFolder():GetAttribute("Level3_BlackoutActive") == true,
	}
end

function Controller.DebugSetElapsed(elapsed: number)
	assert(RunService:IsStudio(), "DebugSetElapsed is Studio-only")
	local activeSession = assert(session, "Level 3 music sequence is not running")
	activeSession.StartServerTime = workspace:GetServerTimeNow() - math.max(0, elapsed)
	stateFolder():SetAttribute("Level3_RoomSongStartServerTime", activeSession.StartServerTime)
	update(activeSession)
	return Controller.GetSnapshot()
end

return Controller
