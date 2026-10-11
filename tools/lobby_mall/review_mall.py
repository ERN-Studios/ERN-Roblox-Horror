"""Make local reference comparisons and validate the rendered deliverables.
Run with /usr/local/bin/python3; no Blender, network, or Studio dependency.
Comparison sheets are image layouts, not additional rendered views.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/lobby-mall-20261011/build'
REFS = ROOT / 'artifacts/lobby-mall-20261011/raw_v3'
NAMES = ['plan', 'arrival', 'shop_and_supplies', 'shop_level1', 'shop_level2',
         'shop_level3', 'shop_level4', 'shop_level5', 'shop_level6', 'queue_bay',
         'the_tape', 'in_the_dark', 'event_stage', 'stand_from_above',
         'dark_wing_lit_for_review','shop_skins','shop_advanced_equipment']


def main():
    review = OUT / 'comparisons'
    review.mkdir(exist_ok=True)
    records = []
    contact = Image.new('RGB', (1200, 1440), (24, 24, 23))
    draw = ImageDraw.Draw(contact)
    for i, name in enumerate(NAMES):
        file = OUT / 'renders' / f'R{i:02d}_{name}.png'
        with Image.open(file) as source:
            assert source.size == (960, 540), (file, source.size)
            assert source.mode == 'RGB', (file, source.mode)
            render = source.copy()
        records.append({'view': file.stem, 'size': [960, 540],
                        'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
        small = render.copy()
        small.thumbnail((394, 216))
        x, y = i % 3 * 400, i // 3 * 240
        contact.paste(small, (x, y + 21))
        draw.text((x + 4, y + 4), file.stem, fill=(236, 232, 211))
        if i != 0:
            reference = REFS / (f'W{i:02d}_{name}.png' if i <= 13 else ('W11_in_the_dark.png' if i == 14 else 'W02_shop_and_supplies.png'))
            with Image.open(reference) as source:
                ref = source.convert('RGB')
                ref.thumbnail((960, 540))
            pair = Image.new('RGB', (1920, 565), (24, 24, 23))
            pd = ImageDraw.Draw(pair)
            pair.paste(ref, ((960-ref.width)//2, 25+(540-ref.height)//2))
            pair.paste(render, (960, 25))
            pd.text((10, 8), reference.stem + ' | approved concept', fill=(236, 232, 211))
            pd.text((970, 8), file.stem + ' | measured native-Part build', fill=(236, 232, 211))
            pair.save(review / f'compare_{i:02d}.jpg', quality=92)
    with Image.open(ROOT/'artifacts/lobby-mall-20261011/plan_v3.png') as source:
        ref=source.convert('RGB').transpose(Image.Transpose.ROTATE_270)
        ref.thumbnail((960,540))
    pair=Image.new('RGB',(1920,565),(24,24,23));pd=ImageDraw.Draw(pair)
    pair.paste(ref,((960-ref.width)//2,25+(540-ref.height)//2))
    with Image.open(OUT/'renders/R00_plan.png') as plan:pair.paste(plan,(960,25))
    pd.text((10,8),'plan_v3 | rotated so north points right',fill=(236,232,211))
    pd.text((970,8),'R00 | full measured lobby extends to z -421',fill=(236,232,211))
    pair.save(review/'compare_00.jpg',quality=92)
    assert len(list((OUT / 'renders').glob('R*.png'))) == 17
    contact.save(OUT / 'render_contact.jpg', quality=94)
    texture_files = sorted((OUT / 'textures').glob('*.png'))
    for file in texture_files:
        with Image.open(file) as im:
            assert im.size in ((512, 512), (1024, 1024)), (file, im.size)
    qa = json.loads((OUT / 'qa.json').read_text())
    parity = json.loads((OUT / 'blend_parity.json').read_text())
    assert qa['passed'] and parity['passed'] and parity['json_equal']
    assert qa['json_sha256'] == hashlib.sha256((OUT / 'mall.json').read_bytes()).hexdigest()
    result = {'passed': True, 'renders': records, 'textures': len(texture_files),
              'parts': qa['parts'], 'json_blend_parity': parity,
              'comparisons': [f'comparisons/compare_{i:02d}.jpg' for i in range(0, 17)]}
    (OUT / 'deliverable_qa.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'PASS: 17 RGB renders at 960x540; 17 paired comparisons; {len(texture_files)} textures; current JSON/Blender parity.')


if __name__ == '__main__':
    main()
