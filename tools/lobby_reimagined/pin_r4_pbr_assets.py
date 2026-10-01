"""Pin the exact nine upload-result IDs to their verified R4 PNG maps.

Accepts a saved URL-to-rbxassetid map returned by Studio upload_image. This is
local artifact preparation only; asset access/rendering still needs Play proof.
"""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PACKAGE=ROOT/'assets/models/lobby-reimagined-r4-20261001'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('upload_mapping',type=Path);args=p.parse_args()
 supplied=args.upload_mapping.read_bytes();mapping=json.loads(supplied)
 keys=('tunnel_concrete','asphalt_road','sidewalk_concrete');roles=('color','normal','roughness')
 expected={f'http://127.0.0.1:8896/texture/{key}/{role}.png':(key,role) for key in keys for role in roles}
 assert isinstance(mapping,dict) and set(mapping)==set(expected),'Exactly the nine requested upload URLs are required'
 path=PACKAGE/'manifest.json';original=path.read_bytes();manifest=json.loads(original)
 assert manifest['schema']=='lobby-reimagined-blender-v2' and manifest['revision']==4
 assert manifest['placeId']==131311258779917 and set(manifest['materials'])==set(keys)
 texture=json.loads((PACKAGE/'textures/manifest.json').read_bytes());rows=[];ids=set()
 for url,(key,role) in expected.items():
  result=mapping[url];assert isinstance(result,str)
  match=re.fullmatch(r'rbxassetid://([1-9][0-9]*)',result);assert match,'Invalid returned asset ID'
  asset_id=match.group(1);assert asset_id not in ids,'Unexpected duplicate upload asset ID';ids.add(asset_id)
  spec=texture['materials'][key]['maps'][role]
  png=PACKAGE/'textures'/spec['file'];raw=png.read_bytes();digest=hashlib.sha256(raw).hexdigest()
  assert digest==spec['sha256'] and raw.startswith(b'\x89PNG\r\n\x1a\n'),'PNG source changed after upload preparation'
  map_spec=manifest['materials'][key]['maps'][role]
  assert map_spec.get('assetId') in (None,asset_id),'Refusing to replace an existing different asset mapping'
  map_spec.update(assetId=asset_id,pngSHA256=digest)
  rows.append({'material':key,'role':role,'assetId':asset_id,'uploadURL':url,'PNG':png.relative_to(ROOT).as_posix(),'pngSHA256':digest})
 new=(json.dumps(manifest,indent=2)+'\n').encode()
 assert path.read_bytes()==original,'Concurrent package manifest change'
 path.write_bytes(new)
 receipt={'mappingSHA256':hashlib.sha256(supplied).hexdigest(),'manifestBeforeSHA256':hashlib.sha256(original).hexdigest(),
  'manifestAfterSHA256':hashlib.sha256(new).hexdigest(),'maps':rows,'StudioChanged':False,'renderingAndAssetAccessVerified':False,
  'next':'Rebuild final catalog and prepared installer; refresh server. Verify static templates and assets on actual clients before publish.'}
 out=ROOT/'artifacts/lobby-rebuild-r4-20261001/published-pbr-map-ids.json';out.write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps({'pinnedMaps':len(rows),'manifestSHA256':receipt['manifestAfterSHA256'],'assetAccessVerified':False}))
if __name__=='__main__':main()
