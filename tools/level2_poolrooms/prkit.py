"""Level 2 POOLROOMS kit foundation (restart 2026-10-03; a copy of tools/level2_blender/kit.py with its own materials
and paths): units, PBR materials, the Mesh builder, part/collider/marker records and export.

Imported by the module files (modules_*.py) and build.py, inside headless Blender only:
    D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level2_blender/build.py
Conventions (artifacts/level2-blender-20261002/KIT_SPEC.md): every number a module passes is in STUDS, Roblox axes
(x right, y up, z back). The Mesh builder converts to Blender metres (0.28 m/stud, Blender (x,y,z) = Roblox (x,-z,y)).
One material per chunk -> one MeshPart with a MaterialVariant; UVs are in texture repeats (metres / tile_m).
"""
from pathlib import Path
import base64, hashlib, json, math
import bpy, bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
KIT_DIR = Path("G:/Blender/Level2_Poolrooms")
PBR_DIR = KIT_DIR / "textures" / "pbr"
EXPORT_DIR = ROOT / "assets" / "level2" / "poolrooms-kit" / "export"
S = 0.28                                                      # metres per stud
C = np.array(((1, 0, 0), (0, 0, 1), (0, -1, 0)), float)       # Blender -> Roblox axes (Level 1/4 exporters)
TILE = 0.5            # grout pitch in studs: one global lattice (LATTICE_SPEC 2.1, was 0.6)
TILE_M = 8 * TILE * 0.28   # one texture = 8 x 8 tiles over 4.0 studs (MaterialVariant StudsPerTile 4.0)
STEEL = Path("G:/Blender/Level2_Pool/textures/pbr")      # reused brushed-steel maps for iron/steel parts
MATERIALS, COMPONENTS = {}, {}
assert bpy.app.background, "Use independent headless Blender; never the owner's open scene"

# G1 (owner fix list 2, 2026-10-04): ONE tile look. Every tiled surface is SmoothPlastic + 'PR Tile' (above water) or
# 'PR Tile Aqua' (submerged floors), Color TILE_RGB, Reflectance 0.06.
TILE_RGB = (241, 237, 220)   # == Kit World Builder WHITE (Color3.fromRGB(241,237,220)); change both together or neither
TILE_REFLECTANCE = 0.06
RETIRED = {"TileShade", "Worn"}   # owner rejected colour bands / worn patches (F3); a use fails the kit build
# name: (pbr set or None, Roblox MaterialVariant or None, tint rgb, tile metres). Tints multiply the colour map.
PALETTE = {
    "Tile": ("pr_tile", "PR Tile", TILE_RGB, TILE_M),
    "Aqua": ("pr_aqua", "PR Tile Aqua", TILE_RGB, TILE_M),
    "Iron": ("steel", "PR Iron", (92, 70, 58), 0.5), "Steel": ("steel", "PR Iron", (200, 200, 196), 0.5),
    "Void": (None, None, (10, 12, 11), 1.0),
    "Dial": (None, None, (226, 220, 204), 1.0),   # pump gauge face: plain SmoothPlastic, not a tile surface
}
NEON = {"LightWarm": (255, 236, 200), "GateRed": (255, 60, 50)}   # Roblox Neon, no maps


def linear(x):
    x /= 255
    return x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4


def material(name):
    if name in MATERIALS:
        return name
    m = bpy.data.materials.new("PR_" + name)
    m.use_nodes = True
    nt, b = m.node_tree, m.node_tree.nodes["Principled BSDF"]
    if name in NEON:
        rgb = NEON[name]
        b.inputs["Base Color"].default_value = (*map(linear, rgb), 1)
        b.inputs["Emission Color"].default_value = (*map(linear, rgb), 1)
        b.inputs["Emission Strength"].default_value = 6
        MATERIALS[name] = {"blender": m, "robloxMaterial": "Neon", "variant": None, "color": list(rgb), "tile_m": 1}
        return name
    if name in RETIRED:
        raise KeyError(f"material {name!r} is retired (FIX_SPEC G1): use 'Tile' or 'Aqua'")
    pbr, variant, rgb, tile_m = PALETTE[name]
    tint = nt.nodes.new("ShaderNodeMix")
    tint.data_type, tint.blend_type = "RGBA", "MULTIPLY"
    tint.inputs["Factor"].default_value = 1
    tint.inputs["B"].default_value = (*map(linear, rgb), 1)
    nt.links.new(tint.outputs["Result"], b.inputs["Base Color"])
    tint.inputs["A"].default_value = (1, 1, 1, 1)
    folder = STEEL if pbr == "steel" else PBR_DIR
    for kind in ("albedo", "rough", "normal", "metal") if pbr else ():
        path = folder / f"{pbr}_{kind}.png"
        if not path.exists():
            continue
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(path), check_existing=True)
        if kind != "albedo":
            tex.image.colorspace_settings.name = "Non-Color"
        if kind == "albedo":
            nt.links.new(tex.outputs["Color"], tint.inputs["A"])
        elif kind == "normal":
            n = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex.outputs["Color"], n.inputs["Color"])
            nt.links.new(n.outputs["Normal"], b.inputs["Normal"])
        else:
            nt.links.new(tex.outputs["Color"], b.inputs["Roughness" if kind == "rough" else "Metallic"])
    MATERIALS[name] = {"blender": m, "robloxMaterial": "SmoothPlastic", "variant": variant, "color": list(rgb),
                       "tile_m": tile_m, "pbr": pbr}
    if variant in ("PR Tile", "PR Tile Aqua"):
        MATERIALS[name]["reflectance"] = TILE_REFLECTANCE
    return name


