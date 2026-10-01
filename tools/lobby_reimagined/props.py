"""Blender-authored prop kit for the separate revised lobby preview.

``library = build_library(collection)`` creates one mesh per asset at (0,0,0).
All dimensions are Roblox studs; +Z is up and -Y is the front. Origins are
grounded at the floor. The caller owns placement, collision, export and lights.
No operator, addon, external download, scene reset or current-scene save is used.

Each returned record contains ``collection``, ``objects`` (one mesh),
``triangles``, ``bounds_xyz`` and JSON-safe ``metadata``. Material slots use
stable keys from PALETTE. UVs address a deterministic 8x8 palette atlas; call
``create_palette_atlas(path)`` and ``use_palette_atlas(library, image)`` for a
single opaque texture/material per imported mesh. The supplied material slots
remain useful in the authoring file until that explicit export-copy step.
"""

from __future__ import annotations

import math
from collections import OrderedDict
from pathlib import Path

import bpy
from mathutils import Euler, Vector


PALETTE = OrderedDict([
    ('steel_black', (.032, .038, .035, 1)),
    ('steel_edge', (.11, .125, .115, 1)),
    ('steel_grey', (.29, .305, .27, 1)),
    ('chrome_dull', (.42, .45, .43, 1)),
    ('rust', (.21, .105, .035, 1)),
    ('wood_edge', (.22, .115, .045, 1)),
    ('wood_laminate', (.43, .29, .14, 1)),
    ('laminate_worn', (.58, .48, .29, 1)),
    ('cabinet_olive', (.32, .335, .22, 1)),
    ('cabinet_light', (.42, .43, .30, 1)),
    ('plastic_beige', (.58, .54, .40, 1)),
    ('plastic_edge', (.41, .395, .29, 1)),
    ('plastic_ivory', (.73, .70, .58, 1)),
    ('rubber', (.021, .023, .021, 1)),
    ('screen_dark', (.012, .024, .026, 1)),
    ('screen_cold', (.042, .11, .095, 1)),
    ('vinyl_olive', (.115, .15, .10, 1)),
    ('vinyl_brown', (.19, .105, .064, 1)),
    ('fabric_olive', (.23, .22, .105, 1)),
    ('fabric_flower', (.46, .395, .17, 1)),
    ('fabric_shadow', (.125, .145, .065, 1)),
    ('paper', (.69, .675, .535, 1)),
    ('cardboard', (.39, .29, .165, 1)),
    ('carpet_roll', (.34, .30, .205, 1)),
    ('led_cyan', (.085, .57, .59, 1)),
    ('led_amber', (.62, .295, .035, 1)),
    ('led_green', (.17, .41, .07, 1)),
    ('label_dark', (.055, .065, .055, 1)),
    ('grille', (.052, .059, .057, 1)),
    ('cone', (.075, .078, .069, 1)),
    ('flightcase', (.049, .055, .051, 1)),
    ('tape', (.37, .35, .245, 1)),
    ('record_label_amber', (.54, .24, .045, 1)),
    ('record_label_cyan', (.055, .36, .39, 1)),
])


def material(key):
    """Create only our namespaced material; supplied scene materials are untouched."""
    name = 'LRP_' + key
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    color = PALETTE[key]
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = .66
    if key.startswith('steel') or key == 'chrome_dull':
        bsdf.inputs['Metallic'].default_value = .50
        bsdf.inputs['Roughness'].default_value = .43
    elif key.startswith('vinyl'):
        bsdf.inputs['Roughness'].default_value = .38
    elif key in {'screen_dark', 'screen_cold'}:
        bsdf.inputs['Roughness'].default_value = .21
    if key.startswith('led_'):
        # Authoring-only emission. Roblox fills are created by the caller.
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = color
            bsdf.inputs['Emission Strength'].default_value = .45
    mat['lobby_prop_palette_key'] = key
    return mat


