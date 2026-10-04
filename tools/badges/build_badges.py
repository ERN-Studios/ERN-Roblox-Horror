"""The 20 achievement badges, drawn as flat pictograms in the store's own icon style (assets/shop/icons-v2-20261001):
the same charcoal ground and the same four inks, bold geometric shapes, no gradients, no texture, no lettering.
Written as SVG (assets/badges/source), rendered to 512x512 PNG with headless Chrome (assets/badges/icons-512),
copied with a contact sheet to ~/Desktop/Backrooms Stay Quiet - Badges.

    python3 tools/badges/build_badges.py

Roblox crops a badge to a circle: every emblem stays inside the middle 78% of the square.
"""
import subprocess, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BG, C, T, A, R = '#161D20', '#F3ECDA', '#4FADAA', '#EDA827', '#F2725D'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'


def door(x, y, w, h, colour, leaf=C):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{colour}"/>'
            f'<rect x="{x + w * 0.16}" y="{y + h * 0.1}" width="{w * 0.68}" height="{h * 0.9}" fill="{BG}"/>'
            f'<polygon points="{x + w * 0.16},{y + h * 0.1} {x + w * 0.62},{y + h * 0.2} {x + w * 0.62},{y + h} {x + w * 0.16},{y + h}" fill="{leaf}"/>')


def person(cx, cy, s, colour):
    return (f'<circle cx="{cx}" cy="{cy - 62 * s}" r="{30 * s}" fill="{colour}"/>'
            f'<rect x="{cx - 44 * s}" y="{cy - 24 * s}" width="{88 * s}" height="{112 * s}" rx="{26 * s}" fill="{colour}"/>'
            f'<rect x="{cx - 22 * s}" y="{cy - 72 * s}" width="{44 * s}" height="{16 * s}" rx="{6 * s}" fill="{BG}"/>')


