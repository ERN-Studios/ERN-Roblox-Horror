"""Serve only frozen owned installer inputs on loopback; receive its receipt."""
import http.server,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*_):pass
 def do_GET(self):
  file={"/catalog":"install-catalog.json","/install":"install-scoped.luau"}.get(self.path)
  if not file:return self.send_error(404)
  raw=(HERE/file).read_bytes();self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
 def do_POST(self):
  if self.path!='/receipt':return self.send_error(404)
  raw=self.rfile.read(int(self.headers['Content-Length']));row=json.loads(raw)
  assert row['placeId']==131311258779917 and row['universeId']==10559217407
  (HERE/'install-receipt.json').write_bytes(raw)
  self.send_response(200);self.end_headers();self.wfile.write(b'saved')
http.server.ThreadingHTTPServer(('127.0.0.1',8905),Handler).serve_forever()
