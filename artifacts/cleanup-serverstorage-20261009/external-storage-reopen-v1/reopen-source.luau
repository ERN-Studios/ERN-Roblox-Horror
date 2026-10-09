-- S06 engine reopen of a pinned native archive, in an owned unparented forest.
-- Never writes original Source/Parent/properties; never stages an editor source.
local HS=game:GetService("HttpService")
local SER=game:GetService("SerializationService")
local ENC=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local REF=game:GetService("ReflectionService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local BASE="http://127.0.0.1:18915"
local KEY="__MongoTVExternalStorageReopen20261009"
local ORIGINAL_KEY="__MongoTVStorageCleanup20261009"
local CAPTURE_KEY="__MongoTVExternalStorageArchive20261009"
local SCHEMA="external-held-storage-native-reopen-v1"
local MAX_NODES=25000
local MAX_PROPERTIES=500000
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning(),"wrong place/Edit")
assert(HS.HttpEnabled,"existing HTTP required")
local state=assert(shared[ORIGINAL_KEY],"held originals unavailable")
assert(state.rootRefs and state.scriptRefs and not state.probeLease and not state.portLease and state.storagePort==nil,"original state in use/changed")
assert(shared[KEY]==nil and shared[CAPTURE_KEY]==nil,"archive/reopen already active")
local lease={} shared[KEY]=lease
local roots,copies,nodes,rows,liveSources,heldSources,liveRoots,connections={},{},{},{},{},{},{},{}
local copyOwnedNodes={}
local epoch,currentCount,checks=0,0,0
local sourceBaselineComplete=false
local report={schema=SCHEMA,pass=false,createdRoots=0,destroyedRoots=0,sourceWrites=0,originalParentWrites=0,
 modeSwitches=0,removalAttributedToCleanup=false,restorationCertified=false,
 limits="Owned off-place native deserialize/readable data/internal referents/raw reserialization only. Protected serialized properties remain opaque when raw bytes differ. External assets, UI workflows, gameplay and performance are not certified."}
local function check(value,message) assert(value,message) checks+=1 end
local function owned()
 return shared[KEY]==lease and shared[ORIGINAL_KEY]==state and not state.probeLease and not state.portLease
  and state.storagePort==nil and shared[CAPTURE_KEY]==nil and not RS:IsRunning()
end
local function sha(raw)
 local value=ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256)
 local result={} for i=0,buffer.len(value)-1 do result[i+1]=string.format("%02x",buffer.readu8(value,i)) end
 return table.concat(result)
