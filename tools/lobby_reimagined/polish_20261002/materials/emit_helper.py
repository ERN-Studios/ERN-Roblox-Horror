"""Emit an asset/hash-pinned helper candidate. No Studio connection or upload."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
ASSETS=ROOT/'assets/models/lobby-material-polish-20261002'
RECORDS=ROOT/'artifacts/lobby-polish-20261002/materials'

def quote(value):
    raw=json.dumps(value,separators=(',',':'))
    assert ']====]' not in raw
    return '[====['+raw+']====]'

def main():
    material=json.loads((ASSETS/'manifest.json').read_text())
    base=json.loads((ROOT/'assets/models/lobby-reimagined-r4-20261001/manifest.json').read_text())
    proof=json.loads((RECORDS/'mesh-proof.json').read_text())
    spec={'materials':{},'sidewalkAtlas':{'pngSHA256':material['sidewalkAtlas']['pngSHA256']}}
    for key,item in material['materials'].items():
        spec['materials'][key]={}
        for role,record in item['maps'].items():
            spec['materials'][key][role]={'pngSHA256':record['pngSHA256'],
                'originalURI':'rbxassetid://'+base['materials'][key]['maps'][role]['assetId']}
    chunks={}
    for chunk in base['chunks']:
        value={k:chunk[k] for k in ('triangles','family','materialKey')}
        if chunk['sha256'] in chunks: assert chunks[chunk['sha256']]==value or chunks[chunk['sha256']]['triangles']==value['triangles']
        # Repeated threshold/floor texture chunks may share raw geometry. Their
        # material key is equal for PBR chunks; asset-only differences do not enter PBR handling.
        chunks.setdefault(chunk['sha256'],value)
        if chunk['name']=='SidewalkSection_atlas':spec['sidewalkAtlas']['chunkSHA256']=chunk['sha256']
    singles={row['sha256']:True for row in proof['rows'] if row['safeSingleSidedCandidate']}
    # Preserve continuous shell curvature and interactive/small silhouettes.
    # This narrower distance-LOD candidate can be enabled only after profiling.
    automaticFamilies={'ArchRib','CableTray','R4MonitorArm','R4BalloonBouquet','SidewalkSection'}
    automatic={row['sha256']:True for row in proof['rows'] if row['safeSingleSidedCandidate']
        and row['family'] in automaticFamilies and row['triangles']>=200}
    text=(HERE/'MaterialPolish.template.luau').read_text()
    for token,value in [('__ASSET_SPEC__',spec),('__CHUNK_SPEC__',chunks),
        ('__SINGLE_SIDED_SPEC__',singles),('__AUTOMATIC_SPEC__',automatic)]:
        assert text.count(token)==1
        text=text.replace(token,quote(value))
    candidate=HERE/'MaterialPolish.ModuleScript.luau';candidate.write_text(text)
    catalog={'schema':'lobby-material-polish-helper-candidate-v1','sourcePath':'ServerScriptService.LobbyReimaginedPreview.MaterialPolish',
        'sourceFile':candidate.relative_to(ROOT).as_posix(),'class':'ModuleScript','sourceBytes':len(text.encode()),
        'sourceSHA256':hashlib.sha256(text.encode()).hexdigest(),'assetSpec':spec,
        'assetsPinned':False,'existingRuntimeBakeSHA256':'1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28',
        'baselineManifestSHA256':material['baselineManifestSHA256'],'singleSidedHashCount':len(singles),
        'automaticHashCount':len(automatic),'optimizationDefault':False,
        'builderIntegration':'Call require(script.Parent.MaterialPolish).Apply(model) after EndBlockades populates BlenderVisuals and before Ready=true/model.Parent=workspace.',
        'requiredChildren':['StaticPBRMaterials (owned Folder, Ready=true, exactly 3 owned SurfaceAppearance templates)',
            'SidewalkAtlas (owned StringValue, Value=published asset ID, PNG_SHA256 pinned)'],
        'playValidationRequired':['matching PBR/joint counts','night normal-walk lane readability','shop-wall concrete close view',
            'upper furniture tint and silhouette','drain legibility','texture permissions/loading on real client',
            'GPU/frame time before and after optional optimization','backface silhouette views from all occupied queue entrances']}
    (RECORDS/'candidate-manifest.json').write_text(json.dumps(catalog,indent=2)+'\n')
    print(json.dumps({k:catalog[k] for k in ('sourceSHA256','sourceBytes','singleSidedHashCount','automaticHashCount')}))

if __name__=='__main__':main()
