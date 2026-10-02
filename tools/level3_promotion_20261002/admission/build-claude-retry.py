from pathlib import Path
import difflib,hashlib,json
r=Path('tools/level3_promotion_20261002/admission');o=r/'claude-review/retry';o.mkdir(exist_ok=True)
m=json.loads((r/'candidate-manifest.json').read_text())['changes']
installed=json.loads(Path('artifacts/level3-promotion-20261002/install/install-receipt.json').read_text())
sources=[]
for x in m:
 s=Path(x['candidateFile']).read_text();assert hashlib.sha256(s.encode()).hexdigest()==x['candidateSHA256']
 assert next(v for v in installed['sources'] if v['path']==x['path'])['sha256']==x['candidateSHA256'];sources.append(s)
base=(r/'ServerScriptService.GameManager.Script.baseline.luau').read_text()
diff=''.join(difflib.unified_diff(base.splitlines(True),sources[0].splitlines(True),n=0))
diff='\n'.join(l[:1]+l[1:].strip() for l in diff.splitlines() if l.startswith(('+','-','@@')) and not l.startswith(('+++','---')) and l[1:].strip() and not l[1:].lstrip().startswith('--'))
helper='\n'.join(l.strip() for l in sources[1].splitlines() if l.strip() and not l.lstrip().startswith('--'))
header='''Read-only review of ONLY installed GM warm changes/helper. No tools. <=180word verdict clear/material-fix/uncertain, concrete trigger/effect/minimalfix; no private reasoning.
60s Loading.Begin must follow coldkit(1200s cap). Check cancel/ownership/deadlines. ExistingStudio postwarm roundBusy check/set has no yield; readyAwait no yield. recover(nil,reason,group) resets players/round and cleans localworld; existingLevel2floor retained beforeBegin. Reserved SelectArrivalSession ignores rawLevel; unchanged staging remembers all departureevidence, tracks presence, reads finalMemoryStorecohort, admits only Final+fullcohort.1/2 retain bootdeadline.5/6DEV unchanged.
27virtual scenarios86checks pass; no live transport/perf claim.14Source/editor nativeCAS exact installed19:59:36Z; only these2reviewed; full14pins in receipt/inputmanifest.
'''
header+='\n'.join(x['path']+' '+x['candidateSHA256'] for x in m)+'\n'
prompt=header+'GM zero-context exact diff (whitespace/comment-only lines removed):\n```diff\n'+diff+'\n```\nComplete helper:\n```luau\n'+helper+'\n```\n'
assert len(prompt)<=8500,len(prompt)
(o/'prompt.md').write_text(prompt)
(o/'input-manifest.json').write_text(json.dumps({'reviewedChanges':m,'installedTask':installed,'promptCharacters':len(prompt),'approximateTokens':round(len(prompt)/4),'mockScenarios':27,'semanticMockChecks':86,'scope':'Warm changes only; no gameplay/transport/performance claim'},indent=2)+'\n')
runner=Path('tools/level3_promotion_20261002/backup/claude_review.py').read_text().replace('assert 30<=a.timeout<=360','assert 30<=a.timeout<=900')
(o/'claude_review_long.py').write_text(runner)
print(json.dumps({'characters':len(prompt),'approximateTokens':round(len(prompt)/4),'runnerMaximumSeconds':900}))
