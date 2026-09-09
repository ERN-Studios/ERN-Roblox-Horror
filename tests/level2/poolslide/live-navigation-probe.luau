local H=game:GetService("HttpService")
local S=game.ServerScriptService["Level 2 Systems"]
local m=require(S["Level 2 Round Adapter"]).GetManifest()
local N=require(S["Level 2 Pool Foam Navigator"])
local outcomes={}
local cases={{1,2,false},{30,31,false},{38,41,true},{1,1,false,Vector3.new(0,0,40)},{30,30,false,Vector3.new(-50,0,0)},{38,38,true,Vector3.new(0,0,50)}}
local finished=0
for caseIndex,pair in ipairs(cases) do task.spawn(function()
 local model=game.ServerStorage.Level2Assets["Level 2 Pool Slide Template"]:Clone()
 model.Name="Navigation Measurement "..caseIndex
 for _,p in model:GetDescendants() do if p:IsA("BasePart") then p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false end end
 model.Parent=workspace
 local nav=N.new(model,m,{StableRoutes=true,PathRequestTimeout=8,AgentRadius=model:GetAttribute("AgentRadius"),AgentHeight=16,WaypointArrivalDistance=2,RepathDistance=6,RepathInterval=.65,MaxTravelStep=.9,FloorProbeAbove=18,SteerAngles={20,35,50}},{ObstacleExclusions={m.BuoyantProps}})
 local a=m.World:FindFirstChild("Level 2 Navigation Node "..pair[1],true)
 local b=m.World:FindFirstChild("Level 2 Navigation Node "..pair[2],true)
 if pair[4] then b={Position=a.Position+pair[4]} end
 local ok=nav:WarpTo(a.Position,b.Position-a.Position,true)
 if not ok then for _,offset in {Vector3.new(12,0,0),Vector3.new(-12,0,0),Vector3.new(0,0,12),Vector3.new(0,0,-12),Vector3.new(20,0,20),Vector3.new(-20,0,-20)} do nav.HasGrounded=false;if nav:WarpTo(a.Position+offset,b.Position-a.Position,true) then ok=true;break end end end
 local result={case=caseIndex,from=pair[1],to=pair[2],delayed=pair[3],started=ok,arrived=false,travel=0,backwards=0,reversals=0,requests=0,samples={},maxFrameTravel=0}
 if pair[3] then local centre=nav._centreRoute;nav._centreRoute=function(self,...) task.wait(.25);return centre(self,...) end end
 if ok then
 local started=os.clock();local previous=nav:GetPosition();local previousDirection;local lastSample=0;local arrivedAt;local firstId=nav.RequestId
 while os.clock()-started<24 do
 local dt=game:GetService("RunService").Heartbeat:Wait()
 nav:SetGoal(b.Position)
 local arrived=nav:Step(math.min(dt,.1),24)
 local pos=nav:GetPosition();local delta=Vector3.new(pos.X-previous.X,0,pos.Z-previous.Z)
 local toGoal=Vector3.new(b.Position.X-previous.X,0,b.Position.Z-previous.Z)
 result.travel+=delta.Magnitude;result.maxFrameTravel=math.max(result.maxFrameTravel,delta.Magnitude)
 if delta.Magnitude>.02 then if previousDirection and previousDirection:Dot(delta.Unit)<-.4 then result.reversals+=1 end;previousDirection=delta.Unit
 if toGoal.Magnitude>.1 then result.backwards+=math.max(0,-delta:Dot(toGoal.Unit)) end end
 if arrived then result.arrived=true;arrivedAt=arrivedAt or os.clock() end
 if os.clock()-lastSample>=.5 then lastSample=os.clock();local snap=nav:GetDebugSnapshot();table.insert(result.samples,{t=os.clock()-started,x=pos.X,z=pos.Z,request=nav.RequestId,index=nav.WaypointIndex,count=#nav.Waypoints,status=nav.Status,computing=nav.Computing,goalDistance=toGoal.Magnitude}) end
 previous=pos
 if arrivedAt and os.clock()-arrivedAt>3 then break end
 end
 result.requests=nav.RequestId-firstId;result.finalDistance=(Vector3.new(nav.FootPosition.X,0,nav.FootPosition.Z)-Vector3.new(b.Position.X,0,b.Position.Z)).Magnitude
 result.waiting=nav:GetDebugSnapshot().WaitingForClearance; result.finalStatus=nav.Status;result.lastCentring=nav.LastCentring;result.error=nav.LastFailure
 end
 nav:Destroy();model:Destroy();outcomes[caseIndex]=result;finished+=1
 if finished==#cases then script:SetAttribute("Result",H:JSONEncode(outcomes));script:SetAttribute("Complete",true) end
end) end
