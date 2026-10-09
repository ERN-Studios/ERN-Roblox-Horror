"""Smoke test for kit.py: two components, export, one EEVEE render. Writes only under G:/Blender/Level2_Pool/smoke."""
import sys, math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import bpy
import kit
kit.EXPORT_DIR = kit.KIT_DIR / "smoke" / "export"
bpy.ops.wm.read_factory_settings(use_empty=True)
m = kit.Mesh("WallTest")
m.box((0, 10, 0), (40, 20, 2), "Tile", bevel=0)
m.box((0, 2, -1.1), (40, 4, .3), "TileTeal", bevel=0)
for i, mat in enumerate(("BandCoral", "BandYellow", "BandBlue")):
    m.box((0, 14 + i * .7, -1.1), (40, .6, .2), mat, bevel=0)
m.cylinder((12, 8, -6), 2.75, 16, "Tile").part("Deck", (0, -.35, -10), (40, .7, 16), "Terrazzo", ground=True)
m.finish()
col = bpy.data.collections.new("Smoke"); bpy.context.scene.collection.children.link(col)
kit.place(col, "WallTest")
man = kit.export()
assert man["chunks"] and all(c["tris"] > 0 for c in man["chunks"])
sc = bpy.context.scene
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); col.objects.link(cam); sc.camera = cam
cam.location = kit.to_blender((0, 8, -40)); cam.rotation_euler = (math.radians(88), 0, math.radians(180))
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")); col.objects.link(sun); sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.world = bpy.data.worlds.new("W"); sc.world.color = (.5, .55, .6)
sc.render.engine = "BLENDER_EEVEE"; sc.render.resolution_x, sc.render.resolution_y = 800, 450
sc.render.filepath = str(kit.KIT_DIR / "smoke" / "smoke.png")
bpy.ops.render.render(write_still=True)
print("SMOKE_OK", len(man["chunks"]), [c["material"] for c in man["chunks"]])
