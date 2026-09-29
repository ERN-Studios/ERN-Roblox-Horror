"""Render a readable overhead index of the seeded Blender Level 6 source."""

from pathlib import Path

import bpy
from mathutils import Vector


root = Path(bpy.data.filepath).resolve().parents[2]
target = root / "assets/level6-worn-party/Level6_FULL_Seed101_Overview.png"
scene = next(s for s in bpy.data.scenes if s.name.startswith("Level 6 | FULL"))
bpy.context.window.scene = scene
print("OVERVIEW_SOURCE", scene.name, len(scene.objects),
      sum(o.instance_type == "COLLECTION" for o in scene.objects),
      [(name, bpy.data.collections[name].hide_render, len(bpy.data.collections[name].all_objects))
       for name in ("L6K_FloorBeige", "L6K_Ceiling")], flush=True)
print("OVERVIEW_SAMPLE",
      [(o.name, tuple(round(v, 2) for v in o.location), o.hide_render)
       for o in list(bpy.data.collections["L6K_FloorBeige"].all_objects)[:2]],
      [(o.name, tuple(round(v, 2) for v in o.location), o.instance_collection.name if o.instance_collection else None)
       for o in list(scene.objects)[:4]], flush=True)
for obj in scene.objects:
    if obj.get("Level6_KitAsset") in {"Ceiling", "FluorescentFrame", "FluorescentDiffuser"}:
        obj.hide_render = True
sun_data = bpy.data.lights.new("Level 6 | plan light", "SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new(sun_data.name, sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (0.2, -0.3, -0.4)
camera_data = bpy.data.cameras.new("Level 6 | overview camera")
camera = bpy.data.objects.new(camera_data.name, camera_data)
scene.collection.objects.link(camera)
target_point = Vector((611.5, -294.0, 0.0))
camera.location = target_point + Vector((0.0, 0.0, 1700.0))
camera.rotation_euler = (target_point - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "ORTHO"
camera_data.ortho_scale = 1420.0
camera_data.clip_end = 5000.0
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(target)
scene.render.film_transparent = False
bpy.ops.render.render(write_still=True)
print("LEVEL6_OVERVIEW", target, flush=True)
