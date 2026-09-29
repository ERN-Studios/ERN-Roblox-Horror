"""Level 6 / worn birthday-party mall: reusable Blender prop library.

Build with ``build_props({'materials': materials, 'parent': library_collection})``.
Returns {asset_name: bpy.types.Collection}; every asset origin is floor Z=0,
front is -Y, units are Roblox studs. Visual geometry is combined by material.
No modifiers, fonts, simulation or external add-ons are required. The caller
owns placement/export. Collision proxies and interaction empties are tagged and
must not be exported as visible geometry. bpy.data is touched only when called.
"""

from __future__ import annotations

import json
import math
import random
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


PALETTE = {
    'ivory_plastic': (0.70, 0.65, 0.51, 1),
    'red_plastic': (0.48, 0.075, 0.035, 1),
    'yellow_plastic': (0.66, 0.43, 0.035, 1),
    'green_plastic': (0.035, 0.26, 0.10, 1),
    'blue_plastic': (0.035, 0.115, 0.26, 1),
    'black_metal': (0.025, 0.03, 0.028, 1),
    'chrome': (0.31, 0.33, 0.30, 1),
    'laminate': (0.58, 0.50, 0.35, 1),
    'wood_worn': (0.31, 0.17, 0.065, 1),
    'cardboard': (0.43, 0.30, 0.15, 1),
    'grey_metal': (0.27, 0.28, 0.245, 1),
    'glass': (0.48, 0.56, 0.52, 0.10),
    'screen_dark': (0.008, 0.018, 0.022, 1),
    'screen_cyan': (0.20, 0.63, 0.77, 1),
    'screen_magenta': (0.63, 0.19, 0.26, 1),
    'screen_green': (0.36, 0.64, 0.21, 1),
    'paper': (0.77, 0.72, 0.60, 1),
    'rubber': (0.024, 0.023, 0.020, 1),
    'balloon_red': (0.52, 0.045, 0.025, 1),
    'balloon_yellow': (0.69, 0.49, 0.035, 1),
    'balloon_green': (0.025, 0.29, 0.12, 1),
    'balloon_blue': (0.025, 0.11, 0.31, 1),
    'cd_silver': (0.52, 0.56, 0.57, 1),
}


def _fallback_material(key):
    """Fallback is deliberately muted; supplied textured materials take priority."""
    name = 'L6P_' + key
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    col = PALETTE[key]
    mat.diffuse_color = col
    bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = .62
    if key in {'chrome', 'cd_silver', 'black_metal', 'grey_metal'}:
        bsdf.inputs['Metallic'].default_value = .35 if key != 'cd_silver' else .76
    if key.startswith('screen_') and key != 'screen_dark':
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = col
            bsdf.inputs['Emission Strength'].default_value = .55
    if key == 'glass':
        bsdf.inputs['Alpha'].default_value = col[3]
        bsdf.inputs['Roughness'].default_value = .26
        if hasattr(mat, 'surface_render_method'):
            mat.surface_render_method = 'DITHERED'
    return mat


