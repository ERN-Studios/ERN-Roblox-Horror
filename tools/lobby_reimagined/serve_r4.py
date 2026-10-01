"""Serve and validate the R4 additive Blender payload; no Studio writes.

Multiple material chunks per family are intentional. Existing R3 Sources and
raw folders are never replacement baselines. Installation is gated separately
by fresh live Source/editor hashes and a verified native recovery checkpoint.
"""
from pathlib import Path
import argparse,base64,hashlib,http.server,json,math,re,struct

ROOT=Path(__file__).resolve().parents[2]
DEFAULT=ROOT/'assets/models/lobby-reimagined-r4-20261001'
SOURCE='LobbyReimaginedBlenderSource20261001R4'
CATALOG=ROOT/'tools/lobby_reimagined/r4_candidates/install-catalog-r4-final.json'
SOURCE_SCOPE={
 'ServerScriptService.LobbyReimaginedPreview.Builder':'ModuleScript',
 'ServerScriptService.LobbyReimaginedPreview.RuntimeBake':'ModuleScript',
 'ServerScriptService.LobbyReimaginedPreview.QueueBridge':'ModuleScript',
 'ServerScriptService.GameManager':'Script',
 'ServerScriptService.Level4V4PreviewAccess':'Script',
 'ServerScriptService.Level5PreviewAccess':'Script',
 'ServerScriptService.Level6PreviewAccess':'Script',
}

def sha(data):return hashlib.sha256(data).hexdigest()
def inside(root,name):
 p=(root/name).resolve();assert p.is_relative_to(root) and p.is_file(),'Invalid package path';return p

def load_package(directory):
 root=Path(directory).resolve();manifest_bytes=inside(root,'manifest.json').read_bytes();manifest=json.loads(manifest_bytes)
 assert manifest['schema']=='lobby-reimagined-blender-v2' and manifest['revision']==4
 assert manifest['placeId']==131311258779917 and manifest['groupId']==1039373905
 payload={'/manifest':manifest_bytes};families=set();chunks=manifest['chunks'];assert 0<len(chunks)<=512
 for index,chunk in enumerate(chunks):
  assert chunk['id']==index and re.fullmatch(r'[A-Za-z0-9_ -]{1,100}',chunk['family'])
  families.add(chunk['family']);encoded=inside(root,chunk['file']).read_bytes();raw=base64.b64decode(encoded,validate=True)
  assert len(raw)==chunk['bytes'] and sha(raw)==chunk['sha256']
  magic,nv,nn,nu,nf=struct.unpack_from('<5I',raw)
  assert magic==0x364D564C and all(0<n<=60000 for n in (nv,nn,nu)) and 0<nf<=20000
  assert len(raw)==20+nv*12+nn*12+nu*8+nf*36 and nf==chunk['triangles']
  vals=struct.unpack_from(f'<{nv*3+nn*3+nu*2}f',raw,20);assert all(math.isfinite(v) for v in vals)
  assert all(0<v<2048 for v in chunk['size'])
  for face in struct.iter_unpack('<9I',raw[20+nv*12+nn*12+nu*8:]):
   for i in range(3):assert face[i*3]<nv and face[i*3+1]<nn and face[i*3+2]<nu
  if chunk['materialKey'] not in manifest['materials'] and chunk['materialKey']!='atlas':assert chunk.get('colorAssetId') and chunk['materialKey']=='asset_'+chunk['colorAssetId']
  payload[f'/chunk/{index}']=encoded
 assert families==set(manifest['prefabs'])
 for item in manifest['placements']:assert item['family'] in families and all(math.isfinite(v) for v in item['robloxPosition']) and math.isfinite(item['yaw'])
 images={'atlas':manifest['atlas']}
 for key,spec in manifest['materials'].items():
  assert re.fullmatch('[a-z_]+',key)
  for role,info in spec['maps'].items():assert role in ('color','normal','roughness');images[key+'/'+role]=info
 for name,info in images.items():
  encoded=inside(root,info['file']).read_bytes();raw=base64.b64decode(encoded,validate=True)
  assert info['width']==info['height']==1024 and len(raw)==info['bytes']==4194304 and sha(raw)==info['sha256']
  payload['/pixels/'+name]=encoded
 texture_manifest=json.loads(inside(root,'textures/manifest.json').read_bytes())
 for key in manifest['materials']:
  for role in ('color','normal','roughness'):
   image_spec=texture_manifest['materials'][key]['maps'][role]
   png=inside(root,'textures/'+image_spec['file']).read_bytes()
   assert sha(png)==image_spec['sha256'] and png.startswith(b'\x89PNG\r\n\x1a\n')
   payload[f'/texture/{key}/{role}.png']=png
 return root,manifest,payload

def load_catalog(root,manifest,payload,catalog_path=CATALOG):
 catalog=json.loads(Path(catalog_path).read_bytes())
 assert catalog['schema']=='lobby-r4-exact-install-catalog-v1'
 assert catalog['sourceCatalogReady'] is True and catalog['sourceCount']==7 and catalog['newSources']==0
 assert catalog['placeId']==131311258779917 and catalog['universeId']==10559217407 and catalog['groupId']==1039373905
 assert catalog['payload']['sourceName']==SOURCE and catalog['payload']['manifestSHA256']==sha(payload['/manifest'])
 assert len(catalog['sources'])==7 and {s['path']:s['class'] for s in catalog['sources']}==SOURCE_SCOPE
 keys=set()
 for spec in catalog['sources']:
  key=spec['key'];assert key not in keys and re.fullmatch('[a-z0-9-]+',key);keys.add(key)
  assert spec['sourceURLPath']=='/source/'+key and spec['isNew'] is False and spec['editorMatch'] is True
  assert spec['expectedSourceSHA256']==spec['expectedEditorSourceSHA256']
  raw=inside(ROOT,spec['candidateFile']).read_bytes();raw.decode('utf-8')
  assert len(raw)==spec['candidateBytes'] and sha(raw)==spec['afterSHA256'] and 0<len(raw)<=500000
  payload['/source/'+key]=raw
 payload['/catalog']=json.dumps(catalog,separators=(',',':')).encode()
 return catalog

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=DEFAULT);parser.add_argument('--port',type=int,default=8896);parser.add_argument('--catalog',type=Path,default=CATALOG);parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
 root,manifest,payload=load_package(args.root)
 catalog=load_catalog(root,manifest,payload,args.catalog)
 receipt={'schema':manifest['schema'],'sourceName':SOURCE,'manifestSHA256':sha(payload['/manifest']),'chunks':len(manifest['chunks']),'families':len(manifest['prefabs']),'uniqueTriangles':manifest['uniqueTriangles'],'instantiatedTriangles':manifest['instantiatedTriangles'],'materialPixelMaps':9,'sources':len(catalog['sources']),'readyForInstaller':catalog['readyForInstaller'],'packageBlockers':catalog['packageBlockers'],'passed':True}
 if args.verify_only:print(json.dumps(receipt));return
 class Handler(http.server.BaseHTTPRequestHandler):
  def log_message(self,*_):pass
  def do_GET(self):
   body=payload.get(self.path)
   if body is None:self.send_error(404);return
   self.send_response(200);self.send_header('Content-Length',str(len(body)));self.send_header('Content-Type','image/png' if self.path.endswith('.png') else 'application/json' if self.path in ('/manifest','/catalog') else 'text/plain');self.end_headers();self.wfile.write(body)
 print(json.dumps({'listening':'127.0.0.1:'+str(args.port),**receipt}),flush=True);http.server.ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
if __name__=='__main__':main()
