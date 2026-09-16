"""Publish only the Blender-authored table-hiding clip in a coordinated Edit window.

Does not change live animation config. Never run until the Studio driver has
handed over a stable Edit session. Returned asset ownership/id must be verified.
"""
from pathlib import Path
import json
import sys
import time
import argparse
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/animations/table-hiding'

def source(payload, asset_name="Zyntra Table Hide Hold v1"):
    return '''local H=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
assert(game.PlaceId==131311258779917,"Unexpected place")
assert(game.CreatorType==Enum.CreatorType.Group and game.CreatorId==1039373905,"Unexpected animation owner")
local data=H:JSONDecode([===[PAYLOAD]===])
local sequence=Instance.new("KeyframeSequence")
sequence.Name=data.name
sequence.Loop=true
sequence.Priority=Enum.AnimationPriority.Action
for _,frameData in data.frames do
 local frame=Instance.new("Keyframe")
 frame.Time=frameData[1]
 local poses={}
 for _,v in frameData[2] do
  local p=Instance.new("Pose")
  p.Name=v[1];p.CFrame=CFrame.new(v[2],v[3],v[4],v[5],v[6],v[7],v[8]);p.Weight=1
  p.EasingStyle=Enum.PoseEasingStyle.Linear;p.EasingDirection=Enum.PoseEasingDirection.InOut
  poses[p.Name]=p
 end
 for name,p in poses do
  local parent=data.parents[name]
  p.Parent=parent and poses[parent] or frame
 end
 frame.Parent=sequence
end
local status,id=AssetService:CreateAssetAsync(sequence,Enum.AssetType.Animation,{
 Name=ASSET_NAME,
 Description="Four-second R15 table-hiding hold, authored and baked in Blender from the game rig",
 CreatorId=1039373905,CreatorType=Enum.AssetCreatorType.Group,
})
local result={status=tostring(status),id=tostring(id),name=data.name,creatorId=1039373905,placeId=game.PlaceId}
sequence:Destroy()
return H:JSONEncode(result)'''.replace('PAYLOAD',payload).replace('ASSET_NAME',json.dumps(asset_name))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--coordinated-edit-window',action='store_true')
    parser.add_argument('--version',choices=['v1','v2'],default='v1')
    args=parser.parse_args()
    if not args.coordinated_edit_window:
        raise SystemExit('Requires a coordinated Edit window; then pass --coordinated-edit-window')
    receipt=OUT/('published-animation.json' if args.version=='v1' else 'published-animation-v2.json')
    if receipt.exists(): raise SystemExit('Existing publication receipt; inspect rather than create duplicate')
    payload=(OUT/('hide-hold-keyframes.json' if args.version=='v1' else 'hide-hold-v2-keyframes.json')).read_text()
    client=StudioMcpClient(find_mcp_batch())
    try:
        client.initialize();time.sleep(3);select_studio(client,'BACKROOMS: STAY QUIET [CO-OP HORROR]',20)
        result=client.call('execute_luau',{'datamodel_type':'Edit','code':source(payload,'Zyntra Actual Character Table Hide '+args.version)})
        (OUT/('publish-attempt-'+args.version+'.txt')).write_text(str(result))
        parsed=json.loads(result)
        if parsed.get('status')!='Enum.CreateAssetResult.Success' or not str(parsed.get('id','')).isdigit():
            raise RuntimeError('Animation publication did not return verified success: '+str(parsed))
        receipt.write_text(json.dumps(parsed,indent=2)+'\n');print(json.dumps(parsed))
    finally: client.close()

if __name__=='__main__': main()
