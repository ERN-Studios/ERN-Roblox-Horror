Read-only focused review of twelve pinned Roblox Luau candidates. Use only supplied facts/code; no tools. Maximum 650 words. Report material defects with severity, exact path/function, trigger, effect and minimal scoped fix. Distinguish source inference from observed test facts. Do not provide a wholesale replacement, deploy/publish, treat omitted code as verified, or claim gameplay/performance/multiplayer passes.

Intent: promote revised Level 6 map/layout/world/visual behavior into the public Level 3 campaign identity, keeping public SelectedLevel=3, RoundActive, InRound, Escaped, BeingChased, Level 3 State/Remotes/Generated World and public completion/reward/Back-to-Lobby settlement. Level 5/6 preview access/namespace and native Level6BlenderKit/Level6BlenderSourceRevision20261001 asset schema remain intact. Public origin remains (6200,24,0). Keep workspace compatibility Elevator/DoorL/DoorR/ElevatorSpawn/MazeStart and Level3_Level2ExitTube slide-resume attributes for Level2 continuation. Promotion calls visual application before public objective/music/hiding/controllers, and visual cleanup before world teardown.

Original TOP SUPPORTERS is one combined recorded donations/utility products/storefront pass/private-server purchase board. Fresh active-source search found no independent buyer ranking; buyer references are receipt/import bookkeeping. Reparent actual original runtime board into R4, preserve title/ten-row renderer/subscriptions/provider/IDs/persistent stores, and remove only exact mounted plaque 'LOBBY REVISION · DEV'. No DataStore or monetization Source changes. R4 can be reused; inspect full original-lobby rebuild duplication hazard rather than assuming current startup-only use proves all resets.

Fresh pinned Studio session c1e8b040-e549-408a-8a5b-7fe6905c2d55, place131311258779917/universe10559217407. Existing edited scripts have exact Source/editor parity in fresh before/scripts.json; new balloon/crayon modules must be absent before scoped creation. Root owns full native backup, fresh in-write CAS, native integration and publication. This review cannot inspect Studio. Candidate selection is the requested layout-world-candidate-manifest-v2 + gameplay_boards/candidate-manifest; separately named final Visual manifest/diff is stale and not a baseline. Supplied body hashes match all twelve selected manifests.

Verified local facts: all four gameplay candidates syntax-compiled and 18 extracted-function mocked cases passed, including strict midpoint/equality/living exclusion, second living participant blocking finale spawn candidates, fixed28, authored CD chunks, separate reactive concealed-wall fade, all eight portal frame captures/chunk synchronization, original board translation/rollback/re-entry. Layout agent reports eight syntax compiles and 1349 deterministic layout fixtures; no live gameplay/physics/board provider/performance pass is inferred. Large whole sources are deliberately omitted; code below is complete critical functions or explicitly labelled excerpts. Review namespace/authority/boarding/skin+frame/controller and expected-diff integration risks.

