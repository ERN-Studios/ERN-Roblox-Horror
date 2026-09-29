"""Blender-authored reusable prefabs -> lossless mesh/normal/UV upload chunks.

Run/import inside Blender. One unit is one stud. The proper rotation (X,Z,-Y)
preserves winding. Root build owns atlas UV authoring and collider metadata.
"""
import base64
import hashlib
import json
import pathlib
import struct

import bpy
from mathutils import Matrix, Vector

MAGIC = 0x364D564C
AXIS = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))


def export_prefab(name, objects, output_dir, chunk_id, pivot=None, metadata=None):
    """Return a manifest chunk. pivot is a Blender world-space Matrix.

    Export visual mesh objects only. Colliders/lights/interaction anchors are
    carried in metadata as Roblox-space values authored by the build script.
    UVs are preserved exactly; ensure an active UV layer exists on every mesh.
    """
    output = pathlib.Path(output_dir)
    (output / "chunks").mkdir(parents=True, exist_ok=True)
    pivot_inverse = (pivot or Matrix.Identity(4)).inverted()
    graph = bpy.context.evaluated_depsgraph_get()
    points, normals, uvs, faces = [], [], [], []
    point_lookup, normal_lookup, uv_lookup = {}, {}, {}

    def intern(value, values, lookup, digits):
        key = tuple(round(float(v), digits) for v in value)
        if key not in lookup:
            lookup[key] = len(values)
            values.append(key)
        return lookup[key]

    for obj in objects:
        if obj.type != "MESH" or obj.get("L6Collider", False):
            continue
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            if not mesh.uv_layers.active:
                raise ValueError(f"{name}/{obj.name} has no active atlas UV layer")
            transform = pivot_inverse @ evaluated.matrix_world
            normal_transform = transform.to_3x3().inverted().transposed()
            mirrored = transform.to_3x3().determinant() < 0
            for tri in mesh.loop_triangles:
                corners = list(tri.loops)
                if mirrored:
                    corners = [corners[0], corners[2], corners[1]]
                face = []
                for loop_index in corners:
                    loop = mesh.loops[loop_index]
                    point = AXIS @ (transform @ mesh.vertices[loop.vertex_index].co)
                    normal = (AXIS @ (normal_transform @ mesh.corner_normals[loop_index].vector)).normalized()
                    uv = mesh.uv_layers.active.data[loop_index].uv
                    face.extend((intern(point, points, point_lookup, 6),
                                 intern(normal, normals, normal_lookup, 6),
                                 intern(uv, uvs, uv_lookup, 7)))
                faces.append(tuple(face))
        finally:
            evaluated.to_mesh_clear()

    if not faces or len(faces) > 20000 or len(points) > 60000:
        raise ValueError(f"{name}: expected 1..20000 triangles/<=60000 vertices; got {len(faces)}/{len(points)}")
    lower = [min(p[i] for p in points) for i in range(3)]
    upper = [max(p[i] for p in points) for i in range(3)]
    center = [(a + b) / 2 for a, b in zip(lower, upper)]
    size = [b - a for a, b in zip(lower, upper)]
    if max(size) >= 2048 or min(size) <= 0:
        raise ValueError(f"{name}: mesh bounds must have positive volume and stay below 2048 studs: {size}")
    body = bytearray(struct.pack("<5I", MAGIC, len(points), len(normals), len(uvs), len(faces)))
    for p in points:
        body.extend(struct.pack("<3f", *(p[i] - center[i] for i in range(3))))
    for normal in normals:
        body.extend(struct.pack("<3f", *normal))
    for uv in uvs:
        body.extend(struct.pack("<2f", *uv))
    for face in faces:
        body.extend(struct.pack("<9I", *face))
    relative = f"chunks/c{chunk_id:05d}.b64"
    (output / relative).write_bytes(base64.b64encode(body))
    return {
        "id": chunk_id, "name": name, "file": relative,
        "sha256": hashlib.sha256(body).hexdigest(), "bytes": len(body),
        "vertices": len(points), "normals": len(normals), "uvs": len(uvs),
        "triangles": len(faces), "center": center, "size": size,
        **(metadata or {}),
    }


def export_collections(output_dir, prefix="L6K_", metadata=None, atlas="atlas.png"):
    """Convenience entrypoint; a collection's L6Pivot empty defines local origin."""
    chunks = []
    for collection in sorted(bpy.data.collections, key=lambda c: c.name):
        if not collection.name.startswith(prefix):
            continue
        pivot = next((o for o in collection.all_objects if o.type == "EMPTY" and o.get("L6Pivot")), None)
        chunks.append(export_prefab(collection.name[len(prefix):], collection.all_objects,
            output_dir, len(chunks), pivot.matrix_world if pivot else None,
            (metadata or {}).get(collection.name, {})))
    manifest = {"schema": "level6-blender-prefabs-v1", "axisMapping": "X,Z,-Y", "studsPerUnit": 1,
                "groupId": 1039373905, "atlas": atlas, "chunks": chunks}
    pathlib.Path(output_dir, "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest
