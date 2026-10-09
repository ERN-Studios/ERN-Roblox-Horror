"""Bounded normal Studio lobby/Level 1 checks; no authoritative Edit writes."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME

COMMON = '''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
local Players=game:GetService("Players")
local RS=game:GetService("RunService")
assert(RS:IsRunning(),"requires Play")
local function counts(root)
 local out={total=0,parts=0,meshes=0,appearances=0,lights=0}
 if root then for _,v in root:GetDescendants() do
  out.total+=1
  if v:IsA("BasePart") then out.parts+=1 end
  if v:IsA("MeshPart") then out.meshes+=1 end
  if v:IsA("SurfaceAppearance") then out.appearances+=1 end
  if v:IsA("Light") then out.lights+=1 end
 end end
 return out
end
local function worlds()
 local out={}
 for _,name in {"ServerLobby","Level 4 Cinema Blender","Level 5 Void","Level 6 Indoor Playground","Maze"} do
  local model=workspace:FindFirstChild(name)
  out[name]=counts(model)
  if model and model:IsA("Model") then out[name].streaming=tostring(model.ModelStreamingMode) end
 end
 local cinema=workspace:FindFirstChild("Level 4 Cinema Blender")
 out.Level4Collision=counts(cinema and cinema:FindFirstChild("Collision"))
 return out
end
local Http=game:GetService("HttpService")
'''

CLIENT_SAMPLE = '''local frames={} local elapsed=0
while elapsed<5 do local dt=RS.RenderStepped:Wait() elapsed+=dt table.insert(frames,dt*1000) end
table.sort(frames) local sum=0 local over50=0 for _,v in frames do sum+=v if v>50 then over50+=1 end end
local Stats=game:GetService("Stats")
return Http:JSONEncode({worlds=worlds(),playerAttributes=p:GetAttributes(),position=tostring(p.Character:GetPivot().Position),
 frameSample={seconds=elapsed,frames=#frames,meanMs=sum/#frames,p95Ms=frames[math.ceil(#frames*.95)],maxMs=frames[#frames],over50ms=over50},
 studioProcessMemoryMB=Stats:GetTotalMemoryUsageMb(),
 limits="Single Studio client, warm local cache, combined Studio process memory; not published/mobile/multiplayer performance."})
'''

PHASES = {
 "opaque-mesh": ("Client", '''local CP=game:GetService("ContentProvider") local rows={}
for _,name in {"StageDeck","HologramBand01","R4WallMonitor","Office Terminal"} do
 local part for _,v in workspace:GetDescendants() do if v.Name==name and v:IsA("MeshPart") then part=v break end end
 if part then
  local row={name=part:GetFullName(),props={},callbacks={}}
  for _,prop in {"MeshContent","TextureContent","MeshId","TextureID"} do
   local ok,val=pcall(function() return part[prop] end) local info={ok=ok,value=tostring(val),type=typeof(val)}
   if ok and typeof(val)=="Content" then info.source=tostring(val.SourceType) local uriok,uri=pcall(function() return val.Uri end) info.uriOk=uriok info.uri=tostring(uri) end
   row.props[prop]=info
  end
  local ok,err=pcall(function() CP:PreloadAsync({part},function(id,status)table.insert(row.callbacks,{id=tostring(id),status=tostring(status)})end)end)
  row.preloadOk=ok row.error=tostring(err) table.insert(rows,row)
 end
end
return Http:JSONEncode({observations=rows,limits="Native preload callback behavior only; no renderer or published-client guarantee."})
'''),
 "lobby": ("Client", '''local p=Players.LocalPlayer
local deadline=os.clock()+45
while p:GetAttribute("LobbyLoadingDone")~=true and os.clock()<deadline do task.wait(.1) end
assert(p:GetAttribute("LobbyLoadingDone")==true,"lobby loader did not finish")
assert(p:GetAttribute("InRound")~=true,"not in lobby")
''' + CLIENT_SAMPLE),
 "queue": ("Server", '''local list=Players:GetPlayers() assert(#list==1,"single-client probe")
local p=list[1] local zone=workspace.ServerLobby.LevelQueueRooms.Level1QueueRoom.LaunchZone1
assert(p.Character and p:GetAttribute("InRound")~=true,"requires lobby character")
p.Character:PivotTo(zone.CFrame*CFrame.new(0,3,0))
return Http:JSONEncode({normalQueueZone=zone:GetFullName(),position=tostring(p.Character:GetPivot().Position)})
'''),
 "configure": ("Client", '''local p=Players.LocalPlayer local deadline=os.clock()+8
while p:GetAttribute("QueueModalOpen")~=true and os.clock()<deadline do task.wait(.1) end
assert(p:GetAttribute("QueueModalOpen")==true,"normal queue modal did not open")
game.ReplicatedStorage.Remotes.ConfigureQueue:FireServer(1,1,"public")
return Http:JSONEncode({normalQueueConfigured=true,level=1,partySize=1})
'''),
 "level1-client": ("Client", '''local p=Players.LocalPlayer local deadline=os.clock()+45
while not (p:GetAttribute("InRound")==true and workspace:GetAttribute("RoundLoadingState")=="ready") and os.clock()<deadline do task.wait(.1) end
assert(p:GetAttribute("InRound")==true,"normal Level 1 entry did not release")
assert(workspace:GetAttribute("SelectedLevel")==1,"wrong level")
assert(workspace:GetAttribute("RoundLoadingState")=="ready","server did not commit entry acknowledgement")
assert(p.Character and not p.Character.HumanoidRootPart.Anchored,"entry did not release character")
task.wait(1)
local maze=assert(workspace:FindFirstChild("Maze"),"missing Maze")
local rooms=assert(maze:FindFirstChild("BlenderRooms"),"missing room art")
local roofCount,atomicCount=0,0
for _,room in rooms:GetChildren() do
 if room:IsA("Model") then assert(room.ModelStreamingMode==Enum.ModelStreamingMode.Atomic,"room not atomic") atomicCount+=1 end
end
for _,v in rooms:GetDescendants() do
 if v:IsA("MeshPart") and v.Transparency<1 and v:GetAttribute("RoomRole")=="SurfaceCeiling" and (v.Position-p.Character:GetPivot().Position).Magnitude<80 then roofCount+=1 end
end
assert(atomicCount>0 and roofCount>0,"missing nearby roof or room")
print("[StutterAssetsQA] normal Level 1 released; atomic rooms="..atomicCount.." nearby visible roof meshes="..roofCount)
''' + CLIENT_SAMPLE.replace("worlds=worlds(),", "worlds=worlds(),atomicRooms=atomicCount,nearbyVisibleRoofMeshes=roofCount,")),
 "level1-server": ("Server", '''local deadline=os.clock()+25
while workspace:GetAttribute("RoundActive")~=true and os.clock()<deadline do task.wait(.1) end
assert(workspace:GetAttribute("RoundActive")==true and workspace:GetAttribute("SelectedLevel")==1,"requires active Level 1")
local Stats=game:GetService("Stats") local samples={}
for i=1,10 do
 table.insert(samples,{heartbeatMs=Stats.HeartbeatTimeMs,physicsMs=Stats.PhysicsStepTimeMs,memoryMB=Stats:GetTotalMemoryUsageMb()}) task.wait(.5)
end
return Http:JSONEncode({worlds=worlds(),samples=samples,active=workspace:GetAttribute("RoundActive"),level=workspace:GetAttribute("SelectedLevel"),loadingState=workspace:GetAttribute("RoundLoadingState"),
 limits="Normal active Studio round; Studio process memory includes editor/server/client; not multiplayer load."})
'''),
}

phase = sys.argv[1]
model, code = PHASES[phase]
client = StudioMcpClient(find_mcp_batch())
try:
 client.initialize()
 studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
 result = json.loads(client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": model, "code": COMMON + code}))
finally:
 client.close()
result["capturedAtUtc"] = datetime.now(timezone.utc).isoformat()
result["phase"] = phase
out = ROOT / "artifacts/stutter-assets-20261009" / ("runtime-" + phase + ".json")
out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result))
