"""Scoped downstream export of freshly verified concurrent Studio changes.

Native reads only. --capture records exact Sources privately, --apply changes
only selected repository mirrors/rows after another native and disk guard.
"""
from pathlib import Path
from datetime import datetime, timezone
import copy, hashlib, importlib.util, json, subprocess, sys, os, uuid
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
PRIVATE=ROOT/'.git/mongotv-cleanup-20261010/concurrent-export-v2'
sys.dont_write_bytecode=True
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,read_native_record,require_edit_state,mirrored_candidates
from studio_source_contract import canonical_bytes
SID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def save(folder,name,value):
 path=folder/name;path.parent.mkdir(parents=True,exist_ok=True)
 raw=value if isinstance(value,bytes) else (json.dumps(value,indent=2)+'\n').encode()
 with path.open('xb') as f:assert f.write(raw)==len(raw)
def load(folder,name):return json.loads((folder/name).read_bytes())

def atomic_cas(path, before, after):
 assert path.read_bytes()==before, 'Concurrent local edit preserved: '+str(path)
 temporary=path.with_name(path.name+'.mongotv-downstream-'+uuid.uuid4().hex+'.tmp')
 with temporary.open('xb') as stream:
  assert stream.write(after)==len(after);stream.flush()
  st=os.fstat(stream.fileno());identity=(st.st_dev,st.st_ino)
 try:
  st=temporary.stat();assert (st.st_dev,st.st_ino)==identity and temporary.read_bytes()==after
  assert path.read_bytes()==before, 'Concurrent local edit before replace preserved'
  os.replace(temporary,path)
  assert path.read_bytes()==after, 'Concurrent local edit after replace preserved'
 finally:
  if temporary.exists():
   st=temporary.stat();assert (st.st_dev,st.st_ino)==identity and temporary.read_bytes()==after
   temporary.unlink()

def verify_manifest_delta(before, after, records):
 a=copy.deepcopy(after)
 old={tuple(x['segments']):x for x in before['items']}
 selected={tuple(r['native']['segments']) for r in records}
 for entry in a['items']:
  key=tuple(entry['segments'])
  if key in selected:
   for field in ('bytes','sha256','sourceEditorMatches','studioTrailingNewline'):
    if field in old[key]:entry[field]=old[key][field]
    else:entry.pop(field,None)
 assert a==before, 'Unowned manifest changes rejected'


