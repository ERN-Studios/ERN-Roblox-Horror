"""Loopback-only transport for disposable Studio multiplayer verification."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json

ROOT = Path(__file__).parent / 'multiplayer-results'
ROOT.mkdir(exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        pending = ROOT / 'pending.json'
        body = pending.read_bytes() if pending.exists() else b'{}'
        if pending.exists():
            pending.unlink()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        data = json.loads(body)
        name = str(data.get('id', 'status'))
        if not name.replace('-', '').replace('_', '').isalnum():
            self.send_error(400)
            return
        (ROOT / (name + '.json')).write_text(json.dumps(data, indent=2), encoding='utf-8')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')

    def log_message(self, *args):
        pass


ThreadingHTTPServer(('127.0.0.1', 44559), Handler).serve_forever()