Pinned paths/classes/hashes:
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 World Builder baseline/editor=1ab3707df9f7dec093fe610478ad67bc563243bff72c52c300b7a3cd2378a652 candidate=507da2f517db2b31c2806db082244c5e07c299dd72e163d9223a29bd08d33ab2
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Layout Generator baseline/editor=2b9aacd4c8bed4fab1da525592a0c777f0e21b0fc84665971721dce276ad4289 candidate=0369a1f11fa20c90bee2fda67191bf58a6a543f1ce66ee554a4fd3c0dfcab594
create ModuleScript ServerScriptService.Level 3 Systems.Level 3 Crayon Wall Art baseline/editor=None candidate=19a59fc800920a881463159c0f724179671355936e4cfca2e8b2fd588e1a6911
create ModuleScript ServerScriptService.Level 3 Systems.Level 3 Balloon Dressing baseline/editor=None candidate=81118f18a222559da860961d23727b876a46298d12609d91c3fbd460425e2ce6
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Worn Party Room Dressing baseline/editor=766976d349759f0320e2e80ed355b9309b818d42d2a0dce34ecb15054715849d candidate=4424920501f4fafa63788f1fb70a3263e23d75e31741d68a37bd6f55b48f511a
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Configuration baseline/editor=8758d35fad3913ae1ac37eab4ee06267c99868cdd3425f40180a5452cd56cf28 candidate=c510b59dc310b719b127a2ff53e4ccf83a215a47ebb63a1b30e2a1d3ab8855ba
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Round Adapter baseline/editor=d1e0a7d68fd4bbbae2bc0052ec849e7c8f4314d35e728ea2f8b72c786595cceb candidate=bfb6470711f716e4ea94c25fd3d3ac45bf6e6cc85eb50418c7e1aac61e566ef1
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter baseline/editor=badbf728d6c219f24c7beff2e7b9234633dac51fc0d3d4f3b1338edd94cb2613 candidate=799f8de629fd3ebfa452d67242d3ef6548248f87a61e844ac060f26adedd24b9
edit LocalScript StarterPlayer.StarterPlayerScripts.Level 3 Lighting Controller baseline/editor=af55a6cba5254e627d6b1c7479a124b586280b024052616b93f0cca2d088c325 candidate=52033d8e5480398a1e54fe44349c277659e0ea66d97f64e6cf826100a408061b
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Objective Controller baseline/editor=ba82b48051005190fe658922b2948830bb22fd0696ef34026af75de8404009ae candidate=5474b27128d9d48deaa5503f4e340b138a06596534d87bff0a21d695ad2f39e8
edit ModuleScript ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller baseline/editor=a59a7ebf9885eff3377899358ac4498062be704bcdff97387f3dcda169d2502c candidate=af5885402a9d42760e7ba059057d186a97395fab20819a8bd6e7aab481f7598d
edit ModuleScript ServerScriptService.LobbyReimaginedPreview.Builder baseline/editor=6154d95902fbe2d89976e6428fc38a69f25e91e78f5ad02afac50ef19a39fad7 candidate=f5df8fc430d985722cd400cd69dc2af6db85b3f9e5a6043c72ee63c03b6c1799
## Visual Adapter exact imports/helper/public-participant/hide pass plus CD/portal/dressing excerpts; ordinary room skinning omitted
```luau
local ServerStorage = game:GetService("ServerStorage")
local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local Metadata = require(game:GetService("ServerScriptService"):WaitForChild("Level 6 Systems"):WaitForChild("Level 6 Kit Metadata"))
local Dressing = require(script.Parent:WaitForChild("Level 3 Worn Party Room Dressing"))
local Balloons = require(script.Parent:WaitForChild("Level 3 Balloon Dressing"))
local Crayon = require(script.Parent:WaitForChild("Level 3 Crayon Wall Art"))
local Manager = require(script.Parent:WaitForChild("Level 3 Mall Manager AI Controller"))
local Adapter = {}
local function vector(a): Vector3 return Vector3.new(a[1], a[2], a[3]) end
local function blender(a): Vector3 return Vector3.new(a[1], a[3], -a[2]) end
local function multiply(a: Vector3, b: Vector3): Vector3
    return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
local function theme(room): string
    if room.Role == "Arrival" then return "Orange" end
    if room.ThemeId == "OrangeBlackParty" then return "Orange" end
    if room.ThemeId == "RedParty" then return "Red" end
    if room.Role == "Exit" then return "Service" end
    return "Beige"
end
local function floorAsset(room): string
    if room.Role == "Arrival" then return "FloorDefault" end
    if room.Role == "Exit" then return "FloorService" end
    return "Floor" .. theme(room)
end
function Adapter.Apply(manifest)
    local world = assert(manifest.World, "Missing Level 3 world")
    assert(not world:GetAttribute("Level3_BlenderApplied"), "Blender adapter already applied")
    local kit = assert(ServerStorage:FindFirstChild("Level6BlenderKit"), "Blender kit is not installed")
    for name in pairs(Metadata) do
        local template = kit:FindFirstChild(name)
        assert(template and template:IsA("Model") and template:FindFirstChildWhichIsA("MeshPart", true),
            "Missing multi-material Blender prefab " .. name)
    end
    local helper = {WorldOrigin=Configuration.WorldOrigin}
    local counts = {Meshes=0, Triangles=0, CollisionBoxes=0, Tables=0, Chairs=0, Fixtures=0}
    local legacy = world:GetDescendants()
    local statusSurface = manifest.DiscPlayer.StatusLabel:FindFirstAncestorOfClass("SurfaceGui")
    helper.IsParticipant = function(player)
        return workspace:GetAttribute("SelectedLevel") == 3
            and workspace:GetAttribute("RoundActive") == true
            and player:GetAttribute("InRound") == true
            and player:GetAttribute("Escaped") ~= true
            and player:GetAttribute("Spectating") ~= true
    end
    helper.OnNoise = function(player, position, strength)
        if helper.IsParticipant(player) then Manager.ReportNoise(player, position, strength) end
    end
    helper.AssetSize = function(name) return vector(assert(Metadata[name], name).Size) end
    helper.Place = function(name, worldCF, parent, options)
        options = options or {}
        local data = assert(Metadata[name], "Unknown Blender prefab " .. tostring(name))
        local template = assert(kit:FindFirstChild(name), "Missing Blender prefab " .. name)
        local scale = options.Scale or options.scale or Vector3.one
        if type(scale) == "number" then scale = Vector3.one * scale end
        local carrier = Instance.new("Part")
        carrier.Name = name
        carrier.Size = Vector3.new(.05, .05, .05)
        carrier.CFrame = worldCF
        carrier.Anchored = true
        carrier.Transparency = if options.Reactive == true then 0 else 1
        carrier.CanCollide = false
        carrier.CanTouch = false
        carrier.CanQuery = false
        carrier.CastShadow = false
        carrier:SetAttribute("Level3_KitAsset", name)
        carrier:SetAttribute("Level3_KitPivot", worldCF)
        carrier:SetAttribute("Level3_KitScale", scale)
        carrier:SetAttribute("Level3_KitVisual", true)
        local templatePivot = template:GetPivot()
        local visualParts = {}
        local originalVariants = {}
        for _, source in ipairs(template:GetDescendants()) do
            if not source:IsA("MeshPart") then continue end
            local visual = source:Clone()
            local localCF = templatePivot:ToObjectSpace(source.CFrame)
            visual.CFrame = worldCF * CFrame.new(multiply(localCF.Position, scale)) * localCF.Rotation
            visual.Size = multiply(source.Size, scale)
            visual.Anchored = options.Dynamic ~= true
            visual.CanCollide = false
            visual.CanTouch = false
            visual.CanQuery = false
            visual.CastShadow = true
            visual:SetAttribute("Level3_KitVisualChunk", true)
            visual.Parent = carrier
            if options.Dynamic == true then
                local weld = Instance.new("Weld")
                weld.Part0 = carrier
                weld.Part1 = visual
                weld.C0 = carrier.CFrame:ToObjectSpace(visual.CFrame)
                weld.C1 = CFrame.identity
                weld.Parent = visual
            end
            table.insert(visualParts, visual)
            originalVariants[visual] = visual.MaterialVariant
        end
        assert(#visualParts == data.ChunkCount, "Blender chunk count drifted for " .. name)
        if options.Reactive == true then
            carrier:GetPropertyChangedSignal("Transparency"):Connect(function()
                for _, visual in ipairs(visualParts) do
                    if visual.Parent then visual.Transparency = carrier.Transparency end
                end
            end)
            carrier:GetPropertyChangedSignal("Color"):Connect(function()
                for _, visual in ipairs(visualParts) do
                    if visual.Parent then visual.Color = carrier.Color end
                end
            end)
            carrier:GetPropertyChangedSignal("Material"):Connect(function()
                for _, visual in ipairs(visualParts) do
                    if visual.Parent then
                        visual.Material = carrier.Material
                        visual.MaterialVariant = if carrier.Material == Enum.Material.Neon
                            then "" else originalVariants[visual]
                    end
                end
            end)
        end
        carrier.Parent = parent
        counts.Meshes += #visualParts
        counts.Triangles += data.Triangles
        if options.Collidable == true or options.collidable == true then
            for index, box in ipairs(data.Colliders or {}) do
                local center = box.center or box.center_xyz
                local size = box.size or box.size_xyz
                local proxy = Instance.new("Part")
                proxy.Name = "Level3 Blender Collision " .. index
                proxy.Size = multiply(Vector3.new(size[1], size[3], size[2]), scale)
                proxy.CFrame = worldCF * CFrame.new(multiply(blender(center), scale))
                proxy.Anchored = true
                proxy.Transparency = 1
                proxy.CanCollide = true
                proxy.CanTouch = false
                proxy.CanQuery = true
                proxy.CastShadow = false
                proxy:SetAttribute("Level3_BlenderCollision", true)
                proxy.Parent = carrier
                counts.CollisionBoxes += 1
            end
        end
        for anchorName, position in pairs(data.Anchors or {}) do
            local anchor = Instance.new("Attachment")
            anchor.Name = anchorName
            anchor.CFrame = CFrame.new(multiply(blender(position), scale))
            anchor.Parent = carrier
        end
        return carrier
    end
    local arrivalTube
    for _, child in ipairs(world:GetChildren()) do
        if child:GetAttribute("Level3_Level2ExitTube") == true then arrivalTube = child break end
    end
    assert(arrivalTube, "Missing public Level 2 slide continuation")
    local waitingRoom = world:FindFirstChild("Escaped Player Waiting Room")
    for _, object in ipairs(legacy) do
        if object:IsDescendantOf(arrivalTube)
            or (waitingRoom and object:IsDescendantOf(waitingRoom)) then continue end
        if object:IsA("BasePart") then
            object:SetAttribute("Level3_LegacyTransparency", object.Transparency)
            object.Transparency = 1
            object.CastShadow = false
        elseif object:IsA("Decal") or object:IsA("Texture") then
            object.Transparency = 1
        elseif object:IsA("SurfaceGui") or object:IsA("BillboardGui") then
            object.Enabled = object == statusSurface
        elseif object:IsA("Beam") or object:IsA("ParticleEmitter") or object:IsA("Trail") then
            object.Enabled = false
        end
    end
    local function centered(name, targetCF, targetSize, parent, color, reactive)
        local data = Metadata[name]
        local size = vector(data.Size)
        local scale = Vector3.new(targetSize.X/size.X, targetSize.Y/size.Y, targetSize.Z/size.Z)
        local pivot = targetCF * CFrame.new(-multiply(vector(data.Center), scale))
        local mesh = helper.Place(name, pivot, parent, {Scale=scale, Reactive=reactive})
        if color then
            mesh.Color = color
            if not reactive then
                for _, visual in ipairs(mesh:GetChildren()) do
                    if visual:IsA("MeshPart") then visual.Color = color end
                end
            end
        end
        return mesh
    end
    local function wallSkin(proxy, palette, parent)
        local alongX = proxy.Size.X >= proxy.Size.Z
        local length = if alongX then proxy.Size.X else proxy.Size.Z
        local thickness = if alongX then proxy.Size.Z else proxy.Size.X
        local cf = proxy.CFrame * (if alongX then CFrame.identity else CFrame.Angles(0, math.pi*.5, 0))
            centered("FluorescentFrame", part.CFrame, Vector3.new(7.5,.3675,2.4), part.Parent)
        elseif part.Name == "Level 3 Fluorescent Diffuser" then
            local skin = centered("FluorescentDiffuser", part.CFrame,
                Vector3.new(7.05,.155,2.05), part.Parent, nil, true)
            skin.Size = part.Size
            skin.CFrame = part.CFrame
            skin.Name = part.Name
            skin.Color = part.Color
            skin.Material = part.Material
            skin.Transparency = part:GetAttribute("Level3_LegacyTransparency") or 0
            if part:GetAttribute("Level3_SubtleFlicker") then skin:SetAttribute("Level3_SubtleFlicker", true) end
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("Light") then
                    if child:IsA("SurfaceLight") then child.Angle = math.max(child.Angle, 175) end
                    child.Parent = skin
                end
            end
            part.Name = "Legacy Hidden Fluorescent Anchor"
            counts.Fixtures += 1
        elseif part.Name == "PA Speaker Housing" then
            centered("PASpeaker", part.CFrame*CFrame.Angles(0,math.pi,0), Vector3.new(1.75,2.3,1.21), part.Parent)
        end
    end
    for _, module in ipairs(manifest.Modules) do
        local oldDisc = module.PickupParts[1]
        local flatCF = oldDisc.CFrame * CFrame.Angles(0,0,-math.pi*.5)
        local disc = helper.Place("CD", flatCF, module.Model,
            {Scale=Vector3.one*1.65, Dynamic=true, Reactive=true})
        local hub = helper.Place("CD", flatCF*CFrame.new(0,.002,0), module.Model,
            {Scale=Vector3.one*.31, Dynamic=true, Reactive=true})
        disc:SetAttribute("Level3_CDBasis", "Y")
        hub:SetAttribute("Level3_CDBasis", "Y")
        disc:SetAttribute("Level3_CDPickupVisual", true)
        hub:SetAttribute("Level3_CDPickupVisual", true)
        module.PickupParts = {disc, hub}
        local case = helper.Place("CDCase", module.Core.CFrame*CFrame.new(0,-.09,0), module.Model,
            {Scale=Vector3.new(2.45,1.25,2.18)})
        case:SetAttribute("Level3_CDPersistentDisplay", true)
    end
    local player = manifest.DiscPlayer
    local cabinet = player.Model:FindFirstChild("AV Cart Locked Cabinet")
    assert(cabinet and cabinet:IsA("BasePart"), "Missing player placement anchor")
    local playerCF = cabinet.CFrame * CFrame.new(0,-1.95,0)
    for _, object in ipairs(player.Model:GetDescendants()) do
        if object:IsA("BasePart") then object.CanCollide=false object.CanQuery=false end
    end
    helper.Place("FoldingTable", playerCF, player.Model, {Scale=Vector3.new(.55,1,.8), Collidable=true})
    helper.Place("CDPlayer", playerCF*CFrame.new(0,3.47,0), player.Model, {Scale=Vector3.one*1.55})
    player.ControlPanel.CFrame = playerCF*CFrame.new(0,4.10,1.50)
    player.ControlPanel.CanQuery = true
    player.Position = player.ControlPanel.Position
    player.Prompt.RequiresLineOfSight = false
    player.Prompt.ObjectText = "BIRTHDAY CD PLAYER  0/5"
    if statusSurface and statusSurface.Parent:IsA("BasePart") then
        local screen = statusSurface.Parent
        screen.Size = Vector3.new(3.3,.72,.04)
        screen.CFrame = playerCF*CFrame.new(0,4.40,1.55)
        statusSurface.Enabled = true
        local static = statusSurface:FindFirstChild("CRT Generated Static")
        if static and static:IsA("ImageLabel") then static.Visible=false end
        player.StatusLabel.Size = UDim2.fromScale(.92,.45)
        player.InstructionLabel.Position = UDim2.fromScale(.05,.55)
        player.InstructionLabel.Size = UDim2.fromScale(.9,.35)
    end
    for index, slot in ipairs(player.Slots) do
        local slotCF = playerCF*CFrame.new((index-3)*.9,3.5,1.0)
        local disc = helper.Place("CD", slotCF, player.Model,
            {Scale=Vector3.one*.62, Reactive=true})
        local hub = helper.Place("CD", slotCF*CFrame.new(0,.002,0), player.Model,
            {Scale=Vector3.one*.13, Reactive=true})
        disc.Transparency=1 hub.Transparency=1
        slot.Disc=disc slot.Hub=hub
        slot.Receiver.CFrame=slotCF
        local indicator = centered("FluorescentDiffuser", playerCF*CFrame.new((index-3)*.9,3.65,1.23),
            Vector3.new(.16,.10,.05), player.Model, nil, true)
        slot.Light.Parent=indicator
        slot.Indicator=indicator
    end
    local portal = manifest.ExitPortal
    local proxy = portal.Wall
    local newWall = centered("WallRed", proxy.CFrame, proxy.Size, portal.Model, nil, true)
    newWall.Name = "Blender Concealed Exit Wall"
    newWall:SetAttribute("Level3_HiddenExitWall", true)
    portal.VisualWall = newWall
    local newFrames={}
    for _, frame in ipairs(portal.FrameParts) do
        local skin = centered("FluorescentDiffuser", frame.CFrame, frame.Size,
            portal.Model, frame.Color, true)
        skin.Transparency=1 skin.Material=Enum.Material.Neon
        skin:SetAttribute("Level3_HiddenExitFrame", true)
        for _, child in ipairs(frame:GetChildren()) do if child:IsA("Light") then child.Parent=skin end end
        table.insert(newFrames,skin)
    end
    portal.FrameParts=newFrames
    local left = manifest.FinalExit:FindFirstChild("Final Exit Left Leaf")
    local right = manifest.FinalExit:FindFirstChild("Final Exit Right Leaf")
    if left and right then
        local center=(left.Position+right.Position)*.5
        centered("ServiceDoor", CFrame.new(center)*CFrame.Angles(0,-math.pi*.5,0),
            Vector3.new(11.8,12.0,.62), manifest.FinalExit)
    end
    local dressing = Dressing.Apply(manifest, helper, {
        WorldOrigin=Configuration.WorldOrigin, Seed=manifest.Layout.ResolvedSeed,
        IsParticipant=helper.IsParticipant, OnNoise=helper.OnNoise,
    })
    local balloons = Balloons.ApplyBalloons(manifest, helper)
    local crayon = Crayon.Apply(manifest)
    manifest.VisualCleanup = dressing and dressing.Cleanup
    manifest.VisualReport = {Kit=counts, Dressing=dressing and dressing.Report, Balloons=balloons.Report, Crayon=crayon}
    manifest.KitHelper = helper
    world:SetAttribute("Level3_BlenderApplied", true)
    world:SetAttribute("Level3_BlenderMeshCount", counts.Meshes)
    world:SetAttribute("Level3_BlenderVisibleTriangles", counts.Triangles)
    return manifest.VisualReport
end
return Adapter
```


