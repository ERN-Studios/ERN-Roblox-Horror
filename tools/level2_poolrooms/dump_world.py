"""Dump exact offline Poolrooms builds for Blender reconstruction.

Run with ``python -B tools/level2_poolrooms/dump_world.py 837834 1 101``.
The existing test harness supplies the fake engine and installed kit fixtures.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.tests import test_level2_kit_world_builder as harness  # noqa: E402

OUTPUT = Path("G:/Blender/Level2_Poolrooms/worlds")
BASEPART_CLASSES = {"Part", "MeshPart", "WedgePart", "SpawnLocation"}


def instrument(program):
    """Record placements before flattened component Models are destroyed."""
    edits = (
        ("local Builder=(function()", "local DUMP_PLACEMENTS={}\nlocal Builder=(function()"),
        (
            "    model.Parent = parent\n    for _, p in ipairs(model:GetDescendants()) do",
            "    model.Parent = parent\n"
            "    DUMP_PLACEMENTS[#DUMP_PLACEMENTS+1]={Component=name,"
            "Pivot=model.WorldPivot,ModelPath=model:GetFullName(),ModelId=model._id,"
            "ParentId=parent._id,Flattened=flatten}\n"
            "    for _, p in ipairs(model:GetDescendants()) do",
        ),
        ("Objects=objects,Fills=fills", "Objects=objects,Placements=DUMP_PLACEMENTS,Fills=fills"),
        ("    fills={}\n    local baseline=", "    fills={} DUMP_PLACEMENTS={}\n    local baseline="),
        (
            '''if kind=="CFrame" then return '{"$cframe":['..table.concat({value:GetComponents()},",")..']}' end''',
            '''if kind=="CFrame" then
        local numbers={value:GetComponents()}
        for i,n in ipairs(numbers) do numbers[i]=string.format("%.17g",n) end
        return '{"$cframe":['..table.concat(numbers,",")..']}'
    end''',
        ),
    )
    for old, new in edits:
        assert program.count(old) == 1, f"offline harness instrumentation anchor changed: {old!r}"
        program = program.replace(old, new, 1)
    return program


def vector(value):
    assert value.get("$type") == "Vector3", value
    return [value[axis] for axis in "XYZ"]


def cframe(value):
    numbers = value["$cframe"]
    assert len(numbers) == 12 and all(isinstance(n, (int, float)) for n in numbers)
    return numbers


def color(value):
    assert value.get("$type") == "Color3", value
    return [value[axis] for axis in "RGB"]


def export(build):
    objects = {obj["Id"]: obj for obj in build["Objects"]}
    paths = {}

    def path(obj):
        if obj["Id"] not in paths:
            parent = objects.get(obj["Parent"])
            paths[obj["Id"]] = (path(parent) if parent else "game.Workspace") + "." + obj["Name"]
        return paths[obj["Id"]]

    parts = []
    for obj in build["Objects"]:
        if obj["ClassName"] not in BASEPART_CLASSES:
            continue
        parent = objects.get(obj["Parent"])
        parts.append({
            "id": obj["Id"],
            "name": obj["Name"],
            "class": obj["ClassName"],
            "shape": obj.get("Shape", {"MeshPart": "Mesh", "WedgePart": "Wedge"}.get(obj["ClassName"], "PartType.Block")),
            "size": vector(obj["Size"]),
            "cframe": cframe(obj["CFrame"]),
            "canCollide": obj["CanCollide"],
            "canQuery": obj["CanQuery"],
            "canTouch": obj["CanTouch"],
            "anchored": obj["Anchored"],
            "castShadow": obj["CastShadow"],
            "transparency": obj["Transparency"],
            "material": obj["Material"],
            "materialVariant": obj["MaterialVariant"],
            "color": color(obj["Color"]),
            "reflectance": obj.get("Reflectance", 0),
            "parentId": obj["Parent"],
            "parentPath": path(parent) if parent else "game.Workspace",
            "path": path(obj),
            "attributes": obj["Attrs"],
            "fixtureComponent": obj.get("FixtureComponent"),
            "fixtureKind": obj.get("FixtureKind"),
            "collisionFidelity": obj.get("CollisionFidelity"),
            "customPhysicalProperties": obj.get("CustomPhysicalProperties"),
        })

    placements = [{
        "component": item["Component"],
        "pivot": cframe(item["Pivot"]),
        "modelPath": item["ModelPath"],
        "modelId": item["ModelId"],
        "parentId": item["ParentId"],
        "flattened": item["Flattened"],
    } for item in build["Placements"]]
    assert placements, "no kit components were recorded"
    for item in placements:
        assert item["modelPath"].startswith("game.Workspace.Level 2 Generated World."), item
        if item["modelId"] in objects:
            assert objects[item["modelId"]]["ClassName"] == "Model", item

    regions = build["Manifest"]["WaterRegions"]
    assert len(regions) == len(build["Fills"])
    water = []
    for region, fill in zip(regions, build["Fills"]):
        assert region["CFrame"] == fill["CFrame"] and region["Size"] == fill["Size"]
        water.append({
            "label": region.get("Label"),
            "cframe": cframe(region["CFrame"]),
            "size": vector(region["Size"]),
            "material": fill["Material"],
        })

    return {
        "requestedSeed": build["RequestedSeed"],
        "seed": build["Layout"]["Seed"],
        "generation": build["Generation"],
        "builderSha256": hashlib.sha256(harness.BUILDER.read_bytes()).hexdigest(),
        "kitExports": {
            job: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for job in "ABCD"                      # D = swerve pieces; read_exports loads it when present
            for path in [harness.JOBS / job / "export/manifest.json"] if path.is_file()
        },
        "layout": build["Layout"],
        "parts": parts,
        "components": placements,
        "terrainWaterRegions": water,
        "terrainWaterAppearance": build["AfterWater"],
        "terrainCenter": vector(build["Manifest"]["TerrainCenter"]),
        "terrainSize": vector(build["Manifest"]["TerrainSize"]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seeds", nargs="+", type=int)
    parser.add_argument("--out", type=Path, default=OUTPUT, help=f"output dir (default {OUTPUT})")
    args = parser.parse_args()
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or harness.DEFAULT_BIN
    components, slides = harness.read_exports()
    program = instrument(harness.build_program(args.seeds, components, slides))
    builds = harness.run_luau(binary, program)
    assert len(builds) == len(args.seeds), f"expected {len(args.seeds)} builds, received {len(builds)}"
    args.out.mkdir(parents=True, exist_ok=True)
    for build in builds:
        data = export(build)
        target = args.out / f"world_{data['requestedSeed']}.json"
        with target.open("w", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, ensure_ascii=False, separators=(",", ":"))
            stream.write("\n")
        print(f"{target}: {len(data['parts'])} BaseParts, "
              f"{len(data['components'])} kit placements, "
              f"{len(data['terrainWaterRegions'])} water regions")


if __name__ == "__main__":
    main()
