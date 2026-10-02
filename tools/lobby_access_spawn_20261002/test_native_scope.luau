local rbx=require("@lune/roblox")
local fs=require("@lune/fs")
local serde=require("@lune/serde")
local base="/private/tmp/lobby-access-spawn-scope-fixtures-20261002"
fs.writeDir(base)
local paths={
 {"ServerScriptService.GameManager","Script"},
 {"ServerScriptService.LobbyReimaginedPreview.Bootstrap","Script"},
 {"ServerScriptService.LobbyReimaginedPreview.Builder","ModuleScript"},
 {"ServerScriptService.LobbyReimaginedPreview.DevBayAccessGuard","ModuleScript"},
 {"ServerScriptService.Level5PreviewAccess","Script"},
 {"ServerScriptService.Level6PreviewAccess","Script"},
 {"StarterPlayer.StarterPlayerScripts.R4DevGateController","LocalScript"},
 {"StarterPlayer.StarterPlayerScripts.Level6PreviewTransport","LocalScript"},
 {"StarterPlayer.StarterPlayerScripts.Friend Boost Client","LocalScript"},
}
local function sha(s)return serde.hash("sha256",s) end
local function save(p,t)fs.writeFile(p,serde.encode("json",t,true)) end
local function make(directory,isAfter,failure)
 fs.writeDir(directory)
 local game=rbx.Instance.new("DataModel")
 local function insert(path,class)
  local components=string.split(path,".");local cursor=game:GetService(components[1])
  for i=2,#components do
   local next=cursor:FindFirstChild(components[i])
   if not next then next=rbx.Instance.new(if i==#components then class else "Folder");next.Name=components[i];next.Parent=cursor end
   cursor=next
  end
  return cursor
 end
 local scripts={}
 for _,row in paths do
  local new=row[1]:find("DevBayAccessGuard",1,true)~=nil
  if new and not isAfter then continue end
  local script=insert(row[1],row[2]);script.Source=if isAfter then "-- changed\nreturn 2\n" else "-- baseline\nreturn 1\n"
  table.insert(scripts,{path=row[1],class=row[2],source=script.Source,sourceBytes=#script.Source,sourceSha256=sha(script.Source),editorSourceSha256=sha(script.Source),editorMatch=true})
 end
 local spawn=insert("Workspace.ServerLobby.LobbySpawn","SpawnLocation")
 spawn.CFrame=rbx.CFrame.new(if failure=="spawn" then 1 else 0,30.4,-860)
 local extra=insert("Workspace.ServerLobby.UnrelatedLamp","Part")
 extra.Color=if failure=="geometry" then rbx.Color3.fromRGB(255,0,0) else rbx.Color3.fromRGB(12,15,17)
 local roots,mapping={},{}
 for _,class in {"ServerScriptService","StarterPlayer","Workspace"} do
  for _,instance in game:GetService(class):GetChildren() do
   table.insert(roots,instance);table.insert(mapping,{index=#roots,service=class,path=class.."."..instance.Name,name=instance.Name,class=instance.ClassName,descendants=#instance:GetDescendants()})
  end
 end
 local raw=rbx.serializeModel(roots)
 fs.writeFile(directory.."/all-service-children.rbxm",raw)
 save(directory.."/scripts.json",scripts)
 save(directory.."/metadata.json",{captureId=if isAfter then "fixture-after" else "fixture-before",placeId=131311258779917,universeId=10559217407,groupId=1039373905,editorConflicts={},skipped={},nativeSHA256=sha(raw),roots=mapping,services={{class="Workspace",properties={Gravity={type="number",value=if failure=="service" then 10 else 196.2}}}},collisionGroups={},collisionMatrix={},materialOverrides={}})
end
make(base.."/before",false,nil)
for _,failure in {"positive","spawn","geometry","service"} do make(base.."/"..failure,true,failure) end
local rows={}
for _,row in paths do
 local new=row[1]:find("DevBayAccessGuard",1,true)~=nil
 local before="-- baseline\nreturn 1\n";local after="-- changed\nreturn 2\n"
 table.insert(rows,{path=row[1],className=row[2],new=new,baselineSHA256=if new then nil else sha(before),baselineBytes=if new then nil else #before,candidateSHA256=sha(after),candidateBytes=#after})
end
save(base.."/manifest.json",{nativeBeforeCaptureId="fixture-before",canonicalSpawnPath="Workspace.ServerLobby.LobbySpawn",spawnPosition={220,30.4,-860},spawnLookAt={220,30.4,-760},rows=rows})
print("Generated closed native scope fixtures")
