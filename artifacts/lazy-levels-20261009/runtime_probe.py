"""Explicit bounded Play phases; importing this file performs no native calls.

Root invokes selected phases after starting the existing Studio test session.
Every invocation writes a distinct immutable receipt. No Edit source/property
writes, Play start/stop, publication, fake streaming acknowledgements or access
bypasses. Shared state and client connections belong only to --session.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STUDIO_ID = '1b603e69-7ae1-4572-b210-d5bf05c684ff'

COMMON = r'''
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local Players=game:GetService("Players") local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage") local SSS=game:GetService("ServerScriptService")
local Rep=game:GetService("ReplicatedStorage") local Http=game:GetService("HttpService")
assert(RS:IsRunning(),"Requires an existing Play session")
local KEY=__KEY__
local PHASE_STARTED=os.clock()
local NAMES={[4]="Level 4 Cinema Blender",[5]="Level 5 Void",[6]="Level 6 Indoor Playground"}
local LIMITS="Single native Studio test client; no published/mobile, multiplayer or cold-cache performance claim."
local function player()
 if RS:IsClient() then return assert(Players.LocalPlayer,"Missing local player") end
 local list=Players:GetPlayers() assert(#list==1,"Requires exactly one existing test client") return list[1]
end
local function body(p)
 local c=p.Character local h=c and c:FindFirstChildOfClass("Humanoid") local r=c and c:FindFirstChild("HumanoidRootPart")
 return c,h,r
end
local function healthy(p)
 local c,h,r=body(p)
 return c and h and r and c:IsDescendantOf(workspace) and h.Health>0 and h:GetState()~=Enum.HumanoidStateType.Dead and not r.Anchored
end
local function floor(model,at)
 local params=RaycastParams.new() params.FilterType=Enum.RaycastFilterType.Include params.FilterDescendantsInstances={model}
 params.RespectCanCollide=true
 local hit=workspace:Raycast(at+Vector3.new(0,8,0),Vector3.new(0,-100,0),params)
 return hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide and hit.Normal.Y>.6,hit and hit.Instance:GetFullName()
end
local function location(model)
 return model and (model.Parent==workspace and "Workspace" or model.Parent==SS and "ServerStorage" or tostring(model.Parent)) or "missing"
end
local function report(p)
 local c,h,r=body(p)
 local out={attributes=p:GetAttributes(),healthy=healthy(p) and true or false,
  position=r and tostring(r.Position) or "missing",health=h and h.Health or 0,worlds={},limits=LIMITS}
 for level,name in NAMES do out.worlds[tostring(level)]={workspace=workspace:FindFirstChild(name)~=nil} end
 return out
end
local function emit(out) return Http:JSONEncode(out) end
local function owned() return assert(shared[KEY],"Start this side's session baseline first") end
local function required(parent,name) return assert(parent:FindFirstChild(name),"Missing existing runtime endpoint: "..name) end
local function statusRemote() return required(required(Rep,"Remotes"),"RoundStatus") end
local function waitUntil(seconds,test,message)
 local deadline=math.min(os.clock()+seconds,PHASE_STARTED+42)
 repeat if test() then return end task.wait(.1) until os.clock()>=deadline
 assert(test(),message)
end
local function gameState() return require(required(required(SSS,"Level 6 Systems"),"Level 6 Playground Game")).State() end
local function serverWorlds(st)
 local storage=require(required(SSS,"LevelWorldStorage")) local out={}
 for level,original in st.maps do
  local current=storage.Get(level) assert(current==original,"Original authored identity changed: "..level)
  out[tostring(level)]={location=location(current),sameOriginal=true}
 end return out
end
local function entry(level)
 local st=owned() local p=player() local model=st.maps[level]
 waitUntil(38,function()
  local marker=p:GetAttribute("Level6PlaygroundPreview")==true
  local specific=level~=5 or p:GetAttribute("Level5VoidRound")==true
  return st.job and st.job.done and st.job.level==level and marker and specific and p:GetAttribute("InRound")==true
   and p.Character~=st.beforeCharacter and healthy(p)
 end,"Entry worker/body did not complete")
 assert(st.job.ok and st.job.joined==1,"Actual LaunchParty rejected: "..tostring(st.job.problem))
 assert(model.Parent==workspace,"Selected original is not mounted")
 assert(st.maps[level==5 and 6 or 5].Parent==SS,"Unrelated Level 5/6 map is mounted")
 assert(st.maps[4].Parent==SS,"Unrelated Level 4 map is mounted")
 local _,_,r=body(p) local good,hit=floor(model,r.Position) assert(good,"No real server floor under round body")
 local out=report(p) out.serverWorlds=serverWorlds(st) out.job=st.job out.serverFloor=hit
 if level==6 then out.playground=gameState() end
 return emit(out)
end
local function exitServer(level)
 local st=owned() local p=player() local model=st.maps[level] local phases={}
 waitUntil(12,function()
  if level==6 then
   local phase=gameState().phase
   if phases[#phases]~=phase then table.insert(phases,phase) end
   if model.Parent==SS then assert(phase=="idle","Level 6 parked before engine/session cleanup completed") end
  end
  return model.Parent==SS and p:GetAttribute("Level6PlaygroundPreview")~=true and p:GetAttribute("Level5VoidRound")~=true and p:GetAttribute("InRound")~=true and healthy(p)
 end,"Normal leave did not unload and restore healthy lobby body")
 task.wait(2.2) -- existing launcher cooldown and existing Level 5 gate reset tween
 local out=report(p) out.serverWorlds=serverWorlds(st) out.observedCleanupPhases=phases
 if level==6 then out.playground=gameState() end
 return emit(out)
end
local function launch(level)
 local st=owned() local p=player()
 assert(not st.job or st.job.done,"Prior native engine launch still owns its worker")
 assert(p:GetAttribute("InRound")~=true and p:GetAttribute("Level6PlaygroundPreview")~=true and healthy(p),"Requires healthy lobby player")
 assert(st.maps[level].Parent==SS,"Entry must start with selected original parked")
 local fn=assert(SS:FindFirstChild("Level"..level.."LaunchParty"),"Missing actual launcher")
 assert(fn:IsA("BindableFunction"),"Wrong launch endpoint class")
 local job={level=level,done=false,startedClock=os.clock(),sequence=(st.sequence or 0)+1}
 st.sequence=job.sequence st.job=job st.party=Http:GenerateGUID(false) st.beforeCharacter=p.Character
 task.spawn(function()
  local called,accepted,joined,problem=pcall(fn.Invoke,fn,{p},st.party)
  job.called=called job.ok=called and accepted==true job.joined=called and joined or 0
  job.problem=if not called then tostring(accepted) elseif problem~=nil then tostring(problem) else nil
  job.finishedClock=os.clock() job.done=true
 end)
 return emit({launchedAsync=true,level=level,sequence=job.sequence,serverWorlds=serverWorlds(st),limits=LIMITS})
end
local function clientEntry(level)
 local st=owned() local p=player()
 waitUntil(38,function()
  local model=workspace:FindFirstChild(NAMES[level])
  return model and healthy(p) and p:GetAttribute("InRound")==true and p:GetAttribute("Level6PlaygroundPreview")==true
   and (level~=5 or p:GetAttribute("Level5VoidRound")==true)
   and not workspace:FindFirstChild(NAMES[level==5 and 6 or 5]) and not workspace:FindFirstChild(NAMES[4])
 end,"Selected map/body did not replicate on actual client")
 local model=assert(workspace:FindFirstChild(NAMES[level])) local _,_,r=body(p)
 local good,hit=floor(model,r.Position) assert(good,"No real client floor under round body")
 local visible=0
 for index,v in model:GetDescendants() do
  if index%1000==0 then task.wait() end
  if v:IsA("BasePart") and v.Transparency<1 then visible+=1 end
 end
 assert(visible>0,"No visible authored map parts on client")
 local out=report(p) out.clientFloor=hit out.visibleMapParts=visible out.win=st.win out.replicaEvents=st.replicaEvents
 return emit(out)
end
local function leaveClient(level)
 local st=owned() local p=player() assert(p:GetAttribute("Level6PlaygroundPreview")==true,"Not a live-level participant")
 if level==5 then assert(p:GetAttribute("Level5VoidRound")==true,"Not a Level 5 member") end
 statusRemote():FireServer("leaveround")
 return emit({normalLeaveRequested=true,level=level,limits=LIMITS})
end
'''

PHASES = {
 'lobby-server': ('Server', r'''
assert(shared[KEY]==nil,"Server session namespace already exists")
local p=player() assert(healthy(p) and p:GetAttribute("InRound")~=true,"Requires healthy lobby body")
local storage=require(required(SSS,"LevelWorldStorage")) local st={maps={},sequence=0}
for level,name in NAMES do
 local model=assert(storage.Get(level),"Missing parked original")
 assert(model.Parent==SS and not workspace:FindFirstChild(name),"Lobby contains inactive authored map: "..level)
 st.maps[level]=model
end
shared[KEY]=st
local out=report(p) out.serverWorlds=serverWorlds(st) out.playground=gameState() return emit(out)
'''),
 'lobby-client': ('Client', r'''
assert(shared[KEY]==nil,"Client session namespace already exists") local p=player()
waitUntil(38,function()return p:GetAttribute("LobbyLoadingDone")==true and healthy(p)end,"Lobby loader/body did not finish")
assert(p:GetAttribute("InRound")~=true,"Not in lobby")
for _,name in NAMES do assert(not workspace:FindFirstChild(name),"Inactive authored map replicated to lobby client") end
local st={connections={},replicaEvents={},roundEvents={}} shared[KEY]=st
local function replica(kind,item)
 for level,name in NAMES do if item.Name==name then
  table.insert(st.replicaEvents,{kind=kind,level=level,clock=os.clock()})
  if #st.replicaEvents>30 then table.remove(st.replicaEvents,1) end
 end end
end
local ok,problem=xpcall(function()
 table.insert(st.connections,workspace.ChildAdded:Connect(function(item)replica("added",item)end))
 table.insert(st.connections,workspace.ChildRemoved:Connect(function(item)replica("removed",item)end))
 local status=statusRemote()
 table.insert(st.connections,status.OnClientEvent:Connect(function(message,...)
  local args={...} table.insert(st.roundEvents,{message=tostring(message),clock=os.clock()})
  if #st.roundEvents>30 then table.remove(st.roundEvents,1) end
  if message=="win" and tonumber(args[5])==6 and tonumber(args[6]) then
   st.win={serial=tonumber(args[6]),deadline=tonumber(args[4]),nextLevel=6,clock=os.clock()}
  end
 end))
end,debug.traceback)
if not ok then for _,c in st.connections do c:Disconnect() end shared[KEY]=nil error(problem) end
local out=report(p)out.ownedHooks=#st.connections return emit(out)
'''),
 'launch5': ('Server', 'return launch(5)'),
 'entry5-server': ('Server', 'return entry(5)'),
 'entry5-client': ('Client', 'return clientEntry(5)'),
 'leave5-client': ('Client', 'return leaveClient(5)'),
 'exit5-server': ('Server', 'return exitServer(5)'),
 'launch6': ('Server', 'return launch(6)'),
 'entry6-server': ('Server', 'return entry(6)'),
 'entry6-client': ('Client', 'return clientEntry(6)'),
 'leave6-client': ('Client', 'return leaveClient(6)'),
 'exit6-server': ('Server', 'return exitServer(6)'),
 'exit-client': ('Client', r'''
local st=owned()local p=player()
waitUntil(12,function()
 return healthy(p) and p:GetAttribute("InRound")~=true and p:GetAttribute("Level6PlaygroundPreview")~=true
  and not workspace:FindFirstChild(NAMES[5]) and not workspace:FindFirstChild(NAMES[6])
end,"Normal leave did not release client map replicas")
local out=report(p)out.replicaEvents=st.replicaEvents return emit(out)
'''),
 'finish5-server': ('Server', r'''
local st=owned()local p=player() assert(healthy(p) and p:GetAttribute("Level5VoidRound")==true,"Requires real Level 5 member")
local model=st.maps[5] assert(model.Parent==workspace,"Level 5 original not mounted")
local finish=assert(model:FindFirstChild("Level5Finish"),"Missing authored finish") assert(finish:IsA("BasePart"),"Wrong finish class")
local at=finish.Position+Vector3.new(0,2.5,0)local good,hit=floor(model,at)assert(good,"Authored finish has no native floor")
local c,_,r=body(p)r.AssemblyLinearVelocity,r.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
c:PivotTo(CFrame.new(at))
return emit({movedBorrowedTestPlayerToAuthoredFinish=finish:GetFullName(),serverFloor=hit,serverWorlds=serverWorlds(st),limits=LIMITS})
'''),
 'continue5-client': ('Client', r'''
local st=owned()local p=player()
waitUntil(5,function()return st.win~=nil end,"Actual Level 5 win serial not received")
assert(p:GetAttribute("Level5VoidRound")==true,"Level 5 already departed")
assert(st.win.deadline and st.win.deadline>workspace:GetServerTimeNow(),"Actual win choice expired; cannot infer confirmation")
statusRemote():FireServer("continuenow",st.win.serial)
return emit({normalContinueRequested=true,capturedWin=st.win,roundEvents=st.roundEvents,limits=LIMITS})
'''),
 'continue-server': ('Server', r'''
local st=owned()local p=player()local samples={}local deadline=os.clock()+38
repeat
 table.insert(samples,{clock=os.clock(),level5=location(st.maps[5]),level6=location(st.maps[6]),
  marker5=p:GetAttribute("Level5VoidRound")==true,shared=p:GetAttribute("Level6PlaygroundPreview")==true,inRound=p:GetAttribute("InRound")==true})
 if st.maps[5].Parent==SS and st.maps[6].Parent==workspace and p:GetAttribute("Level5VoidRound")~=true
  and p:GetAttribute("Level6PlaygroundPreview")==true and p:GetAttribute("InRound")==true and healthy(p)then break end
 task.wait(.1)
until os.clock()>=deadline
assert(st.maps[5].Parent==SS and st.maps[6].Parent==workspace,"Continue did not release old map and mount destination")
assert(p:GetAttribute("Level5VoidRound")~=true and p:GetAttribute("Level6PlaygroundPreview")==true and p:GetAttribute("InRound")==true and healthy(p),"Continue markers/body failed")
local _,_,r=body(p)local good,hit=floor(st.maps[6],r.Position)assert(good,"No real destination floor after Continue")
local overlap=false for _,sample in samples do if sample.level5=="Workspace" and sample.level6=="Workspace" then overlap=true end end
local out=report(p)out.serverWorlds=serverWorlds(st)out.transferSamples=samples out.observedOverlap=overlap out.serverFloor=hit out.playground=gameState()
out.transferLimits="Polling may start after the overlap; observedOverlap=false does not establish that no overlap occurred." return emit(out)
'''),
 'cleanup-client': ('Client', r'''
local st=shared[KEY]local disconnected=0
if st then for _,c in st.connections or {} do c:Disconnect()disconnected+=1 end shared[KEY]=nil end
return emit({clientHooksDisconnected=disconnected,sessionNamespaceCleared=shared[KEY]==nil,limits=LIMITS})
'''),
 'cleanup-server': ('Server', r'''
local st=shared[KEY]
if st then
 assert(not st.job or st.job.done,"Actual engine launch still running: do not abandon owner")
 local p=player()assert(p:GetAttribute("Level6PlaygroundPreview")~=true and p:GetAttribute("InRound")~=true,"Leave normally before probe cleanup")
 for _,model in st.maps do assert(model.Parent==SS,"Authored map still mounted: do not force park")end
 shared[KEY]=nil
end
return emit({sessionNamespaceCleared=shared[KEY]==nil,limits=LIMITS})
'''),
}


def code_for(phase: str, session: str) -> tuple[str, str]:
    assert re.fullmatch(r'[A-Za-z0-9_-]{1,60}', session), 'Invalid session label'
    model, code = PHASES[phase]
    return model, COMMON.replace('__KEY__', json.dumps('__lazyLevelsRuntime_' + session)) + '\n' + code


def invoke(phase: str, session: str, label: str = '') -> tuple[Path, dict]:
    """Call one phase only when explicitly invoked by root; never on import."""
    assert not label or re.fullmatch(r'[A-Za-z0-9_-]{1,60}', label), 'Invalid receipt label'
    model, code = code_for(phase, session)
    sys.path.insert(0, str(ROOT / 'tools'))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
    client = StudioMcpClient(find_mcp_batch())
    receipt = {'task': 'lazy-levels-20261009', 'session': session, 'phase': phase, 'label': label,
               'datamodel': model, 'codeSha256': hashlib.sha256(code.encode()).hexdigest(),
               'startedAtUtc': datetime.now(timezone.utc).isoformat(), 'passed': False}
    try:
        client.initialize()
        studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
        assert studio['id'] == STUDIO_ID, 'Authoritative Studio session changed'
        receipt['result'] = json.loads(client.call('execute_luau', {
            'studio_id': studio['id'], 'datamodel_type': model, 'code': code}))
        receipt['passed'] = True
    except Exception as error:
        receipt['error'] = str(error)
    finally:
        try:
            client.close()
        except Exception as error:
            receipt['clientCloseError'] = str(error)
            receipt['passed'] = False
        receipt['finishedAtUtc'] = datetime.now(timezone.utc).isoformat()
        filename = 'runtime-' + session + '-' + phase + ('-' + label if label else '') + '-' + uuid.uuid4().hex[:10] + '.json'
        path = HERE / filename
        with path.open('x', encoding='utf-8', newline='\n') as handle:
            json.dump(receipt, handle, indent=2, ensure_ascii=False)
            handle.write('\n')
    return path, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=PHASES)
    parser.add_argument('--session', required=True)
    parser.add_argument('--label', default='')
    args = parser.parse_args()
    path, receipt = invoke(args.phase, args.session, args.label)
    print(json.dumps({'receipt': str(path), **receipt}, ensure_ascii=False))
    if not receipt['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
