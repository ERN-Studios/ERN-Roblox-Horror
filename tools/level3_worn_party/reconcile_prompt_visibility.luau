-- Correct the arcade/claw/breaker LOS gate found by an actual Client prompt test.
-- The frozen first-install server remains on 127.0.0.1:8881 for the exact prior source.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SNAPSHOT = "eeaa5d1eb197802bb65b31c9a7aaf5da58bbec8da77e121d611245152fd271d4"
local OLD_SHA = "8aad8f91ad1f823b2b1b1117f5e3e9e74ad9c975cb14d757ceb23acb71dc62d8"
local NEW_SHA = "766976d349759f0320e2e80ed355b9309b818d42d2a0dce34ecb15054715849d"
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong experience")
assert(not RS:IsRunning(), "Requires Studio Edit mode")
local systems = assert(SSS:FindFirstChild("Level 3 Systems"), "Missing Level 3 Systems")
local target = assert(systems:FindFirstChild("Level 3 Worn Party Room Dressing"), "Missing dressing module")
assert(target:IsA("ModuleScript") and target.Parent == systems, "Wrong dressing instance")
assert(target:GetAttribute("Level3WornPartyInstallSnapshot") == SNAPSHOT
    and target:GetAttribute("Level3WornPartySourceSHA256") == OLD_SHA,
    "Dressing module changed since guarded install")
local wasHttp = HS.HttpEnabled
local fetched, baseline = pcall(function()
    HS.HttpEnabled = true
    return HS:GetAsync("http://127.0.0.1:8881/source/5", true)
end)
HS.HttpEnabled = wasHttp
assert(fetched and #baseline == 19273, "Could not fetch exact prior dressing source")
local needle = "\t\tprompt.RequiresLineOfSight=true"
local replacement = table.concat({
    "\t\t-- The authored cabinet and its invisible collision proxy sit between the",
    "\t\t-- player and this internal anchor; range and round checks still gate use.",
    "\t\tprompt.RequiresLineOfSight=false",
}, "\n")
local at = assert(baseline:find(needle, 1, true), "Prompt statement missing")
assert(baseline:find(needle, at + #needle, true) == nil, "Prompt statement is not unique")
local candidate = baseline:sub(1, at-1) .. replacement .. baseline:sub(at+#needle)
assert(#candidate == 19427, "Unexpected candidate byte length")
local function editor()
    local ok, value = pcall(SES.GetEditorSource, SES, target)
    assert(ok and type(value) == "string", "Cannot read dressing editor source")
    return value
end
assert(target.Source == baseline and editor() == baseline, "Studio Source/editor changed")
local drift = false
SES:UpdateSourceAsync(target, function(old)
    if target.Parent ~= systems or target.Source ~= baseline or editor() ~= baseline
        or target:GetAttribute("Level3WornPartySourceSHA256") ~= OLD_SHA or old ~= baseline then
        drift = true
        return old
    end
    return candidate
end)
assert(not drift, "Dressing changed during source update")
local matched = false
for _ = 1, 100 do
    if target.Parent == systems and target.Source == candidate and editor() == candidate then
        matched = true
        break
    end
    task.wait(.05)
end
assert(matched, "Dressing source/editor readback failed")
target:SetAttribute("Level3WornPartySourceSHA256", NEW_SHA)
assert(target.Source == candidate and editor() == candidate, "Dressing changed after readback")
return HS:JSONEncode({ok = true, path = target:GetFullName(), newSha256 = NEW_SHA,
    sourceEditorParity = true, httpRestored = HS.HttpEnabled == wasHttp})