BADGES = {
    'Welcome': door(156, 116, 200, 280, C) + f'<polygon points="282,146 356,146 356,396 282,396" fill="{A}" opacity="1"/><polygon points="188,144 282,172 282,396 188,396" fill="{C}"/><circle cx="262" cy="282" r="9" fill="{BG}"/>',
    'FirstClearLevel1': f'<rect x="116" y="150" width="280" height="250" fill="{A}"/>' + ''.join(
        f'<polygon points="{116 + i * 56},400 {144 + i * 56},340 {172 + i * 56},400" fill="{BG}" opacity="0.28"/>' for i in range(5)) +
        f'<rect x="166" y="112" width="180" height="76" rx="8" fill="{C}"/><rect x="252" y="112" width="8" height="76" fill="{BG}"/><rect x="166" y="146" width="180" height="8" fill="{BG}"/>',
    'FirstClearLevel2': f'<path d="M126 400 V250 A130 130 0 0 1 386 250 V400 H336 V250 A80 80 0 0 0 176 250 V400 Z" fill="{C}"/>'
        f'<path d="M176 330 q20 -22 40 0 t40 0 t40 0 t40 0 V400 H176 Z" fill="{T}"/>'
        f'<path d="M110 372 q24 -22 48 0 t48 0 t48 0 t48 0 t48 0 t48 0" stroke="{T}" stroke-width="16" fill="none"/>',
    'FirstClearLevel3': f'<polygon points="256,104 356,372 156,372" fill="{R}"/><polygon points="226,184 286,184 304,232 208,232" fill="{A}"/><polygon points="190,280 322,280 340,328 172,328" fill="{A}"/>'
        f'<circle cx="256" cy="104" r="26" fill="{C}"/><rect x="140" y="372" width="232" height="26" rx="13" fill="{C}"/>'
        f'<circle cx="136" cy="200" r="11" fill="{T}"/><circle cx="380" cy="230" r="11" fill="{A}"/><circle cx="392" cy="150" r="9" fill="{T}"/><circle cx="124" cy="300" r="9" fill="{C}"/>',
    'FirstClearLevel4': f'<rect x="120" y="118" width="272" height="16" rx="8" fill="{R}"/><rect x="150" y="152" width="212" height="14" rx="7" fill="{T}"/>'
        f'<rect x="176" y="196" width="160" height="130" rx="26" fill="{C}"/><rect x="150" y="300" width="212" height="56" rx="18" fill="{C}"/>'
        f'<rect x="140" y="250" width="34" height="120" rx="14" fill="{R}"/><rect x="338" y="250" width="34" height="120" rx="14" fill="{R}"/><rect x="190" y="356" width="18" height="44" fill="{C}"/><rect x="304" y="356" width="18" height="44" fill="{C}"/>',
    'FirstClearLevel5': f'<rect x="108" y="170" width="120" height="230" fill="{C}"/><rect x="250" y="230" width="84" height="170" fill="{C}"/><rect x="356" y="290" width="52" height="110" fill="{C}"/>'
        f'<circle cx="168" cy="134" r="36" fill="{T}"/>',
    'FirstClearLevel6': f'<rect x="300" y="120" width="22" height="270" fill="{C}"/><rect x="366" y="120" width="22" height="270" fill="{C}"/>' + ''.join(
        f'<rect x="300" y="{160 + i * 52}" width="88" height="16" fill="{C}"/>' for i in range(5)) +
        f'<path d="M322 132 C230 140 250 300 110 330 V386 C290 370 290 200 322 190 Z" fill="{A}"/><circle cx="150" cy="150" r="30" fill="{T}"/><circle cx="214" cy="118" r="18" fill="{R}"/>',
    'CampaignComplete': door(102, 170, 92, 180, A) + door(210, 150, 92, 200, T) + door(318, 170, 92, 180, R),
    'AllSix': door(126, 122, 74, 124, A) + door(219, 122, 74, 124, T) + door(312, 122, 74, 124, R)
        + door(126, 266, 74, 124, R) + door(219, 266, 74, 124, A) + door(312, 266, 74, 124, T),
    'BetterTogether': person(190, 276, 1.0, C) + person(322, 276, 1.0, A) + f'<rect x="222" y="296" width="68" height="26" rx="13" fill="{T}"/>',
    'L5NoFall': f'<rect x="96" y="318" width="320" height="34" fill="{T}"/><path d="M214 150 H286 V262 H346 a34 34 0 0 1 34 34 V318 H214 Z" fill="{C}"/><rect x="214" y="186" width="72" height="16" fill="{BG}"/>',
    'L5Balls': f'<rect x="96" y="330" width="130" height="70" fill="{C}"/><rect x="286" y="330" width="130" height="70" fill="{C}"/>'
        f'<circle cx="256" cy="286" r="46" fill="{T}"/><rect x="208" y="130" width="16" height="84" rx="8" fill="{C}"/><rect x="248" y="104" width="16" height="110" rx="8" fill="{C}"/><rect x="288" y="130" width="16" height="84" rx="8" fill="{C}"/>',
    'L5Mint': f'<rect x="96" y="286" width="96" height="114" fill="{C}"/><rect x="320" y="170" width="96" height="230" fill="{C}"/><polygon points="176,286 336,170 352,192 192,308" fill="{T}"/>',
    'L5Coral': f'<path d="M116 116 H396 V396 H166 V216 H296 V296 H246 V266 H216 V346 H346 V166 H116 Z" fill="{R}"/>',
    'L5TeamLift': f'<ellipse cx="256" cy="300" rx="160" ry="74" fill="{C}"/><ellipse cx="256" cy="286" rx="160" ry="74" fill="{T}"/>' + ''.join(
        f'<rect x="{x}" y="{y}" width="30" height="62" rx="15" fill="{C}"/>' for x, y in ((164, 232), (204, 244), (278, 244), (318, 232))),
    'L6HomeFree': f'<rect x="222" y="130" width="68" height="270" rx="10" fill="{A}"/><rect x="222" y="236" width="68" height="16" fill="{BG}"/>'
        f'<polygon points="256,84 270,118 306,118 277,140 288,174 256,154 224,174 235,140 206,118 242,118" fill="{C}"/>'
        f'<rect x="122" y="250" width="100" height="26" rx="13" fill="{T}"/><rect x="290" y="250" width="100" height="26" rx="13" fill="{T}"/>',
    'L6Caught': f'<circle cx="256" cy="246" r="128" fill="{C}"/><rect x="150" y="196" width="96" height="56" rx="24" fill="{R}"/><rect x="266" y="196" width="96" height="56" rx="24" fill="{R}"/>'
        f'<path d="M216 306 q40 26 80 0" stroke="{BG}" stroke-width="14" fill="none" stroke-linecap="round"/><polygon points="250,118 268,156 246,176 262,206" fill="none" stroke="{BG}" stroke-width="8"/>',
    'L6Party': f'<rect x="250" y="88" width="12" height="60" fill="{C}"/><circle cx="256" cy="232" r="92" fill="{C}"/>' + ''.join(
        f'<rect x="164" y="{176 + i * 36}" width="184" height="8" fill="{BG}"/>' for i in range(4)) + ''.join(
        f'<rect x="{196 + i * 38}" y="140" width="8" height="184" fill="{BG}"/>' for i in range(4)) +
        f'<polygon points="182,330 110,410 150,410" fill="{T}"/><polygon points="330,330 402,410 362,410" fill="{R}"/><polygon points="244,336 236,412 276,412 268,336" fill="{A}"/>',
    'L6Survivor': f'<rect x="110" y="270" width="292" height="130" fill="{T}"/><circle cx="256" cy="262" r="56" fill="{C}"/><rect x="110" y="270" width="292" height="130" fill="{T}"/>'
        f'<circle cx="236" cy="246" r="9" fill="{BG}"/><circle cx="276" cy="246" r="9" fill="{BG}"/>' + ''.join(
        f'<rect x="{196 + i * 52}" y="110" width="18" height="78" rx="9" fill="{A}"/>' for i in range(3)),
    'L6Escaped': f'<circle cx="150" cy="238" r="62" fill="{R}"/><rect x="88" y="238" width="124" height="162" rx="30" fill="{R}"/>'
        f'<circle cx="318" cy="170" r="34" fill="{C}"/><polygon points="286,214 352,214 372,300 330,300 346,400 306,400 296,326 262,400 222,388 266,300 250,262" fill="{C}"/>'
        f'<rect x="212" y="236" width="60" height="22" rx="11" fill="{C}"/><rect x="340" y="240" width="60" height="22" rx="11" fill="{C}"/>',
}

