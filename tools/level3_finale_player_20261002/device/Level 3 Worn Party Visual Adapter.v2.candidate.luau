--!strict
-- Replaces the cloned builder's visible primitives with the Blender-authored kit.
-- Legacy invisible collision, navigation and prompt anchors remain authoritative.
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
    -- The authored revision routes only these two floors away from their
    -- inherited district palette. Exit walls remain red in the Blender scene.
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
        -- The carrier is the authored family pivot. Existing CD and slot logic
        -- requires a BasePart it can clone, weld, move, and fade. Its MeshPart
        -- children retain their separate Blender materials and local UV scale.
        local carrier = Instance.new("Part")
        carrier.Name = name
        carrier.Size = Vector3.new(.05, .05, .05)
        carrier.CFrame = worldCF
        carrier.Anchored = true
        -- Reactive carriers start visible so the objective controller's
        -- world-CD fade from 0 to 1 also fades all five material chunks.
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
                -- An explicit C0 survives cloning and moving a detached CD
                -- carrier before the carry/drop model enters Workspace.
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

    -- Keep the owned arrival tube, aperture seals and notice visible; the
    -- Blender kit still replaces every other legacy room/corridor visual.
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
        helper.Place(floorAsset(room), CFrame.new(base), visuals,
            {Scale=Vector3.new(room.W/80, 1, room.D/64)})
        helper.Place("Ceiling", CFrame.new(base+Vector3.new(0, room.H-.5, 0)), visuals,
            {Scale=Vector3.new(room.W/80, 1, room.D/64)})
        for _, part in ipairs(model:GetChildren()) do
            if part:IsA("BasePart") then
                if part.Name:match("^Level 3 [A-Za-z]+ Wall")
                    or part.Name:match("^Level 3 [A-Za-z]+ Lintel") then
                    wallSkin(part, palette, visuals)
                elseif part.Name == "Level 3 Structural Column" then
                    centered("Wall"..palette, part.CFrame, part.Size, visuals)
                elseif part.Name == "Level 3 Ceiling Beam" then
                    centered("Lintel"..palette, part.CFrame, part.Size, visuals)
                end
            end
        end
    end

    for _, corridor in ipairs(manifest.Corridors) do
        local palette = theme(corridor.A)
        local floorName = if corridor.B.Role == "Exit" then "FloorService"
            elseif corridor.A.Role == "Arrival" then "FloorDefault"
            else "Floor" .. palette
        local folder = Instance.new("Folder")
        folder.Name = "Blender Corridor"
        folder.Parent = corridor.Model
        local horizontal = math.abs(corridor.Forward.X) > .5
        for _, segment in ipairs(corridor.Segments) do
            local cf = CFrame.new(segment.Center)
                * (if horizontal then CFrame.Angles(0, math.pi*.5, 0) else CFrame.identity)
            local sections = math.ceil(segment.Length / 64)
            local length = segment.Length / sections
            for index=1,sections do
                local panel = cf * CFrame.new(0, 0, -segment.Length*.5 + length*(index-.5))
                helper.Place(floorName, panel, folder,
                    {Scale=Vector3.new(corridor.Width/80, 1, length/64)})
                helper.Place("Ceiling", panel*CFrame.new(0, corridor.Height, 0), folder,
                    {Scale=Vector3.new(corridor.Width/80, 1, length/64)})
            end
        end
        for _, part in ipairs(corridor.Model:GetChildren()) do
            if part:IsA("BasePart") and part.Name == "Level 3 Corridor Wall" then
                wallSkin(part, palette, folder)
            end
        end
        if corridor.BlenderRoom then
            local inserted = corridor.BlenderRoom
            local data = assert(Metadata[inserted.Asset], "Missing authored gateway room metadata")
            assert(data.HasFlattenedFixtureVisuals == true
                and data.HasIntegratedFixtureCollision == true
                and data.Anchors and data.Anchors.JoinNorth and data.Anchors.JoinSouth,
                "Authored gateway room must include both portals and integrated fixtures")
            for _, portalName in ipairs({"JoinNorth", "JoinSouth"}) do
                local portal = data.AnchorDetails and data.AnchorDetails[portalName]
                assert(portal and portal.l6_port_width >= inserted.PortalWidth
                    and portal.l6_port_height >= inserted.PortalHeight,
                    "Authored gateway portal is too small for Manager navigation")
            end
            local sectionCenter = corridor.StartPoint
                + corridor.Forward * (inserted.StartDistance + inserted.Length*.5)
            -- lookAt's local -Z faces B. JoinSouth (+Z) faces A, while
            -- JoinNorth (-Z) faces B on both horizontal and vertical links.
            local sectionCF = CFrame.lookAt(sectionCenter, sectionCenter + corridor.Forward)
            local section = helper.Place(inserted.Asset, sectionCF, folder, {Collidable=true})
            section:SetAttribute("Level3_BlenderGatewayRoom", true)
            section:SetAttribute("Level3_BlenderLinkId", inserted.LinkId)
            section:SetAttribute("Level3_BlenderSectionIndex", inserted.SectionIndex)
            for index, lightData in ipairs(data.Lights or {}) do
                local position = lightData.positionXYZ
                if position then
                    local anchor = Instance.new("Attachment")
                    anchor.Name = "Authored Ceiling Light " .. index
                    anchor.CFrame = CFrame.new(blender(position))
                    anchor.Parent = section
                    local light = Instance.new("PointLight")
                    light.Name = "Level 3 Authored Room Lamp"
                    light.Color = Color3.new(table.unpack(lightData.colorRGB or {1,.9,.75}))
                    light.Brightness = 1.8
                    light.Range = 19
                    light.Shadows = false
                    light.Parent = anchor
                end
            end
        end
    end

    local chairNames = {"ChairBlue", "ChairYellow", "ChairRed", "ChairGreen"}
    for _, part in ipairs(legacy) do
        if not part:IsA("BasePart") then continue end
        if part:GetAttribute("Level3_TableCollision") == true then
            local pivot = part.CFrame * CFrame.new(0, -3, 0)
            helper.Place("FoldingTable", pivot, part.Parent)
            counts.Tables += 1
            -- Room Dressing adds the authored cups/plates to table tops.
        elseif part.Name == "Level 3 Vetted Plastic Party Chair" or part.Name == "Level 3 Party Chair" then
            local paletteIndex = (counts.Chairs % #chairNames) + 1
            helper.Place(chairNames[paletteIndex], part.CFrame*CFrame.new(0, -2.28, 0)
                *CFrame.Angles(0, math.pi, 0), part.Parent)
            counts.Chairs += 1
        elseif part.Name == "Level 3 Fluorescent Frame" then
            centered("FluorescentFrame", part.CFrame, Vector3.new(7.5,.3675,2.4), part.Parent)
        elseif part.Name == "Level 3 Fluorescent Diffuser" then
            local skin = centered("FluorescentDiffuser", part.CFrame,
                Vector3.new(7.05,.155,2.05), part.Parent, nil, true)
            -- Preserve the original SurfaceLight rectangle and emission pose.
            -- Authored mesh children are anchored and retain their Blender world transforms.
            skin.Size = part.Size
            skin.CFrame = part.CFrame
            skin.Name = part.Name
            skin.Color = part.Color
            skin.Material = part.Material
            skin.Transparency = part:GetAttribute("Level3_LegacyTransparency") or 0
            if part:GetAttribute("Level3_SubtleFlicker") then skin:SetAttribute("Level3_SubtleFlicker", true) end
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("Light") then
                    -- A broad ceiling cone reaches wall art without adding daylight.
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

    -- Actual authored discs replace PickupParts, so carry/drop/collection clones the Blender geometry.
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
    -- A readable 90s relay display above the authored Blender deck. Keep the
    -- physical screen and canvas at the same aspect ratio; the old 800x600
    -- TV canvas was squeezed onto a 3.3x0.72 strip and distorted every glyph.
    player.Model:SetAttribute("Level3_DiscPlayerVisualRevision", 3)
    local function devicePart(name, relativeCF, size, color, material)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.CFrame = playerCF * relativeCF
        p.Color = color
        p.Material = material or Enum.Material.Metal
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Parent = player.Model
        return p
    end
    local housing = devicePart("CD Relay Display Housing", CFrame.new(0,6.02,1.37),
        Vector3.new(4.92,1.86,.24), Color3.fromRGB(27,31,29))
    housing:SetAttribute("Level3_DiscPlayerDisplayHousing", true)
    for _, side in ipairs({-1,1}) do
        devicePart("CD Relay Display Support", CFrame.new(side*2.30,5.34,.94),
            Vector3.new(.12,2.12,.12), Color3.fromRGB(67,69,62))
        for _, y in ipairs({5.21,6.83}) do
            local screw = devicePart("CD Relay Display Screw", CFrame.new(side*2.34,y,1.506),
                Vector3.new(.095,.095,.025), Color3.fromRGB(132,132,114))
            screw.Shape = Enum.PartType.Ball
        end
    end
    local taskLamp = devicePart("CD Player Task Lamp", CFrame.new(0,7.06,1.52),
        Vector3.new(3.40,.10,.36), Color3.fromRGB(255,227,162), Enum.Material.Neon)
    local lampShade = devicePart("CD Player Task Lamp Shade", CFrame.new(0,7.16,1.48),
        Vector3.new(3.65,.13,.54), Color3.fromRGB(46,48,42))
    local taskLight = Instance.new("SurfaceLight")
    taskLight.Name = "CD Player Warm Task Light"
    taskLight.Face = Enum.NormalId.Bottom
    taskLight.Angle = 120
    taskLight.Range = 13
    taskLight.Brightness = .85
    taskLight.Color = Color3.fromRGB(255,225,165)
    taskLight.Shadows = false
    taskLight.Parent = taskLamp
    if statusSurface and statusSurface.Parent:IsA("BasePart") then
        local screen = statusSurface.Parent
        screen.Name = "CD Player Phosphor Display"
        screen.Size = Vector3.new(4.55,1.50,.04)
        screen.CFrame = playerCF*CFrame.new(0,6.02,1.514)
        screen.Material = Enum.Material.SmoothPlastic
        screen.Color = Color3.fromRGB(3,14,11)
        screen.Transparency = 0
        screen.Reflectance = 0
        statusSurface.Enabled = true
        statusSurface.Face = Enum.NormalId.Back
        statusSurface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
        statusSurface.CanvasSize = Vector2.new(910,300)
        statusSurface.LightInfluence = 0
        statusSurface.Brightness = 1.25
        statusSurface.AlwaysOnTop = false
        statusSurface.MaxDistance = 95
        local static = statusSurface:FindFirstChild("CRT Generated Static")
        if static and static:IsA("ImageLabel") then static.Visible=false end
        local background = Instance.new("Frame")
        background.Name = "Phosphor Background"
        background.Size = UDim2.fromScale(1,1)
        background.BackgroundColor3 = Color3.fromRGB(3,17,13)
        background.BorderSizePixel = 0
        background.ZIndex = 1
        background.Parent = statusSurface
        local function displayText(name, text, position, size, fontSize, color)
            local label = Instance.new("TextLabel")
            label.Name = name
            label.Text = text
            label.Position = position
            label.Size = size
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Code
            label.FontFace = Font.new(label.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
            label.TextSize = fontSize
            label.TextColor3 = color
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.TextStrokeTransparency = 1
            label.ZIndex = 3
            label.Parent = statusSurface
            return label
        end
        displayText("Device Header", "BIRTHDAY CD PLAYER", UDim2.fromScale(.045,.045),
            UDim2.fromScale(.72,.18), 48, Color3.fromRGB(174,220,190))
        displayText("Deck Identifier", "RELAY 03", UDim2.fromScale(.79,.06),
            UDim2.fromScale(.19,.14), 20, Color3.fromRGB(91,140,112))
        local status = player.StatusLabel
        status.BackgroundTransparency = 1
        status.Position = UDim2.fromScale(.045,.29)
        status.Size = UDim2.fromScale(.63,.26)
        status.TextScaled = false
        status.TextSize = 52
        status.FontFace = Font.new(status.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextColor3 = Color3.fromRGB(103,247,177)
        status.TextStrokeTransparency = 1
        status.Text = "AWAITING DISCS"
        player.ProgressLabel = displayText("Inserted Disc Count", "0 / 5 CDS",
            UDim2.fromScale(.72,.29), UDim2.fromScale(.25,.26), 46, Color3.fromRGB(234,216,151))
        player.ScreenSlots = {}
        for index=1,5 do
            local slot = Instance.new("Frame")
            slot.Name = string.format("Disc Progress Segment %02d", index)
            slot.Position = UDim2.fromScale(.045+(index-1)*.184,.62)
            slot.Size = UDim2.fromScale(.168,.065)
            slot.BackgroundColor3 = Color3.fromRGB(20,37,35)
            slot.BorderSizePixel = 0
            slot.ZIndex = 3
            slot.Parent = statusSurface
            player.ScreenSlots[index] = slot
        end
        local instruction = player.InstructionLabel
        instruction.BackgroundTransparency = 1
        instruction.Position = UDim2.fromScale(.045,.77)
        instruction.Size = UDim2.fromScale(.92,.16)
        instruction.TextScaled = false
        instruction.TextSize = 40
        instruction.FontFace = Font.new(instruction.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
        instruction.TextXAlignment = Enum.TextXAlignment.Left
        instruction.TextColor3 = Color3.fromRGB(161,198,166)
        instruction.TextStrokeTransparency = 1
        local glow = Instance.new("SurfaceLight")
        glow.Name = "CD Player Screen Glow"
        glow.Face = Enum.NormalId.Back
        glow.Angle = 110
        glow.Range = 9
        glow.Brightness = .45
        glow.Color = Color3.fromRGB(125,231,179)
        glow.Shadows = false
        glow.Parent = screen
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

    -- The hidden door is a real Blender wall mesh controlled directly by the existing objective tween.
    local portal = manifest.ExitPortal
    local proxy = portal.Wall
    local newWall = centered("WallRed", proxy.CFrame, proxy.Size, portal.Model, nil, true)
    newWall.Name = "Blender Concealed Exit Wall"
    newWall:SetAttribute("Level3_HiddenExitWall", true)
    -- Retain the original full-size, invisible BasePart as the objective
    -- controller's collision wall; the multi-material skin is visual only.
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
