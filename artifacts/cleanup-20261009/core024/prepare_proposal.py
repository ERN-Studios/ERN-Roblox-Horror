"""Create proposal-only copies. Never writes canonical files or contacts Studio."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
MODULE = ROOT / 'ServerScriptService/LobbyReimaginedPreview/EndBlockades.ModuleScript.lua'
BUILDER = ROOT / 'ServerScriptService/LobbyReimaginedPreview/Builder.ModuleScript.lua'


def rewrite(source, replacements):
    for old, new in replacements:
        assert source.count(old) == 1, (old, source.count(old))
        source = source.replace(old, new)
    return source


module_before = MODULE.read_text(encoding='utf-8')
module_candidate = rewrite(module_before, [
    ('function Module.Emit(plan, center, visuals, collisions, lighting, place)',
     'function Module.Emit(plan, center, visuals, collisions, lighting, place, includeFurniture)'),
    ('\tassert(plan.statistics.uniqueNewMeshes == 0 and plan.statistics.archCornerFailures == 0)',
     '\tassert(plan.statistics.uniqueNewMeshes == 0 and plan.statistics.archCornerFailures == 0)\n'
     '\tassert(includeFurniture == nil or type(includeFurniture) == "boolean", "Invalid furniture placement option")'),
    ('\tfor _, item in ipairs(plan.placements) do',
     '\tif includeFurniture ~= false then\n\tfor _, item in ipairs(plan.placements) do'),
    ('\tend\n\tfor _, item in ipairs(plan.colliders) do',
     '\tend\n\tend\n\tfor _, item in ipairs(plan.colliders) do'),
    ('\tfolder:SetAttribute("AddedInstancedTriangles", plan.statistics.extraInstancedTriangles)',
     '\tfolder:SetAttribute("AddedInstancedTriangles", includeFurniture == false and 0 or plan.statistics.extraInstancedTriangles)\n'
     '\tif includeFurniture == false then folder:SetAttribute("SkippedFurnitureInstances", #plan.placements) end'),
    ('function Module.Add(model, kit, manifest)',
     'function Module.Add(model, kit, manifest, includeFurniture)'),
    ('assert(model:FindFirstChild("PreviewLighting")), place)',
     'assert(model:FindFirstChild("PreviewLighting")), place, includeFurniture)'),
])
builder_before = BUILDER.read_text(encoding='utf-8')
builder_candidate = rewrite(builder_before, [
    ('local endPiles = require(script.Parent:WaitForChild("EndBlockades")).Add(model, kit, manifest)',
     'local endPiles = require(script.Parent:WaitForChild("EndBlockades")).Add(model, kit, manifest, false)'),
    ('\t\tlocal removed = 0',
     '\t\tlocal removed = piles and (piles:GetAttribute("SkippedFurnitureInstances") or 0) or 0'),
])

for filename, body in {
    'EndBlockades.before.luau': module_before,
    'EndBlockades.candidate.luau': module_candidate,
    'Builder.before.luau': builder_before,
    'Builder.candidate.luau': builder_candidate,
}.items():
    (OUT / filename).write_text(body, encoding='utf-8')

manifest = {
    'scope': 'proposal only; no existing source or native mutation',
    'before': {str(p.relative_to(ROOT)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in (MODULE, BUILDER)},
    'candidate': {filename: hashlib.sha256(body.encode('utf-8')).hexdigest()
                  for filename, body in [('EndBlockades.candidate.luau', module_candidate),
                                         ('Builder.candidate.luau', builder_candidate)]},
    'changes': [
        'Opt-in includeFurniture=false only at the active Builder Add call',
        'Public Emit/Add default retains the complete authoring placements',
        'Keep PLAN, colliders, lenses, empty folder, historical AddedFurnitureInstances=219',
        'Skip triangle count=0; record skipped count=219; preserve cumulative EndFurnitureRemoved',
        'MaterialPolishFurnitureCount counts actually applied tints and may become zero; record this intentional diagnostic delta during fresh lobby verification',
    ],
    'requiredNativeGate': 'native-fixture.luau plus fresh full lobby before/after flow; no gameplay safety claim from this source proposal',
}
(OUT / 'candidate-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print('proposal files ready')