source, icons = ROOT / 'assets' / 'badges' / 'source', ROOT / 'assets' / 'badges' / 'icons-512'
desktop = Path.home() / 'Desktop' / 'Backrooms Stay Quiet - Badges'
for folder in (source, icons, desktop):
    folder.mkdir(parents=True, exist_ok=True)
for key, body in BADGES.items():
    svg = source / f'badge_{key}.svg'
    svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512"><rect width="512" height="512" fill="{BG}"/>{body}</svg>')
    png = icons / f'badge_{key}.png'
    subprocess.run([CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=512,512',
                    f'--screenshot={png}', f'file://{svg}'], capture_output=True)
    shutil.copy(png, desktop / png.name)
keys = list(BADGES)
rows = []
inputs = []
for key in keys:
    inputs += ['-i', str(icons / f'badge_{key}.png')]
layout = ''.join(f'[{i}:v]scale=256:256[s{i}];' for i in range(len(keys)))
for r in range(4):
    layout += ''.join(f'[s{r * 5 + c}]' for c in range(5)) + f'hstack=inputs=5[r{r}];'
layout += '[r0][r1][r2][r3]vstack=inputs=4'
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *inputs, '-filter_complex', layout, str(desktop / 'contact_sheet.jpg')])
print(len(keys), 'badges ->', icons, 'and', desktop)
