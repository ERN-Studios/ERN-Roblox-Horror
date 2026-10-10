"""Level 5 "the void rooms", v4, 2026-10-10: phone and tablet rebuild.
Owner: "Jeg ved at level 5 er fuldkommen umuligt på telefon"; "Bare fix og lave hele
level 5 om. Gør det nemmere på telefon og tablet".

Walking 16, sprinting 26, JumpPower 50, gravity 196.2. Short, straight gaps use
45/50/52/55/55/0/55/50/60/58 percent walking caps; no gap below 3.2,
and gap dy -3..+1.5. Solid-ground turns, six straight studs before takeoff,
wide long level landings tested at both speeds, edge/2 early and +/-12 degrees.
Teal tests walking fully and sprint at edge only on its 10-stud square tops.
Walkways >=5 (Rose/Blue/Amber >=7), Mint beams >=4; landings >=7, >=11 long
except Teal. <=80 gaps and individual room budgets. Checkpoints every <=3 gaps
and <=90 route studs, on >=7x7 level ground with >=3 edge clearance, with yaw.
Transparent collidable 0.6 side guards span -0.5..+7.5 above the surface, including
gaps, except rests/plazas/Mint beams; spiral stairs have outer guards only.
Guards are trimmed against walkable tops and both routes sampled every 0.5 stud.
Neon Edge strips mark both edges of every gap. Nothing floats outside STACKED;
no crossing; monolith clearance includes alternative routes. Route points remain
0.9 before a gap / 2.0 after it; touching Amber +3 blocks use jump+hop, not GAPS.
Mint and Teal alternatives are real geometry, exported as alts. The shells, lamps,
balls, plazas, plates, doors and the finale retain their existing construction.

python3 tools/level5_void/build_level5.py
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level5_void/build_level5.py
"""
import json, math, random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / 'artifacts' / 'level5-void-20261003' / 'build'
WALK, JUMP, GRAVITY = 16.0, 50.0, 196.2
BOTTOM, HALF, CLEAR_Z, RISE = -420.0, 70.0, 50.0, 320.0
SHARE = dict(rose=.45, blue=.50, amber=.52, mint=.55, violet=.55, coral=0,
             orange=.55, crimson=.50, teal=.60, ivory=.58)
BUDGET = dict(rose=4, blue=8, amber=8, mint=8, violet=8, coral=0,
              orange=4, crimson=6, teal=14, ivory=8)
LENGTH_CAP = dict(rose=430, blue=360, amber=300, mint=360, violet=300, teal=280)
COLOURS = {
    'rose': (224, 150, 200), 'blue': (92, 150, 200), 'amber': (228, 180, 88),
    'mint': (150, 216, 182), 'violet': (164, 134, 214), 'coral': (236, 118, 102), 'black': (4, 4, 5),
    'orange': (244, 142, 44), 'crimson': (188, 34, 46), 'teal': (44, 178, 184), 'ivory': (232, 228, 212),
    'stone': (74, 72, 68), 'slab': (30, 29, 28), 'glass': (150, 190, 200),
    'sphere': (26, 38, 120), 'orb': (150, 146, 134), 'plate': (236, 236, 230), 'edge': (255, 244, 214),
}
PARTS, BALLS, LIGHTS, ROUTE, CHECKPOINTS, GAPS, PLATES, FOOT = [], [], [], [], [], [], [], []
ALTS, GUARDS, EXTENT, FINALE, METRICS = [], [], {}, {}, {}
GUARD_COVERAGE = []
ROOFED, STACKED = {'rose', 'blue', 'amber'}, {'crimson', 'ivory'}
random.seed(505)


def reach_at(speed, dy):
    disc = JUMP * JUMP - 2 * GRAVITY * dy
    assert disc > 0, f'physics: dy {dy} exceeds apex'
    return speed * (JUMP + math.sqrt(disc)) / GRAVITY


def reach(dy):
    return reach_at(WALK, dy)

def part(name, size, pos, colour, yaw=0.0, shape='b', collide=True, material='SmoothPlastic', extra=None):
    row = {'n': name, 's': [round(v, 3) for v in size], 'p': [round(v, 3) for v in pos], 'c': colour,
           'yaw': round(yaw, 3), 'sh': shape, 'col': collide, 'm': material}
    if extra:
        row.update(extra)
    PARTS.append(row)
    return row


def solid(name, length, width, top, cx, cz, yaw, colour, bottom=BOTTOM):
    """A block whose top face is the surface and whose body runs down into the dark."""
    part(name, (length, top - bottom, width), (cx, (top + bottom) / 2, cz), colour, yaw=yaw)


def light(pos, rng=60, brightness=0.2, name=None):
    row = {'p': [round(v, 2) for v in pos], 'r': rng, 'b': round(brightness, 3)}
    if name:
        row['n'] = name
    LIGHTS.append(row)


def corners(f, grow=0.0):
    c, s = math.cos(math.radians(f['yaw'])), math.sin(math.radians(f['yaw']))
    hl, hw = f['l'] / 2 + grow, f['w'] / 2 + grow
    return [(f['x'] + c * a - s * b, f['z'] + s * a + c * b) for a, b in ((hl, hw), (hl, -hw), (-hl, -hw), (-hl, hw))]


def overlap(a, b, grow=0.0):
    """Separating axes for two rectangles in plan."""
    pa, pb = corners(a, grow), corners(b)
    for poly in (pa, pb):
        for i in range(2):
            ex, ez = poly[i + 1][0] - poly[i][0], poly[i + 1][1] - poly[i][1]
            nx, nz = -ez, ex
            da = [nx * x + nz * z for x, z in pa]
            db = [nx * x + nz * z for x, z in pb]
            if max(da) < min(db) - 1e-6 or max(db) < min(da) - 1e-6:
                return False
    return True


def mark(sec, x, y, z, jump=False, sink=None, **flags):
    row = dict(x=round(x, 3), y=round(y, 3), z=round(z, 3), jump=jump, sec=sec, **flags)
    (ROUTE if sink is None else sink).append(row)
    return row


def register(sec, name, length, width, x, y, z, yaw, thin=False, **flags):
    if thin:
        row = part(name, (length, 1.4, width), (x, y-.7, z), sec, yaw=yaw)
    else:
        solid(name, length, width, y, x, z, yaw, sec)
        row = PARTS[-1]
    f = dict(sec=sec, i=sum(a['sec']==sec for a in FOOT)+1, n=name,
             x=x, z=z, l=length, w=width, yaw=yaw, top=y, part=len(PARTS)-1, **flags)
    FOOT.append(f)
    pts = corners(f)
    e = EXTENT.setdefault(sec, [x,x,z,z,y,y])
    e[:] = [min(e[0],min(a for a,b in pts)), max(e[1],max(a for a,b in pts)),
            min(e[2],min(b for a,b in pts)), max(e[3],max(b for a,b in pts)), min(e[4],y),max(e[5],y)]
    return f


