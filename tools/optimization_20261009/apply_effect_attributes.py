"""Apply only the nine fresh, reviewed effect metadata batches in Edit."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / 'tools/optimization_20261009'
sys.path.insert(0, str(ROOT / 'tools'))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio

def main():
    assert sys.argv[1:] == ['--apply'], 'Explicit --apply required'
    selector = (TASK / 'effects/effect_selector.ModuleScript.lua').read_bytes().decode()
    helper = (TASK / 'effects/install/guarded_attribute_apply.luau').read_bytes().decode()
    director = (TASK / 'effects/install/Level4LightDirector.after.lua').read_bytes().decode()
    client = StudioMcpClient(find_mcp_batch())
    receipts = []
    try:
        client.initialize()
        studio = select_studio(client, '[UPDATE] BACKROOMS: STAY QUIET', 25)
        sid = studio.get('studio_id') or studio.get('id')
        for file in sorted((TASK / 'effects/install').glob('attributes-batch-*.json')):
            code = '''local H=game:GetService('HttpService')
local SES=game:GetService('ScriptEditorService')
local originals={}
for i,s in ipairs(game:GetDescendants()) do
 if s:IsA('LuaSourceContainer') then originals[s]={source=s.Source,editor=SES:GetEditorSource(s),parent=s.Parent,name=s.Name} end
 if i%%2000==0 then task.wait() end
end
local Selector=(function()\n%s\nend)()
local Apply=(function()\n%s\nend)()
local ok,result=xpcall(function() return Apply(game,H:JSONDecode(%s),Selector,%s,'apply') end,debug.traceback)
for s,pin in pairs(originals) do
 assert(s.Parent==pin.parent and s.Name==pin.name and s.Source==pin.source and SES:GetEditorSource(s)==pin.editor,'Authoritative original changed: '..s:GetFullName())
end
assert(ok,result)
return H:JSONEncode(result)
''' % (selector, helper, json.dumps(file.read_text()), json.dumps(director))
            receipt = json.loads(client.call('execute_luau', {'studio_id':sid,'datamodel_type':'Edit','code':code}))
            receipts.append(receipt)
            (TASK / 'effects/install/attribute-install-receipt.json').write_text(json.dumps({'batches':receipts,'complete':len(receipts)==9,'backupPolicy':'Owner requested no new backup'},indent=2)+'\n')
            print(file.name, receipt['Changed'], flush=True)
    finally:
        client.close()

if __name__ == '__main__':
    main()
