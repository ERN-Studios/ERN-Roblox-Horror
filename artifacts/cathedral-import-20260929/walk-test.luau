assert(game.PlaceId==121672571539226)
local player=game:GetService('Players'):GetPlayers()[1]
assert(player and player.Character,'Player not ready')
local character=player.Character
local humanoid=character:FindFirstChildOfClass('Humanoid')
local root=character:FindFirstChild('HumanoidRootPart')
assert(humanoid and root and not root.Anchored and humanoid.Health>0)
assert(not _G.VesperWalkQA or _G.VesperWalkQA.done,'QA already running')
local route={{0,75},{0,68},{0,64},{0,60},{0,55},{0,35},{0,15},{0,-5},{0,-25},{0,-39},{0,-46},{0,-39},{24,-39},{24,-15},{24,10},{24,35},{24,45},{0,45},{-24,45},{-24,20},{-24,-5},{-24,-30},{-24,-39},{0,-39}}
local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={workspace['Vesper Cathedral']._VesperSetup,workspace.SpawnLocation};rp.RespectCanCollide=true
local initialHit=workspace:Raycast(root.Position,Vector3.new(0,-10,0),rp)
assert(initialHit,'Avatar not over map')
local offset=root.Position.Y-initialHit.Position.Y
assert(offset>1 and offset<7,'Unexpected avatar height')
local out={done=false,passed=true,route={},start={root.Position.X,root.Position.Y,root.Position.Z},initialHealth=humanoid.Health,rootFloorOffset=offset,gravity=workspace.Gravity,walkSpeed=humanoid.WalkSpeed,jumps=0,teleports=0}
_G.VesperWalkQA=out
root:SetNetworkOwner(nil)
task.spawn(function()
 local started=os.clock()
 for i,p in route do
  if os.clock()-started>100 or not character.Parent or humanoid.Health<=0 then out.passed=false;out.error='Overall timeout or character lost';break end
  local hit=workspace:Raycast(Vector3.new(p[1],16,p[2]),Vector3.new(0,-30,0),rp)
  if not hit then out.passed=false;out.error='Missing floor at waypoint '..i;break end
  local target=Vector3.new(p[1],hit.Position.Y+offset,p[2])
  local moveEvent
  local connection=humanoid.MoveToFinished:Connect(function(ok) moveEvent=ok end)
  local legStart=os.clock()
  humanoid:MoveTo(target)
  local reached=false
  repeat
   task.wait(0.1)
   local delta=root.Position-target
   reached=Vector2.new(delta.X,delta.Z).Magnitude<=2 and math.abs(delta.Y)<0.9 and humanoid.FloorMaterial~=Enum.Material.Air
  until reached or os.clock()-legStart>=5 or humanoid.Health<=0
  connection:Disconnect()
  local delta=root.Position-target
  table.insert(out.route,{index=i,target={target.X,target.Y,target.Z},actual={root.Position.X,root.Position.Y,root.Position.Z},reached=reached,moveToFinished=moveEvent~=nil and tostring(moveEvent) or 'pending',seconds=os.clock()-legStart,horizontalError=Vector2.new(delta.X,delta.Z).Magnitude,floor=tostring(humanoid.FloorMaterial),health=humanoid.Health,state=tostring(humanoid:GetState())})
  if not reached then out.passed=false;out.error='Failed waypoint '..i;break end
 end
 humanoid:MoveTo(root.Position)
 root:SetNetworkOwnershipAuto()
 out.seconds=os.clock()-started
 out.finalHealth=humanoid.Health
 out.done=true
end)
return game:GetService('HttpService'):JSONEncode({started=true,waypoints=#route,rootFloorOffset=offset,start=out.start})
