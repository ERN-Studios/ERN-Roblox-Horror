-- Root-run probe only. No authoritative Source/Parent/attribute writes.
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local ENC=game:GetService("EncodingService")
local expected=H:JSONDecode(__EXPECTED__)
local payloads=H:JSONDecode(__PAYLOADS__)
local installed=__INSTALLED__
local KEY="__MongoTVPreviewNoopProbe20261010"
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Edit-only probe; preserve owner's Play")
end
local function sha(source)
 local b=ENC:ComputeBufferHash(buffer.fromstring(source:gsub("\r\n","\n")),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(out)
end
local function stable(value)
 if type(value)~="table" then return H:JSONEncode(value) end
 local keys={} for key in value do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(value[key]) end
 return "{"..table.concat(out,",").."}"
end
local function resolve(segments)
 local n=game for _,name in segments do
  local found={} for _,child in n:GetChildren() do if child.Name==name then found[#found+1]=child end end
  assert(#found==1,"Exact original path became missing/ambiguous") n=found[1]
 end return n
end
local function metadata(n)
 local props={} for _,name in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do
  local ok,value=pcall(function()return n[name]end)
  if ok then props[name]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local tags=n:GetTags() table.sort(tags)
 return {className=n.ClassName,parent=n.Parent,path=n:GetFullName(),instanceId=n:GetDebugId(16),properties=props,attributes=n:GetAttributes(),tags=tags}
end
mode()
assert(shared[KEY]==nil,"A preview probe lease already exists")
local originalMap,originalList={},{}
local census=game:GetDescendants()
for index,n in census do
 if n:IsA("LuaSourceContainer") then
  local source=n.Source local editor=SES:GetEditorSource(n)
  assert(source==editor and n.Source==source and SES:GetEditorSource(n)==source,"Original Source/editor baseline conflict")
  local m=metadata(n)
  originalMap[n]={source=source,metadata=m,props=stable(m.properties),attrs=stable(m.attributes),tags=stable(m.tags)}
  originalList[#originalList+1]=n
 end
 if index%10000==0 then task.wait();mode() end
end
assert(#originalList==expected.nativeScriptCount,"Concurrent native Source census change")
for _,row in expected.originals do
 local n=resolve(row.segments) local saved=originalMap[n]
 assert(saved and n:GetDebugId(16)==row.instanceId and n.Parent:GetDebugId(16)==row.parentId,"Fresh original identity changed")
 assert(saved.metadata.className==row.className and sha(saved.source)==row.sourceSHA256,"Fresh original Source/class changed")
 assert(stable(saved.metadata.properties)==stable(row.properties) and stable(saved.metadata.attributes)==stable(row.attributes) and stable(saved.metadata.tags)==stable(row.tags),"Fresh original metadata changed")
end
local token,ownedConnections={},{}
local state={token=token,connections=ownedConnections,phase="captured"}
local function ownedLease()
 return shared[KEY]==state and state.token==token and state.connections==ownedConnections
  and next(ownedConnections)==nil and state.phase=="captured"
end
local function claimLease()
 mode()
 -- No yield between this fresh compare and claim: the earlier census can yield.
 assert(shared[KEY]==nil,"A foreign preview probe lease appeared during census")
 shared[KEY]=state
end
local function releaseLease()
 if not ownedLease() then return false end
 shared[KEY]=nil
 return true
end
claimLease()
local probes,created,destroyed={},0,0
local report={schema="mongotv-preview-noop-native-contract-v1",readAtUtc=DateTime.now():ToIsoDate(),installed=installed,pass=false,
 nativeOriginalSourceWrites=0,nativeOriginalParentWrites=0,nativeOriginalAttributeWrites=0,modeSwitches=0,borrowedRuntimeState=false,
 originalSourceCoverage=#originalList,probesCreated=0,probesDestroyed=0,remainingProbes=0,
 limits="Actual full Level4PreviewPrompt source with test-owned native ProximityPrompt instances and real Enabled/DescendantAdded signals. Players/DevAccess/service results and descendant delivery are controlled boundaries. No live client, gameplay, real access/admission, multiplayer, streaming, teleport or performance certification."}
local function guard(fullCensus)
 mode() assert(ownedLease(),"Probe state/token/connections ownership changed")
 for _,n in originalList do
  local saved=originalMap[n] local m=metadata(n)
  assert(n.Parent==saved.metadata.parent and m.path==saved.metadata.path and m.className==saved.metadata.className,"Original identity/Parent/class changed")
  assert(n.Source==saved.source and SES:GetEditorSource(n)==saved.source,"Authoritative Source/editor changed")
  assert(stable(m.properties)==saved.props and stable(m.attributes)==saved.attrs and stable(m.tags)==saved.tags,"Authoritative properties/attrs/tags changed")
 end
 if fullCensus then
  local count=0 for index,n in game:GetDescendants() do
   if n:IsA("LuaSourceContainer") then assert(originalMap[n],"New authoritative Source appeared");count+=1 end
   if index%10000==0 then task.wait();mode();assert(ownedLease(),"Lease changed during final census") end
  end
  assert(count==#originalList,"Authoritative Source removed")
  -- Repeat after the yielding census; point-in-time guard, not a continuous epoch claim.
  guard(false)
 end
end
local function stage(name,body)
 guard(false)
 local probe=Instance.new("ModuleScript")
 probes[#probes+1]={object=probe,name="MongoTVCleanupPreviewNoop_"..name,source=body}
 created+=1
 probe.Name=probes[#probes].name
 assert(not originalMap[probe] and probe.Parent==nil and #probe:GetChildren()==0,"Only a fresh owned unparented ModuleScript may be staged")
 assert(probe.Source=="" and SES:GetEditorSource(probe)=="","Exact empty Source/editor baseline required")
 SES:UpdateSourceAsync(probe,function(current)
  guard(false)
  assert(current=="" and probe.Source=="" and SES:GetEditorSource(probe)=="" and probe.Parent==nil,"Empty staging baseline changed")
  return body
 end)
 guard(false)
 assert(probe.Source==body and SES:GetEditorSource(probe)==body and probe.Parent==nil,"Exact owned staged Source/editor mismatch")
 local run=require(probe)
 assert(type(run)=="function","Contract module must return only its owned runner")
 guard(false)
 return run
end
local ok,result=xpcall(function()
 guard(true)
 local before=stage("Before",payloads.before)
 local candidate=stage("Candidate",payloads.candidate)
 local a,b=before(),candidate()
 assert(a.checks==expected.contractChecks and b.checks==expected.contractChecks,"Actual contract assertion count changed")
 assert(stable(a)==stable(b),"Actual preview filter/access/failure/reentry output changed")
 assert(stable(before())==stable(a) and stable(candidate())==stable(b),"Module runner reentry changed contract output")
 guard(false)
 for _,entry in {{"PublicNegative",payloads.publicNegative,"public L5/L6 prompts remain enabled"},
  {"TruthyNegative",payloads.truthyNegative,"L4 initial entry is fail-closed truthy-string"}} do
  local mutant=stage(entry[1],entry[2])
  local mutantOK,mutantError=pcall(mutant)
  assert(not mutantOK and tostring(mutantError):find(entry[3],1,true),"Actual preview semantic mutant was not rejected")
  guard(false)
 end
 return {checksPerVersion=a.checks,pairedChecks=a.checks+b.checks,reentryChecks=a.checks+b.checks,
 beforeBehaviorSHA256=sha(stable(a)),candidateBehaviorSHA256=sha(stable(b)),semanticNegativeRejected=true,semanticNegativeControls=2}
end,debug.traceback)
local cleanupErrors={}
for _,entry in probes do
 local clean,err=pcall(function()
  local p=entry.object
  assert(not originalMap[p] and p.ClassName=="ModuleScript" and p.Parent==nil and not p:IsDescendantOf(game) and #p:GetChildren()==0 and p.Name==entry.name,"Destroy only the exact untouched owned probe")
  assert((p.Source=="" or p.Source==entry.source) and SES:GetEditorSource(p)==p.Source,"Preserve a foreign probe Source/editor edit")
  p:Destroy() destroyed+=1
 end)
 if not clean then cleanupErrors[#cleanupErrors+1]=tostring(err) end
end
local guarded,guardError=pcall(function()guard(true)end)
report.probesCreated=created report.probesDestroyed=destroyed report.remainingProbes=created-destroyed
report.cleanupErrors=cleanupErrors report.originalsUnchanged=guarded report.contractPassed=ok
if ok then report.contract=result else report.error=tostring(result) end
if not guarded then report.originalGuardError=tostring(guardError) end
local owned=releaseLease()
report.ownedLeaseReleased=owned
report.pass=ok and guarded and #cleanupErrors==0 and created==destroyed and owned
return H:JSONEncode(report)
