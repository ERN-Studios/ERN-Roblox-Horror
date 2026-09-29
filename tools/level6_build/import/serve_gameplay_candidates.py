"""Serve one validated Level 6 install snapshot to Studio over loopback.

The snapshot is immutable for the lifetime of this process.  Only the exact
candidate and baseline bodies needed by install_level6_gameplay.luau are served.
This script never contacts Studio or modifies the place.
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
IMPORT = Path(__file__).resolve().parent
GAMEPLAY = IMPORT.parent / "gameplay-candidates"
BACKUP = ROOT / "artifacts/level6-build-20260930/native-backup/scripts.json"
INSTALLED_KIT_METADATA = IMPORT / "baselines/Level 6 Kit Metadata.installed.luau"
KIT_METADATA_TARGET = "ServerScriptService.Level 6 Systems.Level 6 Kit Metadata"
INSTALLED_KIT_METADATA_SHA256 = "6270f72d32a197a002cd18815f203225f7f3660dd3a9c6da261eea48900870f6"
OFFLINE_KIT_METADATA_SHA256 = "c141f4c5246ece81288d1cefdedd8243057149d4844f8fea7c14ee428ff66f4b"
EXTRAS = (
    ("ServerScriptService.Level 6 Systems.Level 6 Room Dressing", "ModuleScript", IMPORT.parent / "room_dressing.luau"),
    ("ServerScriptService.Level 6 Systems.Level6BlenderRuntimeBake", "ModuleScript", IMPORT / "Level6BlenderRuntimeBake.ModuleScript.luau"),
    ("ServerScriptService.Level6PreviewAccess", "Script", IMPORT / "Level6PreviewAccess.Script.luau"),
    ("StarterPlayer.StarterPlayerScripts.Level6PreviewTransport", "LocalScript", IMPORT / "Level6PreviewTransport.LocalScript.luau"),
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def snapshot() -> tuple[dict, dict[str, bytes]]:
    candidate_manifest = json.loads((GAMEPLAY / "candidate-manifest.json").read_text())
    patch_manifest = json.loads((IMPORT / "shared-candidates/patch-manifest.json").read_text())
    backup = {item["path"]: item for item in json.loads(BACKUP.read_text())}
    payloads: dict[str, bytes] = {}
    new: list[dict] = []
    shared: list[dict] = []
    seen: set[str] = set()

    def add_new(path: str, class_name: str, file: Path, expected_sha: str | None = None) -> None:
        assert path not in seen, f"duplicate install path: {path}"
        assert class_name in {"ModuleScript", "Script", "LocalScript"}, path
        seen.add(path)
        body = file.read_bytes()
        assert body.decode("utf-8").encode("utf-8") == body, file
        sha = digest(body)
        if expected_sha is not None:
            assert sha == expected_sha, f"candidate manifest drift: {file} {sha} != {expected_sha}"
        key = f"new{len(new):03d}"
        payloads[f"/source/{key}"] = body
        new.append({"id": key, "path": path, "class": class_name, "bytes": len(body), "sha256": sha})

    for item in candidate_manifest["scripts"]:
        file = ROOT / item["file"]
        add_new(item["targetPath"], item["class"], file, item["sha256"])
        assert len(payloads[f"/source/new{len(new)-1:03d}"]) == item["bytes"], file
    for path, class_name, file in EXTRAS:
        add_new(path, class_name, file)

    installed_kit = INSTALLED_KIT_METADATA.read_bytes()
    assert len(installed_kit) == 8761 and digest(installed_kit) == INSTALLED_KIT_METADATA_SHA256
    kit = next(item for item in new if item["path"] == KIT_METADATA_TARGET)
    assert kit["class"] == "ModuleScript" and kit["sha256"] == OFFLINE_KIT_METADATA_SHA256
    payloads["/metadata/installed"] = installed_kit
    payloads["/metadata/offline"] = payloads["/source/" + kit["id"]]

    for item in patch_manifest:
        path = item["path"]
        assert path not in seen, f"duplicate install path: {path}"
        seen.add(path)
        original = backup[path]
        assert original["class"] == item["class"] and original["editorMatch"] is True, path
        baseline = original["source"].encode("utf-8")
        assert digest(baseline) == item["beforeSha256"], f"backup baseline drift: {path}"
        candidate = (IMPORT / "shared-candidates" / item["candidate"]).read_bytes()
        assert digest(candidate) == item["afterSha256"], f"shared candidate drift: {path}"
        key = f"shared{len(shared):03d}"
        payloads[f"/baseline/{key}"] = baseline
        payloads[f"/source/{key}"] = candidate
        shared.append({"id": key, "path": path, "class": item["class"],
                       "baselineBytes": len(baseline), "baselineSha256": digest(baseline),
                       "bytes": len(candidate), "sha256": digest(candidate)})

    assert len(new) == 19 and len(shared) == 4, "unexpected Level 6 install scope"
    manifest = {"schema": "level6-gameplay-install-v1", "placeId": 131311258779917,
                "universeId": 10559217407, "new": new, "shared": shared}
    manifest["snapshotSha256"] = digest(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode())
    payloads["/manifest"] = json.dumps(manifest, separators=(",", ":")).encode()
    return manifest, payloads


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8880)
    parser.add_argument("--check", action="store_true", help="validate and print the scope without serving")
    args = parser.parse_args()
    manifest, payloads = snapshot()
    print(f"Level 6 snapshot {manifest['snapshotSha256']}: "
          f"{len(manifest['new'])} new scripts, {len(manifest['shared'])} guarded edits", flush=True)
    if args.check:
        for item in manifest["new"] + manifest["shared"]:
            print(f"{item['class']:<12} {item['bytes']:>7}  {item['path']}")
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

    print(f"Serving validated Level 6 snapshot at http://127.0.0.1:{args.port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