class Path_:
    """The heading is +x=0, +z=90. Turns consume a square, never a gap."""
    def __init__(self, section, x, y, z, heading=0., sink=None):
        self.section = self.colour = section
        self.x, self.y, self.z, self.h = x,y,z,heading
        self.x0, self.mirror, self.sink = x,1,sink
        self.jump_next, self.pending, self.last = False,None,None
        self.thin, self.outer = section in STACKED, None
        self.both = False                   # guards on both sides although `outer` names one (see square_stair)
    def dir(self):
        return math.cos(math.radians(self.h)),math.sin(math.radians(self.h))
    def point(self, along=0., side=0.):
        dx,dz=self.dir()
        return self.x+dx*along-dz*side,self.y,self.z+dz*along+dx*side
    def way(self, along=0., jump=False, **flags):
        return mark(self.section,*self.point(along),jump=jump,sink=self.sink,**flags)
    def checkpoint(self, x,y,z, kind='rest', yaw=None, at=None):
        assert self.sink is None, f'{self.section}: checkpoints belong to main route'
        cp=dict(sec=self.section,x=round(x,3),y=round(y,3),z=round(z,3),
                at=len(ROUTE) if at is None else at,yaw=round(self.h if yaw is None else yaw,3),kind=kind)
        # Insert the checkpoint centre into the actual walking polyline.
        start=max(0,cp['at']-1)
        for j in range(start,min(len(ROUTE)-1,cp['at']+3)):
            a,b=ROUTE[j],ROUTE[j+1]
            dx,dz=b['x']-a['x'],b['z']-a['z']; d2=dx*dx+dz*dz
            if d2<1e-9: continue
            t=((x-a['x'])*dx+(z-a['z'])*dz)/d2
            if .001<t<.999 and abs(a['y']-y)<.01 and abs(b['y']-y)<.01 and math.hypot(a['x']+t*dx-x,a['z']+t*dz-z)<.01:
                ROUTE.insert(j+1,dict(sec=self.section,x=round(x,3),y=round(y,3),z=round(z,3),jump=False))
                for old_cp in CHECKPOINTS:
                    if old_cp['at']>=j+1: old_cp['at']+=1
                for old_g in GAPS:
                    if old_g['route_at']>=j+1 and not old_g['alt']: old_g['route_at']+=1
                cp['at']=j+1
                break
        CHECKPOINTS.append(cp)
        return cp
    def plat(self,length,width,name='Walk',**flags):
        assert length>0, f'{self.section}: piece {len(FOOT)} has length {length}'
        dx,dz=self.dir()
        f=register(self.section,name,length,width,self.x+dx*length/2,self.y,self.z+dz*length/2,self.h,
                   thin=self.thin,outer=self.outer,both=self.both,alt=self.sink is not None,**flags)
        self.way(min(2.,length/2),jump=self.jump_next)
        if self.pending:
            self.pending['landing']=f['i']; self.pending['end']=[self.x,self.y,self.z]
        self.jump_next,self.pending=False,None
        self.x+=dx*length; self.z+=dz*length
        if length>=2.9: self.way(-.9)
        self.last=f
        return self
    def rest(self,length,width):
        at=len(ROUTE)
        cx,cy,cz=self.point(length/2)
        self.plat(length,width,'Rest')
        self.checkpoint(cx,cy,cz,at=at)
        orb(cx,cy+20,cz,self.section)
        return self
    def turn(self,degrees,width=9., checkpoint=False):
        assert not self.jump_next, f'{self.section}: piece {len(FOOT)} turns at a gap'
        cx,cy,cz=self.point(width/2)
        # All rebuilt joints are square and axis aligned.
        f=register(self.section,'Joint',width,width,cx,cy,cz,0,thin=self.thin,outer=self.outer,both=self.both,
                   alt=self.sink is not None,outer_heads=[self.h,self.h+degrees*self.mirror])
        self.x,self.z=cx,cz
        self.h+=degrees*self.mirror
        self.way()
        if checkpoint:
            self.checkpoint(cx,cy,cz,'corner',at=len(ROUTE)-1)
            orb(cx,cy+20,cz,self.section)
        dx,dz=self.dir(); self.x+=dx*width/2; self.z+=dz*width/2
        self.last=f
        return self
    def corner(self,degrees,width=9.):
        return self.turn(degrees,width,checkpoint=True)
    def gap(self,distance,dy=0.,practice=False):
        sec=self.section
        assert self.last and not self.pending, f'{sec}: piece {len(FOOT)} has no takeoff'
        assert 3.2<=distance<=SHARE[sec]*reach(dy)+1e-6 and -3<=dy<=1.5, f'{sec}: piece {self.last["i"]} invalid gap {distance}/{dy}'
        # Explicit straight approach point, then the exact legacy takeoff convention.
        self.way(-.9)
        start=[self.x,self.y,self.z]
        g=dict(sec=sec,gap=distance,dy=dy,reach=round(reach(dy),3),share=round(distance/reach(dy),4),
               start=start,yaw=self.h,takeoff=self.last['i'],route_at=len(ROUTE),alt=self.sink is not None)
        GAPS.append(g)
        if practice:
            dx,dz=self.dir()
            register(sec,'PracticePit',distance,self.last['w'],self.x+dx*distance/2,self.y-2.5,self.z+dz*distance/2,self.h)
            g['practice']=True
        dx,dz=self.dir(); self.x+=dx*distance; self.z+=dz*distance; self.y+=dy
        self.jump_next,self.pending=True,g
        return self
    def stairs(self,steps,run,rise,w0,w1=None):
        for i in range(steps):
            self.y+=rise
            self.plat(run,w0 if w1 is None else w0+(w1-w0)*i/max(1,steps-1),'Step')
        return self
    def ball(self,back,side,r=1.4):
        x,y,z=self.point(-back,side)
        BALLS.append({'p':[round(x,2),round(y+r+.05,2),round(z,2)],'r':r})
        return self
    def plaza(self,last=False):
        assert abs(self.h%360)<1e-6,f'{self.section}: plaza heading {self.h}'
        cx,cy,cz=self.point(17)
        at=len(ROUTE)
        self.plat(12,30,'Plaza'); ROUTE.pop()
        if not last:
            self.way(5.,plate=self.section)
            PLATES.append(dict(sec=self.section,x=round(cx,2),y=round(cy,2),z=round(cz,2)))
        self.plat(24,30,'Plaza')
        self.checkpoint(cx-9,cy,cz,'plaza',at=at)
        orb(cx,cy+22,cz,self.section)
        return self


def local(f,x,z):
    c,s=math.cos(math.radians(f['yaw'])),math.sin(math.radians(f['yaw']))
    return c*(x-f['x'])+s*(z-f['z']),-s*(x-f['x'])+c*(z-f['z'])


def inside(f,x,z,shrink=0.):
    a,b=local(f,x,z)
    return abs(a)<=f['l']/2-shrink+1e-6 and abs(b)<=f['w']/2-shrink+1e-6


def no_crossing(name):
    feet=[f for f in FOOT if f['sec']==name]
    for i,a in enumerate(feet):
        for b in feet[i+1:]:
            assert not overlap(a,b,-.01), f'{name}: pieces {a["i"]}/{b["i"]} cross in plan'

def orb(x, y, z, colour):
    """The lamp: a white ball on a rod from the ceiling (the rod's top is set by `room`, which knows the ceiling)."""
    # Owner, 2026-10-04: the first lamps (a 5-stud white neon globe, light 2.6 over 46 studs) were blinding and hid
    # the way ahead. A 3-stud dull globe and a light a sixth as strong.
    part('Orb', (3, 3, 3), (x, y + 0.9, z), 'orb', shape='s', collide=False, material='Neon', extra={'light': [30, 0.45], 'rod': colour})


def wall_with_door(x, colour, top, door_z, door_y, thick=8.0, door_w=9.0, door_h=13.0):
    """An end wall (constant x) with a doorway at walking height door_y, centred on door_z."""
    def slab(z0, z1, y0, y1):
        z0, z1 = max(z0, -HALF - 8), min(z1, HALF + 8)
        if z1 - z0 > 0.05 and y1 - y0 > 0.05:
            part('Wall', (thick, y1 - y0, z1 - z0), (x, (y0 + y1) / 2, (z0 + z1) / 2), colour)
    slab(-HALF - 8, door_z - door_w / 2, BOTTOM, top)
    slab(door_z + door_w / 2, HALF + 8, BOTTOM, top)
    slab(door_z - door_w / 2, door_z + door_w / 2, door_y + door_h, top)
    slab(door_z - door_w / 2, door_z + door_w / 2, BOTTOM, door_y)        # the sill is the floor of the doorway


def route_y(name, x):
    pts = [r for r in ROUTE if r['sec'] == name]
    return min(pts, key=lambda r: abs(r['x'] - x))['y']


