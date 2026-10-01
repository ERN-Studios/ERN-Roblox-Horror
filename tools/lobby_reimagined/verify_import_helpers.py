#!/usr/bin/env python3
"""Meaningful local transport/installer refusal checks. No server or Studio access."""
import base64
import json
from pathlib import Path
import struct
import subprocess
import tempfile

from serve import load_package, sha
from install import TEMPLATE, long_string


def main():
    task = Path("artifacts/lobby-reimagined-20261001")
    task.mkdir(parents=True, exist_ok=True)
    checks = []
    with tempfile.TemporaryDirectory(prefix="lobby-reimagined-helper-") as temporary:
        root = Path(temporary)
        package = root / "package"
        (package / "chunks").mkdir(parents=True)
        raw = bytearray(struct.pack("<5I", 0x364D564C, 4, 1, 3, 4))
        for xyz in ((-.5, -.5, -.5), (.5, -.5, -.5), (0, .5, -.5), (0, 0, .5)):
            raw.extend(struct.pack("<3f", *xyz))
        raw.extend(struct.pack("<3f", 0, 1, 0))
        for uv in ((0, 0), (1, 0), (.5, 1)):
            raw.extend(struct.pack("<2f", *uv))
        for triangle in ((0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3)):
            raw.extend(struct.pack("<9I", *[item for corner, vertex in enumerate(triangle) for item in (vertex, 0, corner)]))
        (package / "chunks/c00000.b64").write_bytes(base64.b64encode(raw))
        atlas = bytes((120, 130, 110, 255)) * (1024 * 1024)
        (package / "atlas.rgba.b64").write_bytes(base64.b64encode(atlas))
        chunk = {"id": 0, "name": "Fixture", "file": "chunks/c00000.b64", "sha256": sha(raw),
                 "bytes": len(raw), "vertices": 4, "triangles": 4, "center": [0, 0, 0], "size": [1, 1, 1]}
        manifest = {"schema": "lobby-reimagined-blender-v1", "chunks": [chunk], "prefabs": [{"name": "Fixture", "chunkId": 0}],
                    "atlas": {"width": 1024, "height": 1024, "file": "atlas.rgba.b64"},
                    "placements": [{"family": "Fixture", "robloxPosition": [0, 0, 0], "yaw": 0}]}
        manifest_file = package / "manifest.json"
        manifest_file.write_text(json.dumps(manifest))
        loaded = load_package(package)
        assert loaded["plan"]["manifestSha256"] == sha(manifest_file.read_bytes())
        checks.append("valid binary geometry/atlas package accepted and original manifest bytes SHA-pinned")
        manifest["chunks"][0]["sha256"] = "0" * 64
        manifest_file.write_text(json.dumps(manifest))
        try:
            load_package(package)
        except AssertionError:
            checks.append("wrong mesh SHA rejected")
        else:
            raise AssertionError("Wrong SHA accepted")
        manifest["chunks"][0]["sha256"] = sha(raw)
        manifest_file.write_text(json.dumps(manifest))
        outside = root / "outside.b64"; outside.write_bytes(base64.b64encode(raw))
        manifest["chunks"][0]["file"] = "../outside.b64"
        manifest_file.write_text(json.dumps(manifest))
        try:
            load_package(package)
        except ValueError:
            checks.append("path traversal outside package rejected")
        else:
            raise AssertionError("Path traversal accepted")
        manifest["chunks"][0]["file"] = "chunks/c00000.b64"
        manifest_file.write_text(json.dumps(manifest))
        client = root / "client.luau"; client.write_text("-- synthetic local compilation fixture only\nreturn nil\n")
        sources = root / "sources.json"
        source_row = {"key": "queue-controller", "path": "StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController",
                      "class": "LocalScript", "file": "client.luau"}
        sources.write_text(json.dumps({"sources": [source_row]}))
        loaded = load_package(package, sources)
        assert len(loaded["plan"]["sources"]) == 2
        checks.append("new client Source allowlist accepted without duplicating default RuntimeBake")
        source_row.update({"path": "ServerScriptService.TunnelLobbyBuilder", "class": "ModuleScript"})
        sources.write_text(json.dumps({"sources": [source_row]}))
        try:
            load_package(package, sources)
        except AssertionError:
            checks.append("existing/unrelated Studio Source namespace rejected")
        else:
            raise AssertionError("Existing namespace accepted")
        plan = json.dumps(loaded["plan"], separators=(",", ":"))
        generated = TEMPLATE.replace("__BASE__", long_string("http://127.0.0.1:8892")).replace("__PLAN__", long_string(plan))
        candidate = root / "installer.luau"; candidate.write_text(generated)
        compiler = root / "compile.luau"
        compiler.write_text('local fs=require("@lune/fs")\nlocal luau=require("@lune/luau")\n'
                            + f'luau.compile(fs.readFile({json.dumps(str(Path(__file__).parent.resolve() / "runtime_bake.ModuleScript.luau"))}))\n'
                            + f'luau.compile(fs.readFile({json.dumps(str(candidate))}))\n'
                            + 'print("RuntimeBake and generated installer compile; neither executed")\n')
        completed = subprocess.run(["/private/tmp/level6-lune-20261001/lune", "run", str(compiler)], capture_output=True, text=True, check=True)
        checks.append(completed.stdout.strip())
    report = {"schema": "lobby-reimagined-import-helper-verification-v1", "passed": True, "checks": checks,
              "limits": ["Synthetic payload only; actual Blender package still needs the same verification.",
                         "No HTTP server, live Studio, asset upload, runtime rendering, replication or performance check executed."]}
    output = task / "import-helper-verification.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
