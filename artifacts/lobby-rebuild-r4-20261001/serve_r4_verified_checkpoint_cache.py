"""Loopback receipt endpoint; independently rehash every noncloud recovery file."""
from pathlib import Path
import hashlib
import http.server
import json

CACHE = Path("/private/tmp/lobby-r4-recovery-before-20261001")
EXPECTED_RECEIPT_SHA = "7da1a8e7e31da736f2103c5802fdec278655c36de99d80fc9e98f4f7096f5fc2"

def verified_receipt():
    data = (CACHE / "checkpoint-install-gate.json").read_bytes()
    assert hashlib.sha256(data).hexdigest() == EXPECTED_RECEIPT_SHA
    receipt = json.loads(data)
    assert receipt["verified"] is True
    assert receipt["captureId"] == "a3e80689-a0f2-4f26-8d6e-f5b8b4adaaf7"
    assert receipt["nativeSHA256"] == "2291d497321cc847d083ab01f30795ebaae29a245701cd51cd91922b808a70e0"
    assert receipt["placeId"] == 131311258779917 and receipt["universeId"] == 10559217407 and receipt["groupId"] == 1039373905
    assert len(receipt["files"]) == 106
    for row in receipt["files"]:
        file = (CACHE / row["file"]).resolve()
        assert file.is_relative_to(CACHE.resolve()) and file.is_file()
        assert file.stat().st_size == row["bytes"]
        digest = hashlib.sha256()
        with file.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        assert digest.hexdigest() == row["sha256"]
    metadata = json.loads((CACHE / "metadata.json").read_bytes())
    assert metadata["captureId"] == receipt["captureId"] and metadata["nativeSHA256"] == receipt["nativeSHA256"]
    return data

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass
    def do_GET(self):
        if self.path != "/checkpoint":
            return self.send_error(404)
        try:
            value = verified_receipt()
            self.send_response(200)
            self.send_header("Content-Length", str(len(value)))
            self.end_headers()
            self.wfile.write(value)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as error:
            self.send_error(503, str(error))

if __name__ == "__main__":
    verified_receipt()
    print("Verified noncloud recovery receipt http://127.0.0.1:8891/checkpoint", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", 8891), Handler).serve_forever()
