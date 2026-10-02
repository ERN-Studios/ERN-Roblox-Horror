"""Small actual Claude read-only review input; hash-check all twelve candidates."""
from pathlib import Path
import difflib, hashlib, json

task = Path('tools/level3_promotion_20261002')
out = task/'gameplay_boards/claude-review/focused'
out.mkdir(exist_ok=True)
catalog = Path('/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/before/scripts.json')
before = {x['path']:x for x in json.loads(catalog.read_text())}
layout = json.loads((task/'public3/layout-world-candidate-manifest-v2.json').read_text())
gameplay = json.loads((task/'gameplay_boards/candidate-manifest.json').read_text())['changes']
entries = [{'path':x['targetPath'],'file':x['candidatePath'],'sha':x['candidateHash'],'before':x['beforeHash']} for x in layout]
entries += [{'path':x['path'],'file':x['candidateFile'],'sha':x['candidateSHA256'],'before':x['baselineSHA256']} for x in gameplay]
sources = {}
for x in entries:
    raw = Path(x['file']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == x['sha'], x['path']
    if x['before']:
        assert before[x['path']]['sourceSha256'] == x['before'] and before[x['path']]['editorMatch']
    sources[x['path'].split('.')[-1]] = raw.decode()

def compact(s):
    return '\n'.join(l for l in s.splitlines() if l.strip() and not l.lstrip().startswith('--'))

def function(s, marker):
    a = s.index(marker)
    return s[a:s.index('\nend', a)+4]

def lines(s, start, end):
    return '\n'.join(s.splitlines()[start-1:end])

chunks = []
def block(name, s):
    chunks.append('\n### '+name+'\n```luau\n'+compact(s)+'\n```\n')

header = '''Read-only focused Roblox Luau integration review. No tools. Return <=450 words with verdict (clear/material fix/uncertain), concrete severity/function/trigger/effect/minimal fix. Do not give private internal reasoning. Omitted code is not verified. Source inference is not gameplay evidence.

Twelve candidates pinned below; only four integration excerpts supplied. Do not claim whole-twelve review. Revised Level6 kit enters public Level3; keep SelectedLevel=3, InRound, RoundActive, Escaped, rewards, L3Manager death key. Preserve Level5/6 previews. Visual precedes objective. Native Level6BlenderKit names intentional. Root handles backup and fresh Source/editor CAS.

Review separate concealed wall skin plus original invisible full-size collision wall, reactive material chunks, all8 new portal frames (only one frame has Light), client blackout/restoration, CD carrier clones/movement, and R4 original board transfer. New mesh chunks have Level3_KitVisualChunk=true; clone does not preserve event connections, so client lights and CD controllers explicitly sync cloned parts. World teardown destroys round objects/connections. Final ServiceDoor stays closed with authoritative escape trigger in front; no opening animation expected.

Board: actual original one combined TOP SUPPORTERS provider/ten-row renderer tracks recorded donations + utility products + storefront passes + private servers. Source search found no distinct buyer leaderboard. Preserve live subscriptions/provider/IDs/stores by direct nonnil reparent, no DataStore/monetization source changes. Root fresh Edit contains ServerLobby2904 descendants but no R4 model and no revision plaque; remove only exact source plaque creation for next runtime build. Original panel orientation is unrotated; Right SurfaceGui normal +X, size(.62,12.6,18). Fresh authored R4center(220,30,-760), target panel center= center+(-30,7.15,-35)=(190,37.15,-795), so face points toward centerX220. Historical board collision Xrelative[-33.05,-29.69], Z[-44,-26]; lower R4 wall X[-34.85,-33.55], Z[-60,-20]. Runtime occlusion/readability/replication unverified; evaluate source placement, do not invent a passed visual test. Current startup originalLobby then R4 once. Consider original lobby rebuild while R4 persists as edge case.

Local:4 syntax compiles;18 mocked cases pass (midpoint, clearance, CD chunks, wall fade,8frames, board transfer/rollback/reentry). Other agent reports8 compiles/1349 layout checks. No live gameplay/performance/multiplayer or board-renderer test.

Pinned candidate SHA256s:\n'''
header += '\n'.join(x['path']+' '+x['sha'] for x in entries)
s = sources['Level 3 Worn Party Visual Adapter']
block('Visual exact helper.Place plus portal excerpts (ordinary geometry omitted)', lines(s,58,163)+'\n'+lines(s,413,433))
s = sources['Level 3 Objective Controller']
block('Objective complete unlock/CD movement/configuration functions', '\n'.join(function(s,m) for m in ['unlockExit = function','local function configureRuntimeDiscPart','local function setDiscVisualCFrame']))
s = sources['Level 3 Lighting Controller']
block('Lighting complete chunk/frame capture/watch/ownership functions', '\n'.join(function(s,m) for m in ['local function syncKitFixtureVisuals','local function tryWatchKitFixture','local function clearKitFixtureWatchers','local function captureAuthoredRoomGlow','local function captureWorldLightBaseline','local function shouldOwnLighting']))
s = sources['Builder']
old = before['ServerScriptService.LobbyReimaginedPreview.Builder']['source']
block('R4 Builder complete actual scoped source diff', ''.join(difflib.unified_diff(old.splitlines(True),s.splitlines(True),fromfile='fresh original',tofile='candidate')))
s = before['ServerScriptService.TunnelLobbyBuilder']['source']
a = s.index('\t-- One renderer, three sources.')
b = s.index('\nlocal function makeStationMonitorPart',a)
block('Original board renderer subscriptions and teardown unchanged', s[a:b])

prompt = header+'\n'.join(chunks)
assert len(prompt) <= 24000, len(prompt)
(out/'prompt.md').write_text(prompt+'\n')
(out/'input-manifest.json').write_text(json.dumps({'candidateCount':len(entries),'promptCharacters':len(prompt),'approximateTokens':round(len(prompt)/4),'scope':'Four integration excerpts; whole twelve not reviewed','candidates':entries},indent=2)+'\n')
print(json.dumps({'promptCharacters':len(prompt),'approximateTokens':round(len(prompt)/4),'candidateCount':len(entries)}))