## Round Adapter imports and complete manager binding/build/cleanup
```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 3 Layout Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 3 World Builder"))
local VisualAdapter = require(script.Parent:WaitForChild("Level 3 Worn Party Visual Adapter"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 3 Objective Controller"))
local MusicSequenceController = require(script.Parent:WaitForChild("Level 3 Music Sequence Controller"))
local HidingController = require(script.Parent:WaitForChild("Level 3 Hiding Controller"))
local MallManagerController = require(script.Parent:WaitForChild("Level 3 Mall Manager AI Controller"))
local Adapter = {}
local activeManifest: any = nil
local generation = 0
local levelOneScriptStates: {[BaseScript]: boolean}? = nil
local storedLevelOneEntity: Instance? = nil
local storedServerLobby: Instance? = nil
local managerBlackoutConnection: RBXScriptConnection? = nil
local managerLifecycleToken = 0
local STORED_LOBBY_NAME = "Level 3 Stored Server Lobby"
local STORED_LEVEL_ONE_ENTITY_NAME = "Level 3 Stored Level 1 Entity"
local MAX_SEED = 2147483647
local function bindManagerToHunt(manifest: any, activeGeneration: number)
	disconnectManagerLifecycle()
	local token = managerLifecycleToken
	local function sync()
		if token ~= managerLifecycleToken or activeManifest ~= manifest
			or not manifest.World or manifest.World.Parent ~= workspace then return end
		local shouldExist = workspace:GetAttribute("Level3MallManagerHuntActive") == true
			and workspace:GetAttribute("RoundActive") == true
			and workspace:GetAttribute("SelectedLevel") == 3
		if not shouldExist then
			stopMallManager()
			return
		end
		if MallManagerController.GetSnapshot() then return end
		local ok, result = pcall(MallManagerController.Start, manifest, activeGeneration)
		if not ok then
			warn("[Level 3] Mall Manager hunt spawn failed: " .. tostring(result))
			return
		end
		if result == nil then
			task.delay(.35, function()
				if token == managerLifecycleToken
					and workspace:GetAttribute("Level3MallManagerHuntActive") == true then sync() end
			end)
		end
	end
	managerBlackoutConnection = workspace:GetAttributeChangedSignal("Level3MallManagerHuntActive"):Connect(sync)
	sync()
end
function Adapter.Cleanup()
	local recoveringPersistedState = levelOneScriptStates == nil and (
		workspace:GetAttribute("SelectedLevel") == 3
		or workspace:FindFirstChild(Configuration.WorldName) ~= nil
		or ServerStorage:FindFirstChild(STORED_LEVEL_ONE_ENTITY_NAME) ~= nil
		or ServerStorage:FindFirstChild(STORED_LOBBY_NAME) ~= nil
	)
	disconnectManagerLifecycle()
	stopMallManager()
	HidingController.Stop()
	stopMusicSequence()
	stopObjectiveController()
	if activeManifest and type(activeManifest.VisualCleanup) == "function" then
		local ok, problem = pcall(activeManifest.VisualCleanup)
		if not ok then warn("Level 3 visual cleanup: " .. tostring(problem)) end
		activeManifest.VisualCleanup = nil
	end
	local levelState = state()
	levelState:SetAttribute("Level3_Phase", "CLEANING")
	if activeManifest and activeManifest.World and activeManifest.World.Parent then
		activeManifest.World:Destroy()
	end
	activeManifest = nil
	destroyGeneratedWorlds()
	destroyCompatibilityObjects()
	restoreLobby()
	restoreLevelOneRuntime(recoveringPersistedState)
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", 0)
	workspace:SetAttribute("Level3CDsCollected", 0)
	workspace:SetAttribute("Level3CDsCarried", 0)
	workspace:SetAttribute("Level3CDsDropped", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3LightingOwnedByController", false)
	workspace:SetAttribute("Level3PreBlackoutActive", false)
	workspace:SetAttribute("Level3BlackoutActive", false)
	workspace:SetAttribute("Level3MallManagerHuntActive", false)
	workspace:SetAttribute("Level3RecoveryFlickerActive", false)
	workspace:SetAttribute("Level3MallManagerActive", false)
	workspace:SetAttribute("Level3MallManagerState", "OFF")
	workspace:SetAttribute("Level3MallManagerBlackoutBoosted", false)
	workspace:SetAttribute("Level3HiddenPlayers", 0)
	clearLegacyAttributes()
	if workspace:GetAttribute("SelectedLevel") == 3 then
		workspace:SetAttribute("SelectedLevel", 1)
	end
	resetReplicatedState(levelState)
end
function Adapter.Build()
	local kit = ServerStorage:FindFirstChild("Level6BlenderKit")
	assert(kit and kit:IsA("Folder") and kit:GetAttribute("Ready") == true
		and kit:GetAttribute("BlenderSourceSHA256") == "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b",
		"Level 3 revised Blender kit is not ready for public admission")
	Adapter.Cleanup()
	generation += 1
	local levelState = state()
	ensureRemotes()
	clearLegacyAttributes()
	local pinnedSeed = pinnedSeedOverride()
	local requestedSeed = pinnedSeed
		or (DateTime.now().UnixTimestampMillis % (MAX_SEED - 1) + 1)
	applyBaselineReplicatedState(levelState, {
		Phase = "GENERATING_LAYOUT",
		RequestedSeed = requestedSeed,
		SeedPinned = pinnedSeed ~= nil,
		Generation = generation,
		ModuleGoal = Configuration.ModuleGoal,
		LightingMode = "NORMAL",
		RoomSongPhase = "WAITING_FOR_ROUND",
	})
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_3_GENERATING_LAYOUT")
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", Configuration.ModuleGoal)
	workspace:SetAttribute("Level3CDsCollected", 0)
	workspace:SetAttribute("Level3CDsCarried", 0)
	workspace:SetAttribute("Level3CDsDropped", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3LightingOwnedByController", true)
	workspace:SetAttribute("Level3PreBlackoutActive", false)
	workspace:SetAttribute("Level3BlackoutActive", false)
	workspace:SetAttribute("Level3MallManagerHuntActive", false)
	workspace:SetAttribute("Level3RecoveryFlickerActive", false)
	workspace:SetAttribute("Level3MallManagerActive", false)
	workspace:SetAttribute("Level3MallManagerState", "OFF")
	workspace:SetAttribute("Level3MallManagerBlackoutBoosted", false)
	workspace:SetAttribute("Level3HiddenPlayers", 0)
	isolateLevelOneRuntime()
	local success, result = xpcall(function()
		local layoutBegan = os.clock()
		local layout = LayoutGenerator.Generate(requestedSeed)
		levelState:SetAttribute("Level3_LayoutSeconds", math.round((os.clock() - layoutBegan) * 100) / 100)
		local layoutValid, layoutProblem = LayoutGenerator.Validate(layout)
		assert(layoutValid, "Level 3 layout validation failed: " .. tostring(layoutProblem))
		levelState:SetAttribute("Level3_ResolvedSeed", layout.ResolvedSeed)
		levelState:SetAttribute("Level3_GenerationAttempt", layout.Attempt)
		levelState:SetAttribute("Level3_UsedFallback", layout.UsedFallbackSeed == true)
		levelState:SetAttribute("Level3_LayoutHash", layout.LayoutHash)
		levelState:SetAttribute("Level3_GeneratorVersion", layout.Version or LayoutGenerator.Version)
		levelState:SetAttribute("Level3_GeneratedRoomCount", #layout.Rooms)
		levelState:SetAttribute("Level3_GeneratedCorridorCount", #layout.Links)
		levelState:SetAttribute("Level3_GeneratedDistrictCount", #layout.Districts)
		levelState:SetAttribute("Level3_Phase", "BUILDING_WORLD")
		workspace:SetAttribute("LoadStage", "LEVEL_3_BUILDING_WORLD")
		local buildBegan = os.clock()
		local manifest = WorldBuilder.Build(layout, generation)
		validateManifest(manifest)
		activeManifest = manifest
		local visualBegan = os.clock()
		VisualAdapter.Apply(manifest)
		validateManifest(manifest)
		levelState:SetAttribute("Level3_VisualSeconds", math.round((os.clock() - visualBegan) * 100) / 100)
		levelState:SetAttribute("Level3_BuildSeconds", math.round((os.clock() - buildBegan) * 100) / 100)
		local counted, descendants = pcall(function() return #manifest.World:GetDescendants() end)
		levelState:SetAttribute("Level3_WorldDescendants", counted and descendants or nil)
		movePlayersToArrival(manifest)
		storeLobby()
		workspace:SetAttribute("SelectedLevel", 3)
		levelState:SetAttribute("Level3_ExitPosition", manifest.ExitPosition)
		levelState:SetAttribute("Level3_MallManagerSpawnRoomId",
			manifest.Layout.Roles.MallManagerSpawnRoomId)
		levelState:SetAttribute("Level3_BlackoutScreamOpeningCount", #manifest.BlackoutScreamOpenings)
		levelState:SetAttribute("Level3_Phase", "READY")
		ObjectiveController.Start(manifest, generation)
		HidingController.Start(manifest, generation)
		bindManagerToHunt(manifest, generation)
		MusicSequenceController.Start(manifest, generation)
		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return manifest.World
	end, debug.traceback)
	if not success then
		Adapter.Cleanup()
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		levelState:SetAttribute("Level3_Phase", "ERROR")
		levelState:SetAttribute("Level3_Error", tostring(result))
		error(result)
	end
	return result
end
```


