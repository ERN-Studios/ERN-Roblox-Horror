-- Offline exact nine-task-Source plus two concurrent-Source comparison.
-- Separate from the retained strict-nine failure. Never contacts or changes Studio.
local fs=require("@lune/fs")
local process=require("@lune/process")
local serde=require("@lune/serde")
local rbx=require("@lune/roblox")
local beforeDir=assert(process.args[1],"before directory")
local afterDir=assert(process.args[2],"after directory")
local manifestPath=assert(process.args[3],"final installed candidate manifest")
local outputPath=assert(process.args[4],"scope receipt output")
local runtimeSourcesOnly=process.args[5]=="--runtime-sources-only"
assert(process.args[5]==nil or runtimeSourcesOnly,"Unknown native scope mode")
local function read(p) return serde.decode("json",fs.readFile(p)) end
local function sha(v) return serde.hash("sha256",v) end
local bm,am=read(beforeDir.."/metadata.json"),read(afterDir.."/metadata.json")
local manifest=read(manifestPath)
assert(runtimeSourcesOnly,"Concurrent accounting permits only runtime Source mode")
local concurrentPinsPath=assert(process.args[6],"exact concurrent pins required")
local concurrentPins=read(concurrentPinsPath)
assert(concurrentPins.schema=="lobby-access-spawn-exact-concurrent-source-pins-v1")
assert(concurrentPins.beforeCaptureId==bm.captureId and concurrentPins.afterCaptureId==am.captureId)
assert(concurrentPins.taskManifestSHA256==sha(fs.readFile(manifestPath)),"Task manifest changed")
local concurrentExactPaths={
 ["ServerScriptService.Level 1 Systems.MazeGenerator"]="Script",
 ["ServerScriptService.Level 1 Systems.BlenderRoomRenderer"]="ModuleScript",
}
assert(#concurrentPins.rows==2,"Exactly two concurrent Source paths required")
local exactPaths={
 ["ServerScriptService.GameManager"]="Script",
 ["ServerScriptService.LobbyReimaginedPreview.Bootstrap"]="Script",
 ["ServerScriptService.LobbyReimaginedPreview.Builder"]="ModuleScript",
 ["ServerScriptService.LobbyReimaginedPreview.DevBayAccessGuard"]="ModuleScript",
 ["ServerScriptService.Level5PreviewAccess"]="Script",
 ["ServerScriptService.Level6PreviewAccess"]="Script",
 ["StarterPlayer.StarterPlayerScripts.R4DevGateController"]="LocalScript",
 ["StarterPlayer.StarterPlayerScripts.Level6PreviewTransport"]="LocalScript",
 ["StarterPlayer.StarterPlayerScripts.Friend Boost Client"]="LocalScript",
}
assert(#manifest.rows==9,"This task permits exactly nine Source targets")
for _,pin in manifest.rows do assert(exactPaths[pin.path]==pin.className,"Source target outside closed task scope") end
assert(bm.placeId==131311258779917 and am.placeId==bm.placeId and bm.universeId==10559217407 and am.universeId==bm.universeId)
assert(bm.groupId==1039373905 and am.groupId==bm.groupId,"Wrong native owner group")
assert(manifest.nativeBeforeCaptureId==bm.captureId,"Wrong before capture")
assert(#bm.editorConflicts==0 and #am.editorConflicts==0 and #bm.skipped==0 and #am.skipped==0)
local bbytes,abytes=fs.readFile(beforeDir.."/all-service-children.rbxm"),fs.readFile(afterDir.."/all-service-children.rbxm")
assert(sha(bbytes)==bm.nativeSHA256 and sha(abytes)==am.nativeSHA256,"Raw native hash mismatch")
local br,ar=rbx.deserializeModel(bbytes),rbx.deserializeModel(abytes)
local bindex,aindex={},{}
for i,root in br do local row=bm.roots[i];assert(root.Name==row.name and root.ClassName==row.class);assert(not bindex[row.path]);bindex[row.path]=root end
for i,root in ar do local row=am.roots[i];assert(root.Name==row.name and root.ClassName==row.class);assert(not aindex[row.path]);aindex[row.path]=root end
local function resolve(index,mapping,path)
 local best
 for _,row in mapping do if path==row.path or path:sub(1,#row.path+1)==row.path.."." then if not best or #row.path>#best.path then best=row end end end
 if not best then return nil end
 local cursor=index[best.path]
 for token in path:sub(#best.path+2):gmatch("[^%.]+") do cursor=cursor and cursor:FindFirstChild(token) end
 return cursor
end
local function inventory(directory)
 local list=read(directory.."/scripts.json");local index={}
 for _,row in list do
  assert(not index[row.path],"Duplicate source path")
  assert(row.editorMatch and row.sourceSha256==sha(row.source) and row.editorSourceSha256==row.sourceSha256 and #row.source==row.sourceBytes,"Source/editor proof mismatch")
  index[row.path]=row
 end
 return index
end
local bi,ai=inventory(beforeDir),inventory(afterDir)
local allowed,sourceChanges={},{}
for _,pin in manifest.rows do
 assert(not allowed[pin.path],"Duplicate approved path");allowed[pin.path]=pin
 local a=assert(ai[pin.path],"Approved after Source missing "..pin.path)
 assert(a.class==pin.className and a.sourceSha256==pin.candidateSHA256 and #a.source==pin.candidateBytes,"Installed candidate differs "..pin.path)
 local target=assert(resolve(aindex,am.roots,pin.path),"Native candidate missing")
 assert(target.ClassName==a.class and target.Source==a.source,"Native candidate differs")
 if pin.new then
  assert(pin.path=="ServerScriptService.LobbyReimaginedPreview.DevBayAccessGuard" and not bi[pin.path],"Unapproved new source")
  assert(target.ClassName=="ModuleScript","New guard class differs")
  target:Destroy() -- A local deserialized copy only, for exact outside-scope comparison.
 else
  local b=assert(bi[pin.path],"Approved baseline missing")
  assert(b.class==a.class and b.sourceSha256==pin.baselineSHA256 and #b.source==pin.baselineBytes,"Approved before differs")
  target.Source=b.source -- Local copy only; no Studio/repository Source restoration.
 end
 table.insert(sourceChanges,{path=pin.path,class=a.class,new=pin.new,before=pin.baselineSHA256,after=pin.candidateSHA256})
end
local concurrentAllowed,concurrentChanges={},{}
for _,pin in concurrentPins.rows do
 assert(concurrentExactPaths[pin.path]==pin.className and not allowed[pin.path] and not concurrentAllowed[pin.path],"Concurrent path/class outside exact scope")
 concurrentAllowed[pin.path]=true
 local b=assert(bi[pin.path],"Concurrent baseline missing")
 local a=assert(ai[pin.path],"Concurrent after missing")
 assert(b.class==pin.className and a.class==pin.className,"Concurrent class changed")
 assert(b.sourceSha256==pin.beforeSHA256 and b.sourceBytes==pin.beforeBytes,"Concurrent baseline pin differs")
 assert(a.sourceSha256==pin.afterSHA256 and a.sourceBytes==pin.afterBytes,"Concurrent after pin differs")
 local target=assert(resolve(aindex,am.roots,pin.path),"Native concurrent target missing")
 assert(target.ClassName==a.class and target.Source==a.source,"Native concurrent Source differs")
 target.Source=b.source -- Only a local deserialized copy; authoritative after body retained unchanged.
 table.insert(concurrentChanges,pin)
end
local newPath="Workspace.LobbyReimaginedPreview"
local revised,newRootFingerprint=nil,nil
if not runtimeSourcesOnly then
 assert(not bindex[newPath],"Before already contains revised model; cannot mask an existing root")
 revised=assert(aindex[newPath],"New revised native root missing")
 assert(revised.ClassName=="Model" and revised:GetAttribute("LobbyReimaginedOwned")==true
  and revised:GetAttribute("LobbyVisualRevision")==4 and revised:GetAttribute("Ready")==true
  and revised:GetAttribute("PreviewCenter")==rbx.Vector3.new(220,30,-760),"Wrong new owned revised root")
 newRootFingerprint=sha(rbx.serializeModel({revised}))
end
local ownedNewSourceRows={}
for path,row in ai do
 if not bi[path] and not allowed[path] then
  assert(not runtimeSourcesOnly and path:sub(1,#newPath+1)==newPath..".","Unexpected added Source "..path)
  table.insert(ownedNewSourceRows,{path=path,class=row.class,sha256=row.sourceSha256,bytes=row.sourceBytes})
 end
end
for path,row in bi do
 local after=assert(ai[path],"Unexpected removed Source "..path)
 if not allowed[path] and not concurrentAllowed[path] then assert(row.class==after.class and row.sourceSha256==after.sourceSha256 and row.sourceBytes==after.sourceBytes,"Remaining unrelated Source changed "..path) end
end
local bspawn=assert(resolve(bindex,bm.roots,manifest.canonicalSpawnPath))
local aspawn=assert(resolve(aindex,am.roots,manifest.canonicalSpawnPath))
assert(bspawn.ClassName=="SpawnLocation" and aspawn.ClassName==bspawn.ClassName)
if not runtimeSourcesOnly then
 local expected=rbx.CFrame.lookAt(rbx.Vector3.new(table.unpack(manifest.spawnPosition)),rbx.Vector3.new(table.unpack(manifest.spawnLookAt)))
 assert(aspawn.CFrame==expected,"After canonical pad has wrong CFrame")
 assert(aspawn:GetAttribute("LobbySpawnFloorModelName")=="LobbyReimaginedPreview" and aspawn:GetAttribute("LobbySpawnRevision")==4,"After spawn attributes differ")
 aspawn.CFrame=bspawn.CFrame
 for _,key in {"LobbySpawnFloorModelName","LobbySpawnRevision"} do aspawn:SetAttribute(key,bspawn:GetAttribute(key)) end
end
local normalized={}
for _,row in bm.roots do
 local root=assert(aindex[row.path],"Unrelated native root removed "..row.path)
 assert(root.ClassName==row.class and root.Name==row.name,"Unrelated root identity changed")
 table.insert(normalized,root)
end
for path in aindex do assert(bindex[path] or (not runtimeSourcesOnly and path==newPath),"Unexpected native root added "..path) end
local originalCanonical=sha(rbx.serializeModel(br))
local normalizedCanonical=sha(rbx.serializeModel(normalized))
assert(originalCanonical==normalizedCanonical,if runtimeSourcesOnly then "Native changes outside nine exact task Source patches and two exact concurrent Source changes" else "Native changes outside exact Sources/new owned R4 root/spawn CFrame+2attrs")
-- Full service properties are separate from serialized children. This task approves none.
local function serviceIndex(m)
 local out={}
 for _,row in m.services do out[row.class]=row end
 return out
end
local bs,as=serviceIndex(bm),serviceIndex(am)
local serviceDifferences={}
for class,row in bs do
 local other=as[class]
 if not other or serde.encode("json",row)~=serde.encode("json",other) then table.insert(serviceDifferences,class) end
end
for class in as do if not bs[class] then table.insert(serviceDifferences,class) end end
-- Collision groups/material overrides also live outside the forest.
for _,key in {"collisionGroups","collisionMatrix","materialOverrides"} do
 if serde.encode("json",bm[key])~=serde.encode("json",am[key]) then table.insert(serviceDifferences,key) end
end
assert(#serviceDifferences==0,"Service-level properties changed outside this task: "..table.concat(serviceDifferences,","))
local result={schema="lobby-access-spawn-exact-task-plus-concurrent-native-scope-v1",verified=true,beforeCaptureId=bm.captureId,afterCaptureId=am.captureId,
 beforeNativeSHA256=bm.nativeSHA256,afterNativeSHA256=am.nativeSHA256,manifestSHA256=sha(fs.readFile(manifestPath)),
 originalCanonicalNativeSHA256=originalCanonical,normalizedAfterCanonicalNativeSHA256=normalizedCanonical,
 approvedTaskSourceChanges=sourceChanges,concurrentSourceChanges=concurrentChanges,
 concurrentPinsSHA256=sha(fs.readFile(concurrentPinsPath)),scopeMode="runtime-nine-task-sources-plus-two-pinned-concurrent-sources",
 concurrentSourcesRemainUnchangedInAfterBackup=true,concurrentSemanticReviewClaim=false,
 strictNineTaskSourcesOnlyClaim=false,
 newOwnedRoot=if revised then {path=newPath,class="Model",canonicalSHA256=newRootFingerprint,descendants=#revised:GetDescendants(),sourceRows=ownedNewSourceRows} else nil,
 approvedNonSourceChanges=if runtimeSourcesOnly then {} else {path=manifest.canonicalSpawnPath,properties={"CFrame"},attributes={"LobbySpawnFloorModelName","LobbySpawnRevision"}},
 servicePropertyDifferences=serviceDifferences,remainingUnrelatedSourcesPreserved=true,remainingNativeForestPreserved=true,
 studioWritesPerformed=false,publicationClaim=false,limits="Offline exact nine candidate/native task Source comparison and two explicit concurrent Source pins, plus canonical remaining-forest equality. Does not claim unrelated Sources all unchanged or semantic review of concurrent changes. Existing before/after native recovery and unreadable service-property limits remain separate. Does not prove gameplay or publication."}
fs.writeFile(outputPath,serde.encode("json",result,true))
print(serde.encode("json",{verified=true,taskSourceChanges=#sourceChanges,concurrentSourceChanges=#concurrentChanges,remainingNativeForestPreserved=true,servicePropertyDifferences=#serviceDifferences},true))
