-- Meaningful local fixtures: exact scope passes; unrelated/source/asset/reference
-- mutations fail and remain reported. Never uses a real capture as a fixture.
local fs,serde,rbx=require("@lune/fs"),require("@lune/serde"),require("@lune/roblox")
local audit=require("./native_audit")
local BASE="/private/tmp/lobby-polish-native-scope-selftest-20261002"
local ASSET="artifacts/lobby-polish-20261002/materials/candidate-manifest.json"
local UPLOAD="artifacts/lobby-polish-20261002/materials/uploaded-assets.json"
fs.writeDir(BASE)
local function sha(raw)return serde.hash("sha256",raw)end
local function json(path,value)fs.writeFile(path,serde.encode("json",value,true))end
local asset=serde.decode("json",fs.readFile(ASSET));local upload=serde.decode("json",fs.readFile(UPLOAD));local uploaded={}
for url,id in upload do uploaded[url:match("([^/]+)$")]=id end
local paths={
 {path="ServerScriptService.LobbyReimaginedPreview.Builder",className="ModuleScript",new=false},
 {path="ServerScriptService.LobbyReimaginedPreview.EndBlockades",className="ModuleScript",new=false},
 {path="StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController",className="LocalScript",new=false},
 {path="ServerScriptService.LobbyReimaginedPreview.MaterialPolish",className="ModuleScript",new=true},
 {path="ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays",className="ModuleScript",new=true},
 {path="ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene",className="ModuleScript",new=true},
}
local function make(after)
 local game=rbx.Instance.new("DataModel");local roots,services={},{}
 for _,class in {"Workspace","ServerScriptService","StarterPlayer"}do local s=game:GetService(class);services[class]=s end
 local lobby=rbx.Instance.new("Model");lobby.Name="ServerLobby";lobby.Parent=services.Workspace;table.insert(roots,lobby)
 local part=rbx.Instance.new("Part");part.Name="OriginalWall";part.Size=rbx.Vector3.new(5,6,7);part.Parent=lobby
 local ref=rbx.Instance.new("ObjectValue");ref.Name="OriginalReference";ref.Parent=lobby
 local folder=rbx.Instance.new("Folder");folder.Name="LobbyReimaginedPreview";folder.Parent=services.ServerScriptService;table.insert(roots,folder)
 local starters=rbx.Instance.new("StarterPlayerScripts");starters.Parent=services.StarterPlayer;table.insert(roots,starters)
 local nodes={}
 for index,spec in paths do if after or not spec.new then
  local node=rbx.Instance.new(spec.className);node.Name=spec.path:match("([^%.]+)$")
  node.Source="--fixture "..index..(after and " after"or " before").."\nreturn {}\n"
  node:SetAttribute("LobbyReimaginedOwned",true);node:SetAttribute("InstalledSourceSHA256",sha(node.Source))
  node.Parent=spec.className=="LocalScript"and starters or folder;nodes[spec.path]=node
 end end
 if after then
  local module=nodes[paths[4].path];local f=rbx.Instance.new("Folder");f.Name="StaticPBRMaterials";f:SetAttribute("LobbyReimaginedOwned",true);f:SetAttribute("Ready",true);f.Parent=module
  for key,maps in asset.assetSpec.materials do local sa=rbx.Instance.new("SurfaceAppearance");sa.Name=key;sa:SetAttribute("LobbyReimaginedOwned",true)
   sa.AlphaMode=rbx.Enum.AlphaMode.Overlay;sa.Color=rbx.Color3.new(1,1,1);sa.MetalnessMap=""
   for role,property in {color="ColorMap",normal="NormalMap",roughness="RoughnessMap"}do sa[property]=uploaded[key.."_"..role..".png"];sa:SetAttribute(role.."PNG_SHA256",maps[role].pngSHA256)end
   sa.Parent=f
  end
  local value=rbx.Instance.new("StringValue");value.Name="SidewalkAtlas";value.Value=uploaded["sidewalk_joint_atlas.png"]:match("(%d+)$");value:SetAttribute("LobbyReimaginedOwned",true);value:SetAttribute("PNG_SHA256",asset.assetSpec.sidewalkAtlas.pngSHA256);value.Parent=module
 end
 return {game=game,roots=roots,services=services,nodes=nodes,lobby=lobby,part=part,ref=ref}