## Configuration identity/layout/finale exact excerpts
```luau
local Configuration = {
	Version = 47,
	WorldName = "Level 3 Generated World",
	StateFolderName = "Level 3 State",
	RemotesFolderName = "Level 3 Remotes",
	ClientEventName = "ClientEvent",
	MallManagerMotionEventName = "MallManagerMotion",
	HideRequestEventName = "Level3HideRequest",
	WorldOrigin = Vector3.new(6200, 24, 0),
	RoomHeight = 14,
	WallThickness = 1.5,
	FloorThickness = 1,
	CeilingThickness = 1,
	CorridorWidth = 14,
	CorridorHeight = 10.5,
	ModuleGoal = 5,
	Layout = {
		GeneratorVersion = 6,
		DistrictCount = 3,
		RoomsPerDistrict = 10,
		GenerationAttempts = 32,
		RetryStride = 104729,
		FallbackSeeds = {101, 7331, 65537, 1900813},
		MinimumRoomWidth = 80,
		MaximumRoomWidth = 88,
		MinimumRoomDepth = 64,
		MaximumRoomDepth = 76,
		MinimumRoomHeight = 11,
		MaximumRoomHeight = 13,
		MinimumInternalGap = 24,
		MaximumInternalGap = 34,
		MinimumGatewayGap = 38,
		MaximumGatewayGap = 48,
		MinimumCorridorLength = 18,
		ExitCorridorLength = 560,
		FinalHallHalfwayProgress = .50,
		ExitCorridorSpeakerCount = 7,
		ExitCorridorFixtureCount = 9,
		RowHalfSpacing = 90,
		ExtraLinksPerDistrict = 2,
		MinimumModuleSeparation = 105,
		MaximumStraightRunLinks = 3,
		MaximumVerticalRunLinks = 3,
		BuildYieldEveryRooms = 3,
		BuildYieldEveryCorridors = 2,
		HideTableCount = 30,
	},
	TextureStuds = {
		PartyCarpet = 28,
		PartyCarpetNeon = 22,
		PartyCarpetRed = 30,
		CityCarpet = 52,
		Wallpaper = 18,
		OrangeWall = 22,
		Tablecloth = 10,
	},
	Textures = {
		PartyCarpet = "rbxassetid://92795890253148",
		PartyCarpetNeon = "rbxassetid://110230144446272",
		PartyCarpetRed = "rbxassetid://108064770913201",
		CityCarpet = "rbxassetid://75635502248205",
		PastelWallpaper = "rbxassetid://96252806287644",
		OrangeWall = "rbxassetid://128270554927663",
		ConfettiTablecloth = "rbxassetid://103412925025303",
		FinalExitDoor = "rbxassetid://120063024460642",
		KidsDrawingsAtlas = "rbxassetid://136455642832077",
		KidsDrawingsWholesome25 = "rbxassetid://128767366284181",
		KidsDrawingsDisturbing25 = "rbxassetid://132144680342985",
		KidsNotesAtlas = "rbxassetid://81550568434150",
		CDCoversAtlas = "rbxassetid://88160214591687",
		DiskPlayerSurface = "rbxassetid://92830391726737",
		CRTScreenSurface = "rbxassetid://106602270400755",
	},
	Audio = {
		FluorescentHum = "rbxassetid://92576512092725",
		HVAC = "rbxassetid://9125446543",
		PowerDown = "",
		RoomListeningSong = "rbxassetid://140244948455675",
		RoomListeningSongReversed = "rbxassetid://75285146479953",
		CDCollected = "rbxassetid://84585027971879",
		ScareBalloonPop = "",
		ScareChairScrape = "",
		ScareChildGiggle = "",
		ScarePAWhisper = "",
		ScareRunningSteps = "",
		ExitUnlocked = "",
		Escape = "",
		["Mall Manager Walk Sound 1"] = "rbxassetid://86969848436282",
		["Mall Manager Walk Sound 2"] = "rbxassetid://125163405380423",
		["Mall Manager Walk Sound 3"] = "rbxassetid://131363472955449",
		["Mall Manager Walk Sound 4"] = "rbxassetid://128260682244977",
		MallManagerBalloonScream = "rbxassetid://105088070261380",
		MallManagerBlackout = "rbxassetid://125407251695204",
	},
	MusicSequence = {
		DurationSeconds = 180.035917,
		BlackoutStartSeconds = 150,
		PreBlackoutFlickerSeconds = 5,
		BlackoutScreamLeadSeconds = 3,
		PostSongBlackoutSeconds = 30,
		BlackoutSeconds = 60.035917,
		CycleEndSeconds = 210.035917,
	WorldName = "Level 3 Generated World",
	StateFolderName = "Level 3 State",
	RemotesFolderName = "Level 3 Remotes",
		GeneratorVersion = 6,
		FinalHallHalfwayProgress = .50,
		SpawnMinimumDistance = 90,
		FinalHallSpawnProgress = .97,
		FinaleApproachSpeed = 28,
```


## Layout namespace/dependencies and gateway/validation exact excerpts
```luau
local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local KitMetadata = require(game:GetService("ServerScriptService"):WaitForChild("Level 6 Systems"):WaitForChild("Level 6 Kit Metadata"))
local Master = require(game:GetService("ReplicatedStorage"):WaitForChild("MasterConfiguration"))
local LayoutGenerator = {}
local VERSION = 6
local DISTRICT_COUNT = 3
local ROOMS_PER_DISTRICT = 10
local GRID_ROWS = 2
local GRID_COLUMNS = 5
local MODULE_GOAL = 5
local ENTRY_AND_GATEWAY_LINKS = 4
local MAX_SEED = 2147483646
assert(Configuration.Layout.DistrictCount == DISTRICT_COUNT
	and Configuration.Layout.RoomsPerDistrict == ROOMS_PER_DISTRICT
	and ROOMS_PER_DISTRICT == GRID_ROWS * GRID_COLUMNS
	and Configuration.Layout.GeneratorVersion == VERSION,
	"Level 3 Configuration.Layout district sizing drifted from the generator's fixed grid")
local DEFAULTS = {
	GenerationAttempts = 24,
	RetryStride = 104729,
	FallbackSeeds = {101, 7331, 65537, 1900813},
	MinimumRoomWidth = 60,
	MaximumRoomWidth = 78,
	MinimumRoomDepth = 48,
	MaximumRoomDepth = 62,
	MinimumRoomHeight = 11,
	MaximumRoomHeight = 13,
	MinimumInternalGap = 24,
	MaximumInternalGap = 34,
	MinimumGatewayGap = 38,
	MaximumGatewayGap = 48,
	MinimumCorridorLength = 18,
	ExitCorridorLength = 560,
	RowHalfSpacing = 62,
	ExtraLinksPerDistrict = 2,
	MinimumModuleSeparation = 105,
	MaximumStraightRunLinks = 3,
	MaximumVerticalRunLinks = 3,
	ArrivalWidth = 64,
	ArrivalDepth = 54,
	ExitWidth = 58,
	ExitDepth = 52,
}
local function resolveTuning()
	local configuredLayout = Master.Overlay(
		if type((Configuration :: any).Layout) == "table"
	and Configuration.Layout.RoomsPerDistrict == ROOMS_PER_DISTRICT
	MinimumGatewayGap = 38,
	MaximumGatewayGap = 48,
		"L3Layout")
		MinimumGatewayGap = integerSetting("MinimumGatewayGap", DEFAULTS.MinimumGatewayGap, 24, 80),
		MaximumGatewayGap = integerSetting("MaximumGatewayGap", DEFAULTS.MaximumGatewayGap, 24, 90),
	if Tuning.MinimumGatewayGap > Tuning.MaximumGatewayGap then
		Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap = Tuning.MaximumGatewayGap, Tuning.MinimumGatewayGap
			link.SectionIndex, if link.Gateway then 1 else 0
	return string.format("L3-%d-%08x", VERSION, hash)
	local secondGatewayColumn = rng:NextInteger(1, GRID_COLUMNS - 1)
	if secondGatewayColumn == gatewayColumn then secondGatewayColumn = (secondGatewayColumn % (GRID_COLUMNS - 1)) + 1 end
	local gatewayColumns = {gatewayColumn, secondGatewayColumn}
		GatewayLinks = {},
		+ rng:NextInteger(Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap)
			IncomingGatewayLinkId = "",
			OutgoingGatewayLinkId = "",
					else string.format("L3_S%d_R%02d", sectionIndex, slotNumber)
			gatewayGaps[sectionIndex] = rng:NextInteger(Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap)
			Gateway = properties.Gateway == true,
			GatewayKind = properties.GatewayKind,
		if link.Gateway then table.insert(layout.GatewayLinks, link) end
			LinkType = "Gateway",
			Gateway = true,
			GatewayKind = spec.Kind,
			layout.Districts[1].IncomingGatewayLinkId = link.Id
			layout.Districts[1].OutgoingGatewayLinkId = link.Id
			layout.Districts[2].IncomingGatewayLinkId = link.Id
			layout.Districts[2].OutgoingGatewayLinkId = link.Id
			layout.Districts[3].IncomingGatewayLinkId = link.Id
			layout.Districts[3].OutgoingGatewayLinkId = link.Id
	layout.GatewayColumns = gatewayColumns
		GatewayLinkIds = (function()
			for _, link in ipairs(layout.GatewayLinks) do table.insert(ids, link.Id) end
		local link = layout.GatewayLinks[index]
		or type(layout.GatewayLinks) ~= "table" then
				or not link.Gateway or link.GatewayKind == "Exit"
		if link.Gateway == true then
				or link.GatewayKind ~= kind or layout.GatewayLinks[gatewayCount] ~= link then
					or a.GridColumn ~= b.GridColumn or type(layout.GatewayColumns) ~= "table"
					or layout.GatewayColumns[a.SectionIndex] ~= a.GridColumn then
		or type(layout.GatewayLinks) ~= "table"
		or #layout.GatewayLinks ~= ENTRY_AND_GATEWAY_LINKS then
	if type(layout.GatewayColumns) ~= "table" or #layout.GatewayColumns ~= 2 then
			or district.IncomingGatewayLinkId ~= layout.GatewayLinks[sectionIndex].Id
			or district.OutgoingGatewayLinkId ~= layout.GatewayLinks[sectionIndex + 1].Id
```


## World build complete manifest result and arrival/slide exact excerpts
```luau
	local hideTables = {}
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_TableCollision") == true then
			object.CanCollide = true
			object.CanTouch = false
			object.CanQuery = true
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_HideSightOccluder") == true then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = true
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_HideTableAnchor") == true then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			table.insert(hideTables, object)
		end
	end
	table.sort(hideTables, function(a, b)
		if a.Position.X ~= b.Position.X then return a.Position.X < b.Position.X end
		return a.Position.Z < b.Position.Z
	end)
	for index, anchor in ipairs(hideTables) do
		anchor:SetAttribute("Level3_HideTableIndex", index)
		local prompt = anchor:FindFirstChild("HideUnderTablePrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.ObjectText = string.format("FOLDING TABLE %02d", index)
		end
	end
	world:SetAttribute("Level3_HideTableCount", #hideTables)
	return {
		World=world,
		Layout=layout,
		Rooms=manifestRooms,
		Corridors=corridors,
		BlackoutScreamOpenings=blackoutScreamOpenings,
		Doors=doors,
		Modules=modules,
		MallManagerSpawn=mallManagerSpawn,
		MallManagerRuntime=mallManagerRuntime,
		HideTables=hideTables,
		ExitPortal=exitPortal,
		DiscPlayer=exitPortal and exitPortal.DiscPlayer or nil,
		EscapeTrigger=escapeTrigger,
		ExitSafeSpawn=safeSpawn,
		ExitPosition=exitPosition,
		FinalExit=finalExit,
		FinalHall=finalHall,
		Elevator=elevator,
		ElevatorSpawn=elevatorSpawn,
		MazeStart=mazeStart,
		Generation=generation,
	}
end
return Builder
	visual:SetAttribute("Level3_Level2ExitTube", true)
	visual:SetAttribute("Level3_SlideResumePosition", resumePosition)
	visual:SetAttribute("Level3_SlideResumeTangent", resumeTangent)
	visual:SetAttribute("Level3_SlideResumeVelocity", resumeTangent * RESUME_SPEED)
	visual:SetAttribute("Level3_SlideResumeSpeed", RESUME_SPEED)
	local doorL = part(model, "DoorL", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	local doorR = part(model, "DoorR", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	local spawn = part(parent, "ElevatorSpawn", spawnCF, Vector3.new(10, .5, 10),
	local mazeStart = part(parent, "MazeStart", spawn.CFrame, Vector3.new(2, .3, 2),
			local halfwayProgress = Configuration.Layout.FinalHallHalfwayProgress or .50
			local spawnProgress = Configuration.MallManager.FinalHallSpawnProgress or .97
	world:SetAttribute("Level3_FinalHallHalfwayProgress", finalHall.HalfwayProgress)
	world:SetAttribute("Level3_FinalHallSpawnProgress", finalHall.SpawnProgress)
		ElevatorSpawn=elevatorSpawn,
		MazeStart=mazeStart,
```


