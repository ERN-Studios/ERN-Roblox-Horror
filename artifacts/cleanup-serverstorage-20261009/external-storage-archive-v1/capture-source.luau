-- S06 read-only preservation of 23 originals unparented by another actor.
-- No parent/property/source writes, new Instances, cloning, Destroy or modeswitch.
local HS=game:GetService("HttpService")
local SER=game:GetService("SerializationService")
local ENC=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local REF=game:GetService("ReflectionService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local BASE="http://127.0.0.1:18913"
local KEY="__MongoTVExternalStorageArchive20261009"
local ORIGINAL_KEY="__MongoTVStorageCleanup20261009"
local SCHEMA="external-held-storage-archive-v1"
local MAX_NODES=25000
local MAX_PROPERTIES=500000
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
assert(not RS:IsRunning() and HS.HttpEnabled,"Edit/existing HTTP required")
local state=assert(shared[ORIGINAL_KEY],"held originals no longer available")
assert(state.rootRefs and state.scriptRefs and not state.probeLease and not state.portLease,"original state in use")
assert(state.storagePort==nil,"S01 port unexpectedly exists; re-review attribution/scope")
assert(shared[KEY]==nil,"external archive already running or requires explicit release")
local lease={} shared[KEY]=lease
local connections,roots,nodes,nodeRows,liveSources,heldSources,liveRoots={},{},{},{},{},{},{}
local epoch=0
local currentCount=0
local checks=0
local report={schema=SCHEMA,pass=false,nativeMutations=0,sourceWrites=0,modeSwitches=0,
 restorationCertified=false,removalAttributedToCleanup=false,
 opaqueSerializedProperties={},externalSerializedReferences={},dynamicObjectContent={},
 limits="Read-only raw native backup and concurrency evidence; offline reopen/native restoration/assets/reference completeness are separate ports. No deletion, UI, gameplay or performance certification."}
local function check(ok,message) assert(ok,message) checks+=1 end
local function owned()
 return shared[KEY]==lease and shared[ORIGINAL_KEY]==state
  and not state.probeLease and not state.portLease and state.storagePort==nil and not RS:IsRunning()
end
local function sha(raw)
 local value=ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256)
 local output={} for i=0,buffer.len(value)-1 do output[i+1]=string.format("%02x",buffer.readu8(value,i)) end
 return table.concat(output)
