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
