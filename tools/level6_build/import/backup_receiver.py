"""Receive one live native snapshot in bounded chunks on loopback only."""
import http.server
import json
import pathlib
import sys
import urllib.parse

root = pathlib.Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def reply(self, body):
        if isinstance(body, str): body = body.encode()
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path == '/schema': self.reply((root/'service-property-schema.json').read_bytes())
        else: self.send_error(404)
    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        length = int(self.headers.get('Content-Length') or 0)
        if not 0 <= length <= 15000000: return self.send_error(400)
        body = self.rfile.read(length)
        if url.path == '/native':
            index = int(query['index']); assert 0 <= index <= 10000
            path = root/f'native-part-{index:05d}.bin'
        elif url.path == '/scriptchunk':
            index = int(query['index']); assert 0 <= index <= 10000
            path = root/f'script-part-{index:05d}.jsonpart'
        elif url.path in ['/metadata', '/scripts']:
            json.loads(body); path = root/(url.path[1:]+'.json')
        else: return self.send_error(404)
        if path.exists():
            if path.read_bytes() != body: return self.send_error(409, 'Refuse overwrite of different snapshot bytes')
            return self.reply('already saved')
        path.write_bytes(body)
        self.reply('saved')

print('Native backup receiver http://127.0.0.1:8877', flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1',8877),Handler).serve_forever()
