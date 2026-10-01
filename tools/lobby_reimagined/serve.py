#!/usr/bin/env python3
"""Validate/serve only the isolated lobby Blender package and approved new Sources."""
import argparse
import base64
import hashlib
import http.server
import json
import math
from pathlib import Path
import re
import struct

PLACE, UNIVERSE, GROUP = 131311258779917, 10559217407, 1039373905
SCHEMA = "lobby-reimagined-blender-v1"
SOURCE_NAME = "LobbyReimaginedBlenderSource20261001R2"
SYSTEM_NAME = "LobbyReimaginedPreview"
MAGIC = 0x364D564C
HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inside(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError("Package file is absent or escapes root: " + str(relative))
    return path


def load_package(directory, sources_manifest=None, source_name=SOURCE_NAME, allow_r3_shared=False):
    assert source_name in {SOURCE_NAME,"LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B"}
    assert not allow_r3_shared or source_name in {"LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B"}
    shared_paths = {"ServerScriptService.GameManager":"Script", "ServerScriptService.LobbyShopDisplay":"ModuleScript",
                    "ServerScriptService.Level4PreviewAccess":"Script", "ServerScriptService.Level5PreviewAccess":"Script",
                    "ServerScriptService.Level6PreviewAccess":"Script",
                    "ServerScriptService.Level4V4PreviewAccess":"Script"}
    root = Path(directory).resolve(strict=True)
    manifest_bytes = inside(root, "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    assert manifest["schema"] == SCHEMA, "Wrong lobby package schema"
    for key, expected in (("placeId", PLACE), ("universeId", UNIVERSE), ("groupId", GROUP)):
        assert manifest.get(key, expected) == expected, "Wrong package " + key
    chunks, encoded_chunks, families = [], {}, set()
    assert isinstance(manifest["chunks"], list) and 0 < len(manifest["chunks"]) <= 512
    for index, supplied in enumerate(manifest["chunks"]):
        chunk = dict(supplied)
        assert type(chunk["id"]) is int and chunk["id"] == index, "Chunks must have ordered unique IDs"
        family = chunk.get("family") or chunk["name"]
        assert isinstance(family, str) and re.fullmatch(r"[A-Za-z0-9_ -]{1,100}", family)
        assert family not in families, "One mesh chunk is required per prefab family"
        families.add(family)
        encoded = inside(root, chunk["file"]).read_bytes()
        raw = base64.b64decode(encoded, validate=True)
        assert len(raw) == chunk["bytes"] and sha(raw) == chunk["sha256"], "Mesh SHA/bytes mismatch"
        magic, nv, nn, nu, nf = struct.unpack_from("<5I", raw)
        assert magic == MAGIC and 0 < nv <= 60000 and 0 < nn <= 60000 and 0 < nu <= 60000 and 0 < nf <= 20000
        assert len(raw) == 20 + nv * 12 + nn * 12 + nu * 8 + nf * 36
        assert chunk["triangles"] == nf and chunk.get("vertices", nv) == nv
        for key in ("center", "size"):
            assert len(chunk[key]) == 3 and all(math.isfinite(v) for v in chunk[key])
        assert all(0 < v < 2048 for v in chunk["size"]), "Invalid prefab size"
        values = struct.unpack_from(f"<{nv*3+nn*3+nu*2}f", raw, 20)
        assert all(math.isfinite(v) for v in values), "Non-finite mesh attribute"
        for face in struct.iter_unpack("<9I", raw[20 + nv*12 + nn*12 + nu*8:]):
            for corner in range(3):
                assert face[corner*3] < nv and face[corner*3+1] < nn and face[corner*3+2] < nu
        chunk["family"] = family
        chunks.append(chunk)
        encoded_chunks[index] = encoded
    prefabs = manifest.get("prefabs")
    if prefabs is not None:
        names = [entry if isinstance(entry, str) else entry["name"] for entry in prefabs]
        assert len(names) == len(set(names)) and set(names) == families, "Prefab/chunk names differ"
        for prefab in prefabs:
            if isinstance(prefab, dict) and "chunkId" in prefab:
                assert chunks[prefab["chunkId"]]["family"] == prefab["name"]
    for placement in manifest.get("placements", []):
        assert placement["family"] in families
        assert len(placement["robloxPosition"]) == 3
        assert all(math.isfinite(v) for v in placement["robloxPosition"])
        assert math.isfinite(placement.get("yaw", 0))
    atlas = manifest["atlas"]
    assert atlas["width"] == atlas["height"] == 1024
    atlas_encoded = inside(root, atlas["file"]).read_bytes()
    atlas_raw = base64.b64decode(atlas_encoded, validate=True)
    assert len(atlas_raw) == 1024 * 1024 * 4, "Atlas must be exact RGBA1024"
    assert atlas.get("sha256", sha(atlas_raw)) == sha(atlas_raw)
    source_rows = [{"key": "runtime-bake", "path": f"ServerScriptService.{SYSTEM_NAME}.RuntimeBake",
                    "class": "ModuleScript", "file": str(HERE / "runtime_bake.ModuleScript.luau")}]
    if sources_manifest:
        extra = json.loads(Path(sources_manifest).read_bytes())
        source_rows.extend(extra.get("sources", []) if isinstance(extra, dict) else extra)
    scripts, source_specs, keys, paths = {}, [], set(), set()
    for row in source_rows:
        key, path, cls = row["key"], row["path"], row["class"]
        assert re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", key) and key not in keys
        assert cls in {"ModuleScript", "Script", "LocalScript"} and path not in paths
        assert (path.startswith(f"ServerScriptService.{SYSTEM_NAME}.") and cls in {"ModuleScript", "Script"}) or (
            path == "StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController" and cls == "LocalScript") or (
            path.startswith(f"ReplicatedStorage.{SYSTEM_NAME}.") and cls == "ModuleScript") or (
            allow_r3_shared and shared_paths.get(path) == cls), "Source outside approved R3 scope"
        assert len(path.split(".")) == 3 or (allow_r3_shared and path in shared_paths), "Only direct approved Sources are allowed"
        source_path = Path(row["file"])
        if not source_path.is_absolute() and sources_manifest:
            source_path = Path(sources_manifest).resolve().parent / source_path
        data = source_path.resolve(strict=True).read_bytes()
        data.decode("utf-8")
        assert len(data) <= 500000, "Source too large"
        keys.add(key); paths.add(path); scripts[key] = data
        source_specs.append({"key": key, "path": path, "class": cls, "bytes": len(data), "sha256": sha(data)})
    plan = {"schema": "lobby-reimagined-install-plan-v1", "placeId": PLACE, "universeId": UNIVERSE,
            "groupId": GROUP, "sourceName": source_name, "manifestSha256": sha(manifest_bytes),
            "manifestBytes": len(manifest_bytes), "chunks": chunks,
            "atlas": {"width": 1024, "height": 1024, "bytes": len(atlas_raw), "sha256": sha(atlas_raw)},
            "sources": source_specs}
    return {"root": root, "manifestBytes": manifest_bytes, "manifest": manifest, "chunks": encoded_chunks,
            "atlas": atlas_encoded, "scripts": scripts, "plan": plan}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--port", type=int, default=8892)
    parser.add_argument("--sources-manifest", type=Path)
    parser.add_argument("--source-name", choices=[SOURCE_NAME,"LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B"], default=SOURCE_NAME)
    parser.add_argument("--allow-r3-shared", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    assert 1024 <= args.port <= 65535
    package = load_package(args.root, args.sources_manifest, args.source_name, args.allow_r3_shared)
    plan_bytes = json.dumps(package["plan"], separators=(",", ":")).encode()
    if args.verify_only:
        print(json.dumps({"passed": True, "manifestSha256": package["plan"]["manifestSha256"],
                          "chunks": len(package["chunks"]), "sources": len(package["scripts"]),
                          "atlasSha256": package["plan"]["atlas"]["sha256"]}))
        return

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            body, kind = None, "text/plain"
            if self.path == "/manifest": body, kind = package["manifestBytes"], "application/json"
            elif self.path == "/source-module-manifest": body, kind = plan_bytes, "application/json"
            elif self.path == "/atlas-pixels": body = package["atlas"]
            elif re.fullmatch(r"/chunk/[0-9]+", self.path): body = package["chunks"].get(int(self.path[7:]))
            elif re.fullmatch(r"/script/[a-z0-9-]+", self.path): body = package["scripts"].get(self.path[8:])
            if body is None:
                self.send_error(404, "Path is not allowlisted")
                return
            self.send_response(200); self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    print(f"Isolated lobby package on http://127.0.0.1:{args.port}; {len(package['chunks'])} verified chunks", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
