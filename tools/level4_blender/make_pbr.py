# Level 4 cinema: tileable albedo -> PBR set (numpy + PIL, no Blender). Every filter wraps around
# (np.roll / FFT), so a seamless input stays seamless in every output:
#   <name>_albedo.png  colour, optionally delit (divided by its own wrap-around low-pass luminance)
#   <name>_height.png  high-passed, blurred luminance, contrast-stretched for display/displacement
#   <name>_normal.png  tangent space from the raw (unstretched) height, so flat textures stay flat;
#                      opengl = +Y green (Roblox, Blender), directx flips green only
#   <name>_rough.png   rough_base +/- rough_var from inverted high-passed luminance, clamped [min, max]
#   <name>_ao.png      cavity from height (--ao)
# Pixel radii are in 1024-px texels and scale with --size.
#   python make_pbr.py <in.png|jpg> <outdir> [--name N] [--size 1024] [--strength S] [--delight] ...
#   python make_pbr.py <spec.json> <outdir>   spec = {name: {src, strength, rough_base, rough_var, delight}}
#   python make_pbr.py --selftest
import argparse, json, os, sys, tempfile
import numpy as np
from PIL import Image

W = np.array([0.299, 0.587, 0.114])
DEFAULTS = dict(size=1024, strength=8.0, rough_base=0.75, rough_var=0.15, rough_min=0.05, rough_max=1.0,
                convention="opengl", delight=False, highpass=64.0, blur=1.0, ao=False)


