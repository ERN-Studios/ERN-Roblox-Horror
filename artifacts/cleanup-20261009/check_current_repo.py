"""Read-only repository/hash/compile checks while the owner's Play is protected.

No Studio calls. This is explicitly not a current native parity or gameplay gate.
"""
import ast
from datetime import datetime,timezone
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
manifest_path=ROOT/'studio-sync-manifest.json'
manifest_raw=manifest_path.read_bytes()
manifest=json.loads(manifest_raw)
assert manifest['placeId']==131311258779917 and manifest['universeId']==10559217407
compiler=Path(os.environ['TEMP'])/'codex-luau-0.737/luau-compile.exe'
sources={}
rows=[]
for item in manifest['items']:
 if item['className'] not in {'Script','LocalScript','ModuleScript'}:
  continue
 path=ROOT/item['file']
 raw=path.read_bytes()
 sources[path]=raw
 source=raw.replace(b'\r\n',b'\n')
 sha=hashlib.sha256(source).hexdigest()
 compiled=subprocess.run([str(compiler),'--null',str(path)],capture_output=True,timeout=30)
 rows.append({'file':item['file'],'sha256':sha,'bytes':len(source),
  'manifestMatches':sha==item['sha256'] and len(source)==item['bytes'],
  'compilePass':compiled.returncode==0,'error':compiled.stderr.decode(errors='replace')})
python=[]
for path in sorted((ROOT/'tools').rglob('*.py')):
 try:
  ast.parse(path.read_text(encoding='utf-8-sig'))
  error=''
 except (SyntaxError,UnicodeError) as exc:
  error=str(exc)
 python.append({'file':path.relative_to(ROOT).as_posix(),'pass':not error,'error':error})
assert manifest_path.read_bytes()==manifest_raw,'Manifest changed during read-only checks; rerun'
assert all(path.read_bytes()==raw for path,raw in sources.items()),'Source changed during read-only checks; rerun'
result={'scope':'current repo only; owner Play preserved; fresh native parity pending',
 'studioCalls':0,'productionWrites':0,'compiler':str(compiler),
 'manifestRawSHA256':hashlib.sha256(manifest_raw).hexdigest(),'scripts':rows,'python':python}
label=sys.argv[1] if len(sys.argv)>1 else 'owner-play-repo-checks'
assert re.fullmatch(r'[A-Za-z0-9_-]+',label),'Invalid receipt label'
result['capturedAtUtc']=datetime.now(timezone.utc).isoformat()
output=Path(__file__).with_name(label+'.json')
output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
failures=[i for i in rows if not i['compilePass'] or not i['manifestMatches']]+[i for i in python if not i['pass']]
print(json.dumps({'mirrorCompile':f'{sum(i["compilePass"] for i in rows)}/{len(rows)}',
 'mirrorManifest':f'{sum(i["manifestMatches"] for i in rows)}/{len(rows)}',
 'pythonAST':f'{sum(i["pass"] for i in python)}/{len(python)}','failures':failures,
 'freshNativeParity':'pending owner return to Edit'}))
sys.exit(bool(failures))
