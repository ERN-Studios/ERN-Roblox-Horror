-- Scoped R4 preview import. Original lobby and existing payloads are preserved.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local SER=game:GetService("SerializationService")
local SS=game:GetService("ServerStorage")
local RUN=game:GetService("RunService")
local PLAN=HS:JSONDecode([=[{"readyForInstaller":false,"placeId":131311258779917,"universeId":10559217407,"groupId":1039373905,"sources":[{"key":"builder","path":"ServerScriptService.LobbyReimaginedPreview.Builder","class":"ModuleScript","isNew":false,"expectedSourceSHA256":"1b2f45d140545009a82cca7f5f9400453d3860cd1bc0aa2e4fb39ef96ec97338","expectedEditorSourceSHA256":"1b2f45d140545009a82cca7f5f9400453d3860cd1bc0aa2e4fb39ef96ec97338","expectedBeforeBytes":11114,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/Builder.ModuleScript.luau","sourceURLPath":"/source/builder","candidateBytes":11266,"afterSHA256":"a4c4313b9291e412e860f1eb106d17851d25779108f1a900f9967f83e2fb9dcd","observedCandidateSHA256":"a4c4313b9291e412e860f1eb106d17851d25779108f1a900f9967f83e2fb9dcd","status":"PINNED_LOCAL_CANDIDATE","owned":true,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"},{"key":"runtime-bake","path":"ServerScriptService.LobbyReimaginedPreview.RuntimeBake","class":"ModuleScript","isNew":false,"expectedSourceSHA256":"c022cdb69d117c1654e398881dee6bd1621d9945e0e6747f3059185b65b07c5d","expectedEditorSourceSHA256":"c022cdb69d117c1654e398881dee6bd1621d9945e0e6747f3059185b65b07c5d","expectedBeforeBytes":8508,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/RuntimeBake.ModuleScript.luau","sourceURLPath":"/source/runtime-bake","candidateBytes":12341,"afterSHA256":"1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28","observedCandidateSHA256":"1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28","status":"PINNED_LOCAL_CANDIDATE","owned":true,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"},{"key":"queue-bridge","path":"ServerScriptService.LobbyReimaginedPreview.QueueBridge","class":"ModuleScript","isNew":false,"expectedSourceSHA256":"19efa5af64c7097c08be95875ea5c6aa040dface8da09670cd9b702e9b0437fa","expectedEditorSourceSHA256":"19efa5af64c7097c08be95875ea5c6aa040dface8da09670cd9b702e9b0437fa","expectedBeforeBytes":3598,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/ServerScriptService.LobbyReimaginedPreview.QueueBridge.ModuleScript.candidate.luau","sourceURLPath":"/source/queue-bridge","candidateBytes":20210,"afterSHA256":"1a5e14256a7725a35b0b13a6d31b6fd4ea47d14875368d46e9593fe365226e08","observedCandidateSHA256":"1a5e14256a7725a35b0b13a6d31b6fd4ea47d14875368d46e9593fe365226e08","status":"PINNED_LOCAL_CANDIDATE","owned":true,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"},{"key":"game-manager","path":"ServerScriptService.GameManager","class":"Script","isNew":false,"expectedSourceSHA256":"7dc0483fc2cbbc4dd835b56531bbd565cbdf30c347f3fc9fa4950e207aa8cc5d","expectedEditorSourceSHA256":"7dc0483fc2cbbc4dd835b56531bbd565cbdf30c347f3fc9fa4950e207aa8cc5d","expectedBeforeBytes":163203,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/ServerScriptService.GameManager.Script.candidate.luau","sourceURLPath":"/source/game-manager","candidateBytes":165258,"afterSHA256":"951c6af430bf99d9ece0caf858545d2d00e59683155067d3c5e4d398e9997f34","observedCandidateSHA256":"951c6af430bf99d9ece0caf858545d2d00e59683155067d3c5e4d398e9997f34","status":"PINNED_LOCAL_CANDIDATE","owned":false,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"},{"key":"level4-preview","path":"ServerScriptService.Level4V4PreviewAccess","class":"Script","isNew":false,"expectedSourceSHA256":"2628089773ec0ca8610b8d01925a0d96ca25d39db8be4c687ccdf7809cb6abe8","expectedEditorSourceSHA256":"2628089773ec0ca8610b8d01925a0d96ca25d39db8be4c687ccdf7809cb6abe8","expectedBeforeBytes":10629,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/ServerScriptService.Level4V4PreviewAccess.Script.candidate.luau","sourceURLPath":"/source/level4-preview","candidateBytes":12317,"afterSHA256":"b4f8fe4aeada5d9eb26e2d0e538889dd7dc10d52c53e5a42f63796831f20ea40","observedCandidateSHA256":"b4f8fe4aeada5d9eb26e2d0e538889dd7dc10d52c53e5a42f63796831f20ea40","status":"PINNED_LOCAL_CANDIDATE","owned":false,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"},{"key":"level5-preview","path":"ServerScriptService.Level5PreviewAccess","class":"Script","isNew":false,"expectedSourceSHA256":"323d5d2504b1595048eccc7228b8c9054f9e5ec4d27b32aff5f884c2ceeacc8d","expectedEditorSourceSHA256":"323d5d2504b1595048eccc7228b8c9054f9e5ec4d27b32aff5f884c2ceeacc8d","expectedBeforeBytes":10544,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/ServerScriptService.Level5PreviewAccess.Script.candidate.luau","sourceURLPath":"/source/level5-preview","candidateBytes":12232,"afterSHA256":"07659b8077f3dc58869113e3371b906bbead0408edbb8d84ad21d746f7ee420f","observedCandidateSHA256":"07659b8077f3dc58869113e3371b906bbead0408edbb8d84ad21d746f7ee420f","status":"PINNED_LOCAL_CANDIDATE","owned":false,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"},{"key":"level6-preview","path":"ServerScriptService.Level6PreviewAccess","class":"Script","isNew":false,"expectedSourceSHA256":"fa071896a9ac231399d09da41bc3ea26771e174c2ad37bc7ae2b6c5de5217651","expectedEditorSourceSHA256":"fa071896a9ac231399d09da41bc3ea26771e174c2ad37bc7ae2b6c5de5217651","expectedBeforeBytes":10762,"editorMatch":true,"editorHashBasis":"Published native export editorMatch=true; editor Source byte-equal to captured Source","candidateFile":"tools/lobby_reimagined/r4_candidates/ServerScriptService.Level6PreviewAccess.Script.candidate.luau","sourceURLPath":"/source/level6-preview","candidateBytes":12632,"afterSHA256":"0829dc2fed34719fde2937a51a7a18f22f7ea64aa5d89ae06cbc2bb54b193868","observedCandidateSHA256":"0829dc2fed34719fde2937a51a7a18f22f7ea64aa5d89ae06cbc2bb54b193868","status":"PINNED_LOCAL_CANDIDATE","owned":false,"scope":"Exact scoped existing Source update; fresh live identity/Source/editor CAS still required"}],"preservedSources":[{"path":"ServerScriptService.LobbyReimaginedPreview.Bootstrap","class":"Script","bytes":1217,"sourceSHA256":"f2f1ce2c0eca8eda358ed22902ef2072acaa4fdfbe893db0623422c2aca09eee","editorSourceSHA256":"f2f1ce2c0eca8eda358ed22902ef2072acaa4fdfbe893db0623422c2aca09eee","editorMatch":true,"scope":"Preserve; no Source write authorized by this catalog"},{"path":"StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController","class":"LocalScript","bytes":4105,"sourceSHA256":"7f33b95af12201c32bad76974fd0c768e89d7ef2722482e2c908dd00152870f7","editorSourceSHA256":"7f33b95af12201c32bad76974fd0c768e89d7ef2722482e2c908dd00152870f7","editorMatch":true,"scope":"Preserve; no Source write authorized by this catalog"}],"sourceName":"LobbyReimaginedBlenderSource20261001R4","manifestBytes":345751,"manifestSHA256":"5fa07c5e2f9edf53f288096e8a5853591d0e384ce81600583294a34d6d7c0c56","catalogSHA256":"d395bbe1c53b4b957005afb13aee362e3ca1e99e5e8327133968b757a3263627"}]=])
local BASE="http://127.0.0.1:8896"
local BACKUP="http://127.0.0.1:8891"
local OWNED="LobbyReimaginedOwned"
assert(PLAN.readyForInstaller==true,"Published static PBR maps are not pinned; regenerate this installer")
assert(game.PlaceId==PLAN.placeId and game.GameId==PLAN.universeId and game.CreatorId==PLAN.groupId,"Wrong place/owner")
assert(not RUN:IsRunning(),"Edit-only installation")
assert(HS.HttpEnabled,"Existing HTTP must be enabled; do not alter game settings")
assert(not SS:FindFirstChild(PLAN.sourceName),"R4 payload already exists; inspect before continuing")
local function sha(raw)
 local b=ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256);local out={}
 for i=0,buffer.len(b)-1 do out[i+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(out)
end
local function resolve(path)
 local cursor=game
 for token in path:gmatch("[^%.]+") do
  if not cursor then return nil end
  local found
  for _,child in ipairs(cursor:GetChildren()) do
   if child.Name==token then assert(not found,"Ambiguous exact path: "..path);found=child end
  end
  cursor=found
 end
 return cursor
end
local recovery=assert(shared.__r4NativeRecovery,"Fresh session-native checkpoint is missing")
assert(recovery.schema=="lobby-r4-session-recovery-baseline-v1" and recovery.allPostsAcknowledged==true)
assert(recovery.placeId==PLAN.placeId and recovery.universeId==PLAN.universeId and recovery.groupId==PLAN.groupId)
local function recoveryFresh()
 assert(shared.__r4NativeRecovery==recovery and not RUN:IsRunning(),"Checkpoint or Edit state changed")
 assert(DateTime.now().UnixTimestamp-recovery.capturedAtUnix>=0
  and DateTime.now().UnixTimestamp-recovery.capturedAtUnix<=1800,"Refresh the native checkpoint before installation")
 local expectedRoots={}
 assert(#recovery.roots==#recovery.rootMappings and #recovery.sourceRows==recovery.sourceCount)
 for i,root in ipairs(recovery.roots) do
  local row=recovery.rootMappings[i]
  -- GetFullName is descriptive, not a tokenized path: native root names may
  -- contain decimal dots. Keep the captured Instance and exact service/name.
  assert(root.Parent==game:FindService(row.service) and root.Name==row.name
   and root:GetFullName()==row.path and root.ClassName==row.class and root.Archivable,
   "Native root identity changed: "..row.path)
  expectedRoots[root]=true
 end
 local count=0
 for _,class in ipairs(recovery.serviceClasses) do
  local service=assert(game:FindService(class),"Captured service disappeared")
  for _,root in ipairs(service:GetChildren()) do
   assert(root.Archivable and expectedRoots[root],"Native root set changed; capture a new checkpoint")
   count+=1
  end
 end
 assert(count==#recovery.roots,"Native root count changed")
 for _,row in ipairs(recovery.sourceRows) do
  local instance=row.instance
  assert(instance:IsDescendantOf(game) and instance:GetFullName()==row.path and instance.ClassName==row.class
   and instance.Source==row.source and SES:GetEditorSource(instance)==row.source,
   "Source/editor changed since checkpoint: "..row.path)
 end
end
recoveryFresh()
local checkpoint=HS:JSONDecode(HS:GetAsync(BACKUP.."/checkpoint",true))
assert(checkpoint.verified==true and checkpoint.captureId==recovery.captureId
 and checkpoint.nativeSHA256==recovery.nativeSHA256 and checkpoint.placeId==PLAN.placeId
 and checkpoint.universeId==PLAN.universeId and checkpoint.groupId==PLAN.groupId,
 "Verified disk recovery does not match this live session")
local baseline={}
for _,spec in ipairs(PLAN.sources) do
 local instance=assert(resolve(spec.path),"Scoped Source missing: "..spec.path)
 assert(instance.ClassName==spec.class,"Scoped Source class changed")
 if spec.owned then assert(instance:GetAttribute(OWNED)==true,"Preview ownership differs") end
 local raw=instance.Source
 assert(#raw==spec.expectedBeforeBytes and sha(buffer.fromstring(raw))==spec.expectedSourceSHA256
  and SES:GetEditorSource(instance)==raw,"Fresh scoped Source/editor differs: "..spec.path)
 baseline[spec.path]={instance=instance,source=raw}
end
local function scopedFresh()
 assert(not RUN:IsRunning(),"Studio entered Play during installation")
 for _,spec in ipairs(PLAN.sources) do
  local row=baseline[spec.path]
  assert(resolve(spec.path)==row.instance and row.instance.ClassName==spec.class
   and row.instance.Source==row.source and SES:GetEditorSource(row.instance)==row.source,
   "Scoped Source changed during preparation: "..spec.path)
 end
 for _,spec in ipairs(PLAN.preservedSources) do
  local instance=assert(resolve(spec.path))
  assert(instance.ClassName==spec.class and sha(buffer.fromstring(instance.Source))==spec.sourceSHA256
   and SES:GetEditorSource(instance)==instance.Source,"Preserved preview controller changed; reconcile it")
 end
end
local staging=Instance.new("Folder");staging.Name=PLAN.sourceName;staging:SetAttribute(OWNED,true)
local applied,attempted={},{}
local function compressed(name,raw,parent,spec)
 assert(buffer.len(raw)==spec.bytes and sha(raw)==spec.sha256,"R4 payload hash differs: "..name)
 local folder=Instance.new("Folder");folder.Name=name;folder.Parent=parent
 local packed=ENC:CompressBuffer(raw,Enum.CompressionAlgorithm.Zstd,3)
 local encoded=buffer.tostring(ENC:Base64Encode(packed))
 for offset=1,#encoded,60000 do
  local piece=Instance.new("StringValue");piece.Name=string.format("%05d",math.floor((offset-1)/60000))
  piece.Value=encoded:sub(offset,offset+59999);piece.Parent=folder
 end
 folder:SetAttribute("RawBytes",buffer.len(raw));folder:SetAttribute("RawSHA256",spec.sha256)
 folder:SetAttribute("CompressedBytes",buffer.len(packed))
end
local ok,why=pcall(function()
 local catalogBytes=HS:GetAsync(BASE.."/catalog",true)
 assert(sha(buffer.fromstring(catalogBytes))==PLAN.catalogSHA256,"Served source catalog differs")
 local raw=buffer.fromstring(HS:GetAsync(BASE.."/manifest",true))
 compressed("ManifestJSON",raw,staging,{bytes=PLAN.manifestBytes,sha256=PLAN.manifestSHA256})
 local manifest=HS:JSONDecode(buffer.tostring(raw))
 assert(manifest.schema=="lobby-reimagined-blender-v2" and manifest.revision==4)
 local meshes=Instance.new("Folder");meshes.Name="Meshes";meshes.Parent=staging
 for _,chunk in ipairs(manifest.chunks) do
  compressed(tostring(chunk.id),ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/chunk/"..chunk.id,true))),meshes,chunk)
 end
 compressed("AtlasPixels",ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/pixels/atlas",true))),staging,manifest.atlas)
 local templates=Instance.new("Folder");templates.Name="StaticPBRMaterials";templates:SetAttribute(OWNED,true);templates.Parent=staging
 local properties={color="ColorMap",normal="NormalMap",roughness="RoughnessMap"}
 local contentProperties={color="ColorMapContent",normal="NormalMapContent",roughness="RoughnessMapContent"}
 local count=0
 for key,spec in pairs(manifest.materials) do
  assert(key=="tunnel_concrete" or key=="asphalt_road" or key=="sidewalk_concrete")
  local appearance=Instance.new("SurfaceAppearance");appearance.Name=key;appearance:SetAttribute(OWNED,true)
  appearance.Parent=templates -- Off-tree staging owns it even if protected map assignment fails.
  appearance.AlphaMode=Enum.AlphaMode.Overlay;appearance.Color=Color3.new(1,1,1);appearance.MetalnessMap=""
  for _,role in ipairs({"color","normal","roughness"}) do
   local map=spec.maps[role];local id=map.assetId
   assert(type(id)=="string" and string.match(id,"^[1-9]%d*$"),"Unpublished PBR map")
   appearance[properties[role]]="rbxassetid://"..id
   local content=appearance[contentProperties[role]]
   assert(content.SourceType==Enum.ContentSourceType.Uri and content.Uri=="rbxassetid://"..id,"PBR template reference differs")
   appearance:SetAttribute(role.."PNG_SHA256",map.pngSHA256)
  end
  assert(spec.maps.normal.normalConvention=="OpenGL")
  count+=1
 end
 assert(count==3,"Wrong PBR template count")
 local texts={}
 for _,spec in ipairs(PLAN.sources) do
  local text=HS:GetAsync(BASE..spec.sourceURLPath,true)
  assert(#text==spec.candidateBytes and sha(buffer.fromstring(text))==spec.afterSHA256,"Candidate hash differs: "..spec.path)
  texts[spec.path]=text
 end
 -- No persistent changes have occurred. Reconcile the complete live baseline.
 recoveryFresh();scopedFresh()
 local current=SER:SerializeInstancesAsync(recovery.roots)
 assert(buffer.len(current)==recovery.nativeBytes and sha(current)==recovery.nativeSHA256,
  "Live native geometry/properties changed; capture and reconcile a new checkpoint")
 recoveryFresh();scopedFresh()
 assert(not SS:FindFirstChild(PLAN.sourceName),"Concurrent R4 payload appeared")
 staging:SetAttribute("ManifestSHA256",PLAN.manifestSHA256);staging:SetAttribute("Ready",true)
 staging:SetAttribute("RecoveryCaptureId",recovery.captureId);staging.Parent=SS
 for _,spec in ipairs(PLAN.sources) do
  local row=baseline[spec.path]
  assert(not RUN:IsRunning() and resolve(spec.path)==row.instance and row.instance.ClassName==spec.class
   and row.instance.Source==row.source and SES:GetEditorSource(row.instance)==row.source,
   "Fresh Source changed immediately before write: "..spec.path)
  table.insert(attempted,{path=spec.path,class=spec.class,beforeSHA256=spec.expectedSourceSHA256,afterSHA256=spec.afterSHA256})
  SES:UpdateSourceAsync(row.instance,function(editor)
   assert(not RUN:IsRunning() and resolve(spec.path)==row.instance and editor==row.source
    and row.instance.Source==row.source,"Source changed inside scoped CAS: "..spec.path)
   if spec.owned then assert(row.instance:GetAttribute(OWNED)==true,"Preview ownership changed inside scoped CAS") end
   return texts[spec.path]
  end)
  assert(row.instance.Source==texts[spec.path] and SES:GetEditorSource(row.instance)==texts[spec.path],"Post-write editor conflict")
  table.insert(applied,{path=spec.path,class=spec.class,sha256=spec.afterSHA256})
  if spec.owned then row.instance:SetAttribute("InstalledSourceSHA256",spec.afterSHA256) end
 end
end)
if not ok then
 local snapshots={}
 for _,spec in ipairs(PLAN.sources) do
  local record={path=spec.path,expectedClass=spec.class}
  local readOK,readError=pcall(function()
   local instance=assert(resolve(spec.path),"Scoped instance missing")
   record.class=instance.ClassName
   record.sourceSHA256=sha(buffer.fromstring(instance.Source))
   record.editorSHA256=sha(buffer.fromstring(SES:GetEditorSource(instance)))
   record.installedAttribute=instance:GetAttribute("InstalledSourceSHA256")
  end)
  if not readOK then record.snapshotError=tostring(readError) end
  table.insert(snapshots,record)
 end
 local payloadParented=staging.Parent~=nil
 if not staging.Parent then staging:Destroy() end -- Only unparented task staging objects.
 shared.__r4InstallFailure={error=tostring(why),attempted=attempted,applied=applied,sourceSnapshots=snapshots,payloadParented=payloadParented}
 error("R4 import stopped; do not publish. Reconcile partial writes against fresh Studio: "..tostring(why))
end
local receipt={installed=true,placeId=game.PlaceId,sourceName=PLAN.sourceName,manifestSHA256=PLAN.manifestSHA256,
 recoveryCaptureId=recovery.captureId,sources=applied,requiresPlayVerification=true}
shared.__r4InstallReceipt=receipt
return receipt
