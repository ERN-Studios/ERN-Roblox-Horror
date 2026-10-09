"""Explicit normal Level 1 regression for the shared loader; immutable receipts.

Each invocation runs one phase only. No Source, map Parent, readiness, Play
lifecycle or access-flag writes. Normal queue and exit paths remain authoritative.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
sys.path.insert(0, str(ROOT / 'tools'))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME

STUDIO_ID = '1b603e69-7ae1-4572-b210-d5bf05c684ff'
COMMON = '''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local Players=game:GetService("Players") local RunService=game:GetService("RunService")
assert(RunService:IsRunning() and RunService:IsStudio(),"Requires Studio Play")
local Http=game:GetService("HttpService")
local function parked()
 local rows={}
 for _,name in {"Level 4 Cinema Blender","Level 5 Void","Level 6 Indoor Playground"} do
  assert(not workspace:FindFirstChild(name),"Unneeded world active: "..name)
  local row={name=name,inWorkspace=false}
  if not Players.LocalPlayer then
   local model=assert(game.ServerStorage:FindFirstChild(name),"Authored world absent: "..name)
   assert(model:IsA("Model"),"Wrong authored world class")
   row.path=model:GetFullName() row.descendants=#model:GetDescendants()
  end
  table.insert(rows,row)
 end
 return rows
end
'''
PHASES = {
 'queue': ('Server', '''local list=Players:GetPlayers() assert(#list==1,"Single client QA")
local p=list[1] local character=assert(p.Character,"Missing lobby character")
assert(p:GetAttribute("InRound")~=true,"Already in a round")
local root=assert(character:FindFirstChild("HumanoidRootPart"))
assert(character:FindFirstChildOfClass("Humanoid").Health>0,"Dead lobby character")
assert(not _G.__LazyLevel1Borrow,"Previous queue trial not cleaned")
_G.__LazyLevel1Borrow={player=p,character=character,pivot=character:GetPivot(),root=root,
 linear=root.AssemblyLinearVelocity,angular=root.AssemblyAngularVelocity}
local zone=workspace.ServerLobby.LevelQueueRooms.Level1QueueRoom.LaunchZone1
character:PivotTo(zone.CFrame*CFrame.new(0,3,0))
return Http:JSONEncode({normalQueueZone=zone:GetFullName(),maps=parked(),sourceWrites=0})
'''),
 'configure': ('Client', '''local p=assert(Players.LocalPlayer) local deadline=os.clock()+8
while p:GetAttribute("QueueModalOpen")~=true and os.clock()<deadline do task.wait(.1) end
assert(p:GetAttribute("QueueModalOpen")==true,"Normal queue modal did not open")
game.ReplicatedStorage.Remotes.ConfigureQueue:FireServer(1,1,"public")
return Http:JSONEncode({normalQueueConfigured=true,level=1,maps=parked(),sourceWrites=0})
'''),
 'entry-client': ('Client', '''local p=assert(Players.LocalPlayer) local deadline=os.clock()+45
local function released()
 local c=p.Character local root=c and c:FindFirstChild("HumanoidRootPart")
 local hum=c and c:FindFirstChildOfClass("Humanoid")
 return p:GetAttribute("InRound")==true and workspace:GetAttribute("RoundLoadingState")=="ready"
  and workspace:GetAttribute("RoundActive")==true and root and not root.Anchored and hum and hum.Health>0
end
while not released() and os.clock()<deadline do task.wait(.1) end
assert(released(),"Normal Level 1 loading did not release a healthy character")
assert(workspace:GetAttribute("SelectedLevel")==1,"Wrong level")
local root=p.Character.HumanoidRootPart
local maze=assert(workspace:FindFirstChild("Maze"))
local rooms=assert(maze:FindFirstChild("BlenderRooms"))
local atomic,roofs=0,0
for index,room in rooms:GetChildren() do
 if index%1000==0 then task.wait() end
 if room:IsA("Model") then
 assert(room.ModelStreamingMode==Enum.ModelStreamingMode.Atomic,"Room not atomic") atomic+=1
end end
for index,part in rooms:GetDescendants() do
 if index%1000==0 then task.wait() end
 if part:IsA("MeshPart") and part.Transparency<1 and part:GetAttribute("RoomRole")=="SurfaceCeiling"
  and (part.Position-root.Position).Magnitude<80 then roofs+=1 end
end
assert(atomic>0 and roofs>0,"Nearby ceiling or room geometry missing")
local params=RaycastParams.new() params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={p.Character} params.RespectCanCollide=true
local floor=assert(workspace:Raycast(root.Position,Vector3.new(0,-16,0),params),"Missing client floor")
return Http:JSONEncode({level=1,healthy=true,released=true,atomicRooms=atomic,nearbyVisibleRoofMeshes=roofs,
 floor=floor.Instance:GetFullName(),maps=parked(),sourceWrites=0})
'''),
 'entry-server': ('Server', '''assert(Players.LocalPlayer==nil,"Server only")
assert(workspace:GetAttribute("RoundActive")==true and workspace:GetAttribute("SelectedLevel")==1,"Level 1 inactive")
assert(workspace:GetAttribute("RoundLoadingState")=="ready","Loader not ready")
return Http:JSONEncode({level=1,active=true,loadingState="ready",maps=parked(),sourceWrites=0})
'''),
 'leave': ('Client', '''local p=assert(Players.LocalPlayer)
assert(p:GetAttribute("InRound")==true,"Requires active Level 1")
game.ReplicatedStorage.Remotes.RoundStatus:FireServer("leaveround")
local deadline=os.clock()+20
while p:GetAttribute("InRound")==true and os.clock()<deadline do task.wait(.1) end
assert(p:GetAttribute("InRound")~=true,"Normal exit did not return to lobby")
return Http:JSONEncode({normalExit=true,maps=parked(),sourceWrites=0})
'''),
 'cleanup': ('Server', '''assert(Players.LocalPlayer==nil,"Server only")
local borrowed=_G.__LazyLevel1Borrow local restored=false
if borrowed then
 assert(borrowed.player:GetAttribute("InRound")~=true,"Leave the normal round before cleanup")
 if borrowed.player.Character==borrowed.character and borrowed.character.Parent and borrowed.root.Parent
  and borrowed.character:FindFirstChildOfClass("Humanoid").Health>0 then
  borrowed.character:PivotTo(borrowed.pivot)
  borrowed.root.AssemblyLinearVelocity=borrowed.linear borrowed.root.AssemblyAngularVelocity=borrowed.angular
  restored=(borrowed.character:GetPivot().Position-borrowed.pivot.Position).Magnitude<.1
 end
 _G.__LazyLevel1Borrow=nil
end
return Http:JSONEncode({borrowCleared=_G.__LazyLevel1Borrow==nil,borrowedCharacterRestored=restored,maps=parked(),sourceWrites=0})
'''),
}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=PHASES)
    parser.add_argument('label')
    parser.add_argument('--code-only', action='store_true')
    args=parser.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_.-]{1,70}',args.label)
    model,body=PHASES[args.phase]
    code=COMMON+body
    if args.code_only:
        print(code)
        return
    output=HERE/('runtime-level1-'+args.label+'.json')
    code_path=ROOT/'.git/lazy-levels-20261009'/('runtime-level1-'+args.label+'.luau')
    assert not output.exists() and not code_path.exists(),'Do not overwrite evidence'
    code_path.parent.mkdir(parents=True,exist_ok=True)
    with code_path.open('x',encoding='utf-8',newline='\n') as f: f.write(code)
    receipt={'task':'lazy-levels-20261009','phase':args.phase,'datamodel':model,'passed':False,
             'codeSHA256':hashlib.sha256(code.encode()).hexdigest()}
    client=None
    try:
        client=StudioMcpClient(find_mcp_batch()); client.initialize()
        studio=select_studio(client,RELEASE_STUDIO_NAME,20)
        assert studio['id']==STUDIO_ID,'Authoritative session changed'
        receipt['result']=json.loads(client.call('execute_luau',{'studio_id':STUDIO_ID,'datamodel_type':model,'code':code}))
        receipt['passed']=True
    except Exception as error:
        receipt['error']=str(error)
        raise
    finally:
        if client: client.close()
        receipt['capturedAtUtc']=datetime.now(timezone.utc).isoformat()
        receipt['limits']='One normal Studio client, warm asset cache; no mobile, multiplayer or cold-cache performance claim'
        with output.open('x',encoding='utf-8',newline='\n') as f: json.dump(receipt,f,indent=2); f.write('\n')
    print(json.dumps(receipt))

if __name__=='__main__': main()
