local HS=game:GetService("HttpService")
local model=assert(workspace:FindFirstChild("LobbyReimaginedPreview"),"R3 missing")
local center=assert(model:GetAttribute("PreviewCenter"),"center missing")
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={model};params.RespectCanCollide=true
local rows,failures={},{}
local rayCount=0
for _,spec in ipairs({{1,-1,-80},{2,1,-80},{3,-1,0},{4,1,0},{5,-1,80},{6,1,80}}) do
 local level,side,row=table.unpack(spec) local floors,minRoof,maxFloor,minFloor=0,math.huge,-math.huge,math.huge
 for _,lane in ipairs({-3,0,3}) do for step=0,114 do
  local point=center+Vector3.new(side*(8+step*.5),6,row+lane)
  local floor=workspace:Raycast(point,Vector3.new(0,-10,0),params);rayCount+=1
  if not floor then failures[#failures+1]={level=level,kind="floor",at=tostring(point)}
  else
   floors+=1;maxFloor=math.max(maxFloor,floor.Position.Y-center.Y);minFloor=math.min(minFloor,floor.Position.Y-center.Y)
   local ceiling=workspace:Raycast(floor.Position+Vector3.new(0,.02,0),Vector3.new(0,45,0),params);rayCount+=1
   if not ceiling or ceiling.Distance<6.5 then failures[#failures+1]={level=level,kind="headroom",at=tostring(point),distance=ceiling and ceiling.Distance,path=ceiling and ceiling.Instance:GetFullName()}
   else minRoof=math.min(minRoof,ceiling.Distance) end
  end
 end end
 rows[#rows+1]={level=level,floorSamples=floors,minimumFloorY=minFloor,maximumFloorY=maxFloor,minimumHeadroom=minRoof}
end
local zones={} for _,p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") and p:GetAttribute("R3QueueId") then zones[#zones+1]=p end end
table.sort(zones,function(a,b) return a:GetAttribute("R3QueueId")<b:GetAttribute("R3QueueId") end)
local cancelRows,padRows={},{}
local minQueueMargin=math.huge
for _,zone in ipairs(zones) do
 local bay=zone.Parent local floor=bay:FindFirstChild("ChamberFloor")
 local exit=(zone.CFrame*CFrame.new(0,3,-(zone.Size.Z*.5+5))).Position
 local inward=Vector3.new(floor.Position.X-zone.Position.X,0,floor.Position.Z-zone.Position.Z).Unit
 local facing=Vector3.new(zone.CFrame.LookVector.X,0,zone.CFrame.LookVector.Z).Unit
 local nearest=math.huge
 for _,other in ipairs(zones) do
  local p=other.CFrame:PointToObjectSpace(exit);local radius=other:GetAttribute("QueueRadius")
  nearest=math.min(nearest,Vector2.new(p.X,p.Z).Magnitude-radius)
 end
 local floorHit=workspace:Raycast(exit,Vector3.new(0,-10,0),params);rayCount+=1
 local overlaps={}
 if floorHit then
  local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances={bay};overlap.RespectCanCollide=true
  for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(exit.X,exit.Y,exit.Z),Vector3.new(3.3,5.5,3.3),overlap)) do
   if part.CanCollide then overlaps[#overlaps+1]=part:GetFullName() end
  end
 end
 local ownerRef=zone:FindFirstChild("QueueRenderOwner")
 local owner=ownerRef and ownerRef.Value
 local diameter=bay:GetAttribute("CircularBayDiameter")
 local wallMargin=diameter*.5-Vector2.new(exit.X-floor.Position.X,exit.Z-floor.Position.Z).Magnitude-1.65
 local passed=nearest>1.65 and wallMargin>0 and floorHit~=nil and #overlaps==0 and facing:Dot(inward)>.999
 minQueueMargin=math.min(minQueueMargin,nearest)
 local record={id=zone:GetAttribute("R3QueueId"),level=zone:GetAttribute("LevelNumber"),actualCancelPoint={exit.X,exit.Y,exit.Z},
  nearestQueueEdgeStuds=nearest,humanoidWallMargin=wallMargin,orientationTowardCenter=facing:Dot(inward),
  floorPresent=floorHit~=nil,solidOverlapPaths=overlaps,passed=passed,renderOwner=owner and owner:GetFullName(),
  detectorNonphysical=not zone.CanCollide and not zone.CanTouch and not zone.CanQuery}
 cancelRows[#cancelRows+1]=record
 if not passed or not record.detectorNonphysical then failures[#failures+1]={kind="cancel/detector",id=record.id,record=record} end
 local samples,maxRise,last=0,0,nil
 for i=0,30 do
  local t=i/30;local p=floor.Position:Lerp(zone.Position,t)+Vector3.new(0,6,0)
  local hit=workspace:Raycast(p,Vector3.new(0,-10,0),params);rayCount+=1
  if not hit then failures[#failures+1]={kind="pad-approach",id=record.id,at=tostring(p)} else
   samples+=1;if last then maxRise=math.max(maxRise,hit.Position.Y-last) end;last=hit.Position.Y
  end
 end
 padRows[#padRows+1]={id=record.id,samples=samples,maximumRise=maxRise}
end
local prompts={}
for _,p in ipairs(model:GetDescendants()) do if p:IsA("ProximityPrompt") then prompts[#prompts+1]={path=p:GetFullName(),enabled=p.Enabled,name=p.Name,level=p.Parent:GetAttribute("R3DeveloperPreviewEntry")} end end
return HS:JSONEncode({schema="r3-live-server-readonly-geometry-v1",placeId=game.PlaceId,universeId=game.GameId,running=game:GetService("RunService"):IsRunning(),
 modelOwned=model:GetAttribute("LobbyReimaginedOwned"),modelReady=model:GetAttribute("Ready"),revision=model:GetAttribute("R3QueueRevision"),registeredQueueCount=model:GetAttribute("RegisteredQueueCount"),
 sourceBlendSha256=model:GetAttribute("BlenderSourceSHA256"),originalLobbyPresent=workspace:FindFirstChild("ServerLobby")~=nil,
 center={center.X,center.Y,center.Z},passed=#failures==0,rayCount=rayCount,approaches=rows,cancellations=cancelRows,padApproaches=padRows,
 minimumCancelQueueMargin=minQueueMargin,zoneCount=#zones,prompts=prompts,failures=failures,
 limitations={"Actual engine ray/overlap queries only; no player move, UI, mode or instance writes.","Level4 prompt absence diagnosed separately; this receipt is geometry only.","Multiplayer/actual teleport not tested by these queries."}})
