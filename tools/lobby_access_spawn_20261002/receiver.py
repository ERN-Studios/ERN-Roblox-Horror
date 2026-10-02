"""Loopback-only full-native receiver; never writes Studio or uploads assets."""
from pathlib import Path
import argparse,hashlib,http.server,json,os
from urllib.parse import parse_qs,urlparse
TASK=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--phase',required=True,choices=['before','after']);p.add_argument('--port',type=int,default=8912)
args=p.parse_args();DEST=Path('/private/tmp/lobby-access-spawn-20261002')/args.phase
manifest=json.loads((TASK/'input-manifest.json').read_text())
capture=(TASK/'capture-readonly.luau').read_bytes();schema=(TASK/'service-property-schema.json').read_bytes()
assert hashlib.sha256(capture).hexdigest()==manifest['captureSHA256']
assert hashlib.sha256(schema).hexdigest()==manifest['schemaSHA256']
context={'task':manifest['task'],'phase':args.phase}
def save(name,value):
 path=DEST/name;path.parent.mkdir(parents=True,exist_ok=True)
 if path.exists():
  assert path.read_bytes()==value,'Immutable received file differs: '+name
 else:path.write_bytes(value)
def finish_sources(value):
 rows=json.loads(value);assert isinstance(rows,list)
 seen=set();inventory=[]
 for row in rows:
  assert row['path'] not in seen;seen.add(row['path'])
  raw=row['source'].encode();h=hashlib.sha256(raw).hexdigest()
  assert row['editorMatch'] is True and h==row['sourceSha256']==row['editorSourceSha256'] and len(raw)==row['sourceBytes']
  inventory.append({k:row[k] for k in ['path','class','sourceBytes','sourceSha256','editorSourceSha256','editorMatch']})
 save('scripts.json',value)
 save('source-inventory.json',(json.dumps({'sources':sorted(inventory,key=lambda x:x['path']),'count':len(rows),'editorConflicts':0},indent=2)+'\n').encode())
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*_):pass
 def response(self,data):
  self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def do_GET(self):
  data={'/capture':capture,'/schema':schema,'/context':json.dumps(context).encode(),'/health':json.dumps(dict(manifest,**context,pid=os.getpid(),destination=str(DEST),frozenInMemory=True)).encode()}.get(self.path)
  if data is None:self.send_error(404)
  else:self.response(data)
 def do_POST(self):
  url=urlparse(self.path);length=int(self.headers.get('Content-Length','0'))
  if not 0<length<=1000000:return self.send_error(400)
  value=self.rfile.read(length)
  try:
   if url.path in ['/source-part','/native']:
    i=int(parse_qs(url.query)['index'][0]);assert 0<=i<1000
    save(('source-part-' if url.path=='/source-part' else 'native-part-')+f'{i:05d}.bin',value)
   elif url.path=='/sources-finalize':
    v=json.loads(value);assert v['chunkBytes']==750000 and isinstance(v['parts'],int) and 0<v['parts']<=1000
    raw=b''.join((DEST/f'source-part-{i:05d}.bin').read_bytes() for i in range(v['parts']))
    assert len(raw)==v['bytes'] and hashlib.sha256(raw).hexdigest()==v['sha256']
    finish_sources(raw);save('source-transfer-receipt.json',value)
   elif url.path=='/metadata':
    v=json.loads(value);assert v['task']==context['task'] and v['phase']==args.phase
    assert v['placeId']==131311258779917 and v['universeId']==10559217407 and v['groupId']==1039373905
    save('metadata.received.json',value)
    print(json.dumps({'received':'complete','captureId':v['captureId'],'phase':args.phase,'nativeBytes':v['nativeBytes'],'sources':v['scriptCount']}),flush=True)
   elif url.path=='/error':
    json.loads(value);save('capture-errors/'+hashlib.sha256(value).hexdigest()+'.json',value)
   else:return self.send_error(404)
   self.response(b'saved')
  except Exception as error:self.send_error(409,str(error))
if __name__=='__main__':
 DEST.mkdir(parents=True,exist_ok=True)
 print(json.dumps({'port':args.port,'phase':args.phase,'destination':str(DEST),'pid':os.getpid()}),flush=True)
 http.server.ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
