"""Build the runtime bank only after all cleaned recordings have Roblox IDs."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
plan = json.loads((ROOT / 'upload-plan.json').read_text())
assert len(plan) == 51
plan = [r for r in plan if r.get('selected')]
assert len(plan) == 32
assert all(str(r.get('assetId') or '').isdigit() and int(r['assetId']) > 0 for r in plan), 'Uploads are incomplete; do not install this bank.'
mix = {
    'Foam': {'Walk': (.25, 12, 110), 'Run': (.33, 14, 145), 'Idle': (.09, 8, 60),
             'Groan': (.40, 18, 220), 'Squeal': (.32, 18, 220), 'Hunt': (.30, 14, 170), 'Attack': (.45, 12, 110)},
    'Slide': {'Walk': (.35, 18, 170), 'Run': (.43, 22, 210), 'EnragedRun': (.50, 24, 240),
              'Idle': (.14, 12, 100), 'Alert': (.45, 24, 240), 'Attack': (.52, 20, 170)},
}
lines = ['-- Cleaned ElevenLabs recordings; provenance and WAV hashes are in the audio asset manifest.',
         'local Bank = {Enabled = true, Version = 1, Mix = {']
for entity, groups in mix.items():
    lines.append(f'\t{entity} = {{')
    for key, (volume, minimum, maximum) in groups.items():
        lines.append(f'\t\t{key} = {{Volume = {volume}, Min = {minimum}, Max = {maximum}}},')
    lines.append('\t},')
lines.append('},')
for entity, groups in mix.items():
    lines.append(f'{entity} = {{')
    for key in groups:
        records = [r for r in plan if r['entity'] == f'Pool {entity}' and r['key'] == key]
        assert records
        values = ', '.join(f'{{Id = "rbxassetid://{r["assetId"]}", Seconds = {r["seconds"]}}}' for r in records)
        lines.append(f'\t{key} = {{{values}}},')
    lines.append('},')
lines += ['}', 'local function freeze(value)', '\tfor _, child in pairs(value) do if type(child) == "table" then freeze(child) end end', '\ttable.freeze(value)', 'end', 'freeze(Bank)', 'return Bank', '']
(ROOT / 'Level 2 Entity Audio Bank.Module.lua').write_text('\n'.join(lines))
