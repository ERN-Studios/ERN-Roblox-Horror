"""Offline failure injection for exact generated runtime-name borrowing code.

No Studio connection or native gameplay. Luau stand-ins model time/signals and
an arriving validated candidate only to exercise the driver fixture's cleanup.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("distant_driver", HERE / "distant_spectate_smoke.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)

PRELUDE = r'''
local now=0
local scenario=__SCENARIO__
local activeConnections=0
local watchdogCancelled=false
local function vector(x,y,z)
 local v={X=x,Y=y,Z=z,Magnitude=math.sqrt(x*x+y*y+z*z)}
 return setmetatable(v,{__add=function(a,b)return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end,__sub=function(a,b)return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end})
end
Vector3={new=vector,zero=vector(0,0,0)}
Enum={CameraType={Custom={Name="Custom"},Scriptable={Name="Scriptable"}},RaycastFilterType={Include={}}}
RaycastParams={new=function()return {}end}
local function signal(label)
 local s={callbacks={}}
 function s:Connect(fn)
  if scenario=="connect-error" and label=="target" then error("injected connect failure") end
  local item={fn=fn,active=true};table.insert(self.callbacks,item);activeConnections+=1
  local c={}
  function c:Disconnect()
   if item.active then item.active=false;activeConnections-=1 end
   if scenario=="disconnect-error" and label=="target" then error("injected disconnect failure after disposal") end
  end
  return c
 end
 function s:Fire(...)
  for _,item in ipairs(self.callbacks) do if item.active then item.fn(...) end end
 end
 return s
end
local targetSignal=signal("target")
local remoteSignal=signal("remote")
local function part(name,id,position)
 local state={name=name}
 local p={ClassName="Part",Position=position,CFrame={Position=position},Parent=nil}
 function p:GetDebugId()return id end
 function p:IsA(c)return c=="BasePart" or c=="Part"end
 return setmetatable(p,{__index=function(_,key)if key=="Name" then return state.name end end,
  __newindex=function(t,key,value)
   if key=="Name" then
    if scenario=="partial-rename" and id=="p2head" and string.find(value,"__DistantSpectate_",1,true) then error("injected second rename failure") end
    state.name=value
   else rawset(t,key,value) end
  end})
end
local function character(children,id)
 local c={children=children}
 function c:FindFirstChild(n)for _,d in ipairs(self.children)do if d.Name==n and d.Parent==self then return d end end end
 function c:FindFirstChildOfClass(n)for _,d in ipairs(self.children)do if d.ClassName==n and d.Parent==self then return d end end end
 function c:GetDebugId()return id end
 for _,d in ipairs(children)do d.Parent=c end
 return c
end
local h1={ClassName="Humanoid",Name="Humanoid",Health=100}
local h2={ClassName="Humanoid",Name="Humanoid",Health=100}
local r1=part("HumanoidRootPart","p1root",vector(69252,303,710))
local r2=part("HumanoidRootPart","p2root",vector(69999,175,181))
local head2=part("Head","p2head",vector(69999,176,181))
local c1=character({h1,r1},"c1")
local c2=character({h2,r2,head2},"c2")
if scenario=="natural" then r2.Parent=nil end
local p1={Name="Player1",UserId=-1,Character=c1,attrs={InRound=true}}
local p2={Name="Player2",UserId=-2,Character=c2,attrs={InRound=true}}
for _,p in ipairs({p1,p2})do
 function p:GetAttribute(n)
  if scenario=="selection-error" and self==p2 and n=="SpectatorCount" and now>=3 then error("injected selected-target observation failure") end
  return self.attrs[n]
 end
end
function p1:GetAttributeChangedSignal(n)assert(n=="SpectateTargetUserId");return targetSignal end
local players={LocalPlayer=p1}
function players:FindFirstChild(n)if n=="Player1"then return p1 elseif n=="Player2"then return p2 end end
function players:GetPlayers()return {p1,p2}end
local remote={OnClientEvent=remoteSignal}
local remotes={RoundStatus=remote}
function remotes:FindFirstChild(n)if n=="RoundStatus"then return remote end end
local rs={Remotes=remotes}
function rs:FindFirstChild(n)if n=="Remotes"then return remotes end end
local map={}
local floor={}
function floor:GetFullName()return "Workspace.Level 2 Generated World.Collision.Part"end
workspace={CurrentCamera={CFrame={Position=r1.Position},CameraType=Enum.CameraType.Custom}}
function workspace:GetAttribute(n)if n=="SelectedLevel"then return 2 elseif n=="RoundActive"then return true end end
function workspace:FindFirstChild(n)if n=="Level 2 Generated World"then return map end end
function workspace:GetServerTimeNow()return now end
function workspace:Raycast()
 if scenario=="camera-error"then error("injected camera floor error") end
 if scenario=="camera-timeout"then return nil end
 return {Instance=floor,Normal=vector(0,1,0),Position=vector(69999,171.3,181)}
end
local H={}
function H:JSONDecode()return {token="offline",deathDueServerTime=3}end
function H:JSONEncode(t)return t end
local run={}
function run:IsRunning()return true end
game={PlaceId=131311258779917,GameId=10559217407,ReplicatedStorage=rs}
function game:GetService(n)
 if n=="HttpService"then return H elseif n=="Players"then return players elseif n=="RunService"then return run elseif n=="ReplicatedStorage"then return rs end
 error("Unexpected service "..n)
end
local os={clock=function()return now end}
if scenario=="late"then now=3.1 end
local delivered=false
task={}
function task.delay(seconds,fn)return {seconds=seconds,fn=fn}end
function task.cancel(handle)watchdogCancelled=true;handle.cancelled=true end
function task.wait(dt)
 now+=dt
 if now>=3 then h1.Health=0;p1.attrs.Spectating=true end
 if now>=3.05 and not delivered and scenario~="selection-timeout"then
  delivered=true
  p1.attrs.SpectateTargetUserId=-2
  targetSignal:Fire()
  remoteSignal:Fire("spectatecandidates",{Serial=1,UserIds={-2}})
  p2.attrs.SpectatorCount=1
  if scenario=="concurrent-name"then head2.Name="ConcurrentDeveloperName"end
 end
 if scenario=="natural" and now>=3.4 then r2.Parent=c2 end
 if c2:FindFirstChild("Head") and c2:FindFirstChild("HumanoidRootPart") and p1.attrs.SpectateTargetUserId==-2 then
  workspace.CurrentCamera.CFrame.Position=head2.Position
  workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
 end
 return dt
end
'''

SUFFIX = r'''
assert(activeConnections==0,"Leaked callback in "..scenario)
assert(r2.Name=="HumanoidRootPart","Root name not restored in "..scenario)
if scenario=="concurrent-name"then
 assert(head2.Name=="ConcurrentDeveloperName","Concurrent name overwritten")
 assert(not result.nameCleanup.complete and not result.complete)
else
 assert(head2.Name=="Head","Head name not restored in "..scenario)
 if scenario=="disconnect-error"then assert(not result.nameCleanup.complete)
 else assert(result.nameCleanup.complete and watchdogCancelled,"Successful cleanup must cancel watchdog")end
end
if scenario=="success"or scenario=="natural"then
 assert(result.complete and result.selectedWhileRequiredBodyMissing and result.cameraPassed)
 if scenario=="natural"then assert(not result.artificialNameAbsence and #result.renamed==0)end
else assert(not result.complete,"False success in "..scenario)end
if scenario=="late"then assert(#result.renamed==0,"Borrowed names after delayed death")end
if scenario=="camera-error"or scenario=="camera-timeout"then assert(result.selectionPassed and not result.cameraPassed)end
print("DISTANT_FIXTURE_CLEANUP="..scenario)
'''


def orchestration_tests():
    phases = [(name, getattr(driver, name)) for name in ("SERVER_MOVE", "CLIENT2_ARRIVAL", "CLIENT1_NATURAL", "SERVER_SCHEDULE", "CLIENT_FIXTURE", "SERVER_FINAL", "SERVER_RESTORE")]
    before = {"characterId": "c2", "rootId": "r2", "pivot": [0]*12, "rootPosition": [0]*3, "linearVelocity": [0]*3, "angularVelocity": [0]*3}
    for scenario in ("success", "partial-move", "arrival-error", "natural-check-error", "client-transport-error", "selection-failure", "server-final-failure", "position-conflict"):
        seen = []
        report = {}
        def call(surface, code):
            name = next(n for n, body in phases if body in code)
            seen.append(name)
            if name == "SERVER_MOVE":
                return {"ok": scenario != "partial-move", "before": before, "target": [1, 2, 3], "moveAttempted": True, "partialRestore": True}
            if name == "CLIENT2_ARRIVAL":
                return {"ok": scenario != "arrival-error"}
            if name == "CLIENT1_NATURAL":
                if scenario == "natural-check-error":
                    raise RuntimeError("injected pre-death check error")
                return {"rootPresent": True}
            if name == "SERVER_SCHEDULE":
                return {"scheduled": True, "deathDueServerTime": 3}
            if name == "CLIENT_FIXTURE":
                if scenario == "client-transport-error":
                    raise RuntimeError("injected transport loss")
                return {"complete": scenario != "selection-failure", "nameCleanup": {"complete": True}}
            if name == "SERVER_FINAL":
                return {"ok": scenario != "server-final-failure"}
            if name == "SERVER_RESTORE":
                if scenario == "position-conflict":
                    raise RuntimeError("preserve concurrently moved target")
                return {"restored": True}
            raise AssertionError(name)
        complete = driver.exercise(call, {"token": "offline"}, report, lambda: None)
        assert complete == (scenario == "success"), (scenario, report)
        if scenario != "partial-move":
            assert seen[-1] == "SERVER_RESTORE", (scenario, seen)
        if scenario in ("partial-move", "arrival-error", "natural-check-error"):
            assert "SERVER_SCHEDULE" not in seen, (scenario, seen)
        if scenario == "client-transport-error":
            assert report["nameCleanupOutcomeUnknown"] and not report["nameCleanupVerified"]
        if scenario == "position-conflict":
            assert not report["targetPositionCleanup"]["restored"]
    return 8


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path, required=True)
    parser.add_argument("--compiler", type=Path)
    args = parser.parse_args()
    for text in (driver.SERVER_MOVE, driver.SERVER_SCHEDULE, driver.CLIENT_FIXTURE, driver.SERVER_RESTORE):
        assert "Instance.new" not in text and "UpdateSourceAsync" not in text and "FireServer" not in text and "AddReplicationFocus" not in text
    assert "FindFirstChildOfClass(\"Humanoid\")" in driver.GUARD
    temp_root = driver.ROOT / "_local/optimization-20261009/distant-spectate-offline"
    temp_root.mkdir(parents=True, exist_ok=True)
    scenarios = ("success", "natural", "partial-rename", "selection-timeout", "selection-error", "connect-error", "camera-error", "camera-timeout", "concurrent-name", "disconnect-error", "late")
    with tempfile.TemporaryDirectory(prefix="run-", dir=temp_root) as directory:
        folder = Path(directory).resolve()
        folder.relative_to(temp_root.resolve())  # verify bounded target before recursive cleanup
        for scenario in scenarios:
            payload = PRELUDE.replace("__SCENARIO__", json.dumps(scenario)) + "\nlocal result=(function()\n" + driver.source(driver.CLIENT_FIXTURE, {}) + "\nend)()\n" + SUFFIX
            path = folder / (scenario + ".luau")
            path.write_text(payload, encoding="utf-8")
            result = subprocess.run([str(args.luau), str(path)], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, (scenario, result.stdout, result.stderr)
            assert "DISTANT_FIXTURE_CLEANUP=" + scenario in result.stdout
        if args.compiler:
            for index, body in enumerate((driver.SERVER_MOVE, driver.CLIENT2_ARRIVAL, driver.CLIENT1_NATURAL, driver.SERVER_SCHEDULE, driver.CLIENT_FIXTURE, driver.SERVER_FINAL, driver.SERVER_RESTORE)):
                path = folder / ("compile-" + str(index) + ".luau")
                path.write_text(driver.source(body, {}), encoding="utf-8")
                result = subprocess.run([str(args.compiler), str(path)], capture_output=True, text=True, timeout=10)
                assert result.returncode == 0, (index, result.stderr)
    orchestrated = orchestration_tests()
    print(json.dumps({"offlineOnly": True, "studioExecution": False, "generatedClientCleanupScenarios": len(scenarios), "orchestrationFailureScenarios": orchestrated, "allSevenPayloadsCompiled": args.compiler is not None, "gameplayOrStreamingPass": False}))


if __name__ == "__main__":
    main()
