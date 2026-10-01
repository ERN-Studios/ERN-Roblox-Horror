"""Compare authoritative Studio native snapshots with the revised Level 6 kit.

Read-only: deserializes each captured .rbxm with Lune, checks raw compressed
StringValue payloads and MaterialVariant properties, then compares all captured
Source/editor records. It writes only a small local verification JSON.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT / "artifacts/level6-studio-revision-20261001"
BEFORE = TASK / "native-before"
AFTER = TASK / "native-after"
PACKAGE = TASK / "import-package"
IMAGE_RUNTIME = PACKAGE / "images-runtime.json"
MATERIAL_ROUTES = TASK / "materials-studio/material-routes.json"
ASSET_IDS = TASK / "materials-studio/asset-ids.normalized.json"
SCRIPT_MANIFEST = TASK / "scoped-script-manifest.json"
EXTRACTOR = Path(__file__).with_name("extract_native_revision_snapshot.luau")
DEFAULT_LUNE = Path("/private/tmp/level6-lune-20261001/lune")
PLACE_LIMIT_BYTES = 100 * 1024 * 1024


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha_file(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def json_file(path: Path):
    return json.loads(path.read_text())


def extract(lune: Path, backup: Path, output: Path, phase: str):
    for required in ("metadata.json", "scripts.json", "all-service-children.rbxm"):
        if not (backup / required).is_file():
            raise FileNotFoundError(f"{phase} native capture is incomplete: {backup / required}")
    run = subprocess.run(
        [str(lune), "run", str(EXTRACTOR), str(backup), str(output), phase],
        cwd=ROOT, capture_output=True, text=True, timeout=240,
    )
    if run.returncode:
        raise RuntimeError(f"Lune {phase} native extraction failed: {run.stderr.strip()[:1400]}")
    return json_file(output / f"{phase}-native-snapshot.json")


def payload_bytes(output: Path, record):
    encoded = (output / record["file"]).read_bytes()
    assert len(encoded) == record["encodedBytes"], record["file"]
    compressed = base64.b64decode(encoded, validate=True)
    assert record["attributes"]["CompressedBytes"] == len(compressed), record["file"]
    raw = subprocess.run(["zstd", "-d", "-c"], input=compressed,
                         capture_output=True, check=True, timeout=30).stdout
    assert record["attributes"]["RawBytes"] == len(raw), record["file"]
    return compressed, raw


def source_fingerprint(source, output):
    # Compressed payload bytes are compared too; keeping the same uncompressed
    # geometry alone would not prove the old native folder was untouched.
    result = {"strings": source["strings"], "attributes": source["attributes"], "payloads": {}}
    for name, record in source["payloads"].items():
        encoded = (output / record["file"]).read_bytes()
        result["payloads"][name] = {
            "encodedSha256": sha_bytes(encoded),
            "attributes": record["attributes"],
            "pieces": record["pieces"],
        }
    return result


def check_level3_roots(before, after, output):
    assert before["level3Roots"] and set(before["level3Roots"]) == set(after["level3Roots"]), \
        "Original Level 3 native roots were removed or added"
    for path, old in before["level3Roots"].items():
        new = after["level3Roots"][path]
        old_file, new_file = output / old["file"], output / new["file"]
        assert old["bytes"] == old_file.stat().st_size
        assert new["bytes"] == new_file.stat().st_size
        assert sha_file(old_file) == sha_file(new_file), f"Original Level 3 native root changed: {path}"
    return sorted(before["level3Roots"])


def check_native_root_changes(before, after, output, scope, materials):
    old_roots, new_roots = before["rootRecords"], after["rootRecords"]
    assert len(old_roots) >= 170
    expected_changed = set()
    for script in scope["scripts"]:
        matches = [path for path in old_roots if script["path"] == path or
                   script["path"].startswith(path + ".")]
        assert matches, f"No native root contains scoped script {script['path']}"
        expected_changed.add(max(matches, key=len))
    expected_added = {"ServerStorage.Level6BlenderSourceRevision20261001"} | {
        "MaterialService." + item["name"] for item in materials["variants"].values()
    }
    assert expected_added <= set(new_roots) - set(old_roots), "Revised source or variants absent from native roots"
    changes = []
    for path in sorted(set(old_roots) | set(new_roots)):
        old, new = old_roots.get(path), new_roots.get(path)
        old_hash = sha_file(output / old["file"]) if old else None
        new_hash = sha_file(output / new["file"]) if new else None
        if old_hash == new_hash:
            continue
        changes.append({"path": path, "kind": "added" if not old else "removed" if not new else "changed",
                        "beforeSHA256": old_hash, "afterSHA256": new_hash})
    changed = {item["path"] for item in changes}
    assert expected_changed <= changed, "Scoped native script root did not change"
    assert expected_added <= changed
    other = [item for item in changes if item["path"] not in expected_changed | expected_added]
    return {"expectedChangedRoots": sorted(expected_changed),
            "expectedAddedRoots": sorted(expected_added), "otherNativeRootChanges": other}


def service_changes(before_metadata, after_metadata):
    old = {item["class"]: item for item in before_metadata["services"]}
    new = {item["class"]: item for item in after_metadata["services"]}
    changes = []
    for name in sorted(set(old) | set(new)):
        previous, current = old.get(name), new.get(name)
        if previous != current:
            changes.append({
                "service": name,
                "kind": "added" if previous is None else "removed" if current is None else "changed",
                "changedProperties": sorted(key for key in set((previous or {}).get("properties", {})) |
                                            set((current or {}).get("properties", {}))
                                            if (previous or {}).get("properties", {}).get(key) !=
                                            (current or {}).get("properties", {}).get(key)),
                "changedAttributes": sorted(key for key in set((previous or {}).get("attributes", {})) |
                                            set((current or {}).get("attributes", {}))
                                            if (previous or {}).get("attributes", {}).get(key) !=
                                            (current or {}).get("attributes", {}).get(key)),
                "beforeSHA256": sha_bytes(json.dumps(previous, sort_keys=True).encode()) if previous else None,
                "afterSHA256": sha_bytes(json.dumps(current, sort_keys=True).encode()) if current else None,
            })
    for property_name in ("collisionGroups", "collisionMatrix", "materialOverrides"):
        if before_metadata.get(property_name) != after_metadata.get(property_name):
            changes.append({"property": property_name,
                            "beforeSHA256": sha_bytes(json.dumps(before_metadata.get(property_name), sort_keys=True).encode()),
                            "afterSHA256": sha_bytes(json.dumps(after_metadata.get(property_name), sort_keys=True).encode())})
    return changes


def map_id(value):
    assert isinstance(value, dict) and "sourceType" in value, \
        f"Native MaterialVariant Content map unreadable: {value}"
    if value["sourceType"] == "Enum.ContentSourceType.None":
        assert value.get("uri") is None, value
        return None
    assert value["sourceType"] == "Enum.ContentSourceType.Uri", value
    uri = value.get("uri")
    assert isinstance(uri, str) and re.fullmatch(r"rbxassetid://\d{8,}", uri), value
    return int(uri.rsplit("/", 1)[-1])


def check_material_routes(package, runtime, materials):
    """Pin each split mesh and each installed map to its authored route."""
    routes = json_file(MATERIAL_ROUTES)
    asset_ids = json_file(ASSET_IDS)
    assert materials["sourceMaterialManifestSha256"] == routes["sourceMaterialManifestSha256"]
    assert len(routes["routes"]) == len(package["chunks"]) == len(runtime["chunks"]) == 279
    assert len(routes["variants"]) == len(materials["variants"]) == 9
    assert len(asset_ids) == len(routes["images"]) == 27
    assert materials["propsAtlasAssetId"] == asset_ids["props__color"]
    image_keys = {image["key"] for image in routes["images"]}
    assert image_keys == set(asset_ids)
    for image in routes["images"]:
        assert sha_file(ROOT / image["source"]) == image["sha256"], image["key"]
    for index, (route, chunk, live_chunk) in enumerate(zip(routes["routes"], package["chunks"], runtime["chunks"])):
        assert (route["chunkId"], route["family"], route["childName"], route["object"], route["material"]) == (
            index, chunk["family"], chunk["name"], chunk["object"], chunk["material"]), index
        assert (live_chunk["id"], live_chunk["name"], live_chunk["family"]) == (
            index, chunk["name"], chunk["family"]), index
        variant_key = route.get("variantKey")
        if variant_key:
            expected_name = routes["variants"][variant_key]["name"]
            assert live_chunk["materialVariant"] == chunk["materialVariant"] == expected_name, index
            assert chunk["runtimeSurface"] == variant_key, index
        else:
            assert route["atlasImageKey"] == "props__color", index
            assert chunk["materialVariant"] is None and live_chunk["materialVariant"] is None, index
    for key, route in routes["variants"].items():
        installed = materials["variants"][key]
        assert installed["name"] == route["name"] and installed["baseMaterial"] == route["baseMaterial"]
        assert installed["studsPerTile"] == route["studsPerTile"]
        assert installed["mapAssetIds"] == {
            map_name: asset_ids[image_key] for map_name, image_key in route["mapImageKeys"].items()
        }, key
    return {"routedChunks": 279, "verifiedImageHashes": 27, "variantDefinitions": 9}


def check_variants(snapshot, materials):
    expected = {item["name"]: item for item in materials["variants"].values()}
    found = snapshot["variants"]
    assert set(found) == set(expected), {"missing": sorted(set(expected)-set(found)),
                                         "extra": sorted(set(found)-set(expected))}
    map_props = {"color": "colorMap", "normalOpenGL": "normalMap",
                 "roughness": "roughnessMap", "metalness": "metalnessMap"}
    verified = []
    for name, route in expected.items():
        native = found[name]
        assert native["class"] == "MaterialVariant", name
        assert native["baseMaterial"].endswith("SmoothPlastic"), (name, native["baseMaterial"])
        assert abs(float(native["studsPerTile"]) - float(route["studsPerTile"])) < .001, name
        for map_name, asset_id in route["mapAssetIds"].items():
            property_name = map_props[map_name]
            assert map_id(native[property_name]) == asset_id, (name, property_name,
                                                                 native[property_name], asset_id)
        for map_name, property_name in map_props.items():
            if map_name not in route["mapAssetIds"]:
                assert map_id(native[property_name]) is None, (name, property_name, native[property_name])
        verified.append(name)
    return sorted(verified)


def check_revision_source(source, output, package, runtime, materials):
    assert source["class"] == "Folder"
    assert source["attributes"]["Ready"] is True
    assert source["attributes"]["Version"] == "Level6Revised20261001"
    assert source["attributes"]["SourceBlendSHA256"] == package["sourceBlendSha256"]
    assert source["attributes"]["InstalledCount"] == 279
    assert json.loads(source["strings"]["ManifestJSON"]) == runtime
    assert json.loads(source["strings"]["MaterialsJSON"]) == materials
    payloads = source["payloads"]
    assert set(payloads) == {f"mesh-{i}" for i in range(279)}, "Revised raw source is missing or has extra chunks"
    total = 0
    for chunk in package["chunks"]:
        _, raw = payload_bytes(output, payloads[f"mesh-{chunk['id']}"])
        assert sha_bytes(raw) == chunk["sha256"], chunk["name"]
        assert len(raw) == chunk["bytes"], chunk["name"]
        magic, nv, _, _, nf = struct.unpack_from("<5I", raw)
        assert (magic, nv, nf) == (0x364D564C, chunk["vertices"], chunk["triangles"]), chunk["name"]
        total += nf
    assert total == runtime["uniqueTriangles"] == 74092
    return {"chunks": len(payloads), "triangles": total, "rawBytes": sum(c["bytes"] for c in package["chunks"])}


def check_revision_images(source, output, images):
    image_source = source.get("imageSource")
    if image_source is None:
        return None
    assert image_source["attributes"]["Ready"] is True
    assert image_source["attributes"]["InstalledCount"] == 27
    assert image_source["attributes"]["SourceBlendSHA256"] == images["sourceBlendSha256"]
    assert image_source["attributes"]["SourceMaterialRoutesSHA256"] == images["sourceMaterialRoutesSha256"]
    assert image_source["attributes"]["ImageManifestSHA256"] == sha_file(IMAGE_RUNTIME)
    assert json.loads(image_source["strings"]["ImagesJSON"]) == images
    assert len(image_source["payloads"]) == images["imageCount"] == 27
    assert set(image_source["payloads"]) == {"image-" + item["key"] for item in images["images"]}
    total_encoded, total_compressed = 0, 0
    for image in images["images"]:
        record = image_source["payloads"]["image-" + image["key"]]
        encoded = (output / record["file"]).read_bytes()
        assert len(encoded) == record["encodedBytes"] == image["base64Chars"]
        assert record["pieces"] == len(image["parts"])
        offset = 0
        for part in image["parts"]:
            piece = encoded[offset:offset + part["bytes"]]
            assert len(piece) == part["bytes"] and sha_bytes(piece) == part["sha256"], part["path"]
            offset += part["bytes"]
        assert offset == len(encoded)
        compressed = base64.b64decode(encoded, validate=True)
        assert len(compressed) == image["compressedBytes"] and sha_bytes(compressed) == image["compressedSha256"]
        raw = subprocess.run(["zstd", "-d", "-c"], input=compressed,
                             check=True, capture_output=True, timeout=30).stdout
        assert len(raw) == image["rgbaBytes"] == image["width"] * image["height"] * 4
        assert sha_bytes(raw) == image["rgbaSha256"]
        assert record["attributes"]["RGBABytes"] == image["rgbaBytes"]
        assert record["attributes"]["RGBASHA256"] == image["rgbaSha256"]
        assert record["attributes"]["CompressedBytes"] == image["compressedBytes"]
        assert record["attributes"]["CompressedSHA256"] == image["compressedSha256"]
        total_encoded += len(encoded)
        total_compressed += len(compressed)
    assert image_source["attributes"]["CompressedBytes"] == total_compressed
    return {"images": 27, "compressedBytes": total_compressed, "encodedBytes": total_encoded,
            "rgbaBytes": sum(item["rgbaBytes"] for item in images["images"])}


def script_records(backup: Path):
    metadata = json_file(backup / "metadata.json")
    records = json_file(backup / "scripts.json")
    assert metadata["scriptCount"] == len(records)
    assert not metadata["editorConflicts"] and not metadata["skipped"], backup
    assert all(item["editorMatch"] is True for item in records), backup
    mapped = {item["path"]: item for item in records}
    assert len(mapped) == len(records), "Duplicate script paths in native capture"
    return metadata, mapped


def check_scripts(before, after, scope):
    expected = {item["path"]: item for item in scope["scripts"]}
    assert len(expected) == len(scope["scripts"]) and len(expected) >= 7, \
        "Scoped manifest is missing or has duplicate script paths"
    changed = []
    for path, item in expected.items():
        assert path in before and path in after, path
        old_hash = sha_bytes(before[path]["source"].encode())
        new_hash = sha_bytes(after[path]["source"].encode())
        assert old_hash == item["beforeSHA256"], (path, "before source diverged")
        assert new_hash == item["afterSHA256"], (path, "after source differs from scoped candidate")
        assert sha_file(ROOT / item["candidateFile"]) == new_hash, (path, "local candidate file differs")
        assert before[path]["class"] == after[path]["class"], path
        assert old_hash != new_hash, (path, "scoped source did not change")
        changed.append(path)
    level3 = re.compile(r"(?:level[ _]?3|l3_)", re.IGNORECASE)
    level3_changes = []
    other_changes = []
    for path in sorted(set(before) | set(after)):
        if path in expected:
            continue
        old = before.get(path)
        new = after.get(path)
        old_hash = sha_bytes(old["source"].encode()) if old else None
        new_hash = sha_bytes(new["source"].encode()) if new else None
        if old_hash == new_hash and (not old or old["class"] == new["class"]):
            continue
        change = {"path": path, "beforeSHA256": old_hash, "afterSHA256": new_hash,
                  "kind": "added" if not old else "removed" if not new else "changed"}
        (level3_changes if level3.search(path) else other_changes).append(change)
    assert not level3_changes, f"Original Level 3 scripts changed: {level3_changes}"
    return {"scopedScripts": sorted(changed), "level3Unchanged": True,
            "otherDeveloperChanges": other_changes,
            "newScriptPaths": sorted(set(after)-set(before)),
            "removedScriptPaths": sorted(set(before)-set(after))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", type=Path, default=BEFORE)
    parser.add_argument("--after", type=Path, default=AFTER)
    parser.add_argument("--lune", type=Path, default=DEFAULT_LUNE)
    parser.add_argument("--scope", type=Path, default=SCRIPT_MANIFEST)
    parser.add_argument("--require-images", action="store_true")
    parser.add_argument("--output", type=Path, default=AFTER / "revision-native-verification.json")
    args = parser.parse_args()
    before_place = args.before / "BeforeLevel6-AuthoritativeStudio.rbxl"
    after_place = args.after / "AfterLevel6-AuthoritativeStudio.rbxl"
    assert before_place.is_file() and after_place.is_file(), "Both full native .rbxl backups are required"
    before_place_bytes, after_place_bytes = before_place.stat().st_size, after_place.stat().st_size
    assert after_place_bytes < PLACE_LIMIT_BYTES, \
        f"Revised native place exceeds Roblox 100 MiB limit: {after_place_bytes:,} bytes"
    after_place_report = json_file(args.after / "native-place-verification.json")
    assert not after_place_report["rootErrors"] and not after_place_report["sourceErrors"]
    assert after_place_report["nativePlaceBytes"] == after_place_bytes
    assert after_place_report["scriptCount"] >= 202
    package = json_file(PACKAGE / "manifest.json")
    runtime = json_file(PACKAGE / "runtime-manifest.json")
    materials = json_file(PACKAGE / "materials-runtime.json")
    images = json_file(IMAGE_RUNTIME)
    scope = json_file(args.scope)
    route_result = check_material_routes(package, runtime, materials)
    with tempfile.TemporaryDirectory(prefix="l6-native-verify-") as directory:
        temporary = Path(directory)
        native_before = extract(args.lune, args.before, temporary, "before")
        native_after = extract(args.lune, args.after, temporary, "after")
        assert native_before["placeId"] == native_after["placeId"] == 131311258779917
        assert native_before["universeId"] == native_after["universeId"] == 10559217407
        old = native_before["sources"]["Level6BlenderSource"]
        legacy_after = [source for name, source in native_after["sources"].items()
                        if name != "Level6BlenderSourceRevision20261001" and
                        json.loads(source["strings"].get("ManifestJSON", "{}"))
                        .get("schema") == "level6-blender-prefabs-v1"]
        assert len(legacy_after) == 1, "Legacy source was lost or duplicated"
        assert source_fingerprint(old, temporary) == source_fingerprint(legacy_after[0], temporary), \
            "Legacy Level 6 / Level 3 Blender source changed"
        level3_roots = check_level3_roots(native_before, native_after, temporary)
        native_root_result = check_native_root_changes(native_before, native_after,
                                                       temporary, scope, materials)
        revised = native_after["sources"]["Level6BlenderSourceRevision20261001"]
        raw_result = check_revision_source(revised, temporary, package, runtime, materials)
        image_result = check_revision_images(revised, temporary, images)
        assert image_result or not args.require_images, "The 27-image source is not installed"
        variant_result = check_variants(native_after, materials)
    before_metadata, before_scripts = script_records(args.before)
    after_metadata, after_scripts = script_records(args.after)
    assert len(before_scripts) == 202 and len(after_scripts) >= 202
    assert native_before["serializedScriptCount"] == len(before_scripts)
    assert native_after["serializedScriptCount"] == len(after_scripts)
    scripts_result = check_scripts(before_scripts, after_scripts, scope)
    other_service_changes = service_changes(before_metadata, after_metadata)
    result = {
        "schema": "level6-studio-revision-native-verification-v1",
        "placeId": native_after["placeId"], "universeId": native_after["universeId"],
        "beforePlaceVersion": before_metadata["placeVersion"],
        "afterPlaceVersion": after_metadata["placeVersion"],
        "beforeScriptCount": len(before_scripts), "afterScriptCount": len(after_scripts),
        "beforeNativeSha256": sha_file(args.before / "all-service-children.rbxm"),
        "afterNativeSha256": sha_file(args.after / "all-service-children.rbxm"),
        "beforePlaceBytes": before_place_bytes,
        "afterPlaceBytes": after_place_bytes,
        "placeLimitBytes": PLACE_LIMIT_BYTES,
        "afterPlaceSha256": sha_file(after_place),
        "packageManifestSha256": sha_file(PACKAGE / "manifest.json"),
        "runtimeManifestSha256": sha_file(PACKAGE / "runtime-manifest.json"),
        "legacySourcePreserved": True,
        "level3NativeRootsUnchanged": level3_roots,
        **native_root_result,
        "otherServicePropertyChanges": other_service_changes,
        "revisionSource": raw_result,
        "revisionImageSource": image_result,
        "materialVariants": variant_result,
        "materialRoutes": route_result,
        "scriptSourceEditorParity": True,
        **scripts_result,
        "passed": True,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"passed": True, "rawChunks": raw_result["chunks"],
                      "materialVariants": len(variant_result),
                      "scopedScripts": len(scripts_result["scopedScripts"]),
                      "otherDeveloperChanges": len(scripts_result["otherDeveloperChanges"]),
                      "output": str(args.output)}, indent=2))


if __name__ == "__main__":
    main()
