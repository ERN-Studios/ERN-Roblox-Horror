-- Invoke with a freshly staged, test-owned ModuleScript containing the candidate.
-- Staging and authoritative Source/editor checks belong to the caller.
local function probe(candidateModule)
    assert(candidateModule:IsA("ModuleScript"), "Candidate must be a fresh ModuleScript")
    local storage = game:GetService("ServerStorage")
    local kit = assert(storage:FindFirstChild("Level1BlenderKitV2"), "Actual Level 1 kit is unavailable")
    local originals = {}
    for _, object in ipairs(kit:GetDescendants()) do
        if object:IsA("Model") then originals[object] = object.ModelStreamingMode end
    end
    local activeBefore = workspace:GetAttribute("Level1BlenderActive")
    local countBefore = workspace:GetAttribute("Level1BlenderRoomCount")
    local maze = Instance.new("Model")
    maze.Name = "StutterAssetsRendererProbe"
    maze.Parent = storage
    local state
    local ok, result = xpcall(function()
        local renderer = require(candidateModule)
        state = renderer.Begin(maze)
        state:Rooms({{}, {}}, {{}, {}}, 2, 24, -24, {}, 0, 0)
        local rooms = assert(maze:FindFirstChild("BlenderRooms"), "Room folder missing")
        assert(#rooms:GetChildren() == 4, "Tiny probe changed room generation")
        local roofs, parts = 0, 0
        for _, room in ipairs(rooms:GetChildren()) do
            assert(room:IsA("Model") and room.ModelStreamingMode == Enum.ModelStreamingMode.Atomic,
                "Generated room is not atomic")
            local roof, floor = false, false
            for _, object in ipairs(room:GetDescendants()) do
                if object:IsA("BasePart") then
                    parts += 1
                    if object:GetAttribute("RoomRole") == "SurfaceCeiling" and object.Transparency < 1 then roof = true end
                    if object:GetAttribute("RoomRole") == "SurfaceFloor" and object.Transparency < 1 then floor = true end
                end
            end
            assert(roof and floor, "Actual room kit lacks a visible roof/floor")
            roofs += 1
        end
        assert(maze.ModelStreamingMode == Enum.ModelStreamingMode.Default, "Probe made the full maze atomic")
        return {rooms = 4, visibleRoofs = roofs, clonedParts = parts, scope = "tiny actual-kit generation contract"}
    end, debug.traceback)
    if state then pcall(function() state:Cleanup() end) end
    maze:Destroy()
    workspace:SetAttribute("Level1BlenderActive", activeBefore)
    workspace:SetAttribute("Level1BlenderRoomCount", countBefore)
    local preserved, preservationError = pcall(function()
        for object, mode in pairs(originals) do
            assert(object:IsDescendantOf(kit) and object.ModelStreamingMode == mode,
                "Probe changed an authoritative room template")
        end
        assert(workspace:GetAttribute("Level1BlenderActive") == activeBefore
            and workspace:GetAttribute("Level1BlenderRoomCount") == countBefore, "Borrowed markers were not restored")
        assert(not maze.Parent, "Probe maze was not cleaned up")
    end)
    assert(preserved, preservationError)
    assert(ok, result)
    return result
end
return probe
