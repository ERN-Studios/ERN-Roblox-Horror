"""Root-only strict fresh target Source/editor read; never writes Studio or a mirror."""
from pathlib import Path
import hashlib,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,read_native_record,require_edit_state
SID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
raw=(ROOT/'studio-sync-manifest.json').read_bytes();manifest=json.loads(raw)
entry=next(r for r in manifest['items'] if r.get('file')=='StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua')
assert entry['sha256']=='13b6fdf722449d063204c7e4ee5275d06b7056c78be860a829abc4cee905bae3'
destination=HERE/'native-target-read-v1.json';assert not destination.exists()
private=ROOT/'.git/mongotv-cleanup-20261010/exit-target-native-v1';private.mkdir()
client=StudioMcpClient(find_mcp_batch());client.initialize()
try:
 require_edit_state(client,SID)
 source,metadata=read_native_record(client,SID,{'fullPath':entry['studioPath'],'className':entry['className']},131311258779917,10559217407)
 assert metadata['sourceEditorMatches'] and source is not None
 native=source.encode('utf8');repo=(ROOT/entry['file']).read_bytes().replace(b'\r\n',b'\n')
 assert hashlib.sha256(native).hexdigest()==entry['sha256']==metadata['sourceSHA256'] and len(native)==entry['bytes'] and native==repo
 assert metadata['properties']==entry['properties'] and (metadata['attributes'] or [])==entry.get('attributes',[]) and metadata['tags']==entry.get('tags',[])
 (private/'native-source.before.bin').write_bytes(native)
 require_edit_state(client,SID)
 assert (ROOT/'studio-sync-manifest.json').read_bytes()==raw
 proof={'schema':'exit-literal-fresh-native-target-v1','pass':True,'nativeWrites':0,'modeSwitches':0,'metadata':metadata,'bytes':len(native),'sourceSHA256':hashlib.sha256(native).hexdigest(),'manifestSHA256':hashlib.sha256(raw).hexdigest(),'limits':'One fresh target Source/editor/identity/class/properties/attributes/tags read. No all-script epoch, gameplay or feature certificate.'}
 with destination.open('xb') as f:f.write((json.dumps(proof,indent=2)+'\n').encode())
 print(json.dumps(proof),flush=True)
finally:client.close()
