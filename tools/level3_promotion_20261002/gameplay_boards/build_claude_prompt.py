"""Compose a bounded, explicitly supplied read-only integration review input."""
from pathlib import Path
import difflib, hashlib, json, re

task=Path('tools/level3_promotion_20261002')
out=task/'gameplay_boards/claude-review'
out.mkdir(exist_ok=True)
catalog=Path('/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/before/scripts.json')
before={x['path']:x for x in json.loads(catalog.read_text())}
layout=json.loads((task/'public3/layout-world-candidate-manifest-v2.json').read_text())
gameplay=json.loads((task/'gameplay_boards/candidate-manifest.json').read_text())['changes']
entries=[{'path':x['targetPath'],'file':x['candidatePath'],'sha':x['candidateHash'],'class':x['className'],'before':x['beforeHash'],'operation':x['operation']} for x in layout]
entries += [{'path':x['path'],'file':x['candidateFile'],'sha':x['candidateSHA256'],'class':x['class'],'before':x['baselineSHA256'],'operation':'edit'} for x in gameplay]
sources={}
for x in entries:
    raw=Path(x['file']).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==x['sha'],x['path']+' manifest drift'
    if x['before']:
        assert before[x['path']]['sourceSha256']==x['before'] and before[x['path']]['editorMatch'],x['path']+' baseline drift'
    sources[x['path'].split('.')[-1]]=raw.decode()

def compact(s):
    return '\n'.join(line for line in s.splitlines() if line.strip() and not line.lstrip().startswith('--'))

def function(s,marker):
    a=s.index(marker); b=s.index('\nend',a)+4
    return s[a:b]

def lines(s,start,end):
    return '\n'.join(s.splitlines()[start-1:end])

chunks=[]
def block(name,text):
    chunks.append('\n## '+name+'\n```luau\n'+compact(text)+'\n```\n')

header='''Read-only focused review of twelve pinned Roblox Luau candidates. Use only supplied facts/code; no tools. Maximum 650 words. Report material defects with severity, exact path/function, trigger, effect and minimal scoped fix. Distinguish source inference from observed test facts. Do not provide a wholesale replacement, deploy/publish, treat omitted code as verified, or claim gameplay/performance/multiplayer passes.

Intent: promote revised Level 6 map/layout/world/visual behavior into the public Level 3 campaign identity, keeping public SelectedLevel=3, RoundActive, InRound, Escaped, BeingChased, Level 3 State/Remotes/Generated World and public completion/reward/Back-to-Lobby settlement. Level 5/6 preview access/namespace and native Level6BlenderKit/Level6BlenderSourceRevision20261001 asset schema remain intact. Public origin remains (6200,24,0). Keep workspace compatibility Elevator/DoorL/DoorR/ElevatorSpawn/MazeStart and Level3_Level2ExitTube slide-resume attributes for Level2 continuation. Promotion calls visual application before public objective/music/hiding/controllers, and visual cleanup before world teardown.

Original TOP SUPPORTERS is one combined recorded donations/utility products/storefront pass/private-server purchase board. Fresh active-source search found no independent buyer ranking; buyer references are receipt/import bookkeeping. Reparent actual original runtime board into R4, preserve title/ten-row renderer/subscriptions/provider/IDs/persistent stores, and remove only exact mounted plaque 'LOBBY REVISION · DEV'. No DataStore or monetization Source changes. R4 can be reused; inspect full original-lobby rebuild duplication hazard rather than assuming current startup-only use proves all resets.

Fresh pinned Studio session c1e8b040-e549-408a-8a5b-7fe6905c2d55, place131311258779917/universe10559217407. Existing edited scripts have exact Source/editor parity in fresh before/scripts.json; new balloon/crayon modules must be absent before scoped creation. Root owns full native backup, fresh in-write CAS, native integration and publication. This review cannot inspect Studio. Candidate selection is the requested layout-world-candidate-manifest-v2 + gameplay_boards/candidate-manifest; separately named final Visual manifest/diff is stale and not a baseline. Supplied body hashes match all twelve selected manifests.

Verified local facts: all four gameplay candidates syntax-compiled and 18 extracted-function mocked cases passed, including strict midpoint/equality/living exclusion, second living participant blocking finale spawn candidates, fixed28, authored CD chunks, separate reactive concealed-wall fade, all eight portal frame captures/chunk synchronization, original board translation/rollback/re-entry. Layout agent reports eight syntax compiles and 1349 deterministic layout fixtures; no live gameplay/physics/board provider/performance pass is inferred. Large whole sources are deliberately omitted; code below is complete critical functions or explicitly labelled excerpts. Review namespace/authority/boarding/skin+frame/controller and expected-diff integration risks.

Pinned paths/classes/hashes:\n'''
header += '\n'.join(f"{x['operation']} {x['class']} {x['path']} baseline/editor={x['before']} candidate={x['sha']}" for x in entries)