end
local function same(a,b)
 if typeof(a)~=typeof(b) then return false end
 if typeof(a)~="table" then return a==b end
 for k,v in a do if not same(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end
 return true
end
local function tags(s)
 local result=s:GetTags() table.sort(result) return result
end
local function typed(v)
 local kind=typeof(v)
 if kind=="string" or kind=="number" or kind=="boolean" then return {type=kind,value=v} end
 if kind=="Vector2" then return {type=kind,value={v.X,v.Y}} end
 if kind=="Vector3" then return {type=kind,value={v.X,v.Y,v.Z}} end
 if kind=="Color3" then return {type=kind,value={v.R,v.G,v.B}} end
 if kind=="CFrame" then return {type=kind,value={v:GetComponents()}} end
 if kind=="UDim" then return {type=kind,value={v.Scale,v.Offset}} end
 if kind=="UDim2" then return {type=kind,value={v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset}} end
 if kind=="Rect" then return {type=kind,value={v.Min.X,v.Min.Y,v.Max.X,v.Max.Y}} end
 if kind=="NumberRange" then return {type=kind,value={v.Min,v.Max}} end
 if kind=="BrickColor" then return {type=kind,value=v.Number} end
 if kind=="NumberSequence" then
  local values={} for _,p in v.Keypoints do table.insert(values,{p.Time,p.Value,p.Envelope}) end
  return {type=kind,value=values}
 end
 if kind=="ColorSequence" then
  local values={} for _,p in v.Keypoints do table.insert(values,{p.Time,p.Value.R,p.Value.G,p.Value.B}) end
  return {type=kind,value=values}
 end
 return {type=kind,display=tostring(v),nativeOnly=true}
end
local function typedAttrs(values)
 local result={} for k,v in values do result[k]=typed(v) end return result
end
local function scriptRow(s)
 local source=s.Source
 check(SES:GetEditorSource(s)==source,"Source/editor mismatch: "..s:GetFullName())
 local properties={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
 if s:IsA("BaseScript") then
  properties.Enabled=s.Enabled properties.Disabled=s.Disabled properties.RunContext=tostring(s.RunContext)
 end
 return {path=s:GetFullName(),class=s.ClassName,parent=s.Parent,source=source,
  properties=properties,attributes=s:GetAttributes(),tags=tags(s)}
end
local function watch(signal)
 table.insert(connections,signal:Connect(function() epoch+=1 end))
end
local function watchNode(s)
 watch(s.Changed) watch(s.AttributeChanged)
end
local function postParts(kind,raw)
 local count=math.ceil(#raw/750000)
 check(count>0 and count<1000,"transfer size bound exceeded")
 for i=0,count-1 do
  check(owned() and epoch==0,"archive changed during transfer")
  check(HS:PostAsync(BASE.."/"..kind.."/"..i,string.sub(raw,i*750000+1,(i+1)*750000),Enum.HttpContentType.TextPlain)=="saved","archive receiver rejected chunk")
 end
 return {parts=count,bytes=#raw,sha256=sha(buffer.fromstring(raw))}
end
local function guard()
 check(owned() and epoch==0,"archive lease/mode/epoch changed")
 check(#game:GetDescendants()==currentCount,"live instance census changed")
 local seen={}
 for _,f in SS:GetChildren() do
  local row=liveRoots[f]
  check(row and f.Name==row.name and f.ClassName==row.class and f.Archivable==row.archivable
   and same(f:GetAttributes(),row.attributes) and same(tags(f),row.tags),"live root changed")
  seen[f]=true
 end
 for f in liveRoots do check(seen[f] and f.Parent==SS,"live root removed/moved") end
 for _,f in roots do
  local original=state.rootRefs[f]
  check(original and f.Parent==nil and not f:IsDescendantOf(game)
   and f.Name==original.name and f.ClassName==original.class,"held root changed")
  for _,live in SS:GetChildren() do check(live.Name~=f.Name,"same-name live root appeared") end
 end
 for s,row in liveSources do check(s.Parent and s:IsDescendantOf(game) and same(scriptRow(s),row),"live original Source/properties changed") end
 for s,row in heldSources do check(not s:IsDescendantOf(game) and same(scriptRow(s),row),"held original Source/properties changed") end
 for i,s in nodes do
  local row=nodeRows[s]
  check(s.Parent==row.parent and s.Name==row.name and s.ClassName==row.class
   and s.Archivable and s.Sandboxed==false and same(s:GetAttributes(),row.attributes)
   and same(tags(s),row.tags) and #s:GetChildren()==row.children,"held hierarchy changed")
  for _,slot in row.properties do
   local readable,current=pcall(function() return s[slot.name] end)
   check(readable==slot.read,"held serialized property readability changed")
   check(if readable then current==slot.value else tostring(current)==slot.error,
    "held serialized property changed: "..row.path.."."..slot.name)
  end
  if i%500==0 then task.wait() check(owned() and epoch==0,"archive changed during guard yield") end
 end
 check(owned() and epoch==0,"archive changed after guard")
end
local context,archive,native
local ok,why=xpcall(function()
 watch(game.DescendantAdded) watch(game.DescendantRemoving)
 watch(SS.ChildAdded) watch(SS.ChildRemoved)
 context=HS:JSONDecode(HS:GetAsync(BASE.."/context",true))
 check(context.schema==SCHEMA and #context.roots==23,"wrong exact archive context")
 local expected={} for _,r in context.roots do
  check(type(r.name)=="string" and not expected[r.name] and r.currentParent=="nil"
   and r.sameNameLive==false,"invalid observed root set")
  expected[r.name]=r
 end
 local missing=0
 for f,row in state.rootRefs do
  if f.Parent==nil then
   local observed=expected[row.name]
   check(observed and f.Name==row.name and f.ClassName==row.class and row.class==observed.class
    and #f:GetChildren()==observed.children,"held original differs from reviewed observation")
   roots[#roots+1]=f missing+=1
  else check(f.Parent==SS,"previous root was moved elsewhere; re-review closure") end
 end
 check(missing==23,"held set is not exactly23 reviewed originals")
 table.sort(roots,function(a,b) return a.Name<b.Name end)
 for _,f in SS:GetChildren() do
  liveRoots[f]={name=f.Name,class=f.ClassName,archivable=f.Archivable,attributes=f:GetAttributes(),tags=tags(f)}
  watchNode(f)
 end
 local census=game:GetDescendants() currentCount=#census
 for i,s in census do
  if s:IsA("LuaSourceContainer") then liveSources[s]=scriptRow(s) watchNode(s) end
  if i%1000==0 then task.wait() check(owned() and epoch==0,"live baseline changed") end
 end
 local rootMetadata={}
 for _,root in roots do
  watch(root.DescendantAdded) watch(root.DescendantRemoving)
  local subtree={root} for _,s in root:GetDescendants() do subtree[#subtree+1]=s end
  rootMetadata[#rootMetadata+1]={name=root.Name,class=root.ClassName,children=#root:GetChildren(),
   nodes=#subtree,parentIsNil=true,originalHeldReference=true}
  for _,s in subtree do
   check(nodeRows[s]==nil,"overlapping/duplicate held tree")
   check(s.Archivable and s.Sandboxed==false,"non-Archivable or Sandboxed node: "..s:GetFullName())
   nodes[#nodes+1]=s check(#nodes<=MAX_NODES,"held node bound exceeded")
   nodeRows[s]={name=s.Name,class=s.ClassName,parent=s.Parent,path=s:GetFullName(),
    children=#s:GetChildren(),attributes=s:GetAttributes(),tags=tags(s),properties={}}
   watchNode(s)
   if s:IsA("LuaSourceContainer") then
    local current=scriptRow(s)
    local before=assert(state.scriptRefs[s],"held source absent from v8 original snapshot")
    check(current.source==before.source and current.class==before.class
     and same(current.properties,before.properties) and same(current.attributes,before.attributes),"held source changed from v8")
    heldSources[s]=current
   end
   if #nodes%500==0 then task.wait() check(owned() and epoch==0,"held baseline changed") end
  end
 end
 local classes={}
 local caps=SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
 local metadata={}
 local propertiesRead=0
 for i,s in nodes do
  local row=nodeRows[s]
  local props=classes[s.ClassName]
  if not props then
   props={}
   local reflected=assert(REF:GetPropertiesOfClass(s.ClassName,{Security=caps,ExcludeInherited=false,ExcludeDisplay=true}),"unreflected held class")
   for _,p in reflected do if p.Serialized==true and p.Name~="Parent" then props[#props+1]=p end end
   classes[s.ClassName]=props
  end
  local values={}
  for _,p in props do
   propertiesRead+=1 check(propertiesRead<=MAX_PROPERTIES,"serialized property bound exceeded")
   local read,value=pcall(function() return s[p.Name] end)
   row.properties[#row.properties+1]={name=p.Name,read=read,value=if read then value else nil,
    error=if read then nil else tostring(value)}
   if read then
    if p.Name=="Source" then values[p.Name]={type="string",sourceSHA256=sha(buffer.fromstring(value)),bytes=#value,nativeOnly=true}
    elseif typeof(value)=="Instance" then
     local internal=nodeRows[value]~=nil
     values[p.Name]={type="Instance",path=value:GetFullName(),class=value.ClassName,internal=internal}
     if not internal then report.externalSerializedReferences[#report.externalSerializedReferences+1]={owner=row.path,property=p.Name,target=value:GetFullName(),class=value.ClassName} end
    else
     values[p.Name]=typed(value)
     if typeof(value)=="Content" then
      local readable,kind=pcall(function() return tostring(value.SourceType) end)
      if readable and string.find(kind,"Object",1,true) then
       report.dynamicObjectContent[#report.dynamicObjectContent+1]={owner=row.path,property=p.Name,sourceType=kind}
      end
     end
    end
   else
    report.opaqueSerializedProperties[#report.opaqueSerializedProperties+1]={path=row.path,property=p.Name,error=tostring(value)}
   end
  end
  metadata[#metadata+1]={path=row.path,name=row.name,class=row.class,children=row.children,
   archivable=true,sandboxed=false,tags=row.tags,attributes=typedAttrs(row.attributes),properties=values}
  if i%500==0 then task.wait() check(owned() and epoch==0,"property census changed") end
 end
 guard()
 native=SER:SerializeInstancesAsync(roots) -- Any unsupported native content is a blocker; no workaround writes.
 guard()
 local nativeHash=sha(native)
 local sourceMetadata={}
 for s,row in heldSources do
  sourceMetadata[#sourceMetadata+1]={path=row.path,pathBefore=state.scriptRefs[s].path,class=row.class,
   bytes=#row.source,sourceSHA256=sha(buffer.fromstring(row.source)),editorMatchesSource=true,sourceMatchesV8=true}
 end
 table.sort(sourceMetadata,function(a,b) return a.path<b.path end)
 check(#sourceMetadata==#context.heldOutOfGameSources and #sourceMetadata==12,"held source count differs")
 local observedSources={} for _,row in context.heldOutOfGameSources do observedSources[row.pathCurrent]=row end
 for _,row in sourceMetadata do
  local observed=observedSources[row.path]
  check(observed and observed.sourceSHA256==row.sourceSHA256 and observed.sourceBytes==row.bytes,"held source differs from persisted observation")
 end
 local liveSourceCount=0 for _ in liveSources do liveSourceCount+=1 end
 archive={schema=SCHEMA,placeId=game.PlaceId,universeId=game.GameId,capturedAtUtc=DateTime.now():ToIsoDate(),
  nativeBytes=buffer.len(native),nativeSHA256=nativeHash,roots=rootMetadata,nodes=metadata,heldSources=sourceMetadata,
  liveSourceCount=liveSourceCount,liveRootCount=#SS:GetChildren(),liveDescendants=currentCount,heldNodeCount=#nodes,
  propertiesRead=propertiesRead,observationSHA256=context.observationSHA256,
  opaqueSerializedProperties=report.opaqueSerializedProperties,externalSerializedReferences=report.externalSerializedReferences,
  dynamicObjectContent=report.dynamicObjectContent,nativeMutations=0,sourceWrites=0,modeSwitches=0,
  removalAttributedToCleanup=false,restorationCertified=false,limits=report.limits}
 local transfer={native=postParts("native",buffer.tostring(native)),facts=postParts("facts",HS:JSONEncode(archive))}
 guard()
 -- Rehash the complete native forest after HTTP yields to cover opaque serialized data.
 local after=SER:SerializeInstancesAsync(roots)
 guard()
 check(sha(after)==nativeHash,"native forest changed during transfer")
 check(HS:PostAsync(BASE.."/finalize",HS:JSONEncode(transfer),Enum.HttpContentType.ApplicationJson)=="saved","archive not finalized")
 guard()
 report.nativeSHA256=nativeHash report.nativeBytes=buffer.len(native) report.roots=#roots
 report.heldNodes=#nodes report.heldSources=#sourceMetadata report.liveSources=liveSourceCount
 report.liveRoots=#SS:GetChildren() report.propertiesRead=propertiesRead
end,debug.traceback)
for i,connection in connections do
 local clean,reason=pcall(function() connection:Disconnect() end)
 if not clean then ok=false why=tostring(why).."\nwatcher cleanup failed: "..tostring(reason) end
 if i%500==0 then task.wait() end
end
if ok then
 local valid,reason=pcall(guard)
 if not valid then ok=false why="post-cleanup originals guard: "..tostring(reason) end
end
report.pass=ok report.error=if ok then nil else tostring(why)
report.checks=checks report.capturedAtUtc=DateTime.now():ToIsoDate()
for _,name in {"opaqueSerializedProperties","externalSerializedReferences","dynamicObjectContent"} do
 local rows=report[name]
 report[name.."Count"]=#rows
 local sample={} for i=1,math.min(#rows,10) do sample[i]=rows[i] end
 report[name]=sample -- Full evidence is immutable facts.json, not an oversized MCP response.
end
if shared[KEY]==lease then shared[KEY]=nil end -- Preserve any foreign archive lease/state.
return HS:JSONEncode(report)
