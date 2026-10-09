local function validSpectatePair(player, target)
 if target == player or player.Parent ~= Players or target.Parent ~= Players
  or inRound[player] ~= true or inRound[target] ~= true
  or target:GetAttribute("Escaped") == true then return false end
 local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
 return (player:GetAttribute("Escaped") == true or not ownHumanoid or ownHumanoid.Health <= 0)
  and targetHumanoid ~= nil and targetHumanoid.Health > 0
end
local function republishSpectatorCounts()
 local counts = {}
 for spectator, target in pairs(spectateTargets) do
  if validSpectatePair(spectator, target) then
   counts[target] = (counts[target] or 0) + 1
  else
   spectateTargets[spectator] = nil
  end
 end
 for _, subject in ipairs(Players:GetPlayers()) do
  if subject:GetAttribute("SpectatorCount") ~= counts[subject] then
   subject:SetAttribute("SpectatorCount", counts[subject])
  end
 end
end
local function setSpectateTarget(player, targetUserId)
 local target = nil
 if type(targetUserId) == "number" and targetUserId == targetUserId
  and math.abs(targetUserId) < 2^53 and targetUserId % 1 == 0 then
  -- Studio's actual multiplayer clients have negative UserIds. Resolve the
  -- current roster instead of assuming positive production account ids.
  target = Players:GetPlayerByUserId(targetUserId)
 end
 if target and not validSpectatePair(player, target) then target = nil end
 if spectateTargets[player] == target then return end
 spectateTargets[player] = target
 republishSpectatorCounts()
end
local function clearSpectatorCounts()
 if next(spectateTargets) == nil then return end
 table.clear(spectateTargets)
 republishSpectatorCounts()
end
-- Clear stale reports even when a client stops reporting after its target dies,
-- leaves, escapes, or the spectator respawns. No names are replicated.
task.spawn(function()
 while task.wait(1) do
  if next(spectateTargets) ~= nil then republishSpectatorCounts() end
 end
end)