## Room Dressing imports/public prompt and cleanup exact excerpts
```luau
local Players = game:GetService("Players")
local Dress = {}
local V = Vector3.new
local CLEAR_HALF = 7.0
local WALL_INSET = 1.0
local MANAGER_RADIUS = 5.25
local SIZES = {
	ArcadeInvaders=V(3.30,7.19,3.34), ArcadeMaze=V(3.30,7.19,3.34),
	ArcadePlatform=V(3.30,7.19,3.34), ClawMachine=V(3.51,6.84,4.17),
	PrizeCounter=V(9.42,6.23,2.92), SupplyShelf=V(6.96,7.51,2.23),
	ChairStack=V(2.51,5.18,2.60), FoldedTables=V(4.12,6.80,1.96),
	HeliumTank=V(1.26,4.71,1.26), FlatClownCutout=V(2.66,4.45,.31),
	WorkshopBench=V(9.70,5.35,2.80), Pegboard=V(7.30,4.20,.43),
		prompt.MaxActivationDistance=8
		prompt.RequiresLineOfSight=true
		prompt.Enabled=type(participantCheck)=="function"
		prompt.Parent=anchor
		local source=validSoundId(soundIds[if kind=="breaker" then "BreakerInspect" elseif kind=="claw" then "ClawMotor" else asset])
		local sound
		if source then
			sound=Instance.new("Sound")
			sound.Name="Level 3 Original Service Sound"
			sound.SoundId=source
			sound.Volume=if kind=="breaker" then .15 else .21
			sound.Looped=false
			sound.RollOffMode=Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance=4
			sound.RollOffMaxDistance=30
			sound.Parent=anchor
			table.insert(sounds,sound)
		end
		local busy=false
		local machineCooldown=0
		table.insert(connections,prompt.Triggered:Connect(function(player)
			if not alive or not model.Parent or not world.Parent or busy or not prompt.Enabled
				or player.Parent~=Players or workspace:GetAttribute("SelectedLevel")~=3
				or workspace:GetAttribute("RoundActive")~=true then return end
			if generation~=nil and world:GetAttribute("Level3_Generation")~=nil
				and world:GetAttribute("Level3_Generation")~=generation then return end
			local ok,isParticipant=pcall(participantCheck,player)
			if not ok or isParticipant~=true then return end
			local character=player.Character
			local humanoid=character and character:FindFirstChildOfClass("Humanoid")
			local root=character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health<=0 or not root or not root:IsA("BasePart")
				or (root.Position-anchor.Position).Magnitude>10 then return end
			local now=os.clock()
			if now-machineCooldown<2 or now-(lastPlayerAction[player.UserId] or -math.huge)<1 then return end
			machineCooldown=now
			lastPlayerAction[player.UserId]=now
			busy=true
			model:SetAttribute("Level3_LastUsedBy",player.UserId)
			model:SetAttribute("Level3_InteractionSerial",(model:GetAttribute("Level3_InteractionSerial") or 0)+1)
			model:SetAttribute("Level3_ServiceActive",true)
			prompt.ActionText=if kind=="breaker" then "LABEL: PARTY WING / SPARE" elseif kind=="claw" then "The claw is stuck..." else "INSERT COIN — credit rejected"
			if sound then sound:Play() end
			if type(noiseCallback)=="function" then pcall(noiseCallback,player,anchor.Position,if kind=="breaker" then .15 else .4) end
			later(if kind=="breaker" then 3.5 else 5,function()
				if model.Parent and prompt.Parent then
					busy=false
					model:SetAttribute("Level3_ServiceActive",false)
					prompt.ActionText=if kind=="breaker" then "Inspect" else "Try a credit"
					if sound then sound:Stop() end
				end
			end)
		end))
		report.Interactions+=1
	end
	local function faceCF(position,front)
		return CFrame.lookAt(position,position-front)
				local cf=faceCF(point(u,v,y),front)
				local isWallObject=asset=="Pegboard" or asset=="BreakerPanel" or asset=="FlatClownCutout"
				local model=placed(asset,cf,group,not isWallObject,nil)
				if model then
					record.Props+=1
					if not isWallObject then navBox(model,cf,SIZES[asset]) end
					if interaction then interactive(model,cf,interaction,asset) end
				end
			end
			if plan.Variant=="MaintenanceWorkshop" then
				placed("WallClock",faceCF(point(17.8,6.5,7.2),V(-p.sx,0,0)),group,false,nil)
			end
		elseif plan.Variant then
			report.FallbackServiceRooms+=1
			local record={RoomId=room.Id,Variant=plan.Variant,Mode="scattered-open-alcove",Props=0,
				Reason=plan.Reason,ExclusionCount=#blocked}
			table.insert(report.ServiceRooms,record)
			local assets=if plan.Variant=="BudgetArcade" then {"ArcadeInvaders","ArcadeMaze","ArcadePlatform"}
				elseif plan.Variant=="PartySupplyStore" then {"SupplyShelf","ChairStack","HeliumTank","FoldedTables"}
				else {"WorkshopBench","MopBucket","SupplyShelf"}
			for _,asset in ipairs(assets) do
				local size=SIZES[asset]
				local found=false
				for _,signs in ipairs({{sx,sz},{-sx,-sz},{sx,-sz},{-sx,sz}}) do
					if found then break end
					for step=0,8 do
						local x=signs[1]*(room.W*.5-1.4-size.X*.5-step*1.7)
						local z=signs[2]*(room.D*.5-1.4-size.Z*.5)
						local rect={x=x,z=z,hx=size.X*.5,hz=size.Z*.5}
						if safeRect(rect,room,blocked,false) then
							local cf=faceCF(base+V(x,0,z),V(0,0,-signs[2]))
							local model=placed(asset,cf,group,true,nil)
							if model then
								navBox(model,cf,size)
								table.insert(blocked,rect)
								record.Props+=1
								if string.sub(asset,1,6)=="Arcade" then interactive(model,cf,"arcade",asset) end
							end
							found=true
							break
						end
					end
				end
				if not found then table.insert(report.Skipped,{RoomId=room.Id,Asset=asset,Reason="protected-space"}) end
			end
		end
		if roomIndex%4==0 then task.wait() end
		if not alive then break end
	end
	owner:SetAttribute("Level3_DressingPropCount",report.PropsPlaced)
	owner:SetAttribute("Level3_DressingServicePocketCount",report.FullServicePockets)
	owner:SetAttribute("Level3_DressingInteractionCount",report.Interactions)
	return {Cleanup=cleanup,Report=report,Owner=owner}
end
```


## Balloon module imports and exact ApplyBalloons authority/tag excerpts; placement loop omitted
```luau
local Dressing = {}
local CLEAR_HALF = 7
local WALL_INSET = 1.1
local MAX_CLUSTERS = 160
local CLUSTER_WIDTH = 2.21
local CLUSTER_DEPTH = 1.22
local CLUSTER_HEIGHT = 7.95
local CLUSTER_CHUNKS = 5
local CLUSTER_TRIANGLES = 684
local DENSITIES = {"Sparse", "Medium", "Dense"}
function Dressing.ApplyBalloons(manifest, helper)
	assert(manifest.World and manifest.World:GetAttribute("Level3BuildOwned") == true, "Level 3 owned world required")
	assert(type(helper.Place) == "function" and typeof(helper.WorldOrigin) == "Vector3", "Blender placement helper required")
	assert(not manifest.World:FindFirstChild("Level 3 Varied Balloon Dressing"), "Balloon additions already applied")
	local size = helper.AssetSize("BalloonCluster")
	assert(math.abs(size.X-CLUSTER_WIDTH)<.01 and math.abs(size.Y-CLUSTER_HEIGHT)<.01
		and math.abs(size.Z-CLUSTER_DEPTH)<.01, "Blender balloon dimensions changed; revalidate placement")
	local layout, world = manifest.Layout, manifest.World
	local seed = tonumber(layout.ResolvedSeed) or 1
	local assignment = Dressing.AssignDensities(layout.Rooms, seed)
	local owner = Instance.new("Folder")
	owner.Name = "Level 3 Varied Balloon Dressing"
	owner:SetAttribute("Level3_BalloonDressingOwned", true)
	owner:SetAttribute("Level3_ResolvedSeed", seed)
	owner.Parent = world
	local objects = world:GetDescendants()
	local report = {Version="seeded-blender-balloons-1",Seed=seed,Rooms=0,
		Clusters=0,Balloons=0,Bundles=0,GroundedClusters=0,CeilingClusters=0,
		MeshParts=0,Triangles=0,SkippedClusters=0,
	return {Density=density,TargetClusters=target,Placements=placements,Bundles=bundles,
	return {x=object.Position.X-base.X,z=object.Position.Z-base.Z,
	return object:GetAttribute("Level3_"..suffix) == true
		elseif object.CanCollide and object.Size.Y > 1 and relativeY < 8 and relativeY + object.Size.Y*.5 > 0 then padding = .55
		if object:GetAttribute("Level3_KitAsset") == "BalloonCluster" then
			local scale = object:GetAttribute("Level3_KitScale") or Vector3.one
	assert(manifest.World and manifest.World:GetAttribute("Level3BuildOwned") == true, "Level 3 owned world required")
	owner:SetAttribute("Level3_BalloonDressingOwned", true)
	owner:SetAttribute("Level3_ResolvedSeed", seed)
		group:SetAttribute("Level3_RoomId",room.Id)
		group:SetAttribute("Level3_BalloonDensity",density)
			cluster:SetAttribute("Level3_AddedBalloonCluster",true)
			cluster:SetAttribute("Level3_RoomId",room.Id)
			cluster:SetAttribute("Level3_BalloonDensity",density)
			cluster:SetAttribute("Level3_BalloonBundle",placement.Bundle)
			cluster:SetAttribute("Level3_CeilingBalloons",placement.Floating)
					part.CanCollide=false part.CanTouch=false part.CanQuery=false part.CastShadow=false
						part:SetAttribute("Level3_CeilingBalloonWeightSuppressed",true)
		group:SetAttribute("Level3_BalloonClusterCount",roomRecord.Clusters)
	world:SetAttribute("Level3_AddedBalloonClusterCount",report.Clusters)
	world:SetAttribute("Level3_AddedBalloonCount",report.Balloons)
	world:SetAttribute("Level3_AddedBalloonBundleCount",report.Bundles)
	world:SetAttribute("Level3_BalloonSparseRoomCount",report.DensityRooms.Sparse)
	world:SetAttribute("Level3_BalloonMediumRoomCount",report.DensityRooms.Medium)
	world:SetAttribute("Level3_BalloonDenseRoomCount",report.DensityRooms.Dense)
	world:SetAttribute("Level3_BalloonDecorationSeed",seed)
	return {Owner=owner,Report=report}
```


