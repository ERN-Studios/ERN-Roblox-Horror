"""Minimal finale-only overlap alignment against the actual installed v2 receipt."""
from pathlib import Path
import difflib, hashlib, json
r=Path(__file__).resolve().parent
repo=r.parents[2]
sha=lambda b:hashlib.sha256(b).hexdigest()
receipt=json.loads((repo/'artifacts/level3-finale-player-20261002/install-receipt.json').read_text())
path='ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller'
installed=next(row for row in receipt['sources'] if row['path']==path)
b=(r/'Level 3 Mall Manager AI Controller.v2.candidate.luau').read_text()
assert sha(b.encode())==installed['sourceSHA256']==installed['editorSHA256']
old='''local function spawnOverlapParams(records: {any}): OverlapParams
\tlocal params = OverlapParams.new()
\tparams.FilterType = Enum.RaycastFilterType.Exclude
\tlocal ignored = {}
\tfor _, record in ipairs(records) do table.insert(ignored, record.Character) end
\tparams.FilterDescendantsInstances = ignored'''
new='''local function spawnOverlapParams(records: {any}, ignoreAllAvatars: boolean?): OverlapParams
\tlocal params = OverlapParams.new()
\tparams.FilterType = Enum.RaycastFilterType.Exclude
\tlocal ignored = {}
\tif ignoreAllAvatars then
\t\t-- Match navigation's current-avatar exclusions: a retired round life
\t\t-- cannot veto the fixed reveal with a body the Manager already walks through.
\t\tfor _, player in ipairs(Players:GetPlayers()) do
\t\t\tif player.Character then table.insert(ignored, player.Character) end
\t\tend
\telse
\t\tfor _, record in ipairs(records) do table.insert(ignored, record.Character) end
\tend
\tparams.FilterDescendantsInstances = ignored'''
assert b.count(old)==1
c=b.replace(old,new)
old_call='if not spawnVolumeFits(position, spawnOverlapParams(records)) then return nil end'
new_call='if not spawnVolumeFits(position, spawnOverlapParams(records, true)) then return nil end'
assert c.count(old_call)==1
c=c.replace(old_call,new_call)
target=r/'Level 3 Mall Manager AI Controller.v3.candidate.luau'
target.write_text(c)
(r/'Level 3 Mall Manager AI Controller.v3.diff').write_text(''.join(difflib.unified_diff(
    b.splitlines(True),c.splitlines(True),fromfile='Actual installed v2 '+path,tofile='Finale-only overlap candidate v3')))
manifest={'changes':[{'path':path,'class':'ModuleScript','new':False,
    'baselineSHA256':sha(b.encode()),'editorSHA256':installed['editorSHA256'],
    'candidateSHA256':sha(c.encode()),'candidateFile':str(target),
    'baselineFile':str(r/'Level 3 Mall Manager AI Controller.v2.candidate.luau'),
    'baselineMeasuredAtUTC':receipt['installedAtUTC'],
    'baselineEvidence':'Actual Studio install Source/editor receipt; parent must freshly recheck Edit before CAS',
    'freshEditCASRequired':True}]}
(r/'candidate-manifest-v3-ai.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest))
