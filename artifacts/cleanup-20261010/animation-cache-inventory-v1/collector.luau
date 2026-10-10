-- Root-owned READONLY instance metadata collector. No require, clone, serializer,
-- Instance.new, Source/editor/Parent/property write, upload, listener or spawned task.
-- REQUEST is inserted by the driver; shared scratch writes are counted separately.
local H=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local P=REQUEST
assert(type(P)=="table" and type(P.captureId)=="string" and P.captureId:match("^[a-zA-Z0-9%-]+$") and #P.captureId>=24)
assert(type(P.templateSHA256)=="string" and #P.templateSHA256==64)
local key="__MongoTVAnimationCacheInventory20261010V1_"..P.captureId
local ownerKey=key.."_owner"
local LIMIT_BYTES,CHUNK_BYTES,MAX_RECORDS=10000000,12000,10000
local state
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Edit required; never switch Play")
end
local function sha(text)
 local digest=E:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(digest)-1 do out[#out+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(out)
end
local function canonical(value)
 if type(value)~="table" then return H:JSONEncode(value) end
 local keys={} for k in value do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local parts={} for _,k in keys do parts[#parts+1]=H:JSONEncode(tostring(k))..":"..canonical(value[k]) end
 return "{"..table.concat(parts,",").."}"
end
local function number(n) return string.format("%.17g",n) end
local function numbers(...)local out={} for _,v in {...} do out[#out+1]=number(v) end return out end
local function typed(value)
 local kind=typeof(value)
 if kind=="nil" then return {kind="nil"} end
 if kind=="string" or kind=="boolean" then return {kind=kind,value=value} end
 if kind=="number" then return {kind=kind,value=number(value)} end
 if kind=="EnumItem" then return {kind=kind,value=tostring(value)} end
 if kind=="Vector2" then return {kind=kind,components=numbers(value.X,value.Y)} end
 if kind=="Vector3" then return {kind=kind,components=numbers(value.X,value.Y,value.Z)} end
 if kind=="Color3" then return {kind=kind,components=numbers(value.R,value.G,value.B)} end
 if kind=="BrickColor" then return {kind=kind,number=value.Number,name=value.Name} end
 if kind=="CFrame" then return {kind=kind,components=numbers(value:GetComponents())} end
 if kind=="UDim" then return {kind=kind,components=numbers(value.Scale,value.Offset)} end
 if kind=="UDim2" then return {kind=kind,components=numbers(value.X.Scale,value.X.Offset,value.Y.Scale,value.Y.Offset)} end
 if kind=="Rect" then return {kind=kind,components=numbers(value.Min.X,value.Min.Y,value.Max.X,value.Max.Y)} end
 if kind=="NumberRange" then return {kind=kind,components=numbers(value.Min,value.Max)} end
 if kind=="NumberSequence" or kind=="ColorSequence" then
  local points={}
  for _,point in value.Keypoints do
   points[#points+1]={time=number(point.Time),value=typed(point.Value),envelope=if kind=="NumberSequence" then number(point.Envelope) else nil}
  end
  return {kind=kind,keypoints=points}
 end
 if kind=="Instance" then return {kind=kind,instanceId=value:GetDebugId(16),className=value.ClassName,path=value:GetFullName()} end
 error("Unsupported metadata datatype; never omit as nil: "..kind)
end
local function attributes(node)
 local out={} for name,value in node:GetAttributes() do out[#out+1]={name=name,value=typed(value)} end
 table.sort(out,function(a,b)return a.name<b.name end) return out
end
local function tags(node)local out=node:GetTags() table.sort(out) return out end
local function segments(node)
 local out={} while node~=game do out[#out+1]=node.Name node=node.Parent assert(node,"Detached metadata path") end
 local ordered={} for i=#out,1,-1 do ordered[#ordered+1]=out[i] end return ordered
end
local function basic(node)
 return {instanceId=node:GetDebugId(16),parentId=if node.Parent then node.Parent:GetDebugId(16) else nil,
  name=node.Name,className=node.ClassName,archivable=node.Archivable,segments=segments(node),
  childCount=#node:GetChildren(),attributes=attributes(node),tags=tags(node)}
end
local function scriptProperties(node)
 local properties={Archivable=node.Archivable,LinkedSource=tostring(node.LinkedSource)}
 if node:IsA("BaseScript") then
  properties.Enabled=node.Enabled properties.Disabled=node.Disabled properties.RunContext=tostring(node.RunContext)
 end
 return properties
end
local function scriptRow(node)
 local row=basic(node)
 local source=node.Source local editor=SES:GetEditorSource(node)
 assert(source==editor and node.Source==source and SES:GetEditorSource(node)==editor,"Source/editor conflict or unstable read")
 row.sourceBytes=#source row.rawSourceSHA256=sha(source) row.rawEditorSHA256=sha(editor)
 row.properties=scriptProperties(node)
 return row,source,editor
end
local function sourceCatalog()
 local refs,rows={},{}
 for i,node in game:GetDescendants() do
  if node:IsA("LuaSourceContainer") then
   local row,source,editor=scriptRow(node)
   local facts=basic(node) facts.properties=scriptProperties(node)
   refs[#refs+1]={node=node,row=row,source=source,editor=editor,facts=facts} rows[#rows+1]=row
  end
  if i%1000==0 then task.wait() mode() end
 end
 table.sort(rows,function(a,b)return a.instanceId<b.instanceId end)
 assert(#refs==213,"Fresh 213 Source baseline required")
 return refs,sha(canonical(rows)),rows
end
local function guardSources(s)
 mode()
 for _,ref in s.sources do
  assert(ref.node:IsDescendantOf(game) and ref.node.Source==ref.source and SES:GetEditorSource(ref.node)==ref.editor,"Original Source/editor/identity changed")
  local facts=basic(ref.node) facts.properties=scriptProperties(ref.node)
  assert(canonical(facts)==canonical(ref.facts),"Original class/properties/attrs/tags changed")
 end
end
local function uniqueRoot(name,className,topCount)
 local found
 for _,node in SS:GetChildren() do if node.Name==name then assert(not found,"Duplicate named root") found=node end end
 assert(found and found.ClassName==className and #found:GetChildren()==topCount,"Fresh exact animation root/class/topchildren changed")
 return found
end
local function header(node)
 local row=basic(node) local children={}
 for _,child in node:GetChildren() do children[#children+1]=child:GetDebugId(16) end
 table.sort(children) row.directChildIds=children return row
end
local function rootGuard(s)
 mode()
 for _,r in s.roots do
  assert(uniqueRoot(r.header.name,r.header.className,r.header.childCount)==r.node,"Animation named root identity/collision changed")
  assert(r.node.Parent==SS and canonical(header(r.node))==canonical(r.header),"Animation root identity/metadata/topchildren changed")
 end
end
local function metadata(node)
 local row=basic(node)
 row.publishedAssetId=typed(node:GetAttribute("PublishedAssetId"))
 row.animationIdAttribute=typed(node:GetAttribute("AnimationId"))
 if node:IsA("Animation") then
  local ok,value=pcall(function()return node.AnimationId end)
  row.animationId={readable=ok,value=if ok then typed(value) else nil}
  if not ok then row.metadataIncomplete=true end
 end
 if node:IsA("KeyframeSequence") then
  for _,name in {"Loop","Priority","AuthoredHipHeight"} do
   local ok,value=pcall(function()return node[name]end)
   row.sequenceProperties=row.sequenceProperties or {}
   row.sequenceProperties[#row.sequenceProperties+1]={name=name,readable=ok,value=if ok then typed(value) else nil}
   if not ok then row.metadataIncomplete=true end
  end
 end
 if (node.Name=="PublishedAssetId" or node.Name=="AnimationId") and node:IsA("ValueBase") then
  local ok,value=pcall(function()return node.Value end)
  row.namedIdValue={readable=ok,value=if ok then typed(value) else nil}
  if not ok then row.metadataIncomplete=true end
 end
 row.inferredPublisherVersion=node.Name:match("^MongoTV_Entity_.+_(v%d[%w_]*)$")
 return row
end
local function candidate(node,top)
 return top or node:IsA("AnimationClip") or node:IsA("Animation")
  or node:GetAttribute("PublishedAssetId")~=nil or node:GetAttribute("AnimationId")~=nil
  or ((node.Name=="PublishedAssetId" or node.Name=="AnimationId") and node:IsA("ValueBase"))
end
local function ownership(s)
 assert(s and shared[key]==s and shared[ownerKey]==s,"Foreign collector namespace/identity preserved")
 assert(s.captureId==P.captureId and s.templateSHA256==P.templateSHA256,"Collector purpose/code binding changed")
end
local function guards(s)
 ownership(s) s.assertOwned() s.readProgress() guardSources(s) rootGuard(s)
 for _,ref in s.records do assert(canonical(metadata(ref.node))==canonical(ref.row),"Actual cache/Animation/attrs/tags/childcounts changed") end
end
local function close(s)
 ownership(s) s.assertOwned() s.readProgress()
 shared[key]=nil shared[ownerKey]=nil
 s.advance(2,false)
 return {schema="mongotv-animation-cache-read-close-v1",closed=true,collectorStateWrites=s.progress.stateWrites,
  nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,modeSwitches=0}
end
local function freeze(value)
 if type(value)~="table" or typeof(value)=="Instance" or table.isfrozen(value) then return end
 for _,v in value do if type(v)=="table" then freeze(v) end end table.freeze(value)
end
local function discovery(s,record)
 local rows,facts={},{} local incomplete=false
 for _,r in s.roots do
  local top={} for _,node in r.node:GetChildren() do top[node]=true end
  local nodes=r.node:GetDescendants() local histogram={} local count=0 local identities={}
  for i,node in nodes do
   histogram[node.ClassName]=(histogram[node.ClassName] or 0)+1
   assert(not node:IsA("LuaSourceContainer"),"New script in retired animation data forest")
   if candidate(node,top[node]) then
    local comparison=metadata(node)
    identities[#identities+1]=comparison.instanceId
    count+=1
    if record then
     local row=metadata(node) row.rootName=r.node.Name row.topChild=top[node]==true
     s.records[#s.records+1]={node=node,row=comparison}
     rows[#rows+1]=row incomplete=incomplete or row.metadataIncomplete==true
     assert(#rows<=MAX_RECORDS,"Bounded metadata record limit; do not truncate")
    end
   end
   if i%1000==0 then task.wait() ownership(s) s.assertOwned() s.readProgress() rootGuard(s) end
  end
  table.sort(identities)
  facts[#facts+1]={root=r.header,descendantCount=#nodes,nodeCount=#nodes+1,classHistogram=histogram,metadataRecordCount=count,candidateIdentitySHA256=sha(canonical(identities))}
 end
 return rows,facts,incomplete
end
local ok,result=xpcall(function()
 mode()
 if P.command=="begin" then
  assert(shared[key]==nil and shared[ownerKey]==nil,"Occupied collector namespace preserved")
  local sources,sourceHash,sourceRows=sourceCatalog()
  state={captureId=P.captureId,templateSHA256=P.templateSHA256,sources=sources,roots={},records={},progress={nextPage=0,stateWrites=2}}
  shared[key]=state shared[ownerKey]=state
  -- Install identity/progress checks before the first fallible cache read.
  local original,progress=state,state.progress local expectedPage,expectedWrites=0,2
  state.assertOwned=function()ownership(original)end
  state.readProgress=function()
   assert(original.progress==progress and progress.nextPage==expectedPage and progress.stateWrites==expectedWrites,"Foreign collector progress preserved")
  end
  state.advance=function(writes,page)
   expectedWrites+=writes if page then expectedPage+=1 end
   progress.nextPage=expectedPage progress.stateWrites=expectedWrites
  end
  for _,spec in {{"MongoTVEntityAnimations","Folder",117},{"RBX_ANIMSAVES","Model",27}} do
   local node=uniqueRoot(table.unpack(spec)) state.roots[#state.roots+1]={node=node,header=header(node)}
  end
  state.sourceCatalogSHA256=sourceHash
  local rows,rootFacts,incomplete=discovery(state,true)
  state.discoverySHA256=sha(canonical(rootFacts))
  table.sort(rows,function(a,b)return canonical(a.segments)..a.instanceId<canonical(b.segments)..b.instanceId end)
  guards(state)
  local _,sourceAfter=sourceCatalog() assert(sourceAfter==sourceHash,"Source catalog/count changed across capture")
  local _,discoveryAfter=discovery(state,false)
  assert(sha(canonical(discoveryAfter))==state.discoverySHA256,"Cache candidate discovery changed across capture")
  guards(state)
  local manifest={schema="mongotv-animation-cache-preservation-manifest-v1",captureId=P.captureId,templateSHA256=P.templateSHA256,
   nativeReadOnly=true,metadataComplete=not incomplete,sourceCount=213,sourceCatalogBeforeSHA256=sourceHash,sourceCatalogAfterSHA256=sourceAfter,
   roots=rootFacts,records=rows,sourceCatalog=sourceRows,nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,modeSwitches=0,
   limits="Targeted class/PublishedAssetId/AnimationId traversal +complete metadata on all topchildren/cache/AnimationClip candidates. Other pose/keyframe properties/attributes are not inventoried; full off-place native archive remains required. Readable errors/unknown fields are not nil. No upload/delete/gameplay/performance/reference certificate. Point-in-time guards do not prove continuous actor provenance."}
  local payload=H:JSONEncode(manifest) assert(#payload<=LIMIT_BYTES,"Metadata manifest byte bound; do not truncate")
  state.payload=payload state.payloadSHA256=sha(payload) state.pageCount=math.ceil(#payload/CHUNK_BYTES)
  freeze(state.sources) freeze(state.roots) freeze(state.records) table.freeze(state)
  return {schema="mongotv-animation-cache-read-begin-v1",pass=true,captureId=P.captureId,templateSHA256=P.templateSHA256,
   manifestSHA256=state.payloadSHA256,manifestBytes=#payload,pageCount=state.pageCount,recordCount=#rows,metadataComplete=not incomplete,
   sourceCount=213,sourceCatalogSHA256=sourceHash,roots=rootFacts,collectorStateWrites=2,nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,modeSwitches=0}
 end
 state=shared[key] ownership(state) state.assertOwned()
 if P.command=="page" then
  assert(type(P.page)=="number" and P.page==state.progress.nextPage and P.page>=0 and P.page<state.pageCount,"Deterministic fresh page order required")
  guards(state)
  local chunk=string.sub(state.payload,P.page*CHUNK_BYTES+1,(P.page+1)*CHUNK_BYTES)
  state.advance(1,true)
  return {schema="mongotv-animation-cache-read-page-v1",captureId=P.captureId,templateSHA256=P.templateSHA256,page=P.page,
   pageCount=state.pageCount,manifestSHA256=state.payloadSHA256,chunkBytes=#chunk,chunkSHA256=sha(chunk),
   chunkBase64=buffer.tostring(E:Base64Encode(buffer.fromstring(chunk))),collectorStateWrites=state.progress.stateWrites,
   nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,modeSwitches=0}
 elseif P.command=="finish" then
  assert(state.progress.nextPage==state.pageCount,"Every deterministic metadata page required")
  guards(state) local _,sourceAfter=sourceCatalog() assert(sourceAfter==state.sourceCatalogSHA256,"Final Source catalog changed")
  local _,discoveryAfter=discovery(state,false)
  assert(sha(canonical(discoveryAfter))==state.discoverySHA256,"New/missing nested cache metadata candidate; discovery changed")
  guards(state)
  local proof={schema="mongotv-animation-cache-read-finish-v1",captureId=P.captureId,pass=true,
   manifestSHA256=state.payloadSHA256,sourceCatalogSHA256=sourceAfter,sourceCount=213,rootAndCacheMetadataUnchanged=true,
   all213OriginalSourceEditorPropertiesUnchanged=true,pointInTimeGuardsOnly=true}
  proof.cleanup=close(state) return proof
 elseif P.command=="abandon" then return close(state) end
 error("Unknown read collector command")
end,debug.traceback)
if ok then
 local encodedOk,encoded=pcall(function()local out=H:JSONEncode(result) assert(#out<=20000,"Bounded metadata response exceeded") return out end)
 if encodedOk then return encoded end
 ok=false result=tostring(encoded)
end
if not ok then
 local cleanupOk,cleanupError=false,"No owned collector created/available"
 if state then cleanupOk,cleanupError=pcall(function()state.assertOwned()return close(state)end) end
 result={schema="mongotv-animation-cache-read-failure-v1",pass=false,captureId=P.captureId,error=tostring(result),
  collectorAcquired=state~=nil,
  collectorCleanupPassed=cleanupOk,collectorCleanup=if cleanupOk then cleanupError else nil,
  collectorCleanupError=if cleanupOk then nil else tostring(cleanupError):sub(1,2000),nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,modeSwitches=0}
 result.error=result.error:sub(1,8000)
end
local encoded=H:JSONEncode(result)
assert(#encoded<=20000,"Bounded metadata response exceeded; collector outcome needs reconciliation")
return encoded
