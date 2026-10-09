"""Export a Level 2 corridor arch rib as a Wavefront OBJ (ARCH_MESH_PILOT_20260922).

The same geometry `Level 2 World Builder.buildArchRibMesh` builds at runtime from
an EditableMesh: a 3.2 x 2.2 (axial x radial) band swept along the elliptical
arc the Part ribs follow -- radius R across, R * VerticalScale up, feet dipping
`asin((floorDepth + 2.2) / (R * vs))` below the arc centre, `steps` straight
segments. Local space is the rib's own: X across the opening, Y up, Z along the
passage, origin at the arc centre (the Part path's `arcCenter`, i.e. corridor
centre + 1 stud up). UVs are studs / 7 so the Level 2 tile (asset
113211706146395, 7 studs per tile) reads at the size the Texture instances gave.

Usage:
    python tools/level2_arch_rib_obj.py --key r13.20_vs1.90_fd2.00_a3.20_d2.20_s26 --out dir/
    python tools/level2_arch_rib_obj.py --radius 13.2 --floor-depth 2 --out dir/

The key format is exactly what the World Builder records in
`Level2_ArchRibMeshMissingKeys` / `WorldBuilder.ArchRibMeshKeyFor`, so a key read
off a Studio round can be exported verbatim. Upload the .obj through the Creator
Hub or Studio's Import 3D, then put the asset id under
`Level 2 Configuration.Performance.ArchMeshRibAssets[key]`.
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

KEY_RE = re.compile(r"^r([\d.]+)_vs([\d.]+)_fd([\d.]+)_a([\d.]+)_d([\d.]+)_s(\d+)$")
TILE_STUDS = 7.0


def make_key(radius: float, vertical_scale: float, floor_depth: float, axial: float, radial: float, steps: int) -> str:
    return f"r{radius:.2f}_vs{vertical_scale:.2f}_fd{floor_depth:.2f}_a{axial:.2f}_d{radial:.2f}_s{steps}"


def standard_key(radius: float, floor_depth: float, vertical_scale: float = 1.9) -> str:
    """The standard corridor family for a given rib radius (World Builder arithmetic)."""
    radius = max(6.0, radius)
    steps = max(14, math.ceil(radius * 1.9 - 1e-9))
    return make_key(radius, vertical_scale, floor_depth, 3.2, 2.2, steps)


def build(radius: float, vertical_scale: float, floor_depth: float, axial: float, radial: float, steps: int):
    """Vertices (x, y, z), normals, uvs and faces as (v, vt, vn) index triples (1-based)."""
    dip = math.asin(max(0.0, min((floor_depth + 2.2) / (radius * vertical_scale), 0.55)))
    a_from, a_to = -dip, math.pi + dip
    half = radial * 0.5
    z_near, z_far = -axial * 0.5, axial * 0.5
    verts: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    faces: list[list[tuple[int, int, int]]] = []

    def add_v(p):
        verts.append(p)
        return len(verts)

    def add_n(n):
        normals.append(n)
        return len(normals)

    def add_uv(u, v):
        uvs.append((u / TILE_STUDS, v / TILE_STUDS))
        return len(uvs)

    def unit(v):
        m = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
        return (v[0] / m, v[1] / m, v[2] / m) if m > 1e-9 else (0.0, 1.0, 0.0)

    rings = []
    along, previous = 0.0, None
    for i in range(steps + 1):
        a = a_from + (a_to - a_from) * i / steps
        point = (math.cos(a) * radius, math.sin(a) * radius * vertical_scale, 0.0)
        normal = unit((point[0], point[1] / (vertical_scale * vertical_scale), 0.0))
        if previous is not None:
            along += math.dist(point, previous)
        previous = point
        inner = (point[0] - normal[0] * half, point[1] - normal[1] * half, 0.0)
        outer = (point[0] + normal[0] * half, point[1] + normal[1] * half, 0.0)
        rings.append({
            "InnerNear": add_v((inner[0], inner[1], z_near)),
            "InnerFar": add_v((inner[0], inner[1], z_far)),
            "OuterNear": add_v((outer[0], outer[1], z_near)),
            "OuterFar": add_v((outer[0], outer[1], z_far)),
            "Along": along, "Normal": normal, "Point": point,
        })

    def quad(a, b, c, d, normal, uv_a, uv_b, uv_c, uv_d):
        n = add_n(normal)
        faces.append([(a, uv_a, n), (b, uv_b, n), (c, uv_c, n)])
        faces.append([(a, uv_a, n), (c, uv_c, n), (d, uv_d, n)])

    for i in range(steps):
        r0, r1 = rings[i], rings[i + 1]
        u0, u1 = r0["Along"], r1["Along"]
        inward = unit(tuple(-(r0["Normal"][k] + r1["Normal"][k]) for k in range(3)))
        outward = tuple(-x for x in inward)
        quad(r0["InnerNear"], r0["InnerFar"], r1["InnerFar"], r1["InnerNear"], inward,
             add_uv(u0, 0), add_uv(u0, axial), add_uv(u1, axial), add_uv(u1, 0))
        quad(r0["OuterFar"], r0["OuterNear"], r1["OuterNear"], r1["OuterFar"], outward,
             add_uv(u0, axial), add_uv(u0, 0), add_uv(u1, 0), add_uv(u1, axial))
        quad(r0["InnerNear"], r1["InnerNear"], r1["OuterNear"], r0["OuterNear"], (0.0, 0.0, -1.0),
             add_uv(u0, 0), add_uv(u1, 0), add_uv(u1, radial), add_uv(u0, radial))
        quad(r0["InnerFar"], r0["OuterFar"], r1["OuterFar"], r1["InnerFar"], (0.0, 0.0, 1.0),
             add_uv(u0, 0), add_uv(u0, radial), add_uv(u1, radial), add_uv(u1, 0))
    first, last = rings[0], rings[steps]
    t_first = unit(tuple(rings[1]["Point"][k] - first["Point"][k] for k in range(3)))
    t_last = unit(tuple(last["Point"][k] - rings[steps - 1]["Point"][k] for k in range(3)))
    quad(first["InnerNear"], first["OuterNear"], first["OuterFar"], first["InnerFar"], tuple(-x for x in t_first),
         add_uv(0, 0), add_uv(radial, 0), add_uv(radial, axial), add_uv(0, axial))
    quad(last["InnerNear"], last["InnerFar"], last["OuterFar"], last["OuterNear"], t_last,
         add_uv(0, 0), add_uv(0, axial), add_uv(radial, axial), add_uv(radial, 0))
    return verts, normals, uvs, faces


def write_obj(path: Path, key: str, verts, normals, uvs, faces) -> None:
    xs = [v[0] for v in verts]; ys = [v[1] for v in verts]; zs = [v[2] for v in verts]
    lines = [
        f"# Level 2 corridor arch rib {key} -- BACKROOMS: STAY QUIET, ARCH_MESH_PILOT_20260922",
        "# Local space: X across the opening, Y up, Z along the passage; origin = arc centre (corridor centre + 1 stud up).",
        f"# Extents: X {min(xs):.2f}..{max(xs):.2f}  Y {min(ys):.2f}..{max(ys):.2f}  Z {min(zs):.2f}..{max(zs):.2f} studs",
        f"# {len(verts)} vertices, {len(faces)} triangles. UVs in tiles of {TILE_STUDS:g} studs (texture rbxassetid://113211706146395).",
        "# Collision: PreciseConvexDecomposition; the Part ribs it replaces collide too.",
        f"o ArchRib_{key}",
    ]
    lines += [f"v {x:.5f} {y:.5f} {z:.5f}" for x, y, z in verts]
    lines += [f"vt {u:.5f} {v:.5f}" for u, v in uvs]
    lines += [f"vn {x:.5f} {y:.5f} {z:.5f}" for x, y, z in normals]
    lines += ["f " + " ".join(f"{v}/{vt}/{vn}" for v, vt, vn in face) for face in faces]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key", help="family key as the World Builder records it")
    parser.add_argument("--radius", type=float, help="rib radius across (standard family)")
    parser.add_argument("--floor-depth", type=float, default=0.0, help="corridor channel depth (default 0)")
    parser.add_argument("--vertical-scale", type=float, default=1.9)
    parser.add_argument("--out", type=Path, default=Path("artifacts/claude-20260922/level2-arch-mesh"))
    args = parser.parse_args()
    key = args.key or (standard_key(args.radius, args.floor_depth, args.vertical_scale) if args.radius else None)
    if not key:
        raise SystemExit("give --key or --radius")
    match = KEY_RE.match(key)
    if not match:
        raise SystemExit(f"bad key {key!r}")
    radius, vs, fd, axial, radial = (float(match.group(i)) for i in range(1, 6))
    steps = int(match.group(6))
    verts, normals, uvs, faces = build(radius, vs, fd, axial, radial, steps)
    args.out.mkdir(parents=True, exist_ok=True)
    path = args.out / f"arch_rib_{key}.obj"
    write_obj(path, key, verts, normals, uvs, faces)
    print(f"{path}  {len(verts)} vertices  {len(faces)} triangles")


if __name__ == "__main__":
    main()
