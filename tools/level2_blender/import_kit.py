"""Validate, stage, upload, install, and audit the Level 2 Blender kit.

The default command is offline. Studio modes require an exact --studio-id and
never select a session automatically. Run --plan again after uploads so the
staged installer contains the final receipt IDs.
"""

from __future__ import annotations

import argparse
import base64
import copy
import functools
import hashlib
import http.server
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys
import threading
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/level2/blender-kit"
EXPORT = ASSETS / "export"
POOL_EXPORT = ROOT / "assets/level2/poolrooms-kit/export"
PBR = Path("G:/Blender/Level2_Pool/textures/pbr")
POOL_PBR = Path("G:/Blender/Level2_Poolrooms/textures/pbr")
SPEC = ROOT / "tools/level2_blender/pbr_spec.json"
STAGING = Path("G:/Roblox/_local/l2blender/install_staging")
MESH_RECEIPTS = ASSETS / "roblox-assets.json"
TEXTURE_RECEIPTS = ASSETS / "textures-published.json"
PLACE_ID = 131311258779917
GROUP_ID = 1039373905
MESH_BATCH_BYTES = 850_000
MESH_SLICE_CHARS = 170_000  # two ~957 KB wires travel through persistent StringValues
INSTALL_PHASE_BYTES = 500_000
DATA_SLICE_CHARS = 180_000
LUAU_COMPILE = Path(
    "C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/"
    "LocalCache/Local/CodexTools/luau/0.737/luau-compile.exe"
)
MAP_PROPS = {"albedo": "ColorMap", "normal": "NormalMap", "rough": "RoughnessMap", "metal": "MetalnessMap"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
# Poolrooms one-tile-look rule (FIX_SPEC G1): prkit.TILE_RGB == Kit World Builder WHITE; TileShade/Worn are retired.
POOL_TILE_RGB = [241, 237, 220]
POOL_RETIRED_MATERIALS = {"TileShade", "Worn"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def djb2(data: bytes) -> int:
    value = 5381
    for byte in data:
        value = (value * 33 + byte) % 4294967296
    return value


def png_size(content: bytes, path: Path) -> tuple[int, int]:
    require(content[:8] == b"\x89PNG\r\n\x1a\n" and content[12:16] == b"IHDR" and
            len(content) >= 24, f"{path}: invalid PNG")
    return struct.unpack_from(">II", content, 16)


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def lua(value) -> str:
    """Write a native Luau literal, avoiding HttpService in the Studio sandbox."""
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        require(math.isfinite(value), "nonfinite Luau number")
        return repr(value)
    if isinstance(value, str):
        # JSON's common string escapes are also Luau string escapes. Source
        # strings in this export are ASCII; keep non-ASCII as UTF-8, not \uXXXX.
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua(str(k)) + "]=" + lua(v) for k, v in value.items()) + "}"
    raise TypeError(type(value).__name__)


def check_vector(value, length: int, label: str) -> None:
    require(isinstance(value, list) and len(value) == length and
            all(isinstance(x, (int, float)) and math.isfinite(x) for x in value),
            f"{label}: expected {length} finite numbers")


def check_attrs(attrs, label: str) -> None:
    require(isinstance(attrs, dict), f"{label}: attrs must be an object")
    for key, value in attrs.items():
        require(isinstance(key, str) and key, f"{label}: empty attribute name")
        if isinstance(value, (float, int)) and not isinstance(value, bool):
            require(math.isfinite(value), f"{label}.{key}: nonfinite attribute")
        elif isinstance(value, (dict, list)):
            json.dumps(value, allow_nan=False)
        else:
            require(isinstance(value, (str, bool)), f"{label}.{key}: unsupported attribute")


def validate_export(export: Path = EXPORT, profile: str = "c") -> dict:
    """Read every exported byte and cross-check the manifest and slide schema."""
    raw_manifest = (export / "manifest.json").read_bytes()
    manifest = json.loads(raw_manifest)
    chunk_paths = [export / "chunks" / f"c{i:05d}.b64" for i in range(len(manifest["chunks"]))]
    if profile == "poolrooms":
        require(export.resolve() == POOL_EXPORT.resolve(), "poolrooms profile requires its canonical export")
        old = validate_export(EXPORT)
        old_manifest = old["manifest"]
        require(manifest["build"] == "level2-poolrooms", "wrong Poolrooms build")
        require(not set(manifest["components"]) & set(old_manifest["components"]),
                "Poolrooms component collides with previous kit")
        require(not set(manifest["materials"]) & {"ColDebug"}, "Poolrooms collision material conflict")
        require(not set(manifest["materials"]) & POOL_RETIRED_MATERIALS,
                "stale Poolrooms export: retired TileShade/Worn materials (rebuild the kit)")
        for name, material in manifest["materials"].items():
            if material.get("variant") in ("PR Tile", "PR Tile Aqua"):
                require(material["color"] == POOL_TILE_RGB,
                        f"{name}: Poolrooms tile colour must be {POOL_TILE_RGB} (FIX_SPEC G1)")
        # Poolrooms components with Template=true install into SlideTemplates as one collision MeshPart, exactly
        # like the SlideCol_* templates; records would be silently lost there, so refuse them.
        for name, info in manifest["components"].items():
            if info["attrs"].get("Template"):
                require(info["attrs"]["Template"] is True and len(info["chunks"]) == 1 and
                        not (info["parts"] or info["colliders"] or info["markers"]),
                        f"Poolrooms template {name}: needs exactly one mesh chunk and no part/collider/marker records")
        offset = len(manifest["chunks"])
        templates = {name: copy.deepcopy(info) for name, info in old_manifest["components"].items()
                     if name.startswith("SlideCol_") and info["attrs"].get("Template")}
        template_ids = sorted({i for info in templates.values() for i in info["chunks"]})
        remap = {old_id: offset + i for i, old_id in enumerate(template_ids)}
        for info in templates.values():
            info["chunks"] = [remap[i] for i in info["chunks"]]
        manifest["components"].update(templates)
        manifest["materials"]["ColDebug"] = old_manifest["materials"]["ColDebug"]
        manifest["chunks"].extend({**old_manifest["chunks"][i], "id": remap[i]}
                                  for i in template_ids)
        chunk_paths.extend(EXPORT / "chunks" / f"c{i:05d}.b64" for i in template_ids)
        slides = read_json(EXPORT / "slides.json")
        manifest_sha = sha(raw_manifest + old["manifest_sha"].encode() +
                          (EXPORT / "slides.json").read_bytes())
    else:
        slides = read_json(export / "slides.json")
        manifest_sha = sha(raw_manifest)
    require(manifest.get("version") == 1 and manifest.get("build") and
            manifest.get("scaleMetresPerStud") == 0.28, "wrong kit version, build, or scale")
    require(manifest.get("axis") == "Blender(x,y,z) -> Roblox(x,z,-y)", "wrong axis mapping")
    materials = manifest["materials"]
    components = manifest["components"]
    chunks = manifest["chunks"]
    require(isinstance(materials, dict) and isinstance(components, dict) and
            isinstance(chunks, list) and chunks, "missing materials/components/chunks")
    ids = [c["id"] for c in chunks]
    require(ids == list(range(len(chunks))), "chunk IDs must be contiguous in list order")
    chunk_files = {p.name for p in (export / "chunks").glob("c*.b64")}
    require(chunk_files == {f"c{i:05d}.b64" for i in range(len(chunk_paths) if profile == "c" else offset)},
            "chunk file inventory differs from manifest")
    by_hash = {}
    for c in chunks:
        label = f"chunk {c['id']}"
        require(c["component"] in components and c["material"] in materials,
                f"{label}: unknown component/material")
        wire = chunk_paths[c["id"]].read_text(encoding="ascii").strip()
        require(sha(wire.encode("ascii")) == c["wireSha256"], f"{label}: wire hash mismatch")
        blob = base64.b64decode(wire, validate=True)
        require(sha(blob) == c["sha256"], f"{label}: binary hash mismatch")
        require(len(blob) >= 16, f"{label}: short header")
        nv, nn, nu, nf = struct.unpack_from("<4I", blob)
        require(nv == c["verts"] and nf == c["tris"] and 0 < nv <= 60000 and
                0 < nn <= 60000 and 0 < nu <= 60000 and 0 < nf <= 20000,
                f"{label}: count/budget mismatch")
        offset = 16 + 12 * (nv + nn) + 8 * nu
        require(len(blob) == offset + 36 * nf, f"{label}: wire length mismatch")
        floats = struct.unpack_from(f"<{3 * (nv + nn) + 2 * nu}f", blob, 16)
        require(all(math.isfinite(v) for v in floats), f"{label}: nonfinite vertex/normal/UV")
        faces = struct.unpack_from(f"<{9 * nf}I", blob, offset)
        require(all(faces[i] < (nv, nn, nu)[i % 3] for i in range(len(faces))),
                f"{label}: out-of-range face index")
        check_vector(c["center"], 3, label + ".center")
        check_vector(c["size"], 3, label + ".size")
        require(min(c["size"]) > 0 and max(c["size"]) <= 1800,
                f"{label}: mesh bounds exceed budget")
        vertices = floats[:3 * nv]
        axes = [vertices[axis::3] for axis in range(3)]
        lows = [min(axis) for axis in axes]
        highs = [max(axis) for axis in axes]
        # Wire vertices are relative to manifest center. Flat meshes receive
        # the exporter's .01-stud token thickness for MeshPart.Size.
        require(all(abs((lo + hi) / 2) < .001 and
                    abs(max(hi - lo, .01) - size) < .001
                    for lo, hi, size in zip(lows, highs, c["size"])),
                f"{label}: wire bounds disagree with manifest center/size")
        by_hash.setdefault(c["wireSha256"], {"wire": wire, "ids": []})["ids"].append(c["id"])
    referenced = []
    for name, info in components.items():
        require(isinstance(name, str) and name and isinstance(info, dict), "invalid component")
        check_attrs(info["attrs"], name)
        require(all(isinstance(i, int) and 0 <= i < len(chunks) and chunks[i]["component"] == name
                    for i in info["chunks"]), f"{name}: invalid chunk reference")
        require(len({chunks[i]["material"] for i in info["chunks"]}) == len(info["chunks"]),
                f"{name}: duplicate chunk material would make mesh names ambiguous")
        referenced.extend(info["chunks"])
        for kind in ("parts", "colliders", "markers"):
            require(isinstance(info[kind], list), f"{name}: {kind} is not a list")
            for rec in info[kind]:
                require(isinstance(rec.get("name"), str) and rec["name"],
                        f"{name}: unnamed {kind} record")
                require(len(rec["cf"]) in (4, 12), f"{name}.{rec['name']}: bad CFrame")
                check_vector(rec["cf"], len(rec["cf"]), f"{name}.{rec['name']}.cf")
                check_attrs(rec["attrs"], f"{name}.{rec['name']}")
                if kind != "markers":
                    check_vector(rec["size"], 3, f"{name}.{rec['name']}.size")
                    require(min(rec["size"]) > 0, f"{name}.{rec['name']}: nonpositive size")
                if kind == "parts":
                    require(rec["material"] in materials and isinstance(rec["collide"], bool) and
                            isinstance(rec["ground"], bool), f"{name}.{rec['name']}: bad Part")
                    if "cframe" in rec:
                        frame = rec["cframe"]
                        for axis in ("position", "right", "up", "back"):
                            check_vector(frame[axis], 3, f"{name}.{rec['name']}.cframe.{axis}")
                if kind == "colliders":
                    require(rec["shape"] in ("Block", "Cylinder") and
                            isinstance(rec["ground"], bool), f"{name}.{rec['name']}: bad collider")
                if kind != "markers" and (rec.get("shape") == "Cylinder" or
                                          rec.get("properties", {}).get("Shape") == "Cylinder"):
                    native = rec["attrs"]
                    require(native.get("CylinderAxis") == "Y" and
                            all(isinstance(native.get(key), (int, float)) for key in
                                ("NativeSizeX", "NativeSizeY", "NativeSizeZ", "NativeRotationZ")) and
                            abs(native["NativeSizeX"] - rec["size"][1]) < .001 and
                            abs(native["NativeSizeY"] - rec["size"][0]) < .001 and
                            abs(native["NativeSizeZ"] - rec["size"][2]) < .001 and
                            native["NativeRotationZ"] == 90,
                            f"{name}.{rec['name']}: invalid vertical-cylinder native frame")
    require(sorted(referenced) == ids, "component chunks do not partition manifest chunks")
    normalized_slides = json.loads(json.dumps(slides))
    require(isinstance(slides.get("slideProfiles"), dict) and
            isinstance(slides.get("slides"), dict) and isinstance(slides.get("prefabs"), dict),
            "missing slide profiles/slides/prefabs")
    for name, slide_profile in normalized_slides["slideProfiles"].items():
        require(name in components, f"slide profile {name}: missing component")
        require(components[name]["attrs"].get("Template") is True,
                f"slide profile {name}: component is not a slide template")
        target = components[name]["chunks"]
        require(len(slide_profile.get("chunks", [])) == len(target),
                f"slide profile {name}: stale chunk count")
        if target:
            require(len(target) == 1 and len(slide_profile["chunks"]) == 1,
                    f"slide profile {name}: expected one unit chunk")
            c = chunks[target[0]]
            check_vector(slide_profile["size"], 3, f"slide profile {name}.size")
            check_vector(slide_profile["axisOffset"], 3, f"slide profile {name}.axisOffset")
            require(all(abs(a - b) < .001 for a, b in zip(slide_profile["size"], c["size"])) and
                    all(abs(a - b) < .001 for a, b in zip(slide_profile["axisOffset"], c["center"])),
                    f"slide profile {name}: geometry disagrees with final chunk")
        else:
            require(all(child in normalized_slides["slideProfiles"] and
                        components[child]["attrs"].get("Template") is True and
                        len(components[child]["chunks"]) == 1
                        for child in slide_profile.get("children", [])),
                    f"slide profile {name}: missing assembly child")
        slide_profile["chunks"] = target  # slides.json was copied from a slide-only export.
    def has_template(name: str) -> bool:
        return name in normalized_slides["slideProfiles"] and len(components[name]["chunks"]) == 1

    for name, slide in slides["slides"].items():
        require(slide["prefab"] in slides["prefabs"], f"slide {name}: unknown prefab")
        if profile == "c":
            require(all(c in components for c in slide.get("visualChunks", [])),
                    f"slide {name}: unknown visual component")
        require(all(key in slide["visualChunks"] for key in slide.get("visualPlacements", {})),
                f"slide {name}: unknown visual placement")
        if slide.get("tub"):
            tub = slide["tub"]
            require(tub["profile"] in slides["slideProfiles"] and
                    tub["mouthComponent"] in slide["visualChunks"] and
                    all(has_template(p["profile"]) for p in tub["collisionPlacements"]),
                    f"slide {name}: invalid tub reference")
        if slide.get("leadIn"):
            lead = slide["leadIn"]
            require(has_template(lead["profile"]) and
                    lead["visualComponent"] in slide["visualChunks"],
                    f"slide {name}: invalid lead-in reference")
        for segment in slide["segments"]:
            require(has_template(segment["profile"]),
                    f"slide {name}: unknown segment profile")
            require(all(has_template(p["profile"]) for p in segment["pieces"]),
                    f"slide {name}: unknown piece profile")
    for name, prefab in slides["prefabs"].items():
        require((profile == "poolrooms" or prefab["component"] in components) and
                all(t in slides["slides"] for t in prefab["tubes"]),
                f"prefab {name}: invalid component/tube")
        for key, component_key in (("prefabParts", "parts"), ("prefabColliders", "colliders"),
                                   ("prefabMarkers", "markers")):
            if profile == "c":
                require(slides[key][name] == components[prefab["component"]][component_key],
                        f"prefab {name}: {key} differs from component")
    return {"manifest": manifest, "manifest_sha": manifest_sha, "slides": normalized_slides,
            "unique_wires": by_hash, "export": export, "profile": profile}


# Poolrooms tile variants. Parts wear them; kit MeshParts wear their maps as a SurfaceAppearance (texture_sources).
POOL_TILE_VARIANTS = ("PR Tile", "PR Tile Aqua")


def texture_sources(data: dict) -> dict[str, dict]:
    """One entry per image hash; paths remain local until the operator uploads."""
    poolrooms = data.get("profile") == "poolrooms"
    spec = ({"pr_tile": {"tile_m": 4.0 * .28},     # LATTICE_SPEC 2.1: 0.5-stud tiles, StudsPerTile 4.0
             "pr_aqua": {"tile_m": 4.0 * .28},
             "steel": {"tile_m": .5, "metal": 1}}
            if poolrooms else read_json(SPEC))
    materials = data["manifest"]["materials"]
    by_sha = {}
    variants = {}
    atlas_maps = {}
    for name, material in materials.items():
        variant = material.get("variant")
        if variant:
            require(material["robloxMaterial"] == "SmoothPlastic", f"{name}: PBR base material differs")
            pbr = material["pbr"]
            require(pbr in spec, f"{name}: unknown PBR set {pbr}")
            require(abs(material["tile_m"] - spec[pbr]["tile_m"]) < 1e-9,
                    f"{name}: PBR tile size mismatch")
            mapping = {}
            for channel in ("albedo", "normal", "rough", "metal"):
                path = (POOL_PBR if poolrooms and pbr != "steel" else PBR) / f"{pbr}_{channel}.png"
                if channel != "metal" or "metal" in spec[pbr] or path.is_file():
                    require(path.is_file(), f"{name}: missing PBR map {path}")
                    content = path.read_bytes()
                    allowed = (64, 64) if pbr == "steel" and channel == "metal" else (1024, 1024)
                    require(png_size(content, path) == allowed, f"{name}: wrong PBR map size {path}")
                    digest = sha(content)
                    by_sha.setdefault(digest, {"sha256": digest, "paths": [], "bytes": path.stat().st_size})["paths"].append(str(path))
                    mapping[channel] = digest
            record = {"name": variant, "tile_m": material["tile_m"], "maps": mapping}
            require(variant not in variants or variants[variant] == record,
                    f"{name}: conflicting definition for {variant}")
            variants[variant] = record
        if material.get("atlas"):
            mapping = {}
            for channel, filename in material["atlas"].items():
                require(channel in MAP_PROPS, f"{name}: unknown atlas channel {channel}")
                path = Path(filename)
                require(path.is_file(), f"{name}: missing atlas {path}")
                content = path.read_bytes()
                require(png_size(content, path) in ((512, 512), (1024, 1024)),
                        f"{name}: atlas outside 512/1024 budget {path}")
                digest = sha(content)
                by_sha.setdefault(digest, {"sha256": digest, "paths": [], "bytes": path.stat().st_size})["paths"].append(str(path))
                mapping[channel] = digest
            atlas_maps[name] = mapping
    if poolrooms:
        # A MaterialVariant on a MeshPart ignores the mesh UVs (projected in mesh space in studs, centred on the part),
        # so its grout cannot follow the Parts' lattice; a SurfaceAppearance follows the UVs exactly, and the kit UVs
        # are laid for 0.5-stud tiles (Studio Play probes 2026-10-06, G:/Roblox/_local/l2fix/studio/TILE_PHASE.md).
        # Tile meshes therefore get ONE SurfaceAppearance with their variant's maps: listed here per material beside
        # the atlases, told apart from an atlas by the material's missing "atlas" key (chunk_record).
        for name, material in materials.items():
            if material.get("variant") in POOL_TILE_VARIANTS:
                atlas_maps[name] = dict(variants[material["variant"]]["maps"])
    expected = ({*POOL_TILE_VARIANTS, "PR Iron"} if poolrooms else
                {"L2K Tile", "L2K Mosaic", "L2K Cobalt", "L2K Terrazzo",
                 "L2K Glass Block", "L2K Service", "L2K Rubber", "L2K Steel", "L2K Bands"})
    require(set(variants) == expected, f"unexpected PBR variants: {sorted(variants)}")
    data["variants"] = variants
    data["atlas_maps"] = atlas_maps
    data["texture_sources"] = by_sha
    return by_sha


def load_receipts(path: Path) -> dict:
    if not path.exists():
        return {}
    records = read_json(path)
    require(isinstance(records, dict), f"{path}: receipt must be an object")
    for digest, receipt in records.items():
        require(HEX64.fullmatch(digest) is not None, f"{path}: invalid hash key {digest}")
        asset = receipt.get("assetId") if isinstance(receipt, dict) else receipt
        require(isinstance(asset, (str, int)) and re.fullmatch(r"(?:rbxassetid://)?\d+", str(asset)),
                f"{path}: invalid asset ID at {digest}")
        if isinstance(receipt, dict):
            require(receipt.get("wireSha256", digest) == digest and
                    receipt.get("sha256", digest) == digest,
                    f"{path}: receipt hash/key disagreement {digest}")
    return records


def asset_id(receipt) -> str:
    if receipt is None:
        return ""
    value = receipt.get("assetId") if isinstance(receipt, dict) else receipt
    return str(value).removeprefix("rbxassetid://")


def check_mesh_receipts(receipts: dict, kind: str = "mesh") -> None:
    by_asset = {}
    for digest, receipt in receipts.items():
        ident = asset_id(receipt)
        require(ident not in by_asset or by_asset[ident] == digest,
                f"{kind} asset ID {ident} is recorded for different hashes")
        by_asset[ident] = digest


def encode_attrs(attrs: dict) -> dict:
    result = {}
    for key, value in attrs.items():
        if isinstance(value, (dict, list)) and key != "Level2_SlideDirection":
            result[key] = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
        else:
            result[key] = value
    return result


def chunk_record(c: dict, mesh_receipts: dict, materials: dict, texture_receipts: dict,
                 atlas_maps: dict, precise: bool = False) -> dict:
    source = materials[c["material"]]
    tile = c["material"] in atlas_maps and not source.get("atlas")  # Poolrooms tile mesh: SurfaceAppearance, no variant
    material = {"robloxMaterial": source["robloxMaterial"], "variant": None if tile else source.get("variant"),
                "color": source["color"], "atlas": bool(source.get("atlas")), "tile": tile,
                "reflectance": source.get("reflectance", 0)}
    if c["material"] in atlas_maps:
        material["assetMaps"] = {key: "rbxassetid://" + asset_id(texture_receipts.get(digest))
                                  for key, digest in atlas_maps[c["material"]].items()}
    return {"id": c["id"], "name": c["component"] + "_" + c["material"],
            "material": material, "center": c["center"], "size": c["size"],
            "wireSha256": c["wireSha256"], "assetId": asset_id(mesh_receipts.get(c["wireSha256"])),
            "renderFidelity": "Precise" if precise else "Automatic"}


def component_record(name: str, info: dict, chunks: list, mesh_receipts: dict,
                     materials: dict, texture_receipts: dict, atlas_maps: dict) -> dict:
    return {"name": name, "attrs": encode_attrs(info["attrs"]),
            "chunks": [chunk_record(chunks[i], mesh_receipts, materials, texture_receipts, atlas_maps,
                                    bool((info["attrs"].get("Level2_SlideVisual") or
                                          info["attrs"].get("Role") == "ExitFlumeVisual") and
                                         max(chunks[i]["size"]) > 100))
                       for i in info["chunks"]],
            "parts": [{**r, "attrs": encode_attrs(r["attrs"]),
                       "style": {"robloxMaterial": materials[r["material"]]["robloxMaterial"],
                                 "variant": materials[r["material"]].get("variant"),
                                 "color": materials[r["material"]]["color"],
                                 "reflectance": materials[r["material"]].get("reflectance", 0)}}
                      for r in info["parts"]],
            "colliders": [{**r, "attrs": encode_attrs(r["attrs"])} for r in info["colliders"]],
            "markers": [{**r, "attrs": encode_attrs(r["attrs"])} for r in info["markers"]]}


def phase_prefix(index: int, kit_name: str, manifest_sha: str) -> str:
    stage = f"__{kit_name}_Installing_{manifest_sha[:12]}"
    return (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
            'local SS = game:GetService("ServerStorage")\n'
            f'assert(not SS:FindFirstChild({lua(kit_name)}), "Existing kit: no overwrite")\n'
            f'local kit = assert(SS:FindFirstChild({lua(stage)}), "Missing staging kit")\n'
            f'assert(kit:GetAttribute("ManifestSha256") == {lua(manifest_sha)}, "Staging hash mismatch")\n'
            f'assert(kit:GetAttribute("NextPhase") == {index}, "Unexpected install phase")\n')


BUILD_COMPONENTS = r'''
local AS = game:GetService("AssetService")
local function vec(a) return Vector3.new(a[1], a[2], a[3]) end
local function cf(a)
    if #a == 12 then return CFrame.new(table.unpack(a)) end
    return CFrame.new(a[1], a[2], a[3]) * CFrame.Angles(0, math.rad(a[4]), 0)
end
local function fullCf(record)
    if not record.cframe then return cf(record.cf) end
    local frame = record.cframe
    return CFrame.fromMatrix(vec(frame.position), vec(frame.right), vec(frame.up), vec(frame.back))
end
local function attrs(inst, values)
    for key, value in pairs(values) do
        if key == "Level2_SlideDirection" then value = vec(value) end
        inst:SetAttribute(key, value)
    end
end
local function color(style) return Color3.fromRGB(table.unpack(style.color)) end
local function nativeCylinder(part, record)
    assert(record.attrs.CylinderAxis == "Y" and record.attrs.NativeRotationZ == 90,
        "Cylinder missing vertical native frame: " .. record.name)
    part.Size = Vector3.new(record.attrs.NativeSizeX, record.attrs.NativeSizeY, record.attrs.NativeSizeZ)
    part.CFrame = part.CFrame * CFrame.Angles(0, 0, math.rad(record.attrs.NativeRotationZ))
end
local function mesh(c, fidelity)
    assert(c.assetId ~= "", "Mesh receipt missing: " .. c.wireSha256)
    local part = AS:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. c.assetId), {
        CollisionFidelity = fidelity, RenderFidelity = Enum.RenderFidelity[c.renderFidelity],
    })
    part.Name = c.name
    part.Anchored = true
    part.Size = vec(c.size)
    part.CFrame = CFrame.new(vec(c.center))
    part.Material = Enum.Material[c.material.robloxMaterial]
    part.Color = color(c.material)
    part.Reflectance = c.material.reflectance
    part.MaterialVariant = ""
    part.TextureID = ""
    part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
    part.CastShadow = math.max(table.unpack(c.size)) > 8
    part:SetAttribute("WireSha256", c.wireSha256)
    part:SetAttribute("ChunkId", c.id)
    part:SetAttribute("AssetId", c.assetId)
    if c.material.atlas or c.material.tile then
        local sa = Instance.new("SurfaceAppearance")
        sa.Name = c.material.tile and "Tile" or "Atlas"
        for channel, property in pairs({albedo="ColorMap", normal="NormalMap", rough="RoughnessMap", metal="MetalnessMap"}) do
            if c.material.assetMaps[channel] then
                assert(c.material.assetMaps[channel] ~= "rbxassetid://", "Missing atlas receipt")
                sa[property] = c.material.assetMaps[channel]
            end
        end
        if c.material.tile then sa.Color = color(c.material) end
        sa.Parent = part
    elseif c.material.variant then
        part.MaterialVariant = c.material.variant
    end
    return part
end
local function build(rec)
    local model = Instance.new("Model")
    model.Name = rec.name
    model.WorldPivot = CFrame.identity
    attrs(model, rec.attrs)
    for _, c in ipairs(rec.chunks) do
        local p = mesh(c, Enum.CollisionFidelity.Box)
        -- Kit surfaces are open shells (tunnel barrels, coves, chamber walls) whose
        -- exported winding faces away from the room; Roblox would cull them.
        p.DoubleSided = true
        p.Parent = model
    end
    for _, r in ipairs(rec.parts) do
        local p = Instance.new("Part")
        p.Name = r.name; p.Size = vec(r.size); p.CFrame = fullCf(r)
        if r.shape == "Cylinder" or (r.properties and r.properties.Shape == "Cylinder") then
            p.Shape = Enum.PartType.Cylinder
            nativeCylinder(p, r)
        end
        p.Anchored = true; p.Material = Enum.Material[r.style.robloxMaterial]
        p.MaterialVariant = r.style.variant or ""
        p.Color = color(r.style)
        p.Reflectance = r.style.reflectance
        p.CanCollide = r.collide; p.CanQuery = r.collide; p.CanTouch = false
        if r.properties then
            for key, value in pairs(r.properties) do
                if key == "Color" then value = Color3.fromRGB(table.unpack(value))
                elseif key == "Material" then value = Enum.Material[value]
                elseif key == "CustomPhysicalProperties" then
                    value = PhysicalProperties.new(value.density, value.friction, value.elasticity,
                        value.frictionWeight, value.elasticityWeight)
                end
                -- CollisionFidelity applies to MeshParts, not to a Part record.
                if key ~= "CollisionFidelity" and key ~= "Shape" then
                    p[key] = value
                end
            end
        end
        if r.ground then p:SetAttribute("Level2_EntityGround", true) end
        attrs(p, r.attrs)
        p.Parent = model
    end
    for _, r in ipairs(rec.colliders) do
        local p = Instance.new("Part")
        p.Name = r.name; p.Shape = Enum.PartType[r.shape]
        p.Size = vec(r.size); p.CFrame = cf(r.cf)
        if r.shape == "Cylinder" then
            nativeCylinder(p, r)
        end
        p.Anchored = true; p.Transparency = 1
        p.CanCollide = true; p.CanQuery = true; p.CanTouch = false
        if r.ground then p:SetAttribute("Level2_EntityGround", true) end
        attrs(p, r.attrs)
        p.Parent = model
    end
    local markers = Instance.new("Folder")
    markers.Name = "Markers"
    for _, r in ipairs(rec.markers) do
        local marker = Instance.new("CFrameValue")
        marker.Name = r.name; marker.Value = cf(r.cf)
        attrs(marker, r.attrs)
        marker.Parent = markers
    end
    markers.Parent = model
    model.WorldPivot = CFrame.identity
    return model
end
'''


def component_phase(index: int, records: list, kit_name: str, manifest_sha: str) -> str:
    code = phase_prefix(index, kit_name, manifest_sha) + BUILD_COMPONENTS
    code += "local records = " + lua(records) + "\n"
    code += r'''
local destination = assert(kit:FindFirstChild("Components"))
local created = {}
local ok, err = pcall(function()
    for _, rec in ipairs(records) do
        assert(not destination:FindFirstChild(rec.name), "Duplicate component " .. rec.name)
        local model = build(rec)
        table.insert(created, model)
    end
end)
if not ok then
    for _, model in ipairs(created) do model:Destroy() end
    error(err)
end
for _, model in ipairs(created) do model.Parent = destination end
'''
    code += f'kit:SetAttribute("NextPhase", {index + 1})\nreturn "components {len(records)}"\n'
    return code


def template_phase(index: int, records: list, kit_name: str, manifest_sha: str) -> str:
    code = phase_prefix(index, kit_name, manifest_sha) + BUILD_COMPONENTS
    code += "local records = " + lua(records) + "\n"
    code += r'''
local destination = assert(kit:FindFirstChild("SlideTemplates"))
local created = {}
local ok, err = pcall(function()
    for _, rec in ipairs(records) do
        assert(not destination:FindFirstChild(rec.name), "Duplicate slide template " .. rec.name)
        local part = mesh(rec.chunk, Enum.CollisionFidelity.PreciseConvexDecomposition)
        part.Name = rec.name
        part.CanCollide = true; part.CanQuery = true; part.CanTouch = false
        part.CastShadow = false; part.Transparency = 1
        part.Material = Enum.Material.SmoothPlastic
        part.MaterialVariant = ""
        part.CustomPhysicalProperties = PhysicalProperties.new(.7, .05, .05, 1, 1)
        table.insert(created, part)
    end
end)
if not ok then
    for _, part in ipairs(created) do part:Destroy() end
    error(err)
end
for _, part in ipairs(created) do part.Parent = destination end
'''
    code += f'kit:SetAttribute("NextPhase", {index + 1})\nreturn "slide templates {len(records)}"\n'
    return code


def data_phase(index: int, slices: list[tuple[int, str]], kit_name: str, manifest_sha: str) -> str:
    code = phase_prefix(index, kit_name, manifest_sha)
    code += "local records = " + lua([[n, value] for n, value in slices]) + "\n"
    code += r'''
local destination = assert(kit:FindFirstChild("Data"))
local created = {}
local ok, err = pcall(function()
    for _, rec in ipairs(records) do
        local name = string.format("SlidesJSON-%03d", rec[1])
        assert(not destination:FindFirstChild(name), "Duplicate data slice " .. name)
        assert(#rec[2] <= 190000, "Oversize SlidesJSON slice")
        local value = Instance.new("StringValue")
        value.Name = name; value.Value = rec[2]
        table.insert(created, value)
    end
end)
if not ok then
    for _, value in ipairs(created) do value:Destroy() end
    error(err)
end
for _, value in ipairs(created) do value.Parent = destination end
'''
    code += f'kit:SetAttribute("NextPhase", {index + 1})\nreturn "data slices {len(slices)}"\n'
    return code


def expected_inventory(data: dict, mesh_receipts: dict, texture_receipts: dict) -> dict:
    manifest = data["manifest"]
    chunks = manifest["chunks"]
    result = {}
    for name, info in manifest["components"].items():
        if data.get("profile") == "poolrooms" and info["attrs"].get("Template"):
            continue
        mesh_records = []
        for i in info["chunks"]:
            chunk = chunks[i]
            style = manifest["materials"][chunk["material"]]
            maps = {MAP_PROPS[channel]: "rbxassetid://" + asset_id(texture_receipts.get(digest))
                    for channel, digest in data["atlas_maps"].get(chunk["material"], {}).items()}
            tile = bool(maps) and not style.get("atlas")
            # [name, wire, asset, MaterialVariant, SurfaceAppearance maps, its name, tile colour or false]
            mesh_records.append([name + "_" + chunk["material"], chunk["wireSha256"],
                                 asset_id(mesh_receipts.get(chunk["wireSha256"])),
                                 "" if tile else style.get("variant") or "", maps,
                                 "Tile" if tile else "Atlas", style["color"] if tile else False])
        result[name] = {
            "meshes": mesh_records,
            "parts": [r["name"] for r in info["parts"] + info["colliders"]],
            "markers": [r["name"] for r in info["markers"]],
        }
    return result


VERIFY_BODY = r'''
local function multiset(children, className)
    local found = {}
    for _, child in ipairs(children) do
        if child.ClassName == className then found[child.Name] = (found[child.Name] or 0) + 1 end
    end
    return found
end
local function namesEqual(actual, expected, context)
    local want = {}
    for _, name in ipairs(expected) do want[name] = (want[name] or 0) + 1 end
    for name, count in pairs(want) do assert(actual[name] == count, context .. "/" .. name) end
    for name, count in pairs(actual) do assert(want[name] == count, context .. "/" .. name) end
end
local components = assert(kit:FindFirstChild("Components"))
local templates = assert(kit:FindFirstChild("SlideTemplates"))
local data = assert(kit:FindFirstChild("Data"))
assert(#components:GetChildren() == expectedComponents, "Component count mismatch")
assert(#templates:GetChildren() == expectedTemplates, "Slide template count mismatch")
assert(#data:GetChildren() == expectedSlices, "SlidesJSON count mismatch")
for name, spec in pairs(expected) do
    local model = assert(components:FindFirstChild(name), "Missing component " .. name)
    assert(model.ClassName == "Model", "Wrong component class " .. name)
    local children = model:GetChildren()
    assert(#children == #spec.meshes + #spec.parts + 1, "Child count " .. name)
    local meshNames = {}
    for _, rec in ipairs(spec.meshes) do table.insert(meshNames, rec[1]) end
    namesEqual(multiset(children, "MeshPart"), meshNames, name .. " meshes")
    namesEqual(multiset(children, "Part"), spec.parts, name .. " parts")
    local markers = assert(model:FindFirstChild("Markers"), "Missing markers " .. name)
    assert(markers.ClassName == "Folder", "Wrong markers class " .. name)
    assert(#markers:GetChildren() == #spec.markers, "Marker count " .. name)
    namesEqual(multiset(markers:GetChildren(), "CFrameValue"), spec.markers, name .. " markers")
    for _, rec in ipairs(spec.meshes) do
        local part = assert(model:FindFirstChild(rec[1]), "Missing mesh " .. rec[1])
        assert(part:GetAttribute("WireSha256") == rec[2] and
               part:GetAttribute("AssetId") == rec[3], "Mesh receipt mismatch " .. rec[1])
        assert(tostring(part.MeshId):match("%d+$") == rec[3], "MeshId mismatch " .. rec[1])
        assert(part.MaterialVariant == rec[4], "Mesh MaterialVariant mismatch " .. rec[1])
        assert(part.DoubleSided == true, "Mesh not double-sided " .. rec[1])
        local appearances = {}
        for _, child in ipairs(part:GetChildren()) do
            if child.ClassName == "SurfaceAppearance" then table.insert(appearances, child) end
        end
        if next(rec[5]) then
            assert(#appearances == 1 and appearances[1].Name == rec[6],
                "Want exactly one SurfaceAppearance " .. rec[6] .. " on " .. rec[1])
            local sa = appearances[1]
            for _, property in ipairs({"ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap"}) do
                assert((sa[property] or "") == (rec[5][property] or ""),
                    "SurfaceAppearance receipt mismatch " .. rec[1] .. "/" .. property)
            end
            if rec[7] then
                for _, c in ipairs({sa.Color, part.Color}) do
                    assert(c and math.floor(c.R * 255 + .5) == rec[7][1] and math.floor(c.G * 255 + .5) == rec[7][2]
                        and math.floor(c.B * 255 + .5) == rec[7][3], "Tile colour mismatch " .. rec[1])
                end
                assert(part.Material == Enum.Material.SmoothPlastic, "Tile mesh material " .. rec[1])
            end
        else
            assert(#appearances == 0, "Unexpected SurfaceAppearance " .. rec[1])
        end
    end
end
for _, rec in ipairs(expectedTemplateRecords) do
    local part = assert(templates:FindFirstChild(rec[1]), "Missing template " .. rec[1])
    assert(part.ClassName == "MeshPart" and part:GetAttribute("WireSha256") == rec[2] and
           part:GetAttribute("AssetId") == rec[3], "Template receipt mismatch " .. rec[1])
    assert(tostring(part.MeshId):match("%d+$") == rec[3], "Template MeshId mismatch " .. rec[1])
    assert(part.CollisionFidelity == Enum.CollisionFidelity.PreciseConvexDecomposition,
           "Template collision fidelity " .. rec[1])
end
for i = 1, expectedSlices do
    local part = assert(data:FindFirstChild(string.format("SlidesJSON-%03d", i)), "Missing data slice")
    assert(part.ClassName == "StringValue" and #part.Value <= 190000, "Bad data slice")
end
'''


def verification_prelude(data: dict, mesh_receipts: dict, texture_receipts: dict,
                         slice_count: int) -> str:
    inventory = expected_inventory(data, mesh_receipts, texture_receipts)
    chunks = data["manifest"]["chunks"]
    templates = [[name, chunks[info["chunks"][0]]["wireSha256"],
                  asset_id(mesh_receipts.get(chunks[info["chunks"][0]]["wireSha256"]))]
                 for name, info in data["manifest"]["components"].items()
                 if info["attrs"].get("Template") and info["chunks"]]
    return ("local expected = " + lua(inventory) + "\n" +
            f"local expectedComponents = {len(inventory)}\n" +
            f"local expectedTemplates = {len(templates)}\n" +
            f"local expectedSlices = {slice_count}\n" +
            "local expectedTemplateRecords = " + lua(templates) + "\n")


def variant_records(data: dict, texture_receipts: dict) -> list[dict]:
    return [{"name": name, "tile": spec["tile_m"] / .28,
             "maps": {MAP_PROPS[channel]: "rbxassetid://" + asset_id(texture_receipts.get(digest))
                      for channel, digest in spec["maps"].items()}}
            for name, spec in sorted(data["variants"].items())]


VARIANT_CHECK = r'''
local MS = game:GetService("MaterialService")
local function matching(inst, rec)
    if inst.ClassName ~= "MaterialVariant" or inst.BaseMaterial ~= Enum.Material.SmoothPlastic then return false end
    if math.abs(inst.StudsPerTile - rec.tile) > 0.0001 then return false end
    for prop, id in pairs(rec.maps) do if inst[prop] ~= id then return false end end
    for _, prop in ipairs({"ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap"}) do
        if not rec.maps[prop] and inst[prop] ~= "" then return false end
    end
    return true
end
'''


def final_phase(index: int, kit_name: str, data: dict, mesh_receipts: dict,
                texture_receipts: dict, slice_count: int) -> str:
    code = phase_prefix(index, kit_name, data["manifest_sha"])
    code += verification_prelude(data, mesh_receipts, texture_receipts, slice_count) + VERIFY_BODY
    code += "local variants = " + lua(variant_records(data, texture_receipts)) + "\n" + VARIANT_CHECK
    code += r'''
assert(#kit:GetChildren() == 4, "Staging kit child count mismatch")
local staged = assert(kit:FindFirstChild("StagedVariants"))
    for _, rec in ipairs(variants) do
    for _, id in pairs(rec.maps) do assert(id ~= "rbxassetid://", "Missing texture receipt") end
    local existing = MS:FindFirstChild(rec.name)
    assert(not existing or matching(existing, rec), "Conflicting MaterialVariant " .. rec.name)
    local pending = staged:FindFirstChild(rec.name)
    assert(not pending or matching(pending, rec), "Conflicting staged MaterialVariant " .. rec.name)
    if existing and pending then
        pending:Destroy()
    elseif not existing and not pending then
        pending = Instance.new("MaterialVariant")
        pending.Name = rec.name
        pending.BaseMaterial = Enum.Material.SmoothPlastic
        pending.StudsPerTile = rec.tile
        for prop, id in pairs(rec.maps) do pending[prop] = id end
        pending.Parent = staged
    end
end
for _, variant in ipairs(staged:GetChildren()) do
    assert(not MS:FindFirstChild(variant.Name), "Variant appeared during install")
    variant.Parent = MS
end
staged:Destroy()
assert(#kit:GetChildren() == 3, "Final kit child count mismatch")
kit.Name = FINAL_NAME
kit:SetAttribute("NextPhase", nil)
kit:SetAttribute("Ready", true)
return "installed " .. kit.Name .. ": " .. expectedComponents .. " components"
'''.replace("FINAL_NAME", lua(kit_name))
    return code


def audit_code(kit_name: str, data: dict, mesh_receipts: dict,
               texture_receipts: dict, slice_count: int) -> str:
    code = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
            'local SS = game:GetService("ServerStorage")\n'
            f'local kit = assert(SS:FindFirstChild({lua(kit_name)}), "Kit missing")\n'
            f'assert(kit:GetAttribute("Ready") == true, "Kit not Ready")\n'
            f'assert(kit:GetAttribute("KitBuild") == {lua(data["manifest"]["build"])}, "Build mismatch")\n'
            f'assert(kit:GetAttribute("ManifestSha256") == {lua(data["manifest_sha"])}, "Manifest mismatch")\n')
    code += verification_prelude(data, mesh_receipts, texture_receipts, slice_count) + VERIFY_BODY
    code += "local variants = " + lua(variant_records(data, texture_receipts)) + "\n" + VARIANT_CHECK
    code += r'''
assert(#kit:GetChildren() == 3, "Kit child count mismatch")
for _, rec in ipairs(variants) do
    local variant = assert(MS:FindFirstChild(rec.name), "Missing MaterialVariant " .. rec.name)
    assert(matching(variant, rec), "MaterialVariant mismatch " .. rec.name)
end
-- The retired mesh twins (2026-10-05; nothing assigns them now) are left for the operator to delete.
local stale = {}
for _, name in ipairs({"PR Tile Mesh", "PR Tile Aqua Mesh"}) do
    if MS:FindFirstChild(name) then table.insert(stale, name) end
end
return "AUDIT OK components=" .. expectedComponents .. " templates=" .. expectedTemplates .. " data=" .. expectedSlices ..
    (#stale > 0 and (" (unused retired MaterialVariants: " .. table.concat(stale, ", ") .. ")") or "")
'''
    return code


