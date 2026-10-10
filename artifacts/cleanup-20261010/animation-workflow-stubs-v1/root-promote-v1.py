"""Root-owned two-file CAS retirement; actual installed port and scoped recovery."""
from pathlib import Path
import argparse, hashlib, json, subprocess, sys
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
PRIVATE=ROOT/'.git/mongotv-cleanup-20261010/animation-stubs-v1'
SHA=lambda raw:hashlib.sha256(raw).hexdigest()
def save(path,raw):
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb') as stream:assert stream.write(raw)==len(raw)
parser=argparse.ArgumentParser();parser.add_argument('--checkpoint',action='store_true');parser.add_argument('--promote',action='store_true');args=parser.parse_args()
assert args.checkpoint!=args.promote
freeze=json.loads((HERE/'frozen-pins-v1.json').read_bytes())
for row in freeze['files']:
 raw=(ROOT/row['file']).read_bytes();assert len(raw)==row['rawBytes'] and SHA(raw)==row['rawSHA256'],row['file']
proposal=json.loads((HERE/'proposal-v1/proposal.json').read_bytes())
assert json.loads((HERE/'root-before-port-v1.json').read_bytes())['pass']
for row in proposal['retainedInputsAndReceipts']:
 assert SHA((ROOT/row['file']).read_bytes())==row['rawSHA256'],row['file']
before={r['file']:(HERE/'proposal-v1/before'/r['file']).read_bytes() for r in proposal['files']}
after={r['file']:(HERE/'proposal-v1/candidate'/r['file']).read_bytes() for r in proposal['files']}
for row in proposal['files']:
 assert SHA(before[row['file']])==row['beforeSHA256'] and SHA(after[row['file']])==row['candidateSHA256']
 assert (ROOT/row['file']).read_bytes()==before[row['file']],row['file']
if args.checkpoint:
 assert not PRIVATE.exists()
 for file in [*before,'CLEANUP_PLAN.md','CLEANUP_RESULTS.md']:
  save(PRIVATE/'before'/file,(ROOT/file).read_bytes())
 save(PRIVATE/'index.before',(ROOT/'.git/index').read_bytes())
 save(PRIVATE/'head.before',subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT))
 print(json.dumps({'pass':True,'checkpointed':4,'productionWrites':0}))
else:
 assert PRIVATE.exists() and not (HERE/'root-promotion-result-v1.json').exists()
 result={'schema':'mongotv-animation-stubs-root-promotion-v1','pass':False,'nativeWrites':0,'manifestWrites':0,'indexWrites':0,'rollback':{},'files':proposal['files']}
 attempted=[]
 try:
  for file in before:
   assert (PRIVATE/'before'/file).read_bytes()==before[file]
   assert (ROOT/file).read_bytes()==before[file],'Immediate file CAS: '+file
   attempted.append(file)
   with (ROOT/file).open('wb') as stream:assert stream.write(after[file])==len(after[file])
   assert (ROOT/file).read_bytes()==after[file]
  run=subprocess.run([sys.executable,'-B',str(HERE/'prepare_and_verify.py'),'--verify-installed','--receipt',str(HERE/'root-installed-port-v1.json')],cwd=ROOT,capture_output=True,timeout=90)
  result['port']={'exitCode':run.returncode,'stdout':run.stdout.decode(errors='replace'),'stderr':run.stderr.decode(errors='replace')}
  assert run.returncode==0,'Installed contract failed'
  assert all((ROOT/file).read_bytes()==raw for file,raw in after.items())
  result['pass']=True;result['removedSourceBytes']=proposal['removedBytes']
  result['installedPortSHA256']=SHA((HERE/'root-installed-port-v1.json').read_bytes())
 except BaseException as error:
  result['error']=repr(error)
  for file in reversed(attempted):
   try:
    current=(ROOT/file).read_bytes()
    if current==before[file]:result['rollback'][file]='already original'
    elif current==after[file]:
     with (ROOT/file).open('wb') as stream:assert stream.write(before[file])==len(before[file])
     assert (ROOT/file).read_bytes()==before[file];result['rollback'][file]='exact original restored'
    else:result['rollback'][file]='foreign/partial bytes preserved; reconcile'
   except BaseException as recovery:result['rollback'][file]='unreadable/recovery failure: '+repr(recovery)
 result['attemptedToolWrites']=len(attempted)
 result['limits']='Two already-retired/unimportable local authoring exporters; originals fully archived. Scoped CAS/readback is not process-wide atomicity. No native asset/cache/runtime feature removal or performance gain.'
 save(HERE/'root-promotion-result-v1.json',(json.dumps(result,indent=2)+'\n').encode())
 print(json.dumps({'pass':result['pass'],'localTools':len(attempted),'removedSourceBytes':result.get('removedSourceBytes'),'rollback':result['rollback']}))
 raise SystemExit(0 if result['pass'] else 1)
