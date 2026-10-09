"""Root local-Play floor/LOD smoke at three actual decks; restore test position."""
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
assert(workspace:GetAttribute("Level6InUse")==true)
local m=assert(workspace:FindFirstChild("Level 6 Indoor Playground"))
local p=game.Players.Player1
assert(p and p:GetAttribute("InRound")==true and p.Character.Humanoid.Health>0)
'''
SITES=[('lower',[52051.555,110,0]),('middle',[51978.344,150,-80.824]),('upper',[52085.852,230,23.004])]
def main():
 c=StudioMcpClient(find_mcp_batch());before=None
 report={'kind':'actual-two-client-l6-deck-smoke','startedUtc':datetime.now(timezone.utc).isoformat(),'editMutation':False,'testRelocation':True,'fullUnassistedWalkthrough':False,'steps':[]}
 def call(dm,code):return json.loads(c.call('execute_luau',{'studio_id':SERVER if dm=='Server' else CLIENT,'datamodel_type':dm,'code':GUARD+code}))
 try:
  c.initialize()
  before=call('Server','''return H:JSONEncode({characterId=p.Character:GetDebugId(0),pivot={p.Character:GetPivot():GetComponents()}})''');report['before']=before
  for name,coords in SITES:
   moved=call('Server','''local folders={}
for _,d in ipairs(m:GetDescendants()) do if d.Name=="Frame_Decks" or d.Name=="Frame_DecksDeep" then table.insert(folders,d) end end
assert(#folders==2)
local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances=folders;rp.RespectCanCollide=true
local origin=Vector3.new(%s)
local hit=workspace:Raycast(origin,Vector3.new(0,-30,0),rp)
assert(hit and hit.Normal.Y>.9 and hit.Instance:IsA("UnionOperation"),"No safe actual union deck")
assert(hit.Instance.RenderFidelity==Enum.RenderFidelity.Automatic and hit.Instance.CollisionFidelity==Enum.CollisionFidelity.Hull)
local target=hit.Position+Vector3.new(0,4,0);p:RequestStreamAroundAsync(target,5)
local body=p.Character.HumanoidRootPart
p.Character:PivotTo(CFrame.new(target)*body.CFrame:ToObjectSpace(p.Character:GetPivot()));body.AssemblyLinearVelocity=Vector3.zero
return H:JSONEncode({deck=hit.Instance:GetFullName(),class=hit.Instance.ClassName,fidelity=hit.Instance.RenderFidelity.Name,collision=hit.Instance.CollisionFidelity.Name,floor={hit.Position.X,hit.Position.Y,hit.Position.Z},target={target.X,target.Y,target.Z}})'''%','.join(map(str,coords)))
   client=call('Client','''task.wait(.7)
local body=p.Character.HumanoidRootPart.Position
local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={m};rp.RespectCanCollide=true
local hit=workspace:Raycast(body+Vector3.new(0,2,0),Vector3.new(0,-18,0),rp)
assert(hit and hit.Normal.Y>.9,"Actual contacted client floor is absent")
return H:JSONEncode({position={body.X,body.Y,body.Z},health=p.Character.Humanoid.Health,floor=hit.Instance:GetFullName(),floorClass=hit.Instance.ClassName,fidelity=hit.Instance:IsA("UnionOperation") and hit.Instance.RenderFidelity.Name,collision=hit.Instance:IsA("UnionOperation") and hit.Instance.CollisionFidelity.Name,camera={workspace.CurrentCamera.CFrame:GetComponents()}})''')
   assert client['health']>0 and client.get('fidelity')=='Automatic' and client.get('collision')=='Hull',client
   assert abs(client['position'][1]-moved['floor'][1])<6,client
   report['steps'].append({'site':name,'server':moved,'client':client})
   print(name,client['floorClass'],client['fidelity'],client['collision'],client['health'],flush=True)
  report['complete']=True
 except Exception as e:
  report['complete']=False;report['error']=str(e);raise
 finally:
  if before:
   try:
    restored=call('Server','''local before=H:JSONDecode(%s)
assert(p.Character:GetDebugId(0)==before.characterId,"Character changed; preserve round-owned character")
p.Character:PivotTo(CFrame.new(table.unpack(before.pivot)))
p.Character.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
return H:JSONEncode({restored=true})'''%json.dumps(json.dumps(before)))
    report['testPositionRestored']=restored['restored']
   except Exception as e:report['cleanupError']=str(e)
  report['finishedUtc']=datetime.now(timezone.utc).isoformat()
  (ROOT/'tools/optimization_20261009/runtime/observations/level6-deck-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
  c.close()
if __name__=='__main__':main()
