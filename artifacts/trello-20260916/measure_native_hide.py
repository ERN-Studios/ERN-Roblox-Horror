"""Measure actual-character geometry during a whole native uploaded hold loop."""
import json,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio
vertices=(ROOT/'_local/trello-20260916/character-export/native-hulls.json').read_text()
code=r'''
local raw=game.HttpService:JSONDecode([===[VERTICES]===])
local player=game.Players.LocalPlayer
assert(player:GetAttribute('Level3_Hiding')==true,'Enter a real hiding place first')
local c=player.Character;local root=c.HumanoidRootPart
local parts={};for name,points in pairs(raw) do
 local part=c:FindFirstChild(name,true);assert(part,name)
 local vs={};for _,v in ipairs(points) do table.insert(vs,Vector3.new(v[1],v[2],v[3])) end
 table.insert(parts,{part,vs})
end
local track;for _,t in ipairs(c.Humanoid.Animator:GetPlayingAnimationTracks()) do if t.Animation.AnimationId=='rbxassetid://119040885264927' then track=t end end
assert(track and track.Length==4 and track.WeightCurrent>.99,'Uploaded track not ready')
local initial=root.CFrame;local started=os.clock();local minY=1e9;local maxY=-1e9;local maxX=0;local maxZ=0;local drift=0;local samples=0
repeat
 game:GetService('RunService').Heartbeat:Wait()
 assert(player:GetAttribute('Level3_Hiding')==true,'Hiding interrupted')
 assert(track.IsPlaying and track.WeightCurrent>.99,'Track lost')
 samples+=1;drift=math.max(drift,(root.Position-initial.Position).Magnitude)
 for _,record in ipairs(parts) do local cf=root.CFrame:ToObjectSpace(record[1].CFrame)
  for _,v in ipairs(record[2]) do local p=cf:PointToWorldSpace(v)
   minY=math.min(minY,p.Y);maxY=math.max(maxY,p.Y);maxX=math.max(maxX,math.abs(p.X));maxZ=math.max(maxZ,math.abs(p.Z))
  end
 end
until os.clock()-started>=4.2
return game.HttpService:JSONEncode({asset=119040885264927,seconds=os.clock()-started,samples=samples,meshParts=#parts,floorClearance=minY+2.2,tableClearance=.56-maxY,maxLaneX=maxX,maxDepth=maxZ,rootDrift=drift,trackLength=track.Length,trackWeight=track.WeightCurrent,priority=tostring(track.Priority),hidden=player:GetAttribute('Level3_Hiding')})
'''.replace('VERTICES',vertices)
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();time.sleep(2);select_studio(client,'BACKROOMS: STAY QUIET [CO-OP HORROR]',20)
 result=client.call('execute_luau',{'datamodel_type':'Client','code':code})
 report=json.loads(result)
 (Path(__file__).parent/'animation-native-loop.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report))
finally:client.close()
