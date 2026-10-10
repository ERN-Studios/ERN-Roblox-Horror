-- Level 1 objective receiver. PuzzleManager remains the gameplay authority.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local RoundHud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PuzzleStatus")
local leverPhase, leverActive, leverTotal = false, 0, 0
local carriedFuses, boxCurrent, boxGoal = 0, 0, 1
local exitOpen, begun = false, false
-- RELAY_FINDABLE_20261010 (puzzle-client): keep proximity work outside the objective receiver seam.
local nearRelay = false

-- B4_LEVEL1_STATE_BEGIN: count state is data, no longer hidden in old labels.
local function puzzleObjective()
    if exitOpen then
        local target = workspace:GetAttribute("ExitPos")
        return {Level = 1, Title = "GET OUT", Lines = {"Reach the lit exit door."},
            Compass = {State = typeof(target) == "Vector3" and "locked" or "locating", Target = target}, Done = true}
    end
    if leverPhase then
        -- LEVER_PATH_20261010 (puzzle-client): explain the return trip before the cable junction.
        return {Level = 1, Title = "PULL THE LEVERS", Count = leverActive, Goal = leverTotal,
            Tag = "LEVERS", Lines = {"Go back along the cable from the fuse box.", "Where it splits, follow the moving current."},
            Status = {Text = "Levers stay on. No time limit.", Kind = "info"},
            Done = leverTotal > 0 and leverActive >= leverTotal}
    end
    -- LEVER_PATH_20261010 (puzzle-client): teach extraction, insertion and the way back in order.
    local guidance = carriedFuses > 0 and "Follow a colored cable to a fuse box." or "Find a fuse relay under the amber lights."
    local nextStep = carriedFuses > 0 and "Insert the fuse. Then go back the same way." or "Pull the fuse out. Carry it to a fuse box."
    -- A watched player's private carried count is not part of PuzzleStatus's broadcast contract.
    local spectating = player:GetAttribute("Spectating") == true
    if spectating then
        guidance, nextStep = "Find fuses and fill the fuse boxes.", "Follow the colored cables to the fuse boxes."
    end
    return {Level = 1, Title = "RESTORE THE POWER", Count = boxCurrent, Goal = boxGoal,
        Tag = "FUSE BOXES", Lines = {guidance, nextStep},
        Status = carriedFuses == 0 and nearRelay and not spectating
            and {Text = "A fuse relay is close.", Kind = "warning"} or nil,
        Done = boxCurrent >= boxGoal}
end
-- B4_LEVEL1_STATE_END

local function publishObjective()
    if begun and workspace:GetAttribute("SelectedLevel") == 1 then RoundHud.SetObjective(puzzleObjective()) end
end
local function participant()
    if workspace:GetAttribute("SelectedLevel") ~= 1 then return false end
    if player:GetAttribute("InRound") == true then return true end
    if player:GetAttribute("Spectating") ~= true then return false end
    local id = player:GetAttribute("SpectateTargetUserId")
    local watched = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
    local hum = watched and watched.Character and watched.Character:FindFirstChildOfClass("Humanoid")
    return watched ~= nil and watched:GetAttribute("InRound") == true
        and watched:GetAttribute("Escaped") ~= true and hum ~= nil and hum.Health > 0
end
local function showMessage(text)
    RoundHud.Feed({Kind = "LEVEL", Detail = tostring(text or "")})
end
local function teamPrompt(actorName, kind, detail)
    local actor = tostring(actorName or "Someone")
    local text = tostring(detail or "")
    -- Root's server-copy pass supplies sentence-case details; accept old-kit uppercase too.
    if text == string.upper(text) then text = string.lower(text) end
    RoundHud.Feed({Kind = "TEAM", Actor = actor, Detail = text, Key = "level1:" .. tostring(kind)})
end

