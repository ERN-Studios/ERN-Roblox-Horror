"""Root-only readonly native capture for two dependencies and full count."""
from pathlib import Path
import hashlib,importlib.util,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,read_native_record,require_edit_state
from studio_source_contract import canonical_bytes
SID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
baseline=ROOT/'artifacts/cleanup-20261010/resume-baseline-v1/after'
spec=importlib.util.spec_from_file_location('reviewed_parity',baseline/'parity-reader.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
expected=json.loads((baseline/'result.json').read_bytes())['nativeEnd']['catalogSHA256']
assert not (HERE/'native-binding-input-v1.json').exists()
rows=[]
for page in sorted(baseline.glob('native-page-*.json')):
 for r in json.loads(page.read_bytes())['rows']:
  if r['className']!='RemoteEvent':rows.append({'studioPath':r['path'],'className':r['className'],'segments':r['segments'],'instanceId':r['instanceId'],'parentId':r['parentId'],'sha256':r['sourceSHA256']})
assert len(rows)==213
manifest_raw=(ROOT/'studio-sync-manifest.json').read_bytes();manifest=json.loads(manifest_raw)
private=ROOT/'.git/mongotv-cleanup-20261010/preview-native-before-v1';private.mkdir(parents=True)
client=StudioMcpClient(find_mcp_batch());client.initialize()
try:
 def census():
  require_edit_state(client,SID)
  result=json.loads(client.call('execute_luau',{'studio_id':SID,'datamodel_type':'Edit','code':m.CODE+'local rows,meta=catalog() return H:JSONEncode(meta)'}))
  assert result['catalogSHA256']==expected and result['sourceEditorConflictCount']==0,'Fresh catalog drift'
  return result
 start=census()
 for row in rows:
  if row['studioPath'] not in ('StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt','ReplicatedStorage.DevAccess'):continue
  source,meta=read_native_record(client,SID,{'fullPath':row['studioPath'],'className':row['className']},131311258779917,10559217407)
  assert meta['instanceId']==row['instanceId'] and meta['parentId']==row['parentId'] and meta['sourceSHA256']==row['sha256']
  entry=next(r for r in manifest['items'] if r['studioPath']==row['studioPath'])
  assert entry['properties']==meta['properties'] and entry['attributes']==(meta['attributes'] or []) and entry.get('tags',[])==meta['tags']
  raw=canonical_bytes(source);assert hashlib.sha256(raw).hexdigest()==entry['sha256']==row['sha256']
  assert canonical_bytes((ROOT/entry['file']).read_text(encoding='utf8'))==raw
  (private/(meta['className']+'-'+meta['instanceId']+'.source.lua')).write_bytes(raw)
  row.update(properties=meta['properties'],attributes=meta['attributes'] or [],tags=meta['tags'],bytes=len(raw),sourceEditorMatches=True)
 end=census();assert (ROOT/'studio-sync-manifest.json').read_bytes()==manifest_raw
 result={'schema':'preview-native-binding-input-v1','pass':True,'nativeWrites':0,'modeSwitches':0,'rows':rows,'begin':start,'end':end,'manifestSHA256':hashlib.sha256(manifest_raw).hexdigest(),'limits':'Complete native Source/class/identity census; fresh properties/attributes/tags only for the two selected target/DevAccess originals. Other rows are used only for the census and do not pretend metadata coverage.'}
 with (HERE/'native-binding-input-v1.json').open('xb') as f:f.write((json.dumps(result,indent=2)+'\n').encode())
 print(json.dumps({'pass':True,'scriptRows':len(rows),'freshFullMetadataRows':2,'nativeWrites':0}))
finally:client.close()
