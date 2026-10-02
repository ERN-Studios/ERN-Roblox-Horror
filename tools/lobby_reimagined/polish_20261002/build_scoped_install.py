"""Freeze narrowly scoped candidates from fresh Studio baselines; no Studio writes."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT / 'artifacts/lobby-polish-20261002'
HERE = Path(__file__).resolve().parent
sha = lambda raw: hashlib.sha256(raw).hexdigest()
baseline = json.loads((TASK/'root/baseline-critical.json').read_text())
old = (TASK/'root/Builder.live-baseline.luau').read_text()
needle = '\tmodel:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles"))'
assert old.count(needle)==1
hook = '''\tlocal bayPolish = require(script.Parent:WaitForChild("LobbyPolishBays")).Add(model, kit, manifest)
\trequire(script.Parent:WaitForChild("MaterialPolish")).Apply(model)
\trequire(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)
\tmodel:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles") + bayPolish:GetAttribute("AddedInstancedTriangles"))'''
builder = old.replace(needle, hook)
(TASK/'root/Builder.candidate.luau').write_text(builder)
specs = [
 ('ServerScriptService.LobbyReimaginedPreview.EndBlockades','ModuleScript',HERE/'clutter/EndBlockades.ModuleScript.candidate.luau',False),
 ('StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController','LocalScript',HERE/'bays/LobbyReimaginedQueueController.LocalScript.candidate.luau',False),
 ('ServerScriptService.LobbyReimaginedPreview.MaterialPolish','ModuleScript',HERE/'materials/MaterialPolish.ModuleScript.luau',True),
 ('ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays','ModuleScript',HERE/'bays/LobbyPolishBays.ModuleScript.candidate.luau',True),
 ('ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene','ModuleScript',HERE/'scene/LobbyPolishScene.ModuleScript.candidate.luau',True),
 ('ServerScriptService.LobbyReimaginedPreview.Builder','ModuleScript',TASK/'root/Builder.candidate.luau',False),
]
sources=[]
for path,kind,file,new in specs:
 raw=file.read_bytes(); sources.append(dict(path=path,className=kind,file=file.relative_to(ROOT).as_posix(),source=raw.decode(),sha256=sha(raw),new=new))
assets=json.loads((TASK/'materials/uploaded-assets.json').read_text())
contract=json.loads((TASK/'materials/candidate-manifest.json').read_text())['assetSpec']
for key,maps in contract['materials'].items():
 for role,row in maps.items():
  filename=f'{key}_{role}.png'
  assert sha((ROOT/'assets/models/lobby-material-polish-20261002'/filename).read_bytes())==row['pngSHA256']
  row['uri']=assets['http://127.0.0.1:8904/'+filename]
contract['sidewalkAtlas']['uri']=assets['http://127.0.0.1:8904/sidewalk_joint_atlas.png']
assert sha((ROOT/'assets/models/lobby-material-polish-20261002/sidewalk_joint_atlas.png').read_bytes())==contract['sidewalkAtlas']['pngSHA256']
catalog=dict(schema='lobby-polish-scoped-cas-v1',placeId=131311258779917,universeId=10559217407,groupId=1039373905,baseline=baseline,sources=sources,assets=contract)
(TASK/'root/install-catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
(TASK/'root/frozen-source-hashes.json').write_text(json.dumps([{k:r[k] for k in ['path','className','file','sha256','new']} for r in sources],indent=2)+'\n')
print(json.dumps([(r['path'],r['sha256']) for r in sources]))