s=sources['Level 3 Worn Party Visual Adapter']
block('Visual Adapter exact imports/helper/public-participant/hide pass plus CD/portal/dressing excerpts; ordinary room skinning omitted',lines(s,1,210)+'\n'+lines(s,330,456))
s=sources['Level 3 Round Adapter']
block('Round Adapter imports and complete manager binding/build/cleanup',lines(s,1,43)+'\n'+ '\n'.join(function(s,m) for m in ['local function bindManagerToHunt','function Adapter.Cleanup','function Adapter.Build']))
s=sources['Level 3 Configuration']
block('Configuration identity/layout/finale exact excerpts',lines(s,1,130)+'\n'+ '\n'.join(l for l in s.splitlines() if any(w in l for w in ['FinalHall','FinaleApproach','SpawnMinimum','WorldName','StateFolder','RemotesFolder','GeneratorVersion','L3Manager'])))
s=sources['Level 3 Layout Generator']
block('Layout namespace/dependencies and gateway/validation exact excerpts',lines(s,1,70)+'\n'+ '\n'.join(l for l in s.splitlines() if any(w in l for w in ['Gateway','InsertedRoom','L3Layout','L3_','L3-','FinalHall','RoomsPerDistrict','LoopEdgesPerDistrict'])))
s=sources['Level 3 World Builder']
block('World build complete manifest result and arrival/slide exact excerpts',lines(s,2270,2324)+'\n'+ '\n'.join(l for l in s.splitlines() if any(w in l for w in ['ArrivalTube','Level2ExitTube','SlideResume','ElevatorSpawn','MazeStart','DoorL','DoorR','ArrivalRoomHeight','FinalHallSpawnProgress','FinalHallHalfwayProgress'])))
s=sources['Level 3 Worn Party Room Dressing']
block('Room Dressing imports/public prompt and cleanup exact excerpts',lines(s,1,22)+'\n'+lines(s,262,319)+'\n'+lines(s,373,429))
s=sources['Level 3 Balloon Dressing']
block('Balloon module imports and exact ApplyBalloons authority/tag excerpts; placement loop omitted',lines(s,1,18)+'\n'+lines(s,173,191)+'\n'+ '\n'.join(l for l in s.splitlines() if any(w in l for w in ['Level3','Level6','GetAttribute','SetAttribute','CanCollide','CanQuery','return {'])))
s=sources['Level 3 Crayon Wall Art']
block('Crayon module imports and exact Apply authority/native asset/tag excerpts; placement loop omitted',lines(s,1,14)+'\n'+lines(s,61,88)+'\n'+ '\n'.join(l for l in s.splitlines() if any(w in l for w in ['Level3','Level6','GetAttribute','SetAttribute','CanCollide','CanQuery','return {'])))
s=sources['Level 3 Mall Manager AI Controller']
block('Manager AI complete public gates/finale/noise functions', '\n'.join(function(s,m) for m in ['local function validRound','local function livingPlayer','local function currentSpeed','local function nearestLivingPlayer','local function eligibleSpawnPlayers','local function chooseFinalHallSpawn','function Controller.ReportNoise'])+'\n'+ '\n'.join(l for l in s.splitlines() if 'DeathAdvice.Mark' in l))
s=sources['Level 3 Objective Controller']
block('Objective complete public gates/midpoint/CD movement/escape and unlock', '\n'.join(function(s,m) for m in ['local function validSession','local function validPlayer','local function updateFinalHallChase','local function configureRuntimeDiscPart','local function setDiscVisualCFrame','local function fireEscapeStatus','unlockExit = function','local function escapePlayer'])+'\n'+ '\n'.join(l for l in s.splitlines() if 'setDiscVisualCFrame(' in l or 'TeamObjectives' in l))
s=sources['Level 3 Lighting Controller']
block('Lighting complete material-chunk/frame capture and ownership functions; bindWorld first excerpt', '\n'.join(function(s,m) for m in ['local function tryWatchCeilingBounce','local function syncKitFixtureVisuals','local function tryWatchKitFixture','local function clearKitFixtureWatchers','local function captureAuthoredRoomGlow','local function captureWorldLightBaseline','local function shouldOwnLighting'])+'\n'+ '\n'.join(function(s,'local function bindWorld').splitlines()[:41])+'\n'+ '\n'.join(l for l in s.splitlines() if 'local LEVEL' in l or 'GetAttributeChangedSignal("SelectedLevel")' in l or 'GetAttributeChangedSignal("InRound")' in l))
s=sources['Builder']
base=before['ServerScriptService.LobbyReimaginedPreview.Builder']['source']
diff=''.join(difflib.unified_diff(base.splitlines(True),s.splitlines(True),fromfile='fresh R4 Builder',tofile='candidate R4 Builder'))
block('R4 Builder exact actual source diff (all edits)',diff)
old=before['ServerScriptService.TunnelLobbyBuilder']['source']
ix=old.index('\t-- One renderer, three sources.')
block('Original combined board renderer subscriptions (unchanged exact excerpt)',old[ix:old.index('\nlocal function makeStationMonitorPart',ix)]+'\n'+function(old,'function Builder.Build')[:650])

prompt=header+'\n'.join(chunks)
assert len(prompt)<85000, len(prompt)
(out/'prompt.md').write_text(prompt+'\n')
(out/'input-manifest.json').write_text(json.dumps({'sourceCatalog':str(catalog),'candidateCount':len(entries),'scope':'Critical functions/labelled excerpts; full bodies deliberately omitted','promptCharacters':len(prompt),'approximateTokens':round(len(prompt)/4),'candidates':entries},indent=2)+'\n')
print(json.dumps({'promptCharacters':len(prompt),'approximateTokens':round(len(prompt)/4),'candidateCount':len(entries),'file':str(out/'prompt.md')}))