class Geometry:
    """Append-only geometry builder, grouped into shared palette materials."""
    def __init__(self):
        self.groups = defaultdict(lambda: [[], [], []])

    def mesh(self, mat, vertices, faces, smooth=False):
        vs, fs, ss = self.groups[mat]
        offset = len(vs)
        vs.extend(tuple(v) for v in vertices)
        fs.extend(tuple(offset + i for i in f) for f in faces)
        ss.extend([smooth] * len(faces))

    def box(self, mat, pos, size, bevel=0, rz=0):
        x, y, z = size
        if min(size) <= 0:
            raise ValueError('Box dimensions must be positive')
        if not bevel:
            vs = [(a*x/2, b*y/2, c*z/2) for c in (-1, 1)
                  for b in (-1, 1) for a in (-1, 1)]
            fs = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                  (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        else:
            b = min(bevel, min(size)*.42)
            # Clipped corners + bevel rings preserve a molded silhouette cheaply.
            footprint = [(x/2-b, -y/2), (x/2, -y/2+b), (x/2, y/2-b),
                         (x/2-b, y/2), (-x/2+b, y/2), (-x/2, y/2-b),
                         (-x/2, -y/2+b), (-x/2+b, -y/2)]
            vs = []
            for height, inset in [(-z/2, b*.55), (-z/2+b, 0),
                                   (z/2-b, 0), (z/2, b*.55)]:
                for px, py in footprint:
                    vs.append((px-math.copysign(inset, px),
                               py-math.copysign(inset, py), height))
            fs = [tuple(reversed(range(8))), tuple(range(24, 32))]
            for ring in range(3):
                for i in range(8):
                    fs.append((ring*8+i, ring*8+(i+1)%8,
                               (ring+1)*8+(i+1)%8, (ring+1)*8+i))
        c, s = math.cos(rz), math.sin(rz)
        vs = [(pos[0]+px*c-py*s, pos[1]+px*s+py*c, pos[2]+pz)
              for px, py, pz in vs]
        self.mesh(mat, vs, fs)

    def cone(self, mat, pos, radius, height, top=None, sides=12, smooth=True):
        top = radius if top is None else top
        vs = []
        for z, r in [(-height/2, radius), (height/2, top)]:
            for i in range(sides):
                a = i*math.tau/sides
                vs.append((pos[0]+math.cos(a)*r, pos[1]+math.sin(a)*r, pos[2]+z))
        fs = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
        fs.extend((i, (i+1)%sides, (i+1)%sides+sides, i+sides)
                  for i in range(sides))
        self.mesh(mat, vs, fs, smooth)

    def rod(self, mat, start, end, radius=.06, sides=8, top=None):
        delta = Vector(end) - Vector(start)
        length = delta.length
        if length < .00001:
            return
        rotation = Vector((0, 0, 1)).rotation_difference(delta.normalized())
        mid = (Vector(start) + Vector(end))*.5
        vs = []
        for zz, rad in [(-length/2, radius), (length/2, radius if top is None else top)]:
            for i in range(sides):
                a = i*math.tau/sides
                vs.append(mid + rotation @ Vector((math.cos(a)*rad, math.sin(a)*rad, zz)))
        fs = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
        fs.extend((i, (i+1)%sides, (i+1)%sides+sides, i+sides) for i in range(sides))
        self.mesh(mat, vs, fs, True)

    def sphere(self, mat, pos, scale, segments=12, rings=7):
        vs = [(pos[0], pos[1], pos[2]-scale[2])]
        for ring in range(1, rings):
            lat = -math.pi/2 + math.pi*ring/rings
            for i in range(segments):
                a = i*math.tau/segments
                vs.append((pos[0]+scale[0]*math.cos(lat)*math.cos(a),
                           pos[1]+scale[1]*math.cos(lat)*math.sin(a),
                           pos[2]+scale[2]*math.sin(lat)))
        vs.append((pos[0], pos[1], pos[2]+scale[2]))
        fs = [(0, 1+(i+1)%segments, 1+i) for i in range(segments)]
        for r in range(rings-2):
            for i in range(segments):
                a = 1+r*segments+i
                b = 1+r*segments+(i+1)%segments
                fs.append((a, b, b+segments, a+segments))
        top = len(vs)-1
        start = 1+(rings-2)*segments
        fs.extend((start+i, start+(i+1)%segments, top) for i in range(segments))
        self.mesh(mat, vs, fs, True)

    def ring(self, mat, pos, outer, inner, height=.04, sides=32):
        vs = []
        for z, r in [(-height/2, outer), (-height/2, inner),
                     (height/2, outer), (height/2, inner)]:
            for i in range(sides):
                a = i*math.tau/sides
                vs.append((pos[0]+math.cos(a)*r, pos[1]+math.sin(a)*r, pos[2]+z))
        fs = []
        for i in range(sides):
            j = (i+1)%sides
            fs.extend([(i, j, j+sides*2, i+sides*2),
                       (i+sides, i+sides*3, j+sides*3, j+sides),
                       (i+sides*2, j+sides*2, j+sides*3, i+sides*3),
                       (i, i+sides, j+sides, j)])
        self.mesh(mat, vs, fs)

    def profile(self, mat, yz_points, width, x=0):
        """Extruded side silhouette: points run counter-clockwise in Y/Z."""
        n = len(yz_points)
        vs = [(x-width/2, y, z) for y, z in yz_points]
        vs += [(x+width/2, y, z) for y, z in yz_points]
        fs = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
        fs.extend((i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n))
        self.mesh(mat, vs, fs)

    def merge(self, other, pos=(0, 0, 0), rz=0, scale=(1, 1, 1)):
        c, s = math.cos(rz), math.sin(rz)
        for mat, (vs, fs, smooth) in other.groups.items():
            transformed = []
            for x, y, z in vs:
                x *= scale[0]
                y *= scale[1]
                z *= scale[2]
                transformed.append((pos[0]+x*c-y*s, pos[1]+x*s+y*c, pos[2]+z))
            dest = self.groups[mat]
            offset = len(dest[0])
            dest[0].extend(transformed)
            dest[1].extend(tuple(offset+i for i in face) for face in fs)
            dest[2].extend(smooth)


def chair(color='red_plastic'):
    g = Geometry()
    # Seat is subtly dished by slatted detail; four splayed molded legs.
    seat_vs = []
    segments = 6
    radius = .29
    for z, inset in [(2.035,.035),(2.08,0),(2.22,0),(2.265,.025)]:
        for cx,cy,start in [(.85,-.785,-math.pi/2),(.85,.785,0),
                            (-.85,.785,math.pi/2),(-.85,-.785,math.pi)]:
            for step in range(segments):
                a=start+step*math.pi/(2*segments)
                seat_vs.append((cx+math.cos(a)*(radius-inset),
                                cy+math.sin(a)*(radius-inset),z))
    n=segments*4
    seat_fs=[tuple(reversed(range(n))),tuple(range(n*3,n*4))]
    for r in range(3):
        for i in range(n):
            j=(i+1)%n
            seat_fs.append((r*n+i,r*n+j,(r+1)*n+j,(r+1)*n+i))
    g.mesh(color,seat_vs,seat_fs,True)
    g.box(color, (0, .83, 2.02), (2.08, .15, .34), .035)
    for x in (-.93, .93):
        for y in (-.86, .86):
            g.rod(color, (x*1.23, y*1.3, .08), (x, y, 2.1), .105, 6, .14)
            g.box('rubber', (x*1.23, y*1.3, .055), (.22, .22, .11), .025)
    # A single broad molded shell with three real oval slots and a handhold.
    # Adjacent shell patches share the same surface and meet edge-to-edge;
    # there are no separate ladder rungs or metal-looking tubular back rails.
    def shell_patch(cx,cz,half_x,half_z,hole_x,hole_z,rounded_outer=False):
        count=24
        verts=[]
        def shell_y(x,z):
            return .89+(z-2.2)*.092+(x*x)*.025
        outer=[];inner=[]
        for i in range(count):
            a=i*math.tau/count
            ca,sa=math.cos(a),math.sin(a)
            if rounded_outer:
                px=math.copysign(abs(ca)**.43,ca)*half_x
                pz=math.copysign(abs(sa)**.43,sa)*half_z
            else:
                fac=1/max(abs(ca),abs(sa))
                px=ca*fac*half_x;pz=sa*fac*half_z
            outer.append((cx+px,cz+pz))
            inner.append((cx+ca*hole_x,cz+sa*hole_z))
        for depth,loop in [(-.105,outer),(-.105,inner),(.105,outer),(.105,inner)]:
            for x,z in loop:verts.append((x,shell_y(x,z)+depth,z))
        faces=[]
        for i in range(count):
            j=(i+1)%count
            faces.extend([(i,j,count+j,count+i),
                          (count*2+i,count*3+i,count*3+j,count*2+j),
                          (i,count*2+i,count*2+j,j),
                          (count+i,count+j,count*3+j,count*3+i)])
        g.mesh(color,verts,faces,True)
    for x in (-.70,0,.70):
        shell_patch(x,2.95,.35,.75,.16,.56)
    shell_patch(0,3.97,1.16,.33,.38,.11,True)
    # Side shoulders flare into the seat, characteristic of stackable monoblocs.
    for sx in (-1,1):
        g.rod(color,(sx*1.0,.91,2.14),(sx*1.08,1.04,3.74),.09,8,.12)
    # Faint scuff lines sit just above the molded seat.
    for x, y, length in [(-.62, -.45, .44), (.27, .03, .7), (-.12, .52, .52)]:
        g.box('ivory_plastic', (x, y, 2.269), (.014, length, .005))
    return g


def folding_table():
    g = Geometry()
    g.box('black_metal', (0, 0, 3.25), (11.16, 4.30, .22), .075)
    g.box('laminate', (0, 0, 3.37), (11.2, 4.35, .14), .065)
    for x in (-3.83, 3.83):
        for sy in (-1, 1):
            g.rod('black_metal', (x, sy*1.80, .12), (x, sy*1.31, 3.18), .085, 8)
            g.cone('rubber', (x, sy*1.80, .085), .108, .17, sides=8)
        g.rod('black_metal', (x, -1.65, 1.08), (x, 1.65, 1.08), .065, 8)
        g.rod('black_metal', (x, -.86, 1.53), (x*.53, -.86, 3.15), .055, 6)
        g.rod('black_metal', (x, .86, 1.53), (x*.53, .86, 3.15), .055, 6)
        for sy in (-1, 1):
            g.box('grey_metal', (x, sy*1.35, 3.16), (.36, .29, .08), .015)
    # Subtle cheap laminate chips along exposed rim.
    for x, y in [(-4.32, -2.165), (1.80, -2.165), (4.62, 2.165)]:
        g.box('wood_worn', (x, y, 3.369), (.23, .018, .045))
    return g


def cup(g, pos, color='paper', height=.50, radius=.18):
    x, y, z = pos
    g.cone(color, (x, y, z+height/2), radius*.71, height, radius, 10)
    g.ring(color, (x, y, z+height), radius*1.02, radius*.80, .025, 10)
    g.cone('wood_worn', (x, y, z+height-.04), radius*.77, .008, sides=10)


def plate(g, pos, radius=.51):
    g.cone('paper', (pos[0], pos[1], pos[2]+.025), radius*.83, .05, radius, 16)
    g.ring('paper', (pos[0], pos[1], pos[2]+.055), radius, radius*.74, .035, 16)


def tableware():
    g = Geometry()
    for x in (-.85, .90):
        plate(g, (x, 0, 0), .50)
        cup(g, (x+.42, .63, 0), height=.5)
        g.box('paper', (x-.38, -.48, .006), (.34, .37, .012), rz=.18)
        g.box('ivory_plastic', (x+.63, -.16, .026), (.04, .59, .025))
    return g


def folded_tables():
    g = Geometry()
    for i in range(3):
        y = i*.38
        g.box('black_metal', (0, y, 3.40), (4.12, .19, 6.80), .075)
        g.box('laminate', (0, y-.105, 3.40), (4.10, .075, 6.78), .03)
        for x in (-1.2, 1.2):
            g.rod('black_metal', (x, y+.15, 1.05), (x, y+.15, 5.72), .08, 6)
    return g


def chair_stack():
    g = Geometry()
    for i, col in enumerate(['green_plastic']*3):
        g.merge(chair(col), (0, i*.035, i*.44))
    return g


def pixel_sprite(g, pattern, x, y, z, pixel=.08, mat='screen_cyan'):
    for r, line in enumerate(pattern):
        for c, char in enumerate(line):
            if char != ' ':
                g.box(mat, (x+c*pixel, y, z-r*pixel), (pixel*.91, .015, pixel*.91))


def arcade(kind='Invaders'):
    g = Geometry()
    color = {'Invaders':'blue_plastic', 'Maze':'yellow_plastic',
             'Platform':'red_plastic'}[kind]
    g.box('black_metal', (0, -.05, .04), (3.26, 3.12, .08), .02)
    outline = [(-1.6, .08), (1.45, .08), (1.45, 7.18), (-1.02, 7.18),
               (-1.42, 6.95), (-1.34, 6.32), (-.73, 5.98),
               (-.34, 4.28), (-1.43, 4.12), (-1.62, 3.65)]
    for x in (-1.53, 1.53):
        g.profile(color, outline, .18, x)
    # The monitor cavity must stay open: a full-height solid cabinet would hide
    # the recessed CRT and its pixel geometry behind an opaque front face.
    g.box('black_metal', (0, .02, 1.96), (2.93, 2.75, 3.76), .035)
    g.box('black_metal', (0, 1.34, 5.37), (2.93, .18, 3.63), .025)
    g.box('black_metal', (0, .31, 7.06), (2.93, 2.30, .22), .025)
    g.box(color, (0, -1.48, 1.72), (2.90, .19, 3.25), .055)
    # Coin door, twin slots, return tray and a small key lock.
    g.box('black_metal', (0, -1.595, 1.93), (1.35, .06, 1.65), .03)
    for x in (-.29, .29):
        g.box('chrome', (x, -1.636, 2.30), (.28, .045, .37), .015)
        g.box('rubber', (x, -1.663, 2.33), (.075, .01, .22))
        g.box('rubber', (x, -1.634, 1.52), (.27, .055, .12))
    g.box('chrome', (.45, -1.636, 1.98), (.095, .03, .095), .015)
    # Screen set back in its broad black bezel, generic low-res game geometry.
    g.box('black_metal', (0, -.86, 5.26), (2.76, .13, 2.08), .12)
    g.box('screen_dark', (0, -.935, 5.25), (2.21, .075, 1.65), .075)
    if kind == 'Invaders':
        sprite = ['  X X  ', ' XXXXX ', 'XX X XX', 'XXXXXXX', ' X   X ']
        for r in range(2):
            for c in range(3):
                pixel_sprite(g, sprite, -.93+c*.64, -.982, 5.72-r*.53,
                             .055, 'screen_cyan' if r == 0 else 'screen_green')
        pixel_sprite(g, ['  X  ', ' XXX ', 'XXXXX'], -.10, -.982, 4.70, .055, 'screen_magenta')
    elif kind == 'Maze':
        for x in (-.83, -.37, .10, .73):
            g.box('screen_cyan', (x, -.982, 5.25), (.035, .015, 1.26))
        for z in (4.63, 5.06, 5.45, 5.88):
            g.box('screen_cyan', (0, -.982, z), (1.72, .015, .035))
        for i in range(5):
            g.box('yellow_plastic', (-.62+i*.26, -.998, 5.23), (.042, .015, .042))
        g.sphere('screen_magenta', (.40, -.993, 4.83), (.10, .03, .10), 8, 4)
    else:
        for x, z, width in [(-.68, 4.7, .65), (.20, 5.12, .8), (.53, 5.65, .65)]:
            g.box('screen_cyan', (x, -.982, z), (width, .015, .065))
        pixel_sprite(g, [' XX ', 'XXXX', ' XX ', 'X X '], -.8, -.989, 5.10, .07, 'screen_magenta')
    # Hood marquee and inset battered control shelf.
    g.box('black_metal', (0, -1.32, 6.71), (2.94, .18, .68), .045)
    g.box('yellow_plastic' if kind == 'Maze' else 'grey_metal',
          (0, -1.418, 6.71), (2.63, .025, .45), .015)
    for i in range(5):
        g.box(color, (-.84+i*.42, -1.436, 6.70), (.17, .012, .18), rz=0)
    g.box(color, (0, -1.02, 4.05), (2.95, 1.03, .16), .05)
    g.rod('black_metal', (-.67, -1.14, 4.12), (-.67, -1.14, 4.46), .055, 8)
    g.sphere('red_plastic', (-.67, -1.14, 4.47), (.14, .14, .14), 10, 6)
    for i in range(3):
        g.cone('red_plastic' if i != 1 else 'yellow_plastic',
               (.16+i*.37, -1.12+(i%2)*.14, 4.16), .125, .09, sides=12)
    # A few side pixel decals, no copyrighted game branding.
    for x, z in [(-1.636, 1.3), (-1.636, 2.6), (1.636, 1.8), (1.636, 3.0)]:
        g.box('yellow_plastic', (x, .55, z), (.018, .22, .25))
    return g


def plush(g, pos, col, scale=.40):
    x, y, z = pos
    g.sphere(col, (x, y, z+scale*.65), (scale*.56, scale*.43, scale*.70), 8, 5)
    g.sphere(col, (x, y, z+scale*1.38), (scale*.50, scale*.42, scale*.47), 8, 5)
    for sx in (-1, 1):
        g.sphere(col, (x+sx*scale*.35, y, z+scale*1.74), (scale*.20, scale*.15, scale*.22), 8, 4)
        g.box('rubber', (x+sx*scale*.18, y-scale*.403, z+scale*1.48), (.035, .025, .045))


def claw_machine():
    g = Geometry()
    g.box('yellow_plastic', (0, 0, 1.25), (3.40, 3.22, 2.50), .06)
    g.box('black_metal', (0, 0, .12), (3.51, 3.31, .24), .04)
    g.box('black_metal', (0, 0, 6.15), (3.51, 3.31, .32), .035)
    g.box('yellow_plastic', (0, -1.57, 6.55), (3.38, .20, .58), .025)
    for x in (-1.63, 1.63):
        for y in (-1.54, 1.54):
            g.box('black_metal', (x, y, 4.30), (.12, .12, 3.72))
    for x in (-1.63, 1.63):
        g.box('glass', (x, 0, 4.25), (.023, 3.01, 3.51))
    for y in (-1.54, 1.54):
        g.box('glass', (0, y, 4.25), (3.12, .023, 3.51))
    g.box('paper', (0, 0, 2.49), (3.12, 2.93, .07))
    rng = random.Random(69)
    for i in range(9):
        x, y = (i%3-1)*.87, (i//3-1)*.78
        plush(g, (x, y, 2.51), ['red_plastic','yellow_plastic','blue_plastic','green_plastic'][i%4], .42+rng.random()*.1)
    g.rod('chrome', (-1.49, .14, 5.73), (1.49, .14, 5.73), .065, 8)
    g.box('grey_metal', (.22, .14, 5.67), (.40, .41, .30), .025)
    g.rod('black_metal', (.22, .14, 5.50), (.22, .14, 4.85), .035, 6)
    for a in (0, math.tau/3, math.tau*2/3):
        p = (.22+math.cos(a)*.29, .14+math.sin(a)*.29, 4.53)
        g.rod('chrome', (.22, .14, 4.85), p, .032, 6)
        g.rod('chrome', p, (.22+math.cos(a)*.17, .14+math.sin(a)*.17, 4.42), .032, 6)
    g.box('black_metal', (0, -1.624, .88), (1.23, .04, .66), .06)
    g.box('grey_metal', (-.96, -1.63, 1.74), (.33, .08, .52), .02)
    g.box('black_metal', (-.96, -1.68, 1.79), (.07, .015, .23))
    g.box('yellow_plastic', (.56, -1.76, 2.22), (1.42, .65, .16), .045)
    g.cone('red_plastic', (.79, -1.80, 2.36), .14, .12, sides=12)
    g.rod('black_metal', (.24, -1.80, 2.29), (.24, -1.80, 2.54), .045, 6)
    g.sphere('red_plastic', (.24, -1.80, 2.59), (.10, .10, .10), 8, 5)
    return g


def prize_counter():
    g = Geometry()
    g.box('laminate', (0, 0, 1.79), (9.2, 2.7, 3.58), .06)
    g.box('black_metal', (0, 0, .16), (9.26, 2.73, .30), .02)
    g.box('grey_metal', (0, 0, 3.63), (9.42, 2.92, .18), .045)
    for level in range(2):
        z = 3.76+level*1.35
        for i in range(4):
            x = -1.95+i*1.50
            g.box('black_metal', (x, .56, z), (1.42, 1.13, .07))
            g.box('glass', (x, .56, z+.57), (1.39, 1.10, 1.10), .005)
            for j in range(3):
                col = ['red_plastic','yellow_plastic','green_plastic','blue_plastic'][(i+j+level)%4]
                g.sphere(col, (x-.36+j*.36, .47, z+.28), (.20, .22, .22), 8, 4)
                g.box('paper', (x, -.005, z+.09), (.60, .019, .13))
    # Clunky cash register at left.
    g.box('black_metal', (-3.47, -.22, 3.90), (1.57, 1.42, .42), .065)
    g.box('grey_metal', (-3.47, .18, 4.26), (1.39, .69, .48), .04)
    for r in range(3):
        for c in range(5):
            g.box('ivory_plastic', (-3.96+c*.24, -.65+r*.21, 4.13), (.18, .14, .065), .015)
    return g


def balloon_cluster():
    g = Geometry()
    for x, y, z, col in [(-.55, 0, 6.24, 'balloon_green'),
                          (.52, .16, 6.38, 'balloon_yellow'),
                          (0, .18, 7.24, 'balloon_red')]:
        g.sphere(col, (x, y, z), (.57, .52, .71), 12, 8)
        g.cone(col, (x, y, z-.72), .055, .09, .017, 8)
        g.rod('paper', (x, y, z-.74), (0, 0, .22), .009, 4)
    g.box('red_plastic', (0, 0, .08), (.42, .31, .16), .03)
    return g


def birthday_garland():
    g = Geometry()
    cols = ['red_plastic','yellow_plastic','green_plastic','blue_plastic']
    # Thirteen inexpensive triangular flags; optional Roblox SurfaceGui can put
    # the HAPPY BIRTHDAY lettering on the designated front face without fonts.
    points = []
    for i in range(14):
        x = -5.6+i*(11.2/13)
        z = .76+.78*((x/5.6)**2)
        points.append((x, 0, z))
    for a, b in zip(points, points[1:]):
        g.rod('paper', a, b, .016, 4)
    for i in range(13):
        a, b = points[i], points[i+1]
        mx, mz = (a[0]+b[0])/2, (a[2]+b[2])/2
        g.mesh(cols[i%4], [(a[0]+.06,-.01,a[2]), (b[0]-.06,-.01,b[2]),
                          (mx,-.01,mz-.75), (a[0]+.06,.01,a[2]),
                          (b[0]-.06,.01,b[2]), (mx,.01,mz-.75)],
               [(2,1,0),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
    return g


def cake_table():
    g = Geometry()
    g.box('laminate', (0, 0, 3.42), (4.5, 2.65, .18), .075)
    for x in (-1.78, 1.78):
        for y in (-.95, .95):
            g.rod('black_metal', (x, y, .07), (x, y, 3.33), .075, 8)
            g.cone('rubber', (x,y,.05), .083, .10, sides=8)
    plate(g, (-.70, 0, 3.51), .83)
    g.cone('paper', (-.70, 0, 3.78), .71, .48, sides=24)
    g.ring('red_plastic', (-.70, 0, 3.99), .715, .65, .035, 24)
    for i in range(5):
        a = i*math.tau/5
        x, y = -.70+math.cos(a)*.4, math.sin(a)*.4
        g.cone('yellow_plastic', (x, y, 4.16), .027, .30, sides=6)
    for i in range(5):
        plate(g, (1.05, .25, 3.52+i*.045), .43)
    cup(g, (1.20, -.75, 3.51))
    return g


def carton(g, pos, size, opened=False):
    x, y, z = pos
    w, d, h = size
    # Bottom-open form for usable prop storage; tape and paper label are geometry.
    if opened:
        for xx in (-w/2, w/2):
            g.box('cardboard', (x+xx, y, z+h/2), (.055, d, h))
        for yy in (-d/2, d/2):
            g.box('cardboard', (x, y+yy, z+h/2), (w, .055, h))
        g.box('cardboard', (x, y, z+.025), (w, d, .05))
    else:
        g.box('cardboard', (x, y, z+h/2), size, .015)
        g.box('paper', (x, y, z+h+.008), (.16, d*.99, .015))
    g.box('paper', (x-.1*w, y-d/2-.011, z+h*.52), (w*.43, .012, h*.29))
    for i in range(3):
        g.box('wood_worn', (x-.1*w, y-d/2-.020, z+h*.52+(i-1)*.075), (w*.3, .01, .019))


def supply_shelf():
    g = Geometry()
    for x in (-3.40, 3.40):
        for y in (-1.04, 1.04):
            g.box('grey_metal', (x, y, 3.72), (.15, .15, 7.44))
    for z in (.18, 2.17, 4.19, 6.21):
        g.box('grey_metal', (0, 0, z), (6.96, 2.22, .12))
        for y in (-1.07, 1.07):
            g.box('grey_metal', (0, y, z-.07), (6.96, .075, .14))
    g.rod('grey_metal', (-3.36, 1.04, .30), (3.36, 1.04, 6.98), .038, 6)
    g.rod('grey_metal', (3.36, 1.04, .30), (-3.36, 1.04, 6.98), .038, 6)
    for x, y, z, w, d, h in [(-2.34, 0, .25,1.67,1.72,1.39),(-.20, 0, .25,2.14,1.75,1.62),
                             (2.13, 0, .25,1.52,1.45,1.19),(-2.25, 0, 2.24,1.72,1.65,1.28),
                             (2.16, .04, 2.24,1.54,1.62,1.28),
                             (-2.25, 0, 6.28,1.88,1.65,1.16),(.15,0,6.28,2.30,1.71,1.21),
                             (2.45,0,6.28,1.50,1.65,1.05)]:
        carton(g, (x,y,z), (w,d,h))
    # Multi-colored stacked cup sleeves and stacks of paper plates.
    for i in range(4):
        x = -2.62+i*.71
        col = ['red_plastic','blue_plastic','yellow_plastic','paper'][i]
        g.cone(col, (x, .02, 4.86), .24, 1.20, .31, 12)
        for j in range(5):
            g.ring(col, (x, .02, 4.31+j*.21), .247+j*.012, .21, .025, 10)
    for i in range(4):
        plate(g, (1.15, -.02, 4.27+i*.11), .62)
    for i in range(4):
        g.box(['blue_plastic','paper','yellow_plastic','red_plastic'][i],
              (2.53, 0, 4.29+i*.17), (.93, 1.16, .12), .015)
    for i in range(4):
        g.sphere(['red_plastic','yellow_plastic','green_plastic','blue_plastic'][i],
                 (-.75+i*.46, 0, 2.65), (.25,.29,.36), 8, 5)
    return g


def helium_tank():
    g = Geometry()
    g.cone('red_plastic', (0,0,2.07), .58, 3.63, sides=16)
    g.sphere('red_plastic', (0,0,3.79), (.58,.58,.49), 16, 6)
    g.ring('black_metal', (0,0,.09), .63,.55,.18,16)
    g.cone('chrome', (0,0,4.35), .13,.35,sides=10)
    g.rod('chrome', (-.31,0,4.48), (.38,0,4.48), .07,8)
    g.ring('black_metal', (0,0,4.68), .24,.17,.055,12)
    g.box('paper', (0,-.585,2.62), (.63,.015,.81))
    g.box('yellow_plastic', (0,-.595,2.67), (.38,.013,.25))
    for x,z in [(-.28,1.14),(.24,1.94),(-.1,3.2)]:
        g.box('grey_metal', (x,-.558,z), (.16,.02,.33))
    return g


def flat_clown_cutout():
    g = Geometry()
    # A deliberately flat, innocent cheap party decoration, not an entity.
    g.box('cardboard',(0,.08,2.2),(2.42,.12,4.4),.10)
    g.sphere('paper',(0,-.025,2.61),(1.08,.065,1.27),16,8)
    for x in (-.85,.85):
        g.sphere('red_plastic',(x,-.035,2.93),(.48,.04,.73),10,6)
    g.sphere('red_plastic',(0,-.13,2.51),(.30,.04,.28),10,6)
    for x in (-.35,.35):
        g.sphere('black_metal',(x,-.112,2.99),(.095,.025,.19),8,5)
    g.box('blue_plastic',(0,-.028,3.92),(1.89,.12,.23),.06)
    g.box('blue_plastic',(.10,-.026,4.16),(1.13,.12,.57),.11)
    for i in range(7):
        a = math.pi*(1.12+i*.125)
        g.sphere('red_plastic',(math.cos(a)*.62,-.119,2.35+math.sin(a)*.54),(.115,.022,.095),8,4)
    g.box('yellow_plastic',(0,-.03,1.15),(1.70,.08,.64),.09)
    return g


def workshop_bench():
    g = Geometry()
    g.box('wood_worn',(0,0,3.42),(9.70,2.80,.34),.045)
    for x in (-4.30,4.30):
        for y in (-1.0,1.0):
            g.box('wood_worn',(x,y,1.63),(.29,.31,3.26),.02)
    g.box('wood_worn',(0,0,.62),(9.0,2.45,.13),.015)
    # Cast-metal vise and lead screw.
    g.box('black_metal',(-3.1,-.72,3.70),(1.43,.94,.28),.04)
    g.box('grey_metal',(-3.10,-.69,4.02),(.77,.90,.57),.07)
    for x in (-3.52,-2.74):
        g.box('grey_metal',(x,-.68,4.23),(.20,1.05,.27),.03)
    g.rod('chrome',(-3.78,-.72,3.96),(-2.2,-.72,3.96),.082,8)
    g.rod('chrome',(-2.2,-.72,3.54),(-2.2,-.72,4.34),.055,8)
    for z in (3.54,4.34):
        g.sphere('chrome',(-2.2,-.72,z),(.09,.09,.09),8,4)
    # Toolbox with latch and carry handle.
    g.box('red_plastic',(.10,.20,3.93),(1.83,1.20,.65),.045)
    g.box('black_metal',(.10,.20,4.275),(1.86,1.23,.055),.02)
    for x in (-.21,.42):
        g.rod('black_metal',(x,.20,4.30),(x,.20,4.47),.035,6)
    g.rod('black_metal',(-.21,.20,4.47),(.42,.20,4.47),.045,6)
    g.box('chrome',(.10,-.423,4.05),(.18,.03,.20),.02)
    # Small parts drawers, intentionally mismatched inserts.
    g.box('black_metal',(3.05,.50,4.48),(2.1,1.20,1.74),.035)
    for r in range(4):
        for c in range(3):
            x,z=2.37+c*.68,3.86+r*.40
            g.box('grey_metal' if (r+c)%3 else 'ivory_plastic',(x,-.135,z),(.59,.10,.31),.015)
            g.box('paper',(x,-.193,z+.055),(.27,.02,.085))
            g.box('black_metal',(x,-.210,z-.07),(.19,.055,.045))
    for x,col in [(-2.15,'green_plastic'),(.15,'red_plastic'),(2.3,'green_plastic')]:
        g.box(col,(x,0,1.09),(1.91,1.87,.77),.04)
        g.box('black_metal',(x,0,1.49),(1.99,1.93,.10),.025)
    return g


def pegboard():
    g = Geometry()
    g.box('wood_worn',(0,0,2.10),(7.30,.14,4.20),.025)
    # Selected visible hole pattern is geometry; many holes are baked by material.
    for r in range(7):
        for c in range(14):
            g.box('black_metal',(-3.22+c*.495,-.078,.37+r*.56),(.04,.007,.04))
    # Adjustable spanner, hammer and three screwdrivers.
    g.box('chrome',(-2.4,-.17,2.31),(.19,.15,1.71),.04)
    g.box('chrome',(-2.4,-.18,3.27),(.70,.16,.34),.06)
    g.box('black_metal',(-2.36,-.269,3.38),(.30,.01,.14))
    g.rod('wood_worn',(-.83,-.19,1.40),(-.83,-.19,3.01),.09,8)
    g.box('grey_metal',(-.83,-.19,3.02),(.97,.33,.30),.045)
    for i,col in enumerate(['red_plastic','blue_plastic','red_plastic']):
        x=.65+i*.76
        g.rod('chrome',(x,-.21,1.35),(x,-.21,2.28),.035,6)
        g.rod(col,(x,-.21,2.27),(x,-.21,3.12),.12,8)
        g.rod('grey_metal',(x-.11,-.05,2.25),(x-.11,-.33,2.25),.025,6)
    return g


def breaker_panel():
    g = Geometry()
    g.box('grey_metal',(0,0,2.15),(2.77,.51,4.30),.065)
    g.box('grey_metal',(0,-.29,2.15),(2.52,.10,4.06),.03)
    g.box('black_metal',(.98,-.36,2.06),(.10,.07,.43),.015)
    g.box('paper',(0,-.35,2.84),(.92,.018,.80))
    g.box('yellow_plastic',(0,-.366,2.84),(.78,.012,.54))
    # Generic lightning warning rather than unreadable generated words.
    g.mesh('black_metal',[(-.03,-.377,3.08),(-.25,-.377,2.82),(-.05,-.377,2.82),
                          (-.14,-.377,2.59),(.25,-.377,2.95),(.04,-.377,2.95)],
           [(0,1,2,3,4,5)])
    for x in (-1.01,1.01):
        for z in (.25,4.05):
            g.sphere('chrome',(x,-.357,z),(.037,.015,.037),8,4)
    g.rod('chrome',(-.65,.10,4.29),(-.65,.10,5.22),.075,8)
    g.rod('chrome',(.65,.10,4.29),(.65,.10,5.65),.075,8)
    return g


def mop_bucket():
    g = Geometry()
    for x in (-.76,.76):
        for y in (-.60,.60):
            g.sphere('rubber',(x,y,.19),(.19,.11,.19),8,5)
    for x in (-.84,.84):
        g.box('yellow_plastic',(x,0,1.10),(.12,1.50,1.52),.025)
    for y in (-.70,.70):
        g.box('yellow_plastic',(0,y,1.10),(1.64,.12,1.52),.025)
    g.box('yellow_plastic',(0,0,.39),(1.69,1.50,.14),.025)
    for x in (-.88,.88):
        g.box('yellow_plastic',(x,0,1.90),(.13,1.60,.18),.035)
    for y in (-.77,.77):
        g.box('yellow_plastic',(0,y,1.90),(1.86,.13,.18),.035)
    g.box('yellow_plastic',(.0,.33,2.18),(1.52,.86,.16),.025)
    for x in (-.70,.70):
        g.box('yellow_plastic',(x,.33,2.55),(.10,.89,.78),.02)
    g.box('yellow_plastic',(0,.72,2.55),(1.40,.09,.78),.02)
    for i in range(5):
        g.box('black_metal',(-.50+i*.25,.665,2.60),(.065,.011,.42))
    g.rod('chrome',(.70,.35,2.87),(.70,-.37,3.60),.06,8)
    g.rod('black_metal',(.47,-.37,3.60),(.93,-.37,3.60),.09,8)
    # Dry leaning mop and chunky cotton strands.
    g.rod('red_plastic',(1.45,-.11,.70),(1.02,.35,5.93),.063,8)
    for i in range(8):
        a=i*math.tau/8
        g.rod('paper',(1.44,-.10,.71),(1.45+math.cos(a)*.35,-.1+math.sin(a)*.32,.10),.07,6)
    return g


def cd():
    g=Geometry()
    g.ring('cd_silver',(0,0,.03),.52,.079,.035,48)
    g.ring('paper',(0,0,.052),.245,.08,.008,32)
    for i,col in enumerate(['screen_cyan','screen_magenta','screen_green']):
        g.ring(col,(0,0,.052+i*.0006),.487-i*.023,.480-i*.023,.002,48)
    return g


def cd_case():
    g=Geometry()
    g.box('black_metal',(0,0,.04),(1.10,1.18,.08),.015)
    g.box('paper',(0,0,.088),(.95,1.10,.015))
    g.box('red_plastic',(-.34,.08,.100),(.13,.81,.008))
    for i in range(3):
        g.box('black_metal',(.09,.32-i*.13,.101),(.47,.043,.01))
    g.box('glass',(0,0,.12),(1.10,1.18,.045),.012)
    return g


def cd_player():
    g=Geometry()
    g.box('grey_metal',(0,0,.43),(3.36,1.67,.73),.12)
    g.box('black_metal',(0,-.824,.43),(3.02,.09,.48),.035)
    for x in (-1.16,1.16):
        # Perforation strips evoke small cheap boombox speaker grilles.
        for i in range(5):
            g.box('grey_metal',(x,-.88,.24+i*.093),(.62,.018,.034),.006)
    g.box('screen_dark',(0,-.883,.51),(.80,.022,.24),.018)
    for x in (-.22,-.05,.12,.29):
        g.box('screen_green',(x,-.902,.51),(.075,.008,.099))
    g.cone('black_metal',(0,-.07,.810),.60,.035,sides=32)
    g.ring('grey_metal',(0,-.07,.833),.60,.54,.032,32)
    g.box('paper',(.0,-.06,.854),(.37,.12,.005))
    for i in range(4):
        g.box('black_metal',(-.47+i*.31,-.61,.815),(.19,.18,.055),.02)
    for x in (-1.15,1.15):
        g.cone('black_metal',(x,.37,.816),.14,.09,sides=12)
    for x in (-1.28,1.28):
        g.box('rubber',(x,.47,.045),(.27,.29,.09),.02)
    # Folding carry handle and antenna.
    for x in (-1.14,1.14):
        g.rod('black_metal',(x,.61,.64),(x,.61,1.27),.055,8)
    g.rod('black_metal',(-1.14,.61,1.27),(1.14,.61,1.27),.065,8)
    return g


def fluorescent_fixture():
    g=Geometry()
    g.box('black_metal',(0,0,.243),(5.5,1.43,.28),.03)
    g.box('ivory_plastic',(0,0,.131),(5.23,1.20,.065),.02)
    for y in (-.33,.33):
        g.rod('paper',(-2.34,y,.07),(2.34,y,.07),.07,10)
    return g


def wall_speaker():
    g=Geometry()
    g.box('black_metal',(0,0,1.13),(1.40,.93,2.26),.07)
    for z,r in [(1.37,.43),(.58,.27)]:
        # Shallow ellipsoids read as cones behind inexpensive grille strips.
        g.sphere('rubber',(0,-.47,z),(r,.035,r),12,6)
    for i in range(9):
        g.box('grey_metal',(0,-.512,.30+i*.21),(1.12,.018,.020))
    return g


def wall_clock():
    g=Geometry()
    # Vertical disc built using transformed horizontal ring primitives.
    temp=Geometry()
    temp.cone('black_metal',(0,0,.07),1.0,.14,sides=32)
    temp.cone('paper',(0,0,.15),.91,.02,sides=32)
    temp.ring('black_metal',(0,0,.169),.98,.90,.03,32)
    for i in range(12):
        a=i*math.tau/12
        temp.box('black_metal',(math.sin(a)*.76,math.cos(a)*.76,.166),(.025,.095,.014),rz=-a)
    temp.rod('black_metal',(0,0,.19),(-.48,.40,.19),.025,6)
    temp.rod('black_metal',(0,0,.20),(.54,-.16,.20),.02,6)
    for mat,(vs,fs,ss) in temp.groups.items():
        # +Y -> +Z, +Z -> -Y, bottom rests at0.
        g.mesh(mat,[(x,-z,y+1) for x,y,z in vs],fs)
    return g


BUILDERS = {
    'ChairRed': lambda: chair('red_plastic'),
    'ChairYellow': lambda: chair('yellow_plastic'),
    'ChairGreen': lambda: chair('green_plastic'),
    'ChairBlue': lambda: chair('blue_plastic'),
    'FoldingTable': folding_table,
    'Tableware': tableware,
    'ChairStack': chair_stack,
    'FoldedTables': folded_tables,
    'ArcadeInvaders': lambda: arcade('Invaders'),
    'ArcadeMaze': lambda: arcade('Maze'),
    'ArcadePlatform': lambda: arcade('Platform'),
    'ClawMachine': claw_machine,
    'PrizeCounter': prize_counter,
    'BalloonCluster': balloon_cluster,
    'BirthdayGarland': birthday_garland,
    'CakeTable': cake_table,
    'SupplyShelf': supply_shelf,
    'HeliumTank': helium_tank,
    'FlatClownCutout': flat_clown_cutout,
    'WorkshopBench': workshop_bench,
    'Pegboard': pegboard,
    'BreakerPanel': breaker_panel,
    'MopBucket': mop_bucket,
    'CD': cd,
    'CDCase': cd_case,
    'CDPlayer': cd_player,
    'FluorescentFixture': fluorescent_fixture,
    'WallSpeaker': wall_speaker,
    'WallClock': wall_clock,
}


# Collider tuples are (center XYZ, dimensions XYZ). All are convex boxes except
# the fold-table walk-under gap, which deliberately has separate leg proxies.
COLLIDERS = {
    'FoldingTable': [((0,0,3.33),(11.2,4.35,.22)),
                     ((-3.83,0,1.61),(.20,3.76,3.04)),
                     ((3.83,0,1.61),(.20,3.76,3.04))],
    'ChairStack': [((0,.03,2.60),(2.55,2.62,5.20))],
    'FoldedTables': [((0,.34,3.4),(4.12,1.13,6.8))],
    'ClawMachine': [((0,0,3.42),(3.51,3.55,6.84))],
    'PrizeCounter': [((0,0,3.12),(9.42,2.92,6.24))],
    'CakeTable': [((0,0,1.76),(4.5,2.65,3.52))],
    'SupplyShelf': [((0,0,3.76),(6.98,2.23,7.52))],
    'HeliumTank': [((0,0,2.37),(1.27,1.27,4.74))],
    'WorkshopBench': [((0,0,2.70),(9.7,2.8,5.40))],
    'MopBucket': [((.21,0,1.82),(2.32,1.70,3.64))],
    'CDPlayer': [((0,0,.41),(3.36,1.67,.82))],
}
for _name in ['ChairRed','ChairYellow','ChairGreen','ChairBlue']:
    COLLIDERS[_name] = [((0,0,1.13),(2.5,2.55,2.26)),
                        ((0,1.0,3.2),(2.25,.3,2.14))]
for _name in ['ArcadeInvaders','ArcadeMaze','ArcadePlatform']:
    COLLIDERS[_name] = [((0,-.05,3.63),(3.45,3.30,7.26))]


ANCHORS = {
    'FoldingTable': {'HidePrompt': (0,-2.18,2.2), 'HidePose': (0,0,1.4)},
    'CD': {'PickupPrompt': (0,0,.15)},
    'CDCase': {'InspectPrompt': (0,0,.25)},
    'CDPlayer': {'InsertDisc': (0,-.07,.87), 'Controls': (0,-.88,.58),
                 'SpeakerLeft': (-1.16,-.87,.5), 'SpeakerRight': (1.16,-.87,.5)},
    'ArcadeInvaders': {'PlayPrompt': (0,-1.8,4.2), 'ScreenCenter': (0,-.99,5.25)},
    'ArcadeMaze': {'PlayPrompt': (0,-1.8,4.2), 'ScreenCenter': (0,-.99,5.25)},
    'ArcadePlatform': {'PlayPrompt': (0,-1.8,4.2), 'ScreenCenter': (0,-.99,5.25)},
    'ClawMachine': {'PlayPrompt': (.52,-1.94,2.65)},
    'BreakerPanel': {'SwitchPrompt': (.98,-.42,2.15)},
    'WallSpeaker': {'SoundOrigin': (0,-.52,1.13)},
    'FluorescentFixture': {'LightOrigin': (0,0,-.12)},
}


def _create_mesh_objects(asset_name, geometry, collection, materials):
    objects = []
    for key, (verts, faces, smooth_flags) in sorted(geometry.groups.items()):
        if not verts:
            continue
        mesh = bpy.data.meshes.new('L6P_' + asset_name + '_' + key)
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        for p, smooth in zip(mesh.polygons, smooth_flags):
            p.use_smooth = smooth
        # Stable planar UVs for a shared wear texture; each Blender unit equals a
        # stud. Export callers may subsequently remap this into a palette atlas.
        uv = mesh.uv_layers.new(name='WearUV')
        for polygon in mesh.polygons:
            normal = polygon.normal
            axis = max(range(3), key=lambda i: abs(normal[i]))
            for li in polygon.loop_indices:
                co = mesh.vertices[mesh.loops[li].vertex_index].co
                if axis == 2:
                    u, v = co.x, co.y
                elif axis == 1:
                    u, v = co.x, co.z
                else:
                    u, v = co.y, co.z
                uv.data[li].uv = (u*.24, v*.24)
        obj = bpy.data.objects.new(asset_name + '__' + key, mesh)
        collection.objects.link(obj)
        mesh.materials.append(materials[key])
        obj['l6_asset'] = asset_name
        obj['l6_material_key'] = key
        obj['l6_role'] = 'visual'
        obj['export_visual'] = True
        objects.append(obj)
    return objects


def _proxy(asset_name, index, center, dimensions, collection):
    geometry = Geometry()
    geometry.box('grey_metal', center, dimensions)
    verts, faces, _ = geometry.groups['grey_metal']
    mesh = bpy.data.meshes.new(asset_name + '_Collision_' + str(index))
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(asset_name + '__COLLISION_' + str(index), mesh)
    collection.objects.link(obj)
    obj.display_type = 'WIRE'
    obj.hide_render = True
    obj['l6_asset'] = asset_name
    obj['l6_role'] = 'collision'
    obj['export_collision_only'] = True
    obj['center_xyz'] = list(center)
    obj['dimensions_xyz'] = list(dimensions)
    return obj


def asset_spec(collections=None):
    """JSON-safe export/interaction metadata; measured counts when built."""
    record = {
        'schema': 'level6-worn-party-props/1',
        'source': 'tools/level6_build/props.py',
        'unit': 'Roblox stud',
        'coordinates': {'up': '+Z', 'front': '-Y', 'roblox_xyz': ['X','Z','-Y']},
        'art_direction': 'Worn budget 1990s birthday-party mall; plastic chairs, laminate, black tubular legs, tired arcade cabinets. No luxury styling.',
        'material_keys': sorted(PALETTE),
        'assets': {},
    }
    for name in BUILDERS:
        data = {
            'collection': 'L6P_' + name,
            'collision_boxes': [{'center_xyz': list(c), 'size_xyz': list(s)}
                                for c,s in COLLIDERS.get(name,[])],
            'anchors_xyz': {k:list(v) for k,v in ANCHORS.get(name,{}).items()},
            'decorative_noncolliding': name not in COLLIDERS,
        }
        if collections and name in collections:
            data['collection'] = collections[name].name
            visuals = [o for o in collections[name].objects if o.get('l6_role') == 'visual']
            data['visual_objects'] = len(visuals)
            data['vertices'] = sum(len(o.data.vertices) for o in visuals)
            data['triangles'] = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in visuals)
            data['materials'] = [o['l6_material_key'] for o in visuals]
            pts = [v.co for o in visuals for v in o.data.vertices]
            if pts:
                data['bounds_xyz'] = [[min(v[i] for v in pts) for i in range(3)],
                                      [max(v[i] for v in pts) for i in range(3)]]
        record['assets'][name] = data
    return record


def build_props(ctx=None):
    """Create collections once. Raise on collisions to protect existing work.

    ctx keys: materials (dict), parent (Collection or None), collection_prefix,
    include (iterable names), spec_path (optional JSON filepath).
    Parent defaults to a newly created scene-linked L6_PropLibrary collection.
    """
    ctx = ctx or {}
    supplied = ctx.get('materials', {})
    materials = {key: supplied.get(key) or _fallback_material(key) for key in PALETTE}
    prefix = ctx.get('collection_prefix', 'L6P_')
    include = set(ctx.get('include') or BUILDERS)
    unknown = include - set(BUILDERS)
    if unknown:
        raise ValueError('Unknown prop names: ' + ', '.join(sorted(unknown)))
    collisions = [prefix+name for name in include if bpy.data.collections.get(prefix+name)]
    if collisions:
        raise ValueError('Refusing to overwrite existing prop collections: ' + ', '.join(collisions))
    parent = ctx.get('parent')
    if parent is None:
        parent = bpy.data.collections.new('L6_PropLibrary')
        bpy.context.scene.collection.children.link(parent)
    result = {}
    for name, builder in BUILDERS.items():
        if name not in include:
            continue
        collection = bpy.data.collections.new(prefix+name)
        parent.children.link(collection)
        collection['l6_asset'] = name
        collection['l6_family'] = 'worn-party-prop'
        collection['l6_units'] = 'studs'
        collection['l6_forward'] = '-Y'
        _create_mesh_objects(name, builder(), collection, materials)
        for index,(center,dimensions) in enumerate(COLLIDERS.get(name,[])):
            _proxy(name,index,center,dimensions,collection)
        for label,position in ANCHORS.get(name,{}).items():
            anchor = bpy.data.objects.new(name+'__'+label,None)
            anchor.empty_display_type = 'PLAIN_AXES'
            anchor.empty_display_size = .22
            anchor.location = position
            anchor.hide_render = True
            anchor['l6_asset'] = name
            anchor['l6_role'] = 'interaction_anchor'
            anchor['l6_anchor'] = label
            collection.objects.link(anchor)
        result[name] = collection
    if ctx.get('spec_path'):
        path = Path(ctx['spec_path'])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(asset_spec(result),indent=2)+'\n')
    return result
