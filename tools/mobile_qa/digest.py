"""Digest of the audit reports of one state: python3 tools/mobile_qa/digest.py <state>

THUMB findings are folded to one line per control and zone; everything else is printed once with the devices it
was found on."""
import re
import sys
import datetime
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / f'mobile-qa-{datetime.date.today():%Y%m%d}'
state = sys.argv[1]
found = defaultdict(list)
for path in sorted(OUT.glob(f'{state}__*.txt')):
    size = path.stem.split('__')[1]
    for line in path.read_text().splitlines()[1:]:
        kind = line[:7].strip()
        body = line[8:]
        if kind == 'THUMB':
            m = re.match(r"(\S+?)(?: '.*?'| > \S+)? \(.*\) is .* inside the (\w+) zone", body)
            key = f'THUMB   {m.group(1)} in the {m.group(2)} zone' if m else line
        else:
            key = kind.ljust(8) + re.sub(r'\(-?\d+,-?\d+\)-\(-?\d+,-?\d+\)', '', body)
            key = re.sub(r'\s+\(\d+x\d+ px\)', '', key)
        if size not in found[key]:
            found[key].append(size)
for key in sorted(found):
    print(f'{key[:170]:170s}  {" ".join(found[key])}')
