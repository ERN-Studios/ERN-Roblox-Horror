-- Edit-only, exact owned R4 asset correction. Requires a fresh native checkpoint
-- and successful real ContentProvider preload of the nine resolved Image IDs.
-- Does not edit scripts, original lobby, meshes, atlas, queues or prior payloads.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SS=game:GetService("ServerStorage")
local RUN=game:GetService("RunService")
local PLAN=HS:JSONDecode([====[{"schema":"lobby-r4-exact-pbr-rebind-plan-v1","placeId":131311258779917,"universeId":10559217407,"groupId":1039373905,"sourceName":"LobbyReimaginedBlenderSource20261001R4","beforeManifestSHA256":"b9fd7b1acc461f88a03d61668e08f005f32677948be2bba5cbb556ede6a83d57","afterManifestSHA256":"17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995","afterManifestBytes":346928,"historyName":"TextureRebindHistory20261002Laver","rows":[{"material":"tunnel_concrete","role":"color","oldDeniedAssetId":"136674094011110","newUploadedDecalId":"75668559788635","newResolvedImageId":"75893473229833","pngSHA256":"b23eba4560166b0deb6fa2e3d75c671ae2dc9ed93e93dd4267d5bb33f5491427","pixelSHA256":"63834aeae2ee5cc0bb3bad47546a95d13eac9c56936a733d237e3f78e9ce71f0"},{"material":"tunnel_concrete","role":"normal","oldDeniedAssetId":"137959369690348","newUploadedDecalId":"98621004968189","newResolvedImageId":"127271719715729","pngSHA256":"3eb9eb90cf939583ace020ddcfe91b12de2ce374d3ad5cf2d37618301d53b1d9","pixelSHA256":"61b30b715dbcfbc16261f944fc976ebaa551294654e81320fcfa78d1a7f0d56b"},{"material":"tunnel_concrete","role":"roughness","oldDeniedAssetId":"71577905370025","newUploadedDecalId":"84512412696312","newResolvedImageId":"96772314871126","pngSHA256":"64a576a561f8c8134e3b20ea3ba73797344b4c0aa9be31a8b1cafdf365ed9550","pixelSHA256":"ddb727d7034733a2ef2958b9232baba208b681d81af8fae16b8e293fe585d813"},{"material":"asphalt_road","role":"color","oldDeniedAssetId":"87451243227740","newUploadedDecalId":"88177171039397","newResolvedImageId":"122629305677764","pngSHA256":"ffbfd2d8098355696f0d491b3544d00654c0c9f97a644e3d6ac1036b2bba1dde","pixelSHA256":"ce5a37caa604b8b90160c58d9f6974f0a7822b21827bd9de21cb647c5292c7fd"},{"material":"asphalt_road","role":"normal","oldDeniedAssetId":"125125678705803","newUploadedDecalId":"117927527967116","newResolvedImageId":"124637763157232","pngSHA256":"47b9084b178bd89e6376722e37c533ce40e16f6dace5c1b4cc06109b9e061636","pixelSHA256":"1831ed3ff8157dec7fa85ef411e43f0046722f22098890689fce0318ba71bd50"},{"material":"asphalt_road","role":"roughness","oldDeniedAssetId":"109685785814527","newUploadedDecalId":"97983904867523","newResolvedImageId":"102850469487873","pngSHA256":"772bd6f0988c6fb748abdf9f5ccec8f5fa00a50188d62726a0eb0a9d272ea239","pixelSHA256":"b164d93a0e023b1a5637f6f79047be0b350c84d18420a0f1ca81626d41eaf442"},{"material":"sidewalk_concrete","role":"color","oldDeniedAssetId":"90215249737425","newUploadedDecalId":"113544700137989","newResolvedImageId":"103015335983029","pngSHA256":"f49486eff7a5cb2efa60689aac3c5b93c43491c06f5e53927e72fdbe011d2289","pixelSHA256":"013d904e80bad11a531e24f7d344beb54c64ac4b6c02922a6ec914982338321a"},{"material":"sidewalk_concrete","role":"normal","oldDeniedAssetId":"124127057153645","newUploadedDecalId":"107258143744901","newResolvedImageId":"134697002832773","pngSHA256":"6a38c1a0b17d1fde94f8795469d34a664e637731795452c7331d57d7a64d0ead","pixelSHA256":"16282629ef312b6cf2577fd9a72981a006de47938a48aab6ae05d2c5d2b7cc88"},{"material":"sidewalk_concrete","role":"roughness","oldDeniedAssetId":"115484978880140","newUploadedDecalId":"82414651760494","newResolvedImageId":"117887403540614","pngSHA256":"c4b9aba746b93d545b9a4e003d4ff1403ccc98fcf5f4adc3a67e6a95f16642aa","pixelSHA256":"a05945c00e7271023a2b5382fcf64d77df8880dbb522220b62a6abddfc2a9960"}]}]====])
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
