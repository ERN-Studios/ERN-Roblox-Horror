"""Fresh two-client L2 controller near/far test; borrowed stream focus always removed."""
from datetime import datetime,timezone
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch
SERVER='9d580216-35c6-42af-b4ed-6f9bcd271304'
CLIENT='797b67e1-6765-4c02-b2d0-f0b025bfcac1'
GUARD='''local H=game:GetService("HttpService")
assert(game:GetService("RunService"):IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407)
assert(workspace:GetAttribute("SelectedLevel")==2 and workspace:GetAttribute("RoundActive")==true)
local m=assert(workspace:FindFirstChild("Level 2 Generated World"))
local p=game.Players.Player1
assert(p and p:GetAttribute("InRound")==true and p.Character.Humanoid.Health>0)
'''
OBSERVE='''task.wait(.6)
local cam=workspace.CurrentCamera.CFrame.Position;local body=p.Character.HumanoidRootPart.Position
local fx=m:FindFirstChild("Water FX");local out={}
if fx then for _,d in ipairs(fx:GetDescendants()) do if d:IsA("ParticleEmitter") then
 local parent=d.Parent;local position=parent:IsA("Attachment") and parent.WorldPosition or parent.Position
 table.insert(out,{path=d:GetFullName(),enabled=d.Enabled,wanted=d:GetAttribute("SceneBudgetWantedEnabled"),influence=d:GetAttribute("SceneBudgetInfluenceRadius"),distance=math.min((position-body).Magnitude,(position-cam).Magnitude)})
end end end
return H:JSONEncode({root={body.X,body.Y,body.Z},camera={cam.X,cam.Y,cam.Z},fx=out,mapDesc=#m:GetDescendants()})
'''
def main():
 c=StudioMcpClient(find_mcp_batch());added=False
 report={'kind':'fresh-actual-two-client-l2-budget-binding-smoke','startedUtc':datetime.now(timezone.utc).isoformat(),'editMutation':False,'testRelocation':True,'temporaryExtraFocus':True,'steps':[]}
 def call(dm,code):return json.loads(c.call('execute_luau',{'studio_id':SERVER if dm=='Server' else CLIENT,'datamodel_type':dm,'code':GUARD+code}))
 try:
  c.initialize()
  near=call('Client',OBSERVE);report['steps'].append({'label':'near-waterfall','client':near})
  assert len(near['fx'])==8 and all(r['wanted'] and r['enabled'] and r['distance']<352 for r in near['fx'])
  call('Server','''p:AddReplicationFocus(m.Markers.P2_01);return H:JSONEncode({added=true})''');added=True
  relocation=call('Server','''local goal=game.Players.Player2.Character.HumanoidRootPart.Position-Vector3.new(4,0,0)
local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={m.Collision};rp.RespectCanCollide=true
local hit=workspace:Raycast(goal+Vector3.new(0,3,0),Vector3.new(0,-20,0),rp)
assert(hit and hit.Normal.Y>.9)
local target=hit.Position+Vector3.new(0,3,0);p:RequestStreamAroundAsync(target,5)
local body=p.Character.HumanoidRootPart
p.Character:PivotTo(CFrame.new(target)*body.CFrame:ToObjectSpace(p.Character:GetPivot()));body.AssemblyLinearVelocity=Vector3.zero
return H:JSONEncode({floor=hit.Instance:GetFullName(),target={target.X,target.Y,target.Z}})''')
  far=call('Client',OBSERVE);report['steps'].append({'label':'far-region-retained-for-controller-check','relocation':relocation,'client':far})
  assert len(far['fx'])==8 and all(r['wanted'] and not r['enabled'] and r['distance']>400 for r in far['fx']),far
  report['complete']=True
  print('Fresh actual L2: 8 near Water FX on; all 8 retained far FX locally off with server wanted=true')
 except Exception as e:
  report['complete']=False;report['error']=str(e);raise
 finally:
  if added:
   try:report['extraFocusRemoved']=call('Server','''p:RemoveReplicationFocus(m.Markers.P2_01);return H:JSONEncode({removed=true})''')['removed']
   except Exception as e:report['cleanupError']=str(e)
  report['finishedUtc']=datetime.now(timezone.utc).isoformat()
  (ROOT/'tools/optimization_20261009/runtime/observations/level2-fresh-budget-binding.json').write_text(json.dumps(report,indent=2)+'\n')
  c.close()
if __name__=='__main__':main()
