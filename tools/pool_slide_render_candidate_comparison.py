"""Render fixed-time Pool Slide frames from a GLB using the existing preview scene.

Run headlessly with the v1 .blend loaded; this script mutates only the in-memory
scene and writes PNGs. It never saves the .blend or edits Roblox assets.
"""
import argparse
import math
from pathlib import Path
import sys

import bpy


def main():
    argv = sys.argv[sys.argv.index("--")+1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--label", required=True)
    args = ap.parse_args(argv)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for obj in list(bpy.context.scene.objects):
        if obj.type == "ARMATURE" or obj.name in ("Mesh_0", "Mesh_02"):
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        if action.users == 0:
            bpy.data.actions.remove(action)
    bpy.ops.import_scene.gltf(filepath=str(args.source.resolve()))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    print("RIG", rig.name, "ACTIONS", [a.name for a in bpy.data.actions])
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    points = (("Walk", 0.325), ("Walk", 0.825),
              ("Run", 0.283333333333), ("Run", 0.55))
    for name, at in points:
        action = next(a for a in bpy.data.actions if a.name.split(".")[0] == name)
        rig.animation_data_create()
        rig.animation_data.action = action
        if rig.animation_data.action_slot is None and action.slots:
            rig.animation_data.action_slot = action.slots[0]
        frame_float = at*scene.render.fps/scene.render.fps_base
        frame_int = math.floor(frame_float)
        scene.frame_set(frame_int, subframe=frame_float-frame_int)
        scene.render.filepath = str((args.out_dir / f"{args.label}_{name.lower()}_{int(round(at*10000)):05d}.png").resolve())
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    main()
