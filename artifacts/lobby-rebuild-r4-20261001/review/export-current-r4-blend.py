"""Read current R4 blend; export tangent-space FBX and actual detail render.

Background Blender only. Never save or rebuild the source blend/package.
"""
from pathlib import Path
import datetime,hashlib,json,math
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/"assets/models/lobby-reimagined-r4-20261001"
REVIEW=Path(__file__).resolve().parent
BLEND=OUT/"LobbyReimaginedPreview.blend"
MANIFEST=OUT/"manifest.json"
FBX=OUT/"LobbyReimaginedPreview.fbx"
RENDER=OUT/"blender-concrete-detail.png"

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
blend_sha=sha(BLEND);manifest_sha=sha(MANIFEST)
manifest=json.loads(MANIFEST.read_text())
assert manifest["revision"]==4 and manifest["sourceBlendSha256"]==blend_sha,"Current blend/manifest hash conflict"
protected={p.relative_to(OUT).as_posix():sha(p) for p in OUT.rglob("*") if p.is_file() and p.suffix not in (".fbx",".blend1",".log") and not p.name.startswith("blender-")}
old_fbx_sha=sha(FBX) if FBX.exists() else None
if FBX.exists():
    backup=REVIEW/"LobbyReimaginedPreview-before-tangents.fbx"
    if backup.exists():assert sha(backup)==old_fbx_sha,"Previous FBX backup already differs"
    else:backup.write_bytes(FBX.read_bytes())
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene=bpy.data.scenes["Lobby Reimagined | Full Preview"]
bpy.context.window.scene=scene
source_meshes=[o for o in scene.objects if o.type=="MESH"]
assert source_meshes and blend_sha==sha(BLEND),"Missing scene or source changed"
source_triangles=0
for obj in source_meshes:obj.data.calc_loop_triangles();source_triangles+=len(obj.data.loop_triangles)
export_scene=bpy.data.scenes.new("Roblox FBX | PBR and Color Atlas Tangents")
export_scene.unit_settings.system=scene.unit_settings.system
export_scene.unit_settings.scale_length=scene.unit_settings.scale_length
for src in source_meshes:
    obj=src.copy();obj.data=src.data.copy();obj.matrix_world=src.matrix_world
    export_scene.collection.objects.link(obj)
bpy.context.window.scene=export_scene
for obj in export_scene.objects:obj.select_set(True)
bpy.context.view_layer.objects.active=next(iter(export_scene.objects))
assert len({obj.data.as_pointer() for obj in export_scene.objects})==len(source_meshes)
result=bpy.ops.export_scene.fbx(filepath=str(FBX),use_selection=True,object_types={"MESH"},
 axis_forward="-Z",axis_up="Y",global_scale=1,apply_unit_scale=True,bake_anim=False,
 use_mesh_modifiers=True,use_tspace=True,use_triangles=True,path_mode="COPY",embed_textures=True,add_leaf_bones=False)
assert result=={"FINISHED"} and FBX.stat().st_size>100000,"FBX export failed"
from io_scene_fbx import parse_fbx
fbx_tree,fbx_version=parse_fbx.parse(str(FBX),use_namedtuple=True)
all_nodes=[]
def walk(node):
    all_nodes.append(node)
    for child in node.elems:walk(child)
walk(fbx_tree)
geometries=[n for n in all_nodes if n.id==b"Geometry" and len(n.props)>2 and n.props[2]==b"Mesh"]
polygons=0;all_triangles=True
for geometry in geometries:
    indices=next(n.props[0] for n in geometry.elems if n.id==b"PolygonVertexIndex")
    count=0
    for index in indices:
        count+=1
        if index<0:
            polygons+=1
            if count!=3:all_triangles=False
            count=0
    assert count==0,"Incomplete FBX polygon array"
tangent_layers=sum(n.id==b"LayerElementTangent" for n in all_nodes)
binormal_layers=sum(n.id==b"LayerElementBinormal" for n in all_nodes)
normal_layers=sum(n.id==b"LayerElementNormal" for n in all_nodes)
uv_layers=sum(n.id==b"LayerElementUV" for n in all_nodes)
assert len(geometries)==len(source_meshes) and all_triangles and polygons==source_triangles,"FBX mesh/triangle parity failed"
assert tangent_layers>=len(geometries) and binormal_layers>=len(geometries),"FBX missing tangent/binormal layers"
print("R4_TANGENT_FBX",json.dumps({"geometryCount":len(geometries),"triangles":polygons,"tangentLayers":tangent_layers}),flush=True)
# Actual authored scene/materials/lights. Camera changes live only in this
# background process and are never saved to the source file.
bpy.context.window.scene=scene
camera=scene.camera
position=(5,-44,29.6);target=(19,-36,30.1)
camera.location=position;camera.rotation_euler=(Vector(target)-Vector(position)).to_track_quat("-Z","Y").to_euler()
camera.data.lens=31;camera.data.clip_start=.05;camera.data.clip_end=500
scene.render.engine="CYCLES";scene.cycles.samples=64;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG";scene.render.filepath=str(RENDER)
bpy.ops.render.render(write_still=True)
assert RENDER.exists() and RENDER.stat().st_size>10000
assert sha(BLEND)==blend_sha,"Source blend changed during export/render"
changed=[name for name,before in protected.items() if sha(OUT/name)!=before]
assert not changed,"Protected package files changed during background export: "+repr(changed)
receipt={"schema":"lobby-r4-tangent-fbx-and-real-detail-render-v1", "atUTC":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "scope":"Official background Blender file export/render only; no live Blender, Studio, source blend save, package rebuild, Play or publication",
 "blenderVersion":bpy.app.version_string,"sourceBlend":str(BLEND.relative_to(ROOT)),"sourceBlendSHA256":blend_sha,
 "manifestSHA256":manifest_sha,"protectedFileCount":len(protected),"protectedFilesUnchanged":True,
 "previousFBXSHA256":old_fbx_sha,"fbxFile":str(FBX.relative_to(ROOT)),"fbxSHA256":sha(FBX),"fbxBytes":FBX.stat().st_size,
 "fbxVersion":fbx_version,"sourceMeshObjects":len(source_meshes),"fbxMeshGeometries":len(geometries),"sourceTriangles":source_triangles,"fbxTriangles":polygons,
 "useTspace":True,"useTriangles":True,"allFBXPolygonsTriangles":all_triangles,"tangentLayers":tangent_layers,"binormalLayers":binormal_layers,"normalLayers":normal_layers,"uvLayers":uv_layers,
 "renderFile":str(RENDER.relative_to(ROOT)),"renderSHA256":sha(RENDER),"renderCameraPosition":position,"renderCameraTarget":target,"renderLensMM":31,
 "renderSamples":64,"authoredMaterialsAndLightsUnchanged":True,"normalReliefScope":"Actual R4 authored color+OpenGL normal shader; visual detail inspection recorded separately"}
(REVIEW/"tangent-fbx-detail-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
print("R4_TANGENT_DETAIL_COMPLETE",json.dumps(receipt),flush=True)
