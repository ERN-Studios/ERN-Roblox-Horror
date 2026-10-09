-- Test scaffolding only. The complete selected production source is inserted
-- once below, unchanged, and drives the fake scheduler and service callbacks.
local checks = 0
local function check(value, message)
 checks += 1
 assert(value, message)
end
local function equal(actual, expected, message)
 check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function vector(x, y, z)
 local value = {X=x or 0,Y=y or 0,Z=z or 0,_kind="Vector3"}
 local mt = {}
 mt.__index = function(self,key)
  if key=="Magnitude" then return math.sqrt(self.X*self.X+self.Y*self.Y+self.Z*self.Z) end
 end
 mt.__add = function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
 mt.__sub = function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
 mt.__mul = function(a,b)
  if type(a)=="number" then a,b=b,a end
  return vector(a.X*b,a.Y*b,a.Z*b)
 end
 return setmetatable(value,mt)
end
local ENUM = {
 ContentSourceType={Uri="Uri",Opaque="Opaque"},
 AssetFetchStatus={Success="Success",Failure="Failure",Loading="Loading"},
 RaycastFilterType={Include="Include"},
}
local function uri(id) return {_kind="Content",SourceType=ENUM.ContentSourceType.Uri,Uri=id} end
local function signal()
 local value={Connections={}}
 function value:Connect(callback)
  local connection={Connected=true,Callback=callback}
  function connection:Disconnect() self.Connected=false end
  self.Connections[#self.Connections+1]=connection
  return connection
 end
 function value:Fire(...)
  for _,connection in ipairs(table.clone(self.Connections)) do
   if connection.Connected then connection.Callback(...) end
  end
 end
 function value:Count()
  local n=0 for _,connection in ipairs(self.Connections) do if connection.Connected then n+=1 end end
  return n
 end
 return value
end

local function environment()
 local env={Time=0,Jobs={},Errors={},Calls={},Plans={},Created={},Warnings={},Acks={}}
 local function resume(job)
  local ok,delay=coroutine.resume(job.Thread)
  if not ok then env.Errors[#env.Errors+1]=tostring(delay); job.Done=true; return end
  if coroutine.status(job.Thread)=="dead" then job.Done=true
  else job.Due=env.Time+(type(delay)=="number" and delay or 0.03) end
 end
 env.Task={}
 function env.Task.wait(delay) return coroutine.yield(delay or 0.03) end
 function env.Task.spawn(callback,...)
  local args=table.pack(...)
  local job={Thread=coroutine.create(function() callback(table.unpack(args,1,args.n)) end),Due=env.Time}
  env.Jobs[#env.Jobs+1]=job
  resume(job)
  return job.Thread
 end
 function env.Task.defer(callback,...)
  local args=table.pack(...)
  return env.Task.spawn(function() env.Task.wait(0.001); callback(table.unpack(args,1,args.n)) end)
 end
 function env:Advance(duration)
  local deadline=self.Time+duration local steps=0
  while true do
   local nextJob
   for _,job in ipairs(self.Jobs) do
    if not job.Done and job.Due<=deadline and (not nextJob or job.Due<nextJob.Due) then nextJob=job end
   end
   if not nextJob then break end
   self.Time=nextJob.Due resume(nextJob) steps+=1
   assert(steps<20000,"Test scheduler did not settle")
  end
  self.Time=deadline
 end
 local methods={}
 local classes={MeshPart={BasePart=true},Part={BasePart=true},Texture={Decal=true}}
 function methods:IsA(class) return self.ClassName==class or classes[self.ClassName] and classes[self.ClassName][class] or false end
 function methods:IsDescendantOf(ancestor)
  local p=self.Parent while p do if p==ancestor then return true end; p=p.Parent end return false
 end
 function methods:FindFirstChild(name)
  for _,child in ipairs(self._children) do if child.Name==name then return child end end
 end
 function methods:WaitForChild(name) return assert(self:FindFirstChild(name),"Missing fake child "..name) end
 function methods:FindFirstChildOfClass(class)
  for _,child in ipairs(self._children) do if child.ClassName==class then return child end end
 end
 function methods:FindFirstAncestorWhichIsA(class)
  local p=self.Parent while p do if p:IsA(class) then return p end; p=p.Parent end
 end
 function methods:GetDescendants()
  local out={}
  local function visit(root) for _,child in ipairs(root._children) do out[#out+1]=child; visit(child) end end
  visit(self) return out
 end
 function methods:GetAttribute(key) return self._attributes[key] end
 function methods:SetAttribute(key,value) self._attributes[key]=value end
 function methods:GetFullName()
  return self.Parent and self.Parent:GetFullName().."."..self.Name or self.Name
 end
 function methods:Destroy()
  if self._data.Destroyed then return end
  self._data.Destroyed=true self._data.DestroyCount=(self._data.DestroyCount or 0)+1
  local parent=self.Parent
  if parent then local i=table.find(parent._children,self); if i then table.remove(parent._children,i) end end
  self._data.Parent=nil
  env.Task.defer(function() self.Destroying:Fire() end)
 end
 local function instance(class,name,parent)
  local data={ClassName=class,Name=name or class,Destroyed=false,Position=vector(),Size=vector(2,2,2),
   Transparency=0,CanCollide=true,Health=100,Parent=nil}
  local value={_kind="Instance",_data=data,_children={},_attributes={},DescendantAdded=signal(),Destroying=signal()}
  setmetatable(value,{
   __index=function(_,key) return methods[key] or data[key] end,
   __newindex=function(self,key,newValue)
    if key=="Parent" then
     assert(not data.Destroyed,"Parent property is locked after Destroy")
     local previous=data.Parent
     if previous then local i=table.find(previous._children,self); if i then table.remove(previous._children,i) end end
     data.Parent=newValue
     if newValue then
      newValue._children[#newValue._children+1]=self
      local p=newValue while p do p.DescendantAdded:Fire(self); p=p.Parent end
     end
    else
     if class=="Decal" and key=="Texture" and env.FailTextureAssignment then error("Synthetic carrier preparation error") end
     data[key]=newValue
    end
   end,
  })
  if parent then value.Parent=parent end
  return value
 end
 env.Instance={new=function(class)
  local value=instance(class)
  env.Created[#env.Created+1]=value return value
 end}
 env.Make=instance
 env.Workspace=instance("Workspace","Workspace")
 function env.Workspace:GetServerTimeNow() return env.Time end
 function env.Workspace:Raycast()
  return {Instance=env.Floor,Normal=vector(0,1,0),Position=vector(0,-3,0)}
 end
 env.Workspace:SetAttribute("SelectedLevel",4)
 env.Cinema=instance("Model","Level 4 Cinema Blender",env.Workspace)
 env.Floor=instance("Part","AuthoredFloor",env.Cinema)
 env.Character=instance("Model","ActualCharacter",env.Workspace)
 env.Root=instance("Part","HumanoidRootPart",env.Character)
 env.Humanoid=instance("Humanoid","Humanoid",env.Character)
 env.Player=instance("Player","LocalPlayer")
 env.Player.Character=env.Character
 env.Player.CharacterAdded=signal()
 env.Player:SetAttribute("RoundEntryUIReady",true)
 env.Player:SetAttribute("RoundEntryControlsReady",true)
 function env.Player:RequestStreamAroundAsync() end
 env.Remote=instance("RemoteEvent","RoundStatus")
 env.Remote.OnClientEvent=signal()
 function env.Remote:FireServer(event,payload)
  env.Acks[#env.Acks+1]={Event=event,Payload=payload,Time=env.Time}
 end
 local remotes=instance("Folder","Remotes")
 env.Remote.Parent=remotes
 local replicated=instance("ReplicatedStorage","ReplicatedStorage") remotes.Parent=replicated
 env.ContentProvider={}
 local function contentID(value)
  local key=type(value)=="string" and value or type(value)=="table" and value._kind=="Content" and value.Uri or nil
  return key and key~="" and key or nil
 end
 function env:InstanceKeys(object)
  local keys={}
  local properties={MeshPart={"MeshContent","TextureContent"},SpecialMesh={"MeshId","TextureId"},
   Decal={"Texture"},Texture={"Texture"},ImageLabel={"Image"},ImageButton={"Image"},
   ParticleEmitter={"Texture"},Beam={"Texture"},Trail={"Texture"}}
  for _,property in ipairs(properties[object.ClassName] or {}) do
   local key=contentID(object[property])
   if key and not table.find(keys,key) then keys[#keys+1]=key end
  end
  return keys
 end
 function env.ContentProvider:PreloadAsync(objects,callback)
  local call={Objects=table.clone(objects),Keys={},Callbacks={},Time=env.Time}
  for _,object in ipairs(objects) do
   for _,key in ipairs(env:InstanceKeys(object)) do if not table.find(call.Keys,key) then call.Keys[#call.Keys+1]=key end end
  end
  env.Calls[#env.Calls+1]=call
  local plan=env.Plans[#env.Calls] or {}
  while plan.Gate and not plan.Gate.Open do env.Task.wait(0.05) end
  if plan.Throw then error("Synthetic engine request error") end
  local callbacks=plan.Callbacks
  if callbacks==nil then
   callbacks={}
   for _,key in ipairs(call.Keys) do
    callbacks[#callbacks+1]={plan.Alias and plan.Alias(key) or key,ENUM.AssetFetchStatus.Success}
   end
  end
  for _,item in ipairs(callbacks) do
   call.Callbacks[#call.Callbacks+1]=item
   callback(item[1],item[2])
  end
  if plan.ThrowAfterCallbacks then error("Synthetic engine error after callback") end
  call.Returned=true call.ReturnTime=env.Time
 end
 local services={Players={LocalPlayer=env.Player},ReplicatedStorage=replicated,ContentProvider=env.ContentProvider,
  RunService={IsStudio=function() return true end},StarterGui={SetCore=function() end}}
 env.Game={GetService=function(_,name) return assert(services[name],"Unknown fake service "..name) end,IsLoaded=function() return true end}
 env.Vector3={new=vector,yAxis=vector(0,1,0)}
 env.RaycastParams={new=function() return {} end}
 env.Typeof=function(value) return type(value)=="table" and rawget(value,"_kind") or type(value) end
 env.OS={clock=function() return env.Time end}
 env.Warn=function(value) env.Warnings[#env.Warnings+1]=value end
 function env:AddMesh(id,texture,parent)
  local mesh=instance("MeshPart","Mesh"..id,parent or env.Cinema)
  mesh.MeshContent=uri("rbxassetid://"..id)
  mesh.TextureContent=texture and uri("rbxassetid://"..texture) or uri("")
  mesh.MeshId="rbxassetid://"..id mesh.TextureID=texture and "rbxassetid://"..texture or ""
  return mesh
 end
 function env:AddPBR(id)
  local part=instance("Part","PBRPart",env.Cinema)
  local pbr=instance("SurfaceAppearance","PBR",part)
  pbr.ColorMapContent=uri("rbxassetid://"..id)
  pbr.NormalMapContent=uri("") pbr.RoughnessMapContent=uri("") pbr.MetalnessMapContent=uri("")
  return pbr
 end
 return env
end

local function install(env)
 local game,workspace,task,Instance,Enum,typeof,Vector3,RaycastParams,warn,os =
  env.Game,env.Workspace,env.Task,env.Instance,ENUM,env.Typeof,env.Vector3,env.RaycastParams,env.Warn,env.OS
 -- __ACTUAL_ROUND_ENTRY_SOURCE__
 return {Active=function() return active end,Busy=function() return entryPreloadBusy end,Begin=begin,Cancel=cancel}
end
local function start(env,api,token)
 api.Begin({Token=token or "entry-1",Level=4,Character=env.Character,Position=vector(),Deadline=30})
 return api.Active()
end
local function assertNoErrors(env,label)
 equal(#env.Errors,0,label.." has no unhandled worker errors: "..table.concat(env.Errors,"; "))
end
local function assertDecalsDestroyed(env,label)
 local count=0
 for _,object in ipairs(env.Created) do
  if object.ClassName=="Decal" then
   count+=1 check(object.Destroyed,label.." temporary Decal destroyed")
   equal(object.DestroyCount,1,label.." Decal cleanup occurs once")
   check(not pcall(function() object.Parent=nil end),label.." destroyed Parent locked")
  end
 end
 check(count>0,label.." created a supported Decal")
end

-- A batch uses typed meshes and supported temporary Decals together; the same
-- key appearing twice is deduplicated by the actual collector.
do
 local env=environment()
 env:AddMesh(101,102) env:AddMesh(103) env:AddPBR(104) env:AddMesh(101)
 local api=install(env) local request=start(env,api)
 env:Advance(0.8)
 equal(#env.Calls,1,"One engine request for a ready pending batch")
 equal(#env.Calls[1].Objects,3,"Mesh/PBR batch retains three typed carriers")
 equal(#env.Calls[1].Keys,4,"Each unique required asset is included")
 check(env.Calls[1].Objects[1].ClassName=="MeshPart","Actual mesh instance retained")
 check(request.AssetsReady,"Success for every required key permits readiness")
 check(#env.Acks>0,"Normal UI/floor/control gate acknowledges after stability")
 assertDecalsDestroyed(env,"Success") assertNoErrors(env,"Success")
 api.Cancel()
end

-- Roblox callback URLs can be canonical asset IDs even when the property URI
-- uses another supported asset-ID form.
do
 local env=environment() env:AddMesh(111,112)
 local function alias(key) return "https://assetdelivery.roblox.com/v1/asset/?id="..assert(key:match("(%d+)$")) end
 env.Plans[1]={Alias=alias}
 local api=install(env) local request=start(env,api)
 env:Advance(0.8)
 check(request.AssetsReady,"HTTP callbacks match numeric rbxassetid property IDs")
 equal(#env.Calls,1,"Canonical callback alias does not spend retry")
 assertNoErrors(env,"Callback aliases") api.Cancel()
end

-- A partial callback, an unrelated callback, an absent callback, and a failure
-- all preserve the cover. Exactly two completed attempts are allowed.
for _,case in ipairs({
 {Name="Missing second key",Callbacks={{"rbxassetid://201","Success"}}},
 {Name="Unrelated callback",Callbacks={{"rbxassetid://999999","Success"}}},
 {Name="Absent callback",Callbacks={}},
 {Name="Explicit failed key",Callbacks={{"rbxassetid://201","Success"},{"rbxassetid://202","Failure"}}},
 {Name="Failure followed by success",Callbacks={{"rbxassetid://201","Success"},{"rbxassetid://202","Failure"},{"rbxassetid://202","Success"}}},
 {Name="Unknown failed dependency",Callbacks={{"rbxassetid://201","Success"},{"rbxassetid://202","Success"},{"rbxassetid://299","Failure"}}},
 {Name="Untrusted domain ID",Callbacks={{"https://roblox.com.example.test/asset/?id=201","Success"},{"rbxassetid://202","Success"}}},
}) do
 local env=environment() env:AddMesh(201,202)
 env.Plans[1]={Callbacks=case.Callbacks} env.Plans[2]={Callbacks=case.Callbacks}
 local api=install(env) local request=start(env,api)
 env:Advance(1.2)
 equal(#env.Calls,2,case.Name.." gets two attempts")
 check(not request.AssetsReady,case.Name.." blocks readiness")
 equal(#env.Acks,0,case.Name.." never acknowledges")
 check(#env.Warnings>0,case.Name.." reports exhausted real fetch attempt")
 assertNoErrors(env,case.Name) api.Cancel()
end

-- HTTP property IDs and rbxassetid callback IDs match in the reverse direction.
-- Unknown additional successful dependencies do not replace required callbacks.
do
 local env=environment() local mesh=env:AddMesh(601)
 mesh.MeshContent=uri("http://www.roblox.com/asset/?id=601&version=2")
 env.Plans[1]={Callbacks={{"rbxassetid://601","Success"},{"rbxassetid://699","Success"}}}
 local api=install(env) local request=start(env,api)
 env:Advance(0.8)
 check(request.AssetsReady,"HTTP property canonical ID matches real rbxassetid callback")
 equal(#env.Calls,1,"Successful extra dependency does not spend retry")
 assertNoErrors(env,"Reverse callback alias") api.Cancel()
end

-- A failed first batch can recover, with only unresolved carriers retried.
do
 local env=environment() env:AddMesh(211) env:AddMesh(212)
 env.Plans[1]={Callbacks={{"rbxassetid://211","Success"},{"rbxassetid://212","Failure"}}}
 local api=install(env) local request=start(env,api)
 env:Advance(0.8)
 equal(#env.Calls,2,"Unresolved carrier receives one retry")
 equal(#env.Calls[2].Objects,1,"Already successful carrier is not retried")
 equal(env.Calls[2].Keys[1],"rbxassetid://212","Only the failed key is retried")
 check(request.AssetsReady,"Second successful result recovers readiness")
 assertNoErrors(env,"Retry recovery") api.Cancel()
end

-- DescendantAdded while the uncancellable engine yields resets readiness and
-- is included in the next pass; the first batch cannot certify that arrival.
do
 local env=environment() env:AddMesh(301)
 local gate={Open=false} env.Plans[1]={Gate=gate}
 local api=install(env) local request=start(env,api)
 check(api.Busy(),"Pending engine request owns preload mutex")
 env:AddMesh(302) env:Advance(0.2)
 equal(#env.Calls,1,"Dynamic arrival waits behind existing engine owner")
 check(not request.AssetsReady,"Arrival cannot be marked ready before load")
 gate.Open=true env:Advance(0.8)
 equal(#env.Calls,2,"Dynamic arrival is fetched in a following batch")
 equal(env.Calls[2].Keys[1],"rbxassetid://302","Following batch includes arriving key")
 check(request.AssetsReady,"Quiet interval after all results permits readiness")
 assertNoErrors(env,"Dynamic arrival") api.Cancel()
end

-- Cancellation keeps the old request's temporary Decal and mutex until the
-- engine drains. A replacement request cannot overlap or inherit readiness.
do
 local env=environment() env:AddPBR(401)
 local gate={Open=false} env.Plans[1]={Gate=gate}
 local api=install(env) local first=start(env,api,"old-entry")
 check(api.Busy(),"Cancelled engine request initially owns preload mutex")
 equal(#env.Created,1,"Yielding batch owns one temporary Decal")
 check(not env.Created[1].Destroyed,"In-flight Decal remains alive")
 env.Remote.OnClientEvent:Fire("entrycancel",{Token="old-entry"})
 local second=start(env,api,"new-entry") env:Advance(0.5)
 check(api.Busy(),"Cancellation does not release engine mutex")
 equal(#env.Calls,1,"Replacement waits until old engine returns")
 equal(#env.Created,1,"Replacement does not create another owned carrier early")
 check(not first.AssetsReady and not second.AssetsReady,"Neither pending request is ready")
 gate.Open=true env:Advance(0.8)
 equal(#env.Calls,2,"Replacement starts only after drain")
 check(not first.AssetsReady,"Stale engine result never marks old request ready")
 check(second.AssetsReady,"Replacement independently becomes ready")
 for _,ack in ipairs(env.Acks) do equal(ack.Payload.Token,"new-entry","Old entry never acknowledges") end
 check(not api.Busy(),"Mutex released after both engine calls drain")
 assertDecalsDestroyed(env,"Cancellation") assertNoErrors(env,"Cancellation") api.Cancel()
 env:Advance(0.2)
 equal(env.Cinema.DescendantAdded:Count(),0,"Cancellation disconnects world arrivals")
 equal(env.Character.DescendantAdded:Count(),0,"Cancellation disconnects character arrivals")
end

-- Engine throws before and after real callbacks must still clean up carriers,
-- release ownership after return, and require a later complete success.
for _,after in ipairs({false,true}) do
 local env=environment() env:AddPBR(after and 502 or 501)
 env.Plans[1]=after and {ThrowAfterCallbacks=true} or {Throw=true}
 env.Plans[2]=after and {ThrowAfterCallbacks=true} or {Throw=true}
 local api=install(env) local request=start(env,api)
 env:Advance(1.2)
 equal(#env.Calls,2,"Throwing engine receives bounded two attempts")
 check(not request.AssetsReady,"Engine error blocks readiness even after success callback")
 equal(#env.Acks,0,"Engine error cannot acknowledge")
 check(not api.Busy(),"Throwing engine relinquishes mutex after drain")
 assertDecalsDestroyed(env,"Engine error") assertNoErrors(env,"Engine error") api.Cancel()
end

-- A carrier preparation exception occurs before the engine is called; the
-- already-owned temporary Decal is still destroyed and readiness stays false.
do
 local env=environment() env:AddPBR(701) env.FailTextureAssignment=true
 local api=install(env) local request=start(env,api)
 env:Advance(1.2)
 equal(#env.Calls,0,"Carrier preparation error never invokes engine")
 check(not request.AssetsReady,"Preparation error blocks readiness")
 equal(#env.Acks,0,"Preparation error cannot acknowledge")
 check(not api.Busy(),"Preparation error releases owner after cleanup")
 equal(#env.Created,2,"Preparation error consumes bounded two attempts")
 assertDecalsDestroyed(env,"Preparation error") assertNoErrors(env,"Preparation error") api.Cancel()
end

print("Round Entry actual-source contract: "..checks.." checks passed")
