"""Write the uploaded sound ids into the creature's client script (between the REACH_SOUND_IDS markers).

    python3 tools/lobby_reach/install_sounds.py     # then push the script: tools/mac_push_script.py --force "<path>"

Keys in sound_ids.json are `reach_<group>` for a loop and `reach_<group>_<n>` for the takes of a one-shot; a group
is one of wake, presence, creep, windup, slam, grab, drag, kill, retreat.
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCRIPT = ROOT / 'StarterPlayer' / 'StarterPlayerScripts' / 'Lobby Tunnel Reach Client.LocalScript.lua'
LOOPS, SHOTS = ('presence', 'creep', 'drag'), ('wake', 'windup', 'slam', 'grab', 'kill', 'retreat')

ids = {k: v for k, v in json.loads((HERE / 'sound_ids.json').read_text()).items() if not k.startswith('_')}
rows = []
for group in SHOTS:
    takes = [ids[k] for k in sorted(ids) if re.fullmatch(rf'reach_{group}_\d+', k)]
    rows.append(f'\t\t{group} = {{{", ".join(str(t) for t in takes)}}},')
for group in LOOPS:
    rows.append(f'\t\t{group} = {ids.get("reach_" + group, 0)},')
block = ('\t-- REACH_SOUND_IDS_BEGIN (written by tools/lobby_reach/install_sounds.py from sound_ids.json)\n'
         '\tlocal IDS = {\n' + '\n'.join(rows) + '\n\t}\n\t-- REACH_SOUND_IDS_END\n')
source = SCRIPT.read_text()
start = source.index('\t-- REACH_SOUND_IDS_BEGIN')
end = source.index('\t-- REACH_SOUND_IDS_END\n') + len('\t-- REACH_SOUND_IDS_END\n')
SCRIPT.write_text(source[:start] + block + source[end:])
print(block)
