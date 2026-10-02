local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local base="tools/lobby_reimagined/polish_20261002/bays/inspection/"
local catalogPath="/private/tmp/lobby-polish-frozen-receivers-20261002/catalog.json"
local catalogBytes=fs.readFile(catalogPath)
assert(serde.hash("sha256",catalogBytes)=="a7b74111671b2baaa3dba2e8ac4602e1d5f9c9d6569436d4381cc90426c6f7d1")
local catalog=serde.decode("json",catalogBytes)
local rawPath="artifacts/lobby-rebuild-r4-20261001/textures-laver-20261002/manifest-laver-resolved-images.json"
local manifestBytes=fs.readFile(rawPath)
assert(serde.hash("sha256",manifestBytes)=="17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995")
local manifest=serde.decode("json",manifestBytes)
local finalPinsBytes=fs.readFile("artifacts/lobby-polish-20261002/root/final-frozen-source-hashes.json")
local sources=serde.decode("json",finalPinsBytes)
for _,row in ipairs(sources) do assert(serde.hash("sha256",fs.readFile(row.file))==row.sha256,"Final source pin differs: "..row.path) end
local originalClutterSource,clutterSource
for _,row in ipairs(catalog.sources) do if row.path=="ServerScriptService.LobbyReimaginedPreview.EndBlockades" then originalClutterSource=row.source end end
for _,row in ipairs(sources) do if row.path=="ServerScriptService.LobbyReimaginedPreview.EndBlockades" then clutterSource=fs.readFile(row.file) end end
assert(originalClutterSource and clutterSource)
local originalClutter=luau.load((originalClutterSource:gsub("return Module%s*$","return PLAN")))()
local clutter=luau.load((clutterSource:gsub("return Module%s*$","return PLAN")))()
assert(serde.encode("json",clutter.colliders)==serde.encode("json",originalClutter.colliders),"Final backing change modified collider expectations")
assert(#clutter.colliders==66 and #clutter.placements==219)
local pbrCounts={};local djConsoleSHA256
for _,p in ipairs(manifest.placements) do
 for _,c in ipairs(manifest.chunks) do
  if c.family==p.family and manifest.materials[c.materialKey] then pbrCounts[c.materialKey]=(pbrCounts[c.materialKey] or 0)+1 end
 end
end
for _,c in ipairs(manifest.chunks) do if c.family=="DJConsole" then assert(not djConsoleSHA256);djConsoleSHA256=c.sha256 end end
assert(pbrCounts.tunnel_concrete==15 and pbrCounts.asphalt_road==7 and pbrCounts.sidewalk_concrete==26)
local bays,pads,signs={},{},{}
local function subset(row,keys)local out={};for _,key in ipairs(keys)do out[key]=row[key]end;return out end
for _,row in ipairs(manifest.bays)do table.insert(bays,subset(row,{"level","floorPosition","yaw"}))end
for _,row in ipairs(manifest.pads)do table.insert(pads,subset(row,{"level","position"}))end
for _,row in ipairs(manifest.signs)do table.insert(signs,subset(row,{"level","gatePosition","yaw","headerLocalPosition","headerLocalSize","bladeLocalPosition","bladeLocalSize"}))end
local expected={catalogSHA256=serde.hash("sha256",catalogBytes),finalSourcePinsSHA256=serde.hash("sha256",finalPinsBytes),rawManifestSHA256=serde.hash("sha256",manifestBytes),
 placeId=catalog.placeId,universeId=catalog.universeId,assets=catalog.assets,sources=sources,bays=bays,
 pads=pads,signs=signs,pbrCounts=pbrCounts,clutterColliders=clutter.colliders,djConsoleSHA256=djConsoleSHA256,
 themes={"OFFICE BACKROOMS · START HERE","POOLROOMS","MALL BACKROOMS","90s CINEMA · DEV ONLY","QUIET SUBURBS","MALL PARTY"}}
fs.writeFile(base.."expected.json",serde.encode("json",expected,true))
local common=fs.readFile(base.."common.template.luau")
local files={}
for _,context in ipairs({"server","client"}) do
 local scopedExpected=serde.decode("json",serde.encode("json",expected))
 if context=="client" then scopedExpected.clutterColliders=nil end
 local replacement="[====["..serde.encode("json",scopedExpected).."]====]"
 local renderedCommon=common:gsub("__EXPECTED_JSON__",function()return replacement end,1)
 local content=string.format('assert(game:GetService("RunService"):Is%s(),"Expected %s Play context")\n',context=="server" and "Server" or "Client",context)
  ..renderedCommon.."\n"..fs.readFile(base..context..".suffix.luau")
 luau.compile(content)
 for _,forbidden in ipairs({"Instance.new(",":SetAttribute(",":Destroy(",":FireServer(",":InvokeServer(","require("}) do
  assert(not content:find(forbidden,1,true),"Inspector mutation/runtime-module invocation found: "..forbidden)
 end
 local path=base..context..".PlayInspect.luau";fs.writeFile(path,content)
 local tmp="/private/tmp/lobby-polish-"..context.."-inspect.luau";fs.writeFile(tmp,content)
 table.insert(files,{path=path,tmpPath=tmp,bytes=#content,sha256=serde.hash("sha256",content),compiled=true})
end
local receipt={schema="lobby-readonly-play-inspectors-offline-preparation-v1",status="PASS",files=files,
 catalogSHA256=expected.catalogSHA256,rawManifestSHA256=expected.rawManifestSHA256,expectedPBRCounts=pbrCounts,
 finalSourcePinsSHA256=expected.finalSourcePinsSHA256,finalClutterCollidersExactlyEqualFirstInstall=true,clutterPoseChecksIncluded=false,
 expectedQueues=24,expectedBays=6,originalColliderCount=830,extraEndBlockerCount=66,sceneLightTotal=87,sceneEnabledLights=77,
 propertyWritesToLiveInstances=false,StudioExecuted=false,PlayPassClaimed=false,
 scope="Compilation and exact frozen evidence preparation only; root must execute inspectors and preserve returned actual observations"}
fs.writeFile("artifacts/lobby-polish-20261002/bays/inspection/preparation-receipt.json",serde.encode("json",receipt,true))
print(serde.encode("json",receipt))
