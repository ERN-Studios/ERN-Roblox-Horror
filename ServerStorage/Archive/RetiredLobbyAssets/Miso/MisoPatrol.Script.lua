-- MisoPatrol
-- Plays the Meshy walking cycle and guides Miso around the safe lobby floor.

local RunService = game:GetService("RunService")
local rig = script.Parent
local floorPivotY = rig:GetAttribute("PatrolPivotY") or rig:GetPivot().Position.Y
local orientationFix = CFrame.Angles(0, math.rad(-90), 0)
local speed = 4.2
local waypoints = {
    Vector3.new(8, floorPivotY, -788),
    Vector3.new(16, floorPivotY, -783),
    Vector3.new(17, floorPivotY, -775),
    Vector3.new(8, floorPivotY, -770),
    Vector3.new(-3, floorPivotY, -774),
    Vector3.new(-10, floorPivotY, -783),
    Vector3.new(-5, floorPivotY, -791),
}

local controller = rig:FindFirstChildOfClass("AnimationController")
if not controller then
    controller = Instance.new("AnimationController")
    controller.Name = "AnimationController"
    controller.Parent = rig
end
local animator = controller:FindFirstChildOfClass("Animator")
if not animator then
    animator = Instance.new("Animator")
    animator.Parent = controller
end
local animation = rig:WaitForChild("WalkAnimation")
local ok, track = pcall(function()
    return animator:LoadAnimation(animation)
end)
if ok and track then
    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    track:Play(0.18, 1, 1)
else
    warn("[MisoPatrol] Could not load the walking animation", track)
end

local position = waypoints[1]
local waypointIndex = 2
local facing = (waypoints[2] - waypoints[1]).Unit
rig:PivotTo(CFrame.lookAt(position, position + facing, Vector3.yAxis) * orientationFix)

while rig.Parent do
    local dt = RunService.Heartbeat:Wait()
    local target = waypoints[waypointIndex]
    local offset = target - position
    local distance = offset.Magnitude
    if distance < 0.12 then
        position = target
        waypointIndex = waypointIndex % #waypoints + 1
    else
        local direction = offset.Unit
        local turnAlpha = math.clamp(dt * 4.5, 0, 1)
        local blended = facing:Lerp(direction, turnAlpha)
        if blended.Magnitude > 0.001 then
            facing = blended.Unit
        end
        position += direction * math.min(speed * dt, distance)
        rig:PivotTo(CFrame.lookAt(position, position + facing, Vector3.yAxis) * orientationFix)
    end
end