end
local function capture(state,dir,id,editorMismatch)
 fs.writeDir(dir);local raw=rbx.serializeModel(state.roots);local rows,roots,services={},{},{}
 for class,s in state.services do table.insert(services,{name=s.Name,class=class,attributes={},tags={},properties={},propertyErrors={}})end
 table.sort(services,function(a,b)return a.class<b.class end)
 for _,root in state.roots do table.insert(roots,{path=root:GetFullName(),name=root.Name,class=root.ClassName,service=root.Parent.ClassName})
  local nodes=root:GetDescendants();table.insert(nodes,root)
  for _,node in nodes do if node:IsA("LuaSourceContainer")then local digest=sha(node.Source)
   table.insert(rows,{path=node:GetFullName(),class=node.ClassName,source=node.Source,sourceBytes=#node.Source,sourceSha256=digest,editorMatch=not editorMismatch,editorSourceSha256=editorMismatch and "conflict"or digest})
  end end
 end
 fs.writeFile(dir.."/all-service-children.rbxm",raw);json(dir.."/scripts.json",rows)
 local meta={nativeSHA256=sha(raw),nativeBytes=#raw,rootCount=#state.roots,roots=roots,services=services,scriptCount=#rows,
  captureId=id,placeId=131311258779917,universeId=10559217407,groupId=1039373905,editorConflicts={},skipped={},collisionGroups={},collisionMatrix={},materialOverrides={}}
 json(dir.."/metadata.json",meta);return meta,rows
end
local before=make(false);local meta,rows=capture(before,BASE.."/before","before")
local critical={};for _,row in rows do table.insert(critical,{path=row.path,class=row.class,sourceSha256=row.sourceSha256,sourceBytes=row.sourceBytes})end
json(BASE.."/critical.json",critical)
local originalAfter=make(true);local frozen={}
for index,spec in paths do local file=BASE.."/candidate-"..index..".luau";local text=originalAfter.nodes[spec.path].Source;fs.writeFile(file,text)
 table.insert(frozen,{path=spec.path,className=spec.className,new=spec.new,file=file,sha256=sha(text)})
end
json(BASE.."/frozen.json",frozen)
local tests={
 {name="exact_scope",mutate=function()end,pass=true},
 {name="original_lobby_geometry",mutate=function(s)s.part.Size=rbx.Vector3.new(8,6,7)end},
 {name="unrelated_source_addition",mutate=function(s)local n=rbx.Instance.new("ModuleScript");n.Name="ConcurrentDeveloperModule";n.Source="return {concurrent=true}";n.Parent=s.roots[2]end},
 {name="material_uri_mismatch",mutate=function(s)s.nodes[paths[4].path].StaticPBRMaterials.tunnel_concrete.ColorMap="rbxassetid://12345"end},
 {name="unexpected_helper_child",mutate=function(s)local n=rbx.Instance.new("Folder");n.Name="UnscopedGeometry";n.Parent=s.nodes[paths[5].path]end},
 {name="source_editor_conflict",mutate=function()end,editorMismatch=true},
 {name="reference_to_new_task_module",mutate=function(s)s.ref.Value=s.nodes[paths[4].path]end},
 {name="unrelated_attribute",mutate=function(s)s.roots[2]:SetAttribute("ConcurrentDeveloperAttribute",17)end},
 {name="new_root",mutate=function(s)local n=rbx.Instance.new("Folder");n.Name="ConcurrentRoot";n.Parent=s.services.Workspace;table.insert(s.roots,n)end},
}
local results={}
for _,case in tests do
 local state=make(true);case.mutate(state);capture(state,BASE.."/"..case.name,"after-"..case.name,case.editorMismatch)
 local report=audit.audit({before=BASE.."/before",after=BASE.."/"..case.name,frozen=BASE.."/frozen.json",critical=BASE.."/critical.json",
  assetManifest=ASSET,uploads=UPLOAD,expectedBeforeNativeSHA256=meta.nativeSHA256,output=BASE.."/"..case.name.."-report.json"})
 assert(report.verified==(case.pass==true),"Unexpected audit result: "..case.name)
 if case.name=="reference_to_new_task_module"then assert(#report.unclassifiedConcurrentNativeDeltas>0,"New-module reference was hidden by normalization")end
 if case.name=="unrelated_source_addition"then assert(#report.unclassifiedConcurrentSourceDeltas==1,"Concurrent Source not reported")end
 table.insert(results,{name=case.name,expectedVerified=case.pass==true,actualVerified=report.verified,taskScopeVerified=report.taskScopeVerified,
  errors=report.errors,concurrentSources=#report.unclassifiedConcurrentSourceDeltas,concurrentNativeRows=#report.unclassifiedConcurrentNativeDeltas})
end
local receipt={schema="lobby-polish-native-audit-selftest-v1",passed=true,tests=results,fixtureDirectory=BASE,realCaptureCompared=false,studioWrites=false,inputBackupWrites=false}
json("artifacts/lobby-polish-20261002/materials/native-audit-selftest.json",receipt)
print(serde.encode("json",receipt,true))
