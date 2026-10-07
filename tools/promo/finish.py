"""Crop the accepted generations to size, set the lettering, write the sheets and the Desktop folder.

    PY=~/Desktop/"Backrooms Stay Quiet - Covers 2026-10-04"/.artwork-venv/bin/python     # the only Pillow on this Mac
    "$PY" tools/promo/finish.py            # everything that has an accepted raw
    "$PY" tools/promo/finish.py --sheet    # only the review sheets of the raws (for QA, before accepting)
    "$PY" tools/promo/finish.py --only icon   # one set (gallery, thumb, ad_landscape, ad_square, ad_portrait, icon)

Codex makes the pictures without lettering (image models misspell). Everything that is read is set here, in one
typeface, so "LEVEL 3" looks the same on every picture and nothing is misspelled. Each picture is written twice:
with lettering, and clean.

`artifacts/promo-20261007/accept.json` holds what QA decided per picture: another raw than `<name>_raw.png`, a
shifted crop, a smaller line, or a dark strip above the picture for the lettering:
{"name": {"raw": "x_try2_raw.png", "focus": [0.5, 0.42], "tag_px": 92, "top_px": 62, "header": 250}}.
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
JOB = ROOT / 'artifacts' / 'promo-20261007'
DESK = Path.home() / 'Desktop' / 'Backrooms Stay Quiet - Promo 2026-10-07'
DIN = '/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf'
CREAM, AMBER = (243, 236, 218), (237, 168, 39)

SIZE = {'gallery': (1920, 1080), 'thumb': (1920, 1080), 'ad_landscape': (1920, 1080), 'ad_square': (1080, 1080),
        'ad_portrait': (1080, 1920), 'icon': (1024, 1024)}
FOLDER = {'gallery': '1 Gallery (1920x1080)', 'thumb': '2 Thumbnails (1920x1080)',
          'ad_landscape': '3 Ad campaign/landscape 1920x1080', 'ad_square': '3 Ad campaign/square 1080x1080',
          'ad_portrait': '3 Ad campaign/vertical 1080x1920', 'icon': '4 Icons (1024x1024)'}


def font(px):
    return ImageFont.truetype(DIN, int(round(px)))


def tracked_width(draw, text, f, track):
    return sum(draw.textlength(ch, font=f) for ch in text) + track * (len(text) - 1)


def tracked(draw, x, y, text, f, fill, track=0.0, shadow=None):
    """Letters set one by one so the spacing can be opened up. y is the top of the capitals."""
    top = f.getbbox('H')[1]
    for ch in text:
        if shadow:
            draw.text((x + shadow, y - top + shadow), ch, font=f, fill=(0, 0, 0, 150))
        draw.text((x, y - top), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + track
    return x


def cap(f):
    box = f.getbbox('H')
    return box[3] - box[1]


def shade(im, box, strength=0.62, feather=0.55):
    """Darken a soft-edged patch behind lettering: no box, no band, just less picture there."""
    w, h = im.size
    x0, y0, x1, y1 = [int(v) for v in box]
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rectangle((x0, y0, x1, y1), fill=int(255 * strength))
    blur = max(8, int(min(x1 - x0, y1 - y0) * feather))
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    return Image.composite(Image.new('RGB', (w, h), (0, 0, 0)), im, mask)


def lockup(im, x, y, scale, align='left', small=False):
    """BACKROOMS / STAY QUIET / CO-OP HORROR. (x, y) is the top-left, or the top-centre when align is 'centre'.
    Returns the y under it."""
    d = ImageDraw.Draw(im, 'RGBA')
    f1, f2, f3 = font(34 * scale), font(104 * scale), font(24 * scale)
    t1, t2, t3 = 9 * scale, 1.5 * scale, 7 * scale
    rows = [('BACKROOMS', f1, t1, CREAM), ('STAY QUIET', f2, t2, CREAM), ('CO-OP HORROR', f3, t3, AMBER)]
    gaps = [14 * scale, 16 * scale]
    width = max(tracked_width(d, s, f, t) for s, f, t, _ in rows)
    for i, (s, f, t, colour) in enumerate(rows):
        w = tracked_width(d, s, f, t)
        px = x - w / 2 if align == 'centre' else x
        tracked(d, px, y, s, f, colour, t, shadow=max(1, int(2 * scale)))
        y += cap(f) + (gaps[i] if i < len(gaps) else 0)
    return y, width


def level_line(im, level, name):
    """Gallery: a small LEVEL n in the lower-left corner, the place's name beside it."""
    w, h = im.size
    s = h / 1080
    x, y = int(64 * s), int(h - 64 * s - 54 * s)
    im = shade(im, (0, y - 70 * s, 620 * s, h), 0.5, 0.6)
    d = ImageDraw.Draw(im, 'RGBA')
    f_big, f_small = font(64 * s), font(34 * s)
    end = tracked(d, x, y, f'LEVEL {level}', f_big, CREAM, 3 * s, shadow=2)
    d.rectangle((end + 14 * s, y + 2 * s, end + 16 * s, y + cap(f_big) - 2 * s), fill=AMBER + (255,))
    tracked(d, end + 32 * s, y + cap(f_big) - cap(f_small), name, f_small, CREAM, 5 * s, shadow=1)
    return im


