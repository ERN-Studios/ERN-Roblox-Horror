-- Scoped compare-and-swap of reviewed candidates against fresh authoritative Studio text.
-- This never enumerates repository files or overwrites a different live/editor baseline.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
assert(game.PlaceId == 131311258779917 and game.CreatorId == 1039373905, "Wrong place")
assert(not game:GetService("RunService"):IsRunning(), "Apply in Edit mode")
local permitted = {
    ["ServerScriptService.Level 6 Systems.Level 6 Layout Generator"] = true,
    ["ServerScriptService.Level 6 Systems.Level 6 World Builder"] = true,
    ["ServerScriptService.Level 6 Systems.Level 6 Visual Adapter"] = true,
    ["ServerScriptService.Level 6 Systems.Level 6 Objective Controller"] = true,
    ["ServerScriptService.Level 6 Systems.Level 6 Preview Runtime"] = true,
    ["ServerScriptService.Level 6 Systems.Level 6 Kit Metadata"] = true,
    ["ServerScriptService.Level 6 Systems.Level6BlenderRuntimeBake"] = true,
}
local previousHttp = HS.HttpEnabled
local receipts = {}
local ok, err = pcall(function()
    HS.HttpEnabled = true
    local payload = HS:JSONDecode(HS:GetAsync("http://127.0.0.1:8881/scoped-script-payload.json", true))
    assert(#payload.scripts == 7, "Unexpected write count")
    local seen = {}
    for _, item in ipairs(payload.scripts) do
        assert(permitted[item.path] and not seen[item.path], "Unreviewed or duplicate script target")
        seen[item.path] = true
        local instance = game
        for segment in item.path:gmatch("[^.]+") do
            instance = assert(instance:FindFirstChild(segment), "Target disappeared: " .. item.path)
        end
        assert(instance.ClassName == "ModuleScript", "Target class changed")
        assert(instance.Source == item.before and SES:GetEditorSource(instance) == item.before,
            "Concurrent source/editor change: " .. item.path)
        local chunk, compileError = loadstring(item.after)
        assert(chunk, "Candidate compile error: " .. tostring(compileError))
        item.instance = instance
    end
    for _, item in ipairs(payload.scripts) do
        local target = item.instance
        assert(target.Parent and target:GetFullName() == item.path, "Target identity changed")
        assert(target.Source == item.before and SES:GetEditorSource(target) == item.before,
            "Concurrent change before update: " .. item.path)
        SES:UpdateSourceAsync(target, function(editor)
            assert(editor == item.before and target.Source == item.before,
                "Concurrent change inside update: " .. item.path)
            return item.after
        end)
        assert(target.Source == item.after and SES:GetEditorSource(target) == item.after,
            "Source/editor update parity failed: " .. item.path)
        table.insert(receipts, {path=item.path, beforeSHA256=item.beforeSHA256,
            afterSHA256=item.afterSHA256, bytes=#item.after, editorMatch=true})
    end
end)
HS.HttpEnabled = previousHttp
if not ok then
    error("Scoped script application stopped; completed writes=" .. HS:JSONEncode(receipts) .. "; " .. tostring(err))
end
return HS:JSONEncode({ok=true, scripts=receipts, httpRestored=HS.HttpEnabled == previousHttp})