## Crayon module imports and exact Apply authority/native asset/tag excerpts; placement loop omitted
```luau
local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local Art = {}
local LIBRARIES = {
    {Mood="Wholesome", Image="rbxassetid://122680678983418", Pixels=1024},
    {Mood="Unsettling", Image="rbxassetid://86367389253858", Pixels=1024},
    {Mood="Disturbing", Image="rbxassetid://117801916744224", Pixels=1024},
}
local GRID = 4
local REVISION = "20261001-crayon-progression"
function Art.Apply(manifest)
    local world=assert(manifest.World)
    assert(not world:GetAttribute("Level3_CrayonRevision"),"Crayon art already applied")
    local rng=Random.new((manifest.Layout.ResolvedSeed+703777)%2147483646)
    local distances,progress=graphDepth(manifest.Layout)
    local report={Total=0,Wholesome=0,Unsettling=0,Disturbing=0,Rooms={},Revision=REVISION}
    local cellOrder,cellSerial={},{0,0,0}
    for tier=1,3 do
        local cells={} for i=1,16 do table.insert(cells,i) end
        cellOrder[tier]=shuffled(rng,cells)
    end
    local function chooseTier(depth)
        local pick=rng:NextNumber()
        if depth<1/3 then return if pick<.90-depth*.18 then 1 else 2 end
        if depth<2/3 then
            return if pick<.12 then 1 elseif pick<.80 then 2 else 3
        end
        return if pick<.05 then 1 elseif pick<.15 then 2 else 3
    end
    local function mark(parent,position,inward,size,depth,roomId,distance,tierOverride)
        local tier=tierOverride or chooseTier(depth)
        local library=LIBRARIES[tier]
        cellSerial[tier]+=1
        local cell=cellOrder[tier][(cellSerial[tier]-1)%16+1]
        local carrier=Instance.new("Part")
        carrier.Name="Crayon "..library.Mood.." "..cell
        carrier.Anchored=true
        carrier.Size=Vector3.new(size.X,size.Y,.006)
    assert(not world:GetAttribute("Level3_CrayonRevision"),"Crayon art already applied")
        carrier.CanCollide=false
        carrier.CanQuery=false
        carrier:SetAttribute("Level3_KidsWallArt",true)
        carrier:SetAttribute("Level3_NewCrayonArt",true)
        carrier:SetAttribute("Level3_DrawingMood",library.Mood)
        carrier:SetAttribute("Level3_DrawingTier",tier)
        carrier:SetAttribute("Level3_AtlasCell",cell)
        carrier:SetAttribute("Level3_ArtProgress",depth)
        carrier:SetAttribute("Level3_ArtGraphDepth",distance)
        carrier:SetAttribute("Level3_ArtRoomId",roomId)
        model:SetAttribute("Level3_ArtProgress",depth)
        model:SetAttribute("Level3_NewDrawingCount",placed)
    world:SetAttribute("Level3_CrayonRevision",REVISION)
    world:SetAttribute("Level3_NewCrayonDrawingCount",report.Total)
    world:SetAttribute("Level3_NewWholesomeDrawingCount",report.Wholesome)
    world:SetAttribute("Level3_NewUnsettlingDrawingCount",report.Unsettling)
    world:SetAttribute("Level3_NewDisturbingDrawingCount",report.Disturbing)
```


## Manager AI complete public gates/finale/noise functions
```luau
local function validRound(session: any): boolean
	return liveSession(session)
		and workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("Level3MallManagerHuntActive") == true
		and workspace:GetAttribute("EntityPaused") ~= true
end
local function livingPlayer(player: Player, session: any): (Model?, Humanoid?, BasePart?)
	if not validRound(session)
		or player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true then
		return nil, nil, nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart")
		or PlayerProtection.IsActive(player, character) then
		return nil, nil, nil
	end
	return character, humanoid, root
end
local function currentSpeed(session: any): number
	local stateName = session.State
	local activeProfile = profile(session)
	if session.FinalHallChase and stateName == "CHASE" then
		return Tuning.FinaleApproachSpeed
	end
	if stateName == "PATROL" or stateName == "PATROL_LISTEN" or stateName == "AWAKENING" then
		return activeProfile.PatrolSpeed
	end
	if stateName == "INVESTIGATE" or stateName == "ALERT" or stateName == "RECOVER" then
		return activeProfile.InvestigateSpeed
	end
	if stateName == "SEARCH" or stateName == "TRACKING" then return activeProfile.SearchSpeed end
	if stateName == "CHASE" then return activeProfile.ChaseSpeed end
	if stateName == "ATTACK_WINDUP" then return activeProfile.PatrolSpeed end
	return 0
end
local function nearestLivingPlayer(session: any): (Player?, BasePart?)
	local selected: Player? = nil
	local selectedRoot: BasePart? = nil
	local bestDistance = math.huge
	local selectedInFinalHall = false
	for _, candidate in ipairs(Players:GetPlayers()) do
		local _, _, candidateRoot = livingPlayer(candidate, session)
		if candidateRoot then
			local distance = planarDistance(session.Root.Position, candidateRoot.Position)
			local inFinalHall = session.FinalHallChase and insideFinalHall(session, candidateRoot.Position)
			if (inFinalHall and not selectedInFinalHall)
				or (inFinalHall == selectedInFinalHall and (distance < bestDistance - .001
					or (math.abs(distance - bestDistance) <= .001
						and (not selected or candidate.UserId < selected.UserId)))) then
				selected = candidate
				selectedRoot = candidateRoot
				bestDistance = distance
				selectedInFinalHall = inFinalHall
			end
		end
	end
	return selected, selectedRoot
end
local function eligibleSpawnPlayers(): {any}
	local records = {}
	if workspace:GetAttribute("SelectedLevel") ~= 3 or workspace:GetAttribute("RoundActive") ~= true then
		return records
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and character.Parent and humanoid and humanoid.Health > 0
				and root and root:IsA("BasePart")
				and not PlayerProtection.IsActive(player, character) then
				table.insert(records, {Player=player, Character=character, Root=root, Position=root.Position})
			end
		end
	end
	return records
end
local function chooseFinalHallSpawn(manifest: any, generation: number): any?
	local records = eligibleSpawnPlayers()
	if #records == 0 then return nil end
	local hall = manifest.FinalHall
	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return nil end
	local state = stateFolder()
	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)
	local random = Random.new(generation * 7919 + cycle * 104729 + 20260824)
	local position: Vector3? = nil
	local overlap = spawnOverlapParams(records)
	local preferred = math.clamp(tonumber(hall.SpawnProgress) or Tuning.FinalHallSpawnProgress, .90, .98)
	for _, progress in ipairs({preferred, .95, .93, .90}) do
		local candidate = hall.StartPoint:Lerp(hall.EndPoint, progress)
		candidate = Vector3.new(candidate.X, hall.FloorY, candidate.Z)
		local nearestDistance = math.huge
		for _, record in ipairs(records) do
			nearestDistance = math.min(nearestDistance, planarDistance(candidate, record.Position))
		end
		if nearestDistance >= Tuning.SpawnMinimumDistance and spawnVolumeFits(candidate, overlap) then
			position = candidate
			break
		end
	end
	if not position then return nil end
	table.sort(records, function(a, b)
		local aInHall = insideFinalHall({Manifest=manifest}, a.Position)
		local bInHall = insideFinalHall({Manifest=manifest}, b.Position)
		if aInHall ~= bInHall then return aInHall end
		local aDistance = planarDistance(position, a.Position)
		local bDistance = planarDistance(position, b.Position)
		if math.abs(aDistance - bDistance) > .001 then return aDistance < bDistance end
		return a.Player.UserId < b.Player.UserId
	end)
	local anchor = records[1]
	local centroid = Vector3.zero
	local nearestDistance = math.huge
	for _, record in ipairs(records) do
		centroid += record.Position
		nearestDistance = math.min(nearestDistance, planarDistance(position, record.Position))
	end
	centroid /= #records
	return {
		Position = position,
		Anchor = anchor,
		GroupSize = #records,
		Centroid = centroid,
		Cycle = cycle,
		RoomId = nearestRoomId(position),
		Random = random,
		SpawnClearanceValidated = true,
		Visibility = spawnVisibilityCount(position, records),
		NearestDistance = nearestDistance,
		AnchorDistance = planarDistance(position, anchor.Position),
		FinalHallChase = true,
	}
end
function Controller.ReportNoise(player: Player, position: Vector3, strength: number?)
	local session = activeSession
	if not session or typeof(position) ~= "Vector3" then return end
	local character, humanoid, root = livingPlayer(player, session)
	if not character or not humanoid or not root or (root.Position-position).Magnitude > 24 then return end
	session.WorldNoise = {Position=position, Time=os.clock(), Strength=math.clamp(tonumber(strength) or 1, .1, 1.5)}
end
			DeathAdvice.Mark(player, "L3Manager")
```


