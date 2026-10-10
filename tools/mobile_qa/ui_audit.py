"""One screen state, measured and photographed at full resolution in tiles.
    python3 ui_audit.py <state> <WxH> <touch|desktop> [--tiles]
The Studio viewport is a strip, so the device frame is slid under it tile by tile and the tiles are stitched afterwards."""
import sys, time, json
from pathlib import Path
WT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(WT / 'tools' / 'mobile_qa'))
argv = sys.argv[:]
sys.argv = ['qa.py']
import qa
state, size, mode = argv[1], argv[2], argv[3]
tiles = '--tiles' in argv
w, h = (int(n) for n in size.split('x'))
s = qa.Session()
audit = qa.AUDIT.replace('__W__', str(w)).replace('__H__', str(h)).replace('__MODE__', 'on').replace('__EMU__', 'PhoneEmu')
if mode == 'desktop':
    assert audit.count('workspace:SetAttribute("ForceTouchUI", true)') == 1
    audit = audit.replace('workspace:SetAttribute("ForceTouchUI", true)', 'workspace:SetAttribute("ForceTouchUI", nil)')
import datetime
out = WT / 'artifacts' / f'ui-review-{datetime.date.today():%Y%m%d}'
out.mkdir(parents=True, exist_ok=True)
report = s.luau('Client', audit)
(out / f'{state}__{size}__{mode}.txt').write_text(report + '\n')
lines = report.splitlines()
print(f'== {state} {size} {mode}: {len(lines) - 1} findings')
for line in lines[:1] + lines[1:60]:
    print('   ' + line[:240])
if tiles:
    vp = s.luau('Client', 'local v = workspace.CurrentCamera.ViewportSize return v.X .. " " .. v.Y')
    vw, vh = (int(float(n)) for n in vp.split())
    cols, rows = -(-w // vw), -(-h // vh)
    meta = dict(w=w, h=h, vw=vw, vh=vh, cols=cols, rows=rows)
    for r in range(rows):
        for c in range(cols):
            s.luau('Client', '''for _, g in ipairs(game.Players.LocalPlayer.PlayerGui:GetChildren()) do
                if g:GetAttribute("PhoneEmuRoot") then g.Device.Position = UDim2.fromOffset(%d, %d) end end return "ok"''' % (-c * vw, -r * vh))
            time.sleep(0.25)
            path = s.shot(f'tile_{state}_{size}_{mode}_{r}_{c}')
            if path: Path(path).rename(out / f'tile_{state}_{size}_{mode}_{r}_{c}.jpg')
    (out / f'tiles_{state}_{size}_{mode}.json').write_text(json.dumps(meta))
    print('   tiles', cols, 'x', rows)
print(s.luau('Client', qa.AUDIT.replace('__W__', '0').replace('__H__', '0').replace('__MODE__', 'off').replace('__EMU__', 'PhoneEmu')))
