"""Root-owned pure native CFrame constructor gate; never creates or edits objects."""
from pathlib import Path
import hashlib,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,require_edit_state
raw=(HERE/'readonly-constructor-probe.luau').read_bytes()
pin='89a30b82c59fa838edd9275bdb6fa9cada24feb12d95b256234e5c8b867db971'
assert hashlib.sha256(raw).hexdigest()==pin
destination=HERE/'readonly-constructor-native-result-v1.json'
assert not destination.exists()
studio='1b603e69-7ae1-4572-b210-d5bf05c684ff'
client=StudioMcpClient(find_mcp_batch());client.initialize()
try:
 require_edit_state(client,studio)
 result=json.loads(client.call('execute_luau',{'studio_id':studio,'datamodel_type':'Edit','code':raw.decode('utf8')}))
 result['rootExecutedCodeSHA256']=pin
 with destination.open('xb') as f:f.write((json.dumps(result,indent=2)+'\n').encode())
 require_edit_state(client,studio)
 assert result['originalsUnchanged']
 assert all(result[k]==0 for k in ('nativeInstanceCreations','copySetterWrites','originalSetterWrites','sourceWrites','originalParentWrites','sharedStateWrites','modeSwitches'))
 print(json.dumps(result),flush=True)
finally:client.close()
