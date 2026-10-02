"""Prepare three scoped changes, while guarding all five current live Sources.
No Studio or Git mutation. Original installer/receipts stay immutable.
"""
from pathlib import Path
import ast,difflib,hashlib,json
TASK=Path(__file__).resolve().parent
ROOT=TASK.parents[1]
OUT=TASK/'install'
sha=lambda b:hashlib.sha256(b).hexdigest()
module=ast.parse((TASK/'build_delta_install.py').read_text())
helpers=[node for node in module.body if isinstance(node,ast.FunctionDef) and node.name in ['replacements','lua_string']]
env={'difflib':difflib}
exec(compile(ast.Module(body=helpers,type_ignores=[]),'frozen delta helpers','exec'),env)
replacements,lua_string=env['replacements'],env['lua_string']
original=json.loads((OUT/'source-manifest.json').read_text())
fresh=json.loads((TASK/'prewrite-incremental-live-five.json').read_text())
assert fresh['placeId']==131311258779917 and fresh['universeId']==10559217407 and fresh['isRunning'] is False
live={row['path']:row for row in fresh['sources']}
ai=json.loads((TASK/'finale/candidate-manifest-v3-ai.json').read_text())['changes'][0]
reader=json.loads((TASK/'reader/candidate-manifest.v4.json').read_text())
visual=json.loads((TASK/'device/font-refinement-manifest.json').read_text())
latest={ai['path']:(Path(ai['candidateFile']),ai['candidateSHA256']),
        reader['path']:(ROOT/reader['candidatePath'],reader['candidateHash']),
        visual['path']:(Path(visual['candidateFile']),visual['candidateSHA256'])}
rows,final=[],[]
for old in original['changes']:
    before=Path(old['candidateFile']).read_bytes()
    rec=live[old['path']]
    assert rec['editorMatch'] and rec['class']==old['className']
    assert sha(before)==old['candidateSHA256']==rec['sourceSHA256']==rec['editorSHA256']
    assert len(before)==rec['sourceBytes']==rec['editorBytes']
    file,digest=latest.get(old['path'],(Path(old['candidateFile']),old['candidateSHA256']))
    after=file.read_bytes();assert sha(after)==digest
    row=dict(path=old['path'],className=old['className'],baselineSHA256=sha(before),
        editorSHA256=rec['editorSHA256'],baselineBytes=len(before),candidateSHA256=digest,
        candidateBytes=len(after),baselineFile=str(Path(old['candidateFile'])),candidateFile=str(file.resolve()),
        write=before!=after,patches=replacements(before.decode(),after.decode()) if before!=after else [])
    rows.append(row)
    final.append({**old,'candidateFile':str(file.resolve()),'candidateSHA256':digest,'candidateBytes':len(after),
        'incrementalBaselineSHA256':row['baselineSHA256'], 'changedInFollowup':row['write']})
assert len(rows)==5 and sum(row['write'] for row in rows)==3
chunks=[]
for row in rows:
    fields=['path','className','baselineSHA256','editorSHA256','candidateSHA256']
    parts=[field+'='+lua_string(row[field]) for field in fields]
    parts += [f'baselineBytes={row["baselineBytes"]}',f'candidateBytes={row["candidateBytes"]}',
              'write='+('true' if row['write'] else 'false')]
    parts.append('patches={'+','.join('{before='+lua_string(p['before'])+',after='+lua_string(p['after'])+'}'
        for p in row['patches'])+'}')
    chunks.append('{'+','.join(parts)+'}')
template=(TASK/'delta-install.template.luau').read_text()
start=template.index('for _,row in ipairs(rows) do\n    local object = targets[row.path]\n    SES:UpdateSourceAsync')
end=template.index('\nverifyAll()\nlocal receipt',start)
mutation=template[start:end]
mutation=mutation.replace('    local object = targets[row.path]', '    if row.write then\n    local object = targets[row.path]',1)
assert mutation.endswith('\nend')
mutation=mutation[:-4]+'\n    end\nend'
template=template[:start]+mutation+template[end:]
template=template.replace('sourceCount=#rows,sceneChanged=false,','sourceCount=#rows,writeCount=3,sceneChanged=false,')
installer=template.replace('__ROWS__','{'+',\n'.join(chunks)+'}')
payload=installer.encode();assert len(payload)<65536
target=OUT/'install-three-incremental.luau';target.write_bytes(payload)
manifest=dict(task='level3-finale-player-20261002',placeId=131311258779917,universeId=10559217407,
    prewriteCaptureAtUTC=fresh['capturedAtUTC'],guardedSourceCount=5,writeCount=3,
    installerFile=str(target),installerSHA256=sha(payload),installerBytes=len(payload),
    changes=[{k:v for k,v in row.items() if k!='patches'}|{'patchCount':len(row['patches'])} for row in rows])
(OUT/'incremental-source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(OUT/'final-source-manifest.json').write_text(json.dumps(dict(task=manifest['task'],sourceCount=5,
    status='Expected final five Sources; actual final CAS receipt/export required for parity claim',
    originalPrewriteCaptureAtUTC=original['prewriteCaptureAtUTC'],followupCaptureAtUTC=fresh['capturedAtUTC'],
    changes=final),indent=2)+'\n')
print(json.dumps({k:v for k,v in manifest.items() if k!='changes'}))
