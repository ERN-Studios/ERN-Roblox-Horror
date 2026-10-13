"""Upload the two sounds of Level 6's dark rounds to the group as Audio and keep their ids.

    python3 tools/level6_playground/upload_lights_out.py            # upload what has no id yet
    python3 tools/level6_playground/upload_lights_out.py status     # moderation state
    python3 tools/level6_playground/upload_lights_out.py install    # print the Luau that puts them in Studio

Owner, 2026-10-13: "Make sure a round randomly can be in dark mode with the lights turned off. Use elevenlabs to
make the turn off sound and have the entity say 'Lights out for this round'". Both were made with ElevenLabs (by
Codex, flow "stayquiet l6 lights out 20261013"; prompts and takes in assets/level6-lights-out-20261013/notes*.md):
`l6_lights_out` is the breaker and the power dying, `l6_lights_out_line` the Counter's own voice ("Demonic child
for level 6"). Same route as tools/lobby_reach/upload_sounds.py: the request goes out from the owner's signed-in
Creator Dashboard tab, no mouse and no keyboard. The game reads them as Sounds of those names in
ReplicatedStorage.Level6Counter.Voice (attribute `Seconds`); without them a dark round is only silent.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'lobby_reach'))
import upload_sounds as up  # noqa: E402

SOUNDS = ROOT / 'assets' / 'level6-lights-out-20261013' / 'final'
IDS = HERE / 'lights_out_ids.json'
# name -> (file, Volume, RollOffMinDistance, RollOffMaxDistance): the line like the Counter's other lines
KEYS = {'l6_lights_out': ('l6_lights_out.mp3', 1, 10, 10000), 'l6_lights_out_line': ('l6_lights_out_line.mp3', 1, 18, 220)}


def seconds(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                         capture_output=True, text=True).stdout.strip()
    return round(float(out), 2)


def main():
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    hashes = ids.setdefault('_sha256', {})
    if sys.argv[1:] == ['status']:
        for key in KEYS:
            print(f'{key:20s} {ids.get(key)}  {up.moderation(ids[key]) if ids.get(key) else "not uploaded"}')
        return
    if sys.argv[1:] == ['install']:
        rows = ', '.join('{"%s", %d, %s, %d, %d, %d}' % (key, ids[key], seconds(SOUNDS / row[0]), row[1], row[2], row[3]) for key, row in KEYS.items())
        print('''local voice = game:GetService("ReplicatedStorage").Level6Counter.Voice
local made = {}
for _, row in ipairs({%s}) do
	local s = voice:FindFirstChild(row[1]) or Instance.new("Sound")
	s.Name, s.SoundId, s.Volume = row[1], "rbxassetid://" .. row[2], row[4]
	s.RollOffMode = row[5] > 10 and Enum.RollOffMode.InverseTapered or Enum.RollOffMode.Inverse
	s.RollOffMinDistance, s.RollOffMaxDistance = row[5], row[6]
	s:SetAttribute("Seconds", row[3])
	s.Parent = voice
	made[#made + 1] = row[1] .. " " .. s.SoundId .. " " .. row[3] .. " s"
end
return table.concat(made, " | ")''' % rows)
        return
    for key, row in KEYS.items():
        path = SOUNDS / row[0]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if ids.get(key) and hashes.get(key) == digest:
            print(f'{key:20s} already {ids[key]}')
            continue
        asset = up.upload(path, f'BSQ L6 {key[3:]}')
        ids[key], hashes[key] = asset, digest
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
        print(f'{key:20s} -> {asset}')


if __name__ == '__main__':
    main()
