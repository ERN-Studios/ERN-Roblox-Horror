"""Loopback-only, allowlisted mesh transport and append-only upload receipts."""
import argparse
import base64
import hashlib
import http.server
import json
import pathlib
import threading
import time
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument("root", type=pathlib.Path)
parser.add_argument("--port", type=int, default=8876)
args = parser.parse_args()
root = args.root.resolve()
manifest = json.loads((root / "manifest.json").read_text())
chunks = {int(c["id"]): c for c in manifest["chunks"]}
results = root / "upload-results.jsonl"
lock = threading.Lock()


def done():
    records = {}
    if results.exists():
        for line in results.read_text().splitlines():
            item = json.loads(line)
            chunk = chunks.get(item["id"])
            if chunk and item.get("asset") and item.get("sha256") == chunk["sha256"]:
                records[str(item["id"])] = item["asset"]
    return records


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, body, status=200, content_type="text/plain"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            path = urllib.parse.urlparse(self.path).path
            if path == "/manifest":
                return self.reply(json.dumps(manifest), content_type="application/json")
            if path == "/pending":
                completed = done()
                return self.reply(",".join(str(i) for i in chunks if str(i) not in completed))
            if path == "/assets":
                return self.reply(json.dumps(done()), content_type="application/json")
            if path == "/atlas.png":
                atlas = (root / manifest.get("atlas", "atlas.png")).resolve()
                if not atlas.is_relative_to(root):
                    return self.reply("invalid atlas path", 400)
                return self.reply(atlas.read_bytes(), content_type="image/png")
            if path.startswith("/chunk/"):
                chunk = chunks[int(path.rsplit("/", 1)[1])]
                payload = (root / chunk["file"]).read_bytes()
                assert hashlib.sha256(base64.b64decode(payload, validate=True)).hexdigest() == chunk["sha256"]
                return self.reply(payload)
            return self.reply("not found", 404)
        except (ValueError, KeyError, AssertionError, OSError) as exc:
            return self.reply(str(exc), 400)

    def do_POST(self):
        try:
            url = urllib.parse.urlparse(self.path)
            if url.path != "/result":
                return self.reply("not found", 404)
            query = dict(urllib.parse.parse_qsl(url.query))
            chunk = chunks[int(query["id"])]
            size = int(self.headers.get("Content-Length") or 0)
            if not 0 <= size <= 16000:
                return self.reply("invalid body size", 400)
            body = self.rfile.read(size).decode(errors="replace")
            receipt = {"id": chunk["id"], "name": chunk["name"], "sha256": chunk["sha256"], "time": time.time()}
            if query.get("asset"):
                receipt["asset"] = int(query["asset"])
                assert receipt["asset"] > 0
            else:
                receipt["error"] = body
            with lock, results.open("a") as fh:
                fh.write(json.dumps(receipt) + "\n")
                fh.flush()
            self.reply("recorded")
        except (ValueError, KeyError, AssertionError) as exc:
            self.reply(str(exc), 400)


print(f"Level6 import: http://127.0.0.1:{args.port}; {len(chunks)} mesh chunks", flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