def title(im):
    """Thumbnail: the title in the upper-left third."""
    w, h = im.size
    s = h / 1080
    im = shade(im, (-200, -200, 900 * s, 470 * s), 0.6, 0.45)
    lockup(im, 76 * s, 72 * s, 1.4 * s)      # large: the store shows this picture 320 pixels wide
    return im


def wrap(d, text, f, track, limit):
    """One line when it fits. Otherwise two: broken between sentences when there are two, else where the two
    lines come out most alike (never one word left alone under a full line)."""
    def width(t):
        return tracked_width(d, t, f, track)
    if width(text) <= limit:
        return [text]
    words = text.split(' ')
    splits = [(' '.join(words[:i]), ' '.join(words[i:])) for i in range(1, len(words))]
    splits = [(a, b) for a, b in splits if width(a) <= limit and width(b) <= limit]
    if splits:
        sentences = [(a, b) for a, b in splits if a.endswith(('.', '?', '!'))]
        return list(min(sentences or splits, key=lambda ab: abs(width(ab[0]) - width(ab[1]))))
    lines, line = [], ''
    for word in words:
        trial = (line + ' ' + word).strip()
        if line and width(trial) > limit:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def advert(im, kind, tagline, tag_px=None, top_px=None):
    """Ad: the line that sells it, large; the game's name under it."""
    w, h = im.size
    d = ImageDraw.Draw(im, 'RGBA')
    if kind == 'ad_landscape':
        s = h / 1080
        f = font(92 * s)
        lines = wrap(d, tagline, f, 2 * s, 760 * s)
        height = len(lines) * (cap(f) + 20 * s) + 120 * s
        im = shade(im, (-200, -200, 900 * s, 110 * s + height), 0.6, 0.45)
        d = ImageDraw.Draw(im, 'RGBA')
        x, y = 72 * s, 72 * s
        for line in lines:
            tracked(d, x, y, line, f, CREAM, 2 * s, shadow=3)
            y += cap(f) + 20 * s
        y += 10 * s
        d.rectangle((x, y, x + 120 * s, y + 4 * s), fill=AMBER + (255,))
        y += 26 * s
        f2, f3 = font(40 * s), font(24 * s)
        end = tracked(d, x, y, 'BACKROOMS: STAY QUIET', f2, CREAM, 4 * s, shadow=2)
        tracked(d, end + 22 * s, y + cap(f2) - cap(f3), 'CO-OP HORROR', f3, AMBER, 6 * s, shadow=1)
        return im
    s = w / 1080
    f = font((tag_px or (96 if kind == 'ad_square' else 108)) * s)
    lines = wrap(d, tagline, f, 2 * s, 940 * s)
    top = (top_px or (64 if kind == 'ad_square' else 120)) * s
    height = len(lines) * (cap(f) + 22 * s) + 110 * s
    im = shade(im, (-200, -300, w + 200, top + height + 30 * s), 0.6, 0.4)
    d = ImageDraw.Draw(im, 'RGBA')
    y = top
    for line in lines:
        tracked(d, w / 2 - tracked_width(d, line, f, 2 * s) / 2, y, line, f, CREAM, 2 * s, shadow=3)
        y += cap(f) + 22 * s
    y += 8 * s
    d.rectangle((w / 2 - 60 * s, y, w / 2 + 60 * s, y + 4 * s), fill=AMBER + (255,))
    y += 26 * s
    f2, f3 = font(40 * s), font(24 * s)
    a, b = 'BACKROOMS: STAY QUIET', 'CO-OP HORROR'
    wa, wb = tracked_width(d, a, f2, 4 * s), tracked_width(d, b, f3, 6 * s)
    x = w / 2 - (wa + 22 * s + wb) / 2
    end = tracked(d, x, y, a, f2, CREAM, 4 * s, shadow=2)
    tracked(d, end + 22 * s, y + cap(f2) - cap(f3), b, f3, AMBER, 6 * s, shadow=1)
    return im