def to_blender(p):
    """Roblox studs (x, y, z) -> Blender metres."""
    return Vector((p[0] * S, -p[2] * S, p[1] * S))


class Yaw(float):
    """Degrees produced by yaw_x_along/yaw_x_radial: oblique yaws are only accepted in this form (see _yaw)."""


def yaw_x_along(dx, dz):
    """Yaw in degrees for a cf record whose local +X runs along the Roblox-space direction (dx, dz).

    Roblox convention: CFrame.Angles(0, t, 0) maps local X to (cos t, 0, -sin t), so (x, z) = (cos t, -sin t) and
    t = atan2(-dz, dx). import_kit's cf() and the offline harness both use CFrame.new(x,y,z)*CFrame.Angles(0,rad(yaw),0).
    The old atan2(dz, dx) mirrored every oblique collider across X (ANALYSIS F12-A)."""
    return Yaw(math.degrees(math.atan2(-dz, dx)))


def yaw_x_radial(angle):
    """Yaw in degrees whose local +X points radially outward at polar `angle` (radians), where the radial direction
    is (x, z) = (cos angle, sin angle) in Roblox axes. Same convention as yaw_x_along: yaw = -degrees(angle)."""
    return Yaw(-math.degrees(angle))


def _yaw(yaw, label):
    """A raw numeric yaw must be a multiple of 90 degrees; anything oblique must come from yaw_x_along/yaw_x_radial
    or be given as a full frame=, so the sign convention cannot be re-derived wrongly at a call site."""
    if isinstance(yaw, Yaw):
        return float(yaw)
    assert abs(yaw / 90 - round(yaw / 90)) < 1e-9, \
        f"{label}: oblique raw yaw {yaw}; use kit.yaw_x_along/yaw_x_radial or frame=(right, up, back)"
    return yaw


def _rotation(frame):
    """frame=(right, up, back) Roblox-space unit vectors, or a 3x3 rotation (numpy array / mathutils Matrix) whose
    COLUMNS are right, up, back. Returns the 3x3 Roblox rotation matrix R (columns right, up, back)."""
    if isinstance(frame, (np.ndarray, Matrix)):
        R = np.array(frame, float).reshape(3, 3)
    else:
        R = np.array(frame, float).reshape(3, 3).T
    assert np.allclose(R.T @ R, np.eye(3), atol=1e-4) and np.linalg.det(R) > 0, \
        f"frame is not a right-handed orthonormal basis: {R.T.tolist()}"
    return R


def frame_cf(position, frame):
    """12-number cf as Roblox CFrame.new(x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22) expects (row-major R,
    columns right/up/back); import_kit's cf() and the offline harness's recordCF() read it identically."""
    return [*map(float, position), *map(float, _rotation(frame).reshape(-1))]


def blender_rotation(frame):
    """The Blender-axis 4x4 rotation that previews a Roblox-axis frame (C maps Blender to Roblox: Rb = C^T R C)."""
    return Matrix((C.T @ _rotation(frame) @ C).tolist()).to_4x4()


def box_uv(co, normal):
    """World-aligned box projection in metres (Blender axes); finish() divides by the material's tile_m."""
    axis = max(range(3), key=lambda i: abs(normal[i]))
    return (co[1], co[2]) if axis == 0 else ((co[0], co[2]) if axis == 1 else (co[0], co[1]))