def read_module(path):
 spec=importlib.util.spec_from_file_location('frozen_parity_reader',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
reader=read_module(HERE/'before/parity-reader.py')
baseline=load(HERE/'before','result.json')
assert baseline['complete'] and baseline['nativeSourceEditorConflictCount']==0
native=[]
for page in sorted((HERE/'before').glob('native-page-*.json')):native.extend(json.loads(page.read_bytes())['rows'])
expected_catalog=baseline['nativeEnd']['catalogSHA256']
old_snapshot=load(HERE/'before','repo-before-metadata.json')
def disk_guard():
 assert sha((ROOT/'studio-sync-manifest.json').read_bytes())==old_snapshot['manifestRawSHA256']
 assert set(mirrored_candidates(ROOT))==set(old_snapshot['files'])
 for path,record in old_snapshot['files'].items():
  raw=(ROOT/path).read_bytes();assert len(raw)==record['bytes'] and sha(raw)==record['rawSHA256'],path
def catalog_guard(client):
 require_edit_state(client,SID)
 meta=json.loads(client.call('execute_luau',{'studio_id':SID,'datamodel_type':'Edit','code':reader.CODE+'local rows,meta=catalog() return H:JSONEncode(meta)'}))
 assert meta['catalogSHA256']==expected_catalog and meta['sourceEditorConflictCount']==0,'Native drift; export must be recaptured'
 return meta
manifest_raw=(ROOT/'studio-sync-manifest.json').read_bytes();manifest=json.loads(manifest_raw)
entries={tuple(x['segments']):x for x in manifest['items']}
scope=[]
for row in native:
 key=tuple(row['segments']);entry=entries.get(key)
 changed=entry is None or (row['className']!='RemoteEvent' and entry['sha256']!=row['sourceSHA256'])
 remote_gap=row['className']=='RemoteEvent' and entry is not None and any(entry.get('properties',{}).get(k)!=v for k,v in row['properties'].items())
 if changed or remote_gap:
  path='/'.join(row['segments'][:-1])+'/'+row['segments'][-1]+'.'+row['className']+('.txt' if row['className']=='RemoteEvent' else '.lua')
  scope.append({'file':path,'native':row,'reason':'new-native-script' if entry is None else 'concurrent-native-source' if changed else 'fresh-remote-property-gap'})
assert len({r['file'] for r in scope})==len(scope)
assert len(scope)==3 and all(r['reason']=='concurrent-native-source' for r in scope), 'Only the three freshly observed concurrent Source rows are authorized for this export'
assert {r['file'] for r in scope}=={'ServerScriptService/GameManager.Script.lua','StarterPlayer/StarterPlayerScripts/Level2PoolroomsPresentation.LocalScript.lua','StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua'}
client=None
try:
 client=StudioMcpClient(find_mcp_batch());client.initialize()
 if sys.argv[1:] == ['--capture']:
  assert not PRIVATE.exists() and not (HERE/'export-capture.json').exists()
  disk_guard();assert not git('diff','--cached','--name-only')
  head=git('rev-parse','HEAD').decode().strip();PRIVATE.mkdir(parents=True)
  save(PRIVATE,'manifest-before.json',manifest_raw);save(PRIVATE,'head.txt',head.encode())
  save(PRIVATE,'working-before.patch',git('diff','--'));save(PRIVATE,'plan.before.bin',(ROOT/'CLEANUP_PLAN.md').read_bytes());save(PRIVATE,'results.before.bin',(ROOT/'CLEANUP_RESULTS.md').read_bytes());save(HERE,'export-scope.json',{'nativeWrites':0,'modeSwitches':0,'plan':'T01: export concurrent authoritative Sources and fresh remote Archivable metadata; no runtime feature change','scope':scope})
  start=catalog_guard(client);records=[]
  for index,selected in enumerate(scope,1):
   row=selected['native'];path=selected['file'];print(f'[{index}/{len(scope)}] Read {path}',flush=True)
   source,meta=read_native_record(client,SID,{'fullPath':row['path'],'className':row['className']},131311258779917,10559217407)
   assert meta['instanceId']==row['instanceId'] and meta['parentId']==row['parentId'] and meta['properties']==row['properties'],path
   assert source is not None and meta['sourceEditorMatches'] is True and meta['sourceSHA256']==row['sourceSHA256'] and meta['rawSourceSHA256']==row['rawSourceSHA256'],path
   original=(ROOT/path).read_bytes() if (ROOT/path).exists() else None
   if original is not None:save(PRIVATE,'before/'+path,original)
   if source is not None:save(PRIVATE,'captured/'+path,canonical_bytes(source))
   records.append({'file':path,'reason':selected['reason'],'native':meta,'beforeRawSHA256':sha(original) if original is not None else None,'capturedSHA256':sha(canonical_bytes(source)) if source is not None else None})
  end=catalog_guard(client);disk_guard();assert git('rev-parse','HEAD').decode().strip()==head and not git('diff','--cached','--name-only')
  capture={'pass':True,'headAtCapture':head,'nativeWrites':0,'modeSwitches':0,'sourceMirrorWrites':0,'manifestWrites':0,'start':start,'end':end,'records':records,'limits':'Read-time scoped Source/editor/class/property/attribute/tag capture; no gameplay or complete asset validation'}
  save(HERE,'export-capture.json',capture);print(json.dumps({'pass':True,'captured':len(records),'newScripts':sum(r['reason']=='new-native-script' for r in records),'concurrentSources':sum(r['reason']=='concurrent-native-source' for r in records),'remotePropertyRows':sum(r['reason']=='fresh-remote-property-gap' for r in records)}),flush=True)
 elif sys.argv[1:] == ['--apply']:
  capture=load(HERE,'export-capture.json');assert capture['pass'] and not (HERE/'export-result.json').exists()
  disk_guard();assert git('rev-parse','HEAD').decode().strip()==capture['headAtCapture'] and not git('diff','--cached','--name-only')
  start=catalog_guard(client)
  for record in capture['records']:
   meta=record['native'];code=__import__('sync_from_studio').native_metadata_code(meta['segments'],meta['className'],131311258779917,10559217407)
   now=json.loads(client.call('execute_luau',{'studio_id':SID,'datamodel_type':'Edit','code':code}))
   if now.get('attributes')==[]:now['attributes']={}
   assert now==meta,'Captured native row changed before landing: '+record['file']
  disk_guard();assert git('rev-parse','HEAD').decode().strip()==capture['headAtCapture']
  updated=copy.deepcopy(manifest);by_path={tuple(r['segments']):r for r in updated['items']};written=[];writes=[];attempted=[]
  for record in capture['records']:
   path=record['file'];meta=record['native'];key=tuple(meta['segments']);entry=by_path.get(key)
   if entry is None:
    entry={'studioPath':meta['path'],'className':meta['className'],'file':path,'status':'created','segments':meta['segments']};updated['items'].append(entry);by_path[key]=entry
   assert entry['properties']==meta['properties'] and (entry.get('attributes') or {})==(meta['attributes'] or {}) and entry.get('tags',[])==meta['tags'], 'Unowned metadata drift' 
   if meta['className']!='RemoteEvent':
    raw=(PRIVATE/'captured'/path).read_bytes();assert sha(raw)==record['capturedSHA256']==meta['sourceSHA256'] and len(raw)==meta['canonicalBytes']
    entry.update(bytes=len(raw),sha256=sha(raw),sourceEditorMatches=True);entry.pop('studioTrailingNewline',None)
    destination=ROOT/path;assert destination.is_file();before=(PRIVATE/'before'/path).read_bytes();assert destination.read_bytes()==before;writes.append((destination,before,raw));written.append(path)
  updated['counts']['scripts']=sum(x['className'] in ('Script','LocalScript','ModuleScript') for x in updated['items'])
  updated['counts']['remoteEvents']=sum(x['className']=='RemoteEvent' for x in updated['items']);updated['counts']['total']=len(updated['items'])
  assert updated['counts']['scripts']==baseline['counts']['nativeScripts'] and updated['counts']['total']==len(native)
  verify_manifest_delta(manifest,updated,capture['records'])
  new_raw=(json.dumps(updated,indent=2,ensure_ascii=False)+'\n').encode()
  writes.append((ROOT/'studio-sync-manifest.json',manifest_raw,new_raw))
  disk_guard()
  try:
   for destination,before,after in writes:
    attempted.append((destination,before,after));atomic_cas(destination,before,after)
   end=catalog_guard(client)
   for path,old in old_snapshot['files'].items():
    if path not in written:assert sha((ROOT/path).read_bytes())==old['rawSHA256'],path
   for record in capture['records']:
    if record['capturedSHA256'] is not None:assert sha((ROOT/record['file']).read_bytes())==record['capturedSHA256']
   assert (ROOT/'studio-sync-manifest.json').read_bytes()==new_raw and git('rev-parse','HEAD').decode().strip()==capture['headAtCapture']
  except BaseException as error:
   recovery=[]
   # A foreign dependent file blocks ALL automatic rollback. Keeping our other
   # landed fields preserves their dependency; reconcile from fresh Studio.
   try:owned=all(destination.read_bytes() in (before,after) for destination,before,after in attempted)
   except BaseException as read_error:
    owned=False;recovery.append({'status':'read-error-preserve-all-pending-fresh-native-reconciliation','error':str(read_error)})
   if not owned:
    for destination,before,after in attempted:
     recovery.append({'file':destination.relative_to(ROOT).as_posix(),'status':'preserved-pending-fresh-native-reconciliation'})
   else:
    for destination,before,after in reversed(attempted):
     # Recheck the whole dependent set immediately before each rollback write.
     try:
      if not all(p.read_bytes() in (b,a) for p,b,a in attempted):
       recovery.append({'status':'concurrent-change-during-rollback-stop-and-reconcile'});break
      current=destination.read_bytes()
     except BaseException as read_error:
      recovery.append({'status':'read-error-during-rollback-stop-and-reconcile','error':str(read_error)});break
     if current==before:recovery.append({'file':destination.relative_to(ROOT).as_posix(),'status':'already-before'})
     elif current==after:
      try:atomic_cas(destination,after,before)
      except BaseException as secondary:
       recovery.append({'file':destination.relative_to(ROOT).as_posix(),'status':'rollback-stop-and-reconcile','error':str(secondary)});break
      recovery.append({'file':destination.relative_to(ROOT).as_posix(),'status':'owned-export-restored'})
   save(HERE,'export-failure.json',{'pass':False,'nativeWrites':0,'error':str(error),'localRecovery':recovery})
   raise
  result={'pass':True,'headAtLanding':capture['headAtCapture'],'nativeWrites':0,'modeSwitches':0,'sourceMirrorWrites':written,'manifestBeforeSHA256':sha(manifest_raw),'manifestAfterSHA256':sha(new_raw),'counts':updated['counts'],'nativeStart':start,'nativeEnd':end,'privateCheckpoint':'Private .git/mongotv-cleanup-20261010/concurrent-export-v2; all three previous raw mirrors, manifest and existing dirty documentation preserved','historicalOperationCountsPreserved':True,'limits':'Scoped downstream export, not implementation or gameplay approval of other developers changes'}
  save(HERE,'export-result.json',result);print(json.dumps({'pass':True,'sourceMirrors':len(written),'counts':updated['counts'],'nativeWrites':0}),flush=True)
 else:raise ValueError('Use --capture or --apply')
finally:
 if client is not None:client.close()
