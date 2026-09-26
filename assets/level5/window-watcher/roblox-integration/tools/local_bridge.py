from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**k): super().__init__(*a,directory=str(ROOT),**k)
 def do_POST(self):
  if not (__import__('re').fullmatch(r'/(baseline|verification|qa)/[a-zA-Z0-9_-]+\.json',self.path)):
   self.send_error(404);return
  data=self.rfile.read(int(self.headers['Content-Length']))
  parsed=json.loads(data)
  dest=ROOT/self.path.lstrip('/');dest.parent.mkdir(exist_ok=True)
  dest.write_bytes(data)
  self.send_response(200);self.end_headers();self.wfile.write(b'OK')
 def log_message(self,*a): pass
ThreadingHTTPServer(('127.0.0.1',8769),Handler).serve_forever()
