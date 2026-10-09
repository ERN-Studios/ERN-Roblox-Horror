"""Root local-Play control pass on real existing L4 lights; restore borrowed states."""
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch
SERVER='4f7d4c8a-1135-4131-9e84-3d8f932b343e'
CLIENT='85592f54-3adf-4795-8f22-48b0ab3f8286'
PATHS=[
 ['Workspace','Level 4 Cinema Blender','Props','FlickerLens','L4C_L_Concourse_f0','PointLight'],
 ['Workspace','Level 4 Cinema Blender','Props','NeonFlicker','L4D_fl_acove_3589_13','PointLight'],
]
FIND='''local H=game:GetService("HttpService")
assert(game:GetService("RunService"):IsRunning())
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
assert(workspace:GetAttribute("SelectedLevel")==4 and workspace:GetAttribute("Level4RoundActive"))
local nodes={}
for _,segs in ipairs(H:JSONDecode(%s)) do
 local candidates={game}
 for _,seg in ipairs(segs) do
  local matched={}
  for _,n in ipairs(candidates) do for _,d in ipairs(n:GetChildren()) do if d.Name==seg then table.insert(matched,d) end end end
  assert(#matched>0,"Missing existing light segment "..seg);candidates=matched
 end
 assert(#candidates==1,"Ambiguous complete light identity");local n=candidates[1]
 assert(n:IsA("Light") and type(n:GetAttribute("SceneBudgetWantedEnabled"))=="boolean")
 table.insert(nodes,n)
end
'''%json.dumps(json.dumps(PATHS))

def main():
 c=StudioMcpClient(find_mcp_batch()); before=None
 report={'startedUtc':datetime.now(timezone.utc).isoformat(),'kind':'actual-client-budget-controlled-light-smoke','normalPowerObjectivePassed':False,'editMutation':False,'steps':[]}
 def call(dm,code):
  return json.loads(c.call('execute_luau',{'studio_id':SERVER if dm=='Server' else CLIENT,'datamodel_type':dm,'code':FIND+code}))
 def observe(label):
  server=call('Server','''local out={};for _,d in ipairs(nodes) do table.insert(out,{path=d:GetFullName(),id=d:GetDebugId(0),wanted=d:GetAttribute("SceneBudgetWantedEnabled"),enabled=d.Enabled}) end return H:JSONEncode(out)''')
  client=call('Client','''task.wait(.6)
local r=game.Players.LocalPlayer.Character.HumanoidRootPart.Position;local cam=workspace.CurrentCamera.CFrame.Position
local out={};for _,d in ipairs(nodes) do local p=d.Parent.Position
 table.insert(out,{path=d:GetFullName(),wanted=d:GetAttribute("SceneBudgetWantedEnabled"),enabled=d.Enabled,distance=math.min((p-r).Magnitude,(p-cam).Magnitude),range=d.Range}) end
return H:JSONEncode({lights=out,disabled=workspace:GetAttribute("SceneEffectBudgetDisabled")==true})''')
  report['steps'].append({'label':label,'server':server,'client':client})
  return client['lights']
 try:
  c.initialize()
  before=call('Server','''local out={};for _,d in ipairs(nodes) do table.insert(out,{id=d:GetDebugId(0),wanted=d:GetAttribute("SceneBudgetWantedEnabled"),enabled=d.Enabled}) end return H:JSONEncode(out)''')
  report['before']=before
  assert all(r['wanted'] is False and r['enabled'] is False for r in before)
  call('Server','''for _,d in ipairs(nodes) do d:SetAttribute("SceneBudgetWantedEnabled",true);d.Enabled=true end return H:JSONEncode({done=true})''')
  lights=observe('authoritative-on')
  assert lights[0]['wanted'] and lights[0]['enabled'],lights
  assert lights[1]['wanted'] and not lights[1]['enabled'] and lights[1]['distance']>368+lights[1]['range'],lights
  call('Client','''assert(workspace:GetAttribute("SceneEffectBudgetDisabled")==nil)
workspace:SetAttribute("SceneEffectBudgetDisabled",true);return H:JSONEncode({done=true})''')
  assert all(r['enabled'] and r['wanted'] for r in observe('local-budget-disabled-restores-authority'))
  call('Client','''workspace:SetAttribute("SceneEffectBudgetDisabled",nil);return H:JSONEncode({done=true})''')
  assert not observe('budget-reenabled')[1]['enabled']
  call('Server','''for _,d in ipairs(nodes) do d:SetAttribute("SceneBudgetWantedEnabled",false);d.Enabled=false end return H:JSONEncode({done=true})''')
  assert all(not r['wanted'] and not r['enabled'] for r in observe('authoritative-off-while-locally-suppressed'))
  report['complete']=True
  print('Actual controller: near on, far suppressed, disable restores, re-enable suppresses, authority off retained')
 except Exception as e:
  report['complete']=False;report['error']=str(e);raise
 finally:
  try:
   call('Client','''workspace:SetAttribute("SceneEffectBudgetDisabled",nil);return H:JSONEncode({restored=true})''')
   if before:
    baseline=json.dumps(json.dumps(before))
    restored=call('Server','''local before=H:JSONDecode(%s)
for i,d in ipairs(nodes) do assert(d:GetDebugId(0)==before[i].id) end
for i,d in ipairs(nodes) do d:SetAttribute("SceneBudgetWantedEnabled",before[i].wanted);d.Enabled=before[i].enabled end
return H:JSONEncode({restored=true})'''%baseline)
    report['borrowedStateRestored']=restored['restored']
  except Exception as e:report['cleanupError']=str(e)
  report['finishedUtc']=datetime.now(timezone.utc).isoformat()
  (ROOT/'tools/optimization_20261009/runtime/observations/level4-budget-controlled.json').write_text(json.dumps(report,indent=2)+'\n')
  c.close()
if __name__=='__main__':main()
