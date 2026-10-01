#!/usr/bin/env python3
"""Independent local R3 geometry checks from exported bytes; never connects to Studio.

Collision rays use exported analytic boxes/cylinders, while enclosure and sign
mount checks inspect actual Blender mesh vertices/triangles. These checks do not
prove avatar navigation, multiplayer, streaming or Roblox performance.
"""
from __future__ import annotations

import argparse
import base64
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import struct


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mv(a, v):
    return tuple(sum(a[i][j] * v[j] for j in range(3)) for i in range(3))


def transpose(a):
    return list(map(list, zip(*a)))


def rotation(angles):
    x, y, z = angles
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return matmul(matmul([[1, 0, 0], [0, cx, -sx], [0, sx, cx]],
                         [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]),
                  [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])


def bounds(points):
    return tuple(min(p[i] for p in points) for i in range(3)), tuple(max(p[i] for p in points) for i in range(3))


def corners(lo, hi):
    return [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]


class Collider:
    def __init__(self, row):
        self.row, self.name = row, row['name']
        self.position, self.size = row['position'], row['size']
        self.half = [s / 2 for s in self.size]
        self.r = rotation(row.get('rotation', [0, row.get('yaw', 0), 0]))
        self.inv = transpose(self.r)
        self.cylinder = row.get('shape') == 'Cylinder'
        points = [tuple(self.position[i] + v[i] for i in range(3))
                  for v in (mv(self.r, c) for c in corners([-h for h in self.half], self.half))]
        self.lo, self.hi = bounds(points)

    def vertical_hit(self, x, z, origin_y, direction):
        if x < self.lo[0] - 1e-7 or x > self.hi[0] + 1e-7 or z < self.lo[2] - 1e-7 or z > self.hi[2] + 1e-7:
            return None
        if self.cylinder:
            if ((x - self.position[0]) / self.half[0]) ** 2 + ((z - self.position[2]) / self.half[2]) ** 2 > 1 + 1e-7:
                return None
            value = self.position[1] + (self.half[1] if direction < 0 else -self.half[1])
            t = (value - origin_y) / direction
            return t if t >= -1e-7 else None
        o = mv(self.inv, (x - self.position[0], origin_y - self.position[1], z - self.position[2]))
        d = mv(self.inv, (0, direction, 0))
        near, far = -math.inf, math.inf
        for i in range(3):
            if abs(d[i]) < 1e-10:
                if abs(o[i]) > self.half[i] + 1e-7:
                    return None
            else:
                a, b = (-self.half[i] - o[i]) / d[i], (self.half[i] - o[i]) / d[i]
                near, far = max(near, min(a, b)), min(far, max(a, b))
        if near > far or far < -1e-7:
            return None
        return max(0, near)


def nearest_vertical(colliders, x, z, origin_y, direction, limit):
    nearest = None
    for c in colliders:
        t = c.vertical_hit(x, z, origin_y, direction)
        if t is not None and t <= limit and (nearest is None or t < nearest[0]):
            nearest = (t, c)
    return nearest


def mesh_y(triangle, x, z):
    a, b, c = triangle
    den = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
    if abs(den) < 1e-10:
        return None
    u = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / den
    v = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / den
    if u < -1e-7 or v < -1e-7 or u + v > 1 + 1e-7:
        return None
    return u * a[1] + v * b[1] + (1 - u - v) * c[1]


def actual_mesh_ceiling(meshes, x, z, floor_y):
    top = math.inf
    for mesh in meshes:
        lo, hi = mesh['bounds']
        if not lo[0] - 1e-6 <= x <= hi[0] + 1e-6 or not lo[2] - 1e-6 <= z <= hi[2] + 1e-6:
            continue
        for triangle in mesh['triangles']:
            y = mesh_y(triangle, x, z)
            if y is not None and y > floor_y + 6.5:
                top = min(top, y)
    return top if top < math.inf else None


