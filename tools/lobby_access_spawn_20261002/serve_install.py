from pathlib import Path
import json, hashlib, argparse, http.server, os

parser = argparse.ArgumentParser()
parser.add_argument('--snapshot', required=True)
parser.add_argument('--artifacts', required=True)
args = parser.parse_args()
root = Path(args.snapshot)
out = Path(args.artifacts)
out.mkdir(parents=True, exist_ok=True)
files = {name: (root / filename).read_bytes() for name, filename in
         {'payload': 'payload.json', 'install': 'install-scoped.luau', 'scene': 'build-main-lobby-edit.luau'}.items()}
hashes = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *unused):
        pass

    def do_GET(self):
        name = self.path.lstrip('/')
        if name == 'health':
            data = json.dumps({'port': 8913, 'hashes': hashes, 'pid': os.getpid(), 'frozenInMemory': True}).encode()
        elif name in files:
            data = files[name]
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path not in ('/receipt/install', '/receipt/scene'):
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', 0))
        if not 0 < length < 100000:
            self.send_error(400)
            return
        raw = self.rfile.read(length)
        data = json.loads(raw)
        if data['placeId'] != 131311258779917 or data['universeId'] != 10559217407:
            self.send_error(400)
            return
        file = out / (self.path.rsplit('/', 1)[1] + '-receipt.json')
        if file.exists() and file.read_bytes() != raw:
            self.send_error(409)
            return
        file.write_bytes(raw)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'saved')

print(json.dumps({'port': 8913, 'hashes': hashes, 'pid': os.getpid()}), flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1', 8913), Handler).serve_forever()
