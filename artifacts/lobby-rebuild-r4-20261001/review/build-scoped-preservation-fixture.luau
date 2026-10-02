local fs=require("@lune/fs")
local process=require("@lune/process")
local serde=require("@lune/serde")
local rbx=require("@lune/roblox")
local base=assert(process.args[1])
local scenario=process.args[2] or "allowed"
local scopedSourceCount=tonumber(process.args[3]) or 7
assert(scopedSourceCount==7 or scopedSourceCount==8)
local function sha(raw)return serde.hash("sha256",raw)end
local specs={
 {path="ServerScriptService.LobbyReimaginedPreview.Builder",class="ModuleScript",owned=true},
 {path="ServerScriptService.LobbyReimaginedPreview.RuntimeBake",class="ModuleScript",owned=true},
 {path="ServerScriptService.LobbyReimaginedPreview.QueueBridge",class="ModuleScript",owned=true},
 {path="ServerScriptService.GameManager",class="Script",owned=false},
 {path="ServerScriptService.Level4V4PreviewAccess",class="Script",owned=false},
 {path="ServerScriptService.Level5PreviewAccess",class="Script",owned=false},
 {path="ServerScriptService.Level6PreviewAccess",class="Script",owned=false},
}
if scopedSourceCount==8 then
 table.insert(specs,{path="StarterPlayer.StarterPlayerScripts.RoundUI",class="LocalScript",owned=false})
end
local function make()
 local game=rbx.Instance.new("DataModel")
 for _,class in {"ServerScriptService","ServerStorage","StarterPlayer"}do game:GetService(class)end
 return game
end
local function resolve(game,path,create,class)
 local cursor=game
 local pieces=string.split(path,".")
 for i,name in pieces do
  local next=cursor:FindFirstChild(name)
  if not next and create then next=rbx.Instance.new(if i==#pieces then class else "Folder");next.Name=name;next.Parent=cursor end
  cursor=assert(next)
 end
 return cursor
end
local function snapshot(game,path)
 local roots,mapping,services,sources={},{},{},{}
 for _,class in {"ServerScriptService","ServerStorage","StarterPlayer"}do
  local service=game:GetService(class)
  table.insert(services,{class=class,name=class,properties={},attributes={},propertyErrors={},tags={}})
  for _,root in service:GetChildren()do
   table.insert(roots,root)
   table.insert(mapping,{index=#roots,service=class,name=root.Name,class=root.ClassName,path=root:GetFullName(),descendants=#root:GetDescendants()})
  end
 end
 for _,instance in game:GetDescendants()do
  if instance:IsA("LuaSourceContainer")then
   table.insert(sources,{path=instance:GetFullName(),class=instance.ClassName,source=instance.Source,editorMatch=true,
    sourceSha256=sha(instance.Source),editorSourceSha256=sha(instance.Source)})
  end
 end
 local bytes=rbx.serializeModel(roots)
 local metadata={captureId="fixture-"..path,placeId=131311258779917,universeId=10559217407,groupId=1039373905,
  nativeSHA256=sha(bytes),nativeBytes=#bytes,rootCount=#roots,roots=mapping,services=services,scriptCount=#sources,
  editorConflicts={},skipped={},collisionGroups={},collisionMatrix={},materialOverrides={}}
 if scenario=="service-change" and path=="after"then metadata.materialOverrides.Concrete="UnauthorizedFixtureOverride"end
 fs.writeDir(base.."/"..path)
 fs.writeFile(base.."/"..path.."/all-service-children.rbxm",bytes)
 fs.writeFile(base.."/"..path.."/metadata.json",serde.encode("json",metadata,true))
 fs.writeFile(base.."/"..path.."/scripts.json",serde.encode("json",sources,true))
 return bytes,roots
end
local before=make()
for i,spec in specs do
 local instance=resolve(before,spec.path,true,spec.class)
 instance.Source="return 'before-"..i.."'"
 if spec.owned then instance:SetAttribute("InstalledSourceSHA256","recorded-old-fixture-hash")end
 spec.expectedSourceSHA256=sha(instance.Source)
 spec.afterSHA256=sha("return 'after-"..i.."'")
end
local preserved=resolve(before,"ServerScriptService.LobbyReimaginedPreview.Bootstrap",true,"Script")
preserved.Source="return 'unchanged-bootstrap'"
local asset=rbx.Instance.new("Part");asset.Name="PreservedAsset";asset.Color=rbx.Color3.new(0.25,0.3,0.4);asset.Parent=before:GetService("ServerStorage")
local bytes=snapshot(before,"before")
local after=make()
for index,root in rbx.deserializeModel(bytes)do
 local service="ServerScriptService"
 -- Identify the only non-script storage root rather than assume GetChildren order.
 if root.Name=="PreservedAsset"then service="ServerStorage"end
 if root.Name=="StarterPlayerScripts"then service="StarterPlayer"end
 root.Parent=after:GetService(service)
end
for i,spec in specs do
 local instance=resolve(after,spec.path)
 instance.Source="return 'after-"..i.."'"
 if spec.owned then instance:SetAttribute("InstalledSourceSHA256",sha(instance.Source))end
end
local extra=rbx.Instance.new("Folder");extra.Name="LobbyReimaginedBlenderSource20261001R4"
extra:SetAttribute("LobbyReimaginedOwned",true);extra:SetAttribute("Ready",true);extra:SetAttribute("ManifestSHA256","fixture-manifest")
extra.Parent=after:GetService("ServerStorage")
if scenario=="geometry-change"then after:GetService("ServerStorage").PreservedAsset.Color=rbx.Color3.new(0.8,0.1,0.2)end
if scenario=="unrelated-source"then resolve(after,"ServerScriptService.LobbyReimaginedPreview.Bootstrap").Source="return 'unauthorized'"end
if scenario=="source-pin"then specs[1].afterSHA256=sha("wrong source")end
if scenario=="unrelated-attribute"then resolve(after,"ServerScriptService.GameManager"):SetAttribute("NewUnauthorizedAttribute",true)end
snapshot(after,"after")
local catalog={sources=specs,payload={sourceName=extra.Name,manifestSHA256="fixture-manifest",additiveOnly=true}}
fs.writeFile(base.."/catalog.json",serde.encode("json",catalog,true))
print(serde.encode("json",{scenario=scenario,fixtureDirectory=base}))
