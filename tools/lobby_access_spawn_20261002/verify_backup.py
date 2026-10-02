"""Reconstruct/reopen/freeze a fresh full native export; no Studio connection."""
from pathlib import Path
import argparse,datetime,hashlib,json,shutil,subprocess,sys
TASK=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--phase',required=True,choices=['before','after']);p.add_argument('--lune',type=Path,default=Path('/private/tmp/level6-lune-20261001/lune'));p.add_argument('--artifacts',type=Path,required=True)
a=p.parse_args();d=Path('/private/tmp/lobby-access-spawn-20261002')/a.phase
out=a.artifacts/a.phase;out.mkdir(parents=True,exist_ok=True)
durable=Path('/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-access-spawn')/a.phase

def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def read(path):return json.loads(path.read_text())
def immutable(path,data):
 if path.exists():assert path.read_bytes()==data,'Immutable verification output differs: '+str(path)
 else:path.write_bytes(data)
def record(path,obj):immutable(path,(json.dumps(obj,indent=2)+'\n').encode())
metadata=read(d/'metadata.received.json')
assert metadata['task']=='lobby-access-spawn-20261002' and metadata['phase']==a.phase
assert metadata['placeId']==131311258779917 and metadata['universeId']==10559217407 and metadata['groupId']==1039373905
assert metadata['editorConflicts']==[] and metadata['skipped']==[]
transfer=read(d/'source-transfer-receipt.json')
assert transfer==metadata['sourceTransfer']
raw=(d/'scripts.json').read_bytes()
assert len(raw)==transfer['bytes'] and hashlib.sha256(raw).hexdigest()==transfer['sha256']
for i in range(transfer['parts']):immutable(d/f'script-part-{i:05d}.jsonpart',raw[i*750000:(i+1)*750000])
metadata['scriptJsonParts']=transfer['parts'];record(d/'metadata.json',metadata)
shutil.copy2(TASK/'service-property-schema.json',d/'service-property-schema.json')
subprocess.run([sys.executable,str(TASK/'recovery/assemble_native_backup.py'),str(d)],check=True)
assert sha(d/'all-service-children.rbxm')==metadata['nativeSHA256']
subprocess.run([str(a.lune),'run',str(TASK/'recovery/pack_native_backup.luau'),str(d)],check=True)
place=d/f'{a.phase.capitalize()}LobbyAccessSpawn-AuthoritativeStudio.rbxl'
made=d/'BeforeLevel6-AuthoritativeStudio.rbxl'
immutable(place,made.read_bytes())
report_path=d/'native-recovery-reopen-verification.json'
subprocess.run([str(a.lune),'run',str(TASK/'recovery/verify_native_recovery.luau'),str(d),str(place),str(report_path)],check=True)
r=read(report_path)
assert r['verified'] and r['captureId']==metadata['captureId'] and r['nativeSHA256']==metadata['nativeSHA256']
assert r['rootErrors']==r['sourceErrors']==r['sourceEditorConflicts']==0
assert r['sourceCount']==metadata['scriptCount'] and r['rootCount']==metadata['rootCount'] and r['nativePlaceSHA256']==sha(place)
durable.mkdir(parents=True,exist_ok=True);files=[]
for src in sorted(d.rglob('*')):
 if not src.is_file() or 'capture-errors' in src.parts:continue
 rel=src.relative_to(d);dst=durable/rel;dst.parent.mkdir(parents=True,exist_ok=True)
 if dst.exists():assert sha(dst)==sha(src),'Different durable backup exists: '+str(dst)
 else:shutil.copy2(src,dst)
 assert dst.stat().st_size==src.stat().st_size and sha(dst)==sha(src)
 files.append({'file':str(rel),'bytes':dst.stat().st_size,'sha256':sha(dst)})
summary={k:metadata[k] for k in ['task','phase','captureId','capturedAt','placeId','universeId','groupId','rootCount','scriptCount','nativeSHA256','nativeBytes','captureStartUnixMillis','captureFinishedUnixMillis']}
summary.update({'editorConflicts':0,'nativePlaceSHA256':sha(place),'nativePlaceBytes':place.stat().st_size,'canonicalNativeForestSHA256':r['canonicalNativeForestSHA256'],'canonicalReopenedForestSHA256':r['canonicalReopenedForestSHA256'],'nativeRecoveryVerified':True,'sourceCatalogSHA256':sha(d/'scripts.json'),'durableDirectory':str(durable),'serviceReconstructionPropertyErrors':len(read(d/'native-place-verification.json')['propertyErrors']),'unreadableServicePropertyLimits':len(read(d/'native-place-verification.json')['limitations']),'studioWritesPerformed':False,'publicationClaim':False})
record(out/'backup-summary.json',summary)
immutable(out/'source-inventory.json',(d/'source-inventory.json').read_bytes())
receipt={'schema':'lobby-access-spawn-durable-native-backup-v1','verified':True,'phase':a.phase,'captureId':metadata['captureId'],'nativeSHA256':metadata['nativeSHA256'],'nativePlaceSHA256':sha(place),'sourceCatalogSHA256':sha(d/'scripts.json'),'durableDirectory':str(durable),'fileCount':len(files),'files':files,'verification':{'rawChunksExact':True,'canonicalForestReopensExactly':True,'sourcesEditorsEqual':True,'durableRereadMatches':True},'limits':r['limits'],'verifiedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'studioWritesPerformed':False,'publicationClaim':False}
record(out/'durable-backup-receipt.json',receipt)
print(json.dumps(summary))
