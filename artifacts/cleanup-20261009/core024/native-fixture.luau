-- Proposal gate for CORE-024. Run through Studio MCP in the verified place.
-- All created objects live below an UNPARENTED test root. Existing sources,
-- lobby, kit, properties, attributes and player state are read only.
-- This is an Add/Emit contract and timing trial, not a complete lobby/gameplay test.
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local SES = game:GetService("ScriptEditorService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong test place")
local live = assert(SSS:FindFirstChild("LobbyReimaginedPreview")):FindFirstChild("EndBlockades")
assert(live and live:IsA("ModuleScript"), "Wrong EndBlockades instance")
local source = live.Source
assert(SES:GetEditorSource(live) == source, "Source/editor conflict: reconcile before test")

local function hash(s)
    local digest = ENC:ComputeBufferHash(buffer.fromstring(s), Enum.HashAlgorithm.Sha256)
    local chars = table.create(buffer.len(digest))
    for i = 0, buffer.len(digest) - 1 do chars[i + 1] = string.format("%02x", buffer.readu8(digest, i)) end
    return table.concat(chars)
end
local function replaceOnce(s, old, new)
    local at = assert(string.find(s, old, 1, true), "Fresh source differs from candidate needle")
    assert(not string.find(s, old, at + #old, true), "Ambiguous candidate needle")
    return string.sub(s, 1, at - 1) .. new .. string.sub(s, at + #old)
end
local candidate = source
for _, row in ipairs({
    {"function Module.Emit(plan, center, visuals, collisions, lighting, place)",
     "function Module.Emit(plan, center, visuals, collisions, lighting, place, includeFurniture)"},
    {"\tassert(plan.statistics.uniqueNewMeshes == 0 and plan.statistics.archCornerFailures == 0)",
     "\tassert(plan.statistics.uniqueNewMeshes == 0 and plan.statistics.archCornerFailures == 0)\n\tassert(includeFurniture == nil or type(includeFurniture) == \"boolean\", \"Invalid furniture placement option\")"},
    {"\tfor _, item in ipairs(plan.placements) do",
     "\tif includeFurniture ~= false then\n\tfor _, item in ipairs(plan.placements) do"},
    {"\tend\n\tfor _, item in ipairs(plan.colliders) do", "\tend\n\tend\n\tfor _, item in ipairs(plan.colliders) do"},
    {"\tfolder:SetAttribute(\"AddedInstancedTriangles\", plan.statistics.extraInstancedTriangles)",
     "\tfolder:SetAttribute(\"AddedInstancedTriangles\", includeFurniture == false and 0 or plan.statistics.extraInstancedTriangles)\n\tif includeFurniture == false then folder:SetAttribute(\"SkippedFurnitureInstances\", #plan.placements) end"},
    {"function Module.Add(model, kit, manifest)", "function Module.Add(model, kit, manifest, includeFurniture)"},
    {"assert(model:FindFirstChild(\"PreviewLighting\")), place)",
     "assert(model:FindFirstChild(\"PreviewLighting\")), place, includeFurniture)"},
}) do candidate = replaceOnce(candidate, row[1], row[2]) end

local root = Instance.new("Folder")
root.Name = "CORE024_Isolated_Unparented_Test"
assert(root.Parent == nil)
local report = {
    BaselineSourceSHA256 = hash(source), CandidateSourceSHA256 = hash(candidate),
    Checks = 0, Trials = {}, ContractScopeOnly = true,
    Scope = "Native Add/Emit on isolated unparented roots; full real lobby flow remains required",
}
local function check(value, message)
    report.Checks += 1
    assert(value, message)
end
local function difference(expected, actual)
    local first = nil
    for i = 1, math.max(#expected, #actual) do
        if string.byte(expected, i) ~= string.byte(actual, i) then first = i; break end
    end
    return {ExpectedBytes = #expected, ActualBytes = #actual,
        ExpectedSHA256 = hash(expected), ActualSHA256 = hash(actual), FirstDifferentByte = first,
        ExpectedTail = string.sub(expected, math.max(1, #expected - 80)),
        ActualTail = string.sub(actual, math.max(1, #actual - 80))}
end
local function module(body, name)
    -- Source containers MUST be fresh instances. A previous Clone+editor-write
    -- trial changed the authoritative source; shared editor identity is suspected.
    local clone = Instance.new("ModuleScript")
    clone.Name = name
    clone.Parent = root
    check(clone.Source == "" and SES:GetEditorSource(clone) == "", "Fresh instance has an independent empty source/editor baseline")
    SES:UpdateSourceAsync(clone, function(current)
        assert(current == "" and clone.Source == "", "New isolated module changed before write")
        assert(live.Source == source and SES:GetEditorSource(live) == source, "Authoritative source changed before isolated write")
        return body
    end)
    local actualSource, actualEditor = clone.Source, SES:GetEditorSource(clone)
    if actualSource ~= body or actualEditor ~= body then
        report.CloneDiagnostics = {Name = name, Source = difference(body, actualSource), Editor = difference(body, actualEditor),
            SourceEditorMatches = actualSource == actualEditor, SourceIsOriginal = actualSource == source, EditorIsOriginal = actualEditor == source}
    end
    check(clone.Source == body and SES:GetEditorSource(clone) == body, "Isolated clone Source/editor contain exact test source")
    return require(clone)
end
local function encoded(value)
    local kind = typeof(value)
    if kind == "CFrame" then
        local out = {}
        for _, x in ipairs({value:GetComponents()}) do out[#out + 1] = string.format("%.9g", x) end
        return "CFrame:" .. table.concat(out, ",")
    elseif kind == "Vector3" then
        return string.format("Vector3:%.9g,%.9g,%.9g", value.X, value.Y, value.Z)
    elseif kind == "Color3" then
        return string.format("Color3:%.9g,%.9g,%.9g", value.R, value.G, value.B)
    end
    return kind .. ":" .. tostring(value)
end
local function attrs(object, ignoreSkip)
    local rows = {}
    for key, value in pairs(object:GetAttributes()) do
        if not (ignoreSkip and key == "SkippedFurnitureInstances") then rows[#rows + 1] = key .. "=" .. encoded(value) end
    end
    table.sort(rows)
    return table.concat(rows, ";")
end
local function signature(object, ignoreSkip)
    local rows = {}
    for _, item in ipairs(object:GetDescendants()) do
        local path, cursor = {}, item
        while cursor ~= object do table.insert(path, 1, cursor.Name); cursor = cursor.Parent end
        local values = {table.concat(path, "/"), item.ClassName, attrs(item, ignoreSkip)}
        if item:IsA("BasePart") then
            for _, key in ipairs({"CFrame", "Size", "Anchored", "CanCollide", "CanTouch", "CanQuery", "Transparency", "CastShadow", "Material", "MaterialVariant", "Color"}) do
                values[#values + 1] = key .. "=" .. encoded(item[key])
            end
            if item:IsA("MeshPart") then
                for _, key in ipairs({"MeshId", "TextureID", "DoubleSided", "CollisionFidelity", "RenderFidelity"}) do
                    values[#values + 1] = key .. "=" .. encoded(item[key])
                end
            end
        elseif item:IsA("Light") then
            for _, key in ipairs({"Enabled", "Color", "Brightness", "Shadows"}) do values[#values + 1] = key .. "=" .. encoded(item[key]) end
            if item:IsA("PointLight") then values[#values + 1] = "Range=" .. tostring(item.Range) end
        end
        rows[#rows + 1] = table.concat(values, "|")
    end
    table.sort(rows)
    return attrs(object, ignoreSkip) .. "\n" .. table.concat(rows, "\n")
end
local center = Vector3.new(220, 30, -760)
local manifest = {previewCenter = {220, 30, -760}}
local families = {"Desk", "FilingCabinet", "VinylBench", "Sofa", "StackChair", "CRTMonitor", "Photocopier", "WireTrolley"}
local kit
local bake = assert(live.Parent:FindFirstChild("RuntimeBake"))
assert(bake:IsA("ModuleScript") and SES:GetEditorSource(bake) == bake.Source, "RuntimeBake source/editor conflict")
local expectedKitName = assert(bake.Source:match('local KIT = "([^"]+)"'), "Read-only kit contract missing")
local installed = SS:FindFirstChild(expectedKitName)
report.ExpectedKitName = expectedKitName
report.KitInventory = {}
for _, item in ipairs(SS:GetChildren()) do
    if item.Name:find("LobbyReimagined", 1, true) then
        local matched = 0
        for _, family in ipairs(families) do if item:FindFirstChild(family) then matched += 1 end end
        report.KitInventory[#report.KitInventory + 1] = {Name = item.Name, Class = item.ClassName,
            Ready = item:GetAttribute("Ready"), Children = #item:GetChildren(), MatchedFurnitureFamilies = matched,
            ManifestSHA256 = item:GetAttribute("ManifestSHA256"), Owned = item:GetAttribute("LobbyReimaginedOwned")}
    end
end
if installed and installed:GetAttribute("Ready") == true then
    for _, item in ipairs(installed:GetDescendants()) do
        assert(not item:IsA("LuaSourceContainer"), "Do not clone source containers inside a kit")
    end
    kit = installed:Clone()
    report.KitKind = "Clone of installed native kit"
    report.KitChildren = #kit:GetChildren()
else
    kit = Instance.new("Folder")
    report.KitKind = "Synthetic MeshPart/Model kit; actual asset bake/appearance remain unverified"
    for i, family in ipairs(families) do
        local part = Instance.new("MeshPart")
        part.Size = Vector3.new(2 + i / 10, 3, 2)
        part.Anchored = true
        part.CFrame = CFrame.new(i / 10, i / 20, -i / 30)
        part:SetAttribute("LobbyReimaginedOwned", true)
        if i % 2 == 0 then
            local model = Instance.new("Model")
            model.Name = family
            part.Name = "Nested Furniture Mesh"
            part.Parent = model
            model.PrimaryPart = part
            local support = Instance.new("Part")
            support.Name, support.Size, support.Anchored = "Fixture Support", Vector3.new(.5, .5, .5), true
            support.CFrame = part.CFrame
            support.Parent = model
            model.Parent = kit
        else part.Name = family; part.Parent = kit end
    end
end
kit.Parent = root
local function world(name)
    local m = Instance.new("Model")
    m.Name = name
    m.WorldPivot = CFrame.new(center)
    m:SetAttribute("LobbyReimaginedOwned", true)
    m:SetAttribute("Ready", false)
    m.Parent = root
    for _, name in ipairs({"BlenderVisuals", "PreviewCollisions", "PreviewLighting"}) do
        local folder = Instance.new("Folder"); folder.Name = name; folder.Parent = m
    end
    for side = -1, 1, 2 do
        for i = 1, 14 do
            local host = Instance.new("Part")
            host.Name, host.Anchored = "Tunnel Lamp", true
            host.CanCollide, host.CanTouch, host.CanQuery = false, false, false
            host.CFrame = CFrame.new(center + Vector3.new(side * 11, 29.5, -130 + (i - 1) * 20))
            host.Parent = m.PreviewLighting
            local fill = Instance.new("PointLight")
            fill.Name, fill.Brightness, fill.Range, fill.Shadows = "Preview Fill", .23, 36, false
            fill.Parent = host
        end
    end
    local sentinel = Instance.new("Part")
    sentinel.Name, sentinel.Anchored = "Unrelated Stage Fixture", true
    sentinel.Parent = m.PreviewLighting
    local fill = Instance.new("PointLight")
    fill.Name, fill.Brightness, fill.Range = "Preview Fill", .77, 19
    fill.Parent = sentinel
    return m
end
local function finalise(m, folder)
    -- Exact relevant Builder removal/Ready state; other Builder work is excluded.
    local removed = folder:GetAttribute("SkippedFurnitureInstances") or 0
    for _, piece in ipairs(folder:GetChildren()) do piece:Destroy(); removed += 1 end
    folder:SetAttribute("AddedInstancedTriangles", 0)
    m:SetAttribute("EndFurnitureRemoved", removed)
    m:SetAttribute("InstantiatedTriangles", 98765 + folder:GetAttribute("AddedInstancedTriangles"))
    m:SetAttribute("Ready", true)
end
local function reachTransform(m)
    -- Same existing north-end curtain opening condition in Builder (no live world write).
    local wallPosition, inward = center + Vector3.new(0, 18, 134), Vector3.new(0, 0, -1)
    local opened = 0
    for _, c in ipairs(m.PreviewCollisions:GetChildren()) do
        local along = c:IsA("BasePart") and (c.Position - wallPosition):Dot(inward)
        if along and along > -3 and along < 9
            and (c.Name == "Opaque End Cap" or c.Name == "Furniture Base" or c:GetAttribute("FurnitureEndBlocker") == true) then
            c.CanCollide, c.CanQuery, c.CanTouch = false, false, false
            c:SetAttribute("OpenedForTunnelReach", true)
            opened += 1
        end
    end
    return opened
end
local function countLenses(m)
    local count = 0
    for _, child in ipairs(m.PreviewLighting:GetChildren()) do
        if child.Name:find("Ceiling Tube Luminous Lens", 1, true) then count += 1 end
    end
    return count
end
local function expectFailure(fn, text)
    local ok, err = pcall(fn)
    check(not ok and tostring(err):find(text, 1, true) ~= nil, "Expected error: " .. text .. "; got " .. tostring(err))
end
local baseline, changed
local ok, problem = pcall(function()
    baseline, changed = module(source, "Original EndBlockades"), module(candidate, "Candidate EndBlockades")
    -- Default Add authoring behavior must remain byte-for-byte property equivalent.
    for _, option in ipairs({"omitted", "true"}) do
        local a, b = world("Before"), world("After")
        local fa = baseline.Add(a, kit, manifest)
        local fb = option == "omitted" and changed.Add(b, kit, manifest) or changed.Add(b, kit, manifest, true)
        check(#fa:GetChildren() == 219 and #fb:GetChildren() == 219, "Default authoring placements preserved")
        check(#a.PreviewCollisions:GetChildren() == 66, "Baseline owns 66 curtains")
        check(countLenses(a) == 28 and countLenses(b) == 28, "28 lenses preserved")
        check(signature(a, false) == signature(b, false), "Default Add full geometry/property/attribute parity")
        check(fa:GetAttribute("AddedInstancedTriangles") == 220612, "Baseline triangle contract")
        a:Destroy(); b:Destroy()
    end
    for trial = 1, 7 do
        local a, b = world("Before"), world("After")
        local started = os.clock()
        local fa = baseline.Add(a, kit, manifest)
        local clones = #fa:GetChildren()
        finalise(a, fa)
        local oldTime = os.clock() - started
        started = os.clock()
        local fb = changed.Add(b, kit, manifest, false)
        local nextClones = #fb:GetChildren()
        finalise(b, fb)
        local newTime = os.clock() - started
        check(clones == 219 and nextClones == 0, "219 transient furniture instances become zero")
        check(#fa:GetChildren() == 0 and #fb:GetChildren() == 0, "Both final folders empty")
        check(fa:GetAttribute("AddedFurnitureInstances") == fb:GetAttribute("AddedFurnitureInstances"), "Historical planned-furniture metadata preserved")
        check(fb:GetAttribute("SkippedFurnitureInstances") == 219, "Explicit skipped-furniture record")
        check(signature(a, true) == signature(b, true), "Post-removal full surviving property/attribute parity")
        local openedA, openedB = reachTransform(a), reachTransform(b)
        check(openedA > 0 and openedA == openedB, "Tunnel Reach opens same curtains")
        check(signature(a, true) == signature(b, true), "Final Tunnel Reach collider/lens/Ready parity")
        check(math.abs(a.PreviewLighting["Unrelated Stage Fixture"]["Preview Fill"].Brightness - .77) < 1e-6, "Unrelated emitter remains unchanged")
        report.Trials[#report.Trials + 1] = {BeforeSeconds = oldTime, AfterSeconds = newTime,
            BeforeTransientFurniture = clones, AfterTransientFurniture = nextClones, OpenedCurtains = openedA}
        a:Destroy(); b:Destroy()
    end
    -- Public Emit contract: default calls still create placements; explicit false skips.
    local plan = {schema = "lobby-r4-additive-end-clutter-v1", statistics = {uniqueNewMeshes = 0, archCornerFailures = 0, extraInstancedTriangles = 12},
        placements = {{family = "Desk", name = "Authoring Placement", robloxPosition = {0, 1, 0}, rotation = {0, .3, 0}}},
        colliders = {{name = "Contract Collider", size = {2, 3, 1}, position = {0, 1, 4}}}}
    local function emitTest(api, option)
        local m, calls = world("Emit"), 0
        local function place(_, cf, parent)
            calls += 1
            local p = Instance.new("Part"); p.Anchored = true; p.CFrame = cf; p.Parent = parent; return p
        end
        local folder = api.Emit(plan, center, m.BlenderVisuals, m.PreviewCollisions, m.PreviewLighting, place, option)
        return m, folder, calls
    end
    local a, fa, ca = emitTest(baseline)
    local b, fb, cb = emitTest(changed)
    check(ca == 1 and cb == 1 and signature(a, false) == signature(b, false), "Public Emit default authoring parity")
    a:Destroy(); b:Destroy()
    local m, folder, calls = emitTest(changed, false)
    check(calls == 0 and #folder:GetChildren() == 0 and #m.PreviewCollisions:GetChildren() == 1, "Explicit Emit skip preserves colliders")
    expectFailure(function() changed.Emit(plan, center, m.BlenderVisuals, m.PreviewCollisions, m.PreviewLighting, nil, false) end, "Owned pile already exists")
    m:Destroy()
    for _, api in ipairs({baseline, changed}) do
        local m = world("Unowned"); m:SetAttribute("LobbyReimaginedOwned", false)
        expectFailure(function() api.Add(m, kit, manifest) end, "Unowned lobby")
        check(not m.BlenderVisuals:FindFirstChild("Reference End Furniture Piles"), "Unowned rejection creates no owned folder")
        m:Destroy()
        local m, empty = world("Missing Family"), Instance.new("Folder")
        expectFailure(function() api.Add(m, empty, manifest) end, "Missing installed Blender family")
        m:Destroy(); empty:Destroy()
        check(#m:GetDescendants() == 0, "Outer build rollback removes partial error-owned geometry")
    end
    local m, empty = world("Skip Missing Family"), Instance.new("Folder")
    local f = changed.Add(m, empty, manifest, false)
    check(#f:GetChildren() == 0 and #m.PreviewCollisions:GetChildren() == 66, "Runtime skip no longer depends on retired furniture prefab delivery")
    m:Destroy(); empty:Destroy()
    local m = world("Invalid Option")
    expectFailure(function() changed.Add(m, kit, manifest, "invalid") end, "Invalid furniture placement option")
    check(not m.BlenderVisuals:FindFirstChild("Reference End Furniture Piles"), "Option validation precedes creation")
    m:Destroy()
    check(root.Parent == nil, "All test objects remain outside the active DataModel")
    check(live.Source == source and SES:GetEditorSource(live) == source, "Authoritative source/editor remain unchanged")
end)
-- This check must run even when a fixture assertion or staging step failed.
local sourceAfter, editorAfter = live.Source, SES:GetEditorSource(live)
report.AuthoritativeUnchanged = sourceAfter == source and editorAfter == source
if not report.AuthoritativeUnchanged then
    report.AuthoritativeDrift = {Source = difference(source, sourceAfter), Editor = difference(source, editorAfter)}
    report.MaterialBlocker = "Authoritative source/editor changed during an isolated gate; root must stop and reconcile/rollback"
end
report.ObjectsBeforeCleanup = #root:GetDescendants()
root:Destroy()
report.ObjectsAfterCleanup = #root:GetDescendants()
report.CleanupPassed = report.ObjectsAfterCleanup == 0 and root.Parent == nil
report.Passed = ok and report.CleanupPassed and report.AuthoritativeUnchanged
report.Error = not ok and tostring(problem) or nil
-- No physical/gameplay success is inferred from signatures or the synthetic fixture.
report.Unverified = {"Actual full Builder MaterialPolish/Scene/shops/support/stage flow", "Physical traversal/raycast in a real isolated simulation",
    "Public/developer queue, join/reset, multiplayer/streaming", "Full lobby boot time/CPU/memory/FPS", "MaterialPolishFurnitureCount intentional diagnostic delta"}
return HS:JSONEncode(report)
