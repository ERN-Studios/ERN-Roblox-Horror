"""Loopback-only read-only Studio export receiver. No asset upload or Studio write."""
from __future__ import annotations
import hashlib
import http.server
import json
from pathlib import Path
from urllib.parse import parse_qs, urlparse

TASK = Path(__file__).resolve().parent
DEST = Path("/private/tmp/lobby-endfix-before-20261002")
PREVIOUS = Path("/private/tmp/lobby-r4-native-after-20261001")
PORT = 8893
SCHEMA_BYTES = (PREVIOUS / "service-property-schema.json").read_bytes()
CAPTURE_BYTES = (TASK / "capture-before-readonly.luau").read_bytes()

def checkpoint_receipt():
    path=DEST/"checkpoint-install-gate.json"
    assert path.is_file(),"No verified fresh native recovery checkpoint"
    value=path.read_bytes();record=json.loads(value)
    assert record.get("verified") is True and record.get("captureId"),"Native recovery checkpoint not verified"
    metadata=json.loads((DEST/"metadata.json").read_bytes())
    assert record["captureId"]==metadata["captureId"] and record["nativeSHA256"]==metadata["nativeSHA256"]
    assert record["placeId"]==131311258779917 and record["universeId"]==10559217407 and record["groupId"]==1039373905
    assert record.get("files"),"Recovery receipt has no verified file inputs"
    for row in record["files"]:
        file=(DEST/row["file"]).resolve()
        assert file.is_relative_to(DEST.resolve()) and file.is_file(),"Verified recovery file missing"
        assert file.stat().st_size==row["bytes"],"Verified recovery file size changed"
        digest=hashlib.sha256()
        with file.open("rb") as stream:
            for block in iter(lambda:stream.read(1024*1024),b""):digest.update(block)
        assert digest.hexdigest()==row["sha256"],"Verified recovery file bytes changed"
    return value


def save(path: Path, value: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() != value:
        raise ValueError(f"Refuse different bytes: {path.name}")
    path.write_bytes(value)


def export_sources(value: bytes):
    rows = json.loads(value)
    assert isinstance(rows, list) and all(row.get("editorMatch") is True for row in rows)
    save(DEST / "scripts.json", value)
    manifest = []
    for row in rows:
        raw = row["source"].encode()
        record = {"path": row["path"], "class": row["class"], "sourceBytes": len(raw),
                  "sourceSha256": hashlib.sha256(raw).hexdigest(), "editorMatch": row["editorMatch"]}
        manifest.append(record)
        path = row["path"]
        wanted = (path == "ServerScriptService.GameManager" or path == "ReplicatedStorage.DevAccess"
                  or "LobbyReimagined" in path or "PreviewAccess" in path or "Routing" in path
                  or "LobbyQueue" in path or "LevelPreview" in path)
        if wanted:
            filename = path.replace("/", "_").replace("\\", "_") + "." + row["class"] + ".luau"
            save(DEST / "fresh-source" / filename, raw)
    save(DEST / "fresh-source-manifest.json", (json.dumps({"sources": sorted(manifest, key=lambda row: row["path"]),
         "count": len(rows), "editorConflicts": 0}, indent=2) + "\n").encode())
    print(json.dumps({"freshSourceCount": len(rows), "criticalSourceDirectory": str(DEST / "fresh-source")}), flush=True)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def response(self, data: bytes):
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if self.path == "/schema": self.response(SCHEMA_BYTES)
        elif self.path == "/capture": self.response(CAPTURE_BYTES)
        elif self.path == "/checkpoint":
            try: self.response(checkpoint_receipt())
            except Exception as error: self.send_error(503,str(error))
        else: self.send_error(404)
    def do_POST(self):
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 < length <= 15000000: return self.send_error(400)
        value = self.rfile.read(length)
        try:
            if url.path == "/sources": export_sources(value)
            elif url.path == "/source-part":
                index = int(parse_qs(url.query)["index"][0]); assert 0 <= index < 1000
                assert len(value) <= 750000
                save(DEST / f"source-part-{index:05d}.bin", value)
            elif url.path == "/sources-finalize":
                record = json.loads(value)
                count = record["parts"]
                assert isinstance(count, int) and 0 < count <= 1000
                assert record["chunkBytes"] == 750000
                chunks = [DEST / f"source-part-{index:05d}.bin" for index in range(count)]
                raw = b"".join(path.read_bytes() for path in chunks)
                assert len(raw) == record["bytes"]
                assert hashlib.sha256(raw).hexdigest() == record["sha256"]
                export_sources(raw)
                save(DEST / "source-transfer-receipt.json", value)
            elif url.path in ("/metadata", "/fingerprint", "/error"):
                json.loads(value)
                target = (DEST / "capture-errors" / (hashlib.sha256(value).hexdigest() + ".json")) if url.path == "/error" else (DEST / (url.path[1:] + ".json"))
                save(target, value)
                print(json.dumps({"received": url.path, "bytes": len(value), "file": str(target)}), flush=True)
            elif url.path == "/native":
                index = int(parse_qs(url.query)["index"][0]); assert 0 <= index < 1000
                save(DEST / f"native-part-{index:05d}.bin", value)
            else: return self.send_error(404)
            self.response(b"saved")
        except Exception as error:
            self.send_error(409, str(error))


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    print(f"R4 read-only receiver http://127.0.0.1:{PORT}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