-- Real receiver seam shared by normal remote and Studio QA.
local function applyPuzzleStatus(ev, a, b, c, d)
    if ev == "begin" then
        leverPhase, leverActive, leverTotal = false, 0, 0
        carriedFuses, boxCurrent, boxGoal = 0, 0, math.max(1, tonumber(b) or 1)
        exitOpen, begun = false, true
        nearRelay = false
    elseif ev == "carry" then
        carriedFuses = math.max(0, tonumber(a) or 0)
    elseif ev == "msg" then
        showMessage(a)
    elseif ev == "team" then
        teamPrompt(a, b, c)
    elseif ev == "boxes" then
        boxGoal = math.max(1, tonumber(b) or boxGoal)
        boxCurrent = math.clamp(tonumber(a) or 0, 0, boxGoal)
    elseif ev == "levers" then
        leverPhase, leverActive, leverTotal = true, 0, math.max(1, tonumber(a) or 1)
    elseif ev == "lever" then
        leverPhase = true
        leverTotal = math.max(1, tonumber(b) or leverTotal)
        leverActive = math.clamp(tonumber(a) or 0, 0, leverTotal)
        -- c/d are preserved protocol slots; latched levers have no HUD countdown.
    elseif ev == "exit" then
        -- EXIT_COMPASS_20261010 (puzzle-client): announce the marker once per puzzle, including spectators.
        if not exitOpen then showMessage("Exit open. Follow the green marker.") end
        exitOpen, leverPhase = true, false
    elseif ev == "escape" then
        -- Another player's escape is not a second objective transition.
        return
    end
    publishObjective()
end
remote.OnClientEvent:Connect(function(ev, a, b, c, d)
    if not participant() then return end
    applyPuzzleStatus(ev, a, b, c, d)
end)

-- RELAY_FINDABLE_20261010 (puzzle-client): streamed relays can hint nearby without a world marker.
do
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 0.5 then return end
        elapsed = 0
        local close = false
        if begun and not leverPhase and not exitOpen and carriedFuses == 0
            and workspace:GetAttribute("SelectedLevel") == 1 and workspace:GetAttribute("RoundActive") == true
            and player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true
            and player:GetAttribute("Spectating") ~= true then
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local hum = character and character:FindFirstChildOfClass("Humanoid")
            local items = workspace:FindFirstChild("PuzzleItems")
            if root and root:IsA("BasePart") and hum and hum.Health > 0 and items then
                for _, model in ipairs(items:GetChildren()) do
                    if model:IsA("Model") and model.Name == "FuseRelay" and model:GetAttribute("ContainsFuse") == true then
                        local body = model:FindFirstChild("RelayBody") or model.PrimaryPart
                        if body and body:IsA("BasePart") and (body.Position - root.Position).Magnitude <= 80 then
                            close = true
                            break
                        end
                    end
                end
            end
        end
        if close ~= nearRelay then
            nearRelay = close
            publishObjective()
        end
    end)
end

local function resetRoundHud()
    leverPhase, leverActive, leverTotal = false, 0, 0
    carriedFuses, boxCurrent, boxGoal = 0, 0, 1
    exitOpen, begun = false, false
    nearRelay = false
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
    if workspace:GetAttribute("RoundActive") ~= true then resetRoundHud() else publishObjective() end
end)
workspace:GetAttributeChangedSignal("ExitPos"):Connect(publishObjective)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(publishObjective)
for _, name in ipairs({"InRound", "Escaped", "Spectating", "SpectateTargetUserId"}) do
    player:GetAttributeChangedSignal(name):Connect(publishObjective)
end
if RunService:IsStudio() then
    local probe = Instance.new("BindableFunction")
    probe.Name = "UIRegressionPuzzleProbe"
    probe.OnInvoke = function(action, a, b, c, d)
        if action == "reset" then resetRoundHud() else applyPuzzleStatus(action, a, b, c, d) end
        return {Level = 1, Begun = begun, Objective = begun and puzzleObjective() or nil}
    end
    probe.Parent = RoundHud.Gui()
end
