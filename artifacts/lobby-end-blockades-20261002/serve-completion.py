from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
P=Path(__file__).resolve().parent
class H(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path!="/install":self.send_error(404);return
  b=(P/"complete-scoped-native.luau").read_bytes();self.send_response(200);self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
HTTPServer(("127.0.0.1",8895),H).serve_forever()
