import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
from watcher_common import *

base = Path(__file__).resolve().parents[1]
output = base
output.mkdir(parents=True, exist_ok=True)
import_asset(base / "meshy-source" / "window-watcher-rigged.glb")
rig = get_rig()
meshes = bound_meshes(rig)
activate_action(rig, None)
reset_pose(rig)
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
for obj in list(bpy.context.scene.objects):
    if obj != rig and obj not in meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
rig.name = "WindowWatcherRig"
meshes[0].name = "WindowWatcher"
select_export_objects(rig)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
# Meshy's glTF uses dramatically oversize display tails. Shorten along each
# existing axis: head/orientation/rest deformation stay unchanged.
for bone in rig.data.edit_bones:
    child_distances = [(c.head - bone.head).length for c in bone.children]
    bone.length = min(child_distances) if child_distances else 0.08
root = rig.data.edit_bones.new("Root")
root.head, root.tail = (0, 0, 0), (0, 0, 0.15)
root.use_deform = False
rig.data.edit_bones["Hips"].parent = root
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.scene.render.fps = FPS
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0
rig["source"] = "Meshy task rigged GLB, source preserved in meshy-source"
rig["forward_blender"] = "-Y"
rig["height_meters"] = 2.4
bpy.ops.file.pack_all()
write_json(output / "prepared-rig-inventory.json", inventory())
bpy.ops.wm.save_as_mainfile(filepath=str(output / "prepared-rig.blend"))
export_fbx(output / "model.fbx", rig, False)
select_export_objects(rig)
bpy.ops.export_scene.gltf(filepath=str(output / "model.glb"), export_format="GLB",
    use_selection=True, export_animations=False, export_skins=True,
    export_influence_nb=4, export_all_influences=False)
print("WATCHER_MODEL_READY=" + str(output))
