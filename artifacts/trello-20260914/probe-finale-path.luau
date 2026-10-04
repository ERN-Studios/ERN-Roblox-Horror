local S=game.ServerScriptService["Level 3 Systems"]
local A=require(S["Level 3 Round Adapter"])
local m=A.GetManifest()
local path=game:GetService("PathfindingService"):CreatePath({AgentRadius=4,AgentHeight=10,AgentCanJump=false,WaypointSpacing=12})
local start=m.MazeStart.Position+m.MazeStart.CFrame.LookVector*12
local goal=m.FinalHall.StartPoint+m.FinalHall.Forward*50+Vector3.new(0,3,0)
path:ComputeAsync(start,goal)
local points={}
local length=0
local prev=start
for _,p in ipairs(path:GetWaypoints()) do length+=(p.Position-prev).Magnitude prev=p.Position table.insert(points,{p.Position.X,p.Position.Y,p.Position.Z}) end
return {status=path.Status.Name,length=length,points=points}
