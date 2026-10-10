-- Root-only readonly current baseline. No Instances created, no Source/property/Parent/mode writes.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local BASE="http://127.0.0.1:18916"
local ORIGINAL_KEY="__MongoTVStorageCleanup20261009"
local checks=0
local function check(value,message) assert(value,message) checks+=1 end
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
local beforeSources,beforeRoots,connections={},{},{}
local initialCount,epoch=0,0
local expected,baselineRaw,baseline
local state=shared[ORIGINAL_KEY]
local function countKeys(t) local n=0 for _ in t do n+=1 end return n end
local function owned()
 return game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning()
  and shared[ORIGINAL_KEY]==state and state and state.rootRefs and state.scriptRefs
  and not state.probeLease and not state.portLease and state.storagePort==nil
  and countKeys(state.rootRefs)==73 and countKeys(state.scriptRefs)==222
end
local function guard()
 check(owned() and epoch==0,"baseline mode/ledger/epoch changed")
 check(#game:GetDescendants()==initialCount and #SS:GetChildren()==expected.expectedLiveRoots,"baseline live census/roots changed")
 for root,facts in beforeRoots do
  check(root.Parent==SS and canonical({root.Name,root.ClassName,root.Archivable,root:GetAttributes(),tags(root)})==facts,"baseline live root changed")
 end
 local count=0
 for s,row in beforeSources do
  check(s:IsDescendantOf(game) and scriptMatches(s,row),"baseline Source/editor/parent/metadata changed") count+=1
 end
 check(count==213,"baseline source count changed")
end
local function watch(signal) connections[#connections+1]=signal:Connect(function()epoch+=1 end) end
local report={schema="storage-restoration-live-baseline-completion-v1",pass=false,nativeObjectCreations=0,
 sourceWrites=0,propertyWrites=0,originalParentWrites=0,modeSwitches=0,restorationCertified=false}
local ok,why=xpcall(function()
 check(owned() and HS.HttpEnabled,"correct Edit/current original ledger/existing HTTP required")
 expected=HS:JSONDecode(HS:GetAsync(BASE.."/baseline-context",true))
 check(expected.schema=="storage-restoration-live-baseline-context-v1" and expected.expectedLiveSources==213
  and expected.expectedLedgerRootRefs==73 and expected.expectedLedgerScriptRefs==222,"invalid exact baseline context")
 watch(game.DescendantAdded) watch(game.DescendantRemoving) watch(SS.ChildAdded) watch(SS.ChildRemoved)
 for _,root in SS:GetChildren() do
  beforeRoots[root]=canonical({root.Name,root.ClassName,root.Archivable,root:GetAttributes(),tags(root)})
  watch(root.Changed) watch(root.AttributeChanged)
 end
 local census=game:GetDescendants() initialCount=#census
 check(initialCount==expected.expectedLiveDescendants and #SS:GetChildren()==expected.expectedLiveRoots,"fresh census/root baseline mismatch")
 local pins={}
 local unique={}
 for index,s in census do
  if s:IsA("LuaSourceContainer") then
   local row=scriptRow(s)
   check(not unique[row.path],"ambiguous current Source path") unique[row.path]=true
   beforeSources[s]=row watch(s.Changed) watch(s.AttributeChanged)
   pins[#pins+1]={path=row.path,class=row.class,identity=s:GetDebugId(),parentIdentity=row.parent:GetDebugId(),
    sourceSHA256=sha(buffer.fromstring(row.source)),bytes=#row.source,
    metadataSHA256=sha(buffer.fromstring(canonical({properties=row.properties,attributes=row.attributes,tags=row.tags})))}
  end
  if index%1000==0 then task.wait() check(owned() and epoch==0,"baseline changed during census") end
 end
 check(#pins==213,"exact213 current Sources required")
 table.sort(pins,function(a,b)return a.path<b.path end)
 guard()
 baseline={schema="storage-restoration-live-baseline-v1",placeId=game.PlaceId,universeId=game.GameId,mode="Edit",
  expectedLiveSources=213,expectedLiveRoots=#SS:GetChildren(),expectedLiveDescendants=initialCount,
  expectedLedgerRootRefs=73,expectedLedgerScriptRefs=222,sourcePins=pins,capturedAtUtc=DateTime.now():ToIsoDate(),
  sourceWrites=0,propertyWrites=0,originalParentWrites=0,modeSwitches=0}
 baselineRaw=HS:JSONEncode(baseline)
 check(#baselineRaw<=250000,"baseline metadata response bound exceeded")
 check(HS:PostAsync(BASE.."/baseline",baselineRaw,Enum.HttpContentType.ApplicationJson)=="saved","baseline receiver rejected")
 guard()
end,debug.traceback)
for _,connection in connections do
 local released,problem=pcall(function()connection:Disconnect()end)
 if not released then ok=false why=tostring(why).."\nwatcher release failed: "..tostring(problem) end
end
local final,problem=pcall(function()
 check(expected~=nil and baselineRaw~=nil,"baseline never completed")
 guard()
end)
if not final then ok=false why=tostring(why).."\nfinal readonly baseline guard: "..tostring(problem) end
report.pass=ok report.error=if ok then nil else tostring(why)
report.originalSourcesUnchanged=final and ok
report.liveSources=if baseline then #baseline.sourcePins else 0
report.liveRoots=#SS:GetChildren() report.liveDescendants=#game:GetDescendants()
report.baselineSHA256=if baselineRaw then sha(buffer.fromstring(baselineRaw)) else nil
report.watchers=#connections report.watchersReleaseAttempted=#connections
report.checks=checks report.capturedAtUtc=DateTime.now():ToIsoDate()
return HS:JSONEncode(report)
