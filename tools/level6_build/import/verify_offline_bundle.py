"""Read-only integrity check for the Level 6 source and guarded install snapshot."""

from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import re
import runpy
import struct


ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "assets/level6-worn-party"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_generated_luau_table(source: str) -> dict:
    """Read the literal table emitted for the kit; executable Luau is not accepted."""
    body = source.split("return ", 1)[1]
    token_pattern = re.compile(r'\s*(\{|\}|\[|\]|=|,|"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)')
    tokens = []
    position = 0
    for match in token_pattern.finditer(body):
        assert not body[position:match.start()].strip(), "Unexpected kit metadata syntax"
        tokens.append(match.group(1))
        position = match.end()
    assert not body[position:].strip(), "Unexpected kit metadata trailer"
    cursor = 0

    def read(expected: str | None = None) -> str:
        nonlocal cursor
        token = tokens[cursor]
        cursor += 1
        if expected is not None:
            assert token == expected, (expected, token)
        return token

    def value():
        if tokens[cursor] == "{":
            read("{")
            entries = []
            keyed = False
            while tokens[cursor] != "}":
                if tokens[cursor] == "[":
                    keyed = True
                    read("[")
                    key = json.loads(read())
                    read("]")
                    read("=")
                    entries.append((key, value()))
                else:
                    assert not keyed, "Mixed kit metadata table"
                    entries.append(value())
                if tokens[cursor] == ",":
                    read(",")
                else:
                    assert tokens[cursor] == "}"
            read("}")
            return dict(entries) if keyed else entries
        token = read()
        return json.loads(token) if token.startswith('"') else float(token)

    result = value()
    assert cursor == len(tokens) and isinstance(result, dict)
    return result


def numeric_tree_matches(actual, expected) -> bool:
    if isinstance(expected, dict):
        if not expected and actual == []:
            return True  # An empty Luau table has no list/dictionary distinction.
        return isinstance(actual, dict) and actual.keys() == expected.keys() and all(
            numeric_tree_matches(actual[key], val) for key, val in expected.items()
        )
    if isinstance(expected, list):
        return isinstance(actual, list) and len(actual) == len(expected) and all(
            numeric_tree_matches(a, b) for a, b in zip(actual, expected)
        )
    return isinstance(actual, (float, int)) and abs(actual - expected) <= 1e-5


def check() -> dict:
    export = json.loads((ASSETS / "exports-v2/manifest.json").read_text())
    kit = json.loads((ASSETS / "kit-manifest-v2.json").read_text())
    atlas = json.loads((ASSETS / "runtime-source/atlas-pixels.json").read_text())
    chunks = export["chunks"]
    assert export["schema"] == "level6-blender-prefabs-v1"
    assert export["axisMapping"] == "X,Z,-Y" and export["studsPerUnit"] == 1
    assert len(chunks) == 49 and [c["id"] for c in chunks] == list(range(49))
    names = [c["name"] for c in chunks]
    assert len(set(names)) == 49 and set(names) == set(kit["assets"])
    triangles = 0
    raw_bytes = 0
    for chunk in chunks:
        encoded = (ASSETS / "exports-v2" / chunk["file"]).read_bytes()
        raw = base64.b64decode(encoded, validate=True)
        assert len(raw) == chunk["bytes"] and sha256(raw) == chunk["sha256"], chunk["name"]
        magic, vertices, normals, uvs, faces = struct.unpack_from("<IIIII", raw)
        assert magic == 0x364D564C and faces == chunk["triangles"], chunk["name"]
        assert (vertices, normals, uvs) == (
            chunk["vertices"], chunk["normals"], chunk["uvs"]
        ), chunk["name"]
        assert len(raw) == 20 + vertices * 12 + normals * 12 + uvs * 8 + faces * 36
        authored = kit["assets"][chunk["name"]]
        assert authored["triangles"] == faces, chunk["name"]
        # kit-manifest-v2 records visible Blender collection geometry. The
        # export manifest adds gameplay collision and prompt-anchor metadata.
        triangles += faces
        raw_bytes += len(raw)

    rgba = base64.b64decode(
        (ASSETS / "runtime-source/atlas-rgba.b64").read_bytes(), validate=True
    )
    assert (atlas["width"], atlas["height"]) == (1024, 1024)
    assert len(rgba) == atlas["bytes"] == atlas["width"] * atlas["height"] * 4
    assert sha256(rgba) == atlas["sha256"]
    png = (ASSETS / "exports-v2" / export["atlas"]).read_bytes()
    assert sha256(png) == atlas["originalPngSha256"]

    metadata = (
        ROOT
        / "tools/level6_build/gameplay-candidates/Level 6 Kit Metadata.ModuleScript.luau"
    ).read_text()
    found = parse_generated_luau_table(metadata)
    assert len(found) == 49 and found.keys() == set(names)
    by_name = {c["name"]: c for c in chunks}
    for name, data in found.items():
        chunk = by_name[name]
        assert data.keys() == {"Center", "Size", "Colliders", "Anchors", "Triangles"}, name
        assert numeric_tree_matches(data["Center"], chunk["center"]), name
        assert numeric_tree_matches(data["Size"], chunk["size"]), name
        assert numeric_tree_matches(data["Colliders"], chunk["colliders_xyz"]), name
        assert numeric_tree_matches(data["Anchors"], chunk["anchors_xyz"]), name
        assert data["Triangles"] == chunk["triangles"], name

    serve = runpy.run_path(str(ROOT / "tools/level6_build/import/serve_gameplay_candidates.py"))
    snapshot, payloads = serve["snapshot"]()
    assert len(snapshot["new"]) == 19 and len(snapshot["shared"]) == 4
    assert snapshot["snapshotSha256"] == "23a305861ebff83d884b77cf504212abc3728f52a400f0e41e83ec5d60c7eae9"
    assert all(sha256(payloads["/source/" + item["id"]]) == item["sha256"]
               for item in snapshot["new"] + snapshot["shared"])
    assert all(sha256(payloads["/baseline/" + item["id"]]) == item["baselineSha256"]
               for item in snapshot["shared"])
    old_snapshot = json.loads(json.dumps(snapshot))
    old_kit = next(item for item in old_snapshot["new"] if item["path"] == serve["KIT_METADATA_TARGET"])
    old_kit["bytes"] = 8761
    old_kit["sha256"] = serve["INSTALLED_KIT_METADATA_SHA256"]
    del old_snapshot["snapshotSha256"]
    reconstructed_installed = sha256(
        json.dumps(old_snapshot, sort_keys=True, separators=(",", ":")).encode()
    )
    assert reconstructed_installed == "90b5d1e68587d4a213dea9e4666ad67d017342033561ecae7aebac4ee61220d1"
    return {
        "snapshotSha256": snapshot["snapshotSha256"],
        "reconstructedInstalledSnapshotSha256": reconstructed_installed,
        "newScripts": len(snapshot["new"]),
        "guardedSharedEdits": len(snapshot["shared"]),
        "prefabs": len(chunks),
        "uniqueTriangles": triangles,
        "meshPayloadRawBytes": raw_bytes,
        "atlasRGBABytes": len(rgba),
        "atlasRGBASha256": sha256(rgba),
        "atlasPNGSha256": sha256(png),
        "metadataEntries": len(found),
        "metadataFieldsCompared": ["Center", "Size", "Colliders", "Anchors", "Triangles"],
    }


if __name__ == "__main__":
    print(json.dumps(check(), indent=2))
