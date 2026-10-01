--!strict
-- Replaces the cloned builder's visible primitives with the Blender-authored kit.
-- Legacy invisible collision, navigation and prompt anchors remain authoritative.
local ServerStorage = game:GetService("ServerStorage")
local Configuration = require(script.Parent:WaitForChild("Level 6 Configuration"))
local Metadata = require(script.Parent:WaitForChild("Level 6 Kit Metadata"))
local Dressing = require(script.Parent:WaitForChild("Level 6 Room Dressing"))
local Manager = require(script.Parent:WaitForChild("Level 6 Mall Manager AI Controller"))
local Adapter = {}

local function vector(a): Vector3 return Vector3.new(a[1], a[2], a[3]) end
local function blender(a): Vector3 return Vector3.new(a[1], a[3], -a[2]) end
local function multiply(a: Vector3, b: Vector3): Vector3
    return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
local function theme(room): string
    if room.ThemeId == "OrangeBlackParty" then return "Orange" end
    if room.ThemeId == "RedParty" then return "Red" end
    if room.Role == "Exit" then return "Service" end
    return "Beige"
end

function Adapter.Apply(manifest)
    local world = assert(manifest.World, "Missing Level 6 world")
    assert(not world:GetAttribute("Level6_BlenderApplied"), "Blender adapter already applied")
    local kit = assert(ServerStorage:FindFirstChild("Level6BlenderKit"), "Blender kit is not installed")
    for name in pairs(Metadata) do
        local template = kit:FindFirstChild(name)
        assert(template and template:IsA("MeshPart"), "Missing Blender prefab " .. name)
        -- MeshPart class/kit membership is checked here; installer validates uploaded or opaque MeshContent.
    end
    local helper = {WorldOrigin=Configuration.WorldOrigin}
    local counts = {Meshes=0, Triangles=0, CollisionBoxes=0, Tables=0, Chairs=0, Fixtures=0}
    local legacy = world:GetDescendants()
    local statusSurface = manifest.DiscPlayer.StatusLabel:FindFirstAncestorOfClass("SurfaceGui")

    helper.IsParticipant = function(player)
        return manifest.Participants and manifest.Participants[player] ~= nil
            and player:GetAttribute("Level6InRound") == true
            and player:GetAttribute("Level6Escaped") ~= true
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
        local mesh = template:Clone()
        mesh.Name = name
        mesh.Anchored = true
        mesh.CanCollide = false
        mesh.CanTouch = false
        mesh.CanQuery = false
        mesh.CastShadow = true
        mesh.Size = multiply(vector(data.Size), scale)
        mesh.CFrame = worldCF * CFrame.new(multiply(vector(data.Center), scale))
        mesh:SetAttribute("Level6_KitAsset", name)
        mesh:SetAttribute("Level6_KitPivot", worldCF)
        mesh:SetAttribute("Level6_KitScale", scale)
        mesh:SetAttribute("Level6_KitVisual", true)
        mesh.Parent = parent
        counts.Meshes += 1
        counts.Triangles += data.Triangles
        if options.Collidable == true or options.collidable == true then
            for index, box in ipairs(data.Colliders or {}) do
                local center = box.center or box.center_xyz
                local size = box.size or box.size_xyz
                local proxy = Instance.new("Part")
                proxy.Name = "Level6 Blender Collision " .. index
                proxy.Size = multiply(Vector3.new(size[1], size[3], size[2]), scale)
                proxy.CFrame = worldCF * CFrame.new(multiply(blender(center), scale))
                proxy.Anchored = true
                proxy.Transparency = 1
                proxy.CanCollide = true
                proxy.CanTouch = false
                proxy.CanQuery = true
                proxy.CastShadow = false
                proxy:SetAttribute("Level6_BlenderCollision", true)
                proxy.Parent = mesh
                counts.CollisionBoxes += 1
            end
        end
        for anchorName, position in pairs(data.Anchors or {}) do
            local anchor = Instance.new("Attachment")
            anchor.Name = anchorName
            anchor.CFrame = mesh.CFrame:ToObjectSpace(worldCF * CFrame.new(multiply(blender(position), scale)))
            anchor.Parent = mesh
        end
        return mesh
    end

    -- Hide all old rendering, including surface content which Transparency alone does not hide.
    for _, object in ipairs(legacy) do
        if object:IsA("BasePart") then
            object:SetAttribute("Level6_LegacyTransparency", object.Transparency)
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

    local function centered(name, targetCF, targetSize, parent, color)
        local data = Metadata[name]
        local size = vector(data.Size)
        local scale = Vector3.new(targetSize.X/size.X, targetSize.Y/size.Y, targetSize.Z/size.Z)
        local pivot = targetCF * CFrame.new(-multiply(vector(data.Center), scale))
        local mesh = helper.Place(name, pivot, parent, {Scale=scale})
        if color then mesh.Color = color end
        return mesh
    end

    local function wallSkin(proxy, palette, parent)
        local alongX = proxy.Size.X >= proxy.Size.Z
        local length = if alongX then proxy.Size.X else proxy.Size.Z
        local thickness = if alongX then proxy.Size.Z else proxy.Size.X
        local cf = proxy.CFrame * (if alongX then CFrame.identity else CFrame.Angles(0, math.pi*.5, 0))
        local lintel = proxy.Name:find("Lintel", 1, true) ~= nil or proxy.Size.Y < 3
        local segmentSize = if lintel then 14 else 8
        local count = math.max(1, math.ceil(length / segmentSize))
        for index=1,count do
            local width = length/count
            centered((if lintel then "Lintel" else "Wall") .. palette,
                cf*CFrame.new(-length*.5 + width*(index-.5), 0, 0),
                Vector3.new(width+.012, proxy.Size.Y, thickness), parent)
        end
    end

    -- Walls follow the exact colliders, so doors retain the 14 x 10.5 clear aperture.
    for _, room in ipairs(manifest.Layout.Rooms) do
        local model = manifest.Rooms[room.Id]
        local palette = theme(room)
        local base = Configuration.WorldOrigin + Vector3.new(room.X, 0, room.Z)
        local visuals = Instance.new("Folder")
        visuals.Name = "Blender Architecture"
        visuals.Parent = model
        helper.Place("Floor" .. palette, CFrame.new(base), visuals,
            {Scale=Vector3.new(room.W/80, 1, room.D/64)})
        helper.Place("Ceiling", CFrame.new(base+Vector3.new(0, room.H-.5, 0)), visuals,
            {Scale=Vector3.new(room.W/80, 1, room.D/64)})
        for _, part in ipairs(model:GetChildren()) do
            if part:IsA("BasePart") then
                if part.Name:match("^Level 6 [A-Za-z]+ Wall")
                    or part.Name:match("^Level 6 [A-Za-z]+ Lintel") then
                    wallSkin(part, palette, visuals)
                elseif part.Name == "Level 6 Structural Column" then
                    centered("Wall"..palette, part.CFrame, part.Size, visuals)
                elseif part.Name == "Level 6 Ceiling Beam" then
                    centered("Lintel"..palette, part.CFrame, part.Size, visuals)
                end
            end
        end
    end

    for _, corridor in ipairs(manifest.Corridors) do
        local palette = if corridor.DoorType == "HiddenExit" then "Service" else theme(corridor.A)
        local folder = Instance.new("Folder")
        folder.Name = "Blender Corridor"
        folder.Parent = corridor.Model
        local horizontal = math.abs(corridor.Forward.X) > .5
        local cf = CFrame.new(corridor.Center)
            * (if horizontal then CFrame.Angles(0, math.pi*.5, 0) else CFrame.identity)
        local sections = math.ceil(corridor.Length / 64)
        local length = corridor.Length / sections
        for index=1,sections do
            local panel = cf * CFrame.new(0, 0, -corridor.Length*.5 + length*(index-.5))
            helper.Place("Floor"..palette, panel, folder, {Scale=Vector3.new(corridor.Width/80, 1, (length+.02)/64)})
            helper.Place("Ceiling", panel*CFrame.new(0, corridor.Height, 0), folder,
                {Scale=Vector3.new(corridor.Width/80, 1, length/64)})
        end
        for _, part in ipairs(corridor.Model:GetChildren()) do
            if part:IsA("BasePart") and part.Name == "Level 6 Corridor Wall" then
                wallSkin(part, palette, folder)
            end
        end
    end

    local chairNames = {"ChairBlue", "ChairYellow", "ChairRed", "ChairGreen"}
    for _, part in ipairs(legacy) do
        if not part:IsA("BasePart") then continue end
        if part:GetAttribute("Level6_TableCollision") == true then
            local pivot = part.CFrame * CFrame.new(0, -3, 0)
            helper.Place("FoldingTable", pivot, part.Parent)
            counts.Tables += 1
            -- Room Dressing adds the authored cups/plates to table tops.
        elseif part.Name == "Level 6 Vetted Plastic Party Chair" or part.Name == "Level 6 Party Chair" then
            local paletteIndex = (counts.Chairs % #chairNames) + 1
            helper.Place(chairNames[paletteIndex], part.CFrame*CFrame.new(0, -2.28, 0)
                *CFrame.Angles(0, math.pi, 0), part.Parent)
            counts.Chairs += 1
        elseif part.Name == "Level 6 Fluorescent Frame" then
            centered("FluorescentFrame", part.CFrame, Vector3.new(7.5,.3675,2.4), part.Parent)
        elseif part.Name == "Level 6 Fluorescent Diffuser" then
            local skin = centered("FluorescentDiffuser", part.CFrame, Vector3.new(7.05,.155,2.05), part.Parent)
            skin.Name = part.Name
            skin.Color = part.Color
            skin.Material = part.Material
            skin.Transparency = part:GetAttribute("Level6_LegacyTransparency") or 0
            if part:GetAttribute("Level6_SubtleFlicker") then skin:SetAttribute("Level6_SubtleFlicker", true) end
            for _, child in ipairs(part:GetChildren()) do if child:IsA("Light") then child.Parent = skin end end
            part.Name = "Legacy Hidden Fluorescent Anchor"
            counts.Fixtures += 1
        elseif part.Name == "PA Speaker Housing" then
            centered("PASpeaker", part.CFrame*CFrame.Angles(0,math.pi,0), Vector3.new(1.75,2.3,1.21), part.Parent)
        end
    end

    -- Actual authored discs replace PickupParts, so carry/drop/collection clones the Blender geometry.
    for _, module in ipairs(manifest.Modules) do
        local oldDisc = module.PickupParts[1]
        local flatCF = oldDisc.CFrame * CFrame.Angles(0,0,-math.pi*.5)
        local disc = helper.Place("CD", flatCF, module.Model, {Scale=Vector3.one*1.65})
        local hub = helper.Place("CD", flatCF*CFrame.new(0,.002,0), module.Model, {Scale=Vector3.one*.31})
        disc:SetAttribute("Level6_CDBasis", "Y")
        hub:SetAttribute("Level6_CDBasis", "Y")
        disc:SetAttribute("Level6_CDPickupVisual", true)
        hub:SetAttribute("Level6_CDPickupVisual", true)
        module.PickupParts = {disc, hub}
        local case = helper.Place("CDCase", module.Core.CFrame*CFrame.new(0,-.09,0), module.Model,
            {Scale=Vector3.new(2.45,1.25,2.18)})
        case:SetAttribute("Level6_CDPersistentDisplay", true)
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
        local disc = helper.Place("CD", slotCF, player.Model, {Scale=Vector3.one*.62})
        local hub = helper.Place("CD", slotCF*CFrame.new(0,.002,0), player.Model, {Scale=Vector3.one*.13})
        disc.Transparency=1 hub.Transparency=1
        slot.Disc=disc slot.Hub=hub
        slot.Receiver.CFrame=slotCF
        local indicator = centered("FluorescentDiffuser", playerCF*CFrame.new((index-3)*.9,3.65,1.23),
            Vector3.new(.16,.10,.05), player.Model)
        slot.Light.Parent=indicator
        slot.Indicator=indicator
    end

    -- The hidden door is a real Blender wall mesh controlled directly by the existing objective tween.
    local portal = manifest.ExitPortal
    local proxy = portal.Wall
    local newWall = centered("WallRed", proxy.CFrame, proxy.Size, portal.Model)
    newWall.Name = "Blender Concealed Exit Wall"
    newWall.CanCollide=true newWall.CanQuery=true
    newWall:SetAttribute("Level6_HiddenExitWall", true)
    proxy.CanCollide=false proxy.CanQuery=false
    portal.Wall=newWall
    local newFrames={}
    for _, frame in ipairs(portal.FrameParts) do
        local skin = centered("FluorescentDiffuser", frame.CFrame, frame.Size, portal.Model, frame.Color)
        skin.Transparency=1 skin.Material=Enum.Material.Neon
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
    manifest.VisualCleanup = dressing and dressing.Cleanup
    manifest.VisualReport = {Kit=counts, Dressing=dressing and dressing.Report}
    manifest.KitHelper = helper
    world:SetAttribute("Level6_BlenderApplied", true)
    world:SetAttribute("Level6_BlenderMeshCount", counts.Meshes)
    world:SetAttribute("Level6_BlenderVisibleTriangles", counts.Triangles)
    return manifest.VisualReport
end
return Adapter
