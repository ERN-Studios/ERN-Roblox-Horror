-- Deferred MCP Server execute snippet, NOT a normal Script (profiler APIs need plugin security).
-- Run only when no other server profiler owns a capture; do not execute in Edit or publish.
-- Wait <=240s for the actual unpaused giant + living round player; sample <=20s at 1KHz.
local RunService=game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),"Server Play only")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong experience")
local storage=game:GetService("ServerStorage");local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players");local Http=game:GetService("HttpService")
local profiler=game:GetService("ScriptProfilerService")
assert(not storage:FindFirstChild("TEMP_PipeEntityActiveProfile"),"harvest existing capture first")
local folder=Instance.new("Folder");folder.Name="TEMP_PipeEntityActiveProfile";folder.Parent=storage
local began=os.clock();local prefix="Level2_PoolSlide";local stopped,removed,owns,requested=false,false,false,false
local received,finishing,attempted=false,false,false;local dataConnection,destroyConnection;local target,world,captureAt,captureEnded,lastAt,lastActive
local trace={Samples={},ActiveElapsedSeconds=0,NoCheatEscape="NOT_TESTED"};local errors={}
local function attr(name,value) if not removed and folder.Parent then folder:SetAttribute(name,value) end end
local function vec(v) return {v.X,v.Y,v.Z} end
local function living()
 for _,p in ipairs(Players:GetPlayers()) do
  local c=p.Character;local h=c and c:FindFirstChildWhichIsA("Humanoid")
  if p:GetAttribute("InRound")==true and h and h.Health>0 and c:FindFirstChild("HumanoidRootPart") then return true end
 end
 return false
end
local function encounter()
 if workspace:GetAttribute("SelectedLevel")~=2 or workspace:GetAttribute("RoundActive")~=true
  or workspace:GetAttribute("WorldGenerated")~=true or not living() then return nil end
 local w=workspace:FindFirstChild("Level 2 Generated World")
 local r=w and w:FindFirstChild("Level 2 Pool Slide Runtime")
 local m=r and r:FindFirstChild("Level 2 Pool Slide")
 if not(m and m:IsA("Model") and m.PrimaryPart and m:GetAttribute(prefix.."Active")==true and m:GetAttribute(prefix.."Phase")=="ENRAGED") then return nil end
 local generation=w:GetAttribute("Level2_Generation")
 if type(generation)~="number" or generation<=0 or m:GetAttribute("Level2_Generation")~=generation then return nil end
 return m,w
