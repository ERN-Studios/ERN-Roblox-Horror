"""Serve one immutable, Studio-derived Level 6 lighting and CD ESP patch.

Only reviewed baseline and candidate sources are exposed on loopback.  This
server never writes to Studio; install_light_esp_patch.luau performs guarded
source edits against the exact baseline returned here.
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REPAIR = ROOT / "artifacts/level6-light-esp-20260930"
ESP = ROOT / "tools/level6_build/gameplay-candidates/Level 6 CD Dev ESP.LocalScript.luau"
ESP_PATH = "StarterPlayer.StarterPlayerScripts.Level 6 CD Dev ESP"


def sha256(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def snapshot() -> tuple[dict, dict[str, bytes]]:
    baseline = {item["path"]: item for item in json.loads((REPAIR / "native-before/scripts.json").read_text())}
    candidate_manifest = json.loads((REPAIR / "candidates/candidate-manifest.json").read_text())
    assert candidate_manifest["placeId"] == 131311258779917
    assert candidate_manifest["universeId"] == 10559217407
    assert ESP_PATH not in baseline
    assert len(candidate_manifest["scripts"]) == 3

    payloads: dict[str, bytes] = {}
    edits: list[dict] = []
    for index, item in enumerate(candidate_manifest["scripts"]):
        path = item["path"]
        original = baseline[path]
        assert original["class"] == item["class"] and original["editorMatch"] is True, path
        before = original["source"].encode("utf-8")
        after = (REPAIR / item["candidateFile"]).read_bytes()
        assert before != after, path
        assert len(before) == item["before"]["bytes"] and sha256(before) == item["before"]["sha256"]
        assert len(after) == item["after"]["bytes"] and sha256(after) == item["after"]["sha256"]
        before.decode("utf-8")
        after.decode("utf-8")
        key = f"{index:02d}"
        payloads[f"/baseline/{key}"] = before
        payloads[f"/candidate/{key}"] = after
        edits.append({"id": key, "path": path, "class": item["class"],
                      "beforeBytes": len(before), "beforeSha256": sha256(before),
                      "afterBytes": len(after), "afterSha256": sha256(after)})

    esp_source = ESP.read_bytes()
    esp_source.decode("utf-8")
    assert b"IsLevel6PreviewAllowed" in esp_source and b"Level6_CDIndex" in esp_source
    payloads["/candidate/esp"] = esp_source
    new_script = {"path": ESP_PATH, "class": "LocalScript", "bytes": len(esp_source),
                  "sha256": sha256(esp_source)}
    manifest = {"schema": "level6-light-cd-esp-patch/1", "placeId": 131311258779917,
                "universeId": 10559217407, "observedPlaceVersion": 2421,
                "edits": edits, "new": new_script}
    payloads["/manifest"] = json.dumps(manifest, separators=(",", ":")).encode("utf-8")
    return manifest, payloads


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8881)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest, payloads = snapshot()
    print(f"Validated {len(manifest['edits'])} guarded edits and one new ESP script", flush=True)
    if args.check:
        for entry in manifest["edits"]:
            print(f"{entry['path']}: {entry['beforeSha256']} -> {entry['afterSha256']}")
        print(f"{manifest['new']['path']}: {manifest['new']['sha256']}")
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

    print(f"Serving immutable patch on http://127.0.0.1:{args.port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
