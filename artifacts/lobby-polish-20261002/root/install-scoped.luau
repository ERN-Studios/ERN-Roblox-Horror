-- Native Edit command only. Fresh exact instance/Source/editor CAS; no bulk sync.
local H=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local BASE="http://127.0.0.1:8905"
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong authoritative place")
assert(H.HttpEnabled,"Do not change game HTTP setting")
local gate=H:JSONDecode(H:GetAsync("http://127.0.0.1:8903/checkpoint",true))
assert(gate.verified and gate.placeId==game.PlaceId and gate.universeId==game.GameId and gate.groupId==game.CreatorId,"Native recovery proof missing")
local marker=shared.__lobbyPolishBeforeNativeRecovery
assert(marker and marker.captureId==gate.captureId and marker.nativeSHA256==gate.nativeSHA256 and marker.allPostsAcknowledged,"Fresh session recovery proof differs")
local function hash(s) return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",string.byte(c))end)) end
local rawCatalog=H:GetAsync(BASE.."/catalog",true)
assert(hash(rawCatalog)=="a7b74111671b2baaa3dba2e8ac4602e1d5f9c9d6569436d4381cc90426c6f7d1","Reviewed catalog bytes changed")
local C=H:JSONDecode(rawCatalog)
local function at(path)
 local i=game
 for segment in path:gmatch("[^.]+") do i=assert(i:FindFirstChild(segment),"Missing exact live path "..path) end
 return i
end
local parent=at("ServerScriptService.LobbyReimaginedPreview")
assert(parent:IsA("Folder") and parent:GetAttribute("LobbyReimaginedOwned")==true,"Foreign preview owner")
local clientParent=at("StarterPlayer.StarterPlayerScripts")
assert(clientParent:IsA("StarterPlayerScripts"))
local ids,expected={},{}
for _,row in ipairs(C.baseline) do
 assert(row.editorMatch and row.editorSourceSha256==row.sourceSha256)
 ids[row.path]=at(row.path);expected[row.path]=row.sourceSha256
end
local function verify()
 assert(at("StarterPlayer.StarterPlayerScripts")==clientParent and clientParent:IsA("StarterPlayerScripts"),"Client parent changed")
 assert(not game:GetService("RunService"):IsRunning() and not workspace:FindFirstChild("LobbyReimaginedPreview"),"Edit preview conflict")
 assert(at("ServerScriptService.LobbyReimaginedPreview")==parent and parent:GetAttribute("LobbyReimaginedOwned")==true,"Preview owner changed")
 for _,row in ipairs(C.baseline) do
  local i=at(row.path)
  assert(i==ids[row.path] and i.ClassName==row.class and hash(i.Source)==expected[row.path] and hash(SES:GetEditorSource(i))==expected[row.path],"Fresh baseline changed: "..row.path)
 end
 for _,row in ipairs(C.sources) do
  assert(hash(row.source)==row.sha256,"Candidate hash mismatch")
  if row.new then local path,name=row.path:match("^(.*)%.([^.]*)$");assert(not at(path):FindFirstChild(name),"New helper name conflict") end
 end
 local raw=at("ServerStorage.LobbyReimaginedBlenderSource20261001R4")
 assert(raw:GetAttribute("LobbyReimaginedOwned")==true and raw:GetAttribute("Ready")==true and raw:GetAttribute("ManifestSHA256")=="17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995","Raw source changed")
end
verify()
local prepared={}
for _,row in ipairs(C.sources) do
 if row.new then
  local i=Instance.new(row.className);i.Name=row.path:match("([^.]*)$")
  i:SetAttribute("LobbyReimaginedOwned",true);i:SetAttribute("InstalledSourceSHA256",row.sha256)
  SES:UpdateSourceAsync(i,function()return row.source end)
  assert(hash(i.Source)==row.sha256 and hash(SES:GetEditorSource(i))==row.sha256,"Prepared source/editor mismatch")
  prepared[row.path]=i
 end
end
local mat=assert(prepared["ServerScriptService.LobbyReimaginedPreview.MaterialPolish"])
local folder=Instance.new("Folder");folder.Name="StaticPBRMaterials";folder:SetAttribute("LobbyReimaginedOwned",true);folder.Parent=mat
local preloads={}
for key,maps in pairs(C.assets.materials) do
 local appearance=Instance.new("SurfaceAppearance");appearance.Name=key
 appearance:SetAttribute("LobbyReimaginedOwned",true);appearance.AlphaMode=Enum.AlphaMode.Overlay;appearance.Color=Color3.new(1,1,1)
 for role,property in pairs({color="ColorMapContent",normal="NormalMapContent",roughness="RoughnessMapContent"}) do
  local uri=maps[role].uri;assert(uri:match("^rbxassetid://[1-9]%d*$"),"Invalid static asset URI")
  appearance[property]=Content.fromUri(uri);appearance:SetAttribute(role.."PNG_SHA256",maps[role].pngSHA256);table.insert(preloads,uri)
 end
 appearance.Parent=folder
