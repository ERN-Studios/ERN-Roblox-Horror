"""Run one pinned Root-owned C06 native contract; no mode switches."""
from pathlib import Path
import hashlib,json,sys,time
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,StudioMcpError,find_mcp_batch,require_edit_state
phase=sys.argv[1];assert phase in ('before','installed')
binding=json.loads((HERE/'native-binding-v1/binding.json').read_bytes())
raw=(HERE/'native-binding-v1'/('native-'+phase+'.luau')).read_bytes()
assert hashlib.sha256(raw).hexdigest()==binding['nativeCodeHashes'][phase]
destination=HERE/('native-'+phase+'-result-v1.json');assert not destination.exists()
SID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
client=StudioMcpClient(find_mcp_batch());client.initialize()
started=time.monotonic()
try:
 require_edit_state(client,SID)
 print('Running pinned native '+phase+' probe; original Source/editor/metadata and owned cleanup are guarded',flush=True)
 response=client._request('tools/call',{'name':'execute_luau','arguments':{'studio_id':SID,'datamodel_type':'Edit','code':raw.decode('utf8')}},timeout=180)
 result=response.get('result',{});text='\n'.join(c.get('text','') for c in result.get('content',[]) if c.get('type')=='text')
 assert len(text.encode())<20000,'Bounded probe response exceeded'
 if result.get('isError'):raise StudioMcpError(text)
 proof=json.loads(text)
 proof['rootClientWallSeconds']=round(time.monotonic()-started,3)
 proof['rootExecutedCodeSHA256']=hashlib.sha256(raw).hexdigest()
 with destination.open('xb') as f:f.write((json.dumps(proof,indent=2)+'\n').encode())
 require_edit_state(client,SID)
 assert proof['pass'] and proof['originalsUnchanged'] and proof['ownedLeaseReleased'] and proof['remainingProbes']==0,proof
 assert proof['originalSourceCoverage']==213 and proof['probesCreated']==proof['probesDestroyed']==4
 assert proof['nativeOriginalSourceWrites']==proof['nativeOriginalParentWrites']==proof['nativeOriginalAttributeWrites']==proof['modeSwitches']==0
 print(json.dumps(proof),flush=True)
finally:client.close()