## Objective complete public gates/midpoint/CD movement/escape and unlock
```luau
local function validSession(session: AnyTable): boolean
	return liveSession(session)
		and workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
end
local function validPlayer(player: Player, session: AnyTable): boolean
	return validSession(session)
		and player.Parent == Players
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end
local function updateFinalHallChase(session: AnyTable)
	if not session.ExitUnlocked or session.FinalHallChaseTriggered
		or session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then
		return
	end
	local hall = session.Manifest.FinalHall
	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return end
	local horizontalForward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
	if horizontalForward.Magnitude <= .001 then return end
	horizontalForward = horizontalForward.Unit
	local eligibleCount = 0
	local crossedCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if validPlayer(player, session) then
			local character, _, root = livingCharacter(player)
			if character and root then
				eligibleCount += 1
				if session.FinalHallCrossed[player] ~= character then
					local offset = Vector3.new(
						root.Position.X - hall.StartPoint.X, 0, root.Position.Z - hall.StartPoint.Z)
					local along = offset:Dot(horizontalForward)
					local lateral = (offset - horizontalForward * along).Magnitude
					local entryProgress = hall.Length * (hall.HalfwayProgress
						or Configuration.Layout.FinalHallHalfwayProgress or .50)
					local insideHallWidth = lateral <= hall.Width * .5 + 2.5
					local insideHallHeight = math.abs(root.Position.Y - hall.FloorY) <= hall.Height + 6
					if along > entryProgress and along <= hall.Length + 2.5
						and insideHallWidth and insideHallHeight then
						session.FinalHallCrossed[player] = character
					end
				end
				if session.FinalHallCrossed[player] == character then crossedCount += 1 end
			end
		end
	end
	session.FinalHallEligibleCount = eligibleCount
	session.FinalHallCrossedCount = crossedCount
	session.State:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
	session.State:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
	session.Manifest.World:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
	session.Manifest.World:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
	workspace:SetAttribute("Level3FinalHallEligibleCount", eligibleCount)
	workspace:SetAttribute("Level3FinalHallCrossedCount", crossedCount)
	if eligibleCount == 0 or crossedCount == 0 then return end
	session.FinalHallChaseTriggered = true
	session.State:SetAttribute("Level3_FinalHallChaseTriggered", true)
	session.State:SetAttribute("Level3_FinalHallChaseActive", true)
	session.State:SetAttribute("Level3_MallManagerHuntActive", true)
	session.Manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", true)
	session.Manifest.World:SetAttribute("Level3_FinalHallChaseActive", true)
	workspace:SetAttribute("Level3FinalHallChaseTriggered", true)
	workspace:SetAttribute("Level3FinalHallChaseActive", true)
	workspace:SetAttribute("Level3MallManagerHuntActive", true)
end
local function configureRuntimeDiscPart(part: BasePart, anchored: boolean, queryable: boolean)
	part.Anchored = anchored
	part.Massless = not anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = queryable
	part.CastShadow = true
	part.Transparency = 0
	for _, object in ipairs(part:GetDescendants()) do
		if object:IsA("ProximityPrompt") or object:IsA("Light") then
			object:Destroy()
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_KitVisualChunk") == true then
			object.Transparency = 0
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
		end
	end
end
local function setDiscVisualCFrame(carrier: BasePart, targetCF: CFrame)
	local offsets = {}
	for _, object in ipairs(carrier:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_KitVisualChunk") == true then
			offsets[object] = carrier.CFrame:ToObjectSpace(object.CFrame)
		end
	end
	carrier.CFrame = targetCF
	for object, localCF in pairs(offsets) do object.CFrame = targetCF * localCF end
end
local function fireEscapeStatus(player: Player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local roundStatus = remotes and remotes:FindFirstChild("RoundStatus")
	if not roundStatus or not roundStatus:IsA("RemoteEvent") then return end
	for _, recipient in ipairs(Players:GetPlayers()) do
		if recipient:GetAttribute("InRound") == true then
			roundStatus:FireClient(recipient, "escape", player.Name)
		end
	end
end
unlockExit = function(session: AnyTable, startRoomId: string)
	if session.ExitUnlocked or not validSession(session) then return end
	session.ExitUnlocked = true
	local completionStartedAt = workspace:GetServerTimeNow()
	session.State:SetAttribute("Level3_CompletionSongStartServerTime", completionStartedAt)
	session.State:SetAttribute("Level3_CompletionDimStartedAtServerTime", completionStartedAt)
	session.State:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", completionStartedAt)
	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	session.ExitGuideStartRoom = ""
	session.ExitGuideCount = 0
	session.Manifest.World:SetAttribute("Level3_ExitGuideActive", false)
	session.Manifest.World:SetAttribute("Level3_ExitGuideStartRoom", "")
	session.Manifest.World:SetAttribute("Level3_ExitGuideLampCount", 0)
	updateSharedState(session)
	local portal = session.Manifest.ExitPortal
	portal.Model:SetAttribute("Level3_ExitUnlocked", true)
	if portal.Wall and portal.Wall.Parent then
		portal.Wall.CanCollide = false
		portal.Wall.CanTouch = false
		portal.Wall.CanQuery = true
	end
	local visualWall = portal.VisualWall
	if visualWall and visualWall.Parent then
		playTween(session, visualWall, TweenInfo.new(0.60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		})
	end
	for _, framePart in ipairs(portal.FrameParts) do
		if framePart and framePart.Parent then
			playTween(session, framePart, TweenInfo.new(0.60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.08,
			})
		end
	end
	if portal.Light and portal.Light.Parent then
		portal.Light.Enabled = false
	end
	local finalExit = session.Manifest.FinalExit
	if finalExit and finalExit.Parent then
		finalExit:SetAttribute("Level3_ExitPowered", true)
		for _, object in ipairs(finalExit:GetDescendants()) do
			if object:IsA("BasePart") and (object.Name == "Final Exit Energon Rail" or object.Name == "Final Exit Lock Core") then
				playTween(session, object, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.06,
				})
			elseif object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
				object.Enabled = false
			end
		end
	end
	firePayload(session, {
		Type = "ExitUnlocked",
		Progress = session.ModuleCount,
		Goal = session.ModuleGoal,
		ExitPosition = session.Manifest.ExitPosition,
	})
	fireSound(session, "ExitUnlocked", session.Manifest.ExitPosition, nil)
end
local function escapePlayer(session: AnyTable, player: Player)
	if not session.ExitUnlocked or session.Escaping[player] then return end
	if not validPlayer(player, session) then return end
	local trigger = session.Manifest.EscapeTrigger
	if not trigger or not trigger.Parent or not trigger.CanTouch
		or not trigger:IsDescendantOf(session.Manifest.World) then return end
	local character, _, root = livingCharacter(player)
	if not character or not root then return end
	local offset = trigger.CFrame:PointToObjectSpace(root.Position)
	local halfSize = trigger.Size * .5
	if not (math.abs(offset.X) <= halfSize.X and math.abs(offset.Y) <= halfSize.Y
		and math.abs(offset.Z) <= halfSize.Z) then return end
	session.Escaping[player] = true
	session.EscapeOrdinal = (session.EscapeOrdinal or 0) + 1
	player:SetAttribute("Escaped", true)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local slots = {
		Vector3.new(-6, 3, -4), Vector3.new(0, 3, -4), Vector3.new(6, 3, -4),
		Vector3.new(-6, 3, 4), Vector3.new(0, 3, 4), Vector3.new(6, 3, 4),
	}
	local slot = slots[((session.EscapeOrdinal - 1) % #slots) + 1]
	character:PivotTo(session.Manifest.ExitSafeSpawn.CFrame * CFrame.new(slot))
	fireSound(session, "Escape", session.Manifest.ExitPosition, player)
	fireEscapeStatus(player)
end
local TeamObjectives = require(game:GetService("ServerScriptService"):WaitForChild("TeamObjectives"))
local function setDiscVisualCFrame(carrier: BasePart, targetCF: CFrame)
			setDiscVisualCFrame(disc, carryCF * (if disc:GetAttribute("Level3_CDBasis") == "Y" then CFrame.Angles(0,0,-math.pi*.5) else CFrame.identity))
			setDiscVisualCFrame(hub, carryCF * (if hub:GetAttribute("Level3_CDBasis") == "Y" then CFrame.Angles(0,0,-math.pi*.5) else CFrame.identity))
	TeamObjectives.Announce(player.Name, string.format("%s CD %02d",
	setDiscVisualCFrame(disc, dropCF * (if disc:GetAttribute("Level3_CDBasis") == "Y" then CFrame.Angles(0,0,-math.pi*.5) else CFrame.identity))
	setDiscVisualCFrame(hub, dropCF * (if hub:GetAttribute("Level3_CDBasis") == "Y" then CFrame.Angles(0,0,-math.pi*.5) else CFrame.identity))
	TeamObjectives.Announce(player.Name, string.format("INSERTED %d CD%s  //  %d/%d",
```