def blur(a, sigma):            # wrap-around gaussian via FFT
    if sigma <= 0:
        return a
    fy = np.fft.fftfreq(a.shape[0])[:, None]
    fx = np.fft.rfftfreq(a.shape[1])[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.fft.irfft2(np.fft.rfft2(a) * g, s=a.shape)


def load(path, size):          # resample a 3x3 tiling and keep the centre, so edges see their wrap neighbours
    im = Image.open(path).convert("RGB")
    if im.size != (size, size):
        a = np.tile(np.asarray(im), (3, 3, 1))
        im = Image.fromarray(a).resize((3 * size, 3 * size), Image.LANCZOS).crop((size, size, 2 * size, 2 * size))
    return np.asarray(im, np.float64) / 255.0


def save(a, path):
    Image.fromarray(np.floor(np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)
    return path


def make_pbr(path, outdir, name=None, **opts):
    o = {**DEFAULTS, **opts}
    size, u = int(o["size"]), int(o["size"]) / 1024
    name = name or os.path.splitext(os.path.basename(path))[0]
    os.makedirs(outdir, exist_ok=True)
    out = lambda kind: os.path.join(outdir, f"{name}_{kind}.png")
    a = load(path, size)
    if o["delight"]:
        low = blur(a @ W, 128 * u)
        a = np.clip(a * (low.mean() / np.maximum(low, 1e-3))[..., None], 0, 1)
    lum = a @ W
    h = blur(lum - blur(lum, o["highpass"] * u) if o["highpass"] > 0 else lum, o["blur"] * u)
    lo, hi = np.percentile(h, (0.5, 99.5))
    paths = dict(albedo=save(a, out("albedo")),
                 height=save((h - lo) / (hi - lo) if hi - lo > 1e-6 else np.full_like(h, 0.5), out("height")))

    s = lambda dy, dx: np.roll(h, (-dy, -dx), (0, 1))          # s(dy, dx)[y, x] == h[y+dy, x+dx], wrapped
    gx = (s(-1, 1) + 2 * s(0, 1) + s(1, 1) - s(-1, -1) - 2 * s(0, -1) - s(1, -1)) / 8   # Sobel, +x = right
    gy = (s(1, -1) + 2 * s(1, 0) + s(1, 1) - s(-1, -1) - 2 * s(-1, 0) - s(-1, 1)) / 8   # +y = down the rows
    k = o["strength"] / u                                       # slope per 1024-texel, whatever the size
    flip = {"opengl": 1, "directx": -1}[o["convention"]]
    n = np.stack([-k * gx, flip * k * gy, np.ones_like(h)], -1)   # opengl: up the image is +Y
    paths["normal"] = save(n / np.linalg.norm(n, axis=-1, keepdims=True) * 0.5 + 0.5, out("normal"))

    d = blur(lum, 32 * u) - lum                                 # darker than surroundings -> rougher
    d = np.clip(d / max(2 * d.std(), 0.02), -1, 1)              # near-flat textures are not noise-amplified
    paths["rough"] = save(np.clip(o["rough_base"] + o["rough_var"] * d, o["rough_min"], o["rough_max"]), out("rough"))
    if o["ao"]:
        paths["ao"] = save(1 - 4 * np.maximum(blur(h, 6 * u) - h, 0), out("ao"))
    return paths


def batch(spec_path, outdir):
    spec, root = json.load(open(spec_path)), os.path.dirname(os.path.abspath(spec_path))
    return {name: make_pbr(os.path.join(root, e["src"]), outdir, name=name,
                           **{k: v for k, v in e.items() if k != "src"}) for name, e in spec.items()}


def selftest():
    tmp = tempfile.mkdtemp()
    rd = lambda p: np.asarray(Image.open(p)).astype(int)
    # flat colour, resampled 300 -> 256: normal is straight up, roughness is exactly the base
    Image.new("RGB", (300, 300), (120, 90, 60)).save(os.path.join(tmp, "flat.png"))
    p = make_pbr(os.path.join(tmp, "flat.png"), tmp, size=256, rough_base=0.6, delight=True, ao=True)
    for kind, path in p.items():
        assert Image.open(path).size == (256, 256), (kind, Image.open(path).size)
    assert (np.abs(rd(p["normal"]) - [128, 128, 255]) <= 1).all(), "flat normal"
    assert (rd(p["rough"]) == 153).all() and (rd(p["ao"]) == 255).all(), "flat rough/ao"
    # tileable sine bumps
    N = 256
    y, x = np.mgrid[0:N, 0:N] * 2 * np.pi / N
    hin = 0.5 + 0.4 * np.sin(2 * x) * np.sin(3 * y)
    Image.fromarray((np.stack([hin] * 3, -1) * 255).round().astype(np.uint8)).save(os.path.join(tmp, "bump.png"))
    gl = rd(make_pbr(os.path.join(tmp, "bump.png"), tmp, name="gl", size=N)["normal"])
    dx = rd(make_pbr(os.path.join(tmp, "bump.png"), tmp, name="dx", size=N, convention="directx")["normal"])
    assert gl.shape == (N, N, 3)
    for ax in (0, 1):          # the wrap seam jumps no more than any interior neighbour pair does
        seam = np.abs(np.take(gl, 0, ax) - np.take(gl, -1, ax)).max()
        assert seam <= np.abs(np.diff(gl, axis=ax)).max() + 1, ("seam", ax, seam)
    assert (gl[..., 0] == dx[..., 0]).all() and (gl[..., 2] == dx[..., 2]).all(), "only green may differ"
    assert (np.abs(gl[..., 1] + dx[..., 1] - 255) <= 1).all(), "directx green is the opengl green flipped"
    dhx, dhy = np.roll(hin, -1, 1) - np.roll(hin, 1, 1), np.roll(hin, -1, 0) - np.roll(hin, 1, 0)
    assert np.mean((gl[..., 0] - 128) * dhx) < 0, "red faces downhill in x"
    assert np.mean((gl[..., 1] - 128) * dhy) > 0, "opengl green faces up the image (downhill in rows)"
    print("selftest ok:", tmp)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?")
    ap.add_argument("outdir", nargs="?")
    ap.add_argument("--name")
    ap.add_argument("--selftest", action="store_true")
    for key, val in DEFAULTS.items():
        flag = "--" + key.replace("_", "-")
        if isinstance(val, bool):
            ap.add_argument(flag, action="store_true")
        elif key == "convention":
            ap.add_argument(flag, choices=["opengl", "directx"], default=val)
        else:
            ap.add_argument(flag, type=type(val), default=val)
    args = ap.parse_args()
    if args.selftest:
        selftest()
        sys.exit()
    if not (args.input and args.outdir):
        ap.error("need <input> <outdir> (or --selftest)")
    if args.input.lower().endswith(".json"):
        print(json.dumps(batch(args.input, args.outdir), indent=1))
    else:
        print(json.dumps(make_pbr(args.input, args.outdir, name=args.name,
                                  **{k: getattr(args, k) for k in DEFAULTS}), indent=1))
