-- Fixed-camera tour for before/after image diffs (Studio play session, Client datamodel).
-- Level 2, seed 1182081016, entities paused (workspace.EntityPaused = true on the server).
-- Timetable: 3 s lead-in, then 6 s per shot: teleport, 3.5 s to stream, camera set, held 2.5 s.
-- The PowerShell side captures the Studio window at t = 3 + 6*i + 5 s.
local p = game:GetService("Players").LocalPlayer
local cam = workspace.CurrentCamera
local SHOTS = {
  {Vector3.new(-571, 7, -409), Vector3.new(1, 0, 0)},
  {Vector3.new(-571, 7, -409), Vector3.new(-1, 0, 0)},
  {Vector3.new(-571, 7, -409), Vector3.new(0, 0, 1)},
  {Vector3.new(-571, 7, -409), Vector3.new(0, 0, -1)},
  {Vector3.new(-571, 7, -409), Vector3.new(0.3, 1, 0.2)},
  {Vector3.new(-573, 7, -370), Vector3.new(1, 0.15, 0.4)},
  {Vector3.new(-573, 7, -370), Vector3.new(0.2, 0.9, 1)},
  {Vector3.new(-571, 7, -265), Vector3.new(0, 0.1, 1)},
  {Vector3.new(-571, 7, -265), Vector3.new(0.4, 1, 0.3)},
  {Vector3.new(-330, 7, -340), Vector3.new(-1, 0.1, 0.3)},
  {Vector3.new(-330, 7, -340), Vector3.new(0.3, 1, -0.2)},
  {Vector3.new(-356, 7, -133), Vector3.new(-1, 0.2, -0.5)},
}
workspace:SetAttribute("ClaudeShots", 0)
task.spawn(function()
  task.wait(3)
  cam.CameraType = Enum.CameraType.Scriptable
  for i, shot in ipairs(SHOTS) do
    local ch = p.Character
    if ch and ch:FindFirstChild("HumanoidRootPart") then
      ch:PivotTo(CFrame.new(shot[1] + Vector3.new(0, -2, 0)))
      ch.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    end
    cam.CFrame = CFrame.lookAt(shot[1], shot[1] + shot[2])
    task.wait(3.5)
    cam.CFrame = CFrame.lookAt(shot[1], shot[1] + shot[2])
    workspace:SetAttribute("ClaudeShots", i)
    task.wait(2.5)
  end
  cam.CameraType = Enum.CameraType.Custom
  workspace:SetAttribute("ClaudeShots", -1)
end)
return "tour started: " .. #SHOTS .. " shots"
