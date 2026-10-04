local P=game.Players
local a,b=P:FindFirstChild("Player1"),P:FindFirstChild("Player2")
local R=game.ReplicatedStorage.CodexMultiplayerProbe
local z=workspace.ServerLobby.LevelQueueRooms.Level1QueueRoom.LaunchZone1
local function walk(p,pos) R:InvokeClient(p,{op="walk",position={pos.X,pos.Y,pos.Z}}) end
local function radius(p) local d=p.Character:GetPivot().Position-z.Position return Vector2.new(d.X,d.Z).Magnitude end
R:InvokeClient(a,{op="controls",enabled=false})
R:InvokeClient(b,{op="controls",enabled=false})
a.Character:PivotTo(z.CFrame*CFrame.new(0,3,0))
b.Character:PivotTo(z.CFrame*CFrame.new(0,3,12))
task.wait(1)
R:InvokeClient(a,{op="remote",name="ConfigureQueue",args={1,1,"public"}})
task.wait(.7)
local wall=workspace:FindFirstChild("Station1FullBarrier",true)
assert(wall,"full party has no barrier")
local membersGroup=a.Character.HumanoidRootPart.CollisionGroup
local outsiderGroup=b.Character.HumanoidRootPart.CollisionGroup
walk(b,z.Position)
local minRadius=math.huge
for i=1,30 do task.wait(.1) minRadius=math.min(minRadius,radius(b)) end
local blocked=radius(b)
assert(minRadius>7.41,"outsider crossed into full party")
walk(a,z.Position+Vector3.new(0,0,-12))
task.wait(1.3)
local memberLeft=radius(a)
local wallRemoved=not workspace:FindFirstChild("Station1FullBarrier",true)
assert(memberLeft>7.41,"member cannot leave")
assert(wallRemoved,"barrier did not clear after host left")
local restored=a.Character.HumanoidRootPart.CollisionGroup
walk(b,z.Position)
task.wait(1.2)
local reopened=radius(b)
assert(reopened<7.41,"capacity reopening did not admit outsider")
b.Character:PivotTo(z.CFrame*CFrame.new(0,3,12))
return {membersGroup=membersGroup,outsiderGroup=outsiderGroup,minimumOutsiderRadius=minRadius,
 blockedRadius=blocked,memberLeftRadius=memberLeft,barrierRemoved=wallRemoved,restoredGroup=restored,reopenedRadius=reopened}
