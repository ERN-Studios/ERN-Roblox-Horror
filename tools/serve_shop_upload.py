"""Loopback-only PNG server for the twelve authorized shop textures."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit

ROOT=Path(__file__).resolve().parents[1]/'assets/shop'
ALLOWED={p.name:p for p in ROOT.glob('*.png')}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        name=urlsplit(self.path).path.lstrip('/')
        path=ALLOWED.get(name)
        if path is None:
            self.send_error(404);return
        body=path.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type','image/png')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers();self.wfile.write(body)
    def log_message(self,*args): pass

with ThreadingHTTPServer(('127.0.0.1',0),Handler) as server:
    print(server.server_address[1],flush=True)
    server.serve_forever()
