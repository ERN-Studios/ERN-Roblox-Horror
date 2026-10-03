-- Level 6 Preview Runtime (renamed to Level 6 Playground Game)
--!strict
-- Isolated developer preview lifecycle. No shared round, lobby, reward, or progression writes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local Configuration = require(script.Parent:WaitForChild("Level 6 Configuration"))
local RuntimeBake = require(script.Parent:WaitForChild("Level6BlenderRuntimeBake"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 6 Layout Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 6 World Builder"))
local VisualAdapter = require(script.Parent:WaitForChild("Level 6 Visual Adapter"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 6 Objective Controller"))
local HidingController = require(script.Parent:WaitForChild("Level 6 Hiding Controller"))
local MusicSequenceController = require(script.Parent:WaitForChild("Level 6 Music Sequence Controller"))
local MallManagerController = require(script.Parent:WaitForChild("Level 6 Mall Manager AI Controller"))

local Runtime = {}
local activeManifest: any = nil
local generation = 0
local building = false
local buildError: string? = nil
local stale = false
local playing = false
local participants: {[Player]: any} = {}
local managerConnection: RBXScriptConnection? = nil
local managerToken = 0
local MAX_SEED = 2147483646

local function ownedFolder(parent: Instance, name: string): Folder
    local old = parent:FindFirstChild(name)
    if old then assert(old:IsA("Folder"), name .. " has the wrong class") return old end
    local object = Instance.new("Folder")
    object.Name = name
    object.Parent = parent
    return object
end

local function state(): Folder
    return ownedFolder(ReplicatedStorage, Configuration.StateFolderName)
end

local function infrastructure()
    local remotes = ownedFolder(ReplicatedStorage, Configuration.RemotesFolderName)
    for _, spec in ipairs({
        {Configuration.ClientEventName, "RemoteEvent"},
        {Configuration.HideRequestEventName, "RemoteEvent"},
        {Configuration.MallManagerMotionEventName, "UnreliableRemoteEvent"},
    }) do
        local old = remotes:FindFirstChild(spec[1])
        if old then
            assert(old.ClassName == spec[2], "Level 6 remote class mismatch")
        else
            local object = Instance.new(spec[2])
            object.Name = spec[1]
            object.Parent = remotes
        end
    end
end

local function applyBaselineReplicatedState(levelState: Folder, overrides: {[string]: any}?)
	local o = overrides or {}
	-- Retired with the furniture state machine (LEVEL3_PERMANENT_FURNITURE_20260828).
	-- The state folder is a saved place object, so a stale replicated flag would
	-- otherwise outlive the code that wrote it.
	levelState:SetAttribute("Level6_FurnitureTemporarilyRemoved", nil)
	levelState:SetAttribute("Level6_FurnitureCollisionSuppressed", nil)
	levelState:SetAttribute("Level6_Phase", o.Phase or "IDLE")
	levelState:SetAttribute("Level6_RequestedSeed", o.RequestedSeed or 0)
	-- Visible in the state folder so "why is the map the same?" is one glance,
	-- the same readback Level 2 publishes as Level2_SeedPinned.
	levelState:SetAttribute("Level6_SeedPinned", o.SeedPinned == true)
	levelState:SetAttribute("Level6_ResolvedSeed", 0)
	levelState:SetAttribute("Level6_GenerationAttempt", 0)
	levelState:SetAttribute("Level6_UsedFallback", false)
	levelState:SetAttribute("Level6_LayoutHash", "")
	levelState:SetAttribute("Level6_GeneratorVersion", LayoutGenerator.Version)
	levelState:SetAttribute("Level6_GeneratedRoomCount", 0)
	levelState:SetAttribute("Level6_AuthoredGatewayRoomCount", 0)
	levelState:SetAttribute("Level6_AuthoredGatewayFloorArea", 0)
	levelState:SetAttribute("Level6_GeneratedCorridorCount", 0)
	levelState:SetAttribute("Level6_GeneratedDistrictCount", 0)
	if o.Generation ~= nil then
		levelState:SetAttribute("Level6_Generation", o.Generation)
	end
	levelState:SetAttribute("Level6_ModuleProgress", 0)
	levelState:SetAttribute("Level6_ModuleGoal", o.ModuleGoal or 0)
	levelState:SetAttribute("Level6_CDCollectedProgress", 0)
	levelState:SetAttribute("Level6_CDInsertedProgress", 0)
	levelState:SetAttribute("Level6_CDCarriedCount", 0)
	levelState:SetAttribute("Level6_CDDroppedCount", 0)
	levelState:SetAttribute("Level6_ExitUnlocked", false)
	levelState:SetAttribute("Level6_ExitPosition", nil)
	levelState:SetAttribute("Level6_LightingMode", o.LightingMode or "OFF")
	levelState:SetAttribute("Level6_RoomSongPhase", o.RoomSongPhase or "STOPPED")
	levelState:SetAttribute("Level6_RoomSongStartServerTime", 0)
	levelState:SetAttribute("Level6_CompletionSongStartServerTime", 0)
	levelState:SetAttribute("Level6_CompletionDimStartedAtServerTime", 0)
	levelState:SetAttribute("Level6_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	levelState:SetAttribute("Level6_FinalHallEligibleCount", 0)
	levelState:SetAttribute("Level6_FinalHallCrossedCount", 0)
	levelState:SetAttribute("Level6_FinalHallChaseTriggered", false)
	levelState:SetAttribute("Level6_FinalHallChaseActive", false)
	levelState:SetAttribute("Level6_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	levelState:SetAttribute("Level6_BlackoutStartSeconds", Configuration.MusicSequence.BlackoutStartSeconds)
	levelState:SetAttribute("Level6_RoomSongStopSeconds", Configuration.MusicSequence.DurationSeconds)
	levelState:SetAttribute("Level6_PreBlackoutDuration", Configuration.MusicSequence.PreBlackoutFlickerSeconds)
	levelState:SetAttribute("Level6_PreBlackoutStartedAtServerTime", 0)
	levelState:SetAttribute("Level6_PreBlackoutUntilServerTime", 0)
	levelState:SetAttribute("Level6_PreBlackoutSerial", 0)
	levelState:SetAttribute("Level6_PreBlackoutActive", false)
	levelState:SetAttribute("Level6_PostSongBlackoutDuration", Configuration.MusicSequence.PostSongBlackoutSeconds)
	levelState:SetAttribute("Level6_CycleEndSeconds", Configuration.MusicSequence.CycleEndSeconds)
	levelState:SetAttribute("Level6_RecoveryFlickerDuration", Configuration.MusicSequence.RecoveryFlickerSeconds)
	levelState:SetAttribute("Level6_RecoveryFlickerStartedAtServerTime", 0)
	levelState:SetAttribute("Level6_RecoveryFlickerUntilServerTime", 0)
	levelState:SetAttribute("Level6_RecoveryFlickerActive", false)
	levelState:SetAttribute("Level6_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
	levelState:SetAttribute("Level6_BlackoutStartedAtServerTime", 0)
	levelState:SetAttribute("Level6_BlackoutUntilServerTime", 0)
	levelState:SetAttribute("Level6_BlackoutActive", false)
	levelState:SetAttribute("Level6_BlackoutScreamAssetId", Configuration.Audio.MallManagerBlackout)
	levelState:SetAttribute("Level6_BlackoutScreamDuration", Configuration.MallManager.BlackoutScreamDurationSeconds)
	levelState:SetAttribute("Level6_BlackoutScreamVolume", Configuration.MallManager.BlackoutScreamVolume)
	levelState:SetAttribute("Level6_BlackoutScreamStartedAtServerTime", 0)
	levelState:SetAttribute("Level6_MallManagerHuntActive", false)
	levelState:SetAttribute("Level6_FlashlightsSuppressed", false)
	levelState:SetAttribute("Level6_BlackoutScreamOpeningCount", 0)
	levelState:SetAttribute("Level6_MallManagerActive", false)
	levelState:SetAttribute("Level6_MallManagerState", "OFF")
	levelState:SetAttribute("Level6_MallManagerBlackoutBoosted", false)
	levelState:SetAttribute("Level6_MallManagerTargetUserId", 0)
	levelState:SetAttribute("Level6_MallManagerSpeed", 0)
	levelState:SetAttribute("Level6_MallManagerAwarenessRange", 0)
	levelState:SetAttribute("Level6_MallManagerSpawnRoomId", Configuration.MallManager.SpawnRoomId)
	levelState:SetAttribute("Level6_MallManagerSpawnDistance", 0)
	levelState:SetAttribute("Level6_MallManagerSpawnAnchorUserId", 0)
	levelState:SetAttribute("Level6_MallManagerSpawnGroupSize", 0)
	levelState:SetAttribute("Level6_MallManagerSpawnCycle", 0)
	levelState:SetAttribute("Level6_MallManagerSpawnSerial", 0)
	levelState:SetAttribute("Level6_MallManagerPathStatus", "OFF")
	levelState:SetAttribute("Level6_MallManagerAttackSerial", 0)
	levelState:SetAttribute("Level6_MallManagerLastCaptureUserId", 0)
	levelState:SetAttribute("Level6_MallManagerChaseScreamSerial", 0)
	levelState:SetAttribute("Level6_MallManagerChaseScreamPlaying", false)
	levelState:SetAttribute("Level6_MallManagerLastChaseScreamAtServerTime", 0)
	levelState:SetAttribute("Level6_MallManagerLastChaseScreamName", "")
	levelState:SetAttribute("Level6_HiddenPlayers", 0)
	levelState:SetAttribute("Level6_Error", nil)
end


local function countParticipants(): number
    local count = 0
    for player in pairs(participants) do
        if player.Parent == Players and player:GetAttribute("Level6InRound") == true then count += 1 end
    end
    return count
end

local function disconnectManager()
    managerToken += 1
    if managerConnection then managerConnection:Disconnect() managerConnection = nil end
end

local function stopControllers()
    disconnectManager()
    workspace:SetAttribute("Level6RoundActive", false)
    MallManagerController.Stop()
    HidingController.Stop()
    MusicSequenceController.Stop()
    ObjectiveController.Stop()
    workspace:SetAttribute("Level6LightingOwnedByController", false)
    if activeManifest and activeManifest.VisualCleanup then
        pcall(activeManifest.VisualCleanup)
        activeManifest.VisualCleanup = nil
    end
    playing = false
end

local function destroyOwnedWorlds()
    for _, container in ipairs({workspace, ServerStorage}) do
        local world = container:FindFirstChild(Configuration.WorldName)
        if world and world:GetAttribute("Level6BuildOwned") == true then
            world:Destroy()
        end
    end
end

local function bindManager(manifest: any)
    disconnectManager()
    local token = managerToken
    local function sync()
        if token ~= managerToken or activeManifest ~= manifest
            or not manifest.World or manifest.World.Parent ~= workspace then return end
        if workspace:GetAttribute("Level6MallManagerHuntActive") ~= true
            or workspace:GetAttribute("Level6RoundActive") ~= true or countParticipants() == 0 then
            MallManagerController.Stop()
            return
        end
        if MallManagerController.GetSnapshot() then return end
        local ok, result = pcall(MallManagerController.Start, manifest, generation)
        if not ok then
            state():SetAttribute("Level6_ManagerError", tostring(result))
            warn("[Level 6 Preview] Manager start failed:", result)
            return
        end
        if result == nil then
            task.delay(.35, function()
                if token == managerToken then sync() end
            end)
        end
    end
    managerConnection = workspace:GetAttributeChangedSignal("Level6MallManagerHuntActive"):Connect(sync)
    sync()
end

local function lobbySpawn(): BasePart?
    local lobby = workspace:FindFirstChild("ServerLobby")
    local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
    return if spawn and spawn:IsA("BasePart") then spawn else nil
end

function Runtime.GetManifest()
    return activeManifest
end

function Runtime.GetSnapshot()
    return {
        Generation=generation, Building=building, Playing=playing, Participants=countParticipants(),
        Seed=activeManifest and activeManifest.Layout.ResolvedSeed or nil,
        LayoutHash=activeManifest and activeManifest.Layout.LayoutHash or nil,
        RoomCount=activeManifest and #activeManifest.Layout.Rooms or 0,
        AuthoredGatewayRoomCount=activeManifest and #activeManifest.Layout.BlenderRooms or 0,
        Error=buildError, Stale=stale,
    }
end

function Runtime.Leave(player: Player)
    local record = participants[player]
    if not record then
        if player:GetAttribute("Level6InRound") == true then player:SetAttribute("Level6InRound", nil) end
        return
    end
    -- Drop while the participant gate is still true; another dev can recover their CDs.
    pcall(ObjectiveController.ReleaseParticipant, player)
    pcall(HidingController.ReleaseParticipant, player)
    participants[player] = nil
    for _, connection in ipairs(record.Connections) do connection:Disconnect() end
    player:SetAttribute("Level6InRound", nil)
    player:SetAttribute("Level6Escaped", nil)
    player:SetAttribute("Level6BeingChased", nil)
    player:SetAttribute("Level6PreviewActive", nil)
    if countParticipants() == 0 then
        stopControllers()
        destroyOwnedWorlds()
        activeManifest = nil
        stale = false
        workspace:SetAttribute("Level6SelectedLevel", nil)
        applyBaselineReplicatedState(state(), nil)
    end
end

local function returnToLobby(player: Player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local spawn = lobbySpawn()
    if root and root:IsA("BasePart") and spawn then
        pcall(function() player:RequestStreamAroundAsync(spawn.Position, 8) end)
        -- A new character or round supersedes the old preview return.
        if player.Character == character and player:GetAttribute("InRound") ~= true then
            Runtime.Leave(player)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
            return
        end
    end
    Runtime.Leave(player)
end

function Runtime.Cleanup()
    stopControllers()
    local leaving = {}
    for player in pairs(participants) do table.insert(leaving, player) end
    for _, player in ipairs(leaving) do returnToLobby(player) end
    destroyOwnedWorlds()
    activeManifest = nil
    stale = false
    workspace:SetAttribute("Level6SelectedLevel", nil)
    applyBaselineReplicatedState(state(), nil)
end

function Runtime.EnsureWorld(): (Model, BasePart)
    assert(RunService:IsRunning(), "Level 6 preview construction runs during Play")
    if building then
        -- The revised 279-chunk bake can outlast the old four-minute wait;
        -- concurrent preview joins must wait for the same owned build.
        local deadline = os.clock() + 1260
        repeat task.wait(.05) until not building or os.clock() > deadline
        assert(not building, "Level 6 build is still busy")
        assert(not buildError, buildError)
    end
    if activeManifest and activeManifest.World.Parent == workspace and not stale then
        return activeManifest.World, activeManifest.PreviewExit
    end
    assert(countParticipants() == 0, "Cannot regenerate beneath a preview participant")
    building = true
    buildError = nil
    local ok, result = xpcall(function()
        Runtime.Cleanup()
        generation += 1
        infrastructure()
        local requested = workspace:GetAttribute("Level6Seed")
        local pinned = type(requested) == "number" and requested == requested
            and requested >= 1 and requested < MAX_SEED
        local seed = if pinned then math.floor(requested) else Random.new():NextInteger(1, MAX_SEED - 1)
        applyBaselineReplicatedState(state(), {
            Phase="GENERATING_LAYOUT", RequestedSeed=seed, SeedPinned=pinned,
            Generation=generation, ModuleGoal=Configuration.ModuleGoal,
            LightingMode="NORMAL", RoomSongPhase="WAITING_FOR_ROUND",
        })
        workspace:SetAttribute("Level6SelectedLevel", 6)
        workspace:SetAttribute("Level6RoundActive", false)
        local layout = LayoutGenerator.Generate(seed)
        local valid, problem = LayoutGenerator.Validate(layout)
        assert(valid, problem)
        local s = state()
        s:SetAttribute("Level6_Phase", "BAKING_BLENDER_KIT")
        local kit = RuntimeBake.Ensure()
        assert(kit and kit:GetAttribute("Ready") == true, "Level 6 Blender kit is not ready")
        s:SetAttribute("Level6_KitBakedCount", kit:GetAttribute("BakedCount") or 0)
        s:SetAttribute("Level6_KitBakeSeconds", kit:GetAttribute("BakeSeconds") or 0)
        s:SetAttribute("Level6_Phase", "BUILDING_WORLD")
        local began = os.clock()
        local manifest = WorldBuilder.Build(layout, generation)
        activeManifest = manifest
        manifest.Participants = participants
        -- Root-owned adapter replaces every visible shell/furniture piece with the imported Blender kit.
        VisualAdapter.Apply(manifest)
        local marker = Instance.new("Part")
        marker.Name = "Level6Exit"
        marker.Size = Vector3.new(2, .2, 2)
        marker.CFrame = manifest.ElevatorSpawn.CFrame * CFrame.new(0, 3.5, 0)
        marker.Transparency = 1
        marker.Anchored = true
        marker.CanCollide = false
        marker.CanQuery = false
        marker.CanTouch = false
        marker:SetAttribute("Level6PreviewReturn", true)
        marker.Parent = manifest.World
        manifest.PreviewExit = marker
        for _, key in ipairs({"Level6Preview", "PreviewOnly", "Level6PreviewReady"}) do
            manifest.World:SetAttribute(key, true)
        end
        manifest.World:SetAttribute("Level6BuildOwned", true)
        manifest.World:SetAttribute("Level6_RoomFloorArea", layout.RoomFloorArea)
        manifest.World:SetAttribute("Level6_AuthoredGatewayFloorArea", layout.BlenderRoomFloorArea)
        s:SetAttribute("Level6_BuildSeconds", os.clock() - began)
        s:SetAttribute("Level6_WorldDescendants", #manifest.World:GetDescendants())
        s:SetAttribute("Level6_ResolvedSeed", layout.ResolvedSeed)
        s:SetAttribute("Level6_LayoutHash", layout.LayoutHash)
        s:SetAttribute("Level6_GeneratedRoomCount", #layout.Rooms)
        s:SetAttribute("Level6_AuthoredGatewayRoomCount", #layout.BlenderRooms)
        s:SetAttribute("Level6_AuthoredGatewayFloorArea", layout.BlenderRoomFloorArea)
        s:SetAttribute("Level6_GeneratedCorridorCount", #layout.Links)
        s:SetAttribute("Level6_GeneratedDistrictCount", #layout.Districts)
        s:SetAttribute("Level6_ExitPosition", manifest.ExitPosition)
        s:SetAttribute("Level6_BlackoutScreamOpeningCount", #manifest.BlackoutScreamOpenings)
        s:SetAttribute("Level6_Phase", "READY")
        return manifest
    end, debug.traceback)
    building = false
    if not ok then
        buildError = tostring(result)
        stopControllers()
        destroyOwnedWorlds()
        activeManifest = nil
        workspace:SetAttribute("Level6SelectedLevel", nil)
        state():SetAttribute("Level6_Error", buildError)
        error(buildError)
    end
    return result.World, result.PreviewExit
end

function Runtime.Join(player: Player): (boolean, string?)
    if player.Parent ~= Players or not DevAccess.IsLevel6PreviewAllowed(player)
        or player:GetAttribute("InRound") == true
        or workspace:GetAttribute("ReservedRoundServer") == true then
        return false, "PREVIEW_NOT_ALLOWED"
    end
    if participants[player] then return true end
    local manifest = activeManifest
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not manifest or stale or not root or root.Anchored or humanoid.Health <= 0
        or (root.Position - manifest.PreviewExit.Position).Magnitude > 18 then
        return false, "ARRIVAL_NOT_READY"
    end
    local record = {Connections={}}
    participants[player] = record
    player:SetAttribute("Level6Escaped", false)
    player:SetAttribute("Level6InRound", true)
    player:SetAttribute("Level6PreviewActive", true)
    table.insert(record.Connections, player:GetAttributeChangedSignal("Level6Escaped"):Connect(function()
        if player:GetAttribute("Level6Escaped") == true then task.defer(returnToLobby, player) end
    end))
    table.insert(record.Connections, player:GetAttributeChangedSignal("InRound"):Connect(function()
        if player:GetAttribute("InRound") == true then Runtime.Leave(player) end
    end))
    table.insert(record.Connections, humanoid.Died:Connect(function()
        task.defer(Runtime.Leave, player)
    end))
    table.insert(record.Connections, player.CharacterRemoving:Connect(function()
        Runtime.Leave(player)
    end))
    if not playing then
        local ok, problem = xpcall(function()
            ObjectiveController.Start(manifest, generation)
            HidingController.Start(manifest, generation)
            MusicSequenceController.Start(manifest, generation)
            workspace:SetAttribute("Level6LightingOwnedByController", true)
            workspace:SetAttribute("Level6RoundActive", true)
            playing = true
            bindManager(manifest)
        end, debug.traceback)
        if not ok then
            Runtime.Leave(player)
            state():SetAttribute("Level6_Error", tostring(problem))
            return false, tostring(problem)
        end
    end
    return true
end

Players.PlayerRemoving:Connect(function(player) Runtime.Leave(player) end)
local permissionAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
    if not playing then return end
    permissionAccumulator += dt
    if permissionAccumulator < 2 then return end
    permissionAccumulator = 0
    local rejected = {}
    for player in pairs(participants) do
        if not DevAccess.IsLevel6PreviewAllowed(player) then table.insert(rejected, player) end
    end
    for _, player in ipairs(rejected) do task.spawn(returnToLobby, player) end
end)
game:BindToClose(function()
    stopControllers()
end)
return Runtime
