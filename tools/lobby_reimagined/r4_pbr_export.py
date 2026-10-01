"""R4 material-aware mesh export. Authoring/serialization only, no Studio writes."""
from pathlib import Path
import base64,hashlib,json,math
import bpy
from mathutils import Vector


def configure_pbr(out, bindings):
    data=json.loads((out/'textures/manifest.json').read_text())
    source=data['materials']
    if isinstance(source,list):source={x['key']:x for x in source}
    packs={}
    for mat,key in bindings.items():
        spec=dict(source[key]); spec['tileStuds']=10 if key in ('tunnel_concrete','asphalt_road') else spec['tileStuds']
        mat['r4_pbr_key']=key;mat['r4_studs_per_tile']=spec['tileStuds']
        sh=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        for role,slot in (('color','Base Color'),('roughness','Roughness')):
            img=bpy.data.images.load(str(out/'textures'/spec['maps'][role]['file']),check_existing=True)
            if role!='color':img.colorspace_settings.name='Non-Color'
            img.pack();node=nodes.new('ShaderNodeTexImage');node.image=img;node.extension='REPEAT'
            links.new(node.outputs['Color'],sh.inputs[slot])
        img=bpy.data.images.load(str(out/'textures'/spec['maps']['normal']['file']),check_existing=True);img.colorspace_settings.name='Non-Color';img.pack()
        tex=nodes.new('ShaderNodeTexImage');tex.image=img;tex.extension='REPEAT'
        normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=1
        links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],sh.inputs['Normal'])
        # Retain the real height image and a labeled optional bump node without
        # adding the same photographed relief twice to the active normal shader.
        height=bpy.data.images.load(str(out/'textures'/spec['maps']['height']['file']),check_existing=True);height.colorspace_settings.name='Non-Color';height.pack()
        ht=nodes.new('ShaderNodeTexImage');ht.image=height;ht.label='Real 16-bit height / optional editing'
        bump=nodes.new('ShaderNodeBump');bump.label='Optional height relief (normal map already active)';bump.inputs['Distance'].default_value=.015
        links.new(ht.outputs['Color'],bump.inputs['Height'])
        packs[key]=spec
    return packs


def projected_uv(v,n,tile):
    axis=max(range(3),key=lambda a:abs(n[a]))
    if axis==0:return (v.y*(1 if n.x>0 else -1)/tile,v.z/tile)
    if axis==1:return (v.x*(-1 if n.y>0 else 1)/tile,v.z/tile)
    return (v.x*(1 if n.z>0 else -1)/tile,v.y/tile)


def project_pbr_uvs(families,packs):
    for objs in families.values():
        for obj in objs:
            if obj.type!='MESH':continue
            mesh=obj.data;uv=mesh.uv_layers.get('AtlasUV') or mesh.uv_layers.new(name='AtlasUV');mesh.uv_layers.active=uv
            for p in mesh.polygons:
                mat=mesh.materials[p.material_index]
                if not mat.get('r4_pbr_key') and not mat.get('r4_texture_source'):continue
                tile=mat.get('r4_studs_per_tile',8)
                # Exact analytic U/V was authored by Geometry.arc (tunnel).
                if obj.name in ('PlainShell','PortalShell','ArchRib') and p.use_smooth:continue
                for li in p.loop_indices:
                    v=mesh.vertices[mesh.loops[li].vertex_index].co
                    # Curved bay walls use angle and height, continuous across panels.
                    if obj.get('r4_role')=='bay-shell' and p.use_smooth and abs(p.normal.z)<.2:
                        theta=math.atan2(v.y,v.x)
                        if theta<math.radians(-66):theta+=math.tau
                        uv.data[li].uv=(28*theta/tile,v.z/tile)
                    else:uv.data[li].uv=projected_uv(v,p.normal,tile)


def export_material_chunks(families,out,exporter):
    chunks=[]
    for family,objects in sorted(families.items()):
        grouped={}
        for obj in objects:
            if obj.type!='MESH':continue
            for mat in obj.data.materials:
                key=mat.get('r4_pbr_key') or ('asset_'+mat['r4_texture_source'].split('//')[-1] if mat.get('r4_texture_source') else 'atlas')
                grouped.setdefault(key,[])
        for key in sorted(grouped):
            copies=[]
            for obj in objects:
                if obj.type!='MESH':continue
                data=obj.data.copy();keep=[]
                for poly in data.polygons:
                    mat=data.materials[poly.material_index]
                    role=mat.get('r4_pbr_key') or ('asset_'+mat['r4_texture_source'].split('//')[-1] if mat.get('r4_texture_source') else 'atlas')
                    if role==key:keep.append(poly.index)
                if not keep:continue
                # BMesh removes unwanted faces with their corner attributes and
                # leaves intentional custom normals; export copies never affect authors.
                import bmesh
                bm=bmesh.new();bm.from_mesh(data);bm.faces.ensure_lookup_table()
                bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in set(keep)],context='FACES')
                bm.to_mesh(data);bm.free();data.update()
                # BMesh does not preserve custom split-normal attributes reliably.
                # Reassign exact radial shell normals on the independent copy.
                normals=[]
                for poly in data.polygons:
                    if poly.use_smooth and obj.name in ('PlainShell','PortalShell','ArchRib'):
                        c=poly.center;sign=1 if poly.normal.x*c.x+poly.normal.z*(c.z-1)>0 else -1
                        for li in poly.loop_indices:
                            v=data.vertices[data.loops[li].vertex_index].co;n=Vector((v.x,0,v.z-1)).normalized()*sign;normals.append(tuple(n))
                    elif poly.use_smooth and obj.get('r4_role')=='bay-shell' and abs(poly.normal.z)<.2:
                        c=poly.center;sign=1 if poly.normal.x*c.x+poly.normal.y*c.y>0 else -1
                        for li in poly.loop_indices:
                            v=data.vertices[data.loops[li].vertex_index].co;normals.append(tuple(Vector((v.x,v.y,0)).normalized()*sign))
                    else:
                        for li in poly.loop_indices:normals.append(tuple(obj.data.corner_normals[li].vector) if len(data.polygons)==len(obj.data.polygons) else tuple(poly.normal))
                if normals:data.normals_split_custom_set(normals)
                copy=bpy.data.objects.new(obj.name+'_export_'+key,data);copy.matrix_world=obj.matrix_world.copy();bpy.context.scene.collection.objects.link(copy);copies.append(copy)
            if not copies:continue
            material_metadata={'materialKey':key}
            if key.startswith('asset_'):material_metadata['colorAssetId']=key[len('asset_'):]
            chunks.append(exporter(family+'_'+key,copies,out,len(chunks),metadata={'family':family,**material_metadata}))
            for copy in copies:bpy.data.objects.remove(copy,do_unlink=True)
    return chunks


def runtime_texture_packs(out,packs):
    # PNG bytes are encoded by Pillow without Blender's color conversions.
    raw=json.loads((out/'textures/runtime-pixels.json').read_text())
    grouped={}
    for item in raw['images']:
        grouped.setdefault(item['materialKey'],{})[item['role']]={'file':'textures/'+item['file'],'width':item['width'],'height':item['height'],'bytes':item['rgbaBytes'],'sha256':item['rgbaSHA256'],'rowOrder':item['rowOrder'],'normalConvention':'OpenGL'}
    return {key:{'maps':grouped[key],'tileStuds':spec['tileStuds'],'source':spec['source'],'roughness':spec['roughnessMinimum']} for key,spec in packs.items()}