end
local function snapshot()
 local row={T=os.clock()-began,Controller={},Players={},RoundActive=workspace:GetAttribute("RoundActive"),
  Paused=workspace:GetAttribute("EntityPaused")==true,Pumps=workspace:GetAttribute("Level2Pumps")}
 local state=RS:FindFirstChild("Level 2 State")
 if state then for k,v in pairs(state:GetAttributes()) do if k:sub(1,#prefix)==prefix then row.Controller[k]=v end end end
 if target and target.Parent then row.Model={Path=target:GetFullName(),Position=vec(target:GetPivot().Position),
  Generation=target:GetAttribute("Level2_Generation"),Active=target:GetAttribute(prefix.."Active")} end
 for _,p in ipairs(Players:GetPlayers()) do
  local c=p.Character;local h=c and c:FindFirstChildWhichIsA("Humanoid");local root=c and c:FindFirstChild("HumanoidRootPart")
  table.insert(row.Players,{UserId=p.UserId,InRound=p:GetAttribute("InRound"),Health=h and h.Health,
   Position=root and vec(root.Position),Chased=p:GetAttribute("Level2_PoolSlideChased")})
 end
 return row
end
local function chunks(kind,json)
 local count=0
 for i=1,#json,40000 do count+=1;attr(kind..string.format("%03d",count),json:sub(i,i+39999)) end
 attr(kind.."Chunks",count);attr(kind.."Bytes",#json)
end
local function stopAndRequest()
 if not attempted then return end
 for _=1,2 do -- Synchronous bounded retry also works inside Destroying.
  if not owns then break end
  local ok,err=pcall(profiler.ServerStop,profiler)
  if ok then owns=false;captureEnded=os.clock() else table.insert(errors,"ServerStop: "..tostring(err)) end
 end
 if not requested then
  requested=true -- OnNewData may arrive during ServerRequestData.
  local ok,err=pcall(profiler.ServerRequestData,profiler)
  if not ok then table.insert(errors,"ServerRequestData: "..tostring(err)) end
 end
 attr("CleanupFailure",owns);attr("NeedsManualProfilerStop",owns)
end
dataConnection=profiler.OnNewData:Connect(function(player,json)
 if removed or stopped or not requested or received or player~=nil then return end
 if type(json)~="string" or #json==0 then table.insert(errors,"Empty/non-string server profile");return end
 local ok,err=pcall(chunks,"Data",json)
 if ok then received=true else table.insert(errors,"Profile storage: "..tostring(err)) end
end)
destroyConnection=folder.Destroying:Connect(function()
 removed=true;stopAndRequest()
 if dataConnection then dataConnection:Disconnect() end
 if destroyConnection then destroyConnection:Disconnect() end
end)
local function finish(reason)
 if stopped or finishing then return end;finishing=true
 local finalOK,finalState=pcall(snapshot)
 if finalOK then trace.CaptureFinalState=finalState else table.insert(errors,"Final snapshot: "..tostring(finalState)) end
 stopAndRequest()
 if removed then stopped=true;return end
 if owns or requested then
  local untilAt=os.clock()+10
  while not received and not removed and os.clock()<untilAt do task.wait(.1) end
 end
 if stopped then return end;stopped=true
 if dataConnection then dataConnection:Disconnect() end
 if destroyConnection and not owns then destroyConnection:Disconnect() end
 trace.StopReason=reason;trace.ElapsedSeconds=os.clock()-began
 trace.CaptureElapsedSeconds=captureAt and (captureEnded or os.clock())-captureAt or 0
 trace.CaptureWindowComplete=reason=="CAPTURE_WINDOW_COMPLETE" and trace.CaptureElapsedSeconds>=20
 trace.Partial=not trace.CaptureWindowComplete or trace.SawPaused==true
 trace.NoDataFailure=not received;trace.Errors=errors;trace.CleanupFailure=owns
 local ok,err=pcall(function() trace.FinalState=snapshot();chunks("Trace",Http:JSONEncode(trace)) end)
 if not ok then attr("SerializationError",tostring(err)) end
 attr("ActiveElapsedSeconds",trace.ActiveElapsedSeconds);attr("ElapsedSeconds",trace.ElapsedSeconds)
 attr("NoDataFailure",not received);attr("Failed",not received or #errors>0 or not ok or owns)
 attr("CaptureWindowComplete",trace.CaptureWindowComplete);attr("Partial",trace.Partial)
 attr("StopReason",reason);attr("Complete",true)
end
attr("Complete",false);attr("Started",false);attr("FrequencyHz",1000);attr("Status","WAITING_FOR_ACTIVE_ENTITY")
task.defer(function()
 local reason="CAPTURE_WINDOW_COMPLETE"
 local ok,err=xpcall(function()
  local untilAt=began+240
  repeat
   if removed or stopped then return end
   target,world=encounter()
   if target and workspace:GetAttribute("EntityPaused")~=true then break end
   target,world=nil,nil;task.wait(.25)
  until os.clock()>=untilAt
  if not target then reason="ACTIVE_ENTITY_WAIT_TIMEOUT";return end
  if removed or stopped then return end
  attempted,owns=true,true;profiler:ServerStart(1000);captureAt=os.clock();lastAt=captureAt;lastActive=true
  attr("Started",true);attr("WaitSeconds",captureAt-began);attr("Status","CAPTURING")
  trace.InitialState=snapshot();trace.Generation=target:GetAttribute("Level2_Generation")
  while os.clock()-captureAt<20 and not removed and not stopped do
   local m,w=encounter();local now=os.clock()
   local active=m==target and w==world and workspace:GetAttribute("EntityPaused")~=true
   if workspace:GetAttribute("EntityPaused")==true then trace.SawPaused=true end
   -- Endpoint-sampled active duration, not exact scheduler/CPU attribution.
   if lastActive and active then trace.ActiveElapsedSeconds+=now-lastAt end
   lastAt,lastActive=now,active
   table.insert(trace.Samples,snapshot())
   if m~=target or w~=world then reason="ENTITY_ROUND_OR_LIVING_PLAYERS_GONE";break end
   task.wait(.5)
  end
 end,debug.traceback)
 if not ok then table.insert(errors,tostring(err));reason="PROBE_ERROR" end
 finish(reason)
end)
task.delay(275,function()
 if not stopped and not removed then finish("PROBE_WATCHDOG")
 elseif owns then stopAndRequest();if not owns and destroyConnection then destroyConnection:Disconnect() end end
end)
return {Armed=true,WaitSeconds=240,CaptureSeconds=20,DataWaitSeconds=10,FrequencyHz=1000,Output=folder:GetFullName()}
