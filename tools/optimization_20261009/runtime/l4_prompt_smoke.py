"""Root-owned local multiplayer smoke: real note/switch prompts, safe test relocation.

No Edit writes, source edits, objective/Director calls or progress attribute writes.
This checks actual normal prompt handlers; it is not a complete player walkthrough.
"""
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch

SERVER = "4f7d4c8a-1135-4131-9e84-3d8f932b343e"
CLIENT = "85592f54-3adf-4795-8f22-48b0ab3f8286"
GUARD = '''assert(game:GetService("RunService"):IsRunning(),"Actual Play required")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
assert(workspace:GetAttribute("SelectedLevel")==4 and workspace:GetAttribute("Level4RoundActive")==true)
local H=game:GetService("HttpService")
local m=assert(workspace:FindFirstChild("Level 4 Cinema Blender"))
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--resume',action='store_true');args=parser.parse_args()
    c = StudioMcpClient(find_mcp_batch())
    report = {"kind":"actual-multiplayer-normal-prompt-smoke", "startedUtc":datetime.now(timezone.utc).isoformat(),
              "testRelocation":True, "fullWalkthrough":False, "editMutation":False, "steps":[]}
    output = ROOT / ("tools/optimization_20261009/runtime/observations/level4-prompts-resume.json" if args.resume else "tools/optimization_20261009/runtime/observations/level4-prompts.json")
    def call(dm, code):
        raw = c.call("execute_luau", {"studio_id":SERVER if dm=="Server" else CLIENT,"datamodel_type":dm,"code":GUARD+code})
        return json.loads(raw)
    try:
        c.initialize()
        info=call("Server", '''local note=m["Level 4 Round Runtime"].L4Note
local text
for _,d in ipairs(note:GetDescendants()) do if d:IsA("TextLabel") then text=d.Text end end
assert(type(text)=="string")
local keys={};for k in string.gmatch(text,"[AB][123]") do table.insert(keys,k) end
assert(#keys==4)
return H:JSONEncode({text=text,sequence=keys,progress=game.ReplicatedStorage["Level 4 State"]:GetAttribute("Level4_SequenceProgress"),power=game.ReplicatedStorage["Level 4 State"]:GetAttribute("Level4_PowerState")})''')
        report["baseline"]=info
        assert args.resume or info['progress']==0
        for name in (info["sequence"][info['progress']:] if args.resume else ["Note"]+info["sequence"]):
            selector='d.ObjectText=="Note"' if name=="Note" else 'd.ObjectText=='+json.dumps("Switch "+name)
            find='''local prompt
for _,d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") and %s then assert(not prompt);prompt=d end end
assert(prompt and prompt.Enabled)
local goal=prompt.Parent.WorldPosition
''' % selector
            move=call("Server", find+'''local p=game.Players.Player1
assert(p:GetAttribute("InRound")==true and p.Character.Humanoid.Health>0)
local body=p.Character.HumanoidRootPart
assert(body:GetNetworkOwnershipAuto() or body:GetNetworkOwner()==nil,"Unexpected borrowed network ownership")
body:SetNetworkOwner(nil)
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
params.FilterDescendantsInstances={m.Collision};params.RespectCanCollide=true
local overlaps=OverlapParams.new();overlaps.FilterType=Enum.RaycastFilterType.Include
overlaps.FilterDescendantsInstances={m};overlaps.RespectCanCollide=true
local hit,target
for _,offset in ipairs({Vector3.new(0,0,-5),Vector3.new(0,0,5),Vector3.new(-3,0,0),Vector3.new(3,0,0),Vector3.new(0,0,-3)}) do
 local candidate=workspace:Raycast(goal+offset+Vector3.new(0,2,0),Vector3.new(0,-16,0),params)
 if candidate and candidate.Normal.Y>.9 then
  local position=candidate.Position+Vector3.new(0,3,0)
  if (position-goal).Magnitude<prompt.MaxActivationDistance and #workspace:GetPartBoundsInBox(CFrame.new(position),Vector3.new(2,4,2),overlaps)==0 then hit,target=candidate,position;break end
 end
end
assert(hit and target,"No safe unoccupied actual collision floor near prompt")
p:RequestStreamAroundAsync(target,5)
local rootTarget=CFrame.new(target,Vector3.new(goal.X,target.Y,goal.Z))
p.Character:PivotTo(rootTarget * body.CFrame:ToObjectSpace(p.Character:GetPivot()))
p.Character.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
task.wait(.3)
return H:JSONEncode({prompt=prompt:GetFullName(),floor=hit.Instance:GetFullName(),target={target.X,target.Y,target.Z}})''')
            # Wait for the actual streamed prompt and replicated body, never create it.
            fired=call("Client", '''local p=game.Players.LocalPlayer;assert(p.Name=="Player1")
local untilTime=os.clock()+5
local prompt
repeat
 for _,d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") and %s then prompt=d;break end end
 if not prompt then task.wait(.1) end
until prompt or os.clock()>untilTime
assert(prompt and prompt.Enabled,"Prompt did not stream")
task.wait(.3)
assert((p.Character.HumanoidRootPart.Position-prompt.Parent.WorldPosition).Magnitude<=prompt.MaxActivationDistance)
local ok,problem=xpcall(function() prompt:InputHoldBegin();task.wait(.12) end,debug.traceback)
prompt:InputHoldEnd()
assert(ok,problem);task.wait(.3)
return H:JSONEncode({prompt=prompt:GetFullName(),distance=(p.Character.HumanoidRootPart.Position-prompt.Parent.WorldPosition).Magnitude})''' % selector)
            state=call("Server", '''return H:JSONEncode(game.ReplicatedStorage["Level 4 State"]:GetAttributes())''')
            if name!="Note":
                assert state["Level4_SequenceProgress"]==info["sequence"].index(name)+1, state
            report["steps"].append({"name":name,"relocation":move,"clientInput":fired,"serverState":state})
            print(name, state["Level4_SequenceProgress"], state["Level4_PowerState"], flush=True)
        report["complete"]=True
    except Exception as error:
        report["complete"]=False;report["error"]=str(error)
        raise
    finally:
        try:
            report['ownershipRestored']=call('Server', '''local p=game.Players.Player1
local body=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if body then body:SetNetworkOwnershipAuto();assert(body:GetNetworkOwnershipAuto()) end
return H:JSONEncode({automatic=body~=nil})''')
        except Exception as cleanup:
            report['ownershipRestoreError']=str(cleanup)
        report["finishedUtc"]=datetime.now(timezone.utc).isoformat()
        output.write_text(json.dumps(report,indent=2)+"\n")
        c.close()

if __name__=="__main__":main()
