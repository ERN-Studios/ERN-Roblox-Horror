-- Root-only scoped Source CAS and fresh owned parser probes; no mode switches.
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local ENC=game:GetService("EncodingService")
local request=H:JSONDecode(__REQUEST__)
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Edit-only CAS; preserve owner's Play")
end
local function sha(source)
 local b=ENC:ComputeBufferHash(buffer.fromstring(source),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(out)
end
local function stable(value)
 if type(value)~="table" then return H:JSONEncode(value) end
 local keys={} for key in value do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(value[key]) end
 return "{"..table.concat(out,",").."}"
end
local function segments(n)
 local result={} while n~=game do table.insert(result,1,n.Name);n=assert(n.Parent,"Unparented original") end return result
end
local function metadata(n)
 local properties={} for _,name in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do
  local ok,value=pcall(function()return n[name]end)
  if ok then properties[name]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local tags=n:GetTags() table.sort(tags)
 return {segments=segments(n),studioPath=n:GetFullName(),instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),
  className=n.ClassName,properties=properties,attributes=n:GetAttributes(),tags=tags}
end
local function resolve(parts)
 local n=game for _,name in parts do
  local found={} for _,child in n:GetChildren() do if child.Name==name then found[#found+1]=child end end
  assert(#found==1,"Missing/ambiguous original path") n=found[1]
 end return n
end
local targetParts={"StarterPlayer","StarterPlayerScripts","Round Exit Client"}
local target=resolve(targetParts)
local function targetIdentity()
 local m=metadata(target)
 assert(m.instanceId=="1_31096" and m.parentId=="1_410029" and m.className=="LocalScript","Fresh target identity changed")
 assert(stable(m.properties)==stable(request.targetProperties) and stable(m.attributes)==stable(request.targetAttributes)
  and stable(m.tags)==stable(request.targetTags),"Fresh target metadata changed")
 return m
end
mode();targetIdentity()
local function targetSummary()
 local source=target.Source local editor=SES:GetEditorSource(target)
 local row=metadata(target)
 row.sourceSHA256=sha(source) row.editorSHA256=sha(editor)
 row.sourceEditorMatches=source==editor row.bytes=#source row.editorBytes=#editor
 assert(target.Source==source and SES:GetEditorSource(target)==editor,"Target changed during summary")
 return row
end
if request.operation=="target" then
 return H:JSONEncode({pass=true,operation="target",target=targetSummary(),originalSourceWrites=0,modeSwitches=0})
end
if request.operation=="capture" or request.operation=="observe" then
 local rows,map={},{}
 local targetSource=target.Source local targetEditor=SES:GetEditorSource(target)
 assert(targetSource==targetEditor,"Target Source/editor conflict")
 if request.operation=="capture" then
  assert(sha(targetSource)==request.expectedTargetSHA256,"Fresh target is no longer exact selected Source")
 end
 for index,n in game:GetDescendants() do
  if n:IsA("LuaSourceContainer") then
   local body=n.Source local editor=SES:GetEditorSource(n) assert(body==editor,"Original Source/editor conflict")
   local row=metadata(n) row.sha256=sha(body) row.bytes=#body
   rows[#rows+1]=row;map[n]={body=body,meta=stable(metadata(n))}
  end
  if index%10000==0 then task.wait();mode() end
 end
 assert(#rows==request.nativeScriptCount,"Concurrent Source count change")
 -- Final no-yield full Source/editor/property guard after the bounded census.
 mode();targetIdentity()
 for n,saved in map do assert(n.Source==saved.body and SES:GetEditorSource(n)==saved.body and stable(metadata(n))==saved.meta,"Original changed during capture") end
 assert(target.Source==targetSource and SES:GetEditorSource(target)==targetEditor,"Target changed during capture")
 table.sort(rows,function(a,b)return a.studioPath<b.studioPath end)
 local first=request.pageFirst local count=request.pageCount
 assert(type(first)=="number" and first>=1 and first%1==0 and count==20,"Bounded page required")
 local page={} for index=first,math.min(first+count-1,#rows) do page[#page+1]=rows[index] end
 return H:JSONEncode({pass=true,operation=request.operation,target=targetSummary(),rows=page,
  catalogSHA256=sha(stable(rows)),totalRows=#rows,pageFirst=first,pageCount=count,
  readAtUtc=DateTime.now():ToIsoDate(),originalSourceWrites=0,modeSwitches=0,objectsCreated=0})
end
assert(request.operation=="apply" or request.operation=="rollback" or request.operation=="verify" or request.operation=="compile","Unknown operation")
local originals={}
for _,row in request.rows do
 local n=resolve(row.segments)
 assert(not originals[n],"Duplicate baseline original") originals[n]=row
end
assert(#request.rows==request.nativeScriptCount and originals[target],"Exact original coverage required")
local fromHash=if (request.operation=="verify" or request.operation=="compile") then request.expectedTargetSHA256 elseif request.operation=="apply" then request.beforeSHA256 else request.afterSHA256
local toHash=if request.operation=="apply" then request.afterSHA256 else request.beforeSHA256
local function guard(fullCensus,changed)
 mode();targetIdentity()
 for n,row in originals do
  local m=metadata(n)
  local hash=if n==target then (if changed then toHash else fromHash) else row.sha256
  assert(m.instanceId==row.instanceId and m.parentId==row.parentId and m.className==row.className and stable(m.segments)==stable(row.segments),"Original identity/Parent/class changed")
  assert(stable(m.properties)==stable(row.properties) and stable(m.attributes)==stable(row.attributes) and stable(m.tags)==stable(row.tags),"Original metadata changed")
  local body=n.Source assert(SES:GetEditorSource(n)==body and sha(body)==hash,"Original Source/editor changed")
 end
 if fullCensus then
  local count=0 for index,n in game:GetDescendants() do
   if n:IsA("LuaSourceContainer") then assert(originals[n],"New original Source appeared");count+=1 end
   if index%10000==0 then task.wait();mode() end
  end
  assert(count==request.nativeScriptCount,"Original Source removed")
  guard(false,changed)
 end
end
guard(true,false)
if request.operation=="verify" then
 return H:JSONEncode({pass=true,operation="verify",originalSourceCoverage=request.nativeScriptCount,
  sourceSHA256=sha(target.Source),originalSourceWrites=0,modeSwitches=0})
end
local replacements={
 {old=string.sub([=[_local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again
local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band

local prompt = playerScripts:FindFirstChild("RoundExitPrompt")]=],2),new=string.sub([=[_local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again

local prompt = playerScripts:FindFirstChild("RoundExitPrompt")]=],2)},
}
local function transform(current)
 local result=current
 for i=1,#replacements do
  local index=if request.operation=="rollback" then #replacements-i+1 else i
  local entry=replacements[index]
  local old,new=entry.old,entry.new
  if request.operation=="rollback" then old,new=new,old end
  assert(#old>0 and #new>0,"Only exact nonempty scoped helper anchors")
  local start,finish=result:find(old,1,true)
  assert(start and not result:find(old,finish+1,true),"Unique scoped private helper required")
  result=result:sub(1,start-1)..new..result:sub(finish+1)
 end
 assert(sha(result)==toHash,"Scoped replacement result differs from reviewed Source")
 return result
end
-- Native parser port only: require returns a factory; its client body is never called.
if request.operation=="compile" then
 local sources=request.compileSources
 assert(type(sources)=="table" and sha(sources.before)==request.beforeSHA256 and sha(sources.candidate)==request.afterSHA256,"Exact reviewed compile bodies required")
 local old,new=replacements[1].old,replacements[1].new
 local first,last=sources.before:find(old,1,true)
 assert(first and not sources.before:find(old,last+1,true),"Unique compile pair anchor required")
 assert(sources.before:sub(1,first-1)..new..sources.before:sub(last+1)==sources.candidate and #sources.before-#sources.candidate==73,"Only exact 73-byte literal removal may compile")
 local KEY="MongoTVExitLiteralCompileLeaseV1"
 local token={} local state={token=token,phase="compile"}
 local function ownedLease()return shared[KEY]==state and state.token==token and state.phase=="compile"end
 guard(false,false)
 assert(shared[KEY]==nil,"Foreign Exit parser probe lease present")
 shared[KEY]=state -- Fresh no-yield compare/claim; census above may yield.
 local probes,created,destroyed,cleanupErrors={ },0,0,{}
 local function checked(full)
  assert(ownedLease(),"Exit parser probe lease ownership changed")
  guard(full,false)
  assert(ownedLease(),"Exit parser probe lease ownership changed")
 end
 local function stage(name,source)
  checked(false)
  local body="return function()\n"..source.."\nend\n"
  local probe=Instance.new("ModuleScript")
  local entry={object=probe,name="MongoTVCleanupExitLiteral_"..name,body=body}
  probes[#probes+1]=entry;created+=1;probe.Name=entry.name
  assert(not originals[probe] and probe.Parent==nil and #probe:GetChildren()==0,"Fresh owned unparented module required")
  assert(probe.Source=="" and SES:GetEditorSource(probe)=="","Exact empty Source/editor staging baseline required")
  SES:UpdateSourceAsync(probe,function(current)
   checked(false)
   assert(current=="" and probe.Source=="" and SES:GetEditorSource(probe)=="" and probe.Parent==nil and probe.Name==entry.name and probe.ClassName=="ModuleScript" and #probe:GetChildren()==0,"Fresh empty owned staging baseline changed")
   return body
  end)
  checked(false)
  assert(probe.Source==body and SES:GetEditorSource(probe)==body and probe.Parent==nil and probe.Name==entry.name and probe.ClassName=="ModuleScript" and #probe:GetChildren()==0,"Owned staged factory differs")
  local factory=require(probe)
  assert(type(factory)=="function","Whole-source module must return an uncalled factory")
  checked(false)
  return {phase=name,sourceSHA256=sha(source),factorySHA256=sha(body),bytes=#source,factoryUncalled=true}
 end
 local ok,result=xpcall(function()
  checked(true)
  return {stage("Before",sources.before),stage("Candidate",sources.candidate)}
 end,debug.traceback)
 -- All assertion/SES/parser failures reach exact test-owned cleanup.
 for _,entry in probes do
  local clean,why=pcall(function()
   local p=entry.object
   assert(not originals[p] and p.ClassName=="ModuleScript" and p.Parent==nil and not p:IsDescendantOf(game) and #p:GetChildren()==0 and p.Name==entry.name,"Destroy only exact untouched owned parser probe")
   assert((p.Source=="" or p.Source==entry.body) and SES:GetEditorSource(p)==p.Source,"Preserve foreign parser-probe Source/editor edit")
   p:Destroy();destroyed+=1
  end)
  if not clean then cleanupErrors[#cleanupErrors+1]=tostring(why) end
 end
 local guarded,why=pcall(function()checked(true)end)
 local lease=ownedLease()
 if lease then shared[KEY]=nil end -- Never clear a replaced foreign lease.
 return H:JSONEncode({schema="mongotv-exit-literal-native-parser-v1",operation="compile",pass=ok and guarded and lease and #cleanupErrors==0 and created==2 and destroyed==2,
  parserPassed=ok,originalsUnchanged=guarded,ownedLeaseReleased=lease,cleanupErrors=cleanupErrors,
  probesCreated=created,probesDestroyed=destroyed,remainingProbes=created-destroyed,compiles=if ok then result else {},
  error=if ok then nil else tostring(result),originalGuardError=if guarded then nil else tostring(why),
  originalSourceCoverage=request.nativeScriptCount,sourceSHA256=sha(target.Source),originalSourceWrites=0,originalParentWrites=0,originalPropertyWrites=0,
  borrowedRuntimeState=false,clientBodiesExecuted=0,modeSwitches=0,readAtUtc=DateTime.now():ToIsoDate(),
  limits="Native parser/factory-return in fresh empty ModuleScripts; client bodies never run. No gameplay, hardware, multiplayer, streaming, teleport, real-asset or performance certificate."})
end
SES:UpdateSourceAsync(target,function(current)
 -- No task.wait/async calls between this fresh guard and callback return.
 guard(false,false)
 assert(current==target.Source and current==SES:GetEditorSource(target) and sha(current)==fromHash,"Fresh callback Source/editor CAS changed")
 return transform(current)
end)
guard(true,true)
return H:JSONEncode({pass=true,operation=request.operation,path=target:GetFullName(),instanceId=target:GetDebugId(16),
 sourceSHA256=sha(target.Source),sourceEditorMatches=target.Source==SES:GetEditorSource(target),bytes=#target.Source,
 originalSourceCoverage=request.nativeScriptCount,originalSourceWrites=1,otherOriginalSourceWrites=0,
 originalPropertyWrites=0,originalParentWrites=0,modeSwitches=0,objectsCreated=0,
 readAtUtc=DateTime.now():ToIsoDate(),guardSemantics="Exact final point-in-time originals guard after yielding census; no continuous external-change certificate."})
