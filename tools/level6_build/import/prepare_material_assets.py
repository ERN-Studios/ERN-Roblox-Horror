"""Build a deterministic, deduplicated Studio image and material route manifest.

This only reads the authored Blender sidecars and writes local JSON. It does not
upload assets or modify the Studio place. Height maps remain authoring inputs.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
SOURCE = REPO / "artifacts/level6-blender-revision-20260930"
DESTINATION = REPO / "artifacts/level6-studio-revision-20261001/materials-studio"
ROLE_ORDER = ("color", "normalOpenGL", "roughness", "metalness")
SURFACES = frozenset({
    "carpet_default", "carpet_neon", "carpet_red", "carpet_city",
    "wallpaper", "orange_wall", "red_wall", "diamondplate", "kitchen_tile",
})


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    authored = json.loads((SOURCE / "materials/material-manifest.json").read_text())
    imported = json.loads((SOURCE / "exports/import-manifest.json").read_text())
    images: dict[str, dict] = {}
    sha_to_key: dict[str, str] = {}
    variants: dict[str, dict] = {}
    routes: list[dict] = []

    def image_key(relative: str) -> str:
        path = SOURCE / relative
        assert path.is_file(), f"Missing texture {relative}"
        sha = digest(path)
        if sha in sha_to_key:
            return sha_to_key[sha]
        key = relative.replace("materials/", "").replace("exports/", "")
        key = key.replace("/", "__").replace("-1024.png", "").replace(".png", "")
        assert key not in images
        images[key] = {
            "key": key,
            "source": str(path.relative_to(REPO)),
            "sha256": sha,
            "width": 1024,
            "height": 1024,
        }
        sha_to_key[sha] = key
        return key

    for index, mesh in enumerate(imported["meshes"]):
        maps = mesh["maps"]
        surface = mesh.get("surface")
        if surface == "orange_wall" and maps.get("color") == "exports/red-wall-color-1024.png":
            surface = "red_wall"
        assert (surface is None) == (len(maps) == 1 and "color" in maps)
        suffix = mesh["object"].split("__", 1)[1]
        route = {
            "chunkId": index,
            "family": mesh["asset"],
            "childName": f"m{index:03d}__{suffix}",
            "object": mesh["object"],
            "material": mesh["material"],
        }
        if surface is None:
            assert maps["color"] == "materials/props/color-1024.png"
            route["atlasImageKey"] = image_key(maps["color"])
        else:
            assert surface in SURFACES
            route["variantKey"] = surface
            definition = variants.get(surface)
            keys = {role: image_key(maps[role]) for role in ROLE_ORDER if role in maps}
            if definition is None:
                source_key = "orange_wall" if surface == "red_wall" else surface
                repeat = authored["materials"][source_key]["physicalRepeatStuds"]
                definition = {
                    "name": "L6R_" + "".join(word.capitalize() for word in surface.split("_")),
                    "baseMaterial": "SmoothPlastic",
                    "studsPerTile": repeat,
                    "normalConvention": "OpenGL +Y tangent",
                    "mapImageKeys": keys,
                }
                variants[surface] = definition
            else:
                assert definition["mapImageKeys"] == keys, f"Inconsistent maps for {surface}"
        routes.append(route)

    assert len(routes) == 279, len(routes)
    assert len(images) == 27, len(images)
    assert len(variants) == 9, len(variants)
    assert sum("variantKey" in r for r in routes) == 20
    payload = {
        "schema": "level6-studio-material-routes/1",
        "placeId": 131311258779917,
        "universeId": 10559217407,
        "groupId": 1039373905,
        "sourceImportManifestSha256": digest(SOURCE / "exports/import-manifest.json"),
        "sourceMaterialManifestSha256": digest(SOURCE / "materials/material-manifest.json"),
        "images": [images[key] for key in sorted(images)],
        "variants": {key: variants[key] for key in sorted(variants)},
        "routes": routes,
    }
    DESTINATION.mkdir(parents=True, exist_ok=True)
    target = DESTINATION / "material-routes.json"
    target.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"{target}: {len(images)} unique uploadable images, {len(variants)} PBR variants, {len(routes)} segment routes")


if __name__ == "__main__":
    main()
