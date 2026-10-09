"""Explicit bounded Level 4 Studio QA phases; importing/generating code invokes nothing native.

Root owns Play lifecycle. Queue/touch/leave use ordinary player/controller paths and
never change Source, native map Parents, access flags or readiness acknowledgements.
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
from push_repo_to_studio import luau_string

HELPER = HERE / 'level4_native_qa.luau'
STUDIO_ID = '1b603e69-7ae1-4572-b210-d5bf05c684ff'
PHASES = ('sources', 'lobby-server', 'lobby-client', 'position-client', 'configure-client',
          'entry-server', 'entry-client', 'bystander-client', 'door-server', 'door-touch-client',
          'leave-client', 'unmount-server', 'unmount-client', 'cancel-client')
GUARD = '''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local Players=game:GetService("Players") local RunService=game:GetService("RunService")
assert(RunService:IsRunning() and RunService:IsStudio(),"Requires Studio Play")
local HS=game:GetService("HttpService")
'''
CLIENT = '''local player=assert(Players.LocalPlayer,"Requires Client DataModel")
if EXPECTED_PLAYER then assert(player.UserId==EXPECTED_PLAYER,"Wrong selected Client") end
local remotes=game:GetService("ReplicatedStorage"):WaitForChild("Remotes",3)
assert(remotes,"Missing normal round remotes")
'''


def observer(mode):
    source = HELPER.read_text(encoding='utf-8')
    assert source.count('local MODE = "__MODE__"') == 1
    return source.replace('local MODE = "__MODE__"', f'local MODE = "{mode}"')


def snapshot(mode):
    return 'local function snapshot()\n' + observer(mode) + '\nend\nlocal result=HS:JSONDecode(snapshot())\n'


def code_for(phase, station=113, party_size=1, expected_player=None, door=None):
    assert phase in PHASES and station in range(113, 117) and party_size in range(1, 7)
    expected = 'nil' if expected_player is None else str(int(expected_player))
    prefix = GUARD + f'local EXPECTED_PLAYER={expected} local STATION={station}\n'
    if phase == 'sources':
        return observer('sources'), 'Edit'
    if phase.endswith('client'):
        prefix += CLIENT
    else:
        prefix += 'assert(Players.LocalPlayer==nil,"Requires Server DataModel")\n'
    if phase in ('lobby-server', 'lobby-client', 'unmount-client', 'door-server'):
        mode = 'client' if phase.endswith('client') else 'server'
        code = prefix + snapshot(mode)
        if phase != 'door-server':
            code += '''for _,map in result.maps do assert(not map.inWorkspace,"Inactive authored map in Workspace: "..map.name) end
assert(not result.usherVisual,"Inactive Usher visual still replicated")
'''
        return code + 'return HS:JSONEncode(result)', mode.capitalize()
    if phase == 'position-client':
        return prefix + '''assert(player:GetAttribute("InRound")~=true,"Already in a round")
local character=assert(player.Character,"No lobby character")
local root=assert(character:FindFirstChild("HumanoidRootPart"),"No character root")
local hum=assert(character:FindFirstChildOfClass("Humanoid"),"No humanoid") assert(hum.Health>0,"Dead lobby character")
local lobby=assert(workspace:FindFirstChild("LobbyReimaginedPreview"),"Missing revised lobby") local zone
for _,item in lobby:GetDescendants() do if item:IsA("BasePart") and item:GetAttribute("R3QueueId")==STATION then
 assert(not zone and item:GetAttribute("LevelNumber")==4,"Duplicate/wrong Level 4 zone") zone=item
end end
assert(zone,"No normal Level 4 detector")
local borrowed=_G.__LazyLevel4CharacterBorrow
assert(not borrowed or borrowed.Character~=character,"Cancel previous borrowed queue trial first")
_G.__LazyLevel4CharacterBorrow={Character=character,Pivot=character:GetPivot(),Root=root,
 Linear=root.AssemblyLinearVelocity,Angular=root.AssemblyAngularVelocity}
character:PivotTo(zone.CFrame*CFrame.new(0,3,0))
return HS:JSONEncode({phase="position-client",station=STATION,userId=player.UserId,borrowedCharacter=true,
 position={root.Position.X,root.Position.Y,root.Position.Z},normalQueue=true,sourceWrites=0})
''', 'Client'
    if phase == 'configure-client':
        return prefix + f'''assert(player:GetAttribute("InRound")~=true,"Already entered")
local configured=false local status=assert(remotes:FindFirstChild("RoundStatus"))
local connection=status.OnClientEvent:Connect(function(event,a,b,c)
 if event=="queueconfigured" and c==STATION then configured=true end
end)
local ok,problem=xpcall(function()
 local configure=assert(remotes:FindFirstChild("ConfigureQueue"))
 local untilClock=os.clock()+6
 repeat
  configure:FireServer(STATION,{party_size},"public","trial")
  local nextClock=os.clock()+0.5
  repeat task.wait(0.1) until configured or os.clock()>=nextClock
 until configured or os.clock()>=untilClock
 assert(configured,"Normal host configuration was not accepted")
end,debug.traceback)
connection:Disconnect()
assert(ok,problem)
return HS:JSONEncode({{phase="configure-client",station=STATION,partySize={party_size},normalQueue=true,
 configured=true,sourceWrites=0,temporaryConnectionsReleased=true}})
''', 'Client'
    if phase == 'entry-server':
        return prefix + '''local untilClock=os.clock()+25
repeat
 local released=true
 for _,p in Players:GetPlayers() do
  if p:GetAttribute("InRound")==true and p:GetAttribute("Level6PlaygroundPreview")~=true then
   local c=p.Character local r=c and c:FindFirstChild("HumanoidRootPart") local h=c and c:FindFirstChildOfClass("Humanoid")
   if not r or not h or h.Health<=0 or r.Anchored then released=false end
  end
 end
 if workspace:GetAttribute("SelectedLevel")==4 and workspace:GetAttribute("WorldGenerated")==true
  and workspace:GetAttribute("RoundLoadingState")=="ready" and workspace:GetAttribute("RoundActive")==true and released then break end
 task.wait(0.25)
until os.clock()>=untilClock
''' + snapshot('server') + '''assert(result.attributes.SelectedLevel==4 and result.attributes.WorldGenerated==true
 and result.attributes.RoundActive==true and result.attributes.Level4RoundActive==true
 and result.attributes.RoundLoadingState=="ready","Level 4 normal entry not ready within bounded observation")
assert(result.maps[1].inWorkspace and not result.maps[2].inWorkspace and not result.maps[3].inWorkspace,"Wrong authored level active")
assert(result.collisionMode=="Enum.ModelStreamingMode.PersistentPerPlayer","Cinema floor still globally persistent")
local entrants=0
for _,p in result.players do
 local eligible=p.inRound==true and p.preview6~=true and p.preview2~=true
 if eligible then
  entrants+=1 assert(p.persistentCollision==true,"Entrant missing persistent collision: "..p.name)
  if (p.health or 0)>0 and p.escaped~=true then
   assert(p.anchored==false and p.floor and p.floor:find("Level 4 Cinema Blender.Collision",1,true),"Entrant not released on real floor")
  end
 else assert(p.persistentCollision~=true,"Bystander/other-level received persistent collision") end
end
assert(entrants>0,"No actual entrants") result.eligibleEntrants=entrants
return HS:JSONEncode(result)
''', 'Server'
    if phase == 'entry-client':
        return prefix + snapshot('client') + '''local p=result.players[1]
assert(p.inRound==true and (p.health or 0)>0 and p.anchored==false,"Client entrant not released alive")
assert(p.floor and p.floor:find("Level 4 Cinema Blender.Collision",1,true),"Client real cinema floor missing")
assert(p.uiReady==true and p.controlsReady==true and not p.loadingError,"Client entry readiness/error")
assert(result.attributes.SelectedLevel==4 and result.attributes.RoundActive==true and result.cinemaParts>0,"Client cinema round missing")
assert(not result.maps[2].inWorkspace and not result.maps[3].inWorkspace,"Inactive levels replicated to entrant")
_G.__LazyLevel4CharacterBorrow=nil
return HS:JSONEncode(result)
''', 'Client'
    if phase == 'bystander-client':
        return prefix + snapshot('client') + '''assert(result.players[1].inRound~=true,"Selected client is an entrant")
assert(result.cinemaParts==0,"Lobby bystander streamed distant cinema geometry")
assert(not result.maps[2].inWorkspace and not result.maps[3].inWorkspace,"Inactive authored levels reached bystander")
return HS:JSONEncode(result)
''', 'Client'
    if phase == 'door-touch-client':
        wanted = 'nil' if door is None else luau_string(door)
        return prefix + f'''assert(player:GetAttribute("InRound")==true and workspace:GetAttribute("RoundActive")==true
 and workspace:GetAttribute("SelectedLevel")==4,"Requires normal active cinema round")
local character=assert(player.Character) local root=assert(character:FindFirstChild("HumanoidRootPart"))
local hum=assert(character:FindFirstChildOfClass("Humanoid")) assert(hum.Health>0,"Dead player")
local world=assert(workspace:FindFirstChild("Level 4 Cinema Blender")) local folder=assert(world:FindFirstChild("Doors"))
local wanted={wanted} local leaf,hinge,hingePart,chosen,distance
for _,d in folder:GetChildren() do
 local h=d:IsA("Model") and d:FindFirstChild("Hinge") local l=d:IsA("Model") and d:FindFirstChild("Leaf")
 local servo=h and h:FindFirstChildOfClass("HingeConstraint")
 if l and servo and d:GetAttribute("PushDoor")==true and (not wanted or d.Name==wanted) then
  local dist=(root.Position-l.Position).Magnitude
  if not distance or dist<distance then leaf,hinge,hingePart,chosen,distance=l,servo,h,d,dist end
 end
end
assert(leaf and distance<120,"No nearby interior push door")
local along=leaf.Position-hingePart.Position along=Vector3.new(along.X,0,along.Z).Unit
local normal=Vector3.yAxis:Cross(along)
if (root.Position-leaf.Position):Dot(normal)<0 then normal=-normal end
-- Put the borrowed body in actual contact; PlayerModule can overwrite Move
-- each frame, so a distant starting position alone does not prove contact.
local position=leaf.Position+normal*0.9
local params=RaycastParams.new() params.FilterType=Enum.RaycastFilterType.Include params.RespectCanCollide=true
params.FilterDescendantsInstances={{assert(world:FindFirstChild("Collision"))}}
-- Start below the room ceiling, as the production door floor check does.
local floor=workspace:Raycast(position+Vector3.yAxis*2,-Vector3.yAxis*14,params)
assert(floor and floor.Normal.Y>0.7,"No real floor at door contact")
position=Vector3.new(position.X,floor.Position.Y+hum.HipHeight+root.Size.Y/2+0.15,position.Z)
local pivot,linear,angular,move=character:GetPivot(),root.AssemblyLinearVelocity,root.AssemblyAngularVelocity,hum.MoveDirection
local rootToPivot=root.CFrame:ToObjectSpace(pivot)
local maxAngle,restore=0,false
local ok,problem=xpcall(function()
 character:PivotTo(CFrame.lookAt(position,position-normal)*rootToPivot)
 local untilClock=os.clock()+1.8
 repeat
  assert(player.Character==character and player:GetAttribute("InRound")==true and hum.Health>0,"Door trial player changed")
  hum:Move(-normal,false) task.wait(0.05) maxAngle=math.max(maxAngle,math.abs(hinge.CurrentAngle))
 until os.clock()>=untilClock
 assert(maxAngle>2 and math.abs(hinge.TargetAngle)>2,"Real door contact did not open hinge")
end,debug.traceback)
if player.Character==character and character.Parent and hum.Health>0 and player:GetAttribute("InRound")==true then
 hum:Move(move,false) character:PivotTo(pivot) root.AssemblyLinearVelocity=linear root.AssemblyAngularVelocity=angular
 restore=(character:GetPivot().Position-pivot.Position).Magnitude<0.1
end
assert(ok,problem) assert(restore,"Borrowed character movement was not restored")
return HS:JSONEncode({{phase="door-touch-client",door=chosen.Name,maxAngle=maxAngle,targetAngle=hinge.TargetAngle,
 leafCFrame={{leaf.CFrame:GetComponents()}},canCollide=leaf.CanCollide,borrowedCharacterRestored=restore,sourceWrites=0,doorWrites=0}})
''', 'Client'
    if phase == 'leave-client':
        return prefix + '''assert(player:GetAttribute("InRound")==true,"Not a round participant")
assert(workspace:GetAttribute("SelectedLevel")==4 and workspace:GetAttribute("RoundActive")==true,"No active cinema round")
assert(remotes:FindFirstChild("RoundStatus")):FireServer("leaveround")
_G.__LazyLevel4CharacterBorrow=nil
return HS:JSONEncode({phase="leave-client",normalLeaveRequest=true,sourceWrites=0})
''', 'Client'
    if phase == 'unmount-server':
        return prefix + '''local storage=game:GetService("ServerStorage") local untilClock=os.clock()+20
repeat
 local parked=storage:FindFirstChild("Level 4 Cinema Blender")
 if parked and not workspace:FindFirstChild("Level 4 Cinema Blender")
  and workspace:GetAttribute("Level4RoundActive")~=true and workspace:GetAttribute("RoundActive")~=true then break end
 task.wait(0.25)
until os.clock()>=untilClock
''' + snapshot('server') + '''assert(not result.maps[1].inWorkspace and result.maps[1].inServerStorage,"Cinema did not park after ordinary return")
assert(result.attributes.Level4RoundActive~=true and result.attributes.RoundActive~=true and not result.usherVisual,"Cinema cleanup still active")
local world=assert(storage:FindFirstChild("Level 4 Cinema Blender"))
assert(not world:FindFirstChild("Level 4 Round Runtime"),"Round runtime leaked in parked cinema")
local collision=assert(world:FindFirstChild("Collision")) assert(#collision:GetPersistentPlayers()==0,"Parked floor retained persistent members")
for _,p in result.players do assert(p.inRound~=true,"Player retained round marker") end
for _,door in result.doors do assert(door.linearSpeed<0.001 and door.angularSpeed<0.001,"Parked door retained velocity") end
return HS:JSONEncode(result)
''', 'Server'
    if phase == 'cancel-client':
        return prefix + '''assert(player:GetAttribute("InRound")~=true,"Use normal round exit after admission")
assert(remotes:FindFirstChild("ConfigureQueue")):FireServer(STATION,0,"cancel")
task.wait(0.5)
local borrowed=_G.__LazyLevel4CharacterBorrow local restored=false
if borrowed and player.Character==borrowed.Character and player:GetAttribute("InRound")~=true then
 local hum=borrowed.Character:FindFirstChildOfClass("Humanoid")
 if borrowed.Character.Parent and hum and hum.Health>0 and borrowed.Root.Parent then
  borrowed.Character:PivotTo(borrowed.Pivot)
  borrowed.Root.AssemblyLinearVelocity=borrowed.Linear borrowed.Root.AssemblyAngularVelocity=borrowed.Angular
  restored=(borrowed.Character:GetPivot().Position-borrowed.Pivot.Position).Magnitude<0.1
 end
end
_G.__LazyLevel4CharacterBorrow=nil
return HS:JSONEncode({phase="cancel-client",normalCancelRequest=true,borrowedCharacterRestored=restored,sourceWrites=0})
''', 'Client'
    raise AssertionError(phase)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=PHASES)
    parser.add_argument('label', help='unique immutable receipt label')
    parser.add_argument('--station', type=int, choices=range(113, 117), default=113)
    parser.add_argument('--party-size', type=int, choices=range(1, 7), default=1)
    parser.add_argument('--expected-player', type=int)
    parser.add_argument('--door')
    parser.add_argument('--code-only', action='store_true', help='print Luau and invoke no native tool')
    args = parser.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_.-]{1,70}', args.label), 'Unsafe receipt label'
    code, model = code_for(args.phase, args.station, args.party_size, args.expected_player, args.door)
    if args.code_only:
        print(code)
        return
    receipt_path = HERE / ('runtime-level4-' + args.label + '.json')
    code_path = ROOT / '.git/lazy-levels-20261009' / ('runtime-level4-' + args.label + '.luau')
    assert not receipt_path.exists() and not code_path.exists(), 'Do not overwrite native phase evidence'
    code_path.parent.mkdir(parents=True, exist_ok=True)
    with code_path.open('x', encoding='utf-8', newline='\n') as handle:
        handle.write(code)
    receipt = {'task': 'lazy-levels-20261009', 'phase': args.phase, 'label': args.label,
               'datamodel': model, 'station': args.station, 'partySize': args.party_size,
               'expectedPlayer': args.expected_player, 'codeSHA256': hashlib.sha256(code.encode()).hexdigest(),
               'helperSHA256': hashlib.sha256(HELPER.read_bytes()).hexdigest(), 'passed': False}
    client = None
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
        assert studio['id'] == STUDIO_ID, 'Authoritative Studio session changed'
        receipt['studio'] = studio
        result = json.loads(client.call('execute_luau', {'studio_id': studio['id'], 'datamodel_type': model, 'code': code}))
        receipt['result'] = result
        receipt['passed'] = True
    except Exception as error:
        receipt['error'] = str(error)
        raise
    finally:
        if client:
            client.close()
        receipt['capturedAtUtc'] = datetime.now(timezone.utc).isoformat()
        receipt['limits'] = 'This one explicitly invoked Studio QA phase only; no Source/map Parent edits, Play lifecycle, full gameplay or performance claim'
        with receipt_path.open('x', encoding='utf-8', newline='\n') as handle:
            json.dump(receipt, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
    print(json.dumps({'phase': args.phase, 'label': args.label, 'passed': True, 'receipt': str(receipt_path), 'result': result}))


if __name__ == '__main__':
    main()
