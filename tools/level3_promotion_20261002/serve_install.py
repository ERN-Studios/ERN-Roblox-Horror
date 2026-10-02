"""Loopback-only frozen scoped installer; no Studio writes from this process."""
from pathlib import Path
import hashlib,http.server,json,os
TASK=Path(__file__).resolve().parent
snapshot=TASK/'install-snapshot'
out=TASK.parents[1]/'artifacts/level3-promotion-20261002/install'
out.mkdir(parents=True,exist_ok=True)
files={name:(snapshot/file).read_bytes() for name,file in {'payload':'payload.json','install':'install-scoped.luau'}.items()}
hashes={k:hashlib.sha256(v).hexdigest() for k,v in files.items()}
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*_):pass
 def send(self,raw):
  self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
 def do_GET(self):
  key=self.path.lstrip('/')
  if key=='health':return self.send(json.dumps(dict(port=8914,pid=os.getpid(),hashes=hashes,frozenInMemory=True)).encode())
  if key not in files:return self.send_error(404)
  self.send(files[key])
 def do_POST(self):
  if self.path!='/receipt/install':return self.send_error(404)
  size=int(self.headers.get('Content-Length','0'))
  if not 0<size<100000:return self.send_error(400)
  raw=self.rfile.read(size);data=json.loads(raw)
  assert data['task']=='level3-promotion-20261002' and data['placeId']==131311258779917 and data['universeId']==10559217407
  path=out/'install-receipt.json'
  if path.exists() and path.read_bytes()!=raw:return self.send_error(409)
  path.write_bytes(raw);self.send(b'saved')
print(json.dumps(dict(port=8914,pid=os.getpid(),hashes=hashes,frozenInMemory=True)),flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1',8914),Handler).serve_forever()
