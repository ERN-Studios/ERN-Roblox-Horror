"""Closed-eyes variant of Luna's base colour texture (she sleeps with her eyes shut).

    python tools/luna/paint_closed_eyes.py --blend luna_rig2.blend --texture luna_v1_base_color.png \
        --out luna_base_color_eyes_closed.png [--renders <dir>] [--blender D:/Blender/blender.exe]

The Meshy atlas is fragmented, so everything is decided in 3D: every texel covered by a triangle gets its
3D position by barycentric interpolation, the eyes are found as the two dark/brown texel clusters on the
head, and the new colour of a texel is a function of its position in each eye's tangent frame (fur fill
fitted on the fur ring around the eye, fur detail transplanted from the cheek below, a tapered lid line
antialiased over each texel's own 3D footprint). Gutter texels next to an island are placed in 3D by
extrapolating their nearest triangle and painted by the same function, so bilinear/mip sampling shows no
seam. The blend is only read (never saved); the source texture is never written.

Under Blender the same file is the helper: `--dump <npz>` writes the mesh, `--render <tex|-> <prefix>`
renders head close-ups (workbench, textured) with the given image swapped into the material.
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

MESH = "LunaMesh"
HEAD_BOX = ((-0.40, 0.40), (1.55, 2.08), (2.55, 3.00))  # x, y, z studs: brows to muzzle top, excludes the nose
CLUSTER_MIN = 200            # texels; the eyes are ~1000 each
VIEWS = {"front": (0, 1, 0.05), "right": (1, 0.05, 0.05), "left": (-1, 0.05, 0.05),
         "q34r": (0.7, 0.75, 0.2), "q34l": (-0.7, 0.75, 0.2), "high": (0.0, 0.6, 0.8)}


# --------------------------------------------------------------------------- Blender side
def blender_main(argv):
    import bpy
    from mathutils import Vector
    ob = bpy.data.objects[MESH]
    if argv[0] == "--dump":
        me = ob.data
        me.calc_loop_triangles()
        co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get("co", co)
        tv = np.empty(len(me.loop_triangles) * 3, np.int32); me.loop_triangles.foreach_get("vertices", tv)
        tl = np.empty(len(me.loop_triangles) * 3, np.int32); me.loop_triangles.foreach_get("loops", tl)
        uv = np.empty(len(me.loops) * 2, np.float32); me.uv_layers.active.data.foreach_get("uv", uv)
        mw = np.array(ob.matrix_world, np.float32)
        co = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
        np.savez(argv[1], co=co, tv=tv.reshape(-1, 3), tl=tl.reshape(-1, 3), uv=uv.reshape(-1, 2))
        return
    # --render <tex|-> <prefix> <json eye centres>
    tex, prefix, eyes = argv[1], argv[2], json.loads(argv[3])
    sc = bpy.context.scene
    if tex != "-":
        im = bpy.data.images.load(tex, check_existing=False)
        for m in ob.data.materials:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE":
                    n.image = im
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 900
    cam = bpy.data.objects.new("eyes_cam", bpy.data.cameras.new("eyes_cam"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"
    mid = sum((Vector(e["c"]) for e in eyes), Vector()) / len(eyes)
    shots = [(k, mid + Vector((0, 0.05, 0)), d, 1.0) for k, d in VIEWS.items()]
    for e in eyes:   # per eye: along its normal, and the two directions a standing player sees it from
        sx = 1 if e["side"] == "right" else -1
        shots += [(f"zoom_{e['side']}", Vector(e["c"]), e["n"], 0.32),
                  (f"zoom_{e['side']}_front", Vector(e["c"]), (0, 1, 0.1), 0.45),
                  (f"zoom_{e['side']}_high", Vector(e["c"]), (0.55 * sx, 0.6, 0.6), 0.45)]
    for name, centre, d, scale in shots:
        d = Vector(d).normalized()
        cam.data.ortho_scale = scale
        cam.location = centre + d * 6
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)


# --------------------------------------------------------------------------- painting
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def raster_all(P, px, W, H):
    """Texel-centre rasterisation of every triangle: triangle id and 3D position per texel."""
    tri = np.full((H, W), -1, np.int32)
    pos = np.zeros((H, W, 3), np.float32)
    lo = np.clip(np.ceil(px.min(1)).astype(int), 0, [W - 1, H - 1])
    hi = np.clip(np.floor(px.max(1)).astype(int), 0, [W - 1, H - 1])
    for i in range(len(P)):
        if (hi[i] < lo[i]).any():
            continue
        ys, xs = np.mgrid[lo[i, 1]:hi[i, 1] + 1, lo[i, 0]:hi[i, 0] + 1]
        ys, xs = ys.ravel(), xs.ravel()
        bc = barycentric(px[i][None], xs, ys)
        m = (bc >= -1e-6).all(1)
        if m.any():
            tri[ys[m], xs[m]] = i
            pos[ys[m], xs[m]] = bc[m] @ P[i]
    return tri, pos


def barycentric(tp, x, y):
    """Barycentric coords of texel centres (x, y) in pixel-space triangles tp (N or 1, 3, 2)."""
    a, b, c = tp[:, 0], tp[:, 1], tp[:, 2]
    det = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (c[:, 0] - a[:, 0]) * (b[:, 1] - a[:, 1])
    det = np.where(np.abs(det) < 1e-12, np.inf, det)               # degenerate: all weight on a
    dx, dy = x - a[:, 0], y - a[:, 1]
    l1 = (dx * (c[:, 1] - a[:, 1]) - dy * (c[:, 0] - a[:, 0])) / det
    l2 = (dy * (b[:, 0] - a[:, 0]) - dx * (b[:, 1] - a[:, 1])) / det
    return np.stack([1 - l1 - l2, l1, l2], -1)


def find_eyes(img, tri, pos, tri_n):
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    from scipy.spatial import cKDTree
    cov = tri >= 0
    box = cov.copy()
    for k, (a, b) in enumerate(HEAD_BOX):
        box &= (pos[..., k] >= a) & (pos[..., k] <= b)
    lum = img @ [0.299, 0.587, 0.114]
    sat = img.max(-1) - img.min(-1)
    cand = box & ((lum < 0.40) | ((sat > 0.10) & (lum < 0.60))) & (tri_n[tri][..., 1] > -0.2)
    yx = np.argwhere(cand)
    q = pos[cand]
    h = np.median(cKDTree(q).query(q, k=2)[0][:, 1])
    pairs = cKDTree(q).query_pairs(2.5 * h, output_type="ndarray")
    n, lab = connected_components(coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(len(q),) * 2), directed=False)
    sizes = np.bincount(lab)
    big = [k for k in np.argsort(sizes)[::-1][:2] if sizes[k] >= CLUSTER_MIN]
    assert len(big) == 2, f"expected two eye clusters, sizes {sorted(sizes)[-5:]}"
    eyes = []
    for k in big:
        sel = lab == k
        mq = q[sel]
        c = mq.mean(0)
        nrm = tri_n[tri[tuple(yx[sel].T)]].mean(0); nrm /= np.linalg.norm(nrm)
        side = "right" if c[0] > 0 else "left"            # +X is her right
        lateral = np.array([np.sign(c[0]), 0.0, 0.0])
        d = mq - c
        w, V = np.linalg.eigh(np.cov(d.T))
        u0 = V[:, 2] - nrm * (V[:, 2] @ nrm); u0 /= np.linalg.norm(u0)
        if u0 @ lateral < 0:
            u0 = -u0
        s0 = d @ u0
        c_in = mq[s0 <= np.percentile(s0, 1.5)].mean(0)    # medial corner (nose side)
        c_out = mq[s0 >= np.percentile(s0, 98.5)].mean(0)  # lateral corner
        u = c_out - c_in; u -= nrm * (u @ nrm); L = np.linalg.norm(u); u /= L
        v = np.cross(nrm, u)
        if v[2] < 0:
            v = -v
        t = (mq - c_in) @ v
        s = (mq - c_in) @ u
        mid = np.abs(s - L / 2) < 0.25 * L
        b = (np.percentile(t[mid], 99) - np.percentile(t[mid], 1)) / 2
        eyes.append(dict(side=side, c=c, n=nrm, u=u, v=v, o=c_in, c_in=c_in, c_out=c_out, L=L, b=b,
                         t_mid=float(np.median(t[mid])), mask=mq, count=int(sel.sum())))
    return sorted(eyes, key=lambda e: e["side"]), h


def quad_basis(s, t, L):
    s, t = s / L, t / L
    return np.stack([np.ones_like(s), s, t, s * s, s * t, t * t], -1)


def robust_fit(F, Y, iters=4):
    keep = np.ones(len(Y), bool)
    for _ in range(iters):
        coef, *_ = np.linalg.lstsq(F[keep], Y[keep], rcond=None)
        r = (Y - F @ coef) @ [0.299, 0.587, 0.114]
        keep = (r > -0.06) & (r < 0.10)
    return coef


def eye_painter(img_c, p_c, nf_c, e, h, a):
    """Set up one eye from the covered texels near it (positions p_c, colours img_c, facing nf_c).
    Returns colour(p, src, J) -> (new colour, changed) for any surface points, covered or gutter."""
    from scipy.spatial import cKDTree
    b, L, o, u, v, n = e["b"], e["L"], e["o"], e["u"], e["v"], e["n"]
    m_full, m_fade = a.margin * b, a.fade * b
    mask_tree = cKDTree(e["mask"])

    def frame(p):
        q = p - o
        s, t = q @ u, q @ v
        # repaint weight (1 = fully repainted): the dark mask plus a margin, united with an almond-wide
        # ellipse so the grey canthus shading just past both corners goes too
        half = np.where(s < L / 2, a.medial * L / 2, L / 2)            # the canthus spot sits past the medial corner
        r_ell = np.hypot((s - L / 2) / half, (t - e["t_mid"]) / (1.2 * b))
        d_mask = mask_tree.query(p)[0]
        W = np.maximum(1 - smoothstep(m_full, m_fade, d_mask), 1 - smoothstep(a.corner, a.corner + 0.3, r_ell))
        return s, t, W, d_mask

    s_c, t_c, W_c, d_c = frame(p_c)
    ring = (W_c <= 0) & (d_c < m_fade + 0.8 * b)
    coef = robust_fit(quad_basis(s_c[ring], t_c[ring], L), img_c[ring])
    # fur detail: high-pass of the cheek fur straight below the eye, transplanted in tangent space
    st_tree = cKDTree(np.stack([s_c, t_c], 1))
    shift = 2 * b + 2 * m_fade
    det_src = ((t_c > -b - m_fade - shift - 0.01) & (t_c < b + m_fade - shift + 0.01)
               & (np.abs(s_c - L / 2) < L / 2 + m_fade + 0.01))
    coef_s = robust_fit(quad_basis(s_c[det_src], t_c[det_src], L), img_c[det_src])
    hp_c = np.clip(img_c - quad_basis(s_c, t_c, L) @ coef_s, -0.10, 0.10)

    # closed lid: a tapered dark line from the medial to just past the lateral corner, sagging gently
    lam = np.linspace(-0.03, 1.0 + a.tail, 600)
    cs = lam * L
    ct = -a.sag * b * np.sin(np.pi * np.clip(lam, 0, 1)) - a.droop * b * smoothstep(0.65, 1.0 + a.tail, lam)
    width = a.width * b * np.sin(np.pi * np.clip((lam + 0.06) / (1.0 + a.tail + 0.07), 0, 1)) ** 0.65
    # lift the planar curve onto the surface (height from texels on faces that look along the eye
    # normal) so distances are 3D: the creased slivers in the eye opening only darken where they
    # really touch the line instead of smearing it across their tilted width
    flat = nf_c > 0.8
    _, kk = cKDTree(np.stack([s_c[flat], t_c[flat]], 1)).query(np.stack([cs, ct], 1), k=6)
    hgt = (p_c[flat] - o) @ n
    ch = np.convolve(np.pad(hgt[kk].mean(1), 12, mode="edge"), np.ones(25) / 25, mode="valid")
    curve = o + cs[:, None] * u + ct[:, None] * v + ch[:, None] * n
    curve_tree = cKDTree(curve)
    across = np.cross(n, np.gradient(curve, axis=0))                     # in-surface normal of the line
    across /= np.linalg.norm(across, axis=1, keepdims=True)
    line_col = np.array(a.line_color) / 255.0

    def colour(p, src, J):
        """J: (N, 3, 2) 3D step per texel in x and y at each point (its triangle's UV Jacobian)."""
        s, t, W, _ = frame(p)
        fill = quad_basis(s, t, L) @ coef
        dd, ii = st_tree.query(np.stack([s, t - shift], 1))
        fill = fill + hp_c[ii] * (a.detail * (dd < 2 * h))[:, None]
        dc, ic = curve_tree.query(p)
        w = width[ic]
        above = t - ct[ic]                                               # signed offset from the line
        # antialiased over one texel footprint measured across the line (fwidth: the atlas is sheared
        # and stretched, so a fixed 3D ramp leaves a staircase where texels are long across the line);
        # coverage also shrinks with the width so the ends taper to nothing
        fw = np.clip(np.abs(np.einsum("nk,nkj->nj", across[ic], J)).sum(1) * a.aa, 0.5 * h, 6 * h)
        core = np.clip((w - dc) / fw + 0.5, 0, 1) * np.clip(2 * w / fw, 0, 1)
        halo = a.halo * np.exp(-(dc / (2.6 * w + 1e-6)) ** 2) * (w > 0.15 * h)
        alpha = np.clip(np.maximum(core * a.line_alpha, halo), 0, 1)
        # soft shading: the closed upper lid's crease just above the line, a lighter lid bulge above it
        taper = np.sin(np.pi * np.clip(lam[ic], 0, 1))
        shade = (a.crease * np.exp(-((above - 0.55 * b) / (0.30 * b)) ** 2)
                 - a.bulge * np.exp(-((above - 1.05 * b) / (0.40 * b)) ** 2)) * taper * W
        fill = fill * (1 - shade[:, None])
        col = src * (1 - W[:, None]) + fill * W[:, None]
        col = col * (1 - alpha[:, None]) + line_col * alpha[:, None]
        return np.clip(col, 0, 1), (W > 1e-4) | (alpha > 1e-4)

    return colour


def component_boxes(mask):
    from scipy.ndimage import label, find_objects, binary_dilation
    lab, n = label(binary_dilation(mask, iterations=3))
    boxes = []
    for k, sl in enumerate(find_objects(lab), 1):
        cnt = int((mask[sl] & (lab[sl] == k)).sum())
        if cnt:
            boxes.append(dict(x0=sl[1].start, y0=sl[0].start, x1=sl[1].stop - 1, y1=sl[0].stop - 1, pixels=cnt))
    return sorted(boxes, key=lambda b: -b["pixels"])


def run_blender(a, *args):
    cmd = [a.blender, "-b", a.blend, "-P", os.path.abspath(__file__), "--", *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or "Error" in r.stdout:
        sys.exit(f"blender failed:\n{r.stdout[-3000:]}\n{r.stderr[-3000:]}")


def main():
    import argparse
    from PIL import Image
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--blend", required=True)
    ap.add_argument("--texture", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--renders", help="directory for eyes_closed_* close-up renders (orig + new)")
    ap.add_argument("--blender", default=r"D:\Blender\blender.exe")
    ap.add_argument("--margin", type=float, default=0.30, help="full-repaint margin around the eye, x half-height")
    ap.add_argument("--fade", type=float, default=0.85, help="end of the blend back to the original, x half-height")
    ap.add_argument("--sag", type=float, default=0.30, help="lid line sag at the middle, x half-height")
    ap.add_argument("--droop", type=float, default=0.22, help="extra drop at the lateral corner, x half-height")
    ap.add_argument("--tail", type=float, default=0.10, help="line extends past the lateral corner, x length")
    ap.add_argument("--corner", type=float, default=1.10, help="ellipse radius (x half-length) repainted past the corners")
    ap.add_argument("--medial", type=float, default=1.3, help="that ellipse is this much longer on the medial side")
    ap.add_argument("--width", type=float, default=0.15, help="line half-width at its thickest, x half-height")
    ap.add_argument("--aa", type=float, default=1.5, help="antialiasing ramp, x texel footprint")
    ap.add_argument("--line-alpha", type=float, default=0.92)
    ap.add_argument("--halo", type=float, default=0.30)
    ap.add_argument("--crease", type=float, default=0.06)
    ap.add_argument("--bulge", type=float, default=0.03)
    ap.add_argument("--detail", type=float, default=0.8)
    ap.add_argument("--line-color", type=float, nargs=3, default=(34, 30, 30))
    ap.add_argument("--gutter", type=int, default=8, help="gutter texels within this many texels of an island are repainted too")
    a = ap.parse_args()
    if os.path.abspath(a.out) == os.path.abspath(a.texture):
        sys.exit("refusing to overwrite the source texture")

    src_im = Image.open(a.texture)
    mode = src_im.mode
    img = np.asarray(src_im.convert("RGB")).astype(np.float32) / 255.0
    H, W = img.shape[:2]
    with tempfile.TemporaryDirectory() as td:
        npz = os.path.join(td, "mesh.npz")
        run_blender(a, "--dump", npz)
        d = dict(np.load(npz))
    co, tv, tl, uv = d["co"], d["tv"], d["tl"], d["uv"]
    P = co[tv]
    px = np.stack([uv[tl][..., 0] * W - 0.5, (1 - uv[tl][..., 1]) * H - 0.5], -1)
    tri, pos = raster_all(P, px, W, H)
    tri_n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    tri_n /= np.linalg.norm(tri_n, axis=1, keepdims=True) + 1e-12
    tri_n = np.vstack([tri_n, np.zeros((1, 3), tri_n.dtype)])            # index -1 -> zero normal
    # per-triangle UV Jacobian: 3D step for one texel in x and in y
    duv = np.stack([px[:, 1] - px[:, 0], px[:, 2] - px[:, 0]], -1)       # (n, 2 xy, 2 edges)
    dP = np.stack([P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]], -1)            # (n, 3, 2 edges)
    ok = np.abs(np.linalg.det(duv)) > 1e-9
    jac = np.zeros((len(P), 3, 2))
    jac[ok] = dP[ok] @ np.linalg.inv(duv[ok])
    jac[~ok] = 6 * 0.0025
    eyes, h = find_eyes(img, tri, pos, tri_n)

    # every texel the eyes may touch: covered ones, plus gutter texels within a.gutter of an island,
    # placed in 3D by extrapolating their nearest covered texel's triangle so lines and fills continue
    # across island borders smoothly (bilinear and mip sampling then show no seam or staircase)
    from scipy.ndimage import distance_transform_edt
    cov = tri >= 0
    dist, (iy, ix) = distance_transform_edt(~cov, return_indices=True)
    cy, cx = np.nonzero(cov)
    gy, gx = np.nonzero(~cov & (dist <= a.gutter))
    gt = tri[iy[gy, gx], ix[gy, gx]]
    gpos = np.einsum("nk,nkj->nj", barycentric(px[gt], gx, gy), P[gt])
    ty, tx = np.concatenate([cy, gy]), np.concatenate([cx, gx])
    tp = np.concatenate([pos[cy, cx], gpos]).astype(np.float64)
    tt = np.concatenate([tri[cy, cx], gt])
    is_cov = np.arange(len(ty)) < len(cy)

    out = img.copy()
    changed = np.zeros((H, W), bool)
    for e in eyes:
        e["radius"] = 0.6 * e["L"] + a.fade * e["b"] + 3.2 * e["b"]
        nf = tri_n[tt] @ e["n"]
        near = ((np.linalg.norm(tp - e["c"], axis=1) < e["radius"]) & (nf > 0.0)
                & (np.abs((tp - e["c"]) @ e["n"]) < 0.05))
        k = near & is_cov
        colour = eye_painter(img[ty[k], tx[k]], tp[k], nf[k], e, h, a)
        idx = np.nonzero(near)[0]
        col, ch = colour(tp[idx], img[ty[idx], tx[idx]], jac[tt[idx]])
        out[ty[idx[ch]], tx[idx[ch]]] = col[ch]
        changed[ty[idx[ch]], tx[idx[ch]]] = True
    gutter = int((changed & ~cov).sum())

    res = np.round(out * 255).astype(np.uint8)
    orig8 = np.asarray(src_im.convert("RGB"))
    Image.fromarray(res, "RGB").convert(mode).save(a.out)

    diff = (res != orig8).any(-1)
    # every changed texel must sit near an eye in 3D (gutter texels: their extrapolated position)
    pmap = np.full((H, W, 3), np.inf)
    pmap[ty, tx] = tp
    p = pmap[diff]
    near = np.zeros(len(p), bool)
    for e in eyes:
        near |= np.linalg.norm(p - e["c"], axis=1) < e["radius"]
    assert near.all(), f"{(~near).sum()} changed texels are not near an eye"
    report = dict(texture=a.texture, out=a.out, size=[W, H], mode=mode, texel_studs=round(float(h), 5),
                  changed_pixels=int(diff.sum()), gutter_pixels=gutter,
                  boxes=component_boxes(diff),
                  eyes=[dict(side=e["side"], centre=np.round(e["c"], 4).tolist(), normal=np.round(e["n"], 3).tolist(),
                             medial_corner=np.round(e["c_in"], 4).tolist(), lateral_corner=np.round(e["c_out"], 4).tolist(),
                             length=round(float(e["L"]), 4), half_height=round(float(e["b"]), 4),
                             mask_texels=e["count"]) for e in eyes])
    print(json.dumps(report, indent=1))
    if a.renders:
        os.makedirs(a.renders, exist_ok=True)
        cams = json.dumps([dict(side=e["side"], c=e["c"].tolist(), n=(e["n"] + 0.15 * np.array([0, 1, 0])).tolist())
                           for e in eyes])
        run_blender(a, "--render", "-", os.path.join(a.renders, "eyes_closed_orig"), cams)
        run_blender(a, "--render", os.path.abspath(a.out), os.path.join(a.renders, "eyes_closed_new"), cams)


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
    except ImportError:
        main()
    else:
        blender_main(sys.argv[sys.argv.index("--") + 1:])