## Lighting complete material-chunk/frame capture and ownership functions; bindWorld first excerpt
```luau
local function tryWatchCeilingBounce(instance: Instance)
	if not instance:IsA("PointLight")
		or instance:GetAttribute("Level3_CeilingBounce") ~= true
		or ceilingBounceSeen[instance] then return end
	local anchor = instance.Parent
	local primary = anchor and anchor.Parent
	if not (primary and primary:IsA("SurfaceLight")
		and primary.Name == "Level 3 Fluorescent Light") then return end
	local normalBrightness = instance:GetAttribute("Level3_PrimaryBrightness")
	if type(normalBrightness) ~= "number" or normalBrightness <= 0 then return end
	ceilingBounceSeen[instance] = true
	local function sync()
		if not instance.Parent or not primary.Parent then return end
		instance.Enabled = primary.Enabled
		instance.Brightness = .16 * math.clamp(primary.Brightness / normalBrightness, 0, 1)
		instance.Color = primary.Color
	end
	for _, property in ipairs({"Enabled", "Brightness", "Color"}) do
		table.insert(kitFixtureConnections, primary:GetPropertyChangedSignal(property):Connect(sync))
	end
	sync()
end
local function syncKitFixtureVisuals(carrier: BasePart)
	for _, child in ipairs(carrier:GetChildren()) do
		if child:IsA("MeshPart") and child:GetAttribute("Level3_KitVisualChunk") == true then
			if kitVisualVariants[child] == nil then
				kitVisualVariants[child] = child.MaterialVariant
			end
			child.Material = carrier.Material
			child.Color = carrier.Color
			child.Transparency = carrier.Transparency
			child.MaterialVariant = if carrier.Material == Enum.Material.Neon
				or carrier.Material == Enum.Material.SmoothPlastic
				then "" else kitVisualVariants[child]
		end
	end
end
local function tryWatchKitFixture(instance: Instance)
	if not instance:IsA("BasePart") or kitFixtureSeen[instance]
		or instance:GetAttribute("Level3_KitAsset") ~= "FluorescentDiffuser" then return end
	if not instance:FindFirstChildWhichIsA("Light")
		and instance:GetAttribute("Level3_HiddenExitFrame") ~= true then return end
	kitFixtureSeen[instance] = true
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Material"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Color"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Transparency"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	syncKitFixtureVisuals(instance)
end
local function clearKitFixtureWatchers()
	for _, connection in ipairs(kitFixtureConnections) do connection:Disconnect() end
	table.clear(kitFixtureConnections)
	table.clear(kitFixtureSeen)
	table.clear(kitVisualVariants)
	table.clear(ceilingBounceSeen)
end
local function captureAuthoredRoomGlow(instance: Instance)
	if instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitFrame") == true then
		if not blackoutPartSeen[instance] then
			blackoutPartSeen[instance] = true
			table.insert(blackoutParts, {Part=instance, Material=instance.Material, Color=instance.Color})
		end
		return
	end
	if not instance:IsA("MeshPart")
		or instance:GetAttribute("Level3_KitVisualChunk") ~= true
		or instance.Name:sub(-6) ~= "__glow" then return end
	local carrier = instance.Parent
	if not (carrier and carrier:IsA("BasePart")
		and carrier:GetAttribute("Level3_BlenderGatewayRoom") == true)
		or blackoutPartSeen[instance] then return end
	blackoutPartSeen[instance] = true
	table.insert(blackoutParts, {
		Part = instance,
		Material = instance.Material,
		Color = instance.Color,
	})
end
local function captureWorldLightBaseline()
	table.clear(blackoutLights)
	table.clear(blackoutParts)
	table.clear(blackoutPartSeen)
	blackoutSweptUnlocked = nil
	local world = boundWorld
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		captureAuthoredRoomGlow(descendant)
		if descendant:IsA("Light") and descendant:GetAttribute("Level3_CeilingBounce") ~= true then
			table.insert(blackoutLights, {
				Light = descendant,
				Enabled = descendant.Enabled,
				Brightness = descendant.Brightness,
			})
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") and not blackoutPartSeen[parent] then
				blackoutPartSeen[parent] = true
				table.insert(blackoutParts, {
					Part = parent,
					Material = parent.Material,
					Color = parent.Color,
				})
			end
		end
	end
end
local function shouldOwnLighting(): boolean
	return workspace:GetAttribute("SelectedLevel") == LEVEL
		and workspace:GetAttribute("Level3LightingOwnedByController") == true
		and player:GetAttribute("InRound") == true
end
local function bindWorld(world: Model?)
	if world == boundWorld then return end
	if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then restoreBlackoutWorld() end
	if worldAddedConnection then worldAddedConnection:Disconnect() end
	if worldRemovingConnection then worldRemovingConnection:Disconnect() end
	worldAddedConnection = nil
	worldRemovingConnection = nil
	clearFixtureRecords()
	clearKitFixtureWatchers()
	boundWorld = world
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		tryAddFixture(descendant)
		tryWatchKitFixture(descendant)
		tryWatchCeilingBounce(descendant)
	end
	worldAddedConnection = world.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if world ~= boundWorld or not descendant:IsDescendantOf(world) then return end
			tryAddFixture(descendant)
			tryWatchKitFixture(descendant)
			tryWatchCeilingBounce(descendant)
			if descendant:IsA("Light") then
				local lightParent = descendant.Parent
				if lightParent then tryWatchKitFixture(lightParent) end
			elseif descendant:IsA("MeshPart")
				and descendant:GetAttribute("Level3_KitVisualChunk") == true then
				local carrier = descendant.Parent
				if carrier and carrier:IsA("BasePart") then
					tryWatchKitFixture(carrier)
					if kitFixtureSeen[carrier] then syncKitFixtureVisuals(carrier) end
				end
			end
			if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then
				local oldCount = #blackoutParts
				captureAuthoredRoomGlow(descendant)
				if #blackoutParts > oldCount and blackoutApplied then
					if completionFadeActive then
local LEVEL = 3
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(refreshOwnership)
player:GetAttributeChangedSignal("InRound"):Connect(refreshOwnership)
```


## R4 Builder exact actual source diff (all edits)
```luau
+++ candidate R4 Builder
@@ -25,17 +25,63 @@
 	label.Font = Enum.Font.GothamBold; label.TextScaled = true; label.Parent = gui
 	return label
 end
+-- Move the original live renderer; its existing Value/attribute connections
+-- are closure-held and would not survive cloning just the display model.
+local function supportBoardTransfer(destination, center)
+    local installed = destination:FindFirstChild("ZyntraDonationLeaderboardBoard", true)
+    if installed then
+        assert(installed:IsA("Model"), "Inspect conflicting R4 support board")
+        return nil
+    end
+    local lobby = assert(workspace:FindFirstChild("ServerLobby"), "Original server lobby must precede R4")
+    local board
+    for _, descendant in ipairs(lobby:GetDescendants()) do
+        if descendant.Name == "ZyntraDonationLeaderboardBoard" then
+            assert(descendant:IsA("Model") and board == nil, "Inspect conflicting original support boards")
+            board = descendant
+        end
+    end
+    assert(board, "Original support board is not ready")
+    local panel = board:FindFirstChild("LeaderboardPanel")
+    assert(panel and panel:IsA("BasePart") and panel:FindFirstChild("DonationLeaderboardDisplay"),
+        "Inspect original support-board renderer before relocation")
+    return {
+        Board = board,
+        Parent = board.Parent,
+        Pivot = board:GetPivot(),
+        TargetPivot = CFrame.new(center + Vector3.new(-30, 7.15, -35) - panel.Position) * board:GetPivot(),
+    }
+end
+local function applySupportBoardTransfer(transfer, destination)
+    if not transfer then return end
+    transfer.Board:PivotTo(transfer.TargetPivot)
+    -- Never assign a nil direct Parent: the original renderer tears down on nil.
+    transfer.Board.Parent = destination
+end
+local function restoreSupportBoardTransfer(transfer)
+    if not transfer then return end
+    transfer.Board.Parent = transfer.Parent
+    transfer.Board:PivotTo(transfer.Pivot)
+end
 function Module.Build()
 	assert(not RunService:IsClient(), "Server preview only")
 	local existing = workspace:FindFirstChild(NAME)
 	if existing then
 		assert(existing:GetAttribute(OWNED) == true and existing:GetAttribute("Ready") == true, "Inspect conflicting preview first")
-		require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
+		local center = existing:GetAttribute("PreviewCenter")
+		assert(typeof(center) == "Vector3", "Inspect R4 lobby center before relocating support board")
+		local transfer = supportBoardTransfer(existing, center)
+		local ok, failure = pcall(function()
+			applySupportBoardTransfer(transfer, existing)
+			require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
+		end)
+		if not ok then restoreSupportBoardTransfer(transfer); error(failure) end
 		return existing
 	end
 	local manifest, kit = Bake.GetManifest(), Bake.Ensure()
 	local center = vec(manifest.previewCenter)
 	local model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)
+	local transfer
 	local ok, built = pcall(function()
 	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
 	model:SetAttribute(OWNED,true); model:SetAttribute("Ready",false)
@@ -168,23 +214,20 @@
 			wall:SetAttribute("HologramFullSize",wall.Size); wall:SetAttribute("HologramFullCFrame",wall.CFrame)
 		end
 	end
-	local notice=manifest.notice
-	if notice then
-		local host=part(signs,"Mounted Revision Notice",vec(notice.size),CFrame.new(center+vec(notice.position))*CFrame.Angles(0,notice.yaw,0),false)
-		text(host,Enum.NormalId.Back,"LOBBY REVISION · DEV",Color3.fromRGB(192,244,223),Vector2.new(440,100))
-	end
 	assert(not workspace:FindFirstChild(NAME), "Concurrent preview appeared; refusing overwrite")
 	local endPiles = require(script.Parent:WaitForChild("EndBlockades")).Add(model, kit, manifest)
 	local bayPolish = require(script.Parent:WaitForChild("LobbyPolishBays")).Add(model, kit, manifest)
 	require(script.Parent:WaitForChild("MaterialPolish")).Apply(model)
 	require(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)
+	transfer = supportBoardTransfer(model, center)
+	applySupportBoardTransfer(transfer, model)
 	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles") + bayPolish:GetAttribute("AddedInstancedTriangles"))
 	model.Parent = workspace
 	require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)
 	return model
 	end)
-	if not ok then model:Destroy(); error(built) end
+	if not ok then restoreSupportBoardTransfer(transfer); model:Destroy(); error(built) end
 	return built
 end
 return Module
```


## Original combined board renderer subscriptions (unchanged exact excerpt)
```luau
	local function renderRow(entry, value, text)
		local rank = value:GetAttribute("Rank")
		local name = value:GetAttribute("Name")
		local robux = value:GetAttribute("Robux")
		if type(rank) ~= "number" then
			local legacyRank, legacyName, legacyRobux = string.match(text, "^(%d+)%s+(.-)%s+•%s+(%d+) R%$$")
			rank, name, robux = tonumber(legacyRank), legacyName, tonumber(legacyRobux)
		end
		if type(rank) == "number" and rank == rank and rank >= 1 and rank <= 99 then
			entry.Rank.Text = string.format("%02d", math.floor(rank))
			entry.Name.Text = type(name) == "string" and name or ""
			entry.Robux.Text = robuxText(robux)
		else
			entry.Rank.Text = ""
			entry.Name.Text = text
			entry.Robux.Text = ""
		end
	end
	local ROW_ATTRIBUTES = {"Rank", "Name", "Robux"}
	task.spawn(function()
		local values = ReplicatedStorage:WaitForChild("ZyntraDonationLeaderboard", 15)
		if not values or not model.Parent then return end
		local connections = {}
		local function bind(value, render, attributes)
			if not value or not value:IsA("StringValue") then return end
			render(value.Value)
			local function update()
				if model.Parent then render(value.Value) end
			end
			connections[#connections + 1] = value:GetPropertyChangedSignal("Value"):Connect(update)
			for _, attribute in ipairs(attributes or {}) do
				connections[#connections + 1] = value:GetAttributeChangedSignal(attribute):Connect(update)
			end
		end
		bind(values:FindFirstChild("Status"), function(value) status.Text = value end)
		for rank, entry in ipairs(rows) do
			local value = values:FindFirstChild(string.format("Row%02d", rank))
			bind(value, function(text) renderRow(entry, value, text) end, ROW_ATTRIBUTES)
		end
		connections[#connections + 1] = model.AncestryChanged:Connect(function(_, newParent)
			if newParent then return end
			for _, connection in ipairs(connections) do connection:Disconnect() end
			table.clear(connections)
		end)
	end)
	return model
end
function Builder.Build(center)
	local old = workspace:FindFirstChild("ServerLobby")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "ServerLobby"
	model.Parent = workspace
	model:SetAttribute("LobbyStyle", "ZyntraTunnel")
	model:SetAttribute("TextureVersion", 10)
	model:SetAttribute("LobbyAestheticRevision", 5)
	model:SetAttribute("DispatchConcourseVersion", 8)
	model:SetAttribute("SupplyKioskVersion", 6)
	model:SetAttribute("DonationLeaderboardVersion", 2)
	model:SetAttribute("PartyButtonVersion", 3)
	model:SetAttribute("TunnelCurveRevision", 2)
	model:SetAttribute("TunnelGlossVersion", 2)
	model:SetAttr
```