end
local atlas=Instance.new("StringValue");atlas.Name="SidewalkAtlas";atlas.Value=assert(C.assets.sidewalkAtlas.uri:match("^rbxassetid://([1-9]%d*)$"))
atlas:SetAttribute("LobbyReimaginedOwned",true);atlas:SetAttribute("PNG_SHA256",C.assets.sidewalkAtlas.pngSHA256);atlas.Parent=mat
table.insert(preloads,C.assets.sidewalkAtlas.uri)
-- Preload exact image Instances: raw-string callbacks can fail for uploaded image IDs.
-- Roblox documents invisible ImageLabel texture downloads, while SurfaceAppearance
-- texture packs are unsupported by PreloadAsync and still need actual Play verification.
local fetch,imageFetchRows={},{}
local imageProbes,uniqueImageURIs={},{}
local imagePreflightOk,imagePreflightError=pcall(function()
 assert(#preloads==10,"Expected exactly ten reviewed static images")
 for index,uri in ipairs(preloads) do
  assert(uri:match("^rbxassetid://[1-9]%d*$") and not uniqueImageURIs[uri],"Duplicate or invalid reviewed image URI")
  uniqueImageURIs[uri]=true
  local probe=Instance.new("ImageLabel");table.insert(imageProbes,probe)
  probe.Name="LobbyPolishDetachedImageFetchProbe"..index;probe.Image=uri
  assert(probe.Parent==nil,"Temporary image probe must stay detached")
 end
 game:GetService("ContentProvider"):PreloadAsync(imageProbes,function(uri,status)fetch[uri]=status.Name end)
 for index,probe in ipairs(imageProbes) do
  local uri=preloads[index]
  assert(probe.Parent==nil,"Temporary image probe was unexpectedly parented")
  table.insert(imageFetchRows,{uri=uri,imageAssetId=uri:match("^rbxassetid://(%d+)$"),
   status=fetch[uri],ImageLabelIsLoaded=probe.IsLoaded,detached=true})
  -- Unparented textures may be unloaded after PreloadAsync; IsLoaded is recorded only.
  assert(fetch[uri]=="Success","Static image unavailable: "..uri.." "..tostring(fetch[uri]))
 end
 assert(#imageFetchRows==10,"Expected ten successful image fetch callbacks")
end)
local unexpectedProbeParent=false
for _,probe in ipairs(imageProbes) do
 if probe.Parent==nil then probe:Destroy() else unexpectedProbeParent=true end
end
assert(not unexpectedProbeParent,"Refused to destroy a probe that was unexpectedly parented")
assert(imagePreflightOk,"Detached image preflight failed: "..tostring(imagePreflightError))
local imageFetchProof={method="ContentProvider.PreloadAsync(detached ImageLabel instances)",
 imageCount=#imageFetchRows,successCount=#imageFetchRows,images=imageFetchRows,
 immediateIsLoadedRequired=false,temporaryDetachedProbesDestroyed=true,
 surfaceAppearancePlayRequired=true,
 scope="Image texture fetch proof only; actual SurfaceAppearance rendering still requires Play verification"}
folder:SetAttribute("Ready",true)
verify()
for _,row in ipairs(C.sources) do
 if not row.new then
  local target=ids[row.path];assert(target:GetAttribute("LobbyReimaginedOwned")==true or row.path=="StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController","Target ownership missing")
  SES:UpdateSourceAsync(target,function(current)
   verify();assert(hash(current)==expected[row.path],"Editor CAS changed")
   return row.source
  end)
  assert(target.Source==row.source and SES:GetEditorSource(target)==row.source,"Post-write editor conflict")
  expected[row.path]=row.sha256;target:SetAttribute("InstalledSourceSHA256",row.sha256)
 end
end
verify()
for _,row in ipairs(C.sources) do if row.new then prepared[row.path].Parent=at(row.path:match("^(.*)%.[^.]+$")) end end
local receipt={placeId=game.PlaceId,universeId=game.GameId,backupCaptureId=gate.captureId,assetFetch=fetch,assetImageFetchProof=imageFetchProof,sources={}}
for _,row in ipairs(C.sources) do
 local i=at(row.path);assert(hash(i.Source)==row.sha256 and SES:GetEditorSource(i)==row.source,"Installed source differs")
 table.insert(receipt.sources,{path=row.path,class=i.ClassName,sha256=row.sha256,bytes=#i.Source,editorMatch=true})
end
receipt.installedAt=DateTime.now():ToIsoDate()
assert(H:PostAsync(BASE.."/receipt",H:JSONEncode(receipt),Enum.HttpContentType.ApplicationJson)=="saved")
print("Lobby polish installed: six scoped sources; original lobby and queue authority preserved")
return receipt
