"""Hash-pinned minimal, tools-disabled review of installed admission changes."""
from pathlib import Path
import hashlib,json,difflib
task=Path('tools/level3_promotion_20261002')
out=task/'admission/claude-review';out.mkdir(exist_ok=True)
install=json.loads(Path('artifacts/level3-promotion-20261002/install/install-receipt.json').read_text())
assert len(install['sources'])==14
manifest=json.loads((task/'admission/candidate-manifest.json').read_text())['changes']
sources={}
for x in manifest:
 raw=Path(x['candidateFile']).read_bytes()
 assert hashlib.sha256(raw).hexdigest()==x['candidateSHA256']
 installed=next(y for y in install['sources'] if y['path']==x['path'])
 assert installed['sha256']==x['candidateSHA256'] and installed['editorMatch']
 sources[x['path']]=raw.decode()
gm=sources['ServerScriptService.GameManager']
base=(task/'admission/ServerScriptService.GameManager.Script.baseline.luau').read_text()
assert hashlib.sha256(base.encode()).hexdigest()==manifest[0]['baselineSHA256']
def compact(s):
 return '\n'.join(l for l in s.splitlines() if l.strip() and not l.lstrip(' +-').startswith('--'))
def frag(s,a,b):
 start=s.index(a);return s[start:s.index(b,start+len(a))]
diff=''.join(difflib.unified_diff(base.splitlines(True),gm.splitlines(True),n=3))
header='''Read-only focused integration review, no tools. Review ONLY two installed warmup changes plus supplied unchanged ownership/deadline context. Return <=350 words: verdict clear/material-fix/uncertain; concrete severity, function, trigger/effect, minimal fix. Omitted code is not reviewed. Do not disclose private reasoning. Distinguish source inference from observed tests.

Goal: existing 279-chunk Level6 opaque mesh kit may take130s+ (wait cap1200). Public3 queue/campaign/reserved entry MUST prewarm before generic60s Loading.Begin; preserve Level1/2 timing, DEV5/6 access, all routing IDs/rewards and Level2tube. Background shared Ensure owns concurrent original6DEV callers. Cannot cancel engine worker; late completion may serve future admissions but cannot resurrect cancelled parties. Ready checks exact revised SHA. Level3 RoundAdapter requires kit ready and never bakes.

Current root install receipt proves all14 scoped Source/editor CAS matches at2026-10-02T19:59:36Z, correct place131311258779917/universe10559217407. Only two sources reviewed here. Parent started Play separately; no live transport, engine/performance or multiplayer result supplied or claimed.

27 offline virtual-clock scenarios/86semantic checks execute exact helper, fresh Loading+Routing modules and GM fragments:130s cold thenfresh60;1/2 immediate andboot60;host cancel and9invalidations;2coldStudio stations1world;Level1 preempts waiting3;staleentryowner safe;1200timeout+latecompletion;Level2 floor beforewarm+same tube mode;trustedreserved selection+session pin;departed finalcarrier evidence;first provisional packet+snapshot wait until fullcohort. Tests are mocks, not engine evidence.

Unchanged context: Studio roundBusy existing check/set directly before Begin has no yield; when sharedkit ready, Await checks predicate/ready without yielding. Station warm polling owns host+epoch+party character identities and busy flag, but intentionally does not reserve global roundBusy for1200s. PublicCancel exception only warming host cancel. Existing runStation resets after launch returns. Campaign roundBusy already held by prior round; keep its completed floor until warm. Every Begin caller is in diff except Level1 DEV launch, unchanged/nolevel. prepareGroupLoading rechecks canAccessLevel and actual live rigs; marks InRound only afterBegin. Existing reserved setupPlayer appends each trusted arrival to destinationArrivalEvidence even if removed before staging. stageArrivingParty always RememberArrival all recorded evidence, Observe currententries, SelectArrivalSession, async finalcohort MemoryStore read, tracker.Apply subtract only observed departures, Routing.ArrivalDecision; loading-deadline branch admits only Final and full Expected>0 cohort. Those tracker functions themselves unchanged. New target uses SelectArrivalSession (ignores raw Level packet), pinsSessionId+Level throughwarm; reserved1/2 capture original boot deadline before newly-added discovery yields; reserved3 gets fresh60afterwarm. Noearlyfirstpacketadmit.

The input manifest pins all14 installed Source SHA256s; do not claim all14review.
Installed receipt SHA256 and reviewed sources:
'''
header+=hashlib.sha256(Path('artifacts/level3-promotion-20261002/install/install-receipt.json').read_bytes()).hexdigest()+'\n'
header+='\n'.join(x['path']+' '+x['candidateSHA256'] for x in manifest)+'\n'
runtime=(task/'admission/ServerScriptService.Round Loading Runtime.ModuleScript.baseline.luau').read_text()
blocks=[('Exact scoped GM v3 diff (blank/comment-only lines removed)',diff),
 ('Complete new singleton helper',sources['ServerScriptService.Level 3 Kit Warmup']),
 ('Unchanged failed-entry cleanup ownership excerpts (player reset body omitted)',
  frag(base,'recoverFailedEntry = function(', ' for _, player in ipairs(livePlayers(group)) do')
  +'\n-- omitted existing per-player entrycancel/loadfailed/reset notifications\n'
  +frag(base,' task.spawn(function()\n  if IS_RESERVED_ROUND_SERVER and not IS_STUDIO then\n   returnGroupToLobby(group)', '\nloadingRuntime = Loading.New(')),
 ('Unchanged Loading.Begin deadline core',frag(runtime,' function runtime:Begin(members)','  function attempt:SetMembers(group)')+'\n'+frag(runtime,'  attempt:SetMembers(members or {})','\n return runtime'))]
prompt=header+''.join('\n### '+name+'\n```luau\n'+compact(s)+'\n```\n' for name,s in blocks)
assert len(prompt)<17500,len(prompt)
(out/'prompt.md').write_text(prompt+'\n')
(out/'input-manifest.json').write_text(json.dumps({'reviewedChanges':manifest,'installedTaskSHA256s':install['sources'],'promptCharacters':len(prompt),'approximateTokens':round(len(prompt)/4),'mockScenarios':27,'semanticMockChecks':86,'scope':'Only warmup2 with unchanged recovery/loading excerpts; no live transport result'},indent=2)+'\n')
print(json.dumps({'characters':len(prompt),'approximateTokens':round(len(prompt)/4)}))
