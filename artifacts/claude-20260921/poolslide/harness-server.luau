-- Pool Slide chase-latency harness (Studio play session, Server datamodel).
-- Pin the map BEFORE the round:  workspace:SetAttribute("Level2Seed", 1182081016)
-- Start a Level 2 round, run this, pull two pumps (client:
--   LocalPlayer.PlayerScripts.DevCheatCommand:Fire("level2PumpPair", true)),
-- then  workspace:SetAttribute("ClaudeMoverGo", true).
-- The mover walks the only player round four hall nodes at 16 studs/s (22 with the
-- giant inside 40 studs) so before/after runs see the same stimulus. Rows land in
-- ServerStorage.ClaudeProbe (JSON); the request trace is the state-folder attribute
-- Level2_PoolSlideTrace. Nothing here is saved with the place.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local p = Players:GetPlayers()[1]
local st, root
for i = 1, 20 do
  st = game.ReplicatedStorage:FindFirstChild("Level 2 State")
  root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
  if workspace:GetAttribute("RoundActive") and st and st:GetAttribute("Level2_PoolSlideNavigationContextReady") and root and not root.Anchored and root.Position.Z > -800 and root.Position.Y < 100 then break end
  task.wait(1)
end
if not (st and root and root.Position.Z > -800) then return "round not ready" end
workspace:SetAttribute("Level2_PoolSlideDiagnostics", true)
local hum = p.Character:FindFirstChildOfClass("Humanoid")
hum.MaxHealth = 1e9; hum.Health = 1e9
local old = game.ServerStorage:FindFirstChild("ClaudeProbe"); if old then old:Destroy() end
local sv = Instance.new("StringValue"); sv.Name = "ClaudeProbe"; sv.Parent = game.ServerStorage
workspace:SetAttribute("ClaudeProbeRun", true)
workspace:SetAttribute("ClaudeMoverGo", false)
workspace:SetAttribute("ClaudeMoverLeg", 0)
workspace:SetAttribute("ClaudeMoverSpeed", 16)
local function entityPos()
  local m = workspace:FindFirstChild("Level 2 Pool Slide", true)
  return m and m:IsA("Model") and m:GetPivot().Position or nil
end
task.spawn(function()
  local rows, lastFlush = {}, 0
  while workspace:GetAttribute("ClaudeProbeRun") == true and sv.Parent do
    local rt = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    local ep = entityPos()
    local function a(n) return st:GetAttribute("Level2_PoolSlide" .. n) end
    local r = math.round
    table.insert(rows, {r(workspace:GetServerTimeNow()*10)/10, rt and r(rt.Position.X) or 0, rt and r(rt.Position.Z) or 0,
      ep and r(ep.X) or 0, ep and r(ep.Z) or 0, a("State"), r((a("Speed") or 0)*10)/10, a("Computing") and 1 or 0, a("Waypoints") or 0,
      a("GoalAge") or -1, a("GoalError") or -1, a("TargetDistance") or 0, a("PathStatus"), a("PathFailure") or "", workspace:GetAttribute("Level2Pumps") or 0,
      workspace:GetAttribute("ClaudeMoverLeg") or 0})
    if #rows - lastFlush >= 10 then lastFlush = #rows; sv.Value = HttpService:JSONEncode(rows) end
    task.wait(.2)
  end
  sv.Value = HttpService:JSONEncode(rows)
end)
local loop = {Vector3.new(-573,3,-370), Vector3.new(-569,3,-159), Vector3.new(-356,3,-133), Vector3.new(-330,3,-340)}
task.spawn(function()
  local leg = 0
  while workspace:GetAttribute("ClaudeProbeRun") == true do
    if workspace:GetAttribute("ClaudeMoverGo") ~= true then task.wait(.2) continue end
    local rt = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if not rt then break end
    leg += 1
    workspace:SetAttribute("ClaudeMoverLeg", leg)
    local target = loop[(leg - 1) % #loop + 1]
    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6})
    local ok = pcall(function() path:ComputeAsync(rt.Position, target) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then workspace:SetAttribute("ClaudeMoverFail", (workspace:GetAttribute("ClaudeMoverFail") or 0) + 1) task.wait(.5) continue end
    for _, wp in ipairs(path:GetWaypoints()) do
      local goal = wp.Position + Vector3.new(0, 3, 0)
      while workspace:GetAttribute("ClaudeProbeRun") == true and workspace:GetAttribute("ClaudeMoverGo") == true do
        local dt = RunService.Heartbeat:Wait()
        rt = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not rt then break end
        local ep = entityPos()
        local speed = workspace:GetAttribute("ClaudeMoverSpeed") or 16
        if ep and (Vector3.new(ep.X,0,ep.Z) - Vector3.new(rt.Position.X,0,rt.Position.Z)).Magnitude < 40 then speed = math.max(speed, 22) end
        local delta = goal - rt.Position
        local flat = Vector3.new(delta.X, 0, delta.Z)
        if flat.Magnitude < 1 then break end
        local np = rt.Position + flat.Unit * math.min(flat.Magnitude, speed * dt)
        rt.CFrame = CFrame.lookAt(Vector3.new(np.X, goal.Y, np.Z), Vector3.new(np.X, goal.Y, np.Z) + flat.Unit)
        rt.AssemblyLinearVelocity = Vector3.zero
      end
    end
  end
end)
return "harness installed seed=" .. tostring(st:GetAttribute("Level2_Seed")) .. " pos=" .. tostring(root.Position)
