-- TEMPORARY normal Play server diagnostic; NEVER publish. Pair with queue-only client.
-- Required Script attrs: TestToken (>=16 chars), MinimumSpawnDistance (explicit studs).
local RunService = game:GetService("RunService")
if not RunService:IsStudio() or game.PlaceId ~= 131311258779917 or game.GameId ~= 10559217407 then return end
if script.Name ~= "TEMP_Pump3NativeServer" then return end
local token, minimum = script:GetAttribute("TestToken"), script:GetAttribute("MinimumSpawnDistance")
assert(type(token)=="string" and #token>=16 and type(minimum)=="number" and minimum>=60, "explicit diagnostic parameters required")
local Players, RS, SS = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
assert(not RS:FindFirstChild("TEMP_Pump3NativeRemote") and not SS:FindFirstChild("TEMP_Pump3NativeResult"), "test artifact collision")
local remote=Instance.new("RemoteEvent"); remote.Name="TEMP_Pump3NativeRemote"; remote:SetAttribute("TestToken",token); remote.Parent=RS
local output=Instance.new("Folder"); output.Name="TEMP_Pump3NativeResult"; output:SetAttribute("TestToken",token); output.Parent=SS
local started, ended, connections = os.clock(), false, {}
local result={Token=token,MinimumSpawnDistance=minimum,Checks={},Events={},Samples={},Memory={},
 Limitations="Diagnostic player placements and existing proximity/LOS-validated DebugActivatePump; not ordinary-input escape, multiplayer replication, listening, CPU attribution, or long-session memory-leak certification."}
local manifest, controller, actor, actualModel, queueReady, worker, watchdog
local function vec(v) return {v.X,v.Y,v.Z} end
local function horizontal(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function check(name,pass,detail) result.Checks[name]={Status=pass and "PASS" or "FAIL",Detail=detail} end
local function event(name,detail) table.insert(result.Events,{T=os.clock()-started,Kind=name,Detail=detail}) end
local function rootOf(p,round)
 local c=p.Character; local h=c and c:FindFirstChildWhichIsA("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
 if h and h.Health>0 and r and (not round or (p:GetAttribute("InRound")==true and p:GetAttribute("Escaped")~=true and p:GetAttribute("Level2_ExitTransition")~=true)) then return r,h,c end
end
local function memory(label)
 local row={Label=label,T=os.clock()-started}; local stats=game:GetService("Stats")
 local ok,total=pcall(stats.GetTotalMemoryUsageMb,stats); if ok then row.TotalMb=total end
 for _,name in ipairs({"LuaHeap","Instances","PhysicsParts","GraphicsMeshParts"}) do
  local got,value=pcall(function() return stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag[name]) end); if got then row[name.."Mb"]=value end
 end
 table.insert(result.Memory,row)
end
local function finish(err)
 if ended then return end; ended=true; result.Error=err; result.Elapsed=os.clock()-started; memory("finish")
 result.Final={Pumps=workspace:GetAttribute("Level2Pumps"),ExitPowered=workspace:GetAttribute("Level2ExitPowered"),RoundActive=workspace:GetAttribute("RoundActive"),WorldGenerated=workspace:GetAttribute("WorldGenerated")}
 for _,c in ipairs(connections) do c:Disconnect() end
 remote:FireAllClients(token,"stop"); remote:Destroy()
 local ok,json=pcall(game:GetService("HttpService").JSONEncode,game:GetService("HttpService"),result)
 if not ok then output:SetAttribute("SerializationError",tostring(json)) else
  for i=1,math.ceil(#json/40000) do local value=Instance.new("StringValue"); value.Name=string.format("Result%03d",i); value.Value=json:sub((i-1)*40000+1,i*40000); value.Parent=output end
  output:SetAttribute("ByteLength",#json); output:SetAttribute("Chunks",math.ceil(#json/40000))
 end
 output:SetAttribute("Complete",true)
 if watchdog and coroutine.running()~=watchdog then pcall(task.cancel,watchdog) end
 if worker and coroutine.running()~=worker then pcall(task.cancel,worker) end
end
local function waitFor(label,seconds,predicate)
 result.Stage=label; output:SetAttribute("Stage",label); local untilAt=math.min(started+240,os.clock()+seconds)
 repeat assert(not ended,"test ended"); local v=predicate(); if v then return v end; task.wait(.1) until os.clock()>=untilAt
 error("TIMEOUT: "..label)
end
local function place(position,lookAt,reason)
 assert(not ended,"test ended"); local r,_,c=rootOf(actor,true); if not r then r,_,c=rootOf(actor,false) end
 assert(r and c,"living diagnostic actor unavailable")
 c:PivotTo(CFrame.lookAt(position,lookAt or position+Vector3.zAxis)*r.CFrame:ToObjectSpace(c:GetPivot()))
 r.AssemblyLinearVelocity=Vector3.zero; r.AssemblyAngularVelocity=Vector3.zero; event("diagnostic_placement",{Reason=reason,Position=vec(position)})
end
local function liveModel()
 local runtime=manifest and manifest.World:FindFirstChild("Level 2 Pool Slide Runtime")
 return runtime and runtime:FindFirstChild("Level 2 Pool Slide")
end
local function ground(point)
 local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Include; params.FilterDescendantsInstances={manifest.World}; params.IgnoreWater=true
 local origin=point+Vector3.new(0,4,0)
 for _=1,8 do
  local hit=workspace:Raycast(origin,Vector3.new(0,-36,0),params); if not hit then return end
  if hit.Normal.Y>.85 and hit.Instance.CanCollide and hit.Instance:GetAttribute("Level2_EntityGround")==true and hit.Instance:GetAttribute("Level2_NoEntityGround")~=true then return hit.Position+Vector3.new(0,3.5,0) end
  origin=hit.Position-Vector3.new(0,.05,0)
 end
end
local spawnSeen={}
local function recordSpawn(model)
 if ended or spawnSeen[model] then return end; spawnSeen[model]=true
 local position=model:GetPivot().Position; local rows={}; local nearest=math.huge
 for _,p in ipairs(Players:GetPlayers()) do local r=rootOf(p,true); if r then
  local distance=horizontal(position,r.Position); nearest=math.min(nearest,distance)
  table.insert(rows,{UserId=p.UserId,Horizontal=distance,Distance3D=(position-r.Position).Magnitude,Position=vec(r.Position)})
 end end
 result.Spawn={T=os.clock()-started,Path=model:GetFullName(),Generation=model:GetAttribute("Level2_Generation"),Pumps=workspace:GetAttribute("Level2Pumps"),Position=vec(position),Living=rows,MinimumHorizontal=#rows>0 and nearest or nil}
 check("spawn_distance_all_living",#rows>0 and nearest>=minimum,result.Spawn)
end
table.insert(connections,remote.OnServerEvent:Connect(function(p,inToken,command,index)
 if ended or inToken~=token then return end
 if command=="ready" then queueReady=p elseif command=="configured" then event("real_queue_configured",{UserId=p.UserId,Station=index}) end
end))
watchdog=task.delay(240,function() finish("HARD_TIMEOUT: "..tostring(result.Stage)) end)
worker=task.spawn(function()
 local ok,err=xpcall(function()
  actor=waitFor("healthy normal Play client ready",75,function() if queueReady and rootOf(queueReady,false) then return queueReady end end)
  assert(#Players:GetPlayers()==1,"this is explicitly a single-player test")
  assert(workspace:GetAttribute("RoundActive")~=true,"start from normal lobby; existing rounds are not overwritten")
  memory("lobby"); local lobby=assert(workspace:FindFirstChild("ServerLobby")); local zone
  for _,part in ipairs(lobby:GetDescendants()) do if part:IsA("BasePart") and part.Name:match("^LaunchZone%d+$") then
   local a=part.Parent; while a and a~=lobby do if a:GetAttribute("LevelNumber")==2 then zone=part; break end; a=a.Parent end
   if zone then break end
  end end
  assert(zone,"live Level 2 launch zone missing"); local station=assert(tonumber(zone.Name:match("(%d+)$")))
  remote:SetAttribute("QueueStation",station); task.wait(.2); place((zone.CFrame*CFrame.new(0,3.5,0)).Position,zone.Position+zone.CFrame.LookVector*10,"real Level 2 queue zone")
  waitFor("actual Level 2 round",120,function() return workspace:GetAttribute("RoundActive")==true and workspace:GetAttribute("WorldGenerated")==true and workspace:GetAttribute("SelectedLevel")==2 and rootOf(actor,true) end)
  assert(workspace:GetAttribute("EntityPaused")~=true,"entity is paused; test will not unpause it")
  local systems=game.ServerScriptService["Level 2 Systems"]; manifest=assert(require(systems["Level 2 Round Adapter"]).GetManifest())
  controller=require(systems["Level 2 Pool Slide Controller"]); local objective=require(systems["Level 2 Objective Controller"])
  local config=require(systems["Level 2 Pool Slide Configuration"]); local generation=manifest.World:GetAttribute("Level2_Generation")
  result.Generation=generation; result.Seed=manifest.Layout.Seed; memory("generated_before_pumps")
  table.insert(connections,manifest.World.DescendantAdded:Connect(function(item)
   if item:IsA("Model") and item.Name=="Level 2 Pool Slide" and item.Parent and item.Parent.Name=="Level 2 Pool Slide Runtime" then recordSpawn(item) end
  end))
  local pumps=table.clone(manifest.Pumps); table.sort(pumps,function(a,b) return a.Index<b.Index end); assert(#pumps==3)
  local function pull(pump)
   assert(not ended and rootOf(actor,true),"actor unavailable for pump; normal death retained")
   local parent=pump.Prompt.Parent; local target=parent:IsA("Attachment") and parent.WorldPosition or parent.Position
   for i=0,7 do local a=i*math.pi/4; local position=ground(target+Vector3.new(math.cos(a)*4,0,math.sin(a)*4))
    if position then place(position,target,"pump approach; original proximity and LOS check"); task.wait(.15)
     assert(not ended,"test ended"); if objective.DebugActivatePump(pump.Index,actor)==true then event("real_pump_started",{Index=pump.Index,Count=workspace:GetAttribute("Level2Pumps")}); return end
    end
   end
   error("normal pump validation rejected station "..pump.Index)
  end
  assert(workspace:GetAttribute("Level2Pumps")==0,"fresh round required"); check("no_spawn_at_pump0",liveModel()==nil)
  pull(pumps[1]); task.wait(.2); check("no_spawn_at_pump1",workspace:GetAttribute("Level2Pumps")==1 and liveModel()==nil)
  pull(pumps[2]); actualModel=waitFor("actual pump2 spawn",35,liveModel); recordSpawn(actualModel)
  waitFor("actual pump2 ACTIVE state",3,function() return controller.GetDebugSnapshot().Phase=="ACTIVE" end)
  result.BeforePump3={Phase=controller.GetDebugSnapshot().Phase,Speed=actualModel:GetAttribute("Level2_PoolSlideSpeed"),ConfiguredNormalRunSpeed=config.NormalRunSpeed,ConfiguredWalkSpeed=config.WalkSpeed}
  check("spawn_at_pump2",workspace:GetAttribute("Level2Pumps")==2); memory("pump2_spawned")
  pull(pumps[3]); local thirdAt=os.clock(); result.ThirdPumpAt=thirdAt-started
  waitFor("same model ENRAGED",3,function() return liveModel()==actualModel and controller.GetDebugSnapshot().Phase=="ENRAGED" end)
  check("same_entity_enraged_at_pump3",true); result.ConfiguredEnragedSpeed=config.EnragedSpeed
  local foamConfig=require(systems["Level 2 Pool Foam Configuration"])
  local function foamRoots()
   assert(type(foamConfig.RuntimeFolderName)=="string","current Foam runtime configuration missing")
   local runtime=assert(manifest.World:FindFirstChild(foamConfig.RuntimeFolderName),"current Foam runtime absent; placement safety unverified")
   local roots={}; for _,model in ipairs(runtime:GetChildren()) do if model:IsA("Model") then
    local root=model.PrimaryPart; assert(root and root.Parent,"existing Foam model has no PrimaryPart; placement safety unverified")
    table.insert(roots,root)
   end end; return roots
  end
  local currentFoamRoots=foamRoots(); local minimumFoamGap=180; local minimumGiantGap=config.EnragedSpeed*20+100
  local function foamClear(point,roots)
   for _,root in ipairs(roots) do if not root.Parent or horizontal(point,root.Position)<minimumFoamGap then return false end end
   return true
  end
  local best, bestGap; local seen={}; local from=actualModel:GetPivot().Position
  for _,container in pairs({manifest.EntityNodes,manifest.EntityDen,manifest.Navigation}) do if typeof(container)=="Instance" then
   for _,anchor in ipairs(container:GetDescendants()) do if anchor:IsA("BasePart") and not seen[anchor] then
    seen[anchor]=true; local gap=horizontal(from,anchor.Position)
    if gap>minimumGiantGap and (not bestGap or gap<bestGap) then local p=ground(anchor.Position); if p and foamClear(p,currentFoamRoots) then best,bestGap=p,gap end end
   end end
  end end
  assert(best,"no existing grounded anchor satisfies giant and all-current-Foam placement distances; observation not started")
  currentFoamRoots=foamRoots(); from=actualModel:GetPivot().Position
  assert(horizontal(best,from)>=minimumGiantGap and foamClear(best,currentFoamRoots),"entity positions changed; selected anchor no longer satisfies placement safety")
  local placementSafety={Position=vec(best),GiantHorizontalDistance=horizontal(best,from),RequiredGiantDistance=minimumGiantGap,RequiredFoamDistance=minimumFoamGap,Foam={}}
  for _,root in ipairs(currentFoamRoots) do table.insert(placementSafety.Foam,{Path=root:GetFullName(),Position=vec(root.Position),HorizontalDistance=horizontal(best,root.Position)}) end
  event("far_observation_anchor_distances",placementSafety)
  place(best,from,"one far target placement; no enemy, speed, damage or health changes")
  local observeAt=os.clock(); local lastPosition,lastDelta; local travelled,reversals,maxSpeed=0,0,0; local complete=true
  repeat
   if ended then return end
   if not rootOf(actor,true) or liveModel()~=actualModel or manifest.World:GetAttribute("Level2_Generation")~=generation or workspace:GetAttribute("RoundActive")~=true or workspace:GetAttribute("EntityPaused")==true then complete=false; event("observation_interrupted","normal actor death, model replacement, generation reset, pause or round end"); break end
   local snapshot=controller.GetDebugSnapshot(); local nav=snapshot.Navigation or {}; local position=actualModel:GetPivot().Position
   if snapshot.Phase~="ENRAGED" then complete=false; event("observation_interrupted","entity left ENRAGED phase"); break end
   local speed=actualModel:GetAttribute("Level2_PoolSlideSpeed") or 0; maxSpeed=math.max(maxSpeed,speed)
   if lastPosition then local delta=Vector3.new(position.X-lastPosition.X,0,position.Z-lastPosition.Z); travelled+=delta.Magnitude
    if delta.Magnitude>.25 then if lastDelta and lastDelta.Unit:Dot(delta.Unit)<-.65 then reversals+=1 end; lastDelta=delta end
   end
   lastPosition=position
   table.insert(result.Samples,{T=os.clock()-started,Position=vec(position),SameInstance=liveModel()==actualModel,Generation=generation,Pumps=workspace:GetAttribute("Level2Pumps"),Phase=snapshot.Phase,State=snapshot.State,Speed=speed,Target=snapshot.TargetUserId,AttackSerial=snapshot.AttackSerial,PathStatus=nav.Status,Computing=nav.Computing,RequestId=nav.RequestId,RouteInstalls=nav.RouteInstalls,RejectedRoutes=nav.RejectedRoutes,WaypointIndex=nav.WaypointIndex,WaypointCount=nav.WaypointCount,LastPathFailure=nav.LastFailure,LastBlockedBy=nav.LastBlockedBy,SpawnCount=snapshot.SpawnCount,SpawnNavigatorBuilds=snapshot.SpawnNavigatorBuilds,SpawnProbes=snapshot.SpawnProbes,FailedSpawnPasses=snapshot.FailedSpawnPasses,ExitPowered=workspace:GetAttribute("Level2ExitPowered")})
   if not result.ExitPoweredDelay and workspace:GetAttribute("Level2ExitPowered")==true then result.ExitPoweredDelay=os.clock()-thirdAt end
   task.wait(.25)
  until os.clock()-observeAt>=20
  result.Movement={Elapsed=os.clock()-observeAt,Full20Seconds=complete and os.clock()-observeAt>=20,HorizontalTravel=travelled,DirectionReversals=reversals,MaximumPublishedSpeed=maxSpeed,Note="Coarse direction changes may include legitimate corridor turns; not an oscillation classifier."}
  check("observed_speed_32",maxSpeed>=31.9 and maxSpeed<=32.1 and config.EnragedSpeed==32)
  check("full20s_active_movement",result.Movement.Full20Seconds and travelled>20,result.Movement)
  check("original_exit_powers_without_override",result.ExitPoweredDelay~=nil,{ObservedDelay=result.ExitPoweredDelay,SamplingToleranceSeconds=.25})
  local n=0; for _ in pairs(spawnSeen) do n+=1 end; check("one_actual_model",n==1 and liveModel()==actualModel)
  result.FinalController={Running=controller.IsRunning(),SpawnedModels=n}; memory("after_observation")
 end,debug.traceback)
 if not ended then finish(not ok and err or nil) end
end)