def group_by_size(records: list, render, limit: int) -> list[list]:
    groups = []
    current = []
    for rec in records:
        candidate = current + [rec]
        if current and len(render(candidate).encode("utf-8")) > limit:
            groups.append(current)
            current = [rec]
        else:
            current = candidate
        require(len(render(current).encode("utf-8")) <= limit,
                "one installer record exceeds phase payload limit")
    if current:
        groups.append(current)
    return groups


def prepare(data: dict, mesh_receipts: dict, texture_receipts: dict,
            kit_name: str) -> tuple[list[tuple[str, str]], str]:
    require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{1,63}", kit_name) is not None,
            "kit name must be 2-64 alphanumeric/underscore characters")
    manifest = data["manifest"]
    slides_text = json.dumps(data["slides"], separators=(",", ":"), ensure_ascii=False)
    slices = [slides_text[i:i + DATA_SLICE_CHARS] for i in range(0, len(slides_text), DATA_SLICE_CHARS)]
    records = [component_record(name, info, manifest["chunks"], mesh_receipts,
                                manifest["materials"], texture_receipts, data["atlas_maps"])
               for name, info in manifest["components"].items()]
    if data.get("profile") == "poolrooms":
        records = [record for record in records if not record["attrs"].get("Template")]
    stage = f"__{kit_name}_Installing_{data['manifest_sha'][:12]}"
    phases = []
    init = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
            'local SS = game:GetService("ServerStorage")\n'
            f'assert(not SS:FindFirstChild({lua(kit_name)}), "Existing kit: no overwrite")\n'
            f'assert(not SS:FindFirstChild({lua(stage)}), "Existing staging kit: reconcile manually")\n'
            'local kit = Instance.new("Folder")\n'
            f'kit.Name = {lua(stage)}\n'
            f'kit:SetAttribute("KitBuild", {lua(manifest["build"])})\n'
            f'kit:SetAttribute("ManifestSha256", {lua(data["manifest_sha"])})\n'
            'kit:SetAttribute("NextPhase", 1)\n'
            'for _, name in ipairs({"Components", "SlideTemplates", "Data", "StagedVariants"}) do\n'
            '    local folder = Instance.new("Folder"); folder.Name = name; folder.Parent = kit\n'
            'end\nkit.Parent = SS\nreturn "staging kit created"\n')
    phases.append(("init", init))
    index = 1
    render = lambda group: component_phase(index, group, kit_name, data["manifest_sha"])
    for group in group_by_size(records, render, INSTALL_PHASE_BYTES):
        phases.append(("components", component_phase(index, group, kit_name, data["manifest_sha"])))
        index += 1
    template_records = []
    template_sources = (component_record(name, info, manifest["chunks"], mesh_receipts,
                        manifest["materials"], texture_receipts, data["atlas_maps"])
                        for name, info in manifest["components"].items()) if data.get("profile") == "poolrooms" else records
    for record in template_sources:
        if record["attrs"].get("Template") and record["chunks"]:
            require(len(record["chunks"]) == 1, f"template {record['name']} has multiple meshes")
            chunk = record["chunks"][0]
            if chunk["material"]["tile"]:  # an invisible collision template needs no SurfaceAppearance
                chunk = {**chunk, "material": {**chunk["material"], "tile": False}}
            template_records.append({"name": record["name"], "chunk": chunk})
    render = lambda group: template_phase(index, group, kit_name, data["manifest_sha"])
    for group in group_by_size(template_records, render, INSTALL_PHASE_BYTES):
        phases.append(("slide-templates", template_phase(index, group, kit_name, data["manifest_sha"])))
        index += 1
    data_records = list(enumerate(slices, 1))
    render = lambda group: data_phase(index, group, kit_name, data["manifest_sha"])
    for group in group_by_size(data_records, render, INSTALL_PHASE_BYTES):
        phases.append(("slides-data", data_phase(index, group, kit_name, data["manifest_sha"])))
        index += 1
    phases.append(("finalize", final_phase(index, kit_name, data, mesh_receipts,
                                            texture_receipts, len(slices))))
    return phases, slides_text


