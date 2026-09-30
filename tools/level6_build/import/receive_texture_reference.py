"""Receive a fresh, read-only appearance export from the target Studio place.

Never writes to Studio. Refuses to overwrite a different local capture.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import argparse
import hashlib
import json
from urllib.parse import parse_qs, urlparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)

    class Receiver(BaseHTTPRequestHandler):
        def do_POST(self):
            url = urlparse(self.path)
            if url.path not in {"/reference", "/reference-part"}:
                self.send_error(404)
                return
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 750000:
                self.send_error(413)
                return
            raw = self.rfile.read(length)
            if url.path == "/reference-part":
                try:
                    index = int(parse_qs(url.query)["index"][0])
                    assert 0 <= index < 34
                except (KeyError, ValueError, AssertionError):
                    self.send_error(422, "Invalid part index")
                    return
                part = args.directory / f"appearance-part-{index:03d}.jsonpart"
                if part.exists() and part.read_bytes() != raw:
                    self.send_error(409, "Part differs; select a new capture directory")
                    return
                part.write_bytes(raw)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Part received")
                return
            try:
                envelope = json.loads(raw)
                assert envelope["schema"] == "appearance-reference-parts/1"
                count = envelope["partCount"]
                assert isinstance(count, int) and 0 < count <= 34
                assert 0 < envelope["bytes"] <= 25000000
                assert len(list(args.directory.glob("appearance-part-*.jsonpart"))) == count
                raw = b"".join((args.directory / f"appearance-part-{index:03d}.jsonpart").read_bytes()
                               for index in range(count))
                assert len(raw) == envelope["bytes"]
                data = json.loads(raw)
                assert data["placeId"] == 131311258779917
                assert data["universeId"] == 10559217407
                assert all(item["editorMatch"] for item in data["scripts"])
            except (ValueError, KeyError, AssertionError, OSError, TypeError):
                self.send_error(422, "Wrong place or source/editor conflict")
                return
            target = args.directory / "live-appearance-reference.json"
            if target.exists() and target.read_bytes() != raw:
                self.send_error(409, "Capture already exists; select a new directory")
                return
            target.write_bytes(raw)
            (args.directory / "capture-summary.json").write_text(json.dumps({
                "placeId": data["placeId"], "universeId": data["universeId"],
                "placeVersion": data["placeVersion"], "capturedAt": data["capturedAt"],
                "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw),
                "scriptCount": len(data["scripts"]), "sourceEditorParity": True,
                "assetRecords": len(data["assets"]),
            }, indent=2) + "\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Captured authoritative Studio appearance state")

        def log_message(self, fmt, *args):
            print(fmt % args, flush=True)

    print("Read-only texture reference receiver: 127.0.0.1:8882", flush=True)
    HTTPServer(("127.0.0.1", 8882), Receiver).serve_forever()


if __name__ == "__main__":
    main()
