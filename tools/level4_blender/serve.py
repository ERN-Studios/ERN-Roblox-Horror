# Loopback server for the Level 4 cinema import (chunks from export_l4.py).
#   GET  /pending            -> comma list of chunk ids without an asset id yet
#   GET  /chunk/<id>         -> base64 blob of that chunk
#   POST /result?id=<id>&asset=<n>|&error=<text>  -> appended to results.jsonl
import http.server, json, os, sys, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = r"G:\Roblox\_local\l4blender\export"
RESULTS = os.path.join(HERE, "results.jsonl")          # chunk id -> uploaded mesh asset id
manifest = json.load(open(os.path.join(ROOT, "manifest.json")))


def done():
    ids = {}
    if os.path.exists(RESULTS):
        for line in open(RESULTS):
            r = json.loads(line)
            if r.get("asset"):
                ids[r["id"]] = r["asset"]
    return ids


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, body, code=200):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/pending":
            d = done()
            self.reply(",".join(str(c["id"]) for c in manifest["chunks"] if c["id"] not in d))
        elif path.startswith("/chunk/"):
            cid = int(path.rsplit("/", 1)[1])
            self.reply(open(os.path.join(ROOT, "chunks", f"c{cid:05d}.b64")).read())
        elif path == "/assets":
            self.reply(json.dumps(done()))
        else:
            self.reply("?", 404)

    def do_POST(self):
        q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode(errors="replace") if n else ""
        rec = {"id": int(q["id"])}
        if q.get("asset"):
            rec["asset"] = int(q["asset"])
        else:
            rec["error"] = q.get("error", "") + body
        with open(RESULTS, "a") as fh:
            fh.write(json.dumps(rec) + "\n")
        self.reply("ok")


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765), H).serve_forever()
