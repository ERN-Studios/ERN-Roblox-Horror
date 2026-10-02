local rbx=require("@lune/roblox")
local fs=require("@lune/fs")
local serde=require("@lune/serde")
local dir="/private/tmp/r4-static-native-fixture"
if not fs.isDir(dir) then fs.writeDir(dir) end
local catalog=serde.decode("json",fs.readFile("tools/lobby_reimagined/r4_candidates/install-catalog-r4-final.json"))
local source=rbx.Instance.new("Folder");source.Name=catalog.payload.sourceName
source:SetAttribute("LobbyReimaginedOwned",true);source:SetAttribute("Ready",true);source:SetAttribute("ManifestSHA256",catalog.payload.manifestSHA256)
local folder=rbx.Instance.new("Folder");folder.Name="StaticPBRMaterials";folder:SetAttribute("LobbyReimaginedOwned",true);folder.Parent=source
for _,spec in catalog.payload.StaticPBRMaterials.templates do
 local sa=rbx.Instance.new("SurfaceAppearance");sa.Name=spec.name;sa:SetAttribute("LobbyReimaginedOwned",true);sa.Parent=folder
 sa.Color=rbx.Color3.new(1,1,1);sa.AlphaMode=rbx.Enum.AlphaMode.Overlay
 for _,role in {"color","normal","roughness"}do
  local prop=role:sub(1,1):upper()..role:sub(2).."Map";sa[prop]="rbxassetid://"..spec.assetIds[role]
 end
 sa.MetalnessMap=""
end
local raw=rbx.serializeModel({source});local sha=serde.hash("sha256",raw)
local metadata={placeId=131311258779917,universeId=10559217407,groupId=1039373905,captureId="fixture",nativeSHA256=sha,nativeBytes=#raw,rootCount=1,roots={{service="ServerStorage",name=source.Name,class="Folder"}}}
fs.writeFile(dir.."/metadata.json",serde.encode("json",metadata,true));fs.writeFile(dir.."/all-service-children.rbxm",raw)
fs.writeFile(dir.."/checkpoint-install-gate.json",serde.encode("json",{verified=true,captureId="fixture",nativeSHA256=sha},true))
print("Local SurfaceAppearance URI reflection and serialization fixture prepared")
