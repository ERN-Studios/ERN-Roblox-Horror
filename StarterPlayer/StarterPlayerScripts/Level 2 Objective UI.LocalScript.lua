-- Level 2 objective receiver. All Level 2 rounds show the same simple exit goal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local RoundHud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local player = Players.LocalPlayer

local function objectiveSubject()
    if player:GetAttribute("Spectating") == true then
        local id = player:GetAttribute("SpectateTargetUserId")
        local watched = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
        if not watched or watched:GetAttribute("InRound") ~= true
            or watched:GetAttribute("Escaped") == true then return nil end
        local hum = watched.Character and watched.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health > 0 and watched or nil
    end
    if player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true then return nil end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0 and player or nil
end

-- B4_LEVEL2_STATE_BEGIN: the exit goal needs no route, counter or compass.
local function exitObjective()
    return {Level = 2, Title = "Find the exit", Lines = {}, Done = false}
end
-- B4_LEVEL2_STATE_END

local function refresh()
    if workspace:GetAttribute("SelectedLevel") ~= 2
        or player:GetAttribute("Level2NewMapPreview") == true then return end
    local subject = objectiveSubject()
    if not subject or subject:GetAttribute("Level2NewMapPreview") == true then return end
    RoundHud.SetObjective(exitObjective())
end

for _, attribute in ipairs({"SelectedLevel", "RoundActive"}) do
    workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end
for _, attribute in ipairs({"InRound", "Escaped", "Spectating", "SpectateTargetUserId",
    "Level2NewMapPreview", "ZyntraDispatchClientActive"}) do
    player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
UIDevice.Changed:Connect(refresh)
UIDevice.OnScreenOwningModalChanged(refresh)
-- Retain the round-entry retry when the character or shared HUD is not ready yet.
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed < .22 then return end
    elapsed = 0
    if workspace:GetAttribute("SelectedLevel") == 2 then refresh() end
end)
refresh()
