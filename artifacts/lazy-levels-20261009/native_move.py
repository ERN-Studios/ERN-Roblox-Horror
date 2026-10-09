"""Explicit native capture/plan/move/verify/export for three authored levels.

capture --baseline SOURCES.json --approved-sources JSON_PATH_TO_CANDIDATE_FILES
is read-only except a session-only baseline and local private checkpoint files.
planmove CAPTURE_RECEIPT emits Lua and a review plan, never executes it.
move PLAN --reviewed-plan-sha256 SHA is the only native Parent-writing command.
verify PLAN checks the native tree. export PLAN then relocates two verified
source mirrors and exactly their manifest rows. No publication or Git staging.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import shutil
import sys
import threading
import uuid

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PRIVATE=ROOT/'.git/lazy-levels-20261009'
STUDIO_ID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
sys.path.insert(0,str(ROOT/'tools'))
from push_repo_to_studio import luau_string
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME

EMBEDDED={
 'Workspace.Level 4 Cinema Blender.Doors.PushDoors': 'Workspace/Level 4 Cinema Blender/Doors/PushDoors.Script.lua',
 'Workspace.Level 4 Cinema Blender.OccasionalFixtureFlicker': 'Workspace/Level 4 Cinema Blender/OccasionalFixtureFlicker.Script.lua',
}

def require(ok,message):
 if not ok: raise RuntimeError(message)
def sha(raw): return hashlib.sha256(raw).hexdigest()
def encoded(obj): return (json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
def immutable(path,raw):
 path.parent.mkdir(parents=True,exist_ok=True)
 if path.exists(): require(path.read_bytes()==raw,'Different immutable output exists: '+str(path))
 else:
  with path.open('xb') as f: f.write(raw)
def common(): return (HERE/'native_scene.luau').read_text(encoding='utf-8')+'\n'
class NativeClient(StudioMcpClient):
 def _request(self,method,params,timeout=60):
  # Yielding 44k-instance reads may outlast the shared client's 60s default.
  native=method=='tools/call' and params.get('name')=='execute_luau'
  return super()._request(method,params,timeout=600 if native else timeout)
def run(code):
 client=NativeClient(find_mcp_batch())
 try:
  client.initialize(); studio=select_studio(client,RELEASE_STUDIO_NAME,20)
  require(studio['id']==STUDIO_ID,'Authoritative Studio session differs; inspect before invoking')
  return json.loads(client.call('execute_luau',{'studio_id':studio['id'],'datamodel_type':'Edit','code':code}))
 finally: client.close()

def preserve_backup():
 owner=Path(r'G:\Backrooms kopi2.rbxl')
 before=owner.stat(); require(before.st_size==45240585,'Owner backup size changed; inspect fresh file')
 raw=owner.read_bytes(); digest=sha(raw)
 require(owner.stat().st_size==before.st_size and owner.stat().st_mtime_ns==before.st_mtime_ns,'Owner backup changed while reading')
 destination=PRIVATE/'owner-before/Backrooms-kopi2-before.rbxl'
 immutable(destination,raw); require(sha(destination.read_bytes())==digest,'Backup copy hash differs')
 require(sha(owner.read_bytes())==digest,'Owner file changed while preserving')
 receipt={'task':'lazy-levels-20261009','ownerPath':str(owner),'preservedPath':str(destination),
  'bytes':len(raw),'sha256':digest,'ownerFileOverwritten':False,'observedStudioOutput':"22:20:54.848 Place file downloaded to 'G:\\Backrooms kopi2.rbxl'",
  'ownerFileModifiedAtUtc':datetime.fromtimestamp(before.st_mtime,timezone.utc).isoformat(),
  'preservedAtUtc':datetime.now(timezone.utc).isoformat(),
  'limits':'Exact owner-file copy and reread hash; no independent native reopen or whole-place recovery test.'}
 immutable(HERE/'owner-backup.json',encoded(receipt)); return receipt

def source_pins(baseline_path,approved_path):
 raw=baseline_path.read_bytes(); rows=json.loads(raw); approved=json.loads(approved_path.read_bytes())
 require(set(approved)==set(EMBEDDED),'Approve exactly the two embedded source paths')
 pins=[]
 for path in EMBEDDED:
  matches=[r for r in rows if r['path']==path]; require(len(matches)==1,'Expected exact embedded baseline: '+path)
  row=matches[0]; old=Path(row['sourceFile']).read_bytes()
  require(sha(old)==row['sha256'] and len(old)==row['bytes'],'Baseline source file differs')
  source=Path(approved[path]).read_bytes().decode('utf-8').replace('\r\n','\n')
  pins.append({'path':path,'class':row['class'],'source':source,'sha256':sha(source.encode()),'properties':row['properties'],'attributes':{} if row['attributes']==[] else row['attributes']})
 return pins,sha(raw)

def metadata_guards(pins):
 def literal(value):
  if isinstance(value,str): return luau_string(value)
  if isinstance(value,bool): return str(value).lower()
  require(isinstance(value,(int,float)) and math.isfinite(value),'Unsupported script baseline value')
  return repr(value)
 checks=[]
 for i,pin in enumerate(pins,1):
  props=pin['properties']; attrs=pin['attributes']
  require(set(props)<= {'Archivable','LinkedSource','Disabled','RunContext'} and {'Archivable','LinkedSource'}<=set(props),'Incomplete or unsupported script properties')
  require(pin['class']=='ModuleScript' or {'Disabled','RunContext'}<=set(props),'Incomplete BaseScript properties')
  checks.append('do local s=assert(pinObjects['+str(i)+'])')
  for name,value in props.items():
   lhs='s['+luau_string(name)+']'
   if name in {'LinkedSource','RunContext'}: lhs='tostring('+lhs+')'
   checks.append('assert('+lhs+'=='+literal(value)+',"Embedded script property changed")')
  require(isinstance(attrs,dict),'Unsupported script attributes')
  checks.append('local attrs=s:GetAttributes() local count=0 for _ in attrs do count+=1 end assert(count=='+str(len(attrs))+',"Embedded attributes changed")')
  for name,value in attrs.items(): checks.append('assert(attrs['+luau_string(name)+']=='+literal(value)+',"Embedded attribute changed")')
  checks.append('end')
 return '\n'.join(checks)

def capture(baseline_path,approved_path):
 pins,baseline_hash=source_pins(baseline_path,approved_path)
 capture_id=uuid.uuid4().hex; key='__lazyLevels_'+capture_id
 directory=PRIVATE/('capture-'+capture_id); directory.mkdir(parents=True,exist_ok=False)
 class Receiver(BaseHTTPRequestHandler):
  def log_message(self,*_): pass
  def do_POST(self):
   try:
    parts=self.path.strip('/').split('/'); require(len(parts)==2 and parts[0] in {'native','metadata'} and parts[1].isdigit(),'Unexpected capture endpoint')
    require(len(parts[1])==5,'Expected bounded part index')
    length=int(self.headers.get('Content-Length','0')); require(0<length<=750000,'Unexpected capture chunk size')
    data=self.rfile.read(length); require(len(data)==length,'Truncated capture chunk')
    immutable(directory/(parts[0]+'-'+parts[1]+'.part'),data)
    self.send_response(200); self.end_headers(); self.wfile.write(b'saved')
   except Exception as error:
    self.send_response(409); self.end_headers(); self.wfile.write(str(error).encode())
 server=ThreadingHTTPServer(('127.0.0.1',0),Receiver)
 thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
 pin_code='{' + ','.join('{path='+luau_string(p['path'])+',class='+luau_string(p['class'])+',source='+luau_string(p['source'])+'}' for p in pins)+'}'
 suffix='''local key=__KEY__ assert(shared[key]==nil,"Capture key already exists")
assert(H.HttpEnabled,"Read-only native transfer requires existing HttpEnabled; do not alter settings")
local roots={} for _,name in NAMES do
 local root=assert(unique(workspace,name),"Missing Workspace authored map") assert(root.ClassName=="Model","Wrong authored class")
 assert(not unique(SS,name),"Storage collision") table.insert(roots,root)
end
local nodes,index,rows,sources=inspect(roots)
local pins=__PINS__ local pinObjects={} assert(#sources==#pins,"Embedded Source inventory changed")
for _,pin in pins do
 local found for i,entry in nodes do if i%500==0 then task.wait() end if entry.object:GetFullName()==pin.path then assert(not found,"Ambiguous Source path") found=entry.object end end
 assert(found and found.ClassName==pin.class and found.Source==pin.source and SES:GetEditorSource(found)==pin.source,"Approved embedded Source/editor differs")
 table.insert(pinObjects,found)
end
__PIN_METADATA__
local c={key=key,captureId=__ID__,phase="captured",roots=roots,nodes=nodes,index=index,treeSHA256=sha(stable(rows)),expectedParents={workspace,workspace,workspace}}
bindCritical(c)
guard(c)
c.native=SER:SerializeInstancesAsync(roots) c.nativeSHA256=sha(c.native)
guard(c)
local metadata=stable({captureId=c.captureId,nodeCount=#nodes,rows=rows,sources=sources})
local function transfer(kind,bytes)
 local raw=typeof(bytes)=="buffer" and buffer.tostring(bytes) or bytes
 local count=math.ceil(#raw/750000)
 for i=0,count-1 do assert(H:PostAsync(__URL__.."/"..kind.."/"..string.format("%05d",i),string.sub(raw,i*750000+1,math.min((i+1)*750000,#raw)),Enum.HttpContentType.TextPlain)=="saved","Capture transfer failed") end
 return {parts=count,bytes=#raw,sha256=sha(raw)}
end
local nativeTransfer=transfer("native",c.native) local metadataTransfer=transfer("metadata",metadata)
guard(c)
shared[key]=c
local out=summary(c) out.nativeTransfer=nativeTransfer out.metadataTransfer=metadataTransfer
return H:JSONEncode(out)
'''.replace('__KEY__',luau_string(key)).replace('__ID__',luau_string(capture_id)).replace('__PINS__',pin_code).replace('__PIN_METADATA__',metadata_guards(pins)).replace('__URL__',luau_string('http://127.0.0.1:'+str(server.server_address[1])))
 try: receipt=run(common()+suffix)
 finally: server.shutdown(); server.server_close(); thread.join(timeout=3)
 for kind,name in [('native','authored-models.rbxm'),('metadata','native-tree.json')]:
  info=receipt[kind+'Transfer']; data=b''.join((directory/(kind+f'-{i:05d}.part')).read_bytes() for i in range(info['parts']))
  require(len(data)==info['bytes'] and sha(data)==info['sha256'],'Capture transfer hash differs')
  immutable(directory/name,data)
 receipt['checkpoint']=str(directory); receipt['baselineSourcesSHA256']=baseline_hash
 receipt['approvedSources']=[{k:v for k,v in p.items() if k!='source'} for p in pins]
 receipt['capturedAtUtc']=datetime.now(timezone.utc).isoformat()
 immutable(directory/'receipt.json',encoded(receipt))
 immutable(HERE/('capture-'+capture_id+'.json'),encoded(receipt)); return receipt

def planmove(capture_file):
 raw=capture_file.read_bytes(); receipt=json.loads(raw)
 directory=Path(receipt['checkpoint']); require(directory.resolve().is_relative_to(PRIVATE.resolve()),'Wrong capture checkpoint')
 require(sha((directory/'authored-models.rbxm').read_bytes())==receipt['nativeSHA256'],'Native capture file differs')
 suffix='''local c=assert(shared[__KEY__],"Exact capture session unavailable; recapture")
assert(c.captureId==__ID__ and c.phase=="captured" and c.nativeSHA256==__NATIVE__ and c.treeSHA256==__TREE__,"Wrong baseline capture")
guard(c)
assert(sha(SER:SerializeInstancesAsync(c.roots))==c.nativeSHA256,"Saved native property data changed")
guard(c) -- Last full yielding guard after the serializer, before bounded write guards.
local moved={}
local ok,problem=xpcall(function()
 for i,root in c.roots do
  criticalGuard(c) -- Bounded root/embedded Source/editor recheck; no yield before Parent assignment.
  assert(root.Parent==workspace and not unique(SS,NAMES[i]),"Move baseline changed")
  root.Parent=SS c.expectedParents[i]=SS table.insert(moved,i)
 end
 guard(c)
 assert(sha(SER:SerializeInstancesAsync(c.roots))==c.nativeSHA256,"Native payload changed after relocation")
 guard(c) c.phase="moved"
end,debug.traceback)
if not ok then
 local rollback={} local rollbackErrors={} c.phase="failed"
 for j=#moved,1,-1 do
  local i=moved[j] local root=c.roots[i]
  local restored,reason=pcall(function()
   assert(root.Parent==SS and root.Name==NAMES[i] and not unique(workspace,NAMES[i]),"Rollback root/parent or destination changed")
   root.Parent=workspace c.expectedParents[i]=workspace table.insert(rollback,NAMES[i])
  end)
  if not restored then table.insert(rollbackErrors,{name=NAMES[i],error=tostring(reason)}) end
 end
 local out=summary(c) out.success=false out.error=tostring(problem) out.parentsRolledBack=rollback out.rollbackErrors=rollbackErrors
 return H:JSONEncode(out)
end
local out=summary(c) out.success=true out.sameInstances=true out.deletedInstances=false out.clonedInstances=false
return H:JSONEncode(out)
'''
 substitutions={'__KEY__':receipt['captureKey'],'__ID__':receipt['captureId'],'__NATIVE__':receipt['nativeSHA256'],'__TREE__':receipt['treeSHA256']}
 for marker,value in substitutions.items(): suffix=suffix.replace(marker,luau_string(value))
 code=(common()+suffix).encode(); immutable(directory/'move.luau',code)
 plan={'task':'lazy-levels-20261009','captureReceipt':str(capture_file.resolve()),'captureReceiptSHA256':sha(raw),
  'captureKey':receipt['captureKey'],'captureId':receipt['captureId'],'nativeSHA256':receipt['nativeSHA256'],'treeSHA256':receipt['treeSHA256'],
  'code':str(directory/'move.luau'),'codeSHA256':sha(code),'checkpoint':str(directory)}
 immutable(directory/'move-plan.json',encoded(plan))
 return {'plan':str(directory/'move-plan.json'),'reviewedPlanSHA256':sha(encoded(plan)),'reviewCode':plan['code'],'codeSHA256':plan['codeSHA256']}

def read_plan(plan_file):
 plan=json.loads(plan_file.read_bytes()); directory=Path(plan['checkpoint'])
 require(directory.resolve().is_relative_to(PRIVATE.resolve()) and Path(plan['code']).parent==directory,'Wrong plan checkpoint')
 require(sha(Path(plan['code']).read_bytes())==plan['codeSHA256'],'Reviewed move code changed')
 require(sha(Path(plan['captureReceipt']).read_bytes())==plan['captureReceiptSHA256'],'Capture receipt changed')
 return plan,directory

def move(plan_file,reviewed_hash):
 require(sha(plan_file.read_bytes())==reviewed_hash,'Plan was not explicitly reviewed at this hash')
 plan,directory=read_plan(plan_file); require(not (directory/'move-receipt.json').exists(),'Move already attempted')
 receipt=run(Path(plan['code']).read_text(encoding='utf-8'))
 immutable(directory/'move-receipt.json',encoded(receipt)); immutable(HERE/('move-'+plan['captureId']+'.json'),encoded(receipt))
 require(receipt['success'] is True,'Native move failed; inspect receipt without restoring old data')
 return receipt

def verify(plan_file,include_sources=False):
 plan,directory=read_plan(plan_file)
 suffix='''local c=assert(shared[__KEY__],"Exact session capture missing")
assert(c.captureId==__ID__ and c.phase=="moved" and c.nativeSHA256==__NATIVE__ and c.treeSHA256==__TREE__,"Wrong moved capture")
guard(c) assert(sha(SER:SerializeInstancesAsync(c.roots))==c.nativeSHA256,"Native payload changed") guard(c)
local out=summary(c) out.verified=true out.sameInstances=true
__SOURCES__
return H:JSONEncode(out)
'''
 for marker,value in {'__KEY__':plan['captureKey'],'__ID__':plan['captureId'],'__NATIVE__':plan['nativeSHA256'],'__TREE__':plan['treeSHA256']}.items(): suffix=suffix.replace(marker,luau_string(value))
 suffix=suffix.replace('__SOURCES__','for _,row in out.sources do for _,entry in c.nodes do if entry.object:GetFullName()==row.path then row.source=entry.object.Source end end end' if include_sources else '')
 receipt=run(common()+suffix); receipt['verifiedAtUtc']=datetime.now(timezone.utc).isoformat()
 if not include_sources: immutable(HERE/('verified-'+plan['captureId']+'-'+uuid.uuid4().hex+'.json'),encoded(receipt))
 return receipt

def export_sources(root,receipt,directory):
 manifest_path=root/'studio-sync-manifest.json'; before=manifest_path.read_bytes(); manifest=json.loads(before)
 changes=[]
 for old_path,old_rel in EMBEDDED.items():
  new_path=old_path.replace('Workspace.','ServerStorage.',1); new_rel=old_rel.replace('Workspace/','ServerStorage/',1)
  matches=[r for r in receipt['sources'] if r['path']==new_path]; require(len(matches)==1,'Expected verified relocated Source')
  native=matches[0]; source=native['source'].encode('utf-8')
  require(native['sourceEditorMatches'] and sha(source)==native['sha256'] and len(source)==native['bytes'],'Verified Source data differs')
  entries=[e for e in manifest['items'] if e.get('studioPath')==old_path and e.get('file')==old_rel]
  require(len(entries)==1 and entries[0]['className']==native['class'],'Expected exact old manifest entry')
  require(not any(e.get('studioPath')==new_path or e.get('file')==new_rel for e in manifest['items']),'New manifest path already exists')
  old=(root/old_rel); new=(root/new_rel)
  require(old.is_file() and not old.is_symlink() and old.resolve().is_relative_to(root.resolve()),'Wrong existing mirror')
  require(not new.exists() and new.resolve().is_relative_to(root.resolve()),'New mirror path collision')
  old_raw=old.read_bytes()
  require(old_raw.decode('utf-8').replace('\r\n','\n').encode()==source and entries[0]['sha256']==sha(source),'Old mirror is not the newly installed verified Source')
  entry=entries[0]; entry.update(studioPath=new_path,file=new_rel,segments=new_path.split('.'),sha256=sha(source),bytes=len(source),status='synced',sourceEditorMatches=True)
  changes.append((old,new,old_raw,source,old_rel,new_rel))
 updated=encoded(manifest); directory.mkdir(parents=True,exist_ok=False)
 immutable(directory/'manifest-before.json',before); immutable(directory/'manifest-after.json',updated)
 for i,(_,_,old_raw,source,_,_) in enumerate(changes):
  immutable(directory/f'mirror-before-{i}.lua',old_raw); immutable(directory/f'verified-after-{i}.lua',source)
 require(manifest_path.read_bytes()==before,'Manifest changed before export')
 require(all(old.read_bytes()==raw for old,_,raw,_,_,_ in changes),'Old mirror changed before export')
 for _,new,_,source,_,_ in changes:
  new.parent.mkdir(parents=True,exist_ok=True)
  with new.open('xb') as f: f.write(source)
 require(all(new.read_bytes()==source for _,new,_,source,_,_ in changes),'New mirror readback differs')
 require(manifest_path.read_bytes()==before,'Manifest changed during mirror export')
 require(all(old.read_bytes()==raw for old,_,raw,_,_,_ in changes),'Old mirror changed during export')
 manifest_path.write_bytes(updated); require(manifest_path.read_bytes()==updated,'Manifest export readback differs')
 # Delete only the exact old files after both verified new mirrors and manifest exist.
 for old,new,raw,source,_,_ in changes:
  require(old.read_bytes()==raw and new.read_bytes()==source and manifest_path.read_bytes()==updated,'Concurrent work changed before old mirror removal')
  old.unlink()
 return {'task':'lazy-levels-20261009','exported':True,'manifestBeforeSHA256':sha(before),'manifestAfterSHA256':sha(updated),
  'renames':[{'before':a,'after':b,'sha256':sha(source)} for _,_,_,source,a,b in changes],
  'unrelatedManifestEntriesPreserved':True,'studioWrites':False,'checkpoint':str(directory)}

def main():
 p=argparse.ArgumentParser(description=__doc__); sub=p.add_subparsers(dest='command',required=True)
 sub.add_parser('preserve-backup')
 c=sub.add_parser('capture'); c.add_argument('--baseline',required=True,type=Path); c.add_argument('--approved-sources',required=True,type=Path)
 s=sub.add_parser('planmove'); s.add_argument('capture',type=Path)
 m=sub.add_parser('move'); m.add_argument('plan',type=Path); m.add_argument('--reviewed-plan-sha256',required=True)
 for verb in ['verify','export']:
  v=sub.add_parser(verb); v.add_argument('plan',type=Path)
 a=p.parse_args()
 if a.command=='preserve-backup': result=preserve_backup()
 elif a.command=='capture': result=capture(a.baseline,a.approved_sources)
 elif a.command=='planmove': result=planmove(a.capture)
 elif a.command=='move': result=move(a.plan,a.reviewed_plan_sha256)
 elif a.command=='verify': result=verify(a.plan)
 else:
  plan,directory=read_plan(a.plan); receipt_path=HERE/('mirror-export-'+plan['captureId']+'.json')
  require(not receipt_path.exists(),'Mirror export already attempted; inspect its receipt and checkpoint')
  result={'task':'lazy-levels-20261009','exported':False,'studioWrites':False,'checkpoint':str(directory/'mirror-export')}
  try: result=export_sources(ROOT,verify(a.plan,True),directory/'mirror-export')
  except Exception as error:
   result['error']=str(error)
   raise
  finally: immutable(receipt_path,encoded(result))
 print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
