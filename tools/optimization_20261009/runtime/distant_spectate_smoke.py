"""Root-reviewed, bounded actual distant-first spectate smoke; never edits sources.

Without --run this only prints payload metadata. Root supplies fresh active test
IDs after normal two-client Level 2 entry. The controlled path borrows only the
client replica names of Player2 HRP/Head, not Humanoid, parenting or server parts.
Player1's delayed death is intentional gameplay input; root owns normal leave.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = ROOT / "tools/optimization_20261009/runtime"


def literal(value):
    return json.dumps(json.dumps(value, separators=(",", ":")), ensure_ascii=True)


GUARD = '''local H=game:GetService("HttpService")
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local config=H:JSONDecode(__CONFIG__)
assert(Run:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong active place")
assert(workspace:GetAttribute("SelectedLevel")==2 and workspace:GetAttribute("RoundActive")==true,"Expected current normal Level 2 round")
local map=assert(workspace:FindFirstChild("Level 2 Generated World"),"Missing actual generated world")
local p1=assert(Players:FindFirstChild("Player1"),"Missing Player1")
local p2=assert(Players:FindFirstChild("Player2"),"Missing Player2")
assert(#Players:GetPlayers()==2,"Test requires exactly two participants")
local function xyz(v) return {v.X,v.Y,v.Z} end
local function body(p)
 local c=p.Character
 return c,c and c:FindFirstChildOfClass("Humanoid"),c and c:FindFirstChild("HumanoidRootPart")
end
local function live100(p)
 local c,h,r=body(p)
 assert(c and h and r and h.Health==100 and p:GetAttribute("InRound")==true and p:GetAttribute("Escaped")~=true,"Expected living health100 participant: "..p.Name)
 return c,h,r
end
'''

SERVER_MOVE = '''assert(Players.LocalPlayer==nil,"Expected Server")
local gm=assert(game:GetService("ServerScriptService"):FindFirstChild("GameManager"))
assert(string.find(gm.Source,"spectatecandidates",1,true),"Reviewed server candidate fix not present")
local c1,h1,r1=live100(p1)
local c2,h2,r2=live100(p2)
local before={characterId=c2:GetDebugId(0),rootId=r2:GetDebugId(0),pivot={c2:GetPivot():GetComponents()},rootPosition=xyz(r2.Position),linearVelocity=xyz(r2.AssemblyLinearVelocity),angularVelocity=xyz(r2.AssemblyAngularVelocity)}
local marker=assert(map:FindFirstChild("Markers") and map.Markers:FindFirstChild("P2_01"),"Missing actual P2_01 marker")
assert(marker:IsA("BasePart"),"Unexpected marker shape")
local collision=assert(map:FindFirstChild("Collision"))
local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={collision};rp.RespectCanCollide=true
-- This authored marker is at body height under a vaulted ceiling. Start below
-- that ceiling, so the floor check cannot mistake its top for walkable ground.
local hit=workspace:Raycast(marker.Position+Vector3.new(0,2,0),Vector3.new(0,-15,0),rp)
assert(hit and hit.Normal.Y>.95 and hit.Instance.CanCollide,"No safe actual target floor")
local target=hit.Position+Vector3.new(0,3.6,0)
local distance=(target-r1.Position).Magnitude
assert(distance>=800 and distance<=1300,"Unexpected distant test separation")
local attempted=false
local ok,err=xpcall(function()
 p2:RequestStreamAroundAsync(target,5)
 live100(p1);live100(p2)
 assert(p2.Character==c2 and r2.Parent==c2,"Target body changed during stream request")
 attempted=true
 c2:PivotTo(CFrame.new(target)*r2.CFrame:ToObjectSpace(c2:GetPivot()))
 r2.AssemblyLinearVelocity=Vector3.zero;r2.AssemblyAngularVelocity=Vector3.zero
 task.wait(.2)
 assert(h2.Health==100 and (r2.Position-target).Magnitude<5,"Target relocation did not settle safely")
end,debug.traceback)
local partialRestore=false
if not ok and attempted and p2.Character==c2 and r2.Parent==c2 then
 partialRestore=pcall(function() c2:PivotTo(CFrame.new(table.unpack(before.pivot)));r2.AssemblyLinearVelocity=Vector3.new(table.unpack(before.linearVelocity));r2.AssemblyAngularVelocity=Vector3.new(table.unpack(before.angularVelocity)) end)
end
return H:JSONEncode({ok=ok,error=not ok and tostring(err) or nil,before=before,moveAttempted=attempted,partialRestore=partialRestore,target=xyz(target),targetFloor=hit.Instance:GetFullName(),separationStuds=distance,player1UserId=p1.UserId,player2UserId=p2.UserId,player2Position=xyz(r2.Position),player2Health=h2.Health})
'''

CLIENT2_ARRIVAL = '''assert(Players.LocalPlayer==p2,"Wrong Client2")
local deadline=os.clock()+3
local result
repeat
 local c,h,r=body(p2)
 if c and h and r then
  local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={map};rp.RespectCanCollide=true
  local hit=workspace:Raycast(r.Position+Vector3.new(0,2,0),Vector3.new(0,-15,0),rp)
  result={health=h.Health,position=xyz(r.Position),targetDistance=(r.Position-Vector3.new(table.unpack(config.target))).Magnitude,floor=hit and hit.Instance:GetFullName(),floorNormalY=hit and hit.Normal.Y}
  if h.Health==100 and result.targetDistance<5 and hit and hit.Normal.Y>.95 then result.ok=true;break end
 end
 task.wait(.05)
until os.clock()>=deadline
return H:JSONEncode(result or {ok=false,reason="Target replica unavailable"})
'''

CLIENT1_NATURAL = '''assert(Players.LocalPlayer==p1,"Wrong Client1")
live100(p1)
assert(p1:GetAttribute("Spectating")~=true and p1:GetAttribute("SpectateTargetUserId")==nil,"Not a fresh first spectate")
local controller=assert(p1.PlayerScripts:FindFirstChild("SpectateController"))
assert(controller.Enabled and string.find(controller.Source,"spectatecandidates",1,true),"Reviewed client candidate fix not present")
local c,h,r=body(p2);local head=c and c:FindFirstChild("Head")
return H:JSONEncode({characterPresent=c~=nil,humanoidPresent=h~=nil,rootPresent=r~=nil,headPresent=head~=nil,humanoidHealth=h and h.Health,characterId=c and c:GetDebugId(0),rootId=r and r:GetDebugId(0),headId=head and head:GetDebugId(0),requiredBodyNaturallyMissing=not(c and h and r),clientControllerBytes=#controller.Source})
'''

SERVER_SCHEDULE = '''assert(Players.LocalPlayer==nil,"Expected Server")
local c1,h1,r1=live100(p1);local c2,h2,r2=live100(p2)
assert(c2:GetDebugId(0)==config.before.characterId and r2:GetDebugId(0)==config.before.rootId,"Target server identity changed")
assert((r2.Position-r1.Position).Magnitude>=800,"Target returned near before first spectate")
assert(c2:FindFirstChild("Head") and c2:FindFirstChildOfClass("Humanoid"),"Server target parts unexpectedly missing")
local due=workspace:GetServerTimeNow()+3
task.delay(3,function()
 if Run:IsRunning() and workspace:GetAttribute("RoundActive")==true and workspace:GetAttribute("SelectedLevel")==2 and p1.Parent==Players and p1.Character==c1 and h1.Parent==c1 and h1.Health==100 and p1:GetAttribute("InRound")==true and p2.Parent==Players and p2.Character==c2 and h2.Parent==c2 and h2.Health==100 and p2:GetAttribute("InRound")==true and p2:GetAttribute("Escaped")~=true then
  h1.Health=0
 end
end)
return H:JSONEncode({scheduled=true,deathDueServerTime=due,player1HumanoidId=h1:GetDebugId(0),player2RootName=r2.Name,player2HeadName=c2.Head.Name,manualSpectateRemote=false,extraReplicationFocus=false})
'''

CLIENT_FIXTURE = '''assert(Players.LocalPlayer==p1,"Wrong Client1")
local report={kind="actual-distant-first-spectate",artificialNameAbsence=false,renamed={},selectionEvents={},candidateResponses={},editMutation=false,manualSpectateRemote=false,extraReplicationFocus=false}
local borrowed,connections={},{}
local cleanupDone=false
local function availability()
 local c,h,r=body(p2);local head=c and c:FindFirstChild("Head")
 return {characterPresent=c~=nil,humanoidPresent=h~=nil,rootPresent=r~=nil,headPresent=head~=nil,humanoidHealth=h and h.Health}
end
local function restoreNames()
 local result={complete=true,restored={},conflicts={}}
 for _,b in ipairs(borrowed) do
  local ok,err=pcall(function()
   assert(b.instance:GetDebugId(0)==b.id and b.instance.ClassName==b.class,"Borrowed identity changed")
   if b.instance.Name==b.fixtureName then b.instance.Name=b.originalName
   else assert(b.instance.Name==b.originalName,"Concurrent name change; left untouched") end
   assert(b.instance.Name==b.originalName,"Name restoration failed")
   table.insert(result.restored,{id=b.id,name=b.instance.Name,parentPresent=b.instance.Parent~=nil})
  end)
  if not ok then result.complete=false;table.insert(result.conflicts,{id=b.id,error=tostring(err)}) end
 end
 for _,connection in ipairs(connections) do
  local ok,err=pcall(function() connection:Disconnect() end)
  if not ok then result.complete=false;table.insert(result.conflicts,{connection=true,error=tostring(err)}) end
 end
 table.clear(connections)
 cleanupDone=result.complete
 return result
end
-- Independent native watchdog is armed before borrowing names; no globals or
-- new Instances. Normal completion cancels it after exact-name cleanup.
local watchdog=task.delay(15,function() if not cleanupDone then restoreNames() end end)
local ok,err=xpcall(function()
 live100(p1)
 assert(workspace:GetServerTimeNow()<config.deathDueServerTime,"Client call missed delayed death; no names borrowed")
 assert(p1:GetAttribute("Spectating")~=true and p1:GetAttribute("SpectateTargetUserId")==nil,"First spectate already started")
 report.naturalBefore=availability()
 local char=p2.Character
 local root=char and char:FindFirstChild("HumanoidRootPart")
 local head=char and char:FindFirstChild("Head")
 local hum=char and char:FindFirstChildOfClass("Humanoid")
 if char and root and head and hum and hum.Health==100 then
  report.artificialNameAbsence=true;report.fixtureMode="controlled-client-HRP-and-Head-name-absence"
  for _,pair in ipairs({{root,"HRP"},{head,"Head"}}) do
   local instance=pair[1]
   assert(instance:IsA("BasePart") and instance.Parent==char,"Unexpected borrowed part")
   local name="__DistantSpectate_"..config.token.."_"..pair[2]
   assert(char:FindFirstChild(name)==nil,"Fixture name collision")
   local b={instance=instance,id=instance:GetDebugId(0),class=instance.ClassName,originalName=instance.Name,fixtureName=name}
   table.insert(borrowed,b)
   instance.Name=name
   table.insert(report.renamed,{id=b.id,originalName=b.originalName,fixtureName=name})
  end
 else report.fixtureMode="natural-missing-required-replica-parts" end
 local remote=assert(game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") and game.ReplicatedStorage.Remotes:FindFirstChild("RoundStatus"))
 table.insert(connections,remote.OnClientEvent:Connect(function(message,payload)
  if message=="spectatecandidates" and type(payload)=="table" and type(payload.UserIds)=="table" then
   local ids={};for i=1,math.min(16,#payload.UserIds) do ids[i]=payload.UserIds[i] end
   table.insert(report.candidateResponses,{serial=payload.Serial,userIds=ids,serverTime=workspace:GetServerTimeNow()})
   while #report.candidateResponses>8 do table.remove(report.candidateResponses,1) end
  end
 end))
 table.insert(connections,p1:GetAttributeChangedSignal("SpectateTargetUserId"):Connect(function()
  local a=availability()
  table.insert(report.selectionEvents,{target=p1:GetAttribute("SpectateTargetUserId"),rootMissing=not a.rootPresent,headMissing=not a.headPresent,humanoidMissing=not a.humanoidPresent,serverTime=workspace:GetServerTimeNow()})
  while #report.selectionEvents>8 do table.remove(report.selectionEvents,1) end
 end))
 report.afterBorrow=availability()
 local deadline=os.clock()+8
 repeat
  local validated=false
  for _,response in ipairs(report.candidateResponses) do for _,id in ipairs(response.userIds) do if id==p2.UserId then validated=true end end end
  local selectedMissing=false
  for _,event in ipairs(report.selectionEvents) do if event.target==p2.UserId and (event.rootMissing or event.humanoidMissing) then selectedMissing=true end end
  local _,h=body(p1)
  if validated and selectedMissing and p1:GetAttribute("Spectating")==true and p1:GetAttribute("SpectateTargetUserId")==p2.UserId and p2:GetAttribute("SpectatorCount")==1 and h and h.Health==0 then
   report.selectionPassed=true;report.selectedWhileRequiredBodyMissing=true
   report.targetUserId=p2.UserId;report.spectatorCount=p2:GetAttribute("SpectatorCount")
   break
  end
  task.wait(.05)
 until os.clock()>=deadline
 assert(report.selectionPassed,"No validated distant first target while required replica body was missing")
end,debug.traceback)
report.selectionError=not ok and tostring(err) or nil
report.nameCleanup=restoreNames()
if report.nameCleanup.complete then pcall(function() task.cancel(watchdog) end) end
local cameraOK,cameraErr=xpcall(function()
 assert(ok and report.nameCleanup.complete,"Selection/name cleanup failed; camera pass not claimed")
 local deadline=os.clock()+5
 repeat
  local c,h,r=body(p2);local head=c and c:FindFirstChild("Head");local cam=workspace.CurrentCamera
  if h and h.Health==100 and r and head and cam then
   local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={map};rp.RespectCanCollide=true
   local hit=workspace:Raycast(r.Position+Vector3.new(0,2,0),Vector3.new(0,-15,0),rp)
   local distance=(cam.CFrame.Position-head.Position).Magnitude
   if p1:GetAttribute("SpectateTargetUserId")==p2.UserId and cam.CameraType==Enum.CameraType.Scriptable and distance<3 and hit and hit.Normal.Y>.95 then
    report.cameraPassed=true;report.camera={position=xyz(cam.CFrame.Position),targetHead=xyz(head.Position),targetRoot=xyz(r.Position),distanceToHead=distance,type=cam.CameraType.Name,floor=hit.Instance:GetFullName(),floorPosition=xyz(hit.Position),targetHealth=h.Health}
    break
   end
  end
  task.wait(.05)
 until os.clock()>=deadline
 assert(report.cameraPassed,"No actual camera/floor arrival after part restoration")
end,debug.traceback)
report.cameraError=not cameraOK and tostring(cameraErr) or nil
report.complete=ok and cameraOK and report.nameCleanup.complete
return H:JSONEncode(report)
'''

SERVER_FINAL = '''assert(Players.LocalPlayer==nil,"Expected Server")
local c1,h1=body(p1);local c2,h2,r2=body(p2)
local ok=c1~=nil and h1~=nil and h1.Health==0 and c2~=nil and h2~=nil and h2.Health==100 and r2~=nil and c2:FindFirstChild("Head")~=nil and r2.Name=="HumanoidRootPart" and p2:GetAttribute("SpectatorCount")==1 and c2:GetDebugId(0)==config.before.characterId and r2:GetDebugId(0)==config.before.rootId
return H:JSONEncode({ok=ok,player1Health=h1 and h1.Health,player2Health=h2 and h2.Health,targetSpectatorCount=p2:GetAttribute("SpectatorCount"),player2CharacterId=c2 and c2:GetDebugId(0),player2RootId=r2 and r2:GetDebugId(0),serverRootName=r2 and r2.Name,serverHeadName=c2 and c2:FindFirstChild("Head") and c2.Head.Name,player1InRound=p1:GetAttribute("InRound"),player2InRound=p2:GetAttribute("InRound"),ordinaryLeaveStillRootOwned=true})
'''

SERVER_RESTORE = '''assert(Players.LocalPlayer==nil,"Expected Server")
local c,h,r=body(p2)
assert(c and h and r and h.Health==100 and c:GetDebugId(0)==config.before.characterId and r:GetDebugId(0)==config.before.rootId,"Target round body changed; preserve current state")
assert((r.Position-Vector3.new(table.unpack(config.target))).Magnitude<25,"Target moved independently; preserve current position")
p2:RequestStreamAroundAsync(Vector3.new(table.unpack(config.before.rootPosition)),5)
assert(p2.Character==c and r.Parent==c and h.Health==100,"Target body changed during restoration request")
c:PivotTo(CFrame.new(table.unpack(config.before.pivot)))
r.AssemblyLinearVelocity=Vector3.new(table.unpack(config.before.linearVelocity));r.AssemblyAngularVelocity=Vector3.new(table.unpack(config.before.angularVelocity))
return H:JSONEncode({restored=true,characterId=c:GetDebugId(0),position=xyz(r.Position),player2Health=h.Health})
'''


def source(body_text, config):
    return GUARD.replace("__CONFIG__", literal(config)) + body_text


def exercise(call, config, report, save):
    """No hidden concurrency; only the intentional native delayed death spans calls."""
    moved = None
    try:
        report["moveRequested"] = True
        save()
        moved = call("Server", source(SERVER_MOVE, config))
        report["relocation"] = moved
        save()
        if not moved.get("ok"):
            raise AssertionError("Safe target relocation failed")
        config.update(before=moved["before"], target=moved["target"])
        arrival = call("Client2", source(CLIENT2_ARRIVAL, config))
        report["targetClientArrival"] = arrival
        if not arrival.get("ok"):
            raise AssertionError("Actual Client2 target arrival/floor failed")
        report["naturalPreFixtureAvailability"] = call("Client1", source(CLIENT1_NATURAL, config))
        save()
        report["deathScheduleRequested"] = True
        save()
        scheduled = call("Server", source(SERVER_SCHEDULE, config))
        report["deathSchedule"] = scheduled
        config["deathDueServerTime"] = scheduled["deathDueServerTime"]
        # No extra MCP call or disk write between scheduling and fixture start.
        fixture = call("Client1", source(CLIENT_FIXTURE, config))
        report["actualClientFixture"] = fixture
        save()
        if not fixture.get("complete"):
            raise AssertionError("Distant-first candidate/cleanup/camera check failed")
        final = call("Server", source(SERVER_FINAL, config))
        report["actualServerAfter"] = final
        if not final.get("ok"):
            raise AssertionError("Actual server death/target-count/identity check failed")
        report["scenarioPassed"] = True
    except Exception as exc:
        report["scenarioPassed"] = False
        report["error"] = str(exc)
    finally:
        if moved and moved.get("ok"):
            try:
                report["targetPositionCleanup"] = call("Server", source(SERVER_RESTORE, config))
            except Exception as exc:
                report["targetPositionCleanup"] = {"restored": False, "error": str(exc)}
        elif moved:
            report["targetPositionCleanup"] = {"restored": not moved.get("moveAttempted") or bool(moved.get("partialRestore")), "withinFailedMove": True}
        else:
            report["targetPositionCleanup"] = {"restored": False, "unknownNativeMoveOutcome": True}
        fixture = report.get("actualClientFixture", {})
        report["nameCleanupVerified"] = bool(fixture.get("nameCleanup", {}).get("complete"))
        if report.get("deathScheduleRequested") and not fixture:
            report["nameCleanupOutcomeUnknown"] = True
            report["recovery"] = "Native watchdog attempts guarded restoration at 15 seconds; transport loss is not cleanup proof. Root must inspect original Client1 names and use normal round leave before resuming."
        report["complete"] = bool(report.get("scenarioPassed") and report["nameCleanupVerified"] and report["targetPositionCleanup"].get("restored"))
        report["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        save()
    return report["complete"]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server")
    parser.add_argument("--client1")
    parser.add_argument("--client2")
    parser.add_argument("--run", action="store_true", help="Root only, after source review and normal two-client L2 entry")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args(argv)
    config = {"token": uuid.uuid4().hex}
    if not args.run:
        pieces = [SERVER_MOVE, CLIENT2_ARRIVAL, CLIENT1_NATURAL, SERVER_SCHEDULE, CLIENT_FIXTURE, SERVER_FINAL, SERVER_RESTORE]
        print(json.dumps({"preparedOnly": True, "studioConnectionOpened": False, "payloads": [{"bytes": len(x.encode()), "sha256": hashlib.sha256(x.encode()).hexdigest()} for x in pieces], "maxClientSelectionSeconds": 8, "maxCameraSeconds": 5, "nameWatchdogSeconds": 15}, indent=2))
        return 0
    for flag in ("server", "client1", "client2"):
        value = getattr(args, flag)
        if not value:
            parser.error("--run requires --server, --client1 and --client2")
        try:
            uuid.UUID(value)
        except ValueError:
            parser.error("Invalid Studio id for --" + flag)
    if len({args.server, args.client1, args.client2}) != 3:
        parser.error("Server/Client IDs must be distinct")
    receipt = args.receipt or RUNTIME / "observations" / ("distant-first-spectate-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".json")
    if receipt.exists():
        parser.error("Receipt already exists; preserve it and choose a fresh --receipt path")
    report = {"kind": "actual-distant-first-spectate-smoke", "startedUtc": datetime.now(timezone.utc).isoformat(), "studioIds": {"server": args.server, "client1": args.client1, "client2": args.client2}, "editMutation": False, "newInstances": False, "newProbes": False, "runtimeInputs": ["safe actual Player2 relocation", "intentional delayed Player1 ordinary death", "optional Client1-only HRP/Head names borrowed"], "normalQueueAndLeaveRootOwned": True, "naturalStreamOutPass": False, "fpsOrPerformancePass": False}
    receipt.parent.mkdir(parents=True, exist_ok=True)
    def save():
        receipt.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    save()
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch
    client = None
    complete = False
    def call(surface, code):
        studio_id = {"Server": args.server, "Client1": args.client1, "Client2": args.client2}[surface]
        return json.loads(client.call("execute_luau", {"studio_id": studio_id, "datamodel_type": "Server" if surface == "Server" else "Client", "code": code}))
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        report["connectionInitialized"] = True
        complete = exercise(call, config, report, save)
    except Exception as exc:
        report.update(complete=False, error=str(exc), finishedUtc=datetime.now(timezone.utc).isoformat())
        save()
    finally:
        if client is not None:
            client.close()
    print(json.dumps({"complete": complete, "receipt": str(receipt), "normalLeaveStillRootOwned": True}))
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