def room(name, x0, x1, monoliths=True, shaft=False, dense=1, column=None):
    e = EXTENT[name]
    print(f'    {name}: z {e[2]:.1f}..{e[3]:.1f}, ends at z {ROUTE[-1]["z"]:.1f}')
    assert e[0] >= x0 - 0.01 and e[1] <= x1 + 0.01, f'{name}: the path runs x {e[0]:.1f}..{e[1]:.1f}, outside the room {x0:.1f}..{x1:.1f}'
    limit = HALF - 2 if shaft else CLEAR_Z                 # a shaft's stair runs along the walls themselves
    assert e[2] >= -limit and e[3] <= limit, f'{name}: the path runs z {e[2]:.1f}..{e[3]:.1f}, into the walls (limit {limit})'
    if name not in STACKED:
        no_crossing(name)
    length, top = x1 - x0, e[5] + 64
    roofed = name in ROOFED
    lamp_top = top                                 # the lamps and their rods are placed as if the ceiling were there
    if not roofed:
        top = e[5] + RISE                          # no ceiling: the walls carry on up, past where any light reaches
    for side in (-1, 1):
        part('Wall', (length, top - BOTTOM, 8), ((x0 + x1) / 2, (top + BOTTOM) / 2, side * (HALF + 4)), name)
    if roofed:
        part('Ceiling', (length + 8, 6, HALF * 2 + 16), ((x0 + x1) / 2, top + 3, 0), name)
    # the references' walls are huge curved sheets: tall cylinders sunk most of the way into the side walls
    radii = [34, 26, 40, 30, 36]
    n = 0 if shaft else max(2, int(length // 62))
    for k in range(n):
        cx = x0 + (k + 0.5) * length / n
        for side in (-1, 1):
            r = radii[(k + (0 if side < 0 else 2)) % len(radii)]
            part('Fold', (top - BOTTOM, r * 2, r * 2), (cx + side * 9, (top + BOTTOM) / 2, side * (HALF + r * 0.62)),
                 name, shape='c', extra={'roll': 90})
    # loose monoliths standing in the drop: they give the dark a scale and are never on the route
    feet = [f for f in FOOT if f['sec'] == name]
    made, tries = 0, 0
    while monoliths and not shaft and made < int(length // 34) * dense and tries < 9000:
        tries += 1
        w, d = random.choice((6, 8, 10, 14, 18)), random.choice((6, 8, 10, 14))
        m = {'x': random.uniform(x0 + 14, x1 - 14), 'z': random.uniform(-HALF + 20, HALF - 20), 'l': w, 'w': d,
             'yaw': random.choice((0, 0, 12, -18, 30, 45))}
        if any(overlap(m, f, 7.0) for f in feet):
            continue
        feet.append(m)
        base = route_y(name, m['x'])
        solid('Monolith', w, d, base + random.choice((-74, -52, -38, -24, -16, 9, 20, 34)), m['x'], m['z'], m['yaw'], name)
        made += 1
    # Measured in Studio (2026-10-03): brightness 1 at 26 studs from the walls blew the room out to white;
    # 0.2 from two rows near the middle reads as the references' soft gradient. The rows follow the route's
    # height, and a last row sits just under the ceiling, which is black without it.
    if shaft:
        # lamps follow the stair round the walls, a little toward the middle; the middle itself stays black
        pts = [r for r in ROUTE if r['sec'] == name]
        mid, walked = (x0 + x1) / 2, 0.0
        for a, b in zip(pts, pts[1:]):
            walked += math.hypot(b['x'] - a['x'], b['z'] - a['z'])
            if walked >= 26:
                walked = 0.0
                dx, dz = mid - b['x'], -b['z']
                if column:                                 # a stair round a column is lit from outside it
                    dx, dz = b['x'] - column[0], b['z'] - column[1]
                d = math.hypot(dx, dz) or 1.0
                light((b['x'] + dx / d * 12, b['y'] + 10, b['z'] + dz / d * 12))
                light((b['x'] + dx / d * 12, b['y'] + 36, b['z'] + dz / d * 12))
    for i in range(0 if shaft else int((length - 36) // 34) + 1):
        lx = x0 + 18 + i * 34
        y = route_y(name, lx)
        for lz in (-18, 18):
            for ly in (y + 10, y + 44):
                if ly < lamp_top - 16:
                    light((lx, ly, lz))
            if roofed:
                light((lx, top - 12, lz))              # the row that shows the ceiling; an open room has none
    for row in PARTS:                                             # hang this room's lamps from its ceiling
        if row.get('rod') == name:
            x, y, z = row['p']
            part('OrbRod', (0.35, top - y - 1.4, 0.35), (x, (top + y + 1.4) / 2, z), 'black', collide=False, material='Metal')
            row['rod'] = True
    return top


def link(x0, x1, y, z, sec):
    """The pitch-dark corridor between two rooms."""
    length, cx = x1 - x0, (x0 + x1) / 2
    solid('LinkFloor', length, 9, y, cx, z, 0, 'black')
    part('LinkCeiling', (length, 3, 9), (cx, y + 14.5, z), 'black')
    for side in (-1, 1):
        part('LinkWall', (length, 19, 2), (cx, y + 6.5, z + side * 5.5), 'black')
    ROUTE.append({'x': x0 + 2, 'y': y, 'z': z, 'jump': False, 'sec': sec, 'gate': sec})
    ROUTE.append({'x': x1 - 2, 'y': y, 'z': z, 'jump': False, 'sec': sec})


def close(p, x0, last=False, x1=None, shaft=False, dense=1, column=None, door=None):
    """Walls, ceiling, lamps and the two end walls for the room `p` has just finished; returns where the next starts.
    `door` = (width, height) of the way out of the last room, which has no plate and no link."""
    name = p.section
    x1 = p.x if x1 is None else x1
    top = room(name, x0, x1, shaft=shaft, dense=dense, column=column)
    if last and door:
        wall_with_door(x1 + 4, name, top, p.z, p.y, door_w=door[0], door_h=door[1])
        return top
    wall_with_door(x1 + 4, name, top, p.z if not last else 300, p.y if not last else -200)
    if last:
        return None
    for row in PLATES:
        if row['sec'] == name:
            row['gate'] = [round(x1 + 4, 2), round(p.y, 2), round(p.z, 2)]
    link(x1 + 8, x1 + 38, p.y, p.z, name)
    return x1 + 46, p.y, p.z, top


def open_room(name, start, mirror=1):
    x, y, z = start
    p = Path_(name, x, y, z)
    p.x0, p.mirror = x, mirror
    return p


# ROSE: four broad practice jumps, the first with a recoverable pit.
p=open_room('rose',(4.,0.,0.)); START=(16.,0.,0.)
p.rest(30,26).ball(9,8).ball(15,-9,1.9).ball(6,-5,1.)
p.plat(18,8).ball(10,2)
for k in range(4):
    p.gap(3.3,practice=k==0).plat(14,8)
    if k==1:
        p.rest(16,18).ball(8,5,1.6).ball(12,-6)
    if k<3:
        p.stairs(3,3,1,8).plat(8,8)
p.rest(20,18).ball(9,5,1.2)
p.plaza().ball(8,10,2.2).ball(14,-11,1.3)
wall_with_door(p.x0-8,'rose',EXTENT['rose'][5]+64,300,-200)
nxt=close(p,p.x0-4)

# BLUE: L ledges; two offset rows of four jumps; four nested frames kept.
p=open_room('blue',nxt[:3]); blue_in=(p.z,p.y); Y=p.y
p.rest(24,20).ball(8,6)
p.corner(90,9).plat(10,8).corner(-90,9)
for k in range(8):
    if k in (0,4): p.plat(6,8)
    p.gap(3.7).plat(14,8)
    if k==3:
        p.corner(-90,9).plat(10,8).corner(90,9)
p.rest(22,18).ball(9,-5,1.8).ball(13,6,1.1)
corridor_x=p.x
for k,(w,h) in enumerate(((34,36),(26,28),(18,20),(12,14))):
    fx=corridor_x+k*14; side_w=HALF-w/2+8
    for side in (-1,1):
        part('Frame',(12,Y+72-BOTTOM,side_w),(fx+6,(Y+72+BOTTOM)/2,p.z+side*(w/2+side_w/2)),'blue')
    part('Frame',(12,72-h,w),(fx+6,Y+h+(72-h)/2,p.z),'blue')
p.plat(58,8).ball(20,-2.2).ball(14,1.8,1.2)
p.plaza().ball(10,-10,2.).ball(6,11)
nxt=close(p,p.x0-4); wall_with_door(p.x0-4,'blue',nxt[3],*blue_in)

# AMBER: touching 12x12 blocks, walking +/-1 and marked +3 hops.
p=open_room('amber',nxt[:3]); amber_in=(p.z,p.y)
p.rest(20,18).ball(8,5).ball(11,-6,1.)
for k,dy in enumerate((1,1,3,-1,-1,-1,3,1,-1,-1,1,-1)):
    if dy==3:
        p.way(-.9)
    p.y+=dy
    p.plat(12,12,'Step')
    if dy==3:
        ROUTE[-2].update(jump=True,hop=True)
    if k in (3,7):
        p.rest(12,16)
        if k==3: p.ball(8,4,1.5)
p.plat(8,8).gap(3.8).plat(14,8)
p.rest(18,14).ball(7,-4,1.2)
p.plaza().ball(9,10,1.8)
nxt=close(p,p.x0-4); wall_with_door(p.x0-4,'amber',nxt[3],*amber_in)

# MINT: two forks, two unguarded beam jumps each; a no-jump guarded bypass.
p=open_room('mint',nxt[:3]); mint_in=(p.z,p.y)
p.rest(18,16).ball(7,4)
for fork in range(2):
    # Wide branch/join squares attach the detour outside their side edges.
    bx,by,bz=p.point(6)
    p.rest(12,12)
    branch=ROUTE[-2].copy(); branch.update(x=bx,y=by,z=bz)
    left=p.x
    p.plat(10,4.4,beam=True).gap(3.6).plat(14,8)
    p.plat(10,4.4,beam=True).gap(3.6).plat(14,8)
    jx,jy,jz=p.point(6)
    p.rest(12,12)
    if fork==0: p.ball(8,4,1.3)
    points=[]
    q=Path_('mint',bx,by,bz+6,90,sink=points)
    mark('mint',bx,by,bz,sink=points)
    q.plat(12,6).turn(-90,9)
    # q's east-going segment ends before the final joint.
    q.plat(jx-4.5-q.x,6).turn(-90,9)
    q.plat(q.z-(jz+6),6)
    mark('mint',jx,jy,jz,sink=points)
    ALTS.append(dict(sec='mint',points=points))
p.plaza().ball(8,-10,1.6)
nxt=close(p,p.x0-4); wall_with_door(p.x0-4,'mint',nxt[3],*mint_in)

# VIOLET: broad, touching descending terraces and two level jumps, bent on squares.
p=open_room('violet',nxt[:3]); violet_in=(p.z,p.y)
p.rest(22,14)
for k in range(8):
    p.y-=2.5
    p.plat(14,8,'Terrace')
    if k in (1,5):
        p.gap(3.8).plat(14,8)
    if k in (2,5):
        p.rest(12,12)
    if k==2:
        p.corner(90,9).plat(15,8).corner(-90,9)
    if k==5:
        p.corner(-90,9).plat(15,8).corner(90,9)
p.plaza()
nxt=close(p,p.x0-4); wall_with_door(p.x0-4,'violet',nxt[3],*violet_in)

# CORAL: continuous stairs along three well walls, with corner landings.
SHAFT=140.
cx0,cy0,cz0=nxt[:3]
p=Path_('coral',cx0+4.5,cy0,cz0-6,90); p.x0=cx0
coral_in=(cz0,cy0); p.outer=None
p.rest(12,12)
p.stairs(10,3,.7,6).plat(9,6)
p.corner(-90,9)
p.stairs(20,3,.7,6).rest(12,12)
p.stairs(5,2.5,.7,6).corner(-90,9)
p.stairs(10,3,.7,6).plat(9,6).corner(90,9)
p.plaza()
nxt=close(p,cx0-4,shaft=True); wall_with_door(cx0-4,'coral',nxt[3],*coral_in)

# ORANGE: two interleaved square coils, with two straight mid-flight gaps per arm.
p=open_room('orange',nxt[:3]); orange_in=(p.z,p.y)
p.rest(14,10).plat(6,6)
p.corner(-90,9)
ocx=p.x+28; ocz=0.

def coil_vertex(p,x,z,next_heading,gap=False):
    dx,dz=p.dir()
    assert abs((x-p.x)*(-dz)+(z-p.z)*dx)<.001, f'orange: piece {len(FOOT)} coil vertex is off its heading'
    distance=math.hypot(x-p.x,z-p.z)-4.5
    assert distance>0, f'orange: piece {len(FOOT)} reversed coil segment'
    if gap:
        pre=max(6.,(distance-3.8-14)/2)
        tail=distance-pre-3.8-14
        assert tail>=0, f'orange: piece {len(FOOT)} cannot fit the straight landing'
        p.plat(pre,6).gap(3.8).plat(14,8)
        if tail>.01: p.plat(tail,6)
    else:
        p.plat(distance,6)
    p.corner((next_heading-p.h+180)%360-180,9)

coil_vertex(p,ocx-28,-33.2015,0)
coil_vertex(p,ocx+16,-33.2015,90,True)
coil_vertex(p,ocx+16,23.2015,180,True)
coil_vertex(p,ocx,23.2015,270)
p.rest(37.403,9).ball(8,2.5,1.5).ball(13,-2.5,1.1)
p.corner(-90,9)
coil_vertex(p,ocx-16,-23.2015,90)
coil_vertex(p,ocx-16,33.2015,0,True)
coil_vertex(p,ocx+28,33.2015,-90,True)
coil_vertex(p,ocx+28,0,0)
p.h=0
p.plaza()
nxt=close(p,p.x0-4,shaft=True); wall_with_door(p.x0-4,'orange',nxt[3],*orange_in)


def square_stair(p,cx,cz,column,turns,w0,w1,gaps):
    """Four-sided flights: straight missing stretches, level catch runs and square
    corner checkpoints. Each flight rises on touching broad treads. The stair is
    attached around the original pillar; STACKED is the existing thin-part exemption.
    The constant centre line lets the Ivory treads taper without a sideways jump.
    """
    radius=column+w0/2-.4
    p.outer=None # the ground approach has guards on both sides
    # Straight in from the west door to the WEST foot. `turns` ends on a half, so the stair leaves on the east
    # side and nobody walks round the whole pillar first (the first v4 looped 215 studs round it to an east foot).
    assert abs(p.z-cz)<.001 and abs(4*turns%4-2)<1e-9, f'{p.section}: the stair needs a room on its axis and turns ending on a half'
    p.plat(cx-radius-4.5-p.x,6)
    # The pillar is square, so every flight is fixed to it along its whole inner edge. A stair that narrows on a
    # constant centre line (Ivory) leaves a slot there higher up: `both` guards its inner side as well.
    p.outer=1; p.both=w0!=w1
    p.corner(90,9)
    # Foot is the midpoint of the west side; half-side first and last.
    p.h=90; p.way()
    segments=[radius]+[2*radius]*(round(4*turns)-1)+[radius]
    for side,length in enumerate(segments):
        progress=side/max(1,len(segments)-1)
        width=w1 if side>=len(segments)-2 else w0+(w1-w0)*progress
        # At a corner the preceding square consumes half its width on both arms.
        run=length-9
        has_gap=side in gaps
        catch=14. if has_gap else min(11.,run); take=6.; gap=3.6
        climb=run-catch-(take+gap if has_gap else 0)
        if climb>0:
            steps=max(1,int(climb/(1.2 if p.section=='ivory' else 3)))
            p.stairs(steps,climb/steps,.9,width)
        if has_gap:
            p.plat(take,max(7,width)).gap(gap).plat(catch,max(7,width))
        else:
            p.plat(catch,max(7,width))
        p.checkpoint(*p.point(-catch/2),'rest',at=len(ROUTE)-2)
        if side<len(segments)-1:
            p.corner(-90,9)
    assert abs(abs(p.h-90)-360*turns)<1e-6, f'{p.section}: piece {p.last["i"]} has the wrong number of turns'
    # End at the east midpoint, turn outward on a level top joint.
    p.outer=None; p.both=False
    p.turn(90,9)
    return p.y,radius

# CRIMSON: two and a half turns round a square pillar, five straight gaps, the original ruin/bridge recipe.
p=open_room('crimson',nxt[:3]); crimson_in=(p.z,p.y)
p.rest(14,10)
PILLAR,C_TREAD_W=30.,7.
rcx,rcz=p.x0+74,0.
y,rt=square_stair(p,rcx,rcz,PILLAR,2.5,7,7,{1,3,5,7,9})
part('Pillar',(PILLAR*2,y+RISE-BOTTOM,PILLAR*2),(rcx,(y+RISE+BOTTOM)/2,rcz),'crimson')      # square, up into the dark
ruin=random.Random(88); ang,ry=math.radians(-34.),y+4.
for k in range(26):
    ang-=math.radians(8.); ry+=.9
    if ruin.random()<.45: continue
    rr=PILLAR+5./2-.4
    part('Ruin',(4.6,1.4,5.*ruin.uniform(.5,1)),(rcx+rr*math.cos(ang),ry-.7,rcz+rr*math.sin(ang)),
         'crimson',yaw=math.degrees(ang)-90,collide=False)
bridge=9.
p.plat(bridge+1,5)
p.plaza()
nxt=close(p,p.x0-4,shaft=True,column=(rcx,rcz)); wall_with_door(p.x0-4,'crimson',nxt[3],*crimson_in)

# TEAL: 10-stud squares on a 14.4 grid. Ten main jumps and a four-jump detour.
p=open_room('teal',nxt[:3]); teal_in=(p.z,p.y)
p.rest(12,12)
p.plat(10,10,'Top')
tops=[p.last]
for k in range(10):
    # Two right-angle bends are entirely on the preceding square top.
    heading=90 if k==3 else (-90 if k==6 else 0)
    if heading!=p.h:
        f=p.last; p.h=heading
        dx,dz=p.dir(); p.x=f['x']+dx*5; p.z=f['z']+dz*5
        p.way(-6)
    p.gap(4.4).plat(10,10,'Top')
    tops.append(p.last)
    if k in (1,4,7):
        p.checkpoint(p.last['x'],p.y,p.last['z'],'rest',at=len(ROUTE)-2)
# Alternative from top 0 to top 2 on the south row (4 jumps).
a,b=tops[0],tops[2]
points=[]; mark('teal',a['x'],a['top'],a['z']+1,sink=points)
q=Path_('teal',a['x'],a['top'],a['z']-5,-90,sink=points); q.last=a
for heading in (-90,0,0,90):
    old_heading=q.h
    q.h=heading
    if q.last:
        dx,dz=q.dir(); q.x=q.last['x']+dx*5; q.z=q.last['z']+dz*5
    if heading!=old_heading: q.way(-6)
    q.gap(4.4)
    if heading==90:
        # The last landing is the existing main-route top, never a duplicate solid.
        q.pending['landing']=b['i']; q.pending['end']=[q.x,q.y,q.z]
        q.way(2,jump=True); q.way(5); q.pending=None
    else:
        q.plat(10,10,'Top')
ALTS.append(dict(sec='teal',points=points))
# Spare catch tops beside the path, not colliding with either chain.
for f in (tops[5],tops[8]):
    register('teal','Top',10,10,f['x'],f['top'],f['z']+28.8,0,spare=True)
p.h=0; f=p.last; p.x=f['x']+5; p.z=f['z']
p.plaza()
nxt=close(p,p.x0-4,dense=3); wall_with_door(p.x0-4,'teal',nxt[3],*teal_in)

# IVORY: five and a half turns round a square column, width 10 -> 5, eight missing stretches and broad catch runs.
ix0,iy0,iz0=nxt[:3]
p=open_room('ivory',nxt[:3]); ivory_in=(p.z,p.y)
p.rest(12,9)
COLUMN,I_W0,I_W1=12.,10.,5.
icx,icz=ix0+SHAFT/2,0.
y,rt=square_stair(p,icx,icz,COLUMN,5.5,I_W0,I_W1,{1,3,5,7,9,11,13,15})
YT=y; x1=ix0+SHAFT
# Platform on the column, deck, pier and great doorway retain their dimensions.
part('Pillar',(COLUMN*2,YT-BOTTOM,COLUMN*2),(icx,(YT+BOTTOM)/2,icz),'ivory')      # square: its top is the platform
FOOT.append(dict(sec='ivory',i=sum(f['sec']=='ivory' for f in FOOT)+1,n='Column',x=icx,z=icz,l=COLUMN*2,w=COLUMN*2,yaw=0.,top=YT,part=len(PARTS)-1))
register('ivory','Rest',16,14,icx+16,YT,icz,0,thin=True)
# The top stair approaches the deck on its east edge, then returns to the column.
mark('ivory',icx+18,YT,icz)
mark('ivory',icx+6,YT,icz)
p.checkpoint(icx,YT,icz,at=len(ROUTE)-1)
mark('ivory',icx+30,YT,icz); mark('ivory',x1-12,YT,icz)
register('ivory','Walk',x1-(icx+24),12,(icx+24+x1)/2,YT,icz,0)
orb(icx,YT+21,icz,'ivory')
p.x,p.y,p.z,p.h=x1,YT,icz,0.
DOOR_IN=(14.,16.)
close(p,ix0,last=True,x1=x1,shaft=True,column=(icx,icz),door=DOOR_IN)
wall_with_door(ix0-4,'ivory',EXTENT['ivory'][5]+RISE,*ivory_in)

WX = x1 + 8.0                 # the corridor begins at the east face of the well's wall
L, HALF_W, H = 226.0, 13.0, 16.4
EX = WX + L                   # the west face of the end wall
ROOM_LEN = 30.0
SHELL = L + 4 + ROOM_LEN + 4
solid('FinaleFloor', SHELL, 72, YT, WX + SHELL / 2, 0, 0, 'stone')                 # carried from the bottom of the drop, like everything
part('FinaleCeiling', (SHELL, 3, 72), (WX + SHELL / 2, YT + H + 1.6, 0), 'black')
for side in (-1, 1):
    part('FinaleShell', (SHELL, H + 3.2, 3), (WX + SHELL / 2, YT + (H + 3.2) / 2 - 0.1, side * 34.6), 'black')
    # a closing wall: it fills its side from the corridor's face to the shell, and comes in until the two meet
    part('CrusherWall', (L - 0.4, H, 20.0), (WX + L / 2, YT + H / 2, side * (HALF_W + 10.0)), 'slab', extra={'g': 'Finale', 'side': side})
# the block waits inside the wall over the doorway; the gate stands 28 studs in and sinks into the floor
part('CrusherBlock', (7.6, H, DOOR_IN[0] - 0.1), (x1 + 4, YT + DOOR_IN[1] + 0.3 + H / 2, 0), 'slab', extra={'g': 'Finale'})
part('CrusherGate', (2.4, H, HALF_W * 2 + 0.4), (WX + 28.0, YT + H / 2, 0), 'slab', extra={'g': 'Finale'})

def end_slab(z0, z1, y0, y1):
    part('FinaleWall', (4.0, y1 - y0, z1 - z0), (EX + 2, YT + (y0 + y1) / 2, (z0 + z1) / 2), 'stone')
for z0, z1 in ((-36.0, -12.5), (12.5, 36.0), (-5.5, -4.0), (4.0, 5.5)):       # the ends and the piers beside the door
    end_slab(z0, z1, 0.0, H + 0.1)
end_slab(-4.0, 4.0, 13.0, H + 0.1)                                            # over the door (8 wide, 13 high)
for z0, z1 in ((-12.5, -5.5), (5.5, 12.5)):                                    # a window each side: the room looks back down the corridor
    end_slab(z0, z1, 0.0, 2.5)
    end_slab(z0, z1, 10.5, H + 0.1)
    part('FinaleGlass', (0.8, 8.0, 7.0), (EX + 2, YT + 6.5, (z0 + z1) / 2), 'glass', material='Glass', extra={'t': 0.6})
for side in (-1, 1):                                                           # the small room the walls do not reach
    part('FinaleWall', (ROOM_LEN, H + 0.1, 4), (EX + 4 + ROOM_LEN / 2, YT + (H + 0.1) / 2, side * 15.0), 'stone')
FX = EX + 4 + ROOM_LEN
part('FinaleWall', (4, H + 0.1, 72), (FX + 2, YT + (H + 0.1) / 2, 0), 'stone')
for side in (-1, 1):                                                           # the lit doorway out of the level
    part('ExitFrame', (3, 14, 3), (FX - 1.2, YT + 7, side * 5.5), 'ivory')
part('ExitFrame', (3, 3, 14), (FX - 1.2, YT + 14.5, 0), 'ivory')
part('ExitDark', (1, 13, 8), (FX - 0.2, YT + 6.5, 0), 'black')
finish = (FX - 4.5, YT, 0.0)
for i in range(int(L // 28) + 1):
    light((WX + 12 + i * 28, YT + 13.4, 0), 34, 0.4, name='CrusherLight')
light((EX + 4 + ROOM_LEN / 2, YT + 12.5, 0), 34, 0.55)
light((FX - 5, YT + 9, 0), 20, 0.7)
FINALE.update({
    'floor': round(YT, 2), 'height': H, 'half': HALF_W, 'z': 0.0,
    'entry_x': round(x1 + 4, 2),        # the block's doorway
    'inside_x': round(WX + 5.0, 2),     # past this line a body is in the corridor
    'gate_x': round(WX + 28.0, 2), 'end_x': round(EX, 2),
    'room': [round(EX + 4, 2), round(FX, 2), 13.0],
    'reentry': [round(EX + 14, 2), round(YT, 2), 0.0],
    'block_drop': DOOR_IN[1] + 0.3, 'wall_travel': HALF_W,
})
TOTAL = WX + SHELL


def edge_strip(f, x, y, z, heading, inset):
    dx,dz=math.cos(math.radians(heading)),math.sin(math.radians(heading))
    part('Edge',(.5,.16,f['w']-.6),(x+dx*inset,y-.02,z+dz*inset),'edge',yaw=heading,
         material='Neon',collide=False,extra={'sec':f['sec']})


def cut_interval(f, x, z, dx, dz, length, grow=.311):
    """Parameter interval inside a rectangle expanded by guard half-thickness.
    All rebuilt pieces are axis aligned; this also works for rotated footprints.
    """
    a,b=local(f,x,z)
    c,s=math.cos(math.radians(f['yaw'])),math.sin(math.radians(f['yaw']))
    da,db=c*dx+s*dz,-s*dx+c*dz
    lo,hi=0.,length
    for value,delta,half in ((a,da,f['l']/2+grow),(b,db,f['w']/2+grow)):
        if abs(delta)<1e-10:
            if abs(value)>half: return None
        else:
            u,v=(-half-value)/delta,(half-value)/delta
            lo,hi=max(lo,min(u,v)),min(hi,max(u,v))
    return (max(0,lo),min(length,hi)) if hi>lo+1e-7 else None


def guard_run(sec,x,z,heading,length,top):
    dx,dz=math.cos(math.radians(heading)),math.sin(math.radians(heading))
    runs=[(0.,length)]
    for f in FOOT:
        if f['sec']!=sec or abs(top-f['top'])>8.001: continue
        interval=cut_interval(f,x,z,dx,dz,length)
        if not interval: continue
        low,high=interval; nxt=[]
        for a,b in runs:
            if high<=a or low>=b: nxt.append((a,b)); continue
            if low>a+.02: nxt.append((a,low))
            if high<b-.02: nxt.append((high,b))
        runs=nxt
    for a,b in runs:
        if b-a<.04: continue
        GUARDS.append(dict(sec=sec,x=x+dx*(a+b)/2,z=z+dz*(a+b)/2,l=b-a,w=.6,yaw=heading,top=top))
        GUARD_COVERAGE.append((sec,x+dx*a,z+dz*a,heading,b-a,top))


for f in FOOT:
    if f['n'] in ('Rest','Plaza','Column') or f.get('beam') or (f['w']>=9 and f['n']!='Joint' and f['sec'] not in STACKED): continue
    if f['n']=='Joint':
        headings=f.get('outer_heads',[0,90,180,270])
        if f.get('outer') is None or f.get('both'): headings=[0,90,180,270]
        for heading in set(round(h%360,4) for h in headings):
            c,s=math.cos(math.radians(heading)),math.sin(math.radians(heading))
            side=f.get('outer') or 1
            x=f['x']-c*f['l']/2-s*side*(f['w']/2+.32)
            z=f['z']-s*f['l']/2+c*side*(f['w']/2+.32)
            guard_run(f['sec'],x,z,heading,f['l'],f['top'])
    else:
        c,s=math.cos(math.radians(f['yaw'])),math.sin(math.radians(f['yaw']))
        for side in ((f['outer'],) if f.get('outer') is not None and not f.get('both') else (-1,1)):
            x=f['x']-c*f['l']/2-s*side*(f['w']/2+.32)
            z=f['z']-s*f['l']/2+c*side*(f['w']/2+.32)
            guard_run(f['sec'],x,z,f['yaw'],f['l'],f['top'])

for g in GAPS:
    sec=g['sec']; feet={f['i']:f for f in FOOT if f['sec']==sec}
    take,land=feet[g['takeoff']],feet[g['landing']]
    message=f'{sec}: pieces {take["i"]}->{land["i"]}'
    h=g['yaw']; c,s=math.cos(math.radians(h)),math.sin(math.radians(h))
    sx,sy,sz=g['start']; ex,ey,ez=g['end']
    assert abs((ex-sx)*(-s)+(ez-sz)*c)<.001, message+' gap changes centre line'
    assert abs((land['x']-sx)*(-s)+(land['z']-sz)*c)<.001, message+' landing centre line turns'
    assert abs((take['x']-sx)*(-s)+(take['z']-sz)*c)<.001, message+' takeoff centre line turns'
    square=lambda f: abs(f['l']-f['w'])<1e-6 and abs(f['yaw']%90)<1e-6
    assert square(take) or abs((take['yaw']-h+180)%360-180)<.001, message+' takeoff heading differs'
    assert square(land) or abs((land['yaw']-h+180)%360-180)<.001, message+' landing heading differs'
    assert take['l']>=6 and take['w']>=(4 if take.get('beam') else 6),message+' short/narrow approach'
    assert land['w']>=7 and (land['l']>=11 or sec=='teal'),message+' small landing'
    # Rectangle, shrunk by 0.3, at both speeds and both takeoff points with each aim error.
    for speed in (16,26):
        for early in (0,-2):
            if sec=='teal' and speed==26 and early==-2: continue
            for aim in (-12,0,12):
                r=reach_at(speed,g['dy']); angle=math.radians(h+aim)
                x=sx+c*early+r*math.cos(angle); z=sz+s*early+r*math.sin(angle)
                assert inside(land,x,z,.3),message+f' misses landing: speed {speed}, takeoff {early}, aim {aim}'
    edge_strip(take,sx,sy,sz,h,-.45)
    edge_strip(land,ex,ey,ez,h,.45)
    if not take.get('beam'):
        width=min(take['w'],land['w'])
        for side in ((take['outer'],) if take.get('outer') is not None and not take.get('both') else (-1,1)):
            guard_run(sec,sx-s*side*(width/2+.32),sz+c*side*(width/2+.32),h,g['gap'],min(sy,ey))

# Validate the exported waypoints, including the straight final six studs.
for g in GAPS:
    stream=next(a['points'] for a in ALTS if a['sec']==g['sec'] and any(r['jump'] and
                 math.hypot(r['x']-(g['end'][0]+2*math.cos(math.radians(g['yaw']))),r['z']-(g['end'][2]+2*math.sin(math.radians(g['yaw']))))<.01 for r in a['points'])) if g['alt'] else ROUTE
    c,s=math.cos(math.radians(g['yaw'])),math.sin(math.radians(g['yaw']))
    target=(g['end'][0]+2*c,g['end'][2]+2*s)
    i=next(i for i,r in enumerate(stream) if r['sec']==g['sec'] and r['jump'] and not r.get('hop') and abs(r['y']-g['end'][1])<.002 and math.hypot(r['x']-target[0],r['z']-target[1])<.01)
    before=stream[i-1]
    msg=f'{g["sec"]}: pieces {g["takeoff"]}/{g["landing"]}'
    assert math.hypot(before['x']-(g['start'][0]-.9*c),before['z']-(g['start'][2]-.9*s))<.002,msg+' takeoff waypoint is not 0.9 before edge'
    assert abs(stream[i]['y']-g['end'][1])<.002,msg+' landing waypoint height differs'
    straight=.9
    for a,b in reversed(list(zip(stream[:i-1],stream[1:i]))):
        dx,dz=b['x']-a['x'],b['z']-a['z']
        if abs(a['y']-before['y'])>.002 or abs(b['y']-before['y'])>.002 or abs(dx*(-s)+dz*c)>.002 or dx*c+dz*s<-.002: break
        straight+=math.hypot(dx,dz)
    assert straight>=5.999,msg+f' only {straight:.2f} straight level studs before gap'

# Coalesce exactly collinear, level adjacent guard runs; steps retain their surface height.
merged=[]
for g in GUARDS:
    h=g['yaw']%180; c,s=math.cos(math.radians(h)),math.sin(math.radians(h))
    g['yaw']=h
    key=(g['sec'],round(g['top'],3),round(h,3),round(-s*g['x']+c*g['z'],3))
    mid=c*g['x']+s*g['z']
    merged.append((key,mid-g['l']/2,mid+g['l']/2,g))
merged.sort(key=lambda item:(item[0],item[1]))
GUARDS=[]
for key,a,b,g in merged:
    if GUARDS and GUARDS[-1]['key']==key and a<=GUARDS[-1]['b']+.025:
        GUARDS[-1]['b']=max(GUARDS[-1]['b'],b)
    else:
        GUARDS.append(dict(key=key,a=a,b=b,**g))
for g in GUARDS:
    c,s=math.cos(math.radians(g['yaw'])),math.sin(math.radians(g['yaw']))
    offset=g['key'][3]; mid=(g['a']+g['b'])/2
    g.update(x=c*mid-s*offset,z=s*mid+c*offset,l=g['b']-g['a'])
    row=part('Guard',(g['l'],8,.6),(g['x'],g['top']+3.5,g['z']),'black',yaw=g['yaw'],extra={'t':1.,'sec':g['sec']})
    g['part']=len(PARTS)-1
    # Validate the rounded geometry that the importer actually uses.
    g.update(x=row['p'][0],z=row['p'][2],l=row['s'][0],yaw=row['yaw'])

# Guard runs required by each narrow side and gap survive trimming, merging and
# JSON rounding. Exposed portions are sampled at 0.5; overlaps with joints and
# wider landings were removed before this coverage record, as required.
for sec,x,z,heading,length,top in GUARD_COVERAGE:
    dx,dz=math.cos(math.radians(heading)),math.sin(math.radians(heading))
    guards=[g for g in GUARDS if g['sec']==sec and abs(g['top']-top)<.001]
    for j in range(math.ceil(length/.5)+1):
        t=length*j/math.ceil(length/.5)
        assert any(inside(g,x+dx*t,z+dz*t,-.003) for g in guards),f'{sec}: guard run at {x:.2f},{z:.2f} has an uncovered sample {j}'

# Check every guard against every walkable top in its vertical band.
for g in GUARDS:
    for f in FOOT:
        if f['sec']==g['sec'] and abs(g['top']-f['top'])<=8.001:
            assert not overlap(g,f,-.001),f'{g["sec"]}: Guard {g["part"]} stands inside piece {f["i"]}'


def route_length(points):
    return sum(math.hypot(b['x']-a['x'],b['z']-a['z']) for a,b in zip(points,points[1:]))


def guard_clearance(sec,points):
    guards=[g for g in GUARDS if g['sec']==sec]
    for i,(a,b) in enumerate(zip(points,points[1:])):
        length=math.hypot(b['x']-a['x'],b['z']-a['z'])
        for j in range(max(1,math.ceil(length/.5))+1):
            t=j/max(1,math.ceil(length/.5)); x=a['x']+(b['x']-a['x'])*t; z=a['z']+(b['z']-a['z'])*t
            y=a['y']+(b['y']-a['y'])*t
            for g in guards:
                if y+5<g['top']-.5 or y>g['top']+7.5: continue
                u,v=local(g,x,z)
                distance=math.hypot(max(0,abs(u)-g['l']/2),max(0,abs(v)-.3))
                assert distance>=1.2-1e-6,f'{sec}: route segment {i}, sample {j} hits Guard {g["part"]}, clearance {distance:.3f}'


# Stacked flights must leave a body and its jumping apex room below the next turn.
for sec in STACKED:
    stair=[f for f in FOOT if f['sec']==sec and f.get('outer')==1]
    for i,a in enumerate(stair):
        for b in stair[i+1:]:
            if b['i']-a['i']>4 and overlap(a,b,-.01):
                assert abs(b['top']-a['top'])>=15,f'{sec}: pieces {a["i"]}/{b["i"]} have only {abs(b["top"]-a["top"]):.1f} headroom'

# Decoration clearance is checked again using the rounded JSON geometry.
for i,row in enumerate(PARTS):
    if row['n']!='Monolith': continue
    m=dict(x=row['p'][0],z=row['p'][2],l=row['s'][0],w=row['s'][2],yaw=row['yaw'])
    for f in FOOT:
        if f['sec']==row['c']:
            assert not overlap(m,f,6.998),f'{f["sec"]}: Monolith {i} crowds piece {f["i"]}'

# Safe landing checkpoints also bound the early lessons without long retries.
for g in GAPS:
    if g['alt']: continue
    f=next(f for f in FOOT if f['sec']==g['sec'] and f['i']==g['landing'])
    if any(cp['sec']==g['sec'] and abs(cp['y']-f['top'])<.01 and inside(f,cp['x'],cp['z'],3) for cp in CHECKPOINTS): continue
    at=next(i for i,r in enumerate(ROUTE) if r['sec']==g['sec'] and r['jump'] and not r.get('hop') and
            math.hypot(r['x']-(g['end'][0]+2*math.cos(math.radians(g['yaw']))),r['z']-(g['end'][2]+2*math.sin(math.radians(g['yaw']))))<.01)
    helper=Path_(g['sec'],f['x'],f['top'],f['z'],g['yaw'])
    helper.checkpoint(f['x'],f['top'],f['z'],at=at)

# Bypass checkpoints use the corresponding main progress index; their physical
# centres and yaw are on the real alternative pads. Low remains the historical
# main-route computation (all alternatives here are level).
for alt in ALTS:
    sec=alt['sec']; points=alt['points']
    pads=[f for f in FOOT if f['sec']==sec and f.get('alt') and
          (f['n']=='Joint' if sec=='mint' else f['n']=='Top') and
          (sec=='teal' or any(math.hypot(r['x']-f['x'],r['z']-f['z'])<.002 for r in points))]
    if sec=='teal': pads=pads[1:2]
    for f in pads:
        index=min((i for i,r in enumerate(ROUTE) if r['sec']==sec),
                  key=lambda i:abs(ROUTE[i]['x']-f['x']))
        yaw=0 if sec=='mint' and f==pads[0] else (-90 if sec=='mint' else 0)
        cp=dict(sec=sec,x=round(f['x'],3),y=round(f['top'],3),z=round(f['z'],3),
                at=index,yaw=yaw,kind='corner' if sec=='mint' else 'rest',alt=True)
        CHECKPOINTS.append(cp)

# A checkpoint's historical low value looks through to the next checkpoint (+2 points).
CHECKPOINTS.sort(key=lambda cp:cp['at'])
for i,cp in enumerate(CHECKPOINTS):
    end=CHECKPOINTS[i+1]['at']+2 if i+1<len(CHECKPOINTS) else len(ROUTE)
    cp['low']=round(min(r['y'] for r in ROUTE[cp['at']:end]),2); cp['i']=i
    supports=[f for f in FOOT if f['sec']==cp['sec'] and abs(f['top']-cp['y'])<.001 and
              min(f['l'],f['w'])>=7 and inside(f,cp['x'],cp['z'],3.)]
    column_top=cp['sec']=='ivory' and abs(cp['x']-icx)<.001 and abs(cp['z']-icz)<.001 and abs(cp['y']-YT)<.001
    assert supports or column_top,f'{cp["sec"]}: checkpoint {i} lacks a level 7x7 support / 3-stud edge clearance'

for sec in SHARE:
    feet=[f for f in FOOT if f['sec']==sec]
    points=[r for r in ROUTE if r['sec']==sec and 'gate' not in r]
    # Link points are outside the room; exclude them from room metrics/checkpoint cadence.
    e=EXTENT[sec]
    points=[r for r in points if e[0]-.01<=r['x']<=e[1]+.01]
    gs=[g for g in GAPS if g['sec']==sec]
    cps=[cp for cp in CHECKPOINTS if cp['sec']==sec and not cp.get('alt')]
    assert len(gs)<=BUDGET[sec],f'{sec}: piece all: gap budget {len(gs)} > {BUDGET[sec]}'
    if sec in LENGTH_CAP:
        assert route_length(points)<=LENGTH_CAP[sec],f'{sec}: piece all: route too long {route_length(points):.1f}'
        assert e[1]-e[0]<=LENGTH_CAP[sec],f'{sec}: piece all: room too long {e[1]-e[0]:.1f}'
    for f in feet:
        minimum=7 if sec in ('rose','blue','amber') else (4 if f.get('beam') else 5)
        assert f['w']>=minimum,f'{sec}: piece {f["i"]} width {f["w"]} < {minimum}'
        if sec not in STACKED:
            row=PARTS[f['part']]
            assert abs(row['p'][1]-row['s'][1]/2-BOTTOM)<.0011,f'{sec}: piece {f["i"]} floats'
    assert cps and cps[0]['kind']=='rest',f'{sec}: first checkpoint must be entrance rest'
    for a,b in zip(cps,cps[1:]):
        walked=route_length(ROUTE[a['at']:b['at']+1])
        jumps=sum(r['jump'] and not r.get('hop') for r in ROUTE[a['at']+1:b['at']+1])
        assert walked<=90.001,f'{sec}: checkpoints {a["i"]}/{b["i"]} are {walked:.1f} route studs apart'
        assert jumps<=3,f'{sec}: checkpoints {a["i"]}/{b["i"]} have {jumps} gaps between them'
    guard_clearance(sec,points)
    for alt in [a for a in ALTS if a['sec']==sec]:
        guard_clearance(sec,alt['points'])
        for endpoint in (alt['points'][0],alt['points'][-1]):
            assert any(inside(f,endpoint['x'],endpoint['z']) and not f.get('alt') and abs(f['top']-endpoint['y'])<.01 for f in feet),f'{sec}: alt endpoint is not on the main route'
    for alt in [a for a in ALTS if a['sec']==sec]:
        pts=alt['points']; cumulative=[0.]
        for a,b in zip(pts,pts[1:]): cumulative.append(cumulative[-1]+math.hypot(b['x']-a['x'],b['z']-a['z']))
        stops=[0.,cumulative[-1]]
        for cp in [cp for cp in CHECKPOINTS if cp['sec']==sec]:
            for j,(a,b) in enumerate(zip(pts,pts[1:])):
                dx,dz=b['x']-a['x'],b['z']-a['z']; squared=dx*dx+dz*dz
                if squared<1e-9: continue
                t=((cp['x']-a['x'])*dx+(cp['z']-a['z'])*dz)/squared
                if 0<=t<=1 and math.hypot(a['x']+t*dx-cp['x'],a['z']+t*dz-cp['z'])<.002:
                    stops.append(cumulative[j]+t*math.sqrt(squared))
        stops=sorted(set(round(v,3) for v in stops))
        for a,b in zip(stops,stops[1:]):
            assert b-a<=90.001,f'{sec}: alternative has {b-a:.1f} studs between checkpoints'
            assert sum(r['jump'] for j,r in enumerate(pts) if a<cumulative[j]<=b)<=3,f'{sec}: alternative has more than three gaps between checkpoints'
    METRICS[sec]=dict(length=round(route_length(points),1),span=round(e[1]-e[0],1),gaps=len(gs),
                      hardest=max((g['share'] for g in gs),default=0),width=min(f['w'] for f in feet),
                      landing=min((next(f['l'] for f in feet if f['i']==g['landing']) for g in gs),default=None),
                      checkpoints=sum(cp['sec']==sec for cp in CHECKPOINTS),guards=sum(g['sec']==sec for g in GUARDS))
assert sorted(b['r'] for b in BALLS)==sorted([1.4,1.9,1.,1.4,1.6,1.4,1.2,2.2,1.3,1.4,1.8,1.1,1.4,1.2,2.,1.4,1.4,1.,1.5,1.2,1.8,1.4,1.3,1.6,1.5,1.1]),'all rooms: piece balls: original ball counts/radii changed'
assert len(GAPS)<=80,'all rooms: gap count exceeds 80'
assert len(PARTS)+len(BALLS)+len(LIGHTS)+3*len(PLATES)+3<2600,'all rooms: imported part count exceeds 2600'

OUT.mkdir(parents=True,exist_ok=True)
data=dict(origin=[40000,600,0],colours=COLOURS,parts=PARTS,balls=BALLS,lights=LIGHTS,route=ROUTE,
          checkpoints=CHECKPOINTS,plates=PLATES,start=START,finish=finish,gaps=GAPS,finale=FINALE,
          sections=list(SHARE),alts=ALTS,footprints=FOOT,extent=EXTENT,metrics=METRICS,
          physics=dict(walk=WALK,sprint=26,jump=JUMP,gravity=GRAVITY,flat_reach=round(reach(0),2),sprint_reach=round(reach_at(26,0),2)))
(OUT/'level5.json').write_text(json.dumps(data))
print('room       route    x-span gaps hardest width landing checkpoints guards')
for sec,m in METRICS.items():
    landing='--' if m['landing'] is None else f'{m["landing"]:.1f}'
    print(f'{sec:8s} {m["length"]:7.1f} {m["span"]:7.1f} {m["gaps"]:4d} {m["hardest"]:6.1%} {m["width"]:5.1f} {landing:>7s} {m["checkpoints"]:11d} {m["guards"]:6d}')
print(f'TOTAL gaps={len(GAPS)}, geometry parts={len(PARTS)}, imported parts={len(PARTS)+len(BALLS)+len(LIGHTS)+3*len(PLATES)+3}, '
      f'room route={sum(m["length"] for m in METRICS.values()):.1f}, x length including finale={TOTAL:.1f}')

# ---------------------------------------------------------------------------------------------- Blender scene
try:
    import bpy
except ImportError:
    bpy = None
if bpy:
    import bmesh
    import numpy as np

    # The plaster: a tileable height field (broad trowel lumps + grain + a few pits), from which the normal,
    # the roughness and a near-white colour map are derived. Roblox tints the colour map with each part's Color,
    # so one set serves all five rooms.
    N = 1024
    rng = np.random.default_rng(55)
    fx = np.fft.fftfreq(N)[:, None]
    fy = np.fft.fftfreq(N)[None, :]
    radius = np.sqrt(fx * fx + fy * fy)

    def band(lo, hi):
        spectrum = np.fft.fft2(rng.standard_normal((N, N))) * ((radius >= lo) & (radius < hi))
        field = np.real(np.fft.ifft2(spectrum))
        return field / np.abs(field).max()

    lumps, trowel, grain = band(0.002, 0.012), band(0.012, 0.05), band(0.08, 0.32)
    pits = np.clip(band(0.03, 0.09) - 0.55, 0, None) * 2.2
    height = 0.55 * lumps + 0.30 * trowel + 0.10 * grain - 0.45 * pits
    height = (height - height.min()) / (height.max() - height.min())
    strength = 2.0
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength * N / 256
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength * N / 256
    inv = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)
    normal = np.stack([-gx * inv * 0.5 + 0.5, -gy * inv * 0.5 + 0.5, inv * 0.5 + 0.5, np.ones_like(inv)], -1)
    shade = 0.90 + 0.10 * height - 0.10 * np.clip(pits, 0, 1)
    colour = np.stack([shade, shade, shade, np.ones_like(shade)], -1)
    rough_v = np.clip(0.80 + 0.14 * grain * 0.5 + 0.10 * (1 - height), 0, 1)
    rough = np.stack([rough_v, rough_v, rough_v, np.ones_like(rough_v)], -1)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    images = {}
    for key,pixels,space in (('colour',colour,'sRGB'),('normal',normal,'Non-Color'),('roughness',rough,'Non-Color')):
        img=bpy.data.images.new(f'l5_plaster_{key}',N,N,alpha=False)
        img.colorspace_settings.name=space
        img.pixels.foreach_set(pixels.astype(np.float32).ravel())
        img.pack()
        images[key]=img
    mats = {}
    for key, rgb in COLOURS.items():
        m = bpy.data.materials.new('L5_' + key)
        tint = (*[(c / 255) ** 2.2 for c in rgb], 1)
        m.diffuse_color = tint
        m.use_nodes = True
        nodes, links = m.node_tree.nodes, m.node_tree.links
        bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        if key in ('orb', 'edge', 'black'):
            bsdf.inputs['Base Color'].default_value = tint
        else:
            coord = nodes.new('ShaderNodeTexCoord')
            scale = nodes.new('ShaderNodeMapping')
            scale.inputs['Scale'].default_value = (0.08, 0.08, 0.08)       # one tile is about 12 studs
            links.new(coord.outputs['Object'], scale.inputs['Vector'])
            def image(name):
                node = nodes.new('ShaderNodeTexImage')
                node.image, node.projection = images[name], 'BOX'
                node.projection_blend = 0.2
                links.new(scale.outputs['Vector'], node.inputs['Vector'])
                return node
            mix = nodes.new('ShaderNodeMixRGB')
            mix.blend_type = 'MULTIPLY'
            mix.inputs['Fac'].default_value = 1.0
            mix.inputs['Color2'].default_value = tint
            links.new(image('colour').outputs['Color'], mix.inputs['Color1'])
            links.new(mix.outputs['Color'], bsdf.inputs['Base Color'])
            links.new(image('roughness').outputs['Color'], bsdf.inputs['Roughness'])
            bump = nodes.new('ShaderNodeNormalMap')
            links.new(image('normal').outputs['Color'], bump.inputs['Color'])
            links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
        mats[key] = m
    col = bpy.data.collections.new('Level5_Void')
    bpy.context.scene.collection.children.link(col)
    cube = bpy.data.meshes.new('L5Cube')
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(cube); bm.free()
    ball = bpy.data.meshes.new('L5Ball')
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.5); bm.to_mesh(ball); bm.free()
    tube = bpy.data.meshes.new('L5Cylinder')
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=40, radius1=0.5, radius2=0.5, depth=1.0); bm.to_mesh(tube); bm.free()
    meshes = {}
    def mesh_for(shape, colour):
        key = (shape, colour)
        if key not in meshes:
            meshes[key] = {'b': cube, 's': ball, 'c': tube}[shape].copy()
            meshes[key].materials.append(mats[colour])
        return meshes[key]
    for i, row in enumerate(PARTS):
        ob = bpy.data.objects.new(f"{row['n']}_{i:04d}", mesh_for(row['sh'], row['c']))
        x, y, z = row['p']
        ob.location = (x, -z, y)                                  # Blender is Z-up; the level's z runs across
        sx, sy, sz = row['s']
        if row['sh'] == 'c':
            ob.scale = (sy, sz, sx)                               # a vertical fold: Roblox length = Blender height
        else:
            ob.scale = (sx, sz, sy)
            ob.rotation_euler = (0, 0, -math.radians(row['yaw']))
        if row.get('t') == 1.0:
            ob.hide_render = True
            ob.hide_viewport = True
        col.objects.link(ob)
    for i, row in enumerate(BALLS):
        ob = bpy.data.objects.new(f'Ball_{i:03d}', mesh_for('s', 'sphere'))
        x, y, z = row['p']
        ob.location, ob.scale = (x, -z, y), (row['r'] * 2,) * 3
        col.objects.link(ob)
    for i, row in enumerate(LIGHTS):
        lamp = bpy.data.lights.new(f'L5Lamp_{i:03d}', 'POINT')
        lamp.energy = 4000 * row['b']
        ob = bpy.data.objects.new(lamp.name, lamp)
        ob.location = (row['p'][0], -row['p'][2], row['p'][1])
        col.objects.link(ob)
    blend = OUT.parent / 'blend'
    blend.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend / 'Level5_Void.blend'))
    print('saved', blend / 'Level5_Void.blend', 'with packed plaster maps')
