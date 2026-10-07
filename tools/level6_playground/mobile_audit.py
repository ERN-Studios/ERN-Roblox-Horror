"""Lay the player's HUD out as on a phone in a running play session and report what collides.

    python3 tools/level6_playground/mobile_audit.py 844 390      # a still of this moment, measured
    python3 tools/level6_playground/mobile_audit.py off          # back to the ordinary view

See mobile_audit.luau for what it does and what the findings mean. A play session has to be running; take a
screen_capture afterwards to look at it (the phone's screen is the top-left part of the picture).
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from import_to_studio import Studio   # noqa: E402

args = sys.argv[1:]
off = args[:1] == ['off']
w, h = (0, 0) if off else (int(args[0]), int(args[1]))
code = (HERE / 'mobile_audit.luau').read_text().replace('__W__', str(w)).replace('__H__', str(h)).replace('__MODE__', 'off' if off else 'on')
studio = Studio()
print(studio.call('execute_luau', {'studio_id': studio.studio_id, 'datamodel_type': 'Client', 'code': code}))
