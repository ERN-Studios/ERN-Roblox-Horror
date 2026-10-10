"""Run one of this folder's .lua files in the running Studio play session, with __KEY__ placeholders filled in."""
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent


def run(kind, name, **rep):
    src = (HERE / f'{name}.lua').read_text()
    for k, v in rep.items():
        src = src.replace(f'__{k}__', str(v))
    filled = HERE / f'_{name}.lua'
    filled.write_text(src)
    r = subprocess.run(['python3', 'tools/mobile_qa/qa.py', 'run', kind, str(filled)], cwd=ROOT, capture_output=True, text=True)
    filled.unlink()
    return (r.stdout.strip().splitlines() or [r.stderr.strip()[-300:]])[-1]


if __name__ == '__main__':
    print(run(sys.argv[1], sys.argv[2], **dict(a.split('=', 1) for a in sys.argv[3:])))
