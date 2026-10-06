"""The Level 6 arena's PBR texture sets: colour, normal and roughness maps that tile.

    /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 tools/level6_playground/pbr/make_pbr.py
    ... make_pbr.py foam_floor vinyl_quilt          # only these

PBR_20261006 (owner: "recreate level 6 with PBR textures for every texture where it makes sense, and the floor ...
almost everything would look much better with a detailed, extensive PBR look"). Until now the arena was flat
SmoothPlastic and Concrete with see-through overlay pictures for seams: no surface had a normal or a roughness map,
so no lamp ever left a highlight on anything. The look to hit is the approved concept (artifacts/
level6-concept-20261006b): interlocking foam mats in a blue and green check with a worn, almost wet sheen; fat,
glossy, stitched vinyl padding on every wall, post and panel; scuffed moulded plastic slides.

Every map is made here from numbers (numpy, the one in Blender's Python): nothing photographed, nothing generated
by a model. All noise is shaped in the frequency domain, so every map repeats without a seam. A set is three
1024 x 1024 PNGs in assets/level6-pbr-20261006/<name>_{color,normal,roughness}.png; SETS below says how many studs
one repeat covers and which Roblox material it stands on. Normal maps are OpenGL style (green is up), which is what
Roblox reads.

    foam_floor     2 x 2 foam mats, 4 studs each: the check, the jigsaw joints, the embossed grip, dirt
    vinyl_quilt    2 x 2 stitched pads, 3.5 studs each (a 7-stud deck cell is exactly one repeat)
    vinyl_plain    the same skin without seams: posts, beams, tube bumpers
    vinyl_filthy   the quilt gone to mould: the exit room
    block_wall     painted concrete block, 2 x 1 studs, drips and grime
    roof_deck      ribbed steel roof deck, rust at the laps
    slide_plastic  moulded plastic: orange peel, scratches, scuffs (for meshes and tubes; nearly colourless)
    net_knotted    not a set: one picture with alpha, the knotted cord for the nets' Textures
"""
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets' / 'level6-pbr-20261006'
N = 1024
TAU = 2 * np.pi

SETS = {    # studs one repeat covers, the Roblox material it stands on, what it is called in MaterialService
    'foam_floor': {'studs': 6, 'base': 'SmoothPlastic', 'variant': 'L6 Foam Floor'},      # 6: the court's 12-stud tiles are two repeats
    'vinyl_quilt': {'studs': 7, 'base': 'SmoothPlastic', 'variant': 'L6 Vinyl Quilt'},
    'vinyl_plain': {'studs': 6, 'base': 'SmoothPlastic', 'variant': 'L6 Vinyl Plain'},
    'vinyl_filthy': {'studs': 7, 'base': 'SmoothPlastic', 'variant': 'L6 Vinyl Filthy'},
    'block_wall': {'studs': 16, 'base': 'Concrete', 'variant': 'L6 Block Wall'},
    'roof_deck': {'studs': 16, 'base': 'Metal', 'variant': 'L6 Roof Deck'},
    'slide_plastic': {'studs': 8, 'base': 'SmoothPlastic', 'variant': 'L6 Slide Plastic'},
}

Y, X = np.mgrid[0:N, 0:N]
U, V = X / N, Y / N                                   # 0..1 across one repeat; V runs DOWN the picture


# ---- tools -----------------------------------------------------------------------------------------------------------
def save(name, kind, array):
    """Write an 8-bit PNG: H x W (grey, stored as RGB), H x W x 3, or H x W x 4 with alpha."""
    a = np.clip(array, 0.0, 1.0)
    if a.ndim == 2:
        a = np.repeat(a[:, :, None], 3, axis=2)
    a = np.round(a * 255).astype(np.uint8)
    channels = a.shape[2]
    rows = np.concatenate([np.zeros((N, 1), np.uint8), a.reshape(N, N * channels)], axis=1).tobytes()

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6 if channels == 4 else 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / (f'{name}_{kind}.png' if kind else f'{name}.png')
    path.write_bytes(png)
    return path


_FX = np.fft.fftfreq(N) * N
_KX, _KY = np.meshgrid(_FX, _FX)


def unit(a):
    return (a - a.min()) / (a.max() - a.min() + 1e-12)


