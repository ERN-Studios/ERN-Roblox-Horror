"""Join the tiles ui_audit.py took into one picture per screen (needs PIL: /usr/local/bin/python3)."""
import sys, json, glob
from pathlib import Path
from PIL import Image
import datetime
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / 'artifacts' / f'ui-review-{datetime.date.today():%Y%m%d}'
for meta_path in sorted(out.glob('tiles_*.json')):
    key = meta_path.stem[len('tiles_'):]
    m = json.loads(meta_path.read_text())
    first = Image.open(out / f'tile_{key}_0_0.jpg')
    k = first.width / m['vw']
    sheet = Image.new('RGB', (round(m['w'] * k), round(m['h'] * k)))
    for r in range(m['rows']):
        for c in range(m['cols']):
            p = out / f'tile_{key}_{r}_{c}.jpg'
            if p.exists(): sheet.paste(Image.open(p), (round(c * m['vw'] * k), round(r * m['vh'] * k)))
    sheet = sheet.resize((m['w'], m['h']), Image.LANCZOS)
    sheet.save(out / f'screen_{key}.jpg', quality=88)
    print('screen_' + key, sheet.size)
