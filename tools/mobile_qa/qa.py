"""Phone and tablet QA of a running Studio play session, from the session.

    python3 tools/mobile_qa/qa.py play                      # start play and mute it in the same breath
    python3 tools/mobile_qa/qa.py stop
    python3 tools/mobile_qa/qa.py run Client|Server file.lua
    python3 tools/mobile_qa/qa.py audit <state> [WxH ...] [--shot] [--as <ScreenGui name>]   # per device: lay out, measure, save
    python3 tools/mobile_qa/qa.py shot <name>               # the viewport as it is, to the artifacts folder
    python3 tools/mobile_qa/qa.py off                       # back to the ordinary view

`audit` runs tools/level6_playground/mobile_audit.luau once per device (default: the DEVICES below, which are
UIRegression's own matrix plus the classic iPad), writes each report to artifacts/mobile-qa-<day>/<state>__<WxH>.txt
and prints only what is NOT in KNOWN (findings that were looked at and are not faults). With --shot it also saves a
picture per device; a device larger than Studio's viewport is scaled down for the picture AFTER it was measured.
"""
import base64
import datetime
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io   # noqa: E402

OUT = ROOT / 'artifacts' / f'mobile-qa-{datetime.date.today():%Y%m%d}'
AUDIT = (ROOT / 'tools' / 'level6_playground' / 'mobile_audit.luau').read_text()
DEVICES = ['568x320', '667x375', '705x338', '844x390', '956x440', '390x844', '1024x768', '1180x820', '820x1180']
KNOWN_FILE = HERE / 'known.txt'

MUTE = '''
local n = 0
local function mute(s)
	if s:IsA("Sound") or s:IsA("SoundGroup") then
		pcall(function() s.Volume = 0 end)
		s:GetPropertyChangedSignal("Volume"):Connect(function() if s.Volume ~= 0 then s.Volume = 0 end end)
		n += 1
	end
end
for _, root in ipairs({workspace, game:GetService("SoundService"), game:GetService("ReplicatedStorage"), game:GetService("Players").LocalPlayer}) do
	for _, d in ipairs(root:GetDescendants()) do mute(d) end
	root.DescendantAdded:Connect(mute)
end
return "muted " .. n
'''

LOOK = '''
local emu
for _, g in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if g:GetAttribute("PhoneEmuRoot") then emu = g end
end
if not emu then return "no phone view" end
local view = workspace.CurrentCamera.ViewportSize
local s = math.min(1, view.X / %d, view.Y / %d)
local scale = emu:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", emu)
scale.Scale = s
return string.format("%%.3f", s)
'''


def known():
    if not KNOWN_FILE.exists():
        return []
    return [re.compile(line.strip()) for line in KNOWN_FILE.read_text().splitlines() if line.strip() and not line.startswith('#')]


class Session:
    def __init__(self):
        self.s = studio_io.Studio()

    def tool(self, name, **args):
        return self.s.request('tools/call', {'name': name, 'arguments': dict(args, studio_id=self.s.studio_id)})

    def luau(self, kind, code):
        res = self.tool('execute_luau', datamodel_type=kind, code=code)
        text = '\n'.join(c.get('text', '') for c in res.get('content', []) if c.get('type') == 'text')
        return ('ERROR ' if res.get('isError') else '') + text

    def shot(self, name):
        res = self.tool('screen_capture', capture_id=re.sub(r'\W', '_', name))
        OUT.mkdir(parents=True, exist_ok=True)
        for c in res.get('content', []):
            if c.get('type') == 'image':
                kind = 'jpg' if 'jp' in c.get('mimeType', 'jpeg') else 'png'
                path = OUT / f'{name}.{kind}'
                path.write_bytes(base64.b64decode(c['data']))
                return path
        return None


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    what, session = args[0], Session()
    if what == 'play':
        print(session.tool('start_stop_play', is_start=True).get('content', [{}])[0].get('text'))
        for _ in range(40):
            answer = session.luau('Client', MUTE)
            if answer.startswith('muted'):
                print(answer)
                return
            time.sleep(0.5)
        raise SystemExit('never got a Client to mute: ' + answer)
    if what == 'stop':
        print(session.tool('start_stop_play', is_start=False).get('content', [{}])[0].get('text'))
    elif what == 'run':
        print(session.luau(args[1], Path(args[2]).read_text()))
    elif what == 'shot':
        print(session.shot(args[1]))
    elif what == 'off':
        print(session.luau('Client', AUDIT.replace('__W__', '0').replace('__H__', '0').replace('__MODE__', 'off').replace('__EMU__', 'PhoneEmu')))
    elif what == 'audit':
        state = args[1]
        shot = '--shot' in args
        emu = 'PhoneEmu'
        if '--as' in args:                                   # borrow the name of a ScreenGui a takeover leaves alone
            emu = args.pop(args.index('--as') + 1)
            args.remove('--as')
        sizes = [a for a in args[2:] if not a.startswith('--')] or DEVICES
        skip = known()
        OUT.mkdir(parents=True, exist_ok=True)
        for size in sizes:
            w, h = (int(n) for n in size.split('x'))
            report = session.luau('Client', AUDIT.replace('__W__', str(w)).replace('__H__', str(h)).replace('__MODE__', 'on').replace('__EMU__', emu))
            (OUT / f'{state}__{size}.txt').write_text(report + '\n')
            lines = report.splitlines()
            fresh = [line for line in lines[1:] if not any(k.search(line) for k in skip)]
            print(f'== {state} {size}: {len(lines) - 1} findings, {len(fresh)} not known' + (f'  [{lines[0][:60]}]' if lines and lines[0].startswith('ERROR') else ''))
            for line in fresh:
                print('   ' + line[:230])
            if shot:
                session.luau('Client', LOOK % (w, h))
                time.sleep(0.4)
                print('   picture:', session.shot(f'{state}__{size}'))
        print(session.luau('Client', AUDIT.replace('__W__', '0').replace('__H__', '0').replace('__MODE__', 'off').replace('__EMU__', 'PhoneEmu')))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