def accepted():
    path = JOB / 'accept.json'
    return json.loads(path.read_text()) if path.exists() else {}


def raw_of(name, accept):
    entry = accept.get(name, {})
    if entry.get('reject'):
        return None, None
    path = JOB / 'raw' / entry.get('raw', f'{name}_raw.png')
    return (path if path.exists() else None), tuple(entry.get('focus', (0.5, 0.5)))


def sheet(rows, path, cell, cols, label=16):
    """A labelled contact sheet of (name, image)."""
    if not rows:
        return
    cw, ch = cell
    n = (len(rows) + cols - 1) // cols
    out = Image.new('RGB', (cols * (cw + 20) + 20, n * (ch + 20 + label + 14) + 20), '#14171c')
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', label)
    for i, (name, im) in enumerate(rows):
        x, y = 20 + (i % cols) * (cw + 20), 20 + (i // cols) * (ch + 20 + label + 14)
        thumb = im.convert('RGB')
        if thumb.width > cw or thumb.height > ch:      # never enlarged: a 64-pixel icon is shown at 64
            thumb = ImageOps.contain(thumb, cell, Image.Resampling.LANCZOS)
        out.paste(thumb, (x + (cw - thumb.width) // 2, y + (ch - thumb.height) // 2))
        d.text((x, y + ch + 6), name, font=f, fill='#eee8da')
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, quality=92)
    print('sheet', path.relative_to(path.parents[1]) if path.is_relative_to(JOB) else path.name, out.size)


def main():
    images = json.loads((JOB / 'images.json').read_text())
    accept = accepted()
    if '--sheet' in sys.argv:
        by_job = {}
        for path in sorted((JOB / 'raw').glob('*.png')):
            name = path.name.replace('_raw.png', '')
            base = name.split('_try')[0]
            job = next((i['job'] for i in images if i['name'] == base), '?')
            by_job.setdefault(job, []).append((name, Image.open(path)))
        for job, rows in sorted(by_job.items()):
            sheet(rows, JOB / 'review' / f'raw_{job}.jpg', (760, 507), 3)
        return
    only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None
    assert only is None or only in SIZE, only
    done, missing, report = [], [], []
    rows = {k: [] for k in SIZE}
    for spec in images:
        name, kind = spec['name'], spec['set']
        if only and kind != only:
            continue
        raw, focus = raw_of(name, accept)
        if not raw:
            missing.append(name)
            continue
        with Image.open(raw) as opened:
            src = opened.convert('RGB')
        clean = ImageOps.fit(src, SIZE[kind], Image.Resampling.LANCZOS, centering=focus)
        if kind == 'icon':
            # an icon carries no lettering: the 1024 picture, and the 512 that is Roblox's own minimum
            for root in (JOB / 'final', DESK):
                folder = root / FOLDER[kind]
                (folder / '512x512').mkdir(parents=True, exist_ok=True)
                clean.save(folder / f'{name}.png', compress_level=4)
                clean.resize((512, 512), Image.Resampling.LANCZOS).save(folder / '512x512' / f'{name}_512.png', compress_level=4)
            rows[kind].append((name, clean))
            report.append(dict(name=name, set=kind, width=clean.width, height=clean.height, raw=raw.name))
            done.append(name)
            continue
        if kind == 'gallery':
            lettered = level_line(clean.copy(), spec['level'], spec['level_name'])
        elif kind == 'thumb':
            lettered = title(clean.copy())
        else:
            over = accept.get(name, {})
            base = clean.copy()
            if over.get('header'):
                # a picture with no calm space of its own (the six bands): the lettering gets a dark strip above it
                w, h = SIZE[kind]
                base = Image.new('RGB', (w, h), (9, 9, 11))
                base.paste(ImageOps.fit(src, (w, h - over['header']), Image.Resampling.LANCZOS, centering=focus), (0, over['header']))
            lettered = advert(base, kind, spec['tagline'], over.get('tag_px'), over.get('top_px'))
        # encoded once (a 1920 x 1080 PNG takes a couple of seconds), then copied to the Desktop
        folder = JOB / 'final' / FOLDER[kind]
        (folder / 'clean (no lettering)').mkdir(parents=True, exist_ok=True)
        lettered.save(folder / f'{name}.png', compress_level=4)
        clean.save(folder / 'clean (no lettering)' / f'{name}_clean.png', compress_level=4)
        desk = DESK / FOLDER[kind]
        (desk / 'clean (no lettering)').mkdir(parents=True, exist_ok=True)
        shutil.copy2(folder / f'{name}.png', desk / f'{name}.png')
        shutil.copy2(folder / 'clean (no lettering)' / f'{name}_clean.png', desk / 'clean (no lettering)' / f'{name}_clean.png')
        assert lettered.size == SIZE[kind] and clean.size == SIZE[kind]
        rows[kind].append((name, lettered))
        report.append(dict(name=name, set=kind, width=lettered.width, height=lettered.height, raw=raw.name))
        done.append(name)
    for root in (JOB / 'final', DESK):
        sheet(rows['gallery'], root / 'contact sheets' / 'gallery.jpg', (640, 360), 3)
        sheet(rows['thumb'], root / 'contact sheets' / 'thumbnails.jpg', (640, 360), 3)
        sheet(rows['ad_landscape'], root / 'contact sheets' / 'ads landscape.jpg', (640, 360), 3)
        sheet(rows['ad_square'], root / 'contact sheets' / 'ads square.jpg', (420, 420), 4)
        sheet(rows['ad_portrait'], root / 'contact sheets' / 'ads vertical.jpg', (300, 534), 4)
        # how the store shows them: 320 x 180
        small = [(n, ImageOps.fit(im, (320, 180))) for n, im in rows['thumb'] + rows['gallery']]
        sheet(small, root / 'contact sheets' / 'at store size 320x180.jpg', (320, 180), 6, label=11)
        sheet(rows['icon'], root / 'contact sheets' / 'icons.jpg', (380, 380), 5)
        # how Roblox shows an icon: 150 on the game's page and in lists, 64 and smaller in menus
        tiny = [(n.split('_')[0] + ' 150', im.resize((150, 150), Image.Resampling.LANCZOS)) for n, im in rows['icon']]
        tiny += [(n.split('_')[0] + ' 64', im.resize((64, 64), Image.Resampling.LANCZOS)) for n, im in rows['icon']]
        sheet(tiny, root / 'contact sheets' / 'icons at 150 and 64.jpg', (150, 150), 10, label=11)
    (JOB / 'final' / ('size_verification.json' if not only else f'size_verification_{only}.json')).write_text(json.dumps(report, indent=1))
    # the pictures Claude took in the game, and the records
    refs = DESK / 'In-game references (playtest 2026-10-07)'
    refs.mkdir(parents=True, exist_ok=True)
    for path in sorted((JOB / 'refs').glob('*.jpg')):
        shutil.copy2(path, refs / path.name)
    for name in ('README.txt', 'ANALYSIS - the six levels.txt', 'prompts.json'):
        if (JOB / name).exists():
            shutil.copy2(JOB / name, DESK / name)
    print(len(done), 'finished;', len(missing), 'missing:', ', '.join(missing))


if __name__ == '__main__':
    main()