def compile_payload(path: Path) -> None:
    require(LUAU_COMPILE.is_file(), f"luau-compile not found: {LUAU_COMPILE}")
    result = subprocess.run([str(LUAU_COMPILE), "--null", "-O0", str(path)],
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
    require(result.returncode == 0, f"Luau compilation failed: {path}: {result.stderr or result.stdout}")


def stage_plan(data: dict, mesh_receipts: dict, texture_receipts: dict,
               kit_name: str, staging: Path, verbose: bool = True) -> dict:
    phases, slides_text = prepare(data, mesh_receipts, texture_receipts, kit_name)
    staging.mkdir(parents=True, exist_ok=True)
    files = []
    for index, (kind, code) in enumerate(phases):
        path = staging / f"{index:03d}-{kind}.luau"
        path.write_text(code, encoding="utf-8", newline="\n")
        compile_payload(path)
        files.append({"file": path.name, "kind": kind, "bytes": path.stat().st_size, "sha256": sha(path.read_bytes())})
    pending_meshes = [{"wireSha256": digest, "chunkIds": info["ids"],
                       "wireBytes": len(info["wire"])}
                      for digest, info in data["unique_wires"].items() if digest not in mesh_receipts]
    pending_textures = [entry for digest, entry in data["texture_sources"].items()
                        if digest not in texture_receipts]
    inline = [(digest, data["unique_wires"][digest]["wire"])
              for digest in data["unique_wires"] if digest not in mesh_receipts
              and is_inline(data["unique_wires"][digest]["wire"])]
    large = [(digest, data["unique_wires"][digest]["wire"])
             for digest in data["unique_wires"] if digest not in mesh_receipts
             and not is_inline(data["unique_wires"][digest]["wire"])]
    upload_batches = mesh_batches(inline)
    mesh_calls = len(upload_batches) + sum(math.ceil(len(wire) / MESH_SLICE_CHARS) + 1
                                          for _, wire in large)
    prefabs = data["slides"]["prefabs"]
    slide_instances = (prefabs["ExitFlume"]["instances"]["total"] if data.get("profile") == "poolrooms" else
                       2 * prefabs["SlideHall"]["instances"]["total"] +
                       prefabs["GrandSlideHall"]["instances"]["total"] +
                       prefabs["ExitFlume"]["instances"]["total"])
    budget_warnings = []
    if slide_instances > 1500:
        budget_warnings.append(f"slide hall/exit prefab estimate {slide_instances} exceeds KIT_SPEC target 1500")
    plan = {"manifestSha256": data["manifest_sha"], "kitBuild": data["manifest"]["build"],
            "kitName": kit_name, "components": len(expected_inventory(data, mesh_receipts, texture_receipts)),
            "chunks": len(data["manifest"]["chunks"]), "uniqueMeshes": len(data["unique_wires"]),
            "uniqueTextures": len(data["texture_sources"]), "slideDataChars": len(slides_text),
            "slideDataSlices": math.ceil(len(slides_text) / DATA_SLICE_CHARS),
            "authoredTriangles": sum(c["tris"] for c in data["manifest"]["chunks"]),
            "slideHallExitInstanceEstimate": slide_instances,
            "budgetWarnings": budget_warnings,
            "pendingMeshes": pending_meshes, "pendingTextures": pending_textures,
            "estimatedExecuteLuauCalls": {"meshUpload": mesh_calls,
                                          "install": len(files),
                                          "audit": 1 + math.ceil(len(slides_text) / DATA_SLICE_CHARS)},
            "installable": not pending_meshes and not pending_textures,
            "phases": files}
    (staging / "plan.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    if verbose:
        print(f"PLAN {plan['components']} components, {plan['chunks']} chunks, "
              f"{plan['uniqueMeshes']} unique meshes, {plan['uniqueTextures']} unique textures")
        print(f"Pending: {len(pending_meshes)} mesh uploads in {mesh_calls} execute_luau calls; "
              f"{len(pending_textures)} image uploads via upload_image")
        print(f"Installer: {len(files)} compiled execute_luau payloads; "
              f"audit estimate {plan['estimatedExecuteLuauCalls']['audit']} calls")
        for warning in budget_warnings:
            print("BUDGET WARNING: " + warning)
        print(f"Upload inventory and exact payload hashes: {staging / 'plan.json'}")
    return plan


def mesh_batches(items: list[tuple[str, str]]) -> list[list[tuple[str, str]]]:
    batches = []
    batch = []
    size = 0
    for item in items:
        wire_bytes = len(item[1])
        require(is_inline(item[1]), f"mesh {item[0]} needs sliced transport")
        if batch and size + wire_bytes + 7000 > MESH_BATCH_BYTES:
            batches.append(batch)
            batch, size = [], 0
        batch.append(item)
        size += wire_bytes
    if batch:
        batches.append(batch)
    return batches


def is_inline(wire: str) -> bool:
    return len(wire) + 7000 < MESH_BATCH_BYTES


def open_studio(studio_id: str, mode: str):
    """Bind to exactly one operator-named Edit session and the published place."""
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, studio_place_id

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studios = json.loads(client.call("list_roblox_studios")).get("studios", [])
        matches = [s for s in studios if str(s.get("id")) == studio_id]
        require(len(matches) == 1, f"exact Studio ID {studio_id!r} not found")
        studio = matches[0]
        require("BACKROOMS" in studio.get("name", "").upper(),
                f"Studio name does not contain BACKROOMS: {studio.get('name')!r}")
        advertised = studio_place_id(studio)
        require(advertised in (None, PLACE_ID), f"Studio advertises wrong place: {advertised}")
        state = client.call("get_studio_state", {"studio_id": studio_id})
        require(re.search(r"^\s*- Current Studio Mode: Edit\s*$", state, re.MULTILINE) is not None and
                re.search(r"^\s*- Available DataModels: Edit\s*$", state, re.MULTILINE) is not None,
                f"{mode} requires an Edit session, with no Play session running: {state}")
        observed = execute(client, studio_id, "return tostring(game.PlaceId)")
        require(observed.strip() == str(PLACE_ID), f"Studio game.PlaceId is {observed!r}, expected {PLACE_ID}")
        print(f"BOUND Studio {studio_id}: {studio['name']} / place {PLACE_ID} / Edit", flush=True)
        return client
    except Exception:
        client.close()
        raise


def tool_call(client, name: str, arguments: dict, timeout: float = 1800) -> str:
    response = client._request("tools/call", {"name": name, "arguments": arguments}, timeout=timeout)
    result = response.get("result", {})
    output = "\n".join(block.get("text", "") for block in result.get("content", [])
                       if block.get("type") == "text")
    require(not result.get("isError"), f"{name} failed: {output[:2000]}")
    return output


def execute(client, studio_id: str, code: str, timeout: float = 1800) -> str:
    return tool_call(client, "execute_luau", {"studio_id": studio_id,
                                             "datamodel_type": "Edit", "code": code}, timeout)


def report_leftovers(client, studio_id: str, kit_name: str) -> None:
    code = ('local SS = game:GetService("ServerStorage")\n'
            'local found = {}\n'
            'for _, child in ipairs(SS:GetChildren()) do\n'
            '  if string.find(child.Name, "^__L2KMeshWire_") or '
            f'string.find(child.Name, {lua("^__" + kit_name + "_Installing_")}) then\n'
            '    table.insert(found, child.Name)\n'
            '  end\n'
            'end\nreturn table.concat(found, ", ")')
    try:
        print("Leftover staging folders: " + (execute(client, studio_id, code).strip() or "none"), flush=True)
    except Exception as exc:
        print(f"Could not list leftover staging folders: {exc}", flush=True)


def write_receipts(path: Path, records: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(records, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def upload_textures(client, studio_id: str, sources: dict, receipts: dict) -> None:
    pending = [(digest, info) for digest, info in sources.items() if digest not in receipts]
    if not pending:
        print(f"All {len(sources)} distinct texture hashes already have receipts.")
        return
    # An opaque path token maps only to the exact files in this validated plan.
    names = {digest: Path(info["paths"][0]) for digest, info in pending}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requested = unquote(urlsplit(self.path).path).lstrip("/")
            digest = requested[:-4] if requested.endswith(".png") else ""
            path = names.get(digest)
            if path is None:
                self.send_error(404)
                return
            content = path.read_bytes()
            if sha(content) != digest:
                self.send_error(409)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def log_message(self, *_args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for start in range(0, len(pending), 12):
            batch = pending[start:start + 12]
            urls = {digest: f"http://127.0.0.1:{server.server_port}/{digest}.png" for digest, _ in batch}
            response = tool_call(client, "upload_image",
                                 {"studio_id": studio_id, "imagePaths": list(urls.values())})
            uploaded = json.loads(response)
            failures = []
            for digest, url in urls.items():
                asset = uploaded.get(url)
                if not isinstance(asset, str) or not re.fullmatch(r"rbxassetid://\d+", asset):
                    failures.append(digest)
                    continue
                candidate = {**receipts, digest: {"sha256": digest, "assetId": asset}}
                try:
                    check_mesh_receipts(candidate, "texture")
                except ValueError:
                    failures.append(digest)
                    continue
                receipts[digest] = candidate[digest]
                write_receipts(TEXTURE_RECEIPTS, receipts)
                print(f"texture {digest} -> {asset}", flush=True)
            require(not failures, f"Missing upload_image receipts (saved successful receipts): {failures}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def upload_code(batch: list[tuple[str, str]], ids: dict[str, list[int]]) -> str:
    source = (ROOT / "tools/level4_blender/upload.luau").read_text(encoding="utf-8")
    builder = source[source.index("local function build(b)"):source.index("local function run()")]
    items = [[digest, wire, ids[digest][0]] for digest, wire in batch]
    code = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
            'local AS = game:GetService("AssetService")\n'
            'local ENC = game:GetService("EncodingService")\n' + builder +
            "local items = " + lua(items) + "\n")
    code += f"local GROUP = {GROUP_ID}\n"
    code += r'''
local results = {}
for _, item in ipairs(items) do
    local digest, wire, firstId = item[1], item[2], item[3]
    local ok, result = pcall(function()
        local em = build(ENC:Base64Decode(buffer.fromstring(wire)))
        local status, id
        local success, err = pcall(function()
            for attempt = 1, 4 do
                status, id = AS:CreateAssetAsync(em, Enum.AssetType.Mesh, {
                    Name = "L2K_Chunk_" .. firstId,
                    Description = "Level 2 Blender kit mesh " .. digest,
                    CreatorId = GROUP,
                    CreatorType = Enum.AssetCreatorType.Group,
                })
                if status == Enum.CreateAssetResult.Success then break end
                if status ~= Enum.CreateAssetResult.UploadFailed or attempt == 4 then
                    error(tostring(status))
                end
                task.wait(5 * attempt)
            end
        end)
        em:Destroy()
        if not success then error(err) end
        return id
    end)
    table.insert(results, digest .. "=" .. (ok and tostring(result) or ("ERR:" .. tostring(result))))
end
return table.concat(results, "\n")
'''
    require(len(code.encode("utf-8")) <= MESH_BATCH_BYTES, "upload batch exceeds code payload budget")
    return code


def large_upload_codes(digest: str, wire: str, first_id: int) -> list[str]:
    """Carry oversized wire pieces in Instances; execute_luau calls share no Lua state."""
    stage_name = "__L2KMeshWire_" + digest[:16]
    pieces = [wire[i:i + MESH_SLICE_CHARS] for i in range(0, len(wire), MESH_SLICE_CHARS)]
    codes = []
    for index, piece in enumerate(pieces, 1):
        name = f"Part{index:03d}"
        code = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
                'local SS=game:GetService("ServerStorage")\n'
                f'local stage=SS:FindFirstChild({lua(stage_name)})\n'
                'if not stage then\n'
                '  stage=Instance.new("Folder")\n'
                f'  stage.Name={lua(stage_name)}\n'
                f'  stage:SetAttribute("WireSha256", {lua(digest)})\n'
                '  stage.Parent=SS\n'
                'end\n'
                f'assert(stage:GetAttribute("WireSha256") == {lua(digest)}, "Foreign mesh scratch")\n'
                f'local value=stage:FindFirstChild({lua(name)})\n'
                f'if value then assert(value.Value == {lua(piece)}, "Changed mesh scratch slice")\n'
                'else\n'
                '  value=Instance.new("StringValue")\n'
                f'  value.Name={lua(name)}\n'
                f'  value.Value={lua(piece)}\n'
                '  value.Parent=stage\n'
                'end\n'
                f'return "staged mesh slice {index}/{len(pieces)}"\n')
        require(len(code.encode("utf-8")) < MESH_BATCH_BYTES,
                f"mesh slice {digest}/{index} exceeds code budget")
        codes.append(code)
    builder_source = (ROOT / "tools/level4_blender/upload.luau").read_text(encoding="utf-8")
    builder = builder_source[builder_source.index("local function build(b)"):
                             builder_source.index("local function run()")]
    final = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
             'local SS=game:GetService("ServerStorage")\n'
             f'local stage=assert(SS:FindFirstChild({lua(stage_name)}), "Missing mesh scratch")\n'
             f'assert(stage:GetAttribute("WireSha256") == {lua(digest)}, "Foreign mesh scratch")\n'
             'local AS=game:GetService("AssetService")\n'
             'local ENC=game:GetService("EncodingService")\n' + builder +
             'local parts={}\n'
             f'for i=1,{len(pieces)} do\n'
             '  parts[i]=assert(stage:FindFirstChild(string.format("Part%03d",i)), "Missing mesh slice").Value\n'
             'end\n'
             'local wire=table.concat(parts)\n'
             f'assert(#wire == {len(wire)}, "Mesh wire length mismatch")\n'
             'local em=build(ENC:Base64Decode(buffer.fromstring(wire)))\n'
             'local status,id\n'
             'local ok,err=pcall(function()\n'
             '  for attempt=1,4 do\n'
             '    status,id=AS:CreateAssetAsync(em,Enum.AssetType.Mesh,{\n'
             f'      Name="L2K_Chunk_{first_id}",Description="Level 2 Blender kit mesh {digest}",\n'
             f'      CreatorId={GROUP_ID},CreatorType=Enum.AssetCreatorType.Group}})\n'
             '    if status==Enum.CreateAssetResult.Success then break end\n'
             '    if status~=Enum.CreateAssetResult.UploadFailed or attempt==4 then error(tostring(status)) end\n'
             '    task.wait(5*attempt)\n'
             '  end\n'
             'end)\n'
             'em:Destroy()\n'
             'if not ok then error(err) end\n'
             'stage:Destroy()\n'
             f'return {lua(digest + "=")} .. tostring(id)\n')
    require(len(final.encode("utf-8")) < MESH_BATCH_BYTES, "mesh upload final exceeds code budget")
    codes.append(final)
    return codes


def upload_meshes(client, studio_id: str, data: dict, receipts: dict) -> None:
    pending = [(digest, info["wire"]) for digest, info in data["unique_wires"].items()
               if digest not in receipts]
    batches = mesh_batches([(digest, wire) for digest, wire in pending if is_inline(wire)])
    large = [(digest, wire) for digest, wire in pending if not is_inline(wire)]
    ids = {digest: info["ids"] for digest, info in data["unique_wires"].items()}
    for index, batch in enumerate(batches, 1):
        code = upload_code(batch, ids)
        response = execute(client, studio_id, code)
        values = {}
        batch_keys = {digest for digest, _ in batch}
        for line in response.splitlines():
            key, separator, value = line.partition("=")
            if separator and key in batch_keys:
                values[key] = value.strip()
        failures = []
        for digest, _ in batch:
            value = values.get(digest, "")
            if re.fullmatch(r"\d+", value):
                receipts[digest] = {"assetId": int(value), "wireSha256": digest,
                                    "chunkIds": ids[digest], "group": GROUP_ID}
                write_receipts(MESH_RECEIPTS, receipts)
            else:
                failures.append((digest, value or "missing result"))
        print(f"mesh batch {index}/{len(batches)}: {len(batch) - len(failures)}/{len(batch)} received",
              flush=True)
        require(not failures, f"mesh upload failures (saved successful receipts): {failures[:5]}")
    for number, (digest, wire) in enumerate(large, 1):
        codes = large_upload_codes(digest, wire, ids[digest][0])
        print(f"sliced mesh {number}/{len(large)} {digest}: {len(codes)} calls", flush=True)
        for code in codes[:-1]:
            execute(client, studio_id, code)
        response = execute(client, studio_id, codes[-1])
        require(response.strip().startswith(digest + "="), f"missing sliced mesh receipt: {response[:500]}")
        value = response.strip().split("=", 1)[1]
        require(re.fullmatch(r"\d+", value) is not None, f"bad sliced mesh receipt: {response[:500]}")
        receipts[digest] = {"assetId": int(value), "wireSha256": digest,
                            "chunkIds": ids[digest], "group": GROUP_ID}
        write_receipts(MESH_RECEIPTS, receipts)
        print(f"sliced mesh {digest} -> {value}", flush=True)


def install(client, studio_id: str, plan: dict, staging: Path) -> None:
    require(plan["installable"], "upload all unique mesh and texture hashes, then rerun --plan")
    kit_name = plan["kitName"]
    stage_name = f"__{kit_name}_Installing_{plan['manifestSha256'][:12]}"
    probe = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
             'local SS=game:GetService("ServerStorage")\n'
             f'assert(not SS:FindFirstChild({lua(kit_name)}), "Existing kit: no overwrite")\n'
             f'local stage=SS:FindFirstChild({lua(stage_name)})\n'
             'if not stage then return "0" end\n'
             f'assert(stage:GetAttribute("ManifestSha256") == {lua(plan["manifestSha256"])}, "Staging hash differs")\n'
             f'assert(stage:GetAttribute("KitBuild") == {lua(plan["kitBuild"])}, "Staging build differs")\n'
             'assert(stage:GetAttribute("Ready") ~= true, "Staging kit already Ready")\n'
             'return tostring(stage:GetAttribute("NextPhase"))\n')
    first = int(execute(client, studio_id, probe).strip())
    require(0 <= first < len(plan["phases"]), f"invalid staged phase cursor {first}")
    if first:
        print(f"RESUME verified staging kit at phase {first + 1}/{len(plan['phases'])}", flush=True)
    for index in range(first, len(plan["phases"])):
        record = plan["phases"][index]
        path = staging / record["file"]
        code = path.read_text(encoding="utf-8")
        require(sha(path.read_bytes()) == record["sha256"], f"staged payload changed: {path}")
        response = execute(client, studio_id, code)
        if record["kind"] == "finalize":
            require(response.strip().startswith(f"installed {plan['kitName']}: "),
                    f"install phase {index + 1} returned unexpected result: {response[:500]}")
        else:
            expected = re.search(r'return "([^"]+)"\s*$', code)
            require(expected is not None and response.strip() == expected.group(1),
                    f"install phase {index + 1} returned unexpected result: {response[:500]}")
        print(f"install phase {index + 1}/{len(plan['phases'])} {record['kind']}: {response}", flush=True)


def audit(client, studio_id: str, data: dict, mesh_receipts: dict,
          texture_receipts: dict, kit_name: str) -> None:
    phases, slides_text = prepare(data, mesh_receipts, texture_receipts, kit_name)
    require(all(digest in mesh_receipts for digest in data["unique_wires"]) and
            all(digest in texture_receipts for digest in data["texture_sources"]),
            "audit requires complete receipt ledgers")
    slice_count = math.ceil(len(slides_text) / DATA_SLICE_CHARS)
    response = execute(client, studio_id,
                       audit_code(kit_name, data, mesh_receipts, texture_receipts, slice_count))
    print(response, flush=True)
    for index in range(1, slice_count + 1):
        code = (f'assert(game.PlaceId == {PLACE_ID}, "Wrong place")\n'
                f'local kit = assert(game:GetService("ServerStorage"):FindFirstChild({lua(kit_name)}))\n'
                'assert(kit:GetAttribute("Ready") == true, "Kit not Ready")\n'
                f'local value = assert(kit.Data:FindFirstChild("SlidesJSON-{index:03d}")).Value\n'
                'local hash = 5381\n'
                'for i = 1, #value do hash = (hash * 33 + string.byte(value, i)) % 4294967296 end\n'
                'return tostring(#value) .. ":" .. tostring(hash)')
        observed = execute(client, studio_id, code)
        expected = slides_text[(index - 1) * DATA_SLICE_CHARS:index * DATA_SLICE_CHARS]
        expected_check = f"{len(expected.encode('utf-8'))}:{djb2(expected.encode('utf-8'))}"
        require(observed.strip() == expected_check,
                f"SlidesJSON-{index:03d} content differs from export")
    print(f"AUDIT OK: all {slice_count} SlidesJSON slices match normalized slides.json", flush=True)


def main(argv: list[str] | None = None) -> int:
    global MESH_RECEIPTS, TEXTURE_RECEIPTS
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--plan", action="store_true", help="offline validation and compiled payload staging (default)")
    mode.add_argument("--upload-textures", action="store_true")
    mode.add_argument("--upload-meshes", action="store_true")
    mode.add_argument("--install", action="store_true")
    mode.add_argument("--audit", action="store_true")
    parser.add_argument("--studio-id", help="exact Studio session ID; required for all live modes")
    parser.add_argument("--kit-name", default="Level2BlenderKit")
    parser.add_argument("--profile", choices=("c", "poolrooms"), default="c")
    parser.add_argument("--export", type=Path,
                        help="offline validation fixture only; Studio modes require the canonical export")
    parser.add_argument("--staging", type=Path)
    args = parser.parse_args(argv)
    canonical = POOL_EXPORT if args.profile == "poolrooms" else EXPORT
    export = args.export or canonical
    staging = args.staging or (STAGING.parent / "poolrooms_install_staging" if args.profile == "poolrooms" else STAGING)
    if args.profile == "poolrooms":
        receipts = POOL_EXPORT.parent
        MESH_RECEIPTS = receipts / "roblox-assets.json"
        TEXTURE_RECEIPTS = receipts / "textures-published.json"
    offline = args.plan or not (args.upload_textures or args.upload_meshes or args.install or args.audit)
    if offline:
        require(not args.studio_id, "--plan is offline and does not accept --studio-id")
    else:
        require(args.studio_id and args.studio_id.strip() == args.studio_id,
                "live modes require an exact --studio-id")
        require(export.resolve() == canonical.resolve(), "Studio modes require the canonical Level 2 export")
    data = validate_export(export.resolve(), args.profile)
    texture_sources(data)
    meshes = load_receipts(MESH_RECEIPTS)
    check_mesh_receipts(meshes)
    textures = load_receipts(TEXTURE_RECEIPTS)
    check_mesh_receipts(textures, "texture")
    if offline:
        stage_plan(data, meshes, textures, args.kit_name, staging.resolve())
        return 0
    action = "upload textures" if args.upload_textures else "upload meshes" if args.upload_meshes else \
             "install" if args.install else "audit"
    print(f"WILL {action}: Studio ID {args.studio_id}, place {PLACE_ID}, kit {args.kit_name}", flush=True)
    plan = None
    if args.install:
        plan = stage_plan(data, meshes, textures, args.kit_name, staging.resolve())
        require(plan["installable"], "incomplete upload receipts; upload first and rerun --plan")
    if args.audit:
        require(all(h in meshes for h in data["unique_wires"]) and
                all(h in textures for h in data["texture_sources"]),
                "audit requires complete upload receipts")
    client = open_studio(args.studio_id, action)
    try:
        if args.upload_textures:
            upload_textures(client, args.studio_id, data["texture_sources"], textures)
        elif args.upload_meshes:
            upload_meshes(client, args.studio_id, data, meshes)
        elif args.install:
            install(client, args.studio_id, plan, staging.resolve())
        else:
            audit(client, args.studio_id, data, meshes, textures, args.kit_name)
    except Exception:
        if args.upload_meshes or args.install:
            report_leftovers(client, args.studio_id, args.kit_name)
        raise
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, IndexError, json.JSONDecodeError) as error:
        print(f"LEVEL 2 KIT IMPORT FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
