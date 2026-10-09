"""Build the Poolrooms modules into one export and a reviewable Blender scene.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level2_poolrooms/build.py
"""

import importlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy
import prkit as kit


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    built = []
    # The tunnel module validates its own registry, so it must run first.
    for name in ("modules_tunnel", "modules_arch", "objectives", "modules_swerve"):
        before = set(kit.COMPONENTS)
        importlib.import_module(name).build()
        added = len(set(kit.COMPONENTS) - before)
        built.append((name, added))
        print("PR_MODULE", name, added, flush=True)
    manifest = kit.export()
    for stale in (kit.EXPORT_DIR / "chunks").glob("c*.b64"):
        if stale.name not in {f"c{i:05d}.b64" for i in range(len(manifest["chunks"]))}:
            stale.unlink()
    root = bpy.data.collections.new("Poolrooms Components")
    bpy.context.scene.collection.children.link(root)
    for i, component in enumerate(kit.COMPONENTS):
        kit.place(root, component, ((i % 12) * 120, 0, (i // 12) * 120))
    kit.KIT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.KIT_DIR / "Level2_PoolroomsKit.blend"))
    print("PR_BUILD=" + json.dumps({"modules": built,
        "components": len(manifest["components"]), "chunks": len(manifest["chunks"]),
        "tris": sum(chunk["tris"] for chunk in manifest["chunks"])}), flush=True)


main()
