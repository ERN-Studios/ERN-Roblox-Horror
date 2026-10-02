-- Edit-only, exact owned R4 asset correction. Requires a fresh native checkpoint
-- and successful real ContentProvider preload of the nine resolved Image IDs.
-- Does not edit scripts, original lobby, meshes, atlas, queues or prior payloads.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SS=game:GetService("ServerStorage")
local RUN=game:GetService("RunService")
local PLAN=HS:JSONDecode(__PLAN__)
local BASE="http://127.0.0.1:8896"
local OWNED="LobbyReimaginedOwned"
assert(not RUN:IsRunning(),"Edit-only PBR rebind; stop Play first")
assert(game.PlaceId==PLAN.placeId and game.GameId==PLAN.universeId
 and game.CreatorId==PLAN.groupId,"Wrong place/owner")
assert(PLAN.schema=="lobby-r4-exact-pbr-rebind-plan-v1" and #PLAN.rows==9)
assert(HS.HttpEnabled,"Existing HTTP must be enabled; do not change game settings")
local function sha(raw)
 local digest=ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256)
 local out={};for i=0,buffer.len(digest)-1 do out[i+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(out)
end
local function exact(parent,name,class)
 local found
 for _,child in ipairs(parent:GetChildren()) do
  if child.Name==name then assert(not found,"Ambiguous owned child: "..name);found=child end
 end
 assert(found and found.ClassName==class,"Missing/wrong owned child: "..name)
 return found
end
local function decode(folder)
 local pieces=folder:GetChildren();table.sort(pieces,function(a,b)return a.Name<b.Name end)
 assert(#pieces>0,"Empty owned manifest")
 local encoded={}
 for i,piece in ipairs(pieces) do
  assert(piece.ClassName=="StringValue" and piece.Name==string.format("%05d",i-1),"Wrong manifest piece")
  encoded[i]=piece.Value
 end
 local packed=ENC:Base64Decode(buffer.fromstring(table.concat(encoded)))
 assert(buffer.len(packed)==folder:GetAttribute("CompressedBytes"),"Wrong compressed manifest length")
 local raw=ENC:DecompressBuffer(packed,Enum.CompressionAlgorithm.Zstd)
 assert(buffer.len(raw)==folder:GetAttribute("RawBytes") and sha(raw)==folder:GetAttribute("RawSHA256"),"Wrong manifest raw hash")
 return raw
end
local function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for key,value in pairs(a) do if not same(value,b[key]) then return false end end
 for key in pairs(b) do if a[key]==nil then return false end end
 return true
end
local mapProperty={color="ColorMap",normal="NormalMap",roughness="RoughnessMap"}
local contentProperty={color="ColorMapContent",normal="NormalMapContent",roughness="RoughnessMapContent"}
local source=exact(SS,PLAN.sourceName,"Folder")
local manifestFolder=exact(source,"ManifestJSON","Folder")
local templates=exact(source,"StaticPBRMaterials","Folder")
assert(source:GetAttribute(OWNED)==true and source:GetAttribute("Ready")==true)
assert(templates:GetAttribute(OWNED)==true and #templates:GetChildren()==3)
assert(source:GetAttribute("ManifestSHA256")==PLAN.beforeManifestSHA256,"Fresh source manifest differs")
assert(not source:FindFirstChild(PLAN.historyName),"This rebind history already exists; inspect the actual prior result")
local beforeRaw=decode(manifestFolder)
assert(sha(beforeRaw)==PLAN.beforeManifestSHA256,"Fresh compressed manifest differs")
local before=HS:JSONDecode(buffer.tostring(beforeRaw))
local materials,seen={},{}
for _,row in ipairs(PLAN.rows) do
 assert(mapProperty[row.role] and type(row.newResolvedImageId)=="string"
  and row.newResolvedImageId:match("^[1-9]%d*$"),"Invalid map/image plan")
 local key=row.material.."/"..row.role;assert(not seen[key],"Duplicate map in plan");seen[key]=true
 local spec=before.materials[row.material].maps[row.role]
 assert(spec.assetId==row.oldDeniedAssetId and spec.pngSHA256==row.pngSHA256
  and spec.sha256==row.pixelSHA256,"Old manifest map differs: "..key)
 local appearance=materials[row.material] or exact(templates,row.material,"SurfaceAppearance")
 materials[row.material]=appearance
end
local recoveryCaptureId=source:GetAttribute("RecoveryCaptureId")
local function baselineFresh()
 assert(not RUN:IsRunning() and exact(SS,PLAN.sourceName,"Folder")==source)
 assert(source:GetAttribute(OWNED)==true and source:GetAttribute("Ready")==true
  and source:GetAttribute("ManifestSHA256")==PLAN.beforeManifestSHA256
  and source:GetAttribute("RecoveryCaptureId")==recoveryCaptureId)
 assert(exact(source,"ManifestJSON","Folder")==manifestFolder
  and exact(source,"StaticPBRMaterials","Folder")==templates
  and templates:GetAttribute(OWNED)==true and #templates:GetChildren()==3)
 assert(not source:FindFirstChild(PLAN.historyName),"Concurrent rebind appeared")
 assert(sha(decode(manifestFolder))==PLAN.beforeManifestSHA256,"Manifest changed during preparation")
 for _,row in ipairs(PLAN.rows) do
  local appearance=materials[row.material]
  assert(exact(templates,row.material,"SurfaceAppearance")==appearance
   and appearance:GetAttribute(OWNED)==true,"PBR identity/ownership changed")
  assert(appearance.AlphaMode==Enum.AlphaMode.Overlay and appearance.Color==Color3.new(1,1,1)
   and appearance.MetalnessMapContent.SourceType==Enum.ContentSourceType.None,"PBR unchanged properties differ")
  local content=appearance[contentProperty[row.role]]
  assert(content.SourceType==Enum.ContentSourceType.Uri
   and content.Uri=="rbxassetid://"..row.oldDeniedAssetId
   and appearance:GetAttribute(row.role.."PNG_SHA256")==row.pngSHA256,"Fresh old PBR URI/hash differs")
 end
end
baselineFresh()
-- Only this network read yields. All preparations remain off-tree.
local afterRaw=buffer.fromstring(HS:GetAsync(BASE.."/manifest",true))
assert(buffer.len(afterRaw)==PLAN.afterManifestBytes and sha(afterRaw)==PLAN.afterManifestSHA256,"Served replacement manifest differs")
local after=HS:JSONDecode(buffer.tostring(afterRaw))
local restored=HS:JSONDecode(buffer.tostring(afterRaw))
for _,row in ipairs(PLAN.rows) do
 assert(after.materials[row.material].maps[row.role].assetId==row.newResolvedImageId,"Replacement Image ID differs")
 restored.materials[row.material].maps[row.role].assetId=row.oldDeniedAssetId
end
assert(same(before,restored),"Replacement changes something beyond the nine owned PBR Image IDs")
local staged=Instance.new("Folder");staged.Name="ManifestJSON_rebound_staging"
local packed=ENC:CompressBuffer(afterRaw,Enum.CompressionAlgorithm.Zstd,3)
local encoded=buffer.tostring(ENC:Base64Encode(packed))
for offset=1,#encoded,60000 do
 local piece=Instance.new("StringValue");piece.Name=string.format("%05d",math.floor((offset-1)/60000))
 piece.Value=encoded:sub(offset,offset+59999);piece.Parent=staged
end
staged:SetAttribute("RawBytes",buffer.len(afterRaw));staged:SetAttribute("RawSHA256",PLAN.afterManifestSHA256)
staged:SetAttribute("CompressedBytes",buffer.len(packed));assert(sha(decode(staged))==PLAN.afterManifestSHA256)
local history=Instance.new("Folder");history.Name=PLAN.historyName;history:SetAttribute(OWNED,true)
history:SetAttribute("BeforeManifestSHA256",PLAN.beforeManifestSHA256)
history:SetAttribute("AfterManifestSHA256",PLAN.afterManifestSHA256)
local snapshot=manifestFolder:Clone();snapshot.Name="ManifestJSON_before_copy";snapshot.Parent=history
local planRecord=Instance.new("StringValue");planRecord.Name="ExactRebindPlanJSON";planRecord.Value=HS:JSONEncode(PLAN);planRecord.Parent=history
baselineFresh() -- Exact references/properties/bytes rechecked inside the write.
local attempted,applied={},{}
local ok,why=xpcall(function()
 -- A partial failure cannot leave a payload advertised as Ready.
 source:SetAttribute("Ready",false);history.Parent=source
 for _,row in ipairs(PLAN.rows) do
  local appearance=materials[row.material];local key=row.material.."/"..row.role
  table.insert(attempted,key)
  appearance[mapProperty[row.role]]="rbxassetid://"..row.newResolvedImageId
  local content=appearance[contentProperty[row.role]]
  assert(content.SourceType==Enum.ContentSourceType.Uri and content.Uri=="rbxassetid://"..row.newResolvedImageId,"Rebound URI differs")
  table.insert(applied,key)
 end
 staged.Parent=source
 manifestFolder.Name="ManifestJSON_original";manifestFolder.Parent=history
 staged.Name="ManifestJSON"
 source:SetAttribute("ManifestSHA256",PLAN.afterManifestSHA256)
 assert(exact(source,"ManifestJSON","Folder")==staged and sha(decode(staged))==PLAN.afterManifestSHA256)
 for _,row in ipairs(PLAN.rows) do
  local appearance=materials[row.material];local content=appearance[contentProperty[row.role]]
  assert(content.SourceType==Enum.ContentSourceType.Uri and content.Uri=="rbxassetid://"..row.newResolvedImageId
   and appearance:GetAttribute(row.role.."PNG_SHA256")==row.pngSHA256)
 end
 history:SetAttribute("Complete",true);source:SetAttribute("Ready",true)
end,function(err)return tostring(err) end)
local receipt={schema="lobby-r4-static-pbr-rebind-result-v1",success=ok,attempted=attempted,applied=applied,
 beforeManifestSHA256=PLAN.beforeManifestSHA256,afterManifestSHA256=PLAN.afterManifestSHA256,
 observedManifestSHA256=source:GetAttribute("ManifestSHA256"),observedReady=source:GetAttribute("Ready"),
 originalManifestPreserved=manifestFolder:IsDescendantOf(history),historyName=PLAN.historyName,
 noScriptsEdited=true,noOriginalLobbyEdited=true,rootMustVerifyFreshPlay=true,error=if ok then nil else why}
shared.__r4AssetRebindResult=receipt
if not ok then
 -- Preserve partial state and prepared recovery data; never revert over a new edit.
 shared.__r4AssetRebindFailedStage={history=history,manifest=staged,source=source}
 history:SetAttribute("Complete",false)
 warn(HS:JSONEncode(receipt));error("PBR rebind incomplete; inspect actual Ready state and the preserved receipt: "..tostring(why))
end
print(HS:JSONEncode(receipt))