class Geometry:
    """Small append-only geometry builder; all primitives have outward faces."""

    def __init__(self):
        self.vertices = []
        self.faces = []
        self.materials = []
        self.smooth = []

    def mesh(self, key, vertices, faces, smooth=False):
        if key not in PALETTE:
            raise KeyError(key)
        offset = len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.faces.extend(tuple(offset + i for i in face) for face in faces)
        self.materials.extend([key] * len(faces))
        self.smooth.extend([smooth] * len(faces))

    def box(self, key, pos, size, bevel=0, rotation=(0, 0, 0)):
        if min(size) <= 0:
            raise ValueError('Box dimensions must be positive')
        x, y, z = size
        if not bevel:
            verts = [(a*x/2, b*y/2, c*z/2) for c in (-1, 1)
                     for b in (-1, 1) for a in (-1, 1)]
            faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                     (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        else:
            b = min(bevel, min(size)*.42)
            foot = [(x/2-b, -y/2), (x/2, -y/2+b), (x/2, y/2-b),
                    (x/2-b, y/2), (-x/2+b, y/2), (-x/2, y/2-b),
                    (-x/2, -y/2+b), (-x/2+b, -y/2)]
            verts = []
            for height, inset in [(-z/2, b*.5), (-z/2+b, 0),
                                   (z/2-b, 0), (z/2, b*.5)]:
                for px, py in foot:
                    verts.append((px-math.copysign(inset, px),
                                  py-math.copysign(inset, py), height))
            faces = [tuple(reversed(range(8))), tuple(range(24, 32))]
            for ring in range(3):
                for i in range(8):
                    faces.append((ring*8+i, ring*8+(i+1)%8,
                                  (ring+1)*8+(i+1)%8, (ring+1)*8+i))
        rot = Euler(rotation, 'XYZ').to_matrix()
        self.mesh(key, [Vector(pos) + rot @ Vector(v) for v in verts], faces)

    def rod(self, key, start, end, radius=.06, sides=8, top=None):
        start, end = Vector(start), Vector(end)
        delta = end - start
        if delta.length < 1e-6:
            raise ValueError('Zero-length rod')
        rot = Vector((0, 0, 1)).rotation_difference(delta.normalized())
        mid = (start + end)*.5
        verts = []
        for z, rad in [(-delta.length/2, radius),
                       (delta.length/2, radius if top is None else top)]:
            for i in range(sides):
                a = i*math.tau/sides
                verts.append(mid + rot @ Vector((math.cos(a)*rad,
                                                math.sin(a)*rad, z)))
        faces = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
        faces.extend((i, (i+1)%sides, (i+1)%sides+sides, i+sides)
                     for i in range(sides))
        self.mesh(key, verts, faces, True)

    def disc(self, key, center, radius, depth, axis=(0, 0, 1), sides=24):
        v = Vector(axis).normalized()*depth*.5
        self.rod(key, Vector(center)-v, Vector(center)+v, radius, sides)

    def ring(self, key, pos, outer, inner, height=.04, sides=24,
             rotation=(0, 0, 0)):
        verts = []
        rot = Euler(rotation, 'XYZ').to_matrix()
        for z, r in [(-height/2, outer), (-height/2, inner),
                     (height/2, outer), (height/2, inner)]:
            for i in range(sides):
                a = i*math.tau/sides
                verts.append(Vector(pos) + rot @ Vector((math.cos(a)*r,
                                                        math.sin(a)*r, z)))
        faces = []
        for i in range(sides):
            j = (i+1)%sides
            faces.extend([(i, j, j+sides*2, i+sides*2),
                          (i+sides, i+sides*3, j+sides*3, j+sides),
                          (i+sides*2, j+sides*2, j+sides*3, i+sides*3),
                          (i, i+sides, j+sides, j)])
        self.mesh(key, verts, faces)

    def polyline(self, key, points, radius=.035, sides=6):
        for a, b in zip(points, points[1:]):
            self.rod(key, a, b, radius, sides)

    def merge(self, other, pos=(0, 0, 0), rotation=(0, 0, 0)):
        rot = Euler(rotation, 'XYZ').to_matrix()
        offset = len(self.vertices)
        self.vertices.extend(tuple(Vector(pos) + rot @ Vector(v))
                             for v in other.vertices)
        self.faces.extend(tuple(offset+i for i in f) for f in other.faces)
        self.materials.extend(other.materials)
        self.smooth.extend(other.smooth)


def _feet(g, width, depth, height=.44, key='wood_edge'):
    for x in (-width/2+.4, width/2-.4):
        for y in (-depth/2+.35, depth/2-.35):
            g.box(key, (x, y, height*.5), (.22, .22, height), .025)


def _rosette(g, key, center, u=(1, 0, 0), v=(0, 0, 1), scale=.13):
    """A flat four-petal damask motif; silhouette detail without fabric tessellation."""
    c, u, v = Vector(center), Vector(u), Vector(v)
    for a in (0, math.pi/2, math.pi, math.pi*1.5):
        along = u*math.cos(a) + v*math.sin(a)
        across = -u*math.sin(a) + v*math.cos(a)
        vertices = [c+along*scale*.25,
                    c+along*scale*.9+across*scale*.45,
                    c+along*scale*1.55,
                    c+along*scale*.9-across*scale*.45]
        # Orient the front consistently towards u cross v.
        g.mesh(key, vertices, [(3, 2, 1, 0)])


def floral_sofa():
    g = Geometry()
    _feet(g, 7.4, 3.25)
    g.box('fabric_shadow', (0, .08, .96), (7.6, 3.2, 1.05), .13)
    g.box('fabric_olive', (0, 1.28, 2.46), (7.2, .58, 2.42), .15)
    for x in (-3.38, 3.38):
        g.box('fabric_olive', (x, .02, 1.96), (.84, 3.28, 2.35), .24)
        g.box('fabric_flower', (x, -.02, 3.045), (.57, 2.76, .024), .01)
    for x in (-2.06, 0, 2.06):
        g.box('fabric_olive', (x, -.37, 1.89), (2.02, 2.32, .58), .16)
        g.box('fabric_olive', (x, .84, 2.73), (2.02, .38, 1.58), .12)
        # Back and seat flower rows stay on the broad flat regions.
        for xx in (-.65, 0, .65):
            for zz in (2.26, 2.76, 3.18):
                _rosette(g, 'fabric_flower', (x+xx, .646, zz), scale=.14)
            for yy in (-1.0, -.4, .2):
                _rosette(g, 'fabric_flower', (x+xx, yy, 2.185),
                         v=(0, 1, 0), scale=.13)
        g.box('fabric_shadow', (x, -1.535, 1.845), (1.74, .012, .03))
    # Front piping catches the tunnel fill lights without a heavy subdivision.
    g.rod('fabric_flower', (-2.94, -1.515, 1.68), (2.94, -1.515, 1.68), .025)
    return g


def vinyl_bench():
    g = Geometry()
    for x in (-2.5, 2.5):
        for y in (-.8, .78):
            g.rod('chrome_dull', (x, y, .07), (x, y, 2.0), .085)
            g.box('rubber', (x, y, .035), (.22, .22, .07), .015)
    g.box('steel_black', (0, 0, 1.53), (5.6, 1.72, .20), .025)
    for x in (-1.87, 0, 1.87):
        g.box('vinyl_olive', (x, -.05, 1.90), (1.83, 2.12, .58), .14)
        g.box('vinyl_olive', (x, .86, 2.80), (1.83, .40, 1.78), .12)
        g.box('vinyl_brown', (x, .65, 2.35), (1.54, .012, .025))
    return g


def laminate_desk():
    g = Geometry()
    g.box('wood_edge', (0, 0, 3.03), (6.8, 3.0, .28), .055)
    g.box('laminate_worn', (0, 0, 3.175), (6.69, 2.89, .035), .015)
    g.box('wood_laminate', (0, 1.07, 1.82), (6.25, .15, 1.85), .02)
    for x in (-2.55, 2.55):
        g.box('wood_laminate', (x, .05, 1.58), (1.18, 2.52, 2.78), .035)
        for z in (.70, 1.59, 2.45):
            g.box('wood_laminate', (x, -1.23, z), (1.12, .13, .79), .02)
            g.rod('chrome_dull', (x-.18, -1.32, z+.12),
                  (x+.18, -1.32, z+.12), .025)
        g.box('steel_black', (x, .05, .09), (1.04, 2.28, .18), .02)
    g.box('label_dark', (-.45, -.03, 3.196), (1.14, .69, .009))
    g.box('tape', (-.8, -.28, 3.205), (.27, .09, .008))
    return g


def filing_cabinet():
    g = Geometry()
    g.box('cabinet_olive', (0, 0, 2.49), (2.48, 2.61, 4.98), .055)
    g.box('steel_black', (0, -.04, .10), (2.3, 2.42, .20), .02)
    for z in (.75, 1.93, 3.11, 4.29):
        g.box('steel_edge', (0, -1.314, z), (2.22, .015, 1.095))
        g.box('cabinet_light', (0, -1.338, z), (2.10, .074, 1.02), .04)
        for x in (-.29, .29):
            g.rod('chrome_dull', (x, -1.4, z+.08), (x, -1.49, z+.08), .035)
        g.rod('chrome_dull', (-.29, -1.49, z+.08), (.29, -1.49, z+.08), .035)
        g.box('chrome_dull', (0, -1.385, z+.34), (.65, .025, .24), .02)
        g.box('paper', (0, -1.403, z+.34), (.50, .009, .14))
        g.box('label_dark', (.52, -1.382, z-.33), (.19, .007, .019))
    return g


def crt_monitor():
    g = Geometry()
    g.box('plastic_edge', (0, .0, .145), (2.13, 1.43, .29), .10)
    g.box('plastic_beige', (0, .04, .375), (.75, .62, .22), .05)
    # Frustum housing: broad glass/bezel front with a deep, tapered CRT back.
    front = [(-1.30, -1.12, .62), (1.30, -1.12, .62),
             (1.30, -1.12, 2.64), (-1.30, -1.12, 2.64)]
    back = [(-.89, 1.0, .88), (.89, 1.0, .88),
            (.89, 1.0, 2.39), (-.89, 1.0, 2.39)]
    g.mesh('plastic_beige', front+back,
           [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
            (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)])
    g.box('plastic_edge', (0, -1.146, 1.66), (2.26, .055, 1.61), .12)
    # Convex glass has a coarse 8x6 grid; no transparency or reflections needed.
    verts = []
    nx, nz = 8, 6
    for iz in range(nz+1):
        z = (iz/nz-.5)*1.40
        for ix in range(nx+1):
            x = (ix/nx-.5)*1.97
            bulge = .10*(1-(x/1.05)**2)*(1-(z/.79)**2)
            verts.append((x, -1.18-bulge, 1.69+z))
    faces = []
    for iz in range(nz):
        for ix in range(nx):
            a = iz*(nx+1)+ix
            faces.append((a, a+1, a+nx+2, a+nx+1))
    g.mesh('screen_dark', verts, faces, True)
    g.box('plastic_beige', (0, -1.174, .775), (2.27, .065, .22), .03)
    for x in (.55, .76, .98):
        g.disc('plastic_edge', (x, -1.218, .80), .045, .025, (0, -1, 0), 10)
    g.box('led_green', (.32, -1.212, .8), (.054, .017, .027))
    for z in (1.05, 1.20, 1.35, 1.50, 1.65, 1.80, 1.95, 2.1):
        g.box('plastic_edge', (0, 1.008, z), (1.44, .019, .035))
    return g


def copier():
    g = Geometry()
    for x in (-1.55, 1.55):
        for y in (-1.05, 1.05):
            g.disc('rubber', (x, y, .18), .18, .13, (1, 0, 0), 10)
    g.box('plastic_edge', (0, 0, .50), (3.65, 2.81, .65), .065)
    g.box('plastic_beige', (0, 0, 1.60), (3.74, 2.88, 1.60), .08)
    for z in (1.04, 1.69, 2.15):
        g.box('plastic_ivory', (0, -1.47, z), (3.51, .09, .44), .025)
        g.box('label_dark', (0, -1.523, z+.025), (.64, .012, .07), .01)
    g.box('plastic_edge', (0, .02, 2.46), (3.93, 3.09, .22), .07)
    g.box('plastic_ivory', (-.33, .18, 2.71), (3.12, 2.48, .31), .065)
    g.box('plastic_edge', (-.32, .27, 2.90), (2.88, 2.24, .12), .055)
    g.box('plastic_beige', (-.41, .36, 3.11), (2.54, 1.66, .30), .09)
    g.box('paper', (-.42, .01, 3.272), (1.52, .90, .025))
    # Sloped control panel, deliberately few raised buttons.
    tilt = (math.radians(13), 0, 0)
    g.box('plastic_ivory', (1.26, -.85, 2.75), (.74, .90, .15), .03, tilt)
    g.box('screen_cold', (1.24, -.62, 2.849), (.51, .22, .012), .01, tilt)
    for x in (1.10, 1.28, 1.46):
        for y in (-1.06, -.88):
            g.box('plastic_edge', (x, y, 2.83+(y+.85)*.23), (.12, .10, .04), .01, tilt)
    g.disc('led_green', (1.52, -.75, 2.87), .08, .023, sides=12)
    g.box('plastic_edge', (-2.14, -.02, 2.21), (.69, 2.01, .09), .025)
    g.box('plastic_beige', (-2.41, .02, 2.43), (.11, 1.92, .52), .03)
    return g


def office_chair():
    g = Geometry()
    for a in range(5):
        angle = a*math.tau/5
        x, y = math.cos(angle)*1.12, math.sin(angle)*1.12
        g.rod('steel_black', (0, 0, .48), (x, y, .30), .075)
        g.disc('rubber', (x, y, .18), .18, .14,
               (-math.sin(angle), math.cos(angle), 0), 10)
    g.rod('chrome_dull', (0, 0, .34), (0, 0, 1.73), .15, 12)
    g.box('steel_black', (0, 0, 1.71), (1.85, 1.61, .16), .04)
    g.box('vinyl_brown', (0, -.08, 1.97), (2.31, 2.04, .43), .16)
    g.rod('steel_black', (0, .74, 1.80), (0, 1.0, 3.33), .09)
    g.box('vinyl_brown', (0, .98, 3.17), (2.05, .46, 1.72), .16,
          (math.radians(-5), 0, 0))
    for x in (-1.12, 1.12):
        g.rod('steel_black', (x*.88, .68, 1.84), (x, .43, 2.63), .065)
        g.box('vinyl_brown', (x, .0, 2.68), (.26, 1.38, .17), .06)
    return g


def stack_chair():
    g = Geometry()
    for x in (-.89, .89):
        for y in (-.82, .70):
            g.rod('chrome_dull', (x*1.08, y*1.17, .09), (x, y, 1.89), .061)
            g.box('rubber', (x*1.08, y*1.17, .045), (.15, .15, .09), .02)
        g.rod('chrome_dull', (x, .70, 1.77), (x, 1.01, 3.40), .061)
        g.rod('chrome_dull', (x, -.72, 1.56), (x, .75, 1.56), .045)
    g.box('vinyl_brown', (0, -.02, 1.96), (2.06, 1.92, .24), .11)
    g.box('vinyl_brown', (0, .96, 2.95), (1.98, .24, 1.14), .11,
          (math.radians(-9), 0, 0))
    return g


def wire_trolley():
    g = Geometry()
    width, depth = 3.72, 2.62
    for x in (-width*.44, width*.44):
        for y in (-depth*.43, depth*.43):
            g.disc('rubber', (x, y, .20), .20, .18, (1, 0, 0), 10)
            g.rod('chrome_dull', (x, y, .25), (x, y, .48), .06)
    for z in (.45, 3.65):
        g.polyline('chrome_dull', [(-width/2, -depth/2, z),
                   (width/2, -depth/2, z), (width/2, depth/2, z),
                   (-width/2, depth/2, z), (-width/2, -depth/2, z)], .048)
    for x in (-width/2, width/2):
        for y in (-depth/2, depth/2):
            g.rod('chrome_dull', (x, y, .45), (x, y, 3.65), .055)
    for i in range(1, 8):
        x = -width/2+i*width/8
        g.rod('steel_grey', (x, depth/2, .50), (x, depth/2, 3.61), .025, 6)
        # Front opening remains visually distinct from the rear wire cage.
        g.rod('steel_grey', (x, -depth/2, .50), (x, -depth/2, 2.63), .025, 6)
        g.rod('steel_grey', (x, -depth/2, .48), (x, depth/2, .48), .025, 6)
    for i in range(1, 6):
        y = -depth/2+i*depth/6
        for x in (-width/2, width/2):
            g.rod('steel_grey', (x, y, .5), (x, y, 3.61), .025, 6)
    for z in (.95, 1.55, 2.15, 2.65, 3.15):
        g.polyline('steel_grey', [(-width/2, -depth/2, z),
                   (-width/2, depth/2, z), (width/2, depth/2, z),
                   (width/2, -depth/2, z)], .025, 6)
        if z <= 2.65:
            g.rod('steel_grey', (-width/2, -depth/2, z),
                  (width/2, -depth/2, z), .025, 6)
    g.polyline('chrome_dull', [(-width/2, depth/2, 3.56),
               (-width/2, depth/2+.55, 3.80),
               (width/2, depth/2+.55, 3.80),
               (width/2, depth/2, 3.56)], .065)
    g.box('cardboard', (-.43, .23, 1.10), (1.57, 1.70, 1.17), .025)
    g.box('tape', (-.43, .23, 1.698), (.14, 1.72, .012))
    return g


def carpet_roll():
    g = Geometry()
    g.rod('carpet_roll', (-2.2, 0, .68), (2.2, 0, .68), .68, 24)
    for x in (-2.212, 2.212):
        g.disc('fabric_shadow', (x, 0, .68), .56, .012, (1, 0, 0), 24)
        # Sparse spiral makes the object read as a carpet roll rather than a pipe.
        pts = []
        for i in range(75):
            a = i/74*math.tau*3.0
            r = .12+i/74*.42
            pts.append((x+math.copysign(.011, x), math.cos(a)*r,
                        .68+math.sin(a)*r))
        g.polyline('carpet_roll', pts, .018, 4)
    g.box('tape', (0, -.004, 1.365), (.25, .65, .014))
    return g


def keyboard():
    g = Geometry()
    g.box('plastic_edge', (0, 0, .13), (2.90, 1.00, .26), .075)
    for y in (-.30, -.11, .08, .27):
        for x in range(13):
            g.box('plastic_beige', (-1.24+x*.188, y, .29), (.15, .143, .055), .016)
    g.box('plastic_beige', (-.18, -.34, .31), (.82, .135, .055), .017)
    return g


def _turntable():
    g = Geometry()
    g.box('steel_black', (0, 0, .16), (3.47, 3.34, .32), .075)
    g.box('steel_edge', (0, 0, .324), (3.36, 3.23, .018), .018)
    # Stationary support platter; separate VinylDisc assets sit at Z=.493.
    g.disc('steel_black', (-.16, -.08, .401), 1.41, .136, sides=48)
    g.ring('chrome_dull', (-.16, -.08, .477), 1.405, 1.355, .023, 48)
    for a in range(24):
        angle = a*math.tau/24
        g.box('chrome_dull', (-.16+math.cos(angle)*1.389,
              -.08+math.sin(angle)*1.389, .412), (.040, .049, .057), .005,
              (0, 0, angle))
    # Clearly readable offset pickup, pivot, counterweight, headshell and needle.
    g.disc('steel_black', (1.30, .94, .395), .20, .13, sides=16)
    g.disc('chrome_dull', (1.30, .94, .493), .14, .067, sides=16)
    g.rod('chrome_dull', (1.30, .94, .525), (1.30, .94, .81), .065, 12)
    g.rod('chrome_dull', (1.30, 1.29, .77), (1.30, .94, .77), .043)
    g.disc('steel_grey', (1.30, 1.25, .77), .125, .23, (0, 1, 0), 16)
    g.polyline('chrome_dull', [(1.30, .94, .77), (1.16, .52, .73),
               (.90, .08, .68), (.64, -.21, .625)], .037, 10)
    g.box('steel_black', (.595, -.27, .603), (.16, .29, .062), .02,
          (0, 0, -.58))
    g.box('plastic_ivory', (.573, -.295, .568), (.064, .086, .035), .01)
    g.rod('chrome_dull', (.572, -.298, .566), (.57, -.30, .551), .009, 6)
    g.rod('steel_edge', (1.12, .13, .349), (1.12, .13, .622), .023)
    g.box('steel_black', (1.12, .13, .63), (.13, .10, .023), .01)
    g.box('rubber', (1.51, -.58, .348), (.032, 1.14, .016))
    g.box('plastic_ivory', (1.51, -.60, .395), (.14, .078, .065), .018)
    g.box('steel_edge', (-1.35, -1.48, .36), (.29, .20, .055), .025)
    g.box('led_green', (-1.35, -1.48, .395), (.15, .055, .008))
    g.disc('steel_black', (-1.43, 1.39, .385), .072, .10, sides=12)
    g.box('led_amber', (-1.0, -1.51, .350), (.042, .034, .012))
    return g


def vinyl_disc(label='record_label_amber'):
    """Separate rotatable record. Origin is the record base; center axis is +Z."""
    g = Geometry()
    g.disc('rubber', (0, 0, .025), 1.345, .05, sides=64)
    # Sparse concentric highlights imply vinyl grooves without microgeometry.
    for r in (.57, .72, .88, 1.03, 1.19, 1.30):
        g.ring('steel_black', (0, 0, .051), r+.002, r-.002, .002, 48)
    g.disc(label, (0, 0, .053), .425, .006, sides=48)
    # Offset blocks reveal the slow rotation even though groove rings are radial.
    g.box('paper', (0, -.18, .058), (.30, .025, .003))
    g.box('label_dark', (-.045, -.245, .058), (.25, .012, .003))
    g.box('label_dark', (.095, .195, .058), (.14, .037, .003))
    g.disc('chrome_dull', (0, 0, .065), .027, .03, sides=12)
    return g


def _mixer():
    g = Geometry()
    g.box('steel_black', (0, 0, .16), (1.55, 2.67, .32), .052)
    g.box('steel_edge', (0, 0, .327), (1.47, 2.57, .016))
    for x in (-.49, -.17, .17, .49):
        for y in (.87, .61, .34, .08):
            g.disc('rubber', (x, y, .391), .066, .11, sides=10)
            g.box('plastic_ivory', (x, y-.025, .449), (.013, .049, .007))
        g.box('rubber', (x, -.52, .34), (.025, .79, .018))
        g.box('plastic_ivory', (x, -.61+x*.32, .394), (.17, .080, .069), .012)
    g.box('rubber', (0, -1.08, .341), (.89, .03, .016))
    g.box('steel_grey', (-.18, -1.08, .39), (.08, .16, .062), .015)
    for x in (-.69, .69):
        for i in range(7):
            g.box('led_green' if i < 5 else 'led_amber',
                  (x, .82-i*.10, .347), (.035, .048, .012))
    return g


def _headphones():
    g = Geometry()
    # Headband arches in its own Y/Z plane, open at the lower side.
    pts = [(.53*math.cos(a), 0, .57+.61*math.sin(a))
           for a in [i*math.pi/12 for i in range(13)]]
    g.polyline('rubber', pts, .070, 8)
    g.polyline('steel_grey', [(x, .035, z) for x, _, z in pts], .022, 6)
    for x in (-.53, .53):
        g.box('steel_black', (x, 0, .45), (.16, .35, .53), .055)
        g.box('rubber', (x, -.06, .45), (.19, .28, .45), .065)
    return g


def dj_console():
    g = Geometry()
    # Flightcase pedestal, metal corners, access seams, recessed carry handles.
    g.box('flightcase', (0, 0, 1.57), (10.50, 3.85, 3.14), .075)
    for x in (-5.24, 5.24):
        for y in (-1.91, 1.91):
            g.box('chrome_dull', (x, y, 1.61), (.13, .13, 3.20), .015)
    for z in (.07, 2.83, 3.15):
        g.box('chrome_dull', (0, -1.93, z), (10.50, .11, .11), .012)
        g.box('chrome_dull', (0, 1.93, z), (10.50, .11, .11), .012)
        for x in (-5.28, 5.28):
            g.box('chrome_dull', (x, 0, z), (.11, 3.86, .11), .012)
    for x in (-2.89, 2.89):
        g.box('steel_edge', (x, -1.989, 1.58), (1.25, .045, .54), .08)
        g.box('rubber', (x, -2.018, 1.60), (.90, .022, .27), .035)
        g.rod('chrome_dull', (x-.33, -2.05, 1.66), (x+.33, -2.05, 1.66), .04)
        for z in (.29, 2.63):
            g.box('chrome_dull', (x, -2.0, z), (.26, .07, .35), .035)
    g.box('steel_edge', (0, 0, 3.20), (10.77, 4.06, .12), .035)
    for x in (-2.80, 2.80):
        g.merge(_turntable(), (x, -.13, 3.28))
    g.merge(_mixer(), (0, -.13, 3.28))
    g.merge(_headphones(), (4.74, -.20, 3.24), (math.pi/2, 0, .28))
    # A restrained service-cable loop and input runs visible behind the decks.
    for x in (-2.8, 0, 2.8):
        g.polyline('rubber', [(x, 1.55, 3.46), (x+.2, 1.79, 3.39),
                   (x+.4, 2.0, 3.15), (x+.45, 2.01, 2.42)], .033, 6)
    g.box('label_dark', (0, -2.0, 1.4), (1.77, .01, .43))
    g.box('tape', (0, -2.014, 1.40), (1.30, .014, .16))
    return g


def _speaker_box(width=2.9, height=1.12, depth=1.22):
    g = Geometry()
    g.box('steel_black', (0, 0, 0), (width, depth, height), .06)
    g.box('grille', (0, -depth/2-.013, 0), (width-.18, .035, height-.15), .035)
    g.box('steel_edge', (0, -depth/2-.037, -height*.32),
          (width-.30, .016, .022))
    # Four wider grille seams read from below; no thousands of tiny grille holes.
    for x in (-.91, -.30, .30, .91):
        g.box('steel_black', (x, -depth/2-.038, 0), (.015, .012, height-.20))
    for x in (-width/2-.025, width/2+.025):
        g.box('steel_grey', (x, .02, 0), (.045, .52, .40), .025)
        for z in (-.13, .13):
            g.disc('chrome_dull', (x, -.08, z), .035, .02, (1, 0, 0), 8)
    return g


def speaker_tower():
    """Floor-mounted four-upright festival truss; max height 22.5 studs."""
    g = Geometry()
    xs, ys, height = (-1.0, 1.0), (-.72, .72), 22.2
    for x in xs:
        for y in ys:
            g.box('steel_black', (x, y, .10), (.91, .84, .20), .035)
            g.rod('steel_grey', (x, y, .20), (x, y, height), .12, 10)
            for xx in (-.28, .28):
                for yy in (-.23, .23):
                    g.disc('chrome_dull', (x+xx, y+yy, .215), .045, .027, sides=8)
    levels = [1.0+i*2.65 for i in range(9)]
    for z in levels:
        for y in ys:
            g.rod('steel_grey', (-1.0, y, z), (1.0, y, z), .067)
        for x in xs:
            g.rod('steel_grey', (x, -.72, z), (x, .72, z), .067)
    for i, (z0, z1) in enumerate(zip(levels, levels[1:])):
        for y in ys:
            g.rod('steel_grey', (-1.0 if i % 2 == 0 else 1.0, y, z0),
                  (1.0 if i % 2 == 0 else -1.0, y, z1), .058)
        for x in xs:
            g.rod('steel_grey', (x, -.72 if i % 2 == 0 else .72, z0),
                  (x, .72 if i % 2 == 0 else -.72, z1), .058)
    # Wide, low outriggers belong on the ground, not on the raised DJ deck.
    for x in (-2.11, 2.11):
        g.rod('steel_black', (math.copysign(1.0, x), .42, .51),
              (x, .42, .26), .10)
        g.box('steel_black', (x, .42, .16), (.61, .91, .32), .035)
    # Cantilever carries the hanging speakers in front of the upright lattice.
    for x in (-.90, .90):
        g.rod('steel_grey', (x, .61, 21.95), (x, -2.0, 21.95), .105)
        g.rod('steel_grey', (x, -.72, 19.55), (x, -1.94, 21.95), .075)
    g.rod('steel_grey', (-1.05, -1.96, 21.95), (1.05, -1.96, 21.95), .105)
    g.box('steel_black', (0, -1.96, 21.73), (.48, .66, .29), .06)
    g.rod('steel_black', (0, -1.96, 21.7), (0, -1.96, 20.24), .07)
    g.box('steel_edge', (0, -1.96, 20.25), (3.04, 1.16, .10), .02)
    # Five compact cabinets gradually angle down towards the audience.
    for i in range(5):
        z = 19.56-i*1.10
        y = -1.98-i*.09
        g.merge(_speaker_box(), (0, y, z), (math.radians(2+i*4), 0, 0))
        if i < 4:
            for x in (-1.42, 1.42):
                g.box('steel_grey', (x, y-.02, z-.56), (.12, .38, .17), .025)
    g.polyline('rubber', [(0, .83, .30), (.25, .83, 12.0),
               (.32, .84, 21.93), (.29, -1.35, 21.93),
               (.29, -1.4, 19.67)], .033, 6)
    return g


def subwoofer():
    g = Geometry()
    g.box('steel_black', (0, 0, 1.38), (4.10, 2.90, 2.76), .11)
    g.box('grille', (0, -1.464, 1.40), (3.87, .050, 2.48), .055)
    for x in (-.99, .99):
        g.disc('cone', (x, -1.506, 1.59), .78, .022, (0, -1, 0), 24)
        g.disc('grille', (x, -1.524, 1.59), .67, .018, (0, -1, 0), 24)
    for x in (-.95, .95):
        g.box('rubber', (x, -1.511, .42), (1.55, .019, .15), .025)
    for x in (-2.063, 2.063):
        g.box('steel_edge', (x, 0, 1.43), (.034, .95, .45), .025)
        g.box('rubber', (x+math.copysign(.022, x), 0, 1.43), (.010, .67, .20), .018)
    for z in (.14, 2.62):
        for x in (-1.94, 1.94):
            g.box('steel_grey', (x, -1.459, z), (.14, .04, .14), .015)
    return g


BUILDERS = OrderedDict([
    ('FloralSofa90s', floral_sofa),
    ('OliveVinylBench', vinyl_bench),
    ('LaminateOfficeDesk', laminate_desk),
    ('FourDrawerFilingCabinet', filing_cabinet),
    ('BeigeCRTMonitor', crt_monitor),
    ('OfficePhotocopier', copier),
    ('BrownOfficeChair', office_chair),
    ('BrownStackChair', stack_chair),
    ('WireServiceTrolley', wire_trolley),
    ('RolledCarpet', carpet_roll),
    ('BeigeKeyboard', keyboard),
    ('TwinDeckDJConsole', dj_console),
    ('VinylDiscAmber', vinyl_disc),
    ('VinylDiscCyan', lambda: vinyl_disc('record_label_cyan')),
    ('FestivalTrussSpeakerTower', speaker_tower),
    ('TwinSubwoofer', subwoofer),
])

NOTES = {
    'FloralSofa90s': 'Budget 1990s olive/gold damask sofa, three seat cushions, piping and low feet.',
    'FestivalTrussSpeakerTower': 'Independent ground-mounted four-upright lattice, low outriggers, cantilever, five downward-angled hanging cabinets. Keep outside deck and check roof clearance at all corners.',
    'TwinDeckDJConsole': 'Raised-stage console asset only; stage platform/stairs supplied by caller. Two physical turntables with offset pickup tonearms/counterweights/needles, mixer, headphones, flightcase hardware and cable runs. Record discs are separate meshes for slow client rotation.',
    'WireServiceTrolley': 'Open front lip and rear/side cage; purely cosmetic collision should remain simple.',
}


def _atlas_uv(mesh, face_keys):
    uv = mesh.uv_layers.new(name='PaletteUV')
    slots = {key: i for i, key in enumerate(PALETTE)}
    for poly, key in zip(mesh.polygons, face_keys):
        index = slots[key]
        # Every face lies inside a color tile, with a generous mip padding.
        x, y = index % 8, index // 8
        center = ((x+.5)/8, (y+.5)/8)
        for i, loop_index in enumerate(poly.loop_indices):
            a = i*math.tau/max(3, len(poly.loop_indices))
            uv.data[loop_index].uv = (center[0]+math.cos(a)*.024,
                                      center[1]+math.sin(a)*.024)
    return uv


def build_library(collection, *, prefix='LRP_', include=None):
    """Create a fresh prop kit in a caller-owned collection; refuse name collisions.

    Returned objects stay at the grounded origin. Instantiate with linked-data
    ``obj.copy()`` / ``copy.data = original.data`` to avoid duplicated mesh IDs.
    All sixteen original assets together are below a 60k triangle kit budget.
    That budget is checked from Blender tessellation; it is not a frame-rate claim.
    """
    names = list(BUILDERS) if include is None else list(include)
    unknown = set(names)-set(BUILDERS)
    if unknown:
        raise ValueError('Unknown assets: ' + ', '.join(sorted(unknown)))
    if len(names) != len(set(names)):
        raise ValueError('Duplicate asset names')
    collisions = [prefix+n for n in names if bpy.data.collections.get(prefix+n)
                  or bpy.data.objects.get(prefix+n)]
    if collisions:
        raise RuntimeError('Refusing to overwrite existing props: ' + ', '.join(collisions))
    output = OrderedDict()
    for name in names:
        g = BUILDERS[name]()
        child = bpy.data.collections.new(prefix+name)
        collection.children.link(child)
        mesh = bpy.data.meshes.new(prefix+name+'_Mesh')
        mesh.from_pydata(g.vertices, [], g.faces)
        mesh.update()
        used = list(dict.fromkeys(g.materials))
        for key in used:
            mesh.materials.append(material(key))
        for poly, key, smooth in zip(mesh.polygons, g.materials, g.smooth):
            poly.material_index = used.index(key)
            poly.use_smooth = smooth
        _atlas_uv(mesh, g.materials)
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        if triangles > 20000:
            raise RuntimeError(f'{name} exceeds mesh triangle budget: {triangles}')
        obj = bpy.data.objects.new(prefix+name, mesh)
        child.objects.link(obj)
        obj['lobby_preview_asset'] = name
        obj['lobby_preview_role'] = 'visual'
        obj['units'] = 'Roblox stud'
        obj['front'] = '-Y'
        obj['ground_origin'] = True
        bounds = [[min(v[i] for v in g.vertices) for i in range(3)],
                  [max(v[i] for v in g.vertices) for i in range(3)]]
        if bounds[0][2] < -.0001:
            raise RuntimeError(f'{name} is not grounded: {bounds[0][2]}')
        meta = {'asset': name, 'vertices': len(mesh.vertices), 'triangles': triangles,
                'materials': used, 'bounds_xyz': bounds, 'origin_xyz': [0, 0, 0],
                'up': '+Z', 'front': '-Y', 'unit': 'stud',
                'collision': 'Caller supplies simple separate collision; visual meshes do not authorize hull collision.',
                'notes': NOTES.get(name, 'Reusable worn backrooms furniture; placement controlled by caller.')}
        if name == 'TwinDeckDJConsole':
            meta['anchors_xyz'] = {'left_record_base': [-2.96, -.21, 3.773],
                                   'right_record_base': [2.64, -.21, 3.773]}
            meta['record_assets'] = {'left_record_base': 'VinylDiscAmber',
                                     'right_record_base': 'VinylDiscCyan'}
            meta['record_animation'] = {'axis': '+Z Blender / +Y Roblox',
                                        'suggested_degrees_per_second': 12,
                                        'authoring_preview_only': True}
        output[name] = {'collection': child, 'objects': [obj],
                        'triangles': triangles, 'bounds_xyz': bounds, 'metadata': meta}
    if sum(v['triangles'] for v in output.values()) > 60000:
        raise RuntimeError('Combined original prop kit exceeds 60k triangles')
    return output


def create_palette_atlas(path, size=512):
    """Create and pack the deterministic opaque PNG; no internet assets or baking."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    image = bpy.data.images.new('LRP_PaletteAtlas', width=size, height=size, alpha=False)
    colors = list(PALETTE.values()) + [PALETTE['steel_black']]*(64-len(PALETTE))
    pixels = []
    for y in range(size):
        for x in range(size):
            pixels.extend(colors[min(y*8//size, 7)*8 + min(x*8//size, 7)])
    image.pixels.foreach_set(pixels)
    image.colorspace_settings.name = 'sRGB'
    image.filepath_raw = str(path)
    formats = {i.identifier for i in image.bl_rna.properties['file_format'].enum_items}
    if 'PNG' not in formats:
        raise RuntimeError('PNG is unsupported by this Blender version: ' + ', '.join(sorted(formats)))
    image.file_format = 'PNG'
    image.save()
    image.pack()
    return image


def use_palette_atlas(library, image):
    """Explicit conversion on this library only, preferably on export copies."""
    name = 'LRP_OpaquePaletteExport'
    mat = bpy.data.materials.get(name)
    if mat is not None:
        raise RuntimeError('Refusing to retarget an existing export material')
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = .60
    texture = mat.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    mat.node_tree.links.new(texture.outputs['Color'], bsdf.inputs['Base Color'])
    for record in library.values():
        for obj in record['objects']:
            obj.data.materials.clear()
            obj.data.materials.append(mat)
            for poly in obj.data.polygons:
                poly.material_index = 0
    return mat


def metadata(library):
    """JSON-safe record; source mesh budgets do not imply measured Roblox FPS."""
    return {'schema': 'lobby-reimagined-props/1', 'builder': 'tools/lobby_reimagined/props.py',
            'coordinates': {'up': '+Z', 'front': '-Y', 'unit': 'Roblox stud'},
            'triangle_limit_per_mesh': 20000,
            'total_original_triangles': sum(r['triangles'] for r in library.values()),
            'assets': {name: record['metadata'] for name, record in library.items()}}
