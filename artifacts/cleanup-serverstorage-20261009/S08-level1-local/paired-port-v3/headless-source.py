"""Actual shared Blender authoring kernels in a private test workspace only.

No production saves, uploads, Studio connection or renders. Exercises actual
V2 component/room and elevator component/assembly generation and mesh export.
"""
from pathlib import Path
import importlib.util
import json
import os
import shutil
import sys
import bpy

assert bpy.app.background
workspace=Path(sys.argv[sys.argv.index('--')+1]).resolve()
assert (workspace/'S08_PRIVATE_WORKSPACE').is_file(),'Private workspace marker required'

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

records={}
for kit,filename in (('blender-v2','build_v2.py'),('elevator-inset-20261004','elevator_inset.py')):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    module=load('S08_'+kit,workspace/'tools/level1_blender'/filename)
    output=workspace/'generated'/kit
    output.mkdir(parents=True)
    shutil.copytree(workspace/'assets/level1'/kit/'textures',output/'textures')
    module.b.OUT=output
    module.b.TEX=output/'textures'
    if kit=='blender-v2':
        module.build_components()
        catalogue=module.b.collection('L1 Room Catalogue',bpy.context.scene.collection)
        module.build_rooms(catalogue)
        data=module.export()
        assert len(data['rooms'])==42 and len(data['components'])==41
        assert len(catalogue.children)==42
    else:
        module.materials()
        module.build_exterior()
        module.build_cabin_components()
        module.build_assemblies()
        module.export()
        data=json.loads((output/'export/manifest.json').read_bytes())
        assert set(data['assemblies'])=={'CabinDepth'+str(n) for n in (12,14,16,18)}
        assert not data['rooms'] and not data['aliases']
        assert all(not value['colliders'] for value in data['components'].values())
    assert all(info['mesh'].uv_layers.active and len(info['mesh'].polygons)>0 for info in module.b.COMPONENTS.values())
    records[kit]={'components':len(data['components']),'rooms':len(data['rooms']),
                  'chunks':len(data['chunks']),'uvMeshes':len(module.b.COMPONENTS),'blender':bpy.app.version_string,
                  'pythonHashSeed':os.environ.get('PYTHONHASHSEED'),'hashProbe':hash('MongoTV-S08')}
(workspace/'headless-kernels.json').write_text(json.dumps(records,indent=2)+'\n')
print('S08_AUTHORING_KERNELS='+json.dumps(records),flush=True)