def noise(seed, beta=1.6, lo=1.0, hi=None, sx=1.0, sy=1.0):
    """Seamless noise in 0..1. beta: how fast the detail falls away; lo/hi: the band, in waves per repeat;
    sx, sy above 1 stretch it along x or y (streaks, drips)."""
    rng = np.random.default_rng(seed)
    k = np.sqrt((_KX * sx) ** 2 + (_KY * sy) ** 2)
    amp = np.where(k > 0, np.maximum(k, 1e-9) ** -beta, 0.0)
    amp[k < lo] = 0.0
    if hi:
        amp = amp * np.exp(-(k / hi) ** 4)
    return unit(np.real(np.fft.ifft2(np.fft.fft2(rng.standard_normal((N, N))) * amp)))


def blur(a, pixels):
    k2 = _KX ** 2 + _KY ** 2
    return np.real(np.fft.ifft2(np.fft.fft2(a) * np.exp(-2 * (np.pi * pixels / N) ** 2 * k2)))


def step(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    """a where t is 0, b where it is 1. Either may be a picture, a grey picture or one (r, g, b)."""
    t = np.clip(t, 0.0, 1.0)
    a, b = np.asarray(a, float), np.asarray(b, float)
    if a.ndim == 3 or b.ndim == 3 or a.shape == (3,) or b.shape == (3,):
        a = a[None, None, :] if a.ndim == 1 else (a[:, :, None] if a.ndim == 2 else a)
        b = b[None, None, :] if b.ndim == 1 else (b[:, :, None] if b.ndim == 2 else b)
        return a + (b - a) * t[:, :, None]
    return a + (b - a) * t


def normal_map(height, strength):
    """Height (in studs) -> an OpenGL normal map. `strength` = pixels per stud of this map."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength      # down the picture
    nz = 1.0 / np.sqrt(dx * dx + dy * dy + 1.0)
    return np.stack([(-dx * nz) * 0.5 + 0.5, (dy * nz) * 0.5 + 0.5, nz * 0.5 + 0.5], axis=2)


def strokes(seed, count, length, width, straight=0.9):
    """Scratches and scuff marks that run off one edge and come in at the other. length, width in pixels."""
    rng = np.random.default_rng(seed)
    canvas = np.zeros((N, N))
    for _ in range(count):
        x, y, a = rng.uniform(0, N), rng.uniform(0, N), rng.uniform(0, TAU)
        n = int(rng.uniform(0.3, 1.0) * length)
        t = np.arange(n)
        bend = rng.normal(0, (1 - straight) * 0.02)
        xs = (x + np.cos(a + bend * t) * t).astype(int) % N
        ys = (y + np.sin(a + bend * t) * t).astype(int) % N
        fade = np.sin(np.pi * t / max(n, 1)) * rng.uniform(0.4, 1.0)
        np.add.at(canvas, (ys, xs), fade)
    return np.clip(blur(canvas, width) * (width * 2.2 + 1), 0, 1)


def spots(seed, count, radius):
    """Round specks (mould, pits). radius in pixels."""
    rng = np.random.default_rng(seed)
    canvas = np.zeros((N, N))
    np.add.at(canvas, (rng.integers(0, N, count), rng.integers(0, N, count)), rng.uniform(0.4, 1.0, count))
    out = blur(canvas, radius)
    return np.clip(out / (out.max() + 1e-9) * 2.2, 0, 1)


# ---- foam mats -------------------------------------------------------------------------------------------------------
def foam_floor():
    px = N / SETS['foam_floor']['studs']                           # pixels per stud
    TILES, TEETH, BITE = 2, 9, 0.034                               # mats per repeat, teeth along an edge, their reach
    u, v = U * TILES, V * TILES

    def tooth(s):                                                  # a row of rounded dovetails, -1..1
        return np.tanh(np.sin(TAU * s * TEETH) * 3.2)
    # the joint between two mats is a toothed line, and which mat a point belongs to follows the teeth
    ju = u - BITE * tooth(v)
    jv = v - BITE * tooth(u)
    cu, cv = np.floor(ju).astype(int) % TILES, np.floor(jv).astype(int) % TILES
    du = np.minimum(ju % 1.0, 1 - ju % 1.0)                        # distance to the nearest joint, in mats
    dv = np.minimum(jv % 1.0, 1 - jv % 1.0)
    joint = np.minimum(du, dv) * (N / TILES)                       # ... in pixels
    groove = np.exp(-(joint / 2.3) ** 2)
    lip = np.exp(-(joint / 16.0) ** 2)                             # the mat's edge is a little rounded over
    check = (cu + cv) % 2

    # the embossed grip: fine diamonds, and they wear smooth where feet go
    F = 26
    a, b = (u % 1.0), (v % 1.0)
    diamond = 0.5 + 0.5 * np.sin(TAU * F * (a + b)) * np.sin(TAU * F * (a - b))
    wear = step(noise(11, 2.2, 1, 9), 0.42, 0.78)                  # broad patches walked smooth
    dents = noise(12, 2.4, 2, 30)
    scratch = strokes(13, 110, 260, 0.6, 0.97)
    scuff = strokes(14, 60, 150, 3.5, 0.6)
    grime = noise(15, 1.9, 1, 40) * 0.6 + noise(16, 1.2, 8, 140) * 0.4
    stain = step(noise(17, 2.0, 3, 40), 0.66, 0.80) * (0.55 + 0.45 * noise(171, 1.4, 8, 90))
    speck = np.maximum(spots(18, 150, 1.3), spots(181, 40, 2.6) * 0.8) * step(noise(182, 2.0, 1, 12), 0.35, 0.7)

    height = (0.02 * diamond * (1 - 0.8 * wear) + 0.05 * dents - 0.085 * groove - 0.03 * lip
              - 0.006 * scratch - 0.003 * scuff)
    BLUE, GREEN = np.array([0.10, 0.155, 0.37]), np.array([0.165, 0.34, 0.20])
    tint = 1 + 0.06 * (noise(19, 3.0, 1, 3) - 0.5)                 # no two mats quite the same
    colour = mix(BLUE, GREEN, check.astype(float)) * tint[:, :, None]
    colour = colour * (0.80 + 0.28 * (1 - grime))[:, :, None]
    colour = mix(colour, colour * 1.5 + 0.06, 0.35 * wear * diamond)        # worn tops of the grip go pale
    colour = mix(colour, (0.42, 0.42, 0.40), 0.30 * scuff)
    colour = mix(colour, (0.50, 0.50, 0.48), 0.13 * scratch)
    colour = mix(colour, (0.055, 0.05, 0.04), 0.24 * stain)
    colour = mix(colour, (0.03, 0.028, 0.024), 0.9 * groove + 0.25 * lip * grime)
    colour = mix(colour, (0.04, 0.035, 0.03), 0.7 * speck)
    # worn foam has a sheen; dirt, scuffs and the joints kill it; the walked-smooth patches are nearly wet
    rough = 0.29 + 0.10 * (diamond - 0.5) * (1 - wear) - 0.13 * wear + 0.22 * scuff + 0.14 * scratch
    rough = rough + 0.30 * groove + 0.14 * stain + 0.10 * (grime - 0.5) + 0.2 * speck
    return colour, normal_map(height, px), np.clip(rough, 0.1, 0.95)


# ---- vinyl padding ---------------------------------------------------------------------------------------------------
def vinyl(seed, quilt, filthy=False, studs=7.0):
    px = N / studs

    def lines(n, width=0.11):                                      # the contour of a noise field, as thin lines
        return 1 - step(np.abs(n - 0.5) * 2, 0.0, width)
    grain = noise(seed + 1, 0.4, 70, 260)                          # the skin's own pebble
    folds = noise(seed + 2, 2.7, 1, 9)
    across = lines(noise(seed + 3, 1.9, 2, 34, sx=6.0, sy=0.55), 0.085)   # wrinkles that run along x ...
    down = lines(noise(seed + 9, 1.9, 2, 34, sx=0.55, sy=6.0), 0.085)     # ... and along y
    scuff = strokes(seed + 4, 55, 170, 3.0, 0.55)
    scratch = strokes(seed + 5, 90, 220, 0.6, 0.97)
    grime = noise(seed + 6, 1.8, 1, 50)
    seam = np.zeros((N, N))
    stitch = np.zeros((N, N))
    near = np.ones((N, N))
    shade = 0.90 + 0.10 * folds                                   # what a soft light from above would do, painted in
    if quilt:
        CELLS = 2
        a, b = (U * CELLS) % 1.0, (V * CELLS) % 1.0
        da, db = np.minimum(a, 1 - a), np.minimum(b, 1 - b)
        edge = np.minimum(da, db) * (N / CELLS)                    # pixels to the nearest seam
        pillow = (1 - (2 * a - 1) ** 6) * (1 - (2 * b - 1) ** 6)   # fat in the middle, pulled down at the seam
        seam = np.exp(-(edge / 5.5) ** 2)
        near = np.exp(-(edge / 80.0) ** 2)
        shade = (0.70 + 0.30 * pillow ** 0.6) * (0.94 + 0.06 * folds)   # each cushion darkens into its seams
        # the skin is pulled toward its stitching: wrinkles run in at right angles to the seam they come from
        side = np.exp(-((da * N / CELLS) / 95.0) ** 2)             # near a seam that runs down the picture
        top = np.exp(-((db * N / CELLS) / 95.0) ** 2)              # near one that runs across
        crease = np.clip(across * side * (1 - top) + down * top * (1 - side), 0, 1)
        along = np.where(da < db, b, a)
        dash = (np.sin(TAU * along * 46) > 0.25).astype(float)
        stitch = blur(np.exp(-((edge - 9.0) / 2.2) ** 2) * dash, 0.8)
        height = 0.03 * folds * pillow + 0.006 * grain + 0.58 * pillow - 0.14 * seam + 0.03 * stitch - 0.055 * crease
    else:
        patch = step(noise(seed + 10, 2.4, 1, 6), 0.35, 0.7)       # wrinkled here, taut there
        crease = np.clip(across * patch + 0.5 * down * (1 - patch) * step(noise(seed + 11, 2.4, 1, 6), 0.5, 0.8), 0, 1)
        height = 0.10 * folds + 0.006 * grain - 0.045 * crease
    colour = np.ones((N, N, 3)) * 0.96 * shade[:, :, None]
    colour = colour * (0.86 + 0.14 * (1 - step(grime, 0.35, 0.8)))[:, :, None]
    colour = mix(colour, (0.50, 0.49, 0.46), 0.28 * scuff)
    colour = mix(colour, (0.99, 0.99, 0.97), 0.25 * scratch)
    colour = mix(colour, (0.30, 0.28, 0.25), 0.42 * crease)                           # a wrinkle is a shadow, and dirt sits in it
    colour = mix(colour, (0.12, 0.11, 0.09), 0.85 * seam)
    colour = mix(colour, (0.72, 0.70, 0.62), 0.8 * stitch)
    rough = 0.18 + 0.08 * (grain - 0.5) + 0.26 * scuff + 0.12 * scratch + 0.18 * step(grime, 0.45, 0.9) + 0.35 * seam + 0.3 * stitch
    if filthy:
        # mould: it starts in the seams and the low corners and spreads in blotches with a pale fringe
        spread = noise(seed + 20, 2.3, 1, 14) * 0.65 + near * 0.35 * (1 if quilt else 0) + 0.12 * noise(seed + 21, 1.2, 10, 120)
        mould = step(spread, 0.50, 0.66)
        fringe = step(spread, 0.44, 0.52) * (1 - mould)
        speck = spots(seed + 22, 2600, 1.4) * step(spread, 0.36, 0.55)
        drip = step(noise(seed + 23, 2.0, 2, 60, sx=0.35, sy=7.0), 0.55, 0.8) * step(spread, 0.3, 0.6)
        colour = mix(colour, (0.62, 0.60, 0.44), 0.55 * fringe)
        colour = mix(colour, (0.36, 0.33, 0.24), 0.5 * drip)
        colour = mix(colour, (0.075, 0.085, 0.06), 0.88 * mould * (0.75 + 0.25 * grain))
        colour = mix(colour, (0.05, 0.055, 0.04), 0.8 * speck)
        height = height - 0.012 * mould * noise(seed + 24, 0.8, 30, 160)
        rough = mix(rough, 0.82, 0.85 * mould)
        rough = rough + 0.25 * speck + 0.12 * fringe - 0.1 * drip
    return colour, normal_map(height, px), np.clip(rough, 0.1, 0.95)


# ---- painted block ---------------------------------------------------------------------------------------------------
def block_wall():
    studs = SETS['block_wall']['studs']
    px = N / studs
    COURSES, PER = 16, 8                                           # courses up the repeat, blocks along a course
    row = np.floor(V * COURSES).astype(int)
    b = (V * COURSES) % 1.0
    a = (U * PER + 0.5 * (row % 2)) % 1.0                          # running bond
    bed = np.minimum(b, 1 - b) * (N / COURSES)
    head = np.minimum(a, 1 - a) * (N / PER)
    joint = np.minimum(bed, head)
    mortar = np.exp(-(joint / 3.4) ** 2)
    which = (np.floor(U * PER + 0.5 * (row % 2)).astype(int) % PER) * 7 + row * 13
    shade = (np.sin(which * 12.9898) * 43758.5453) % 1.0           # every block a touch different
    pits = spots(31, 5200, 1.3)
    peel = noise(32, 0.6, 50, 220)
    bulge = noise(33, 2.4, 2, 24)
    chips = step(noise(34, 1.5, 12, 90), 0.74, 0.8) * step(noise(35, 2.2, 2, 12), 0.5, 0.7)
    drip = step(noise(36, 2.0, 2, 90, sx=0.3, sy=9.0), 0.52, 0.86)
    damp = step(noise(37, 2.6, 1, 6), 0.55, 0.85)
    grime = noise(38, 1.8, 1, 40)
    height = -0.05 * mortar - 0.02 * pits + 0.006 * peel + 0.012 * bulge - 0.018 * chips + 0.006 * (shade - 0.5)
    colour = np.ones((N, N, 3)) * (0.90 + 0.06 * (shade - 0.5))[:, :, None]
    colour = colour * (0.84 + 0.16 * (1 - grime))[:, :, None]
    colour = mix(colour, (0.52, 0.50, 0.44), 0.55 * mortar)
    colour = mix(colour, (0.60, 0.57, 0.48), 0.38 * drip)
    colour = mix(colour, (0.42, 0.41, 0.36), 0.45 * damp * (0.5 + 0.5 * grime))
    colour = mix(colour, (0.46, 0.45, 0.43), 0.9 * chips)          # bare block where the paint has gone
    colour = mix(colour, (0.35, 0.34, 0.31), 0.5 * pits)
    rough = 0.46 + 0.10 * (peel - 0.5) + 0.25 * mortar + 0.3 * chips + 0.16 * drip + 0.12 * damp + 0.2 * pits
    return colour, normal_map(height, px), np.clip(rough, 0.15, 0.95)


# ---- roof deck -------------------------------------------------------------------------------------------------------
def roof_deck():
    studs = SETS['roof_deck']['studs']
    px = N / studs
    RIBS = 16
    t = (U * RIBS) % 1.0
    rib = step(np.abs(t - 0.5) * 2, 0.34, 0.62)                    # flat crown, sloped web, flat trough
    lap = np.exp(-((np.minimum(V, 1 - V) * N) / 3.0) ** 2)         # where one sheet laps the next
    screw = np.zeros((N, N))
    for k in range(RIBS):
        for row in (0.0, 0.5):
            cx, cy = (k + 0.5) / RIBS * N, row * N
            d2 = ((X - cx + N / 2) % N - N / 2) ** 2 + ((Y - cy + N / 2) % N - N / 2) ** 2
            screw = np.maximum(screw, np.exp(-d2 / 14.0))
    dent = noise(41, 2.5, 2, 18)
    rust_seed = noise(42, 2.1, 1, 30) * 0.6 + lap * 0.25 + screw * 0.5 + noise(43, 1.2, 10, 120) * 0.15
    rust = step(rust_seed, 0.52, 0.7)
    run = step(noise(44, 2.0, 2, 70, sx=0.3, sy=8.0), 0.5, 0.85) * step(rust_seed, 0.35, 0.6)
    dust = noise(45, 1.7, 1, 50)
    height = -0.22 * rib + 0.02 * dent - 0.03 * lap + 0.03 * screw - 0.012 * rust * noise(46, 0.7, 30, 160)
    colour = np.ones((N, N, 3)) * 0.88
    colour = colour * (0.80 + 0.2 * (1 - dust))[:, :, None]
    colour = colour * (1 - 0.22 * rib)[:, :, None]                 # the troughs hold the dirt
    colour = mix(colour, (0.55, 0.36, 0.22), 0.45 * run)
    colour = mix(colour, (0.33, 0.16, 0.08), 0.9 * rust * (0.7 + 0.3 * noise(47, 0.8, 20, 120)))
    colour = mix(colour, (0.25, 0.24, 0.23), 0.8 * screw)
    colour = mix(colour, (0.3, 0.29, 0.27), 0.6 * lap)
    rough = 0.42 + 0.2 * (dust - 0.5) + 0.42 * rust + 0.15 * run + 0.2 * lap
    return colour, normal_map(height, px), np.clip(rough, 0.15, 0.95)


# ---- moulded plastic -------------------------------------------------------------------------------------------------
def slide_plastic():
    px = N / SETS['slide_plastic']['studs']
    peel = noise(51, 0.7, 40, 200)
    wave = noise(52, 2.6, 1, 10)
    fine = strokes(53, 380, 300, 0.6, 0.97)
    deep = strokes(54, 22, 240, 1.0, 0.95)
    scuff = strokes(55, 70, 140, 4.0, 0.5)
    grime = noise(56, 1.8, 1, 40)
    height = 0.005 * peel + 0.012 * wave - 0.0012 * fine - 0.004 * deep
    colour = np.ones((N, N, 3)) * 0.95
    colour = colour * (0.88 + 0.12 * (1 - step(grime, 0.4, 0.85)))[:, :, None]
    colour = mix(colour, (0.26, 0.25, 0.24), 0.30 * scuff)         # rubber from a thousand shoes
    colour = mix(colour, (1.0, 1.0, 1.0), 0.10 * fine)
    colour = mix(colour, (0.62, 0.61, 0.58), 0.18 * deep)
    rough = 0.17 + 0.06 * (peel - 0.5) + 0.14 * fine + 0.2 * deep + 0.3 * scuff + 0.14 * step(grime, 0.5, 0.9)
    return colour, normal_map(height, px), np.clip(rough, 0.08, 0.95)


def net_knotted():
    """Knotted cord netting, 4 meshes across the repeat (the nets' Textures repeat every 5 studs, as before).
    Near-white with a little shading across the cord, so Texture.Color3 still makes it black or yellow."""
    CELLS, CORD = 4, 0.058                                         # meshes per repeat, half a cord's width in meshes
    a, b = (U * CELLS) % 1.0, (V * CELLS) % 1.0
    wob = 0.012 * (noise(61, 2.0, 3, 30) - 0.5) * 8                # cord is never quite straight
    da = np.abs(((a + wob) % 1.0) - 0.5)                           # distance to the cord that runs down ...
    db = np.abs(((b + wob.T) % 1.0) - 0.5)                         # ... and to the one that runs across
    twist_a = 0.5 + 0.5 * np.sin(TAU * (b * 9 + da * 6))           # the lay of the cord
    twist_b = 0.5 + 0.5 * np.sin(TAU * (a * 9 + db * 6))
    width = CORD * (1 + 0.16 * (noise(62, 1.5, 6, 60) - 0.5) * 2)
    fray = 0.007 * (noise(63, 0.6, 60, 240) - 0.5)
    cord_a = 1 - step(da, width * 0.72 + fray, width + fray)
    cord_b = 1 - step(db, width * 0.72 + fray, width + fray)
    knot = 1 - step(np.hypot(da, db), CORD * 1.55, CORD * 2.05)
    alpha = np.clip(np.maximum(np.maximum(cord_a, cord_b), knot), 0, 1)
    round_a = np.sqrt(np.clip(1 - (da / (width + 1e-6)) ** 2, 0, 1))
    round_b = np.sqrt(np.clip(1 - (db / (width + 1e-6)) ** 2, 0, 1))
    shade = np.where(cord_a >= cord_b, round_a * (0.72 + 0.28 * twist_a), round_b * (0.72 + 0.28 * twist_b))
    shade = np.maximum(shade, knot * (0.8 + 0.2 * noise(64, 0.8, 30, 120)))
    grey = 0.45 + 0.55 * shade
    return np.dstack([grey, grey, grey, alpha])


MAKERS = {
    'foam_floor': foam_floor,
    'vinyl_quilt': lambda: vinyl(100, True, False, SETS['vinyl_quilt']['studs']),
    'vinyl_plain': lambda: vinyl(200, False, False, SETS['vinyl_plain']['studs']),
    'vinyl_filthy': lambda: vinyl(300, True, True, SETS['vinyl_filthy']['studs']),
    'block_wall': block_wall,
    'roof_deck': roof_deck,
    'slide_plastic': slide_plastic,
}

if __name__ == '__main__':
    asked = sys.argv[1:]
    wanted = [a for a in asked if a in MAKERS] or ([] if asked else list(MAKERS))
    for name in wanted:
        colour, normal, rough = MAKERS[name]()
        sizes = [save(name, kind, data).stat().st_size for kind, data in (('color', colour), ('normal', normal), ('roughness', rough))]
        print(f'{name:14s} colour mean {colour.mean():.2f}  roughness {rough.min():.2f}..{rough.max():.2f} mean {rough.mean():.2f}'
              f'  normal z min {normal[:, :, 2].min() * 2 - 1:.2f}  files {sum(sizes) // 1024} KB', flush=True)
    if not asked or 'net_knotted' in asked:
        print('net_knotted   ', save('net_knotted', '', net_knotted()).stat().st_size // 1024, 'KB (colour with alpha, for the nets\' Textures)')
    import json
    (OUT / 'sets.json').write_text(json.dumps(SETS, indent=1) + '\n')
