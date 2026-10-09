local function validSpectatePair(player, target)
 if target == player or player.Parent ~= Players or target.Parent ~= Players
  or inRound[player] ~= true or inRound[target] ~= true
  or target:GetAttribute("Escaped") == true then return false end
 local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
 return (player:GetAttribute("Escaped") == true or not ownHumanoid or ownHumanoid.Health <= 0)
  and targetHumanoid ~= nil and targetHumanoid.Health > 0
end
-- PERFORMANCE_STREAMING_20261009: a Scriptable spectator camera follows another
-- body. Keep that body's region streamed with one extra focus; never replace the
-- spectator's default own-character focus. The existing 1 s reconciliation owns
-- character/root changes, death and respawn; no per-target connections accumulate.
local spectateFocus = {Records = {}}
function spectateFocus:Clear(player)
 local record = self.Records[player]
 if not record then return true end
 if record.Part and player.Parent == Players then
  local ok, problem = pcall(function() player:RemoveReplicationFocus(record.Part) end)
  if not ok then
   -- Keep ownership and retry next reconciliation. Never add a second focus
   -- while removal of the first has not been confirmed.
   warn("[SpectateStreaming] remove focus: " .. tostring(problem))
   return false
  end
 end
 self.Records[player] = nil
 return true
end
function spectateFocus:Sync(player, target)
 local record = self.Records[player]
 if record and record.Character ~= player.Character then
  self:Clear(player)
  return false -- a respawn ends the previous camera owner
 end
 local character = target.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if root and (not root:IsA("BasePart") or not root:IsDescendantOf(workspace)) then root = nil end
 if record and record.Part == root then return true end
 if not self:Clear(player) then return true end
 record = {Character = player.Character}
 self.Records[player] = record
 if root then
  local ok, problem = pcall(function() player:AddReplicationFocus(root) end)
  if ok then
   record.Part = root
  else
   warn("[SpectateStreaming] add focus: " .. tostring(problem))
  end
 end
 return true
end
local function republishSpectatorCounts()
 local counts = {}
 for spectator, target in pairs(spectateTargets) do
  if validSpectatePair(spectator, target) and spectateFocus:Sync(spectator, target) then
   counts[target] = (counts[target] or 0) + 1
  else
   spectateTargets[spectator] = nil
   spectateFocus:Clear(spectator)
  end
 end
 for spectator in pairs(spectateFocus.Records) do
  if not spectateTargets[spectator] then spectateFocus:Clear(spectator) end
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
 if next(spectateTargets) == nil and next(spectateFocus.Records) == nil then return end
 table.clear(spectateTargets)
 republishSpectatorCounts()
end
-- Clear stale reports even when a client stops reporting after its target dies,
-- leaves, escapes, or the spectator respawns. No names are replicated.
task.spawn(function()
 while task.wait(1) do
  if next(spectateTargets) ~= nil or next(spectateFocus.Records) ~= nil then republishSpectatorCounts() end
 end
end)

-- PlayerRemoving fires before Parent leaves Players: detach owned foci now.
Players.PlayerRemoving:Connect(function(leaving)
 for spectator, target in pairs(spectateTargets) do
  if spectator == leaving or target == leaving then
   spectateTargets[spectator] = nil
   spectateFocus:Clear(spectator)
  end
 end
 spectateFocus:Clear(leaving)
 republishSpectatorCounts()
end)