def connected_bounds(points, triangles):
    # Merge only identical positions; overlapping boxes remain separate bodies.
    unique, ids, position_ids = [], [], {}
    for p in points:
        k = tuple(round(c, 5) for c in p)
        if k not in position_ids:
            position_ids[k] = len(unique)
            unique.append(p)
        ids.append(position_ids[k])
    parent = list(range(len(unique)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for tri in triangles:
        root = find(ids[tri[0]])
        for i in tri[1:]:
            parent[find(ids[i])] = root
    components = defaultdict(list)
    for i, p in enumerate(unique):
        components[find(i)].append(p)
    return [bounds(p) for p in components.values()]


def touching(a, b, tolerance=.001):
    return all(a[0][i] <= b[1][i] + tolerance and b[0][i] <= a[1][i] + tolerance for i in range(3))


def contains(box, p, tolerance=.001):
    return all(box[0][i] - tolerance <= p[i] <= box[1][i] + tolerance for i in range(3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', default='assets/models/lobby-reimagined-r3-20261001/manifest.json')
    parser.add_argument('--report', default='artifacts/lobby-reimagined-r3-20261001/geometry-qa.json')
    args = parser.parse_args()
    path, report_path = Path(args.manifest), Path(args.report)
    manifest_bytes = path.read_bytes()
    m = json.loads(manifest_bytes)
    errors, checks, prefabs, binary_rows = [], [], {}, []
    def check(name, passed, details):
        checks.append({'name': name, 'passed': bool(passed), 'details': details})
        if not passed:
            errors.append(name)
    for chunk in m['chunks']:
        raw = base64.b64decode((path.parent / chunk['file']).read_bytes(), validate=True)
        assert hashlib.sha256(raw).hexdigest() == chunk['sha256'], chunk['family'] + ': changed bytes'
        magic, nv, nn, nu, nt = struct.unpack_from('<5I', raw)
        assert magic == 0x364D564C and len(raw) == 20 + nv * 12 + nn * 12 + nu * 8 + nt * 36
        assert nv == chunk['vertices'] and nt == chunk['triangles']
        points = [tuple(p[j] + chunk['center'][j] for j in range(3))
                  for p in (struct.unpack_from('<3f', raw, 20 + i * 12) for i in range(nv))]
        assert all(math.isfinite(c) for p in points for c in p)
        start = 20 + nv * 12 + nn * 12 + nu * 8
        triangles = []
        for i in range(nt):
            indices = struct.unpack_from('<9I', raw, start + i * 36)
            assert all(indices[k] < (nv, nn, nu)[k % 3] for k in range(9))
            triangles.append(tuple(indices[k] for k in (0, 3, 6)))
        prefabs[chunk['family']] = {'points': points, 'triangles': triangles, 'bounds': bounds(points)}
        binary_rows.append({'family': chunk['family'], 'sha256': chunk['sha256'], 'vertices': nv, 'triangles': nt})
    check('All exported binary hashes/counts/indices/vertices validated', True, {'chunks': len(binary_rows)})
    colliders = [Collider(c) for c in m['colliders']]
    structural = []
    for item in m['placements']:
        if item['family'] not in {'PlainShell', 'PortalShell', 'QueueRoom', 'EntryConnector'}:
            continue
        source = prefabs[item['family']]
        r = rotation([0, item.get('yaw', 0), 0])
        points = [tuple(item['robloxPosition'][j] + p[j] for j in range(3)) for p in (mv(r, v) for v in source['points'])]
        structural.append({'family': item['family'], 'bounds': bounds(points),
                           'triangles': [tuple(points[i] for i in tri) for tri in source['triangles']]})
    check('Six complete bay/gate groups and 24 pads', len(m.get('bays', [])) == 6 and len(m['signs']) == 6 and len(m['pads']) == 24,
          {'bays': len(m.get('bays', [])), 'gates': len(m['signs']), 'pads': len(m['pads'])})
    bays = {b['level']: b for b in m['bays']}
    route_rows, route_errors, roof_errors = [], [], []
    for sign in m['signs']:
        side, row, level = sign['side'], sign['row'], sign['level']
        floor_values, min_headroom = [], math.inf
        for lane in (-3, 0, 3):
            for step in range(115):
                x, z = side * (8 + step * .5), row + lane
                hit = nearest_vertical(colliders, x, z, 6, -1, 10)
                if not hit:
                    route_errors.append({'level': level, 'point': [x, z], 'reason': 'missing floor'})
                    continue
                floor = 6 - hit[0]
                floor_values.append(floor)
                roof = nearest_vertical(colliders, x, z, floor + .02, 1, 45)
                if not roof or roof[0] < 6.5:
                    route_errors.append({'level': level, 'point': [x, z], 'reason': 'missing/low ceiling',
                                         'ceiling': roof[1].name if roof else None, 'headroom': roof[0] if roof else None})
                elif roof:
                    min_headroom = min(min_headroom, roof[0])
        # Fine samples across the former shell/gate/connector gap use actual opaque mesh.
        roofs = []
        for lane in (-3, 0, 3):
            for step in range(41):
                x, z = side * (24 + step * .5), row + lane
                actual = actual_mesh_ceiling(structural, x, z, .8)
                if actual is None:
                    roof_errors.append({'level': level, 'point': [x, z]})
                else:
                    roofs.append(actual)
        route_rows.append({'level': level, 'floorSamples': len(floor_values),
                           'floorRange': [min(floor_values), max(floor_values)] if floor_values else None,
                           'minimumColliderHeadroom': min_headroom if min_headroom < math.inf else None,
                           'actualMeshRoofSamples': len(roofs), 'meshRoofRange': [min(roofs), max(roofs)] if roofs else None})
    check('All six approach aisles have continuous floors and avatar headroom', not route_errors, {'rays': 6 * 3 * 115 * 2, 'failures': route_errors})
    check('Actual Blender meshes cover former sky gaps over all six gates', not roof_errors, {'samples': 6 * 3 * 41, 'failures': roof_errors})
    ground_colliders = [c for c in colliders if c.name in {'Road', 'Sidewalk', 'Door Threshold', 'Connector Floor', 'Bay Floor', 'Queue Pad'}]
    bay_samples, bay_errors = 0, []
    for level, bay in bays.items():
        bx, _, bz = bay['position']
        for dx in range(-20, 21, 5):
            for dz in range(-20, 21, 5):
                if math.hypot(dx, dz) > bay['diameter'] / 2 - 2:
                    continue
                x, z = bx + dx, bz + dz
                floor = nearest_vertical(ground_colliders, x, z, 6, -1, 10)
                roof = actual_mesh_ceiling(structural, x, z, .8)
                bay_samples += 1
                if floor is None or roof is None or roof - .8 < 6.5:
                    bay_errors.append({'level': level, 'point': [x, z], 'floor': floor is not None, 'meshCeilingY': roof})
    check('All six bay interiors have actual opaque mesh roofs and ground coverage', not bay_errors,
          {'samples': bay_samples, 'failures': bay_errors, 'note': 'Furniture occupancy is not treated as walkable ground.'})
    pad_routes, pad_route_errors = [], []
    for pad in m['pads']:
        bay = bays[pad['level']]
        x, _, z = pad['position']
        bx, _, bz = bay['position']
        values = []
        for step in range(31):
            t = step / 30
            px, pz = bx + (x - bx) * t, bz + (z - bz) * t
            hit = nearest_vertical(ground_colliders, px, pz, 6, -1, 10)
            if hit is None:
                pad_route_errors.append({'id': pad.get('id'), 'point': [px, pz]})
            else:
                values.append(6 - hit[0])
        pad_routes.append({'id': pad.get('id'), 'level': pad['level'], 'floorSamples': len(values),
                           'maximumSampledStepRiseStuds': max((b - a for a, b in zip(values, values[1:])), default=0)})
    check('All24 radial pad approaches have continuous ground', not pad_route_errors,
          {'samples': 24 * 31, 'failures': pad_route_errors,
           'maximumSampledStepRiseStuds': max(r['maximumSampledStepRiseStuds'] for r in pad_routes),
           'requiresLiveVerification': 'Humanoid walking/jumping over the pad lip must be observed in Play.'})
    cancel_rows, cancel_errors = [], []
    for pad in m['pads']:
        bay = bays[pad['level']]
        x, y, z = pad['position']
        bx, _, bz = bay['position']
        distance = math.hypot(bx - x, bz - z)
        # GameManager phone cancel uses detector half-depth +5; root creates 14.8-wide zones.
        displacement = 14.8 / 2 + 5
        ex, ez = x + (bx - x) / distance * displacement, z + (bz - z) / distance * displacement
        nearest = min(math.hypot(ex - p['position'][0], ez - p['position'][2]) - p['radius']
                      for p in m['pads'] if p['level'] == pad['level'])
        edge_margin = bay['diameter'] / 2 - math.hypot(ex - bx, ez - bz) - 1.65
        floor_hit = nearest_vertical(colliders, ex, ez, y + 3, -1, 10)
        head_hit = nearest_vertical(colliders, ex, ez, (.8 if not floor_hit else y + 3 - floor_hit[0]) + .02, 1, 40)
        passed = nearest > 1.65 and edge_margin > 0 and floor_hit is not None and head_hit is not None and head_hit[0] > 6.5
        record = {'id': pad.get('id'), 'level': pad['level'], 'inwardCancelPoint': [ex, y + 3, ez],
                  'nearestQueueEdgeStuds': nearest, 'humanoidWallMarginStuds': edge_margin,
                  'floorPresent': floor_hit is not None, 'headroomStuds': head_hit[0] if head_hit else None, 'passed': passed}
        cancel_rows.append(record)
        if not passed:
            cancel_errors.append(record)
    check('Every inward-oriented phone cancellation clears all queues and bay walls', not cancel_errors,
          {'assumedZoneSizeXZ': 14.8, 'humanoidHalfWidth': 1.65, 'failures': cancel_errors,
           'requiresLiveVerification': 'Actual zone LookVector must match inward direction; validator does not invent installed zone yaw.'})
    gate = prefabs['LevelGate']
    components = connected_bounds(gate['points'], gate['triangles'])
    graph = [set() for _ in components]
    for i, a in enumerate(components):
        for j in range(i):
            if touching(a, components[j]):
                graph[i].add(j); graph[j].add(i)
    header = m['signs'][0]['headerLocalPosition']
    blade = m['signs'][0]['bladeLocalPosition']
    roots = {i for i, b in enumerate(components) if contains(b, (-10.7, 8.1, 0)) or contains(b, (10.7, 8.1, 0))}
    reached, pending = set(roots), list(roots)
    while pending:
        for i in graph[pending.pop()] - reached:
            reached.add(i);pending.append(i)
    # Native artwork deliberately sits .10 stud proud of its mesh backing.
    supported = lambda point: any(i in reached and contains(b, point, .15) for i, b in enumerate(components))
    check('Actual Blender blade/header mounts are connected to gate posts', supported(header) and supported(blade),
          {'meshConnectedBodies': len(components), 'bodiesReachableFromPosts': len(reached), 'headerSupported': supported(header), 'bladeSupported': supported(blade),
           'method': 'Triangle-position components and contacting body bounds; visual support check, not structural-load simulation.'})
    sign_rows, sign_errors = [], []
    for sign in m['signs']:
        r = rotation([0, sign['yaw'], 0])
        header_normal = mv(r, (0, 0, 1))
        header_inward_dot = header_normal[0] * -sign['side']
        blade_normals = {face: mv(r, (-1 if face == 'Left' else 1, 0, 0)) for face in ('Left', 'Right')}
        passed = header_inward_dot > .999 and all(abs(n[2]) > .999 for n in blade_normals.values())
        passed &= sign['bladeArrows'] == {'Left': '←', 'Right': '→'}
        # Readable Left face screen-right is local+Z; Right face screen-right is local−Z.
        for face, normal in blade_normals.items():
            screen_right = (normal[2], 0, -normal[0])
            arrow_vector = tuple(v * (-1 if sign['bladeArrows'][face] == '←' else 1) for v in screen_right)
            passed &= arrow_vector[0] * sign['side'] > .999
        record = {'level': sign['level'], 'headerFacesAisle': header_inward_dot, 'bladeFacesBothTunnelDirections': blade_normals,
                  'arrowsPointTowardBay': bool(passed)}
        sign_rows.append(record)
        if not passed:
            sign_errors.append(record)
    check('Header faces aisle and both blade arrows point into the correct bay', not sign_errors, {'failures': sign_errors})
    report = {'schema': 'lobby-r3-independent-geometry-v1', 'passed': not errors,
              'manifest': str(path), 'manifestSha256': hashlib.sha256(manifest_bytes).hexdigest(),
              'sourceBlendSha256': m['sourceBlendSha256'], 'placements': len(m['placements']),
              'staticTriangles': m['instantiatedTriangles'], 'colliders': len(colliders), 'checks': checks,
              'routes': route_rows, 'padRoutes': pad_routes, 'cancellations': cancel_rows, 'signs': sign_rows,
              'binaryGeometry': binary_rows, 'errors': errors,
              'limitations': ['Exported local geometry only; no Studio write or Play test.',
                              'Avatar movement, floor ray parity, actual zone cancellation yaw, original-lobby preservation and all interactions need live verification.',
                              'No FPS, memory, streaming or multiplayer result is inferred from triangle count.',
                              'Native text/image readability requires actual rendered views; geometry normals alone do not prove legibility.']}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'report': str(report_path), 'errors': errors, 'checks': len(checks)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
