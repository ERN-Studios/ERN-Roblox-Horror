"""One-line generated L2 root correction and full-controller regression fixtures."""
from pathlib import Path
import difflib
import hashlib
import json
import os
import re
import subprocess

HERE = Path(__file__).resolve().parent
RELATIVE = "tools/optimization_20261009/loading/install/compatibility/l2-root-fix/"


def main():
    before = (HERE / "SceneEffectBudgetClient.before.luau").read_bytes()
    after = (HERE / "SceneEffectBudgetClient.proposed.luau").read_bytes()
    capture = json.loads((HERE / "baseline-capture.json").read_text(encoding="utf-8"))
    wrong, correct = b'["Level2PoolroomsMap"] =', b'["Level 2 Generated World"] ='
    assert len(before) == capture["bytes"] == 3532 and capture["editorParity"]
    assert before.count(wrong) == 1 and before.replace(wrong,correct,1) == after
    assert len(after) == len(before)+len(correct)-len(wrong)
    sha = lambda raw:hashlib.sha256(raw).hexdigest()
    manifest = {"placeId":131311258779917,"universeId":10559217407,
        "status":"Prepared one-line fix against fresh authoritative Edit source; root applies CAS",
        "scripts":[{"segments":["StarterPlayer","StarterPlayerScripts","SceneEffectBudgetClient"],
            "class":"LocalScript","baselineInstanceId":capture["instanceId"],
            "beforeFile":RELATIVE+"SceneEffectBudgetClient.before.luau","beforeSha256":sha(before),"beforeBytes":len(before),
            "afterFile":RELATIVE+"SceneEffectBudgetClient.proposed.luau","afterSha256":sha(after),"afterBytes":len(after)}]}
    (HERE / "source-install-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    diff = "".join(difflib.unified_diff(before.decode().splitlines(keepends=True),after.decode().splitlines(keepends=True),
        fromfile="SceneEffectBudgetClient.before.luau",tofile="SceneEffectBudgetClient.proposed.luau"))
    (HERE / "SceneEffectBudgetClient.patch.diff").write_bytes(diff.encode())
    preamble = '''return function()
local checks = 0
local function check(condition,message) assert(condition,message);checks+=1 end
local function signal()
 local records={}
 return {
  Connect=function(_,callback)
   local c={Connected=true,Callback=callback}
   function c:Disconnect() self.Connected=false end
   table.insert(records,c);return c
  end,
  Fire=function(_,...) for _,c in ipairs(table.clone(records)) do if c.Connected then c.Callback(...) end end end,
  Count=function() local count=0;for _,c in ipairs(records) do if c.Connected then count+=1 end end;return count end,
 }
end
local workspace={Children={},Attributes={},ChildAdded=signal(),ChildRemoved=signal(),CurrentCamera={CFrame={Position="camera"}}}
function workspace:GetChildren() return table.clone(self.Children) end
function workspace:GetAttribute(key) return self.Attributes[key] end
local function model(name,parent)
 local m={Name=name,Parent=parent}
 function m:IsA(class) return class=="Model" end
 return m
end
local function arrive(m)
 m.Parent=workspace;table.insert(workspace.Children,m);workspace.ChildAdded:Fire(m)
end
local function depart(m)
 local index=table.find(workspace.Children,m);if index then table.remove(workspace.Children,index) end
 m.Parent=nil;workspace.ChildRemoved:Fire(m)
end
local initial=model("Level 2 Generated World",workspace)
table.insert(workspace.Children,initial)
local oldTemplate=model("Level2PoolroomsMap",workspace)
table.insert(workspace.Children,oldTemplate)
local created={}
local Budget={new=function(root,options)
 local session={Root=root,Options=options,Destroyed=0,Steps=0}
 function session:Destroy() self.Destroyed+=1 end
 function session:Step(views) self.Steps+=1;self.LastViews=views end
 table.insert(created,session);return session
end}
local module={}
local ReplicatedStorage={WaitForChild=function(_,name,timeout) assert(name=="SceneEffectBudget" and timeout==30);return module end}
local require=function(value) assert(value==module);return Budget end
local Character={FindFirstChild=function(_,name) assert(name=="HumanoidRootPart");return {Position="body"} end}
local Players={LocalPlayer={Character=Character}}
local RunService={Heartbeat=signal()}
local services={Players=Players,ReplicatedStorage=ReplicatedStorage,RunService=RunService}
local game={GetService=function(_,name) return assert(services[name]) end}
local script={Enabled=true,Destroying=signal(),EnabledChanged=signal()}
function script:GetPropertyChangedSignal(name) assert(name=="Enabled");return self.EnabledChanged end
local debug={traceback=debug.traceback,profilebegin=function() end,profileend=function() end}
local warnings={}
local function warn(message) table.insert(warnings,message) end
(function()
'''
    tail = '''
end)()
check(#created==1 and created[1].Root==initial,"generated runtime world bound")
check(created[1].Options.ScanRoots[1]=="Water FX" and #created[1].Options.ScanRoots==1,"actual Water FX subtree selected")
check(created[1].Options.ActiveDistance==320 and created[1].Options.Hysteresis==48 and created[1].Options.CellSize==128,"L2 authored budget retained")
workspace.ChildAdded:Fire(initial)
check(#created==1,"duplicate discovery stays bounded")
local foreign=model("Level 2 Generated World",{})
workspace.ChildAdded:Fire(foreign)
check(#created==1,"non-Workspace world rejected")
local l6=model("Level 6 Indoor Playground",workspace)
workspace.ChildAdded:Fire(l6)
check(#created==1,"existing L6 exemption retained")
RunService.Heartbeat:Fire(0.24)
check(created[1].Steps==0,"existing cadence retained")
RunService.Heartbeat:Fire(0.01)
check(created[1].Steps==1 and #created[1].LastViews==2 and created[1].LastViews[1]=="camera" and created[1].LastViews[2]=="body","camera and body views retained")
local l4=model("Level 4 Cinema Blender")
local l5=model("Level 5 Void")
arrive(l4);arrive(l5)
check(#created==3 and created[2].Options.ScanRoots[1]=="Lights" and created[2].Options.ScanRoots[2]=="Props","L4 configuration retained")
check(created[3].Options.ActiveDistance==384 and created[3].Options.Hysteresis==64 and created[3].Options.ScanRoots[1]=="Lights","L5 configuration retained")
depart(initial)
check(created[1].Destroyed==1,"stream-out root releases session")
RunService.Heartbeat:Fire(0.25)
check(created[1].Steps==1,"removed root no longer stepped")
local returning=model("Level 2 Generated World")
arrive(returning)
check(#created==4 and created[4].Root==returning,"returning runtime root obtains fresh session")
workspace.Attributes.SceneEffectBudgetDisabled=true
RunService.Heartbeat:Fire(0.25)
check(created[2].Destroyed==1 and created[3].Destroyed==1 and created[4].Destroyed==1,"disable restores/releases all sessions")
depart(returning)
local returned=model("Level 2 Generated World")
arrive(returned)
check(#created==4,"disabled root arrival remains suspended")
workspace.Attributes.SceneEffectBudgetDisabled=false
RunService.Heartbeat:Fire(0.25)
check(#created==7 and created[7].Root==returned and created[7].Steps==1,"reenable rediscovers actual generated world")
Players.LocalPlayer.Character=nil;workspace.CurrentCamera=nil
RunService.Heartbeat:Fire(0.25)
check(#created[7].LastViews==0 and #warnings==0,"temporarily missing views stand down without errors")
script.Destroying:Fire()
check(created[5].Destroyed==1 and created[6].Destroyed==1 and created[7].Destroyed==1,"script cleanup releases sessions")
check(workspace.ChildAdded.Count()==0 and workspace.ChildRemoved.Count()==0 and RunService.Heartbeat.Count()==0 and script.Destroying.Count()==0 and script.EnabledChanged.Count()==0,"cleanup disconnects all owners")
arrive(model("Level 2 Generated World"));RunService.Heartbeat:Fire(0.25);script.Destroying:Fire()
check(#created==7 and created[7].Destroyed==1,"post-cleanup events cannot leak another session")
return {checks=checks,realGameplayStreamingPerformancePass=false}
end
'''
    fixture = preamble + after.decode() + tail
    (HERE / "native-controller-contract-probe.luau").write_bytes(fixture.encode())
    for label, source in (("before",before),("after",after)):
        runnable = "local run=(function()\n"+preamble+source.decode()+tail+"\nend)()\nlocal result=run()\nprint('L2_ROOT_FIX_CHECKS='..result.checks)\n"
        (HERE / f"controller-{label}-contract.luau").write_bytes(runnable.encode())
    compiler = str(Path(os.environ["LUAU_BIN"]).with_name("luau-compile.exe"))
    for filename in ("SceneEffectBudgetClient.proposed.luau","native-controller-contract-probe.luau","controller-after-contract.luau"):
        result=subprocess.run([compiler,str(HERE/filename)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    original=subprocess.run([os.environ["LUAU_BIN"],str(HERE/"controller-before-contract.luau")],capture_output=True,text=True)
    assert original.returncode!=0 and "generated runtime world bound" in original.stderr,original.stdout+original.stderr
    proposed=subprocess.run([os.environ["LUAU_BIN"],str(HERE/"controller-after-contract.luau")],capture_output=True,text=True)
    assert proposed.returncode==0,proposed.stdout+proposed.stderr
    match=re.search(r"L2_ROOT_FIX_CHECKS=(\d+)",proposed.stdout);assert match
    receipt={"source_sha256":sha(after),"before_sha256":sha(before),"oneLineOnly":True,
        "compiled":True,"controllerChecks":int(match[1]),"beforeRegressionConfirmed":True,
        "nativeExecuted":False,"gameplayStreamingPerformancePass":False}
    (HERE/"offline-result.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(receipt,indent=2))


if __name__=="__main__":main()
