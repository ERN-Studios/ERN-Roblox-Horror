-- Artifact only. Root chooses the already-open Edit SID; this never changes mode.
-- Native geometry/callback-body authoring port, not player/gameplay certification.
local NativeGame, NativeInstance, NativeTask, NativeRequire = game, Instance, task, require
local H = NativeGame:GetService("HttpService")
local SES = NativeGame:GetService("ScriptEditorService")
local RS = NativeGame:GetService("RunService")
local ENC = NativeGame:GetService("EncodingService")
local TS = NativeGame:GetService("TweenService")
local request = H:JSONDecode(string.sub([[_{"schema":"mongotv-lobby-owned-native-request-v1","nativeScriptCount":213,"operation":"capture","variant":"before","fault":"none"}]],2))
local KEY = "MongoTVLobbyServicesOwnedWorldModelPortV1"
local state, originals, baselineBodies, assetRows, assetObjects = nil, {}, {}, {}, {}
local originalRawAttrs,assetRawAttrs={},{}
local owned, records, worlds, probes = {}, {}, {}, {}
local checks, phases, callbackErrors, cleanupErrors, guardErrors = 0, {}, {}, {}, {}
local started = os.clock()
local function check(value, label) checks += 1; assert(value, label) end
local function sha(text)
 local bytes = ENC:ComputeBufferHash(buffer.fromstring(text), Enum.HashAlgorithm.Sha256)
 local result = {} for i=0,buffer.len(bytes)-1 do result[#result+1]=string.format("%02x", buffer.readu8(bytes,i)) end
 return table.concat(result)
end
local function stable(value)
 if type(value) ~= "table" then return H:JSONEncode(value) end
 local keys={} for key in pairs(value) do keys[#keys+1]=key end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={} for _,key in ipairs(keys) do out[#out+1]=H:JSONEncode(key)..":"..stable(value[key]) end
 return "{"..table.concat(out,",").."}"
end
local function mode()
 check(NativeGame.PlaceId==131311258779917 and NativeGame.GameId==10559217407,"Wrong place/universe")
 check(not RS:IsRunning(),"Edit required; preserve other actor's Play")
 check(os.clock()-started<90,"Bounded port deadline")
end
local function path(n)
 local out={} while n~=NativeGame do table.insert(out,1,n.Name);n=assert(n.Parent,"Unparented original") end
 return out
end
local function resolve(parts)
 local n=NativeGame for _,name in ipairs(parts) do
  local found={} for _,child in ipairs(n:GetChildren()) do if child.Name==name then found[#found+1]=child end end
  check(#found==1,"Missing/ambiguous original path") n=found[1]
 end return n
end
local function attributes(n)
 local function bits(value)
  local b=buffer.create(8);buffer.writef64(b,0,value);local out={}
  for i=0,7 do out[#out+1]=string.format("%02x",buffer.readu8(b,i))end;return table.concat(out)
 end
 local out={}
 for key,value in pairs(n:GetAttributes())do
  local kind=typeof(value);local item={type=kind}
  if kind=="string"or kind=="number"or kind=="boolean"then item.value=value
  elseif kind=="Vector3"then item.components={value.X,value.Y,value.Z}
  elseif kind=="Vector2"then item.components={value.X,value.Y}
  elseif kind=="Color3"then item.components={value.R,value.G,value.B}
  elseif kind=="CFrame"then item.components={value:GetComponents()}
  elseif kind=="BrickColor"then item.value=value.Number
  elseif kind=="UDim"then item.components={value.Scale,value.Offset}
  elseif kind=="UDim2"then item.components={value.X.Scale,value.X.Offset,value.Y.Scale,value.Y.Offset}
  elseif kind=="Rect"then item.components={value.Min.X,value.Min.Y,value.Max.X,value.Max.Y}
  elseif kind=="NumberRange"then item.components={value.Min,value.Max}
  else error("Unsupported native attribute type for exact guard: "..kind)end
  if kind=="number"then item.valueBits=bits(value)end
  if item.components then item.componentBits={};for _,component in ipairs(item.components)do item.componentBits[#item.componentBits+1]=bits(component)end end
  out[key]=item
 end
 return out
end
local function sameProperty(a,b)
 if a==b then return true end
 local kind=typeof(a);if typeof(b)~=kind then return false end
 local function bits(values)
  local out=buffer.create(#values*8);for i,v in ipairs(values)do buffer.writef64(out,(i-1)*8,v)end;return buffer.tostring(out)
 end
 -- Equal exact component bytes also handle an owned NaN readback: NaN is not
 -- reflexive under ==. This is an ownership cleanup check, never a pose gate.
 if kind=="CFrame"then return bits({a:GetComponents()})==bits({b:GetComponents()})end
 if kind=="Vector3"then return bits({a.X,a.Y,a.Z})==bits({b.X,b.Y,b.Z})end
 if kind=="Vector2"then return bits({a.X,a.Y})==bits({b.X,b.Y})end
 if kind=="Color3"then return bits({a.R,a.G,a.B})==bits({b.R,b.G,b.B})end
 if kind=="number"then return bits({a})==bits({b})end
 return false
end
local function sameAttributes(a,b)
 for key,value in pairs(a)do if not sameProperty(b[key],value)then return false end end
 for key,value in pairs(b)do if not sameProperty(a[key],value)then return false end end
 return true
end
local function metadata(n)
 local props={} for _,name in ipairs({"Enabled","Disabled","RunContext","Archivable","LinkedSource"}) do
  local ok,v=pcall(function()return n[name]end)
  if ok then props[name]=if typeof(v)=="EnumItem" then tostring(v) else v end
 end
 local tags=n:GetTags();table.sort(tags)
 return {segments=path(n),studioPath=n:GetFullName(),instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),
  className=n.ClassName,properties=props,attributes=attributes(n),tags=tags}
end
local session={gameId=NativeGame:GetDebugId(16),workspaceId=NativeGame:GetService("Workspace"):GetDebugId(16),
 placeId=NativeGame.PlaceId,universeId=NativeGame.GameId,jobId=NativeGame.JobId,placeVersion=NativeGame.PlaceVersion}
local assetRoot=resolve({"ServerStorage","LobbyReimaginedBlenderSource20261001R4"})
local function assetSnapshot()
 local rows,objects={},{}
 local nodes={assetRoot,table.unpack(assetRoot:GetDescendants())}
 check(#nodes<=400 and not assetRoot:IsA("LuaSourceContainer"),"Bounded R4 native authoring data required")
 for _,n in ipairs(nodes) do
  check(not n:IsA("LuaSourceContainer"),"No Sourcecontainer asset clones/require")
  local row=metadata(n)
  if n:IsA("StringValue") then row.valueSHA256=sha(n.Value);row.valueBytes=#n.Value end
  rows[#rows+1]=row;objects[n]=stable(row)
 end
 table.sort(rows,function(a,b)return a.studioPath<b.studioPath end)
 return rows,objects
end
local function decodeManifest()
 check(assetRoot:IsA("Folder") and assetRoot:GetAttribute("Ready")==true and assetRoot:GetAttribute("LobbyReimaginedOwned")==true,"Inspect current native R4 ownership/readiness")
 local folder=assetRoot:FindFirstChild("ManifestJSON")
 check(folder and folder:IsA("Folder"),"Native compressed manifest absent")
 local children=folder:GetChildren();table.sort(children,function(a,b)return a.Name<b.Name end)
 check(#children>0 and #children<=30,"Bounded manifest chunks")
 local chunks={} for i,n in ipairs(children) do
  check(n:IsA("StringValue") and n.Name==string.format("%05d",i-1),"Manifest chunks ambiguous")
  chunks[#chunks+1]=n.Value
 end
 local compressed=ENC:Base64Decode(buffer.fromstring(table.concat(chunks)))
 check(buffer.len(compressed)==folder:GetAttribute("CompressedBytes"),"Native manifest compressed length")
 local raw=buffer.tostring(ENC:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd))
 check(#raw==folder:GetAttribute("RawBytes") and sha(raw)==folder:GetAttribute("RawSHA256") and sha(raw)==assetRoot:GetAttribute("ManifestSHA256"),"Native R4 manifest hashes")
 local manifest=H:JSONDecode(raw)
 check(manifest.schema=="lobby-reimagined-blender-v2" and manifest.revision==4 and manifest.placeId==131311258779917 and manifest.groupId==1039373905,"Native current R4 schema")
 return manifest,sha(raw)
end
local function guard(full)
 mode()
 if state then check(shared[KEY]==state and state.active,"Owned lease changed") end
 check(stable(session)==stable(request.session or session),"Native session epoch changed")
 for n,row in pairs(originals) do
  check(stable(metadata(n))==stable(row.meta),"Original identity/class/metadata changed")
  check(sameAttributes(n:GetAttributes(),originalRawAttrs[n]),"Original raw native attribute changed")
  check(n.Source==baselineBodies[n] and SES:GetEditorSource(n)==baselineBodies[n] and sha(n.Source)==row.sha256,"Original Source/editor changed")
 end
 local currentAssetRows=assetSnapshot()
 check(stable(currentAssetRows)==stable(assetRows),"Native R4 data/identity changed")
 for n,saved in pairs(assetRawAttrs)do check(sameAttributes(n:GetAttributes(),saved),"R4 raw native attribute changed")end
 if full then
  local count=0 for i,n in ipairs(NativeGame:GetDescendants()) do
   if n:IsA("LuaSourceContainer") and not owned[n] then check(originals[n]~=nil,"Concurrent original Source appeared");count+=1 end
   if i%10000==0 then NativeTask.wait();mode() end
  end
  check(count==request.nativeScriptCount,"Original Source count changed")
  guard(false)
 end
end
mode()
check(request.schema=="mongotv-lobby-owned-native-request-v1" and request.nativeScriptCount==213,"Reviewed request required")
assetRows,assetObjects=assetSnapshot()
for n in pairs(assetObjects)do assetRawAttrs[n]=n:GetAttributes()end
local rows={}
for i,n in ipairs(NativeGame:GetDescendants()) do
 if n:IsA("LuaSourceContainer") then
  local body=n.Source;check(SES:GetEditorSource(n)==body,"Original Source/editor conflict")
  local meta=metadata(n);local row={meta=meta,sha256=sha(body),bytes=#body}
  originals[n]=row;baselineBodies[n]=body;originalRawAttrs[n]=n:GetAttributes();rows[#rows+1]=row
 end
 if i%10000==0 then NativeTask.wait();mode() end
end
check(#rows==request.nativeScriptCount,"Fresh original Source coverage")
guard(true)
table.sort(rows,function(a,b)return a.meta.studioPath<b.meta.studioPath end)
local manifest,manifestHash=decodeManifest()
guard(false)
if request.operation=="capture" then
 local raw=H:JSONEncode({schema="mongotv-lobby-owned-native-baseline-v1",attributeEncoding="roblox-attribute-components-v1",pass=true,session=session,rows=rows,assetRows=assetRows,
  nativeManifestSHA256=manifestHash,originalSourceWrites=0,modeSwitches=0,objectsCreated=0,readAtUtc=DateTime.now():ToIsoDate()})
 check(#raw<=1000000,"Bounded native baseline raw JSON")
 local compressed=buffer.tostring(ENC:CompressBuffer(buffer.fromstring(raw),Enum.CompressionAlgorithm.Zstd))
 local data=buffer.tostring(ENC:Base64Encode(buffer.fromstring(compressed)))
 check(#data<=80000,"Bounded native baseline compressed transport")
 local envelope=H:JSONEncode({schema="mongotv-lobby-native-compressed-envelope-v2",encoding="zstd/base64",rawBytes=#raw,rawSHA256=sha(raw),
  compressedBytes=#compressed,compressedSHA256=sha(compressed),data=data})
 check(#envelope<=85000,"Proxy-safe native baseline envelope")
 return envelope
end
check(request.operation=="query" or(request.operation=="trial" and (request.variant=="before" or request.variant=="candidate")),"Single reviewed trial required")
check(request.fault=="none" or request.fault=="stage" or request.fault=="constructor" or request.fault=="callback","Reviewed owned failure port required")
check(stable(rows)==stable(request.rows) and stable(assetRows)==stable(request.assetRows) and manifestHash==request.nativeManifestSHA256,"Fresh captured native epoch mismatch")
check(shared[KEY]==nil,"Existing foreign/pending port lease")
state={active=true,phase="initial",owned=owned,records=records,worlds=worlds,probes=probes};shared[KEY]=state
local ROOT_PREFIX="MongoTV_LobbyServicesNativeOwned_"..H:GenerateGUID(false)
local gui,viewport,worldModel
local OWN_PROPERTIES={"Archivable","CFrame","Size","Color","Material","MaterialVariant","Transparency","Reflectance","CanCollide","CanTouch","CanQuery","Anchored","CastShadow","Shape","Enabled","Value","Brightness","Range","Angle","Face","Text","Texture","Image","MaxActivationDistance","HoldDuration","RequiresLineOfSight","KeyboardKeyCode","GamepadKeyCode","Duration","Neutral","AllowTeamChangeOnTouch"}
local function ownNative(n,allowSource)
 check(not originals[n] and not owned[n],"Fresh unique owned object required")
 check(allowSource or not n:IsA("LuaSourceContainer"),"Sourcecontainers require fresh staging path")
 local row={object=n,className=n.ClassName,name=n.Name,parent=n.Parent,props={},attrs=n:GetAttributes(),destroyed=false}
 for _,key in ipairs(OWN_PROPERTIES)do local good,value=pcall(function()return n[key]end);if good then row.props[key]=value end end
 owned[n]=row;records[#records+1]=row
 return n
end
local function quick()
 mode();check(shared[KEY]==state and state.active,"Owned lease lost")
 check(#records<12000,"Owned instance budget")
end
local function makeNative(class)
 quick();local n=ownNative(NativeInstance.new(class),false)
 if #records%500==0 then guard(false) end
 return n
end
local function noForeign(n)
 check(owned[n] and not originals[n],"Only registered owned instances")
 for _,child in ipairs(n:GetDescendants()) do check(owned[child]~=nil,"Foreign child retained") end
end
local function recordTree(n)
 for _,child in ipairs({n,table.unpack(n:GetDescendants())}) do
  local row=assert(owned[child],"Unknown tree child")
  row.name=child.Name;row.parent=child.Parent;row.attrs=child:GetAttributes()
  for _,key in ipairs(OWN_PROPERTIES)do local good,value=pcall(function()return child[key]end);if good then row.props[key]=value end end
 end
end
local function initialQueries()
 guard(false)
 gui=makeNative("ScreenGui");gui.Name=ROOT_PREFIX;gui.Enabled=false
 local core=NativeGame:GetService("CoreGui")
 check(not core:FindFirstChild(gui.Name),"Foreign authoring GUI collision")
 gui.Parent=core;recordTree(gui)
 viewport=makeNative("ViewportFrame");viewport.Name="OwnedViewport";viewport.Visible=false;viewport.Parent=gui
 worldModel=makeNative("WorldModel");worldModel.Name="OwnedWorld";worldModel.UseWorkspaceCollisionGroups=false;worldModel.Parent=viewport
 local floor=makeNative("Part");floor.Name="InitialQueryFloor";floor.Size=Vector3.new(20,1,20);floor.Anchored=true;floor.CanCollide=true;floor.CanQuery=true
 floor.CFrame=CFrame.new(0,-.5,0);floor.Parent=worldModel
 recordTree(gui);NativeTask.wait();guard(false)
 local ray=worldModel:Raycast(Vector3.new(0,5,0),Vector3.new(0,-10,0))
 check(ray and ray.Instance==floor and math.abs(ray.Position.Y)<.0001 and ray.Normal.Y>.99,"Actual WorldModel ray prerequisite failed")
 local hit=worldModel:GetPartBoundsInBox(CFrame.new(0,0,0),Vector3.new(2,2,2))
 check(table.find(hit,floor)~=nil,"Actual WorldModel overlap prerequisite failed")
 floor:Destroy();owned[floor].destroyed=true
 phases[#phases+1]={name="native-worldmodel-ray-overlap-prerequisite",pass=true}
end
-- All factory-visible objects are proxies for owned native objects. Raw original
-- instances/services, Source/editor setters, network and require are unavailable.
local function environment()
 local w={clock=0,jobs={},connections={},tweens={},manualSignals={},warnings={},active=true,players={}}
 worlds[#worlds+1]=w
 local proxies=setmetatable({},{__mode="k"});local natives=setmetatable({},{__mode="k"})
 local mt,methods={},{}
 local function raw(p) return natives[p] or p end
 local wrap,signal
 local function permitted(n) check(owned[n] and not originals[n],"Owned object missing") end
 local function write(p,key,value)
  quick();local n=raw(p);permitted(n);check(not owned[n].destroyed,"Write to destroyed owned object denied")
  check(key~="Source" and key~="LinkedSource" and key~="RunContext","Factory cannot alter Source/execution properties")
  if key=="Parent" and value~=nil then permitted(raw(value)) end
  n[key]=raw(value)
  local row=owned[n]
  if key=="Parent" then row.parent=raw(value) elseif key=="Name" then row.name=value else row.props[key]=n[key] end
  if n:IsA("BasePart")and(key=="Position"or key=="CFrame")then row.props.CFrame=n.CFrame;row.props.Position=nil end
 end
 local function dispatch(connection,...)
  if not w.active or not connection.Connected then return end
  quick();local args=table.pack(...)
  for i=1,args.n do if typeof(args[i])=="Instance" then permitted(args[i]);args[i]=wrap(args[i]) end end
  local ok,why=xpcall(function()
   connection.fn(table.unpack(args,1,args.n))
   if request.fault=="callback"and not w.callbackFaultInjected then w.callbackFaultInjected=true;error("OWNED_CALLBACK_FAULT")end
  end,debug.traceback)
  if not ok then callbackErrors[#callbackErrors+1]=tostring(why) end
 end
 signal=function(nativeSignal,label)
  local wrapper={}
  function wrapper:Connect(fn)
   quick();check(type(fn)=="function","Owned callback required")
   local c={Connected=true,fn=fn,label=label}
   function c:Disconnect() if self.Connected then self.Connected=false;if self.native then self.native:Disconnect() end end end
   w.connections[#w.connections+1]=c
   if nativeSignal then c.native=nativeSignal:Connect(function(...)dispatch(c,...)end) end
   w.manualSignals[label]=w.manualSignals[label] or {};table.insert(w.manualSignals[label],c)
   return c
  end
  function wrapper:Once(fn) local c;c=self:Connect(function(...)c:Disconnect();fn(...)end);return c end
  return wrapper
 end
 function methods:IsA(class) return raw(self):IsA(class) end
 function methods:GetChildren() local out={} for _,n in ipairs(raw(self):GetChildren())do permitted(n);out[#out+1]=wrap(n)end return out end
 function methods:GetDescendants() local out={} for _,n in ipairs(raw(self):GetDescendants())do permitted(n);out[#out+1]=wrap(n)end return out end
 function methods:FindFirstChild(name,recursive) local n=raw(self):FindFirstChild(name,recursive);if n then permitted(n);return wrap(n)end return nil end
 function methods:WaitForChild(name) return self:FindFirstChild(name) end -- Fixture-only missing returns nil; never waits on original services.
 function methods:FindFirstChildWhichIsA(class,recursive) local n=raw(self):FindFirstChildWhichIsA(class,recursive);if n then permitted(n);return wrap(n)end return nil end
 methods.FindFirstChildOfClass=methods.FindFirstChildWhichIsA
 function methods:IsDescendantOf(parent) return raw(self):IsDescendantOf(raw(parent)) end
 function methods:GetFullName() return raw(self):GetFullName() end
 function methods:GetAttributes() return raw(self):GetAttributes() end
 function methods:GetAttribute(name) return raw(self):GetAttribute(name) end
 function methods:GetTags() return raw(self):GetTags() end
 function methods:SetAttribute(name,value)quick();permitted(raw(self));raw(self):SetAttribute(name,value);owned[raw(self)].attrs=raw(self):GetAttributes() end
 function methods:GetAttributeChangedSignal(name)return signal(raw(self):GetAttributeChangedSignal(name),raw(self):GetDebugId(16).."/attr/"..name)end
 function methods:GetPropertyChangedSignal(name)return signal(raw(self):GetPropertyChangedSignal(name),raw(self):GetDebugId(16).."/prop/"..name)end
 function methods:GetPivot()return raw(self):GetPivot()end
 function methods:PivotTo(cf)quick();noForeign(raw(self));raw(self):PivotTo(cf);for _,n in ipairs(raw(self):GetDescendants())do if n:IsA("BasePart")then owned[n].props.CFrame=n.CFrame end end end
 function methods:ScaleTo(scale)quick();noForeign(raw(self));raw(self):ScaleTo(scale);for _,n in ipairs(raw(self):GetDescendants())do if n:IsA("BasePart")then owned[n].props.CFrame=n.CFrame;owned[n].props.Size=n.Size end end end
 function methods:GetScale()return raw(self):GetScale()end
 function methods:Clone()
  quick();noForeign(raw(self));check(not raw(self):IsA("LuaSourceContainer"),"Never clone Sourcecontainer")
  for _,n in ipairs(raw(self):GetDescendants())do check(not n:IsA("LuaSourceContainer"),"Never clone Sourcecontainer descendant")end
  local copy=raw(self):Clone();check(copy~=nil,"Owned clone failed")
  ownNative(copy,false);for _,n in ipairs(copy:GetDescendants())do ownNative(n,false)end;recordTree(copy);return wrap(copy)
 end
 function methods:Destroy()
  quick();noForeign(raw(self));local nodes={raw(self),table.unpack(raw(self):GetDescendants())}
  raw(self):Destroy();for _,n in ipairs(nodes)do owned[n].destroyed=true end
 end
 local function queryParams(p)
  local params=RaycastParams.new();params.FilterType=p.FilterType or Enum.RaycastFilterType.Exclude;params.RespectCanCollide=p.RespectCanCollide==true
  local items={}for _,n in ipairs(p.FilterDescendantsInstances or {})do permitted(raw(n));items[#items+1]=raw(n)end
  params.FilterDescendantsInstances=items;return params
 end
 function methods:Raycast(origin,direction,params)
  check(raw(self)==worldModel,"Only owned WorldModel query")
  local hit=worldModel:Raycast(origin,direction,queryParams(params or {}))
  if not hit then return nil end;permitted(hit.Instance)
  return {Instance=wrap(hit.Instance),Position=hit.Position,Normal=hit.Normal,Distance=hit.Distance,Material=hit.Material}
 end
 mt.__index=function(p,key)
  local n=natives[p];permitted(n)
  if methods[key]then return methods[key]end
  check(key~="Source" and key~="LinkedSource" and key~="RunContext","Factory Source escape blocked")
  local value=n[key]
  if typeof(value)=="RBXScriptSignal" then return signal(value,n:GetDebugId(16).."/signal/"..key)end
  if typeof(value)=="Instance" then permitted(value);return wrap(value)end
  check(type(value)~="function","Unreviewed native method escape blocked: "..tostring(key))
  return value
 end
 mt.__newindex=write
 wrap=function(n)
  permitted(n);if not proxies[n]then local p=setmetatable({},mt);proxies[n]=p;natives[p]=n end
  return proxies[n]
 end
 w.raw,w.wrap=raw,wrap;w.workspace=wrap(worldModel)
 local function new(class)local n=makeNative(class);return wrap(n)end
 local function resume(job,...)
  if not w.active or job.done or job.cancelled then return end
  quick();local ok,delay=coroutine.resume(job.thread,...)
  if not ok then job.done=true;error(delay)end
  if coroutine.status(job.thread)=="dead"then job.done=true else check(type(delay)=="number" and delay>=0,"Owned coroutine yielded unexpected result");job.due=w.clock+delay end
 end
 local tasks,threads={},{}
 function tasks.spawn(fn,...)
  local job={thread=coroutine.create(fn),due=w.clock};threads[job.thread]=job;w.jobs[#w.jobs+1]=job;resume(job,...);return job.thread
 end
 function tasks.delay(delay,fn,...)
  check(type(delay)=="number" and delay>=0 and delay<=30,"Bounded owned delay")
  local args=table.pack(...);local job={thread=coroutine.create(function()fn(table.unpack(args,1,args.n))end),due=w.clock+delay}
  threads[job.thread]=job;w.jobs[#w.jobs+1]=job;return job.thread
 end
 function tasks.defer(fn,...)return tasks.delay(0,fn,...)end
 function tasks.wait(seconds)
  check(threads[coroutine.running()]~=nil,"Factory wait must be registered owned coroutine")
  return coroutine.yield(seconds or .03)
 end
 function tasks.cancel(thread)local job=assert(threads[thread],"Unknown owned thread");job.cancelled=true;if coroutine.status(thread)~="dead"then coroutine.close(thread)end end
 function w.advance(seconds)
  local target=w.clock+seconds;local iterations=0
  while true do
   local nextJob=nil for _,job in ipairs(w.jobs)do if not job.done and not job.cancelled and job.due<=target and(not nextJob or job.due<nextJob.due)then nextJob=job end end
   if not nextJob then break end;iterations+=1;check(iterations<10000,"Owned scheduler budget")
   w.clock=math.max(w.clock,nextJob.due);resume(nextJob)
  end
  w.clock=target;NativeTask.wait();guard(false)
  check(#callbackErrors==0,"Owned callback assertion failed")
 end
 function w.fire(p,name,...)
  permitted(raw(p));local label=raw(p):GetDebugId(16).."/signal/"..name
  local count=0 for _,c in ipairs(w.manualSignals[label]or{})do if c.Connected then count+=1;dispatch(c,...)end end
  check(count>0,"Owned callback not connected: "..name);check(#callbackErrors==0,"Owned manual callback failed")
 end
 w.services={Workspace=w.workspace}
 for _,name in ipairs({"ReplicatedStorage","ServerStorage","ServerScriptService","MaterialService"})do local obj=new("Folder");obj.Name=name;obj.Parent=wrap(gui);w.services[name]=obj end
 w.services.Players={GetPlayers=function()return w.players end}
 w.services.TweenService={Create=function(_,p,info,properties)
  quick();permitted(raw(p));local target={}for key,value in pairs(properties)do target[key]=raw(value)end
  local native=TS:Create(raw(p),info,target);local entry={native=native,stopped=false};w.tweens[#w.tweens+1]=entry
  return {Play=function()
   quick();native:Play();native:Cancel();entry.stopped=true
   -- Completion is deterministic property application, not real timing proof.
   for key,value in pairs(properties)do p[key]=value end
  end}
 end}
 local env={game={GetService=function(_,name)return assert(w.services[name],"Unowned service denied: "..name)end},workspace=w.workspace,
  Instance={new=new},task=tasks,typeof=function(v)return if natives[v]then"Instance"else typeof(v)end,
  DateTime={now=function()return{UnixTimestampMillis=w.clock*1000}end},os={clock=function()return w.clock end},
  RaycastParams={new=function()return{}end},warn=function(...)w.warnings[#w.warnings+1]=tostring(...)end}
 local modules={}
 function env.require(p)
  local record=assert(modules[raw(p)],"Unmapped/original require denied")
  if record.value==nil then local callEnv=table.clone(env);callEnv.script=p;record.value=record.factory(callEnv);record.loaded=true end
  return record.value
 end
 function w.module(name,key,parent)
  local p=wrap(assert(probes[key],"Missing fresh factory").object);p.Name=name;p.Parent=parent
  modules[raw(p)]={factory=probes[key].factory};return p
 end
 w.module("ZyntraConfig","config",w.services.ReplicatedStorage)
 w.module("LobbyShopDisplay","shop",w.services.ServerScriptService)
 local builderModule=w.module("TunnelLobbyBuilder","builder",w.services.ServerScriptService)
 w.builder=function()return env.require(builderModule)end
 w.party=function()
  local p=w.module("PartyPort","party",w.services.ServerScriptService);local callEnv=table.clone(env);callEnv.script=p;probes.party.factory(callEnv)
 end
 local values=new("Folder");values.Name="ZyntraDonationLeaderboard";values.Parent=w.services.ReplicatedStorage
 for i=0,10 do local v=new("StringValue");v.Name=if i==0 then"Status"else string.format("Row%02d",i);v.Value=if i==0 then"OWNED PORT READY"else"NO SUPPORT RECORDED YET";v.Parent=values end
 w.leaderboard=values;w.new=new;w.env=env
 return w
end
local FACTORY_PREFIX="return function(env)\nlocal game,workspace,script,Instance,task,require,typeof,DateTime,os,RaycastParams,warn=env.game,env.workspace,env.script,env.Instance,env.task,env.require,env.typeof,env.DateTime,env.os,env.RaycastParams,env.warn\n"
local function stage(key,source,pin)
 guard(false);check(type(source)=="string" and #source==pin.bytes and sha(source)==pin.sha256,"Exact reviewed factory Source")
 local n=ownNative(NativeInstance.new("ModuleScript"),true);n.Name=ROOT_PREFIX.."_"..key;owned[n].name=n.Name
 local body=FACTORY_PREFIX..source.."\nend\n";local entry={object=n,body=body,name=n.Name};probes[key]=entry
 check(n.Parent==nil and #n:GetChildren()==0 and n.Source=="" and SES:GetEditorSource(n)=="","Fresh empty Source/editor only")
 SES:UpdateSourceAsync(n,function(current)
  guard(false);check(n.Parent==nil and n.Name==entry.name and #n:GetChildren()==0 and current=="" and n.Source=="" and SES:GetEditorSource(n)=="","Fresh factory callback CAS")
  if request.fault=="stage"then error("OWNED_STAGE_FAULT")end
  return body
 end)
 guard(false);check(n.Source==body and SES:GetEditorSource(n)==body and n.Parent==nil and #n:GetChildren()==0,"Owned factory staged exactly")
 entry.factory=NativeRequire(n);check(type(entry.factory)=="function","Require returns uncalled factory")
 guard(false);return entry
end
local function nativeR4(w)
 local center=Vector3.new(table.unpack(manifest.previewCenter));local model=w.new("Model");model.Name="LobbyReimaginedPreview";model.Parent=w.workspace
 model:SetAttribute("LobbyReimaginedOwned",true);model:SetAttribute("Ready",true);model:SetAttribute("PreviewCenter",center);model:SetAttribute("R3QueueRevision",3)
 local pads=w.new("Folder");pads.Name="PreviewQueuePads";pads.Parent=model;local bays={}
 for _,spec in ipairs(manifest.bays)do local bay=w.new("Model");bay.Name="QueueBay_Level"..spec.level;bay:SetAttribute("BayCenter",center+Vector3.new(table.unpack(spec.floorPosition)));bay:SetAttribute("CircularBayDiameter",spec.diameter);bay.Parent=pads;bays[spec.level]=bay end
 local selected={Road=true,Sidewalk=true,["Connector Floor"]=true,["Bay Floor"]=true,["Door Threshold"]=true,["Stage Deck"]=true,["Stage Step"]=true}
 local count=0
 for _,spec in ipairs(manifest.colliders)do if not selected[spec.name]then continue end
  local p=w.new("Part");p.Name=spec.name;p.Size=Vector3.new(table.unpack(spec.size));p.Anchored=true;p.CanCollide=true;p.CanQuery=true;p.CanTouch=false
  p.CFrame=CFrame.new(center+Vector3.new(table.unpack(spec.position)))*CFrame.Angles(0,spec.yaw or 0,0)
  if spec.shape=="Cylinder"then p.Shape=Enum.PartType.Cylinder;p.Size=Vector3.new(spec.size[2],spec.size[1],spec.size[3]);p.CFrame*=CFrame.Angles(0,0,math.pi/2)end
  p.Parent=model
  if spec.name=="Bay Floor"then for _,bay in pairs(bays)do if p.Position==bay:GetAttribute("BayCenter")then p.Name="ChamberFloor";p.Parent=bay;break end end end
  count+=1
 end
 check(count>0,"Native R4 manifest floor inventory");return model
end
local function countName(root,name)local count=0 for _,n in ipairs(root:GetDescendants())do if n.Name==name then count+=1 end end return count end
local result={}
local ok,why=xpcall(function()
 initialQueries()
 if request.operation=="query"then result={nativeInitialRay=true,nativeInitialOverlap=true};return end
 for _,key in ipairs({"config","shop","builder","party","board"})do stage(key,request.sources[key],request.pins[key])end
 phases[#phases+1]={name="whole-source-factory-parsers",pass=true,count=5}
 local w=environment();local builder=w.builder();local lobby,spawn,stations
 if request.variant=="before"then lobby,spawn,stations=builder.Build(Vector3.new(0,30,-760))else lobby,spawn,stations=builder.BuildServices(Vector3.new(0,30,-760))end
 if request.fault=="constructor"then error("OWNED_CONSTRUCTOR_FAULT")end
 w.advance(0);check(lobby.Parent==w.workspace and spawn.Parent==lobby,"Canonical owned lobby/spawn")
 check(#stations==(if request.variant=="before" then 16 else 0),"Legacy station contract")
 check(lobby.ZyntraShopDisplay:GetAttribute("ShopItemCount")==10,"Whole current shop native constructor")
 if request.variant=="candidate"then
  local revised=nativeR4(w)
  local callEnv=table.clone(w.env);callEnv.script=w.wrap(probes.board.object)
  local transfer=probes.board.factory(callEnv);local capture=transfer.capture(revised,Vector3.new(220,30,-760));transfer.apply(capture,revised)
  check(capture.Board.Parent==revised,"Same board direct nonnil native transfer")
  NativeTask.wait();guard(false)
  check(builder.AttachServicesToR4(lobby,revised)==true and lobby:GetAttribute("R4ServicesReady")==true,"Actual candidate 27 native floor rays/attach")
  local repeated,problem=pcall(builder.AttachServicesToR4,lobby,revised)
  check(not repeated and tostring(problem):find("already attempted",1,true),"Attach reentry rejects duplication")
  check(#lobby.TunnelGeometry:GetChildren()==0 and countName(lobby,"TunnelReinforcementRib")==0 and countName(lobby,"CeilingServiceTrack")==0,"No old shell/ribs/tracks")
 end
 guard(false);phases[#phases+1]={name="actual-full-constructor-and-current-native-manifest-floors",pass=true}
 local board=assert(w.workspace:FindFirstChild("ZyntraDonationLeaderboardBoard",true));local row=w.leaderboard.Row01
 row:SetAttribute("Rank",1);row:SetAttribute("Name","ALPHA");row:SetAttribute("Robux",123456);NativeTask.wait()
 check(board:FindFirstChild("Rank01",true):FindFirstChild("Name").Text=="ALPHA" and board:FindFirstChild("Rank01",true).Robux.Text=="123,456 R$","Actual native attribute signals render board")
 local signalPrompt=assert(lobby:FindFirstChild("SignalSweepPrompt",true));w.fire(signalPrompt,"Triggered");w.fire(signalPrompt,"Triggered")
 check(lobby:GetAttribute("SignalSweepSerial")==1 and not signalPrompt.Enabled,"Signal callback busy/reentry")
 w.advance(3);check(signalPrompt.Enabled,"Signal callback delayed restore")
 w.fire(signalPrompt,"Triggered");w.advance(3);check(lobby:GetAttribute("SignalSweepSerial")==2,"Signal callback second entry")
 w.party();local partyPrompt=assert(lobby:FindFirstChild("ZyntraPartyPrompt",true));local lighting=lobby.TunnelLighting
 check(countName(lighting,"WarmTunnelLight")==28,"Preserved native active light inventory")
 local target=assert(lighting:FindFirstChild("WarmTunnelLight"));local color=target.Color;local brightness=target:FindFirstChildWhichIsA("Light").Brightness
 w.fire(partyPrompt,"Triggered");w.fire(partyPrompt,"Triggered");check(not partyPrompt.Enabled,"Whole current party callback busy")
 w.advance(1);check(target.Color~=color,"Whole party native Color readback")
 w.advance(11);check(partyPrompt.Enabled and target.Color==color and target:FindFirstChildWhichIsA("Light").Brightness==brightness,"Party exact native property restoration")
 w.fire(partyPrompt,"Triggered");w.fire(signalPrompt,"Triggered");lobby:Destroy();w.advance(12)
 phases[#phases+1]={name="native-connections-and-actual-owned-callback-bodies",pass=true,manualPromptDispatch=true,virtualClock=true,nativeTweenTiming=false}
 result={descendants=#worldModel:GetDescendants(),oldStations=#stations,manifestSHA256=manifestHash,jobs=#w.jobs,connections=#w.connections,tweens=#w.tweens}
end,debug.traceback)
-- Cleanup registry remains available on shared[KEY] if exact ownership fails.
state.active=false
for _,w in ipairs(worlds)do
 w.active=false
 for _,job in ipairs(w.jobs)do if not job.done and not job.cancelled then job.cancelled=true;local good,errorText=pcall(coroutine.close,job.thread);if not good then cleanupErrors[#cleanupErrors+1]=tostring(errorText)end end end
 for _,entry in ipairs(w.tweens)do local good,errorText=pcall(function()entry.native:Cancel();entry.native:Destroy();entry.stopped=true end);if not good then cleanupErrors[#cleanupErrors+1]=tostring(errorText)end end
 for _,connection in ipairs(w.connections)do local good,errorText=pcall(function()connection:Disconnect()end);if not good then cleanupErrors[#cleanupErrors+1]=tostring(errorText)end end
end
local finalGuard,finalWhy=pcall(function()state.active=true;guard(true);state.active=false end)
if not finalGuard then guardErrors[#guardErrors+1]=tostring(finalWhy);state.active=false end
local destroyed,preserved=0,0
-- A partial mode/identity/foreign outcome is retained; it is never treated as cleanup PASS.
local cleanupOrder=table.clone(records)
local function ownedDepth(n)local depth=0;while n.Parent and owned[n.Parent]do depth+=1;n=n.Parent;check(depth<=12000,"Owned hierarchy cycle/budget")end;return depth end
table.sort(cleanupOrder,function(a,b)return ownedDepth(a.object)>ownedDepth(b.object)end)
for _,row in ipairs(cleanupOrder)do
 local n=row.object
 if row.destroyed then destroyed+=1 else
  local safe,reason=pcall(function()
   check(finalGuard,"Native original/mode drift: preserve owned forest for reviewed cleanup")
   check(shared[KEY]==state,"Foreign lease retained")
   check(n.ClassName==row.className and n.Name==row.name and n.Parent==row.parent,"Foreign owned-object identity/Parent edit retained")
   check(sameAttributes(n:GetAttributes(),row.attrs),"Foreign owned-object attributes retained")
   for key,value in pairs(row.props)do check(sameProperty(n[key],value),"Foreign owned-object property retained: "..key)end
   noForeign(n)
   if n:IsA("ModuleScript")then
    local probe=nil for _,entry in pairs(probes)do if entry.object==n then probe=entry;break end end
    check(probe and(n.Source==""or n.Source==probe.body)and SES:GetEditorSource(n)==n.Source,"Foreign probe Source/editor retained")
   end
   -- Never use Destroy(root) to sweep a known foreign descendant.
   check(#n:GetChildren()==0,"Owned parent with retained child preserved")
   n:Destroy();row.destroyed=true
  end)
  if safe then destroyed+=1 else preserved+=1;cleanupErrors[#cleanupErrors+1]=tostring(reason)end
 end
end
local jobs,connections,tweens=0,0,0
for _,w in ipairs(worlds)do for _,job in ipairs(w.jobs)do if not job.done and not job.cancelled then jobs+=1 end end;for _,c in ipairs(w.connections)do if c.Connected then connections+=1 end end;for _,t in ipairs(w.tweens)do if not t.stopped then tweens+=1 end end end
local postGuard,postWhy=pcall(function()state.active=true;guard(true);state.active=false end)
if not postGuard then guardErrors[#guardErrors+1]=tostring(postWhy);state.active=false end
local released=shared[KEY]==state and preserved==0 and #cleanupErrors==0
if released then shared[KEY]=nil else state.phase="retained-after-failure";state.reason=why end
local expectedCallback=request.fault=="callback"and #callbackErrors==1 and callbackErrors[1]:find("OWNED_CALLBACK_FAULT",1,true)~=nil
local expectedFailure=request.fault~="none" and not ok and(tostring(why):find("OWNED_"..string.upper(request.fault).."_FAULT",1,true)~=nil or expectedCallback)
return H:JSONEncode({schema="mongotv-lobby-owned-native-result-v1",pass=(ok or expectedFailure)and finalGuard and postGuard and released and jobs==0 and connections==0 and tweens==0 and(#callbackErrors==0 or expectedCallback),
 variant=request.variant,fault=request.fault,expectedFailureObserved=expectedFailure,executionPassed=ok,error=if ok then nil else tostring(why),checks=checks,phases=phases,result=result,
 cleanup={registered=#records,destroyed=destroyed,preserved=preserved,remainingJobs=jobs,remainingConnections=connections,remainingTweens=tweens,errors=cleanupErrors,leaseReleased=released},
 originalGuardsPassed=finalGuard and postGuard,guardErrors=guardErrors,callbackErrors=callbackErrors,originalSourceCoverage=request.nativeScriptCount,
 originalSourceWrites=0,originalParentWrites=0,originalPropertyWrites=0,modeSwitches=0,productionEligible=false,readAtUtc=DateTime.now():ToIsoDate(),
 limits="Owned native WorldModel/manifest floor/property/signal callback-body port. Fixture-only no native template clones. Synthetic players absent, manual prompt dispatch, owned virtual coroutine clock, Tween cancelled then properties applied deterministically. No full R4 bake, real UI/input/touch/character navigation, actual gameplay, multiplayer, streaming, reserved teleport, economy or performance pass."})
