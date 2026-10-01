"""Serve an immutable, allowlisted Level 6 source snapshot on loopback.

This server only exposes seven exact baseline/candidate pairs and never writes
to Studio. The caller must compare each live Source and editor buffer to its
baseline inside the Studio write before assigning the candidate Source.
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
META = ROOT / "artifacts/level6-studio-revision-20261001/import-package/Level 6 Kit Metadata.v2.ModuleScript.luau"
BAKE = ROOT / "tools/level6_build/import/Level6BlenderRuntimeBake.ModuleScript.luau"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def snapshot() -> dict[str, bytes]:
    doc = json.loads((HERE / "candidate-manifest.json").read_text())
    pairs = []
    payloads = {}
    for entry in doc["scripts"]:
        name = entry["name"]
        before = (HERE / "live-baseline" / f"{name}.luau").read_bytes()
        after = (HERE / f"{name}.luau").read_bytes()
        assert sha(before) == entry["baselineSHA256"]
        assert sha(after) == entry["candidateSHA256"]
        pairs.append((name, entry["studioPath"], entry["className"], before, after))
    pairs.extend((
        ("kit_metadata", "ServerScriptService.Level 6 Systems.Level 6 Kit Metadata",
         "ModuleScript", (HERE / "live-baseline/kit_metadata.luau").read_bytes(), META.read_bytes()),
        ("blender_runtime_bake", "ServerScriptService.Level 6 Systems.Level6BlenderRuntimeBake",
         "ModuleScript", (HERE / "live-baseline/blender_runtime_bake.luau").read_bytes(), BAKE.read_bytes()),
    ))
    manifest = {"schema": "level6-guarded-runtime-v1", "placeId": 131311258779917,
                "universeId": 10559217407, "scripts": []}
    for name, path, class_name, before, after in pairs:
        for body in (before, after):
            assert body.decode("utf-8").encode("utf-8") == body
        payloads[f"/baseline/{name}"] = before
        payloads[f"/candidate/{name}"] = after
        manifest["scripts"].append({"id": name, "path": path, "class": class_name,
                                    "baselineBytes": len(before), "baselineSHA256": sha(before),
                                    "candidateBytes": len(after), "candidateSHA256": sha(after)})
    payloads["/manifest"] = json.dumps(manifest, separators=(",", ":")).encode()
    return payloads


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8891)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    payloads = snapshot()
    if args.check:
        print(payloads["/manifest"].decode())
        return

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args: object) -> None:
            pass

        def do_GET(self) -> None:
            body = payloads.get(self.path)
            if body is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json" if self.path == "/manifest" else "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    print(f"Serving guarded Level 6 sources at http://127.0.0.1:{args.port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