end
local function canonical(value)
 local kind=typeof(value)
 if kind=="nil" then return "nil" end
 if kind=="boolean" then return if value then "true" else "false" end
 if kind=="number" then return "n"..string.format("%.17g",value) end
 if kind=="string" then return "s"..#value..":"..value end
 if kind=="table" then
  local keys={} for k in value do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return canonical(a)<canonical(b) end)
  local result={"{"} for _,k in keys do result[#result+1]=canonical(k)..canonical(value[k]) end
  result[#result+1]="}" return table.concat(result)
 end
 if kind=="Vector2" then return canonical({kind,value.X,value.Y}) end
 if kind=="Vector3" then return canonical({kind,value.X,value.Y,value.Z}) end
 if kind=="Color3" then return canonical({kind,value.R,value.G,value.B}) end
 if kind=="CFrame" then return canonical({kind,value:GetComponents()}) end
 if kind=="UDim" then return canonical({kind,value.Scale,value.Offset}) end
 if kind=="UDim2" then return canonical({kind,value.X.Scale,value.X.Offset,value.Y.Scale,value.Y.Offset}) end
 if kind=="Rect" then return canonical({kind,value.Min.X,value.Min.Y,value.Max.X,value.Max.Y}) end
 if kind=="NumberRange" then return canonical({kind,value.Min,value.Max}) end
 if kind=="BrickColor" then return canonical({kind,value.Number}) end
 if kind=="NumberSequence" then
  local values={kind} for _,p in value.Keypoints do values[#values+1]={p.Time,p.Value,p.Envelope} end return canonical(values)
 end
 if kind=="ColorSequence" then
  local values={kind} for _,p in value.Keypoints do values[#values+1]={p.Time,p.Value.R,p.Value.G,p.Value.B} end return canonical(values)
 end
 -- EnumItem/Capabilities/Content and other opaque datatypes retain type+display.
 -- This display check does not certify their hidden native state.
 return canonical({kind,tostring(value)})
end
local function tags(s) local t=s:GetTags() table.sort(t) return t end
local function scriptRow(s)
 local source=s.Source
 check(SES:GetEditorSource(s)==source,"authoritative Source/editor mismatch: "..s:GetFullName())
 local p={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
 if s:IsA("BaseScript") then p.Enabled=s.Enabled p.Disabled=s.Disabled p.RunContext=tostring(s.RunContext) end
 return {path=s:GetFullName(),class=s.ClassName,parent=s.Parent,source=source,properties=p,attributes=s:GetAttributes(),tags=tags(s)}
end
local function scriptMatches(s,row)
 local current=scriptRow(s)
 return current.parent==row.parent and current.path==row.path and current.class==row.class and current.source==row.source
  and canonical(current.properties)==canonical(row.properties) and canonical(current.attributes)==canonical(row.attributes)
  and canonical(current.tags)==canonical(row.tags)
end
local function watch(signal)
 check(#connections<60000,"watcher bound exceeded")
 connections[#connections+1]=signal:Connect(function() epoch+=1 end)
end
local function watchNode(s) watch(s.Changed) watch(s.AttributeChanged) end
local classes={}
local caps
local function properties(class)
 if classes[class] then return classes[class] end
 local result={}
 local reflected=assert(REF:GetPropertiesOfClass(class,{Security=caps,ExcludeInherited=false,ExcludeDisplay=true}),"unreflected held class")
 for _,p in reflected do if p.Serialized==true and p.Name~="Parent" then result[#result+1]=p.Name end end
 table.sort(result) classes[class]=result return result
end
local function liveGuard()
 check(owned() and epoch==0,"lease/Edit/foreign epoch changed")
 check(#game:GetDescendants()==currentCount,"live native census changed")
 local seen={}
 for _,f in SS:GetChildren() do
  local row=liveRoots[f]
  check(row and canonical({f.Name,f.ClassName,f.Archivable,f:GetAttributes(),tags(f)})==row,"live ServerStorage root changed") seen[f]=true
 end
 for f in liveRoots do check(seen[f] and f.Parent==SS,"live ServerStorage root moved") end
 for _,f in roots do
  local before=state.rootRefs[f]
  check(before and f.Parent==nil and not f:IsDescendantOf(game) and f.Name==before.name and f.ClassName==before.class,"held root changed")
  for _,live in SS:GetChildren() do check(live.Name~=f.Name,"same-name live root appeared") end
 end
 for s,row in liveSources do check(s:IsDescendantOf(game) and scriptMatches(s,row),"live Source/properties changed") end
 for s,row in heldSources do check(not s:IsDescendantOf(game) and scriptMatches(s,row),"held Source/properties changed") end
end
local function originals()
 liveGuard()
 for i,s in nodes do
  local row=rows[s]
  check(s.Parent==row.parent and canonical({s.Name,s.ClassName,s.Archivable,s.Sandboxed,s:GetAttributes(),tags(s)})==row.basic
   and #s:GetChildren()==#row.children,"held hierarchy/metadata changed")
  for _,slot in row.slots do
   local readable,current=pcall(function() return s[slot.name] end)
   check(readable==slot.read and (if readable then current==slot.value else tostring(current)==slot.error),"held serialized property changed: "..row.path.."."..slot.name)
  end
  if i%500==0 then task.wait() check(owned() and epoch==0,"foreign change during original guard") end
 end
 liveGuard()
end
local function forestSnapshot(forest,original)
 local treeNodes,nodeRows,pathCounts={}, {}, {}
 local propertyReads,opaque,refs=0,0,{}
 -- Explicit preorder makes the reverse traversal a safe bottom-up tree digest.
 local stack={} for i=#forest,1,-1 do stack[#stack+1]=forest[i] end
 while #stack>0 do
  local s=table.remove(stack)
  check(nodeRows[s]==nil,"overlapping native forest")
  if not original then check(copyOwnedNodes[s] and rows[s]==nil,"native copy identity overlaps original or escaped ownership") end
  check(not s:IsDescendantOf(game) and s.Archivable and s.Sandboxed==false,"forest escaped ownership/non-Archivable/Sandboxed")
  local children=s:GetChildren()
  local row={path=s:GetFullName(),parent=s.Parent,children=children,
   basic=canonical({s.Name,s.ClassName,s.Archivable,s.Sandboxed,s:GetAttributes(),tags(s)}),slots={}}
  treeNodes[#treeNodes+1]=s nodeRows[s]=row check(#treeNodes<=MAX_NODES,"node bound exceeded")
  pathCounts[row.path]=(pathCounts[row.path] or 0)+1
  for i=#children,1,-1 do stack[#stack+1]=children[i] end
  if original then watchNode(s) end
  local digestValues={basic=row.basic,properties={}}
  for _,name in properties(s.ClassName) do
   propertyReads+=1 check(propertyReads<=MAX_PROPERTIES,"serialized property bound exceeded")
   local read,value=pcall(function() return s[name] end)
   if original then row.slots[#row.slots+1]={name=name,read=read,value=if read then value else nil,error=if read then nil else tostring(value)} end
   if not read then opaque+=1 digestValues.properties[name]={read=false}
   elseif name=="Source" then digestValues.properties[name]={read=true,sourceSHA256=sha(buffer.fromstring(value)),bytes=#value}
   elseif typeof(value)=="Instance" then
    refs[#refs+1]={owner=s,property=name,target=value}
    digestValues.properties[name]={read=true,kind="Instance",targetPath=value:GetFullName(),class=value.ClassName}
   else digestValues.properties[name]={read=true,value=canonical(value)} end
  end
  row.localHash=sha(buffer.fromstring(canonical(digestValues)))
  if #treeNodes%500==0 then task.wait() check(owned() and epoch==0,"foreign change during forest census") end
 end
 for _,ref in refs do
  check(nodeRows[ref.target]~=nil,"readable reference escaped joint forest")
  check(pathCounts[nodeRows[ref.owner].path]==1 and pathCounts[nodeRows[ref.target].path]==1,"ambiguous readable referent; cannot prove exact topology")
 end
 for i=#treeNodes,1,-1 do
  local row=nodeRows[treeNodes[i]] local children={}
  for _,child in row.children do children[#children+1]=assert(nodeRows[child]).treeHash end
  table.sort(children)
  row.treeHash=sha(buffer.fromstring(canonical({row.localHash,children})))
  if i%500==0 then task.wait() check(owned() and epoch==0,"foreign change during tree digest") end
 end
 local summaries={}
 for _,f in forest do
  check(f.Parent==nil,"native top root is parented")
  summaries[#summaries+1]={name=f.Name,class=f.ClassName,children=#f:GetChildren(),treeSHA256=nodeRows[f].treeHash}
 end
 table.sort(summaries,function(a,b) return a.name<b.name end)
 local refRows={}
 for _,ref in refs do refRows[#refRows+1]=canonical({nodeRows[ref.owner].path,ref.property,nodeRows[ref.target].path}) end
 table.sort(refRows)
 return {nodes=treeNodes,rows=nodeRows,roots=summaries,propertiesRead=propertyReads,opaqueGetters=opaque,
  references=#refs,referenceSHA256=sha(buffer.fromstring(canonical(refRows)))}
end
local function postParts(raw)
 local count=math.ceil(#raw/750000) check(count>0 and count<1000,"roundtrip bound exceeded")
 for i=0,count-1 do
  liveGuard()
  check(HS:PostAsync(BASE.."/roundtrip/"..i,string.sub(raw,i*750000+1,(i+1)*750000),Enum.HttpContentType.TextPlain)=="saved","roundtrip receiver rejected chunk")
 end
 return {parts=count,bytes=#raw,sha256=sha(buffer.fromstring(raw))}
end
local context,originalSnapshot
local ok,why=xpcall(function()
 caps=SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
 watch(game.DescendantAdded) watch(game.DescendantRemoving) watch(SS.ChildAdded) watch(SS.ChildRemoved)
 context=HS:JSONDecode(HS:GetAsync(BASE.."/context",true))
 check(context.schema==SCHEMA and #context.roots==23 and #context.heldSources==12,"wrong archive context")
 local expected={} for _,r in context.roots do check(not expected[r.name],"duplicate expected root") expected[r.name]=r end
 for f,before in state.rootRefs do
  if f.Parent==nil then
   local row=expected[f.Name]
   check(row and before.name==f.Name and row.class==f.ClassName and row.children==#f:GetChildren(),"held original differs from archive")
   roots[#roots+1]=f watch(f.DescendantAdded) watch(f.DescendantRemoving)
  else check(f.Parent==SS,"old root moved elsewhere") end
 end
 check(#roots==23,"held root closure changed") table.sort(roots,function(a,b) return a.Name<b.Name end)
 for _,f in SS:GetChildren() do liveRoots[f]=canonical({f.Name,f.ClassName,f.Archivable,f:GetAttributes(),tags(f)}) watchNode(f) end
 local census=game:GetDescendants() currentCount=#census
 for i,s in census do
  if s:IsA("LuaSourceContainer") then liveSources[s]=scriptRow(s) watchNode(s) end
  if i%1000==0 then task.wait() check(owned() and epoch==0,"live baseline changed") end
 end
 local expectedSources={} for _,row in context.heldSources do check(not expectedSources[row.path],"duplicate expected Source path") expectedSources[row.path]=row end
 for _,root in roots do for _,s in root:GetDescendants() do if s:IsA("LuaSourceContainer") then
  local row=scriptRow(s) local before=assert(state.scriptRefs[s],"held Source no v8 baseline") local expectedRow=expectedSources[row.path]
  check(expectedRow and row.source==before.source and row.class==before.class and sha(buffer.fromstring(row.source))==expectedRow.sourceSHA256
   and #row.source==expectedRow.bytes,"held Source differs from native archive/v8") heldSources[s]=row
 end end end
 local heldCount=0 for _ in heldSources do heldCount+=1 end check(heldCount==12,"held Source count changed")
 sourceBaselineComplete=true
 originalSnapshot=forestSnapshot(roots,true) nodes=originalSnapshot.nodes rows=originalSnapshot.rows
 check(#nodes==context.heldNodeCount,"archive node count changed") originals()
 local parts={} check(context.nativeParts>0 and context.nativeParts<1000,"native part bound")
 for i=0,context.nativeParts-1 do parts[#parts+1]=HS:GetAsync(BASE.."/native/"..i,true) liveGuard() end
 local raw=buffer.fromstring(table.concat(parts))
 check(buffer.len(raw)==context.nativeBytes and sha(raw)==context.nativeSHA256,"archive transport hash mismatch")
 originals()
 local fresh=SER:SerializeInstancesAsync(roots)
 originals() check(sha(fresh)==context.nativeSHA256,"held native forest changed since raw archive")
 copies=SER:DeserializeInstancesAsync(raw) -- Native engine, never a cloned editor staging container.
 report.createdRoots=#copies
 for _,f in copies do
  check(rows[f]==nil and f.Parent==nil,"deserialize returned original/parented root")
  copyOwnedNodes[f]=true
  for _,s in f:GetDescendants() do check(rows[s]==nil,"deserialize hierarchy contains original") copyOwnedNodes[s]=true end
 end
 -- Guard authoritative editors immediately after native creation, before any copy inspection/cleanup.
 originals()
 check(#copies==23,"engine returned wrong top-root count")
 local snapshot=forestSnapshot(copies,false)
 report.readableDataPass=#snapshot.nodes==#nodes and canonical(snapshot.roots)==canonical(originalSnapshot.roots)
 check(snapshot.references==originalSnapshot.references and snapshot.referenceSHA256==originalSnapshot.referenceSHA256,"joint internal referents differ")
 local copySources=0
 for _,s in snapshot.nodes do if s:IsA("LuaSourceContainer") then
  local expectedRow=assert(expectedSources[s:GetFullName()],"unexpected reconstructed Source")
  check(s.ClassName==expectedRow.class and sha(buffer.fromstring(s.Source))==expectedRow.sourceSHA256 and #s.Source==expectedRow.bytes,"reconstructed Source differs") copySources+=1
 end end
 check(copySources==12,"reconstructed Source count differs") originals()
 local roundtrip=SER:SerializeInstancesAsync(copies)
 originals()
 local transfer=postParts(buffer.tostring(roundtrip))
 originals()
 check(HS:PostAsync(BASE.."/finalize",HS:JSONEncode(transfer),Enum.HttpContentType.ApplicationJson)=="saved","roundtrip not finalized")
 originals()
 report.internalReferencesPass=true report.reconstructedNodes=#snapshot.nodes
 report.reconstructedSources=copySources report.referenceProperties=snapshot.references
 report.propertiesRead=snapshot.propertiesRead report.opaqueGetters=snapshot.opaqueGetters
 report.archiveSHA256=context.nativeSHA256 report.roundtripSHA256=transfer.sha256 report.roundtripBytes=transfer.bytes
 report.nativeSerializedBytesExact=transfer.sha256==context.nativeSHA256 and transfer.bytes==context.nativeBytes
 report.readableRootTrees=snapshot.roots
 report.originalReadableRootTrees=originalSnapshot.roots
 local n=0 for _ in liveSources do n+=1 end report.liveSources=n report.liveRoots=#SS:GetChildren()
 -- Preserve diagnostic native bytes even when an exact readable-property digest fails.
 check(report.readableDataPass,"readable native property/subtree reconstruction differs; complete roundtrip retained")
end,debug.traceback)
-- Independently clean only returned unparented copies; no original Destroy/restore.
for _,f in copies do
 local clean,reason=pcall(function()
  check(rows[f]==nil and f.Parent==nil and not f:IsDescendantOf(game),"copy escaped ownership; preserve foreign parenting")
  check(copyOwnedNodes[f],"unowned returned root; preserve")
  for _,s in f:GetDescendants() do check(copyOwnedNodes[s] and rows[s]==nil,"foreign/original node entered copy; preserve") end
  f:Destroy()
 end)
 if clean then report.destroyedRoots+=1 else ok=false why=tostring(why).."\nowned copy cleanup failed: "..tostring(reason) end
end
local valid,reason=pcall(function()
 if originalSnapshot then
  originals()
  local afterCleanup=SER:SerializeInstancesAsync(roots)
  originals()
  check(sha(afterCleanup)==context.nativeSHA256,"opaque native original forest changed during reopen/cleanup")
  report.originalNativeArchiveUnchanged=true
 else check(owned() and epoch==0,"failed probe original epoch/lease changed") end
 check(#connections<=60000,"watcher cleanup bound exceeded")
end)
if not valid then ok=false why=tostring(why).."\npost-cleanup originals guard: "..tostring(reason) end
-- All watches remain active through the last full guarded yield. Disconnect is
-- one bounded, non-yielding release (<=60k calls), not a whole-scene property scan.
local releaseStart=os.clock()
for _,connection in connections do
 local clean,problem=pcall(function() connection:Disconnect() end)
 if not clean then ok=false why=tostring(why).."\nwatcher cleanup failed: "..tostring(problem) end
end
report.watcherReleaseCPUSeconds=os.clock()-releaseStart report.watchers=#connections
local final,problem=pcall(liveGuard)
if not final then ok=false why=tostring(why).."\nfinal original Source/root guard: "..tostring(problem) end
report.pass=ok report.error=if ok then nil else tostring(why)
report.checks=checks report.capturedAtUtc=DateTime.now():ToIsoDate()
report.originalSourcesUnchanged=valid and final and sourceBaselineComplete
if shared[KEY]==lease then shared[KEY]=nil end -- Never clear or overwrite held original state.
return HS:JSONEncode(report)
