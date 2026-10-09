"""Build the whole Level 2 kit (every module file), export one manifest and save the generated .blend.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level2_blender/build.py
Writes assets/level2/blender-kit/export/ (manifest + chunk wire files) and G:/Blender/Level2_Pool/Level2_PoolKit.blend
(a generated file: never hand-edit it, rebuild instead).
"""
import importlib, json, shutil, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import bpy
import kit

MODULES = ("modules_arch", "modules_tunnel", "rooms_small", "props_meshy", "slides", "modules_extra", "props_small")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    built = []
    for name in MODULES:
        if not (Path(__file__).parent / (name + ".py")).exists():
            print("L2K_SKIP", name, "(not written yet)", flush=True)
            continue
        before = set(kit.COMPONENTS)
        importlib.import_module(name).build()
        added = sorted(set(kit.COMPONENTS) - before)
        built.append((name, len(added)))
        print("L2K_MODULE", name, len(added), flush=True)
    manifest = kit.export()
    # slides.json (segment records for the runtime slide placer) is written by slides.py's own checked run.
    slides = Path("G:/Blender/Level2_Pool/jobs/F/export/slides.json")
    if slides.exists():
        shutil.copyfile(slides, kit.EXPORT_DIR / "slides.json")
    root = bpy.data.collections.new("L2K Components")
    bpy.context.scene.collection.children.link(root)
    for i, comp in enumerate(kit.COMPONENTS):
        kit.place(root, comp, ((i % 12) * 120, 0, (i // 12) * 120))
    kit.KIT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.KIT_DIR / "Level2_PoolKit.blend"))
    summary = {"modules": built, "components": len(manifest["components"]), "chunks": len(manifest["chunks"]),
               "tris": sum(c["tris"] for c in manifest["chunks"]),
               "variants": sorted({m["variant"] for m in manifest["materials"].values() if m.get("variant")}),
               "atlases": sorted(k for k, m in manifest["materials"].items() if m.get("atlas"))}
    print("L2K_BUILD=" + json.dumps(summary), flush=True)


main()