class Mesh:
    """A kit component. Geometry arguments are Roblox studs; `uv` may override box projection with a function
    (co_metres, normal) -> (u, v) in metres, divided by the material's tile_m here.

    `facing` (absorb/raw/box/cylinder, FIX_SPEC G2): a callable (x, y, z) Roblox studs -> Roblox-space direction of
    the VISIBLE side at that point. finish() flips every hinted face whose normal disagrees, so open shells (tunnel
    barrels, coves, chamber corners) shade from the side the player sees. raw(vertex_uv=[(u, v), ...]) gives per-vertex
    UVs in metres (divided by tile_m like the callback), for surfaces whose UV must not be re-derived from Blender
    coordinates (arc shells, chamber corners). finish() marks every edge whose face angle exceeds SHARP_DEG sharp."""

    SHARP_DEG = 45   # above every intended smooth step (coves 15, 16-segment columns 22.5); 8-gons would facet

    def __init__(self, name, **attrs):
        self.name, self.attrs = name, attrs
        self.bm, self.mats, self.uvf = bmesh.new(), [], []   # uvf: (face, uv callback) pairs; objectives.py edits them
        self.hints = {}              # face -> (facing callable or None, {vert: (u, v) metres} or None)
        self.parts, self.colliders, self.markers = [], [], []
        self.preview = None          # Part records drawn for renders only; never exported as mesh chunks

    def absorb(self, tmp, mat, uv=None, smooth=False, facing=None, vert_uv=None):
        """vert_uv: optional {tmp BMVert: (u, v) metres}; faces then take those UVs instead of `uv`."""
        material(mat)
        if mat not in self.mats:
            self.mats.append(mat)
        idx, mapping = self.mats.index(mat), {}
        bmesh.ops.scale(tmp, vec=Vector((S, S, S)), verts=list(tmp.verts))   # input built in Blender-axis studs
        for v in tmp.verts:
            mapping[v] = self.bm.verts.new(v.co)
        vuv = {mapping[v]: tuple(t) for v, t in vert_uv.items()} if vert_uv is not None else None
        for face in tmp.faces:
            f = self.bm.faces.new([mapping[v] for v in face.verts])
            f.material_index, f.smooth = idx, smooth
            self.uvf.append((f, uv))
            if facing is not None or vuv is not None:
                self.hints[f] = (facing, vuv)
        tmp.free()
        return self

    @staticmethod
    def _xf(bm, center, rotation):
        if rotation is not None:
            bmesh.ops.transform(bm, matrix=rotation, verts=list(bm.verts))
        c = to_blender(center) / S
        bmesh.ops.translate(bm, vec=c, verts=list(bm.verts))

    def box(self, center, size, mat, bevel=.06, rotation=None, uv=None, facing=None):
        """size (x, y, z) in studs, Roblox axes; rotation is a Blender-axis Matrix (e.g. yaw about Z)."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=Vector((size[0], size[2], size[1])), verts=list(bm.verts))
        if bevel:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * .3), segments=2, affect="EDGES")
        self._xf(bm, center, rotation)
        return self.absorb(bm, mat, uv, facing=facing)

    def cylinder(self, center, radius, height, mat, segments=16, axis="Y", radius2=None, uv=None, caps=True, smooth=True,
                 facing=None):
        """axis in Roblox terms: 'Y' vertical, 'X' or 'Z' horizontal."""
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segments, radius1=radius,
                              radius2=radius if radius2 is None else radius2, depth=height)
        if axis == "X":
            bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=list(bm.verts))
        elif axis == "Z":
            bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=list(bm.verts))
        self._xf(bm, center, None)
        return self.absorb(bm, mat, uv, smooth, facing=facing)

    def raw(self, verts, faces, mat, uv=None, smooth=False, facing=None, vertex_uv=None):
        """verts: Roblox-stud tuples; faces: index tuples. For lofted/curved pieces (vaults, arches, coping).
        vertex_uv: one (u, v) in METRES per vertex (same order as verts); overrides `uv` for these faces."""
        bm = bmesh.new()
        vs = [bm.verts.new(to_blender(v) / S) for v in verts]
        for f in faces:
            bm.faces.new([vs[i] for i in f])
        if vertex_uv is not None:
            assert len(vertex_uv) == len(verts), (self.name, "vertex_uv needs one (u, v) per vertex")
            vertex_uv = dict(zip(vs, vertex_uv))
        return self.absorb(bm, mat, uv, smooth, facing=facing, vert_uv=vertex_uv)

    # Records for things that are NOT mesh chunks. All in Roblox studs/axes, relative to the component pivot.
    # cf is [x, y, z, yawDegrees] (CFrame.new(x,y,z)*CFrame.Angles(0,rad(yaw),0)) or, with frame=(right, up, back),
    # the 12-number row-major CFrame (frame_cf). A raw yaw must be a multiple of 90 (see _yaw).
    def _cf(self, name, center, yaw, frame):
        return frame_cf(center, frame) if frame is not None else [*center, _yaw(yaw, f"{self.name}.{name}")]

    def part(self, name, center, size, mat, collide=True, ground=False, attrs=None, yaw=0, show=True, frame=None):
        """A Roblox Part with a MaterialVariant (shells: walls, floors, decks). Also drawn in Blender for renders."""
        material(mat)
        rec = {"name": name, "cf": self._cf(name, center, yaw, frame), "size": list(size), "material": mat,
               "collide": collide, "ground": ground, "attrs": attrs or {}}
        self.parts.append(rec)
        if show:
            self.preview = self.preview or Mesh(self.name + "__parts")
            rotation = (blender_rotation(frame) if frame is not None else
                        Matrix.Rotation(math.radians(yaw), 4, "Z") if yaw else None)
            self.preview.box(center, size, mat, bevel=0, rotation=rotation)
        return self

    def collider(self, name, center, size, ground=False, yaw=0, shape="Block", attrs=None, frame=None):
        self.colliders.append({"name": name, "cf": self._cf(name, center, yaw, frame), "size": list(size),
                               "ground": ground, "shape": shape, "attrs": attrs or {}})
        return self

    def marker(self, name, position, yaw=0, frame=None, **attrs):
        self.markers.append({"name": name, "cf": self._cf(name, position, yaw, frame), "attrs": attrs})
        return self

    def finish(self, register=True):
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        self.bm.normal_update()
        # G2: the visible side wins over recalc's guess on open shells. Roblox (x,y,z) = Blender (x, z, -y) in studs.
        for f, (facing, _vuv) in self.hints.items():
            if facing is None or not f.is_valid:
                continue
            c = f.calc_center_median() / S
            w = facing((c.x, c.z, -c.y))
            if f.normal.dot(Vector((w[0], -w[2], w[1]))) < 0:
                f.normal_flip()
        self.bm.normal_update()
        sharp = math.radians(self.SHARP_DEG)
        for e in self.bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0) > sharp:
                e.smooth = False      # export() reads mesh.corner_normals, which splits at sharp edges
        self.bm.normal_update()
        layer = self.bm.loops.layers.uv.new("UVMap")
        for f, uvfn in self.uvf:
            if not f.is_valid:
                continue
            vuv = self.hints.get(f, (None, None))[1]
            tile = MATERIALS[self.mats[f.material_index]]["tile_m"]
            for loop in f.loops:
                u, v = vuv[loop.vert] if vuv is not None else (uvfn or box_uv)(loop.vert.co, f.normal)
                loop[layer].uv = (u / tile, v / tile)
        mesh = bpy.data.meshes.new("PR_" + self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for key in self.mats:
            mesh.materials.append(MATERIALS[key]["blender"])
        if not register:
            return mesh
        COMPONENTS[self.name] = {"mesh": mesh, "attrs": self.attrs, "parts": self.parts, "colliders": self.colliders,
                                 "markers": self.markers, "chunks": [],
                                 "preview": self.preview.finish(register=False) if self.preview else None}
        return self


def atlas_material(name, maps, tile_m=1.0):
    """A Meshy prop atlas: one Blender material + a manifest entry routed to SurfaceAppearance (not a variant).
    maps = {"albedo": path, "normal": path, "rough": path, "metal": path?} (1024 or 512 px, already resampled)."""
    m = bpy.data.materials.new("PR_" + name)
    m.use_nodes = True
    nt, b = m.node_tree, m.node_tree.nodes["Principled BSDF"]
    for kind, path in maps.items():
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(path), check_existing=True)
        if kind != "albedo":
            tex.image.colorspace_settings.name = "Non-Color"
        if kind == "normal":
            n = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex.outputs["Color"], n.inputs["Color"])
            nt.links.new(n.outputs["Normal"], b.inputs["Normal"])
        else:
            nt.links.new(tex.outputs["Color"], b.inputs[{"albedo": "Base Color", "rough": "Roughness", "metal": "Metallic"}[kind]])
    MATERIALS[name] = {"blender": m, "robloxMaterial": "SmoothPlastic", "variant": None, "color": [255, 255, 255],
                       "tile_m": tile_m, "atlas": {k: str(v) for k, v in maps.items()}}
    return name


def register_mesh(name, mesh, colliders=(), markers=(), **attrs):
    """Register a ready Blender mesh (metres, Blender axes, its own UVs kept) as a component, e.g. a Meshy prop."""
    COMPONENTS[name] = {"mesh": mesh, "attrs": attrs, "parts": [], "colliders": list(colliders),
                        "markers": list(markers), "chunks": []}
    return name


def place(collection, component, position=(0, 0, 0), yaw=0):
    """Instance a finished component (mesh + its Part preview) into a review collection at Roblox studs / yaw."""
    info = COMPONENTS[component]
    M = Matrix.Rotation(math.radians(yaw), 4, "Z")
    M.translation = to_blender(position)
    ob = None
    for mesh in (info["mesh"], info.get("preview")):
        if mesh is None:
            continue
        o = bpy.data.objects.new(component, mesh)
        collection.objects.link(o)
        o.matrix_world = M
        o["l2k_component"] = component
        ob = ob or o
    return ob


def export():
    """Chunk wire files (Level 1/4 format) + manifest.json for the importer."""
    (EXPORT_DIR / "chunks").mkdir(parents=True, exist_ok=True)
    chunks = []
    for info in COMPONENTS.values():
        info["chunks"] = []                     # export() may run more than once per session
    for name, info in COMPONENTS.items():
        mesh = info["mesh"]
        mesh.calc_loop_triangles()
        uvl = mesh.uv_layers.active.data
        for idx, mat in enumerate(mesh.materials):
            ts = [t for t in mesh.loop_triangles if t.material_index == idx]
            if not ts:
                continue
            p = np.array([[mesh.vertices[v].co[:] for v in t.vertices] for t in ts], float) @ C.T / S
            n = np.array([[mesh.corner_normals[l].vector[:] for l in t.loops] for t in ts], float) @ C.T
            u = np.array([[uvl[l].uv[:] for l in t.loops] for t in ts], float)
            u[:, :, 1] = 1 - u[:, :, 1]
            lo, hi = p.reshape(-1, 3).min(0), p.reshape(-1, 3).max(0)
            center = (lo + hi) / 2
            pv, pi = np.unique(np.round(p.reshape(-1, 3) - center, 5), axis=0, return_inverse=True)
            nv, ni = np.unique(np.round(n.reshape(-1, 3), 4), axis=0, return_inverse=True)
            uv, ui = np.unique(np.round(u.reshape(-1, 2), 5), axis=0, return_inverse=True)
            assert len(ts) <= 20000 and len(pv) <= 60000 and (hi - lo).max() <= 1800, name
            f = np.stack([pi.reshape(-1, 3), ni.reshape(-1, 3), ui.reshape(-1, 3)], axis=2).reshape(-1, 9)
            blob = np.array([len(pv), len(nv), len(uv), len(ts)], dtype="<u4").tobytes()
            blob += pv.astype("<f4").tobytes() + nv.astype("<f4").tobytes() + uv.astype("<f4").tobytes() + f.astype("<u4").tobytes()
            wire = base64.b64encode(blob).decode()
            cid = len(chunks)
            (EXPORT_DIR / "chunks" / ("c%05d.b64" % cid)).write_text(wire, encoding="ascii")
            key = mat.name.removeprefix("PR_")
            chunks.append({"id": cid, "component": name, "material": key, "tris": len(ts), "verts": len(pv),
                           "center": np.round(center, 5).tolist(), "size": np.maximum(hi - lo, .01).round(5).tolist(),
                           "sha256": hashlib.sha256(blob).hexdigest(), "wireSha256": hashlib.sha256(wire.encode()).hexdigest()})
            info["chunks"].append(cid)
    manifest = {"version": 1, "build": "level2-poolrooms", "scaleMetresPerStud": S, "axis": "Blender(x,y,z) -> Roblox(x,z,-y)",
                "materials": {k: {x: y for x, y in v.items() if x != "blender"} for k, v in MATERIALS.items()},
                "components": {k: {x: y for x, y in v.items() if x not in ("mesh", "preview")} for k, v in COMPONENTS.items()},
                "chunks": chunks}
    (EXPORT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    print("PR_EXPORT=" + json.dumps({"components": len(COMPONENTS), "chunks": len(chunks),
                                     "tris": sum(c["tris"] for c in chunks)}), flush=True)
    return manifest
