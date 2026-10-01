"""Build the explicit seven-script payload from captured Studio, never repo mirrors."""
import hashlib
import json
import pathlib

ROOT=pathlib.Path('artifacts/level6-entity-decor-20261001')
sources={item['path']: item for item in json.loads((ROOT/'native-before/scripts.json').read_text())}
prefix='ServerScriptService.Level 6 Systems.'
manifest=json.loads((ROOT/'candidates/entity/manifest.json').read_text())
scripts=[]
for item in manifest['scripts']:
    before=sources[item['path']]
    assert before['editorMatch']
    assert hashlib.sha256(before['source'].encode()).hexdigest()==item['expectedSourceSha256']
    after=(ROOT/'candidates/entity'/item['candidateRelativePath']).read_text()
    assert hashlib.sha256(after.encode()).hexdigest()==item['candidateSha256']
    scripts.append({'path':item['path'],'name':item['path'][len(prefix):],
        'new':False,'before':before['source'],'after':after})

path=prefix+'Level 6 Visual Adapter'
before=sources[path]['source']
anchor='local Dressing = require(script.Parent:WaitForChild("Level 6 Room Dressing"))'
assert before.count(anchor)==1
after=before.replace(anchor,anchor+'\nlocal Balloons = require(script.Parent:WaitForChild("Level 6 Balloon Dressing"))\nlocal Crayon = require(script.Parent:WaitForChild("Level 6 Crayon Wall Art"))')
anchor='            skin.Name = part.Name\n            skin.Color = part.Color'
assert after.count(anchor)==1
after=after.replace(anchor,'            -- Preserve the original SurfaceLight rectangle and emission pose.\n            -- Authored mesh children are anchored and retain their Blender world transforms.\n            skin.Size = part.Size\n            skin.CFrame = part.CFrame\n'+anchor)
anchor='            for _, child in ipairs(part:GetChildren()) do if child:IsA("Light") then child.Parent = skin end end'
assert after.count(anchor)==1
after=after.replace(anchor,'            for _, child in ipairs(part:GetChildren()) do\n                if child:IsA("Light") then\n                    -- A broad ceiling cone reaches wall art without adding daylight.\n                    if child:IsA("SurfaceLight") then child.Angle = math.max(child.Angle, 175) end\n                    child.Parent = skin\n                end\n            end')
anchor='    manifest.VisualCleanup = dressing and dressing.Cleanup\n    manifest.VisualReport = {Kit=counts, Dressing=dressing and dressing.Report}'
assert after.count(anchor)==1
after=after.replace(anchor,'    local balloons = Balloons.ApplyBalloons(manifest, helper)\n    local crayon = Crayon.Apply(manifest)\n'+anchor.replace('Dressing=dressing and dressing.Report','Dressing=dressing and dressing.Report, Balloons=balloons.Report, Crayon=crayon'))
scripts.append({'path':path,'name':'Level 6 Visual Adapter','new':False,'before':before,'after':after})
for name in ('Level 6 Balloon Dressing','Level 6 Crayon Wall Art'):
    path=prefix+name
    assert path not in sources
    after=(pathlib.Path('tools/level6_build/decor')/(name+'.ModuleScript.luau')).read_text()
    assert '__CRAYON_' not in after
    scripts.append({'path':path,'name':name,'new':True,'before':None,'after':after})

for item in scripts:
    item['beforeSHA256']=hashlib.sha256(item['before'].encode()).hexdigest() if item['before'] else None
    item['afterSHA256']=hashlib.sha256(item['after'].encode()).hexdigest()
payload={'placeId':131311258779917,'universeId':10559217407,'scripts':scripts}
(ROOT/'entity-decor-payload.json').write_text(json.dumps(payload))
review=[]
for item in scripts:
    candidate=ROOT/'candidates/combined'/(item['name']+'.ModuleScript.luau')
    candidate.parent.mkdir(exist_ok=True)
    candidate.write_text(item['after'])
    review.append({key:item[key] for key in ('path','name','new','beforeSHA256','afterSHA256')})
(ROOT/'scoped-script-manifest.json').write_text(json.dumps(review,indent=2)+'\n')
print(json.dumps(review,indent=2))
