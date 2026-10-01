from pathlib import Path
from io import BytesIO
import base64,hashlib,json,struct,subprocess
from PIL import Image
repo=Path(__file__).resolve().parents[3]
names=[x.decode() for x in subprocess.check_output(['git','diff','--cached','--name-only','-z'],cwd=repo).split(b'\0') if x]
receipt_path='artifacts/lobby-rebuild-r4-20261001/staged-verification.json'
names=[x for x in names if x!=receipt_path] # This receipt cannot hash its own future bytes.
assert all(x=='.gitignore' or x.startswith(('tools/lobby_reimagined/','assets/models/lobby-reimagined-r4-20261001/','artifacts/lobby-rebuild-r4-20261001/')) for x in names)
assert not any('vesper-cathedral' in x or x.endswith(('.blend1','.log','.pid','.rbxl','.bin')) for x in names)
proc=subprocess.Popen(['git','cat-file','--batch'],cwd=repo,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
proc.stdin.write(('\n'.join(':'+x for x in names)+'\n').encode());proc.stdin.close()
blobs={};hashes={}
for path in names:
 header=proc.stdout.readline().decode().split();assert len(header)==3 and header[1]=='blob'
 raw=proc.stdout.read(int(header[2]));assert len(raw)==int(header[2]) and proc.stdout.read(1)==b'\n'
 blobs[path]=raw;hashes[path]=hashlib.sha256(raw).hexdigest()
assert proc.wait()==0
asset='assets/models/lobby-reimagined-r4-20261001/'
manifest=json.loads(blobs[asset+'manifest.json']);textures=json.loads(blobs[asset+'textures/manifest.json'])
assert hashes[asset+'LobbyReimaginedPreview.blend']=='165712df68a47fe4811264f3e4801d09e5a876a4a8108a1a758b53e876c02259'
assert hashes[asset+'LobbyReimaginedPreview.fbx']=='01c96f012c117b9042591f6fa3fe20b90349706306780a0072d2c66d77d6d9fa'
triangles=0
for spec in manifest['chunks']:
 raw=base64.b64decode(blobs[asset+spec['file']],validate=True)
 assert len(raw)==spec['bytes'] and hashlib.sha256(raw).hexdigest()==spec['sha256']
 magic,nv,nn,nu,nf=struct.unpack_from('<5I',raw)
 assert magic==0x364D564C and 0<nf<=20000 and nf==spec['triangles']
 assert len(raw)==20+nv*12+nn*12+nu*8+nf*36
 triangles+=nf
assert triangles==manifest['uniqueTriangles']==66872
pngs=0;rgba=0
for key,spec in textures['materials'].items():
 for role,img in spec['maps'].items():
  raw=blobs[asset+'textures/'+img['file']]
  assert hashlib.sha256(raw).hexdigest()==img['sha256']
  with Image.open(BytesIO(raw)) as picture:
   assert picture.size==(1024,1024)
   if key in manifest['materials'] and role in manifest['materials'][key]['maps']:
    target=manifest['materials'][key]['maps'][role]
    pixels=picture.convert('RGBA').tobytes()
    assert len(pixels)==target['bytes'] and hashlib.sha256(pixels).hexdigest()==target['sha256']
    assert base64.b64decode(blobs[asset+target['file']],validate=True)==pixels
    rgba+=1
  pngs+=1
catalog=json.loads(blobs['tools/lobby_reimagined/r4_candidates/install-catalog-r4-final.json'])
assert catalog['sourceCount']==7 and catalog['sourceCatalogReady'] and not catalog['readyForInstaller']
assert catalog['payload']['manifestSHA256']==hashes[asset+'manifest.json']
for spec in catalog['sources']:
 raw=blobs[spec['candidateFile']]
 assert len(raw)==spec['candidateBytes'] and hashlib.sha256(raw).hexdigest()==spec['afterSHA256']
receipt=json.loads(blobs['artifacts/lobby-rebuild-r4-20261001/install-r4-prepared.receipt.json'])
assert not receipt['executed'] and not receipt['readyForInstaller']
assert receipt['installerSHA256']==hashes['artifacts/lobby-rebuild-r4-20261001/install-r4-prepared.luau']
assert json.loads(blobs['artifacts/lobby-rebuild-r4-20261001/native-before/checkpoint-install-gate.json'])['verified'] is False
result={'passed':True,'scope':'Exact staged Git blobs only; no current Studio/import/Play/publication claim',
 'stagedFiles':len(names),'chunks':len(manifest['chunks']),'uniqueTriangles':triangles,'PBR_PNGsVerified':pngs,'PBR_RGBAExact':rgba,
 'candidateSources':len(catalog['sources']),'installerSHA256':receipt['installerSHA256'],'readyForInstaller':False,
 'unrelatedCathedralExcluded':True,'selfReceiptExcluded':receipt_path,'fileSHA256':hashes}
out=repo/'artifacts/lobby-rebuild-r4-20261001/staged-verification.json'
out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='fileSHA256'}))
