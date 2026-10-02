"""Task-owned loopback receivers; served inputs are pinned, preloaded /tmp bytes.

This script never controls Studio. Run one process for ``install`` (8905) and
one for ``capture-after`` (8906). Receipt acknowledgement depends on the fast
local /tmp copy; the repository receipt is mirrored in a background thread.
"""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import threading
from urllib.parse import parse_qs, urlparse

PLACE, UNIVERSE, GROUP = 131311258779917, 10559217407, 1039373905
EXPECTED_BEFORE = "451e86549091122a992da3a8cabee5f38471dd20d5b77212dc6d77dad1433872"
LOCK = threading.RLock()


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def save(path: Path, value: bytes) -> None:
    """Never replace different capture or receipt bytes from another run."""
    with LOCK:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            if path.read_bytes() != value:
                raise ValueError(f"Refuse different bytes: {path.name}")
            return
        temporary = path.with_name(path.name + ".receiving")
        temporary.write_bytes(value)
        temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("role", choices=("install", "capture-after"))
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--mirror-receipt", type=Path)
    args = parser.parse_args()
    snapshot = args.snapshot.resolve()
    assert snapshot.is_relative_to(Path("/private/tmp"))
    manifest = json.loads((snapshot / "input-manifest.json").read_bytes())
    assert manifest["expectedBeforeNativeSHA"] == EXPECTED_BEFORE
    assert manifest["capturePrefix"] == "__lobbyPolishAfter"
    payloads = {}
    for row in manifest["inputs"]:
        path = snapshot / row["file"]
        assert path.resolve().is_relative_to(snapshot)
        raw = path.read_bytes()
        assert len(raw) == row["bytes"] and sha(raw) == row["sha256"], row["file"]
        payloads[row["file"]] = raw
    capture = payloads["capture-after.luau"].decode()
    assert EXPECTED_BEFORE in capture and "__lobbyPolishAfterBackupRunning" in capture
    assert "__lobbyPolishBefore" not in capture
    port = 8905 if args.role == "install" else 8906
    dest = Path("/private/tmp/lobby-polish-after-20261002")
    dest.mkdir(exist_ok=True)
    health = dict(manifest, role=args.role, port=port, pid=os.getpid(), frozenInMemory=True,
                  receipt=str(snapshot / "install-receipt.json"), captureDestination=str(dest))
    health_bytes = (json.dumps(health, sort_keys=True) + "\n").encode()

    def checkpoint_receipt() -> bytes:
        path = dest / "checkpoint-install-gate.json"
        assert path.is_file(), "No verified fresh native recovery checkpoint"
        value = path.read_bytes()
        record = json.loads(value)
        assert record.get("verified") is True and record.get("captureId")
        metadata = json.loads((dest / "metadata.json").read_bytes())
        assert record["captureId"] == metadata["captureId"]
        assert record["nativeSHA256"] == metadata["nativeSHA256"]
        assert (record["placeId"], record["universeId"], record["groupId"]) == (PLACE, UNIVERSE, GROUP)
        assert record.get("files")
        for row in record["files"]:
            file = (dest / row["file"]).resolve()
            assert file.is_relative_to(dest.resolve()) and file.is_file()
            assert file.stat().st_size == row["bytes"]
            digest = hashlib.sha256()
            with file.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            assert digest.hexdigest() == row["sha256"]
        return value

    def mirror_receipt(value: bytes) -> None:
        try:
            if args.mirror_receipt:
                save(args.mirror_receipt, value)
                print(json.dumps({"mirroredInstallReceipt": str(args.mirror_receipt), "sha256": sha(value)}), flush=True)
        except Exception as error:
            print(json.dumps({"receiptMirrorError": str(error), "recoverableReceipt": str(snapshot / "install-receipt.json")}), flush=True)

    def export_sources(value: bytes) -> None:
        rows = json.loads(value)
        assert isinstance(rows, list) and all(row.get("editorMatch") is True for row in rows)
        save(dest / "scripts.json", value)
        source_manifest = []
        for row in rows:
            raw = row["source"].encode()
            source_manifest.append({"path": row["path"], "class": row["class"], "sourceBytes": len(raw),
                                    "sourceSha256": sha(raw), "editorMatch": row["editorMatch"]})
            path = row["path"]
            wanted = (path == "ServerScriptService.GameManager" or path == "ReplicatedStorage.DevAccess"
                      or "LobbyReimagined" in path or "PreviewAccess" in path or "Routing" in path
                      or "LobbyQueue" in path or "LevelPreview" in path or path.endswith(".R4DevGateController"))
            if wanted:
                filename = path.replace("/", "_").replace("\\", "_") + "." + row["class"] + ".luau"
                save(dest / "fresh-source" / filename, raw)
        save(dest / "fresh-source-manifest.json", (json.dumps({"sources": sorted(source_manifest, key=lambda row: row["path"]),
             "count": len(rows), "editorConflicts": 0}, indent=2) + "\n").encode())
        print(json.dumps({"freshSourceCount": len(rows), "criticalSourceDirectory": str(dest / "fresh-source")}), flush=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def response(self, data: bytes):
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Content-Type", "application/octet-stream")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                return self.response(health_bytes)
            endpoints = ({"/catalog": "catalog.json", "/install": "install.luau"} if args.role == "install"
                         else {"/schema": "schema.json", "/capture": "capture-after.luau"})
            if self.path in endpoints:
                return self.response(payloads[endpoints[self.path]])
            if args.role == "capture-after" and self.path == "/checkpoint":
                try:
                    return self.response(checkpoint_receipt())
                except Exception as error:
                    return self.send_error(503, str(error))
            self.send_error(404)

        def do_POST(self):
            url = urlparse(self.path)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 15000000:
                    return self.send_error(400)
                self.connection.settimeout(30)
                value = self.rfile.read(length)
                assert len(value) == length, "Truncated body"
                if args.role == "install":
                    if url.path != "/receipt":
                        return self.send_error(404)
                    row = json.loads(value)
                    assert row["placeId"] == PLACE and row["universeId"] == UNIVERSE
                    save(snapshot / "install-receipt.json", value)
                    threading.Thread(target=mirror_receipt, args=(value,), daemon=True).start()
                    print(json.dumps({"receivedInstallReceipt": str(snapshot / "install-receipt.json"), "bytes": len(value), "sha256": sha(value)}), flush=True)
                elif url.path == "/sources":
                    export_sources(value)
                elif url.path == "/source-part":
                    index = int(parse_qs(url.query)["index"][0])
                    assert 0 <= index < 1000 and len(value) <= 750000
                    save(dest / f"source-part-{index:05d}.bin", value)
                elif url.path == "/sources-finalize":
                    record = json.loads(value)
                    count = record["parts"]
                    assert isinstance(count, int) and 0 < count <= 1000
                    assert record["chunkBytes"] == 750000
                    raw = b"".join((dest / f"source-part-{index:05d}.bin").read_bytes() for index in range(count))
                    assert len(raw) == record["bytes"] and sha(raw) == record["sha256"]
                    export_sources(raw)
                    save(dest / "source-transfer-receipt.json", value)
                elif url.path in ("/metadata", "/fingerprint", "/error"):
                    json.loads(value)
                    target = dest / "capture-errors" / (sha(value) + ".json") if url.path == "/error" else dest / (url.path[1:] + ".json")
                    save(target, value)
                    print(json.dumps({"received": url.path, "bytes": len(value), "file": str(target)}), flush=True)
                elif url.path == "/native":
                    index = int(parse_qs(url.query)["index"][0])
                    assert 0 <= index < 1000
                    save(dest / f"native-part-{index:05d}.bin", value)
                else:
                    return self.send_error(404)
                self.response(b"saved")
            except Exception as error:
                self.send_error(409, str(error))

    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(json.dumps(health), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
