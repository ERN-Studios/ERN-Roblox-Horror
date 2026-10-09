"""Explicit isolated lazy-level task staging; no Studio writes or GitHub push.

stage SCOPE.json creates a review plan/alternate index from fresh HEAD.
commit PLAN --reviewed-plan-sha256 SHA --message-file FILE commits that tree,
then refreshes only selected task entries in the locked real index.
Scope: {"sources":[{"studioPath":...,"className":...,"file":...,
"operation":"modify|add|move","beforeFile":...,"beforeStudioPath":...}],
"artifacts":[explicit top-level task artifact paths]}. before* is move-only.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime,timezone
import importlib.util
import json
import os
from pathlib import Path,PurePosixPath
import uuid

ROOT=Path(__file__).resolve().parents[2]
TASK='artifacts/lazy-levels-20261009'
MANIFEST='studio-sync-manifest.json'
LUA_ARTIFACTS={
 'native_scene.luau',
 'level4_lifecycle_harness.luau',
 'level4_native_qa.luau',
 'round_entry_batch_harness.luau',
 'level6_deferred_audio_harness.luau',
}
spec=importlib.util.spec_from_file_location('reviewed_stutter_stage',ROOT/'artifacts/stutter-assets-20261009/stage_task.py')
b=importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
require,sha,encode,git,entries=b.require,b.sha,b.encode,b.git,b.entries
ALLOWED={
 'ServerScriptService.LevelWorldStorage':'ModuleScript',
 'ServerScriptService.Level4RoundGenerator':'ModuleScript',
 'ServerScriptService.Level5PreviewAccess':'Script',
 'ServerScriptService.Level6PreviewAccess':'Script',
 'ServerScriptService.Level 6 Systems.Level 6 Playground Game':'ModuleScript',
 'ServerScriptService.Live Level Server':'Script',
 'ServerScriptService.GameManager':'Script',
 'ServerScriptService.LobbyReimaginedPreview.QueueBridge':'ModuleScript',
 'ServerStorage.Level 4 Cinema Blender.OccasionalFixtureFlicker':'Script',
 'ServerStorage.Level 4 Cinema Blender.Doors.PushDoors':'Script',
 'StarterPlayer.StarterPlayerScripts.Level 4 Round Client':'LocalScript',
 'StarterPlayer.StarterPlayerScripts.Level 4 Lighting Controller':'LocalScript',
 'StarterPlayer.StarterPlayerScripts.Level 5 Lighting Controller':'LocalScript',
 'StarterPlayer.StarterPlayerScripts.Level 6 Playground Client':'LocalScript',
 'StarterPlayer.StarterPlayerScripts.Level6PreviewTransport':'LocalScript',
 'StarterPlayer.StarterPlayerScripts.Round Entry Client':'LocalScript',
}

def mirror(native,kind): return native.replace('.','/')+'.'+kind+'.lua'

def scope(value):
 require(isinstance(value,dict) and set(value)=={'sources','artifacts'},'Expected explicit sources/artifacts scope')
 require(isinstance(value['sources'],list) and value['sources'],'Select source rows explicitly')
 sources=copy.deepcopy(value['sources']); seen=set()
 for row in sources:
  require(set(row)<= {'studioPath','className','file','operation','beforeFile','beforeStudioPath'},'Unexpected source scope fields')
  native=row['studioPath']; kind=row['className']; operation=row['operation']
  require(ALLOWED.get(native)==kind and row['file']==mirror(native,kind),'Source outside authorized task allowlist')
  require(operation in {'modify','add','move'} and row['file'] not in seen,'Invalid/duplicate source operation')
  seen.add(row['file'])
  if operation=='move':
   require(native.startswith('ServerStorage.Level 4 Cinema Blender.'),'Only embedded Level4 scripts may move')
   require(row.get('beforeStudioPath')==native.replace('ServerStorage.','Workspace.',1) and row.get('beforeFile')==row['file'].replace('ServerStorage/','Workspace/',1),'Unexpected native/mirror relocation')
   require(row['beforeFile'] not in seen,'Duplicate old source path'); seen.add(row['beforeFile'])
  else:
   require('beforeFile' not in row and 'beforeStudioPath' not in row,'Unexpected old source identity')
   require((operation=='add')==(native=='ServerScriptService.LevelWorldStorage'),'Only the new storage module may be added')
 artifacts=value['artifacts']
 require(isinstance(artifacts,list) and all(isinstance(p,str) for p in artifacts) and len(set(artifacts))==len(artifacts),'Expected explicit unique artifact paths')
 for rel in artifacts:
  path=PurePosixPath(rel); lower=path.name.lower()
  require(str(path)==rel and path.parent.as_posix()==TASK and path.suffix in {'.json','.md','.py','.luau'},'Unexpected artifact path/type')
  require(not any(token in lower for token in ('candidate','baseline','sources.json','secret','credential','.env','.before.')),'Private source snapshots/credentials are excluded')
  require(path.suffix!='.luau' or path.name in LUA_ARTIFACTS or lower.startswith('probe_'),'Only explicit native helpers/QA or probe Luau may be committed')
 return {'sources':sources,'artifacts':artifacts}

def paths_of(selection):
 paths=[row['file'] for row in selection['sources']]
 paths += [row['beforeFile'] for row in selection['sources'] if row['operation']=='move']
 return paths+selection['artifacts']+[MANIFEST]

def task_rows(manifest,selection):
 result={}
 for row in selection['sources']:
  matches=[e for e in manifest['items'] if e.get('file')==row['file'] or e.get('studioPath')==row['studioPath']]
  require(len(matches)==1,'Expected one verified task manifest row: '+row['file'])
  entry=matches[0]
  require(entry.get('file')==row['file'] and entry.get('studioPath')==row['studioPath'] and entry.get('className')==row['className'],'Manifest identity mismatch')
  if row['operation']=='move': require(not any(e.get('file')==row['beforeFile'] or e.get('studioPath')==row['beforeStudioPath'] for e in manifest['items']),'Old relocated manifest row remains')
  result[row['file']]=copy.deepcopy(entry)
 return result

def replace_rows(base,replacements,selection,allow_current=False):
 result=copy.deepcopy(base)
 for row in selection['sources']:
  old_file=row.get('beforeFile',row['file']); old_native=row.get('beforeStudioPath',row['studioPath'])
  old=[i for i,e in enumerate(result['items']) if e.get('file')==old_file or e.get('studioPath')==old_native]
  current=[i for i,e in enumerate(result['items']) if e.get('file')==row['file'] or e.get('studioPath')==row['studioPath']]
  if row['operation']=='add':
   require(not current or (allow_current and len(current)==1),'Added manifest row already exists in HEAD')
   if current:
    entry=result['items'][current[0]]
    require(entry.get('file')==row['file'] and entry.get('studioPath')==row['studioPath'] and entry.get('className')==row['className'],'Added staged manifest identity mismatch')
    result['items'][current[0]]=copy.deepcopy(replacements[row['file']])
   else: result['items'].append(copy.deepcopy(replacements[row['file']]))
  else:
   candidates=old if old else (current if allow_current else [])
   require(len(candidates)==1 and (row['operation']!='move' or not (old and current)),'Task baseline manifest identity absent/ambiguous')
   entry=result['items'][candidates[0]]
   expected_file=old_file if old else row['file']; expected_native=old_native if old else row['studioPath']
   require(entry.get('file')==expected_file and entry.get('studioPath')==expected_native and entry.get('className')==row['className'],'Task baseline manifest identity mismatch')
   result['items'][candidates[0]]=copy.deepcopy(replacements[row['file']])
 return result

def apply_entries(root,index,values):
 b.update_entries(root,index,{p:(v if v is not None else ['0','0'*40]) for p,v in values.items()})

def stage(root,scope_file,plan_dir=None):
 root=root.resolve(); scope_raw=scope_file.read_bytes(); selection=scope(json.loads(scope_raw))
 reference=b.head_ref(root); baseline=b.head(root); before=entries(root)
 real_index=Path(git(root,'rev-parse','--path-format=absolute','--git-path','index').decode().strip())
 git_dir=Path(git(root,'rev-parse','--absolute-git-dir').decode().strip()).resolve()
 directory=(plan_dir or git_dir/'lazy-levels-20261009'/('stage-'+uuid.uuid4().hex)).resolve()
 require(directory.is_relative_to(git_dir),'Plan must stay in repository Git directory'); directory.mkdir(parents=True,exist_ok=False)
 alternate=directory/'alternate-index'; paths=paths_of(selection)
 replacements=task_rows(json.loads(b.read_file(root,MANIFEST)),selection)
 prepared=encode(replace_rows(json.loads(git(root,'show',baseline+':'+MANIFEST)),replacements,selection))
 git(root,'read-tree',baseline,index=alternate); head_entries=entries(root,alternate)
 staged={}; inputs={}; source_files={r['file']:r for r in selection['sources']}
 removed=[r['beforeFile'] for r in selection['sources'] if r['operation']=='move']
 for rel in paths:
  if rel in removed:
   require(rel in head_entries and not (root/rel).exists(),'Expected verified old mirror removal: '+rel); staged[rel]=None; continue
  if rel in source_files:
   require((rel not in head_entries)==(source_files[rel]['operation'] in {'add','move'}),'Source add/modify operation differs from HEAD')
  raw=prepared if rel==MANIFEST else b.read_file(root,rel)
  if rel in source_files:
   canonical=raw.decode('utf-8').replace('\r\n','\n').encode(); row=replacements[rel]
   require(row.get('status')=='synced' and row.get('sourceEditorMatches') is True and row.get('sha256')==sha(canonical) and row.get('bytes')==len(canonical),'Verified native source/mirror parity missing')
  oid=b.blob(root,rel,raw)
  if rel in source_files: require(git(root,'cat-file','blob',oid)==canonical,'Git clean conversion changed native source')
  staged[rel]=[head_entries.get(rel,['100644'])[0],oid]
  if rel!=MANIFEST: inputs[rel]=sha(raw)
 apply_entries(root,alternate,staged); tree=git(root,'write-tree',index=alternate).decode().strip()
 changed=git(root,'diff','--cached','--name-only','-z',baseline,index=alternate).split(b'\0')
 require(any(changed) and all(not p or p.decode() in paths for p in changed),'No changes or unrelated alternate-index change')
 diff=git(root,'diff','--cached','--no-ext-diff','--no-textconv','--binary',baseline,index=alternate)
 (directory/'staged.diff').write_bytes(diff); (directory/'name-status.txt').write_bytes(git(root,'diff','--cached','--name-status',baseline,index=alternate))
 (directory/'status-before.txt').write_bytes(git(root,'status','--short')); (directory/'blobs.json').write_bytes(encode(staged)); (directory/'task-manifest.json').write_bytes(prepared)
 b.require_head_ref(root,reference); require(b.head(root)==baseline,'HEAD advanced during planning')
 current=entries(root); require({p:current.get(p) for p in paths}=={p:before.get(p) for p in paths},'Target staged entries changed during planning')
 require(scope_file.read_bytes()==scope_raw,'Scope file changed during planning')
 plan={'format':1,'task':'lazy-levels-20261009','root':str(root),'head':baseline,'headRef':reference,'tree':tree,'createdAtUtc':datetime.now(timezone.utc).isoformat(),'scope':selection,'scopeFile':str(scope_file.resolve()),'scopeSHA256':sha(scope_raw),'paths':paths,'alternateIndex':str(alternate),'alternateIndexSHA256':sha(alternate.read_bytes()),'realIndex':str(real_index),'targetIndexBefore':{p:before.get(p) for p in paths},'blobs':staged,'inputsSHA256':inputs,'manifestRows':replacements,'diffSHA256':sha(diff)}
 plan_file=directory/'plan.json'; plan_file.write_bytes(encode(plan))
 return {'plan':str(plan_file),'reviewedPlanSHA256':sha(plan_file.read_bytes()),'reviewDiff':str(directory/'staged.diff'),'nameStatus':str(directory/'name-status.txt'),'blobs':str(directory/'blobs.json'),'head':baseline,'tree':tree}

def commit(root,plan_file,reviewed_sha,message_file):
 root=root.resolve(); raw=plan_file.read_bytes(); require(sha(raw)==reviewed_sha,'Plan differs from reviewed SHA256'); plan=json.loads(raw)
 require(plan['format']==1 and plan['task']=='lazy-levels-20261009' and Path(plan['root'])==root,'Wrong plan')
 selection=scope(plan['scope']); paths=paths_of(selection); require(paths==plan['paths'],'Scope differs')
 require(sha(Path(plan['scopeFile']).read_bytes())==plan['scopeSHA256'],'Explicit scope changed after review')
 b.require_head_ref(root,plan['headRef']); alternate=Path(plan['alternateIndex'])
 git_dir=Path(git(root,'rev-parse','--absolute-git-dir').decode().strip()).resolve()
 require(plan_file.resolve().parent.is_relative_to(git_dir) and alternate.parent==plan_file.resolve().parent,'Plan/index outside Git checkpoint')
 require(sha(alternate.read_bytes())==plan['alternateIndexSHA256'],'Reviewed alternate index changed')
 require(git(root,'write-tree',index=alternate).decode().strip()==plan['tree'] and sha(alternate.read_bytes())==plan['alternateIndexSHA256'],'Reviewed tree/index changed')
 reviewed=entries(root,alternate); require({p:reviewed.get(p) for p in paths}==plan['blobs'],'Reviewed blob list changed')
 require(sha(git(root,'diff','--cached','--no-ext-diff','--no-textconv','--binary',plan['head'],index=alternate))==plan['diffSHA256'],'Reviewed staged diff changed')
 for rel,digest in plan['inputsSHA256'].items(): require(sha(b.read_file(root,rel))==digest,'Working task file changed: '+rel)
 for row in selection['sources']:
  if row['operation']=='move': require(not (root/row['beforeFile']).exists(),'Old mirror reappeared after review')
 require(task_rows(json.loads(b.read_file(root,MANIFEST)),selection)==plan['manifestRows'],'Working task manifest rows changed')
 message=message_file.read_bytes(); require(message.strip(),'Empty message')
 real_index=Path(git(root,'rev-parse','--path-format=absolute','--git-path','index').decode().strip()); require(real_index==Path(plan['realIndex']),'Index path changed')
 lock=real_index.with_name(real_index.name+'.lock'); receipt=plan_file.parent/'commit-receipt.json'; require(not receipt.exists(),'Plan already attempted')
 b.require_head_ref(root,plan['headRef']); fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600); moved=False
 result={'task':'lazy-levels-20261009','headBefore':plan['head'],'headRef':plan['headRef'],'commit':None,'realIndexUpdated':False,'push':False}
 try:
  original=real_index.read_bytes(); (plan_file.parent/'real-index-before-commit').write_bytes(original)
  b.require_head_ref(root,plan['headRef']); require(b.head(root)==plan['head'],'HEAD advanced; regenerate and review plan')
  latest=entries(root); require({p:latest.get(p) for p in paths}==plan['targetIndexBefore'],'Target staged entries changed after review')
  refreshed=plan_file.parent/'refreshed-real-index'; require(not refreshed.exists(),'Recovery index exists'); refreshed.write_bytes(original)
  require(latest.get(MANIFEST) is not None,'Staged manifest was removed')
  merged=encode(replace_rows(json.loads(git(root,'cat-file','blob',latest[MANIFEST][1])),plan['manifestRows'],selection,True))
  updates=copy.deepcopy(plan['blobs']); updates[MANIFEST]=[latest[MANIFEST][0],b.blob(root,MANIFEST,merged)]; apply_entries(root,refreshed,updates)
  after=entries(root,refreshed); require({p:v for p,v in after.items() if p not in paths}=={p:v for p,v in latest.items() if p not in paths},'Unrelated staged entries changed')
  require(real_index.read_bytes()==original,'Real index changed despite lock')
  result['commit']=git(root,'commit-tree',plan['tree'],'-p',plan['head'],index=alternate,data=message).decode().strip(); receipt.write_bytes(encode(result))
  with os.fdopen(fd,'wb',closefd=False) as handle: handle.write(refreshed.read_bytes()); handle.flush(); os.fsync(fd)
  b.require_head_ref(root,plan['headRef']); git(root,'update-ref','-m','commit: lazy-levels-20261009',plan['headRef'],result['commit'],plan['head']); moved=True
  os.close(fd); fd=None; os.replace(lock,real_index); result.update(realIndexUpdated=True,unrelatedStagedEntriesPreserved=True,manifestUnrelatedRowsPreserved=True)
  receipt.write_bytes(encode(result)); return result
 except Exception as error:
  result.update(headUpdated=moved,error=str(error)); receipt.write_bytes(encode(result)); raise
 finally:
  if fd is not None: os.close(fd)
  if lock.exists() and not moved: lock.unlink()

def main():
 p=argparse.ArgumentParser(description=__doc__); sub=p.add_subparsers(dest='command',required=True)
 s=sub.add_parser('stage'); s.add_argument('scope',type=Path); s.add_argument('--plan-dir',type=Path)
 c=sub.add_parser('commit'); c.add_argument('plan',type=Path); c.add_argument('--reviewed-plan-sha256',required=True); c.add_argument('--message-file',required=True,type=Path)
 a=p.parse_args(); result=stage(ROOT,a.scope,a.plan_dir) if a.command=='stage' else commit(ROOT,a.plan.resolve(),a.reviewed_plan_sha256,a.message_file)
 print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
