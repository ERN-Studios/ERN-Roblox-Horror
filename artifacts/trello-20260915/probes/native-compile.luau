-- Run in the normal Studio Edit command bar. Wrapping in a returned function
-- compiles source without running gameplay code. No security settings change.
local scripts = {}
for _, rootName in ipairs({"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "Workspace", "RobloxReplicatedStorage"}) do
    local root = game:FindFirstChild(rootName)
    if root then
        for _, item in ipairs(root:GetDescendants()) do
            if item:IsA("LuaSourceContainer") and not item:GetFullName():find("ServerStorage.Archive", 1, true) then
                table.insert(scripts, item)
            end
        end
    end
end
workspace:SetAttribute("CodexNativeCompileDone", false)
task.spawn(function()
    local results, passed = {}, 0
    for _, source in ipairs(scripts) do
        local probe = Instance.new("ModuleScript")
        probe.Name = "CodexCompileProbe"
        local ok, result = pcall(function()
            probe.Parent = game.ServerStorage
            local wrapped = "return function()\n" .. source.Source .. "\nend"
            game:GetService("ScriptEditorService"):UpdateSourceAsync(probe, function() return wrapped end)
            return require(probe)
        end)
        probe:Destroy()
        if ok and type(result) == "function" then passed += 1
        else table.insert(results, source:GetFullName() .. ": " .. tostring(result)) end
        task.wait()
    end
    workspace:SetAttribute("CodexNativeCompileReport", game.HttpService:JSONEncode({total=#scripts, passed=passed, failures=results}))
    workspace:SetAttribute("CodexNativeCompileDone", true)
end)
