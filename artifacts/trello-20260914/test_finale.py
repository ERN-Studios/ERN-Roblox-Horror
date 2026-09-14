"""Execute actual finale trigger and spawn functions; no Studio or live data writes."""
from pathlib import Path
import subprocess
HERE=Path(__file__).resolve().parent
SYSTEMS=Path('ServerScriptService/Level 3 Systems')
def read(folder,name): return (HERE/folder/SYSTEMS/name).read_text(encoding='utf-8')
def section(s,start,end): return s[s.index(start):s.index(end,s.index(start))]
ai=read('finale-proposed','Level 3 Mall Manager AI Controller.ModuleScript.lua')
obj=read('finale-proposed','Level 3 Objective Controller.ModuleScript.lua')
before=read('finale-before','Level 3 Mall Manager AI Controller.ModuleScript.lua')
# Everything in normal spawn selection and gameplay remains byte-for-byte identical.
assert ai[ai.index('local function chooseBlackoutSpawn'):]==before[before.index('local function chooseBlackoutSpawn'):]
PRELUDE=r'''
type AnyTable = {[any]:any}
local checks=0
local function warn(_) end
local function check(v,m) checks+=1; assert(v,m) end
local Vector3={}
local mt={}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
mt.__div=function(a,b) return a*(1/b) end
mt.__index=function(v,k)
 if k=='Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k=='Unit' then return v/v.Magnitude end
 if k=='Dot' then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
Vector3.zero=Vector3.new(0,0,0)
local function attributes()
 return {attrs={},order={},GetAttribute=function(self,k) return self.attrs[k] end,
 SetAttribute=function(self,k,v) self.attrs[k]=v; table.insert(self.order,k) end}
end
local workspace=attributes()
local Players={players={},GetPlayers=function(self) return self.players end}
local function validPlayer(p) return not p.lobby and not p.escaped end
local function livingCharacter(p) if not p.dead then return p.character,{},p.root end end
local function player(id,x,z)
 return {UserId=id,character={},root={Position=Vector3.new(x,3,z or 0)}}
end
local function makeSession()
 local state=attributes(); state.attrs.Level3_RoomSongPhase='DONE'
 return {ExitUnlocked=true,FinalHallCrossed={},State=state,Manifest={World=attributes(),
 FinalHall={Model={Parent=true},StartPoint=Vector3.new(100,0,0),Forward=Vector3.new(1,0,0),Length=560,Width=20,Height=20,FloorY=0},
 MazeStart={Parent=true,Position=Vector3.new(-200,.25,0),CFrame={LookVector=Vector3.new(1,0,0)}}}}
end
local currentRecords={}
local blocked=false
local function eligibleSpawnPlayers() return currentRecords end
local function spawnOverlapParams() return {} end
local function spawnVolumeFits(position) return not blocked and position.X>=-188 end
local function spawnVisibilityCount() return 0 end
local function planarDistance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function nearestRoomId(p) return if p.X<0 then 'Arrival' else 'SignalHall' end
local function stateFolder() return attributes() end
local Random={new=function() return {} end}
'''
TEST=r'''
local session=makeSession()
local first=player(1,106)
local laggard=player(2,-50)
Players.players={first,laggard}
session.ExitUnlocked=false
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'started before CDs unlocked exit')
session.ExitUnlocked=true; session.State.attrs.Level3_RoomSongPhase='BLACKOUT'
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'normal gameplay changed')
session.State.attrs.Level3_RoomSongPhase='DONE'
first.root.Position=Vector3.new(102,3,0)
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'started outside entry commitment')
first.root.Position=Vector3.new(106,3,80)
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'started outside hall width')
first.root.Position=Vector3.new(106,3,0); first.dead=true
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'dead player triggered finale')
first.dead=false; first.lobby=true
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'lobby player triggered finale')
first.lobby=false
updateFinalHallChase(session)
check(session.FinalHallChaseTriggered,'first runner did not trigger with laggard still outside')
check(session.FinalHallCrossedCount==1 and session.FinalHallEligibleCount==2,'cohort diagnostic counts wrong')
check(workspace.order[#workspace.order-1]=='Level3FinalHallChaseActive' and workspace.order[#workspace.order]=='Level3MallManagerHuntActive','spawn mode must precede lifecycle edge')
local writes=#workspace.order
updateFinalHallChase(session)
check(#workspace.order==writes,'finale triggered twice')
currentRecords={{Player=first,Position=first.root.Position},{Player=laggard,Position=laggard.root.Position}}
local spawn=chooseFinalHallSpawn(session.Manifest,12)
check(spawn~=nil and spawn.Position.X==-188 and spawn.Position.Y==0,'spawn not at first clear level-entry point')
check(spawn.RoomId=='Arrival' and spawn.FinalHallChase,'wrong spawn mode/room')
check(spawn.Anchor.Player==laggard,'hunt anchor is not nearest living player')
check(spawn.SpawnClearanceValidated,'spawn clearance not checked')
blocked=true
check(chooseFinalHallSpawn(session.Manifest,12)==nil,'blocked entry must retry, not teleport to exit')
blocked=false; currentRecords={}
check(chooseFinalHallSpawn(session.Manifest,12)==nil,'spawned without living player')
check(not insideFinalHall(session,session.Manifest.MazeStart.Position),'entry treated as direct hall route')
check(insideFinalHall(session,Vector3.new(150,0,0)),'hall position rejected')
check(not insideFinalHall(session,Vector3.new(150,0,100)),'unrelated parallel room treated as hall')
print('PASS Level 3 finale: '..checks..' scenario assertions; normal spawn/gameplay source unchanged')
'''
code=PRELUDE+'\n'+section(obj,'local function updateFinalHallChase','local function promptWorldPosition')+'\n'+section(ai,'local function insideFinalHall','-- A bounded repair')+'\n'+section(ai,'local function chooseFinalHallSpawn','local function chooseBlackoutSpawn')+'\n'+TEST
host=HERE/'finale-runtime.luau'; host.write_text(code,encoding='utf-8')
r=subprocess.run([r'C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe',str(host)],text=True,capture_output=True)
print(r.stdout,end=''); print(r.stderr,end=''); raise SystemExit(r.returncode)
