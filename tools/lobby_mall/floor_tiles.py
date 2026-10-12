"""The mall lobby's tile floors: colour, bump (normal) and gloss (roughness) sheets, drawn from one description.

    from floor_tiles import SHEETS, sheet        # sheet(key) -> (colour, normal, roughness) as uint8 RGB arrays

2026-10-12, the owner on the first tile floor: "Gulvet ligner lidt et badeværelses gulv nu, gør tiles større og lav
de her grimme random pattern fra ref billeder" (six photographs of 1990s malls). So: a tile is FOUR studs now (it
was two), the joint is a thin grey line (it was a wide dark one), and beside the plain cream field there are the
patterns those malls laid into their floors:
    floor_tile       plain cream; tinted by the part's colour it is also the tan wall band and the black rows
    floor_checker    black and white, the court round the stand
    floor_redgrey    dull red and grey checker
    floor_bands      stepped diagonal bands of green and pink through white, with grey half tiles
    floor_inlay      one 4 x 4 block of terracotta shades with a turned pale square in its middle
    floor_harlequin  big diamonds in teal, tan, cream and slate blue cut out of square tiles (8 x 8 tiles a sheet)
128 px a tile; a sheet is SHEETS[key] tiles each way and is laid at 4 studs a tile, so StudsPerTile = 4 * SHEETS[key].
A joint runs along every sheet edge, and Roblox lays a material's sheet from the world's origin (seen in play: the
joints of separate floor parts run on through each other), so parts whose edges stand on multiples of 4 studs meet
on joints and a sheet-sized part on a multiple of the sheet shows one whole sheet.
Every tile is glossy and every joint matt and sunk: the bump map is what gives the joints their depth.
"""
import numpy as np

PX = 128
SHEETS = {'floor_tile': 4, 'floor_checker': 4, 'floor_redgrey': 4, 'floor_bands': 4, 'floor_inlay': 4, 'floor_harlequin': 8}
CREAM, WHITE, BLACK, GROUT = (232, 226, 212), (236, 233, 224), (34, 34, 36), (96, 90, 82)
RED, GREY = (128, 52, 58), (172, 174, 178)
GREEN, PINK, LILAC = (70, 128, 102), (222, 166, 168), (146, 142, 158)
TERRA, PALE = ((186, 118, 102), (202, 138, 120), (168, 102, 90)), (226, 180, 166)
TEAL, TAN, SLATE = (36, 84, 78), (190, 142, 102), (72, 98, 150)
JOINT, BEVEL = 1.5, 3.5          # px: half the joint's width, and the slope from the tile's face down into it


def sheet(key):
    tiles = SHEETS[key]
    n = tiles * PX
    yy, xx = np.mgrid[:n, :n]
    x, y = (xx + 0.5) / PX, (yy + 0.5) / PX                 # in tiles
    i, j = xx // PX, yy // PX
    fx, fy = x - i, y - j
    cut = np.full((n, n), np.inf)                           # tiles to the nearest joint that is not on the grid
    region = np.zeros((n, n), int)                          # which piece of a cut tile (for the shade)

    def paint(choices, index):
        return np.asarray(choices, float)[index]

    if key == 'floor_tile':
        rgb = paint([CREAM], np.zeros((n, n), int))
    elif key == 'floor_checker':
        rgb = paint([WHITE, BLACK], (i + j) % 2)
    elif key == 'floor_redgrey':
        rgb = paint([GREY, RED], (i + j) % 2)
    elif key == 'floor_bands':
        step = (i + j) % 4
        half = (step == 2) & ((i - j) % 4 == 0)             # a white tile on the band's edge, cut corner to corner
        grey = half & (fx + fy < 1)
        rgb = paint([WHITE, GREEN, WHITE, PINK], step)
        rgb[grey] = LILAC
        region[grey] = 1
        cut[half] = np.abs(fx + fy - 1)[half] / np.sqrt(2)
    elif key == 'floor_inlay':
        shade = np.random.default_rng(31).integers(0, 3, (tiles, tiles))
        rgb = paint(TERRA, shade[j, i])
        middle = (i >= 1) & (i <= 2) & (j >= 1) & (j <= 2)
        turned = np.abs(x - 2) + np.abs(y - 2)              # the pale square stands on its corner in the middle four
        rgb[middle & (turned < 1)] = PALE
        rgb[middle & (turned >= 1)] = TERRA[2]
        region[middle & (turned < 1)] = 1
        cut[middle] = np.abs(turned - 1)[middle] / np.sqrt(2)
    elif key == 'floor_harlequin':
        a, b = np.floor((x + y) / 4).astype(int), np.floor((x - y) / 4).astype(int)
        rgb = paint([TEAL, TAN, CREAM, SLATE], (a % 2) + 2 * (b % 2))
        region = (a % 2) + 2 * (b % 2)
        cut = np.minimum(np.abs((x + y + 2) % 4 - 2), np.abs((x - y + 2) % 4 - 2)) / np.sqrt(2)
    else:
        raise KeyError(key)

    # no two tiles came out of the kiln alike: a shade for every tile, and for each piece of a cut one
    tone = np.random.default_rng(1012 + tiles).normal(0, 0.016, (tiles, tiles, 4))
    rgb = rgb * (1 + tone[j, i, region % 4])[..., None]

    to_joint = np.minimum(np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)), cut) * PX      # px
    smooth = lambda t: np.clip(t, 0, 1) ** 2 * (3 - 2 * np.clip(t, 0, 1))
    face = smooth((to_joint - JOINT) / BEVEL)               # 1 on the tile's face, 0 down in the joint
    edge = smooth((to_joint - JOINT + 0.6) / 1.2)           # the same, sharp, for what colour a pixel is
    colour = np.asarray(GROUT, float) * (1 - edge[..., None]) + rgb * (0.94 + 0.06 * face[..., None]) * edge[..., None]

    dx = (np.roll(face, -1, 1) - np.roll(face, 1, 1)) / 2
    dy = (np.roll(face, -1, 0) - np.roll(face, 1, 0)) / 2
    normal = np.dstack((-dx * 3.0, dy * 3.0, np.ones_like(dx)))        # green up, as Roblox reads a normal map
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    rough = 0.86 - 0.76 * edge                              # glazed tile 0.10, grout 0.86

    as_bytes = lambda v: np.uint8(np.clip(v, 0, 255) + 0.5)
    return as_bytes(colour), as_bytes((normal * 0.5 + 0.5) * 255), as_bytes(np.repeat(rough[..., None] * 255, 3, axis=2))


if __name__ == '__main__':                                  # a contact sheet for a look
    import sys
    from PIL import Image
    strip = Image.new('RGB', (512 * len(SHEETS), 1024))
    for at, key in enumerate(SHEETS):
        c, nm, r = sheet(key)
        strip.paste(Image.fromarray(c).resize((512, 512)), (512 * at, 0))
        strip.paste(Image.fromarray(nm).resize((512, 512)), (512 * at, 512))
    strip.save(sys.argv[1] if len(sys.argv) > 1 else '/tmp/floor_tiles.jpg', quality=90)
