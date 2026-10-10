"""Write the Poolrooms audio plan v3: one ambient bed per section and a pool of one-shots that belong to each section.

    python3 tools/poolrooms_audio_20261010/make_plan.py            # writes assets/poolrooms-audio-20261010/plan.json
    python3 tools/poolrooms_audio_20261010/make_plan.py --all      # as if every sound existed (to read the design)

Owner, 2026-10-10: "Variation af ambient lyde i de forskellige sektioner er røv. Det er den samme rum hum som spilles i
alle større sektioner ... langt mere variation med flere random lyde der passer til hver sektion og hver deres ambient
lyd for hver sektion der passer til sektionen."

The plan keeps v2's sections, order, origin and route (assets/poolrooms-audio-20261009/plan.json) and replaces beds, loops
and shots. Schema: tools/poolrooms_audio_20261010/SCHEMA.md (the client's own account of every field).

A row is only written when its sound has BOTH a master that passed QC (assets/poolrooms-audio-20261010/qc.json) and an
uploaded asset id (sound_ids.json). A section whose own bed is missing keeps the old shared bed (bed_hall for the halls,
bed_service for the passages), so no section can come out without a bed; the tool prints every such fallback.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OLD = ROOT / 'assets' / 'poolrooms-audio-20261009'
NEW = ROOT / 'assets' / 'poolrooms-audio-20261010'

REVISION = 'poolrooms-audio-20261010-v3'
HALLS = ['A1', 'A3', 'A4', 'A2', 'A5', 'A6']

# key, sections, volume, fade (None = the client's 3 s in / 2 s out). Passages are walked in 5 to 15 s: their beds
# come up in 1.5 s or they would be a crossfade and nothing else.
BEDS = [
    ('bed_s_desert', ['S'], 0.42, [1.5, 1.5]),
    ('bed_p0_stairwell', ['P0'], 0.40, [1.5, 1.5]),
    ('bed_a1_cistern', ['A1'], 0.50, None),
    ('bed_p1_pipes', ['P1'], 0.42, [1.5, 1.5]),
    ('bed_a3_nave', ['A3'], 0.55, None),
    ('bed_p2_culvert', ['P2'], 0.40, [1.5, 1.5]),
    ('bed_a4_stepwell', ['A4'], 0.45, None),
    ('bed_p3_vent', ['P3'], 0.40, [1.5, 1.5]),
    ('bed_a2_rotunda', ['A2'], 0.50, [2, 2]),
    ('bed_p4_lockers', ['P4'], 0.40, [1.5, 1.5]),
    ('bed_a5_natatorium', ['A5'], 0.50, None),
    ('bed_p5_doors', ['P5'], 0.40, [1.5, 1.5]),
    ('bed_a6_atrium', ['A6'], 0.42, None),
    ('bed_exit_flume', ['EXIT'], 0.45, [1.5, 1.5]),
    # The lapping bed the owner had turned "right down to a very low level" on 2026-10-10: unchanged.
    ('bed_water', ['A1', 'A2', 'A5', 'P2'], 0.06, None),
]
FALLBACK_BED = {'hall': ('bed_hall', 0.5), 'passage': ('bed_service', 0.45)}

# 3D loops. The first four are v2's; the pump house gets its own sound instead of the passage hum it borrowed.
LOOPS = [
    {'key': 'loop_pumphouse', 'fallback': 'bed_service', 'name': 'Pump House Resonance', 'position': [-743.5, -55, 288],
     'sections': ['A1', 'P1'], 'volume': 0.6, 'min': 6, 'max': 80},
    {'key': 'loop_weir', 'name': 'A3 Weir', 'position': [-38, -127, 272], 'sections': ['A3', 'P2'], 'volume': 0.7, 'min': 8, 'max': 85},
    {'key': 'loop_weir', 'name': 'P2 Cascade', 'position': [9.15, -124.82, 164.085], 'sections': ['A3', 'P2', 'A4'],
     'volume': 0.75, 'min': 8, 'max': 75, 'replaces': 'Cascade Water'},
    {'key': 'loop_lion', 'name': 'Lion Spouts', 'position': [-308, 9, 51], 'sections': ['A2', 'P3', 'P4'], 'volume': 0.75, 'min': 10, 'max': 95},
    {'key': 'loop_impellers', 'name': 'A3 Impellers', 'position': [36, -138, 288], 'sections': ['A3', 'P2'], 'volume': 0.65, 'min': 10, 'max': 95},
    {'key': 'loop_gutter', 'name': 'A5 Overflow Gutter', 'position': [-244, -1, -390], 'sections': ['A5'], 'volume': 0.5, 'min': 6, 'max': 70},
]

PITS = [[-434.3, -150, 271.7], [-391.8, -150, 237.4], [-288.9, -150, 340.3], [-220.2, -150, 203.1], [-185.9, -150, 306.0]]

# One-shots: key, sections, volume, dist, extra. Every row has a 40 s cooldown unless it says otherwise.
SHOTS = [
    ('shot_a1_drips', ['A1'], 0.60, [16, 44], {}),
    ('shot_a1_plink', ['A1'], 0.55, [18, 48], {}),
    ('shot_a1_pump_clank', ['A1'], 0.55, [20, 120], {'position': [-743.5, -55, 288], 'max': 160}),
    ('shot_a1_stir', ['A1'], 0.40, [28, 60], {'cooldown': 70}),
    ('shot_a1_tile', ['A1'], 0.55, [14, 40], {}),
    ('shot_a1_moan', ['A1'], 0.50, [30, 70], {'cooldown': 80}),

    ('shot_a3_pit_stone', ['A3'], 0.60, [8, 90], {'positions': PITS}),
    ('shot_a3_boom', ['A3'], 0.60, [40, 90], {'cooldown': 80, 'max': 160}),
    ('shot_a3_pit_breath', ['A3'], 0.50, [8, 80], {'positions': PITS, 'cooldown': 70}),
    ('shot_a3_lamp_buzz', ['A3'], 0.50, [20, 50], {}),
    ('shot_a3_chain', ['A3'], 0.55, [30, 70], {}),
    ('shot_a3_surge', ['A3'], 0.55, [30, 80], {'cooldown': 70}),
    ('shot_a3_grit', ['A3'], 0.55, [14, 40], {}),

    ('shot_a4_glass', ['A4'], 0.50, [14, 40], {}),
    ('shot_a4_drop', ['A4'], 0.60, [6, 140], {'position': [0, -114, 0], 'max': 170}),
    ('shot_a4_rail', ['A4'], 0.50, [14, 40], {}),
    ('shot_a4_tile_steps', ['A4'], 0.55, [14, 40], {}),
    ('shot_a4_valve', ['A4'], 0.50, [12, 30], {}),
    ('shot_a4_steps_above', ['A4'], 0.45, [26, 50], {'cooldown': 120}),

    ('shot_a2_disc', ['A2'], 0.50, [6, 130], {'position': [-257.4, -11.3, -0.2], 'cooldown': 90, 'max': 160}),
    ('shot_a2_flutter', ['A2'], 0.55, [16, 50], {}),
    ('shot_a2_whoosh', ['A2'], 0.45, [20, 50], {'cooldown': 70}),
    ('shot_a2_brass', ['A2'], 0.50, [14, 40], {}),
    ('shot_a2_gulp', ['A2'], 0.55, [10, 130], {'position': [-308, 9, 51], 'max': 160}),

    ('shot_a5_roof', ['A5'], 0.55, [30, 70], {'cooldown': 60}),
    ('shot_a5_truss', ['A5'], 0.50, [26, 60], {}),
    ('shot_a5_seat', ['A5'], 0.55, [24, 60], {}),
    ('shot_a5_ladder', ['A5'], 0.50, [16, 44], {}),
    ('shot_a5_glug', ['A5'], 0.55, [10, 120], {'position': [-244, -1, -390], 'max': 150}),
    ('shot_a5_rope', ['A5'], 0.45, [16, 44], {}),

    ('shot_a6_latch', ['A6'], 0.50, [26, 60], {}),
    ('shot_a6_creak', ['A6'], 0.50, [24, 55], {'cooldown': 70}),
    ('shot_a6_knock', ['A6'], 0.45, [26, 55], {'cooldown': 120}),
    ('shot_a6_stair', ['A6'], 0.50, [20, 60], {}),
    ('shot_a6_drain', ['A6'], 0.50, [16, 50], {}),
    ('shot_a6_bulb', ['A6'], 0.45, [10, 26], {}),

    ('shot_p_locker', ['P0', 'P4'], 0.50, [10, 26], {}),
    ('shot_p_hangers', ['P0', 'P4'], 0.45, [8, 22], {}),
    ('shot_p_pipe_knock', ['P1', 'P3'], 0.55, [12, 34], {}),
    ('shot_p_grating', ['P1'], 0.50, [12, 30], {}),
    ('shot_p_drain', ['P3', 'P2'], 0.50, [8, 24], {}),
    ('shot_p5_handle', ['P5'], 0.45, [8, 22], {'cooldown': 90}),
    ('shot_p5_buzz', ['P5'], 0.45, [8, 22], {}),
    ('shot_s_gust', ['S'], 0.50, [10, 26], {}),
    ('shot_s_shutter', ['S'], 0.45, [8, 20], {}),

    # v2's four, kept as a thin shared layer (they were weighted 3 and 2 when they were all there was)
    ('shot_drip', ['A1', 'A2', 'A4', 'A5', 'P2', 'P3', 'P4'], 0.60, [16, 42], {'cooldown': 70}),
    ('shot_pipe', ['P0', 'P1', 'A3', 'P3', 'P4', 'P5', 'A6'], 0.55, [20, 48], {'cooldown': 70}),
    ('shot_splash', ['A1', 'A2', 'A5'], 0.30, [24, 55], {'cooldown': 90}),
    ('shot_creak', ['A1', 'A3', 'A4', 'A2', 'A5', 'A6', 'P5'], 0.55, [24, 48], {'cooldown': 70}),
]

# Seconds between one-shots while in a section, and how soon a section speaks after it is entered. v2 had one timer
# for the whole level: 18 to 45 s, so a hall walked in 23 s said one thing or nothing.
TIMING = {
    'hall': {'gap': [8, 18], 'first': [3, 7]},
    'A6': {'gap': [10, 22], 'first': [4, 8]},
    'passage': {'gap': [9, 18], 'first': [2, 5]},
    'S': {'gap': [10, 20], 'first': [3, 6]},
}


def main():
    everything = '--all' in sys.argv
    old = json.loads((OLD / 'plan.json').read_text())
    ids = json.loads((NEW / 'sound_ids.json').read_text()) if (NEW / 'sound_ids.json').exists() else {}
    qc = json.loads((NEW / 'qc.json').read_text()).get('sounds', {}) if (NEW / 'qc.json').exists() else {}
    legacy = set(json.loads((OLD / 'sound_ids.json').read_text()))

    def have(key):
        if everything or key in legacy:
            return True
        return (bool(ids.get(key, {}).get('asset_id')) and ids[key].get('moderation') == 'Approved'
                and qc.get(key, {}).get('numeric_pass') is True)

    dropped, notes = [], []
    plan = {'revision': REVISION, 'origin': old['origin'], 'order': old['order'], 'limits': {'recent': 3},
            'sections': {}, 'route': old['route'], 'beds': [], 'loops': [], 'shots': []}
    for name in old['order']:
        section = dict(old['sections'][name])
        if name != 'EXIT':
            kind = name if name in TIMING else ('hall' if name in HALLS else 'passage')
            section.update(TIMING[kind])
        plan['sections'][name] = section

    bedded = set()
    for key, sections, volume, fade in BEDS:
        if not have(key):
            dropped.append(key)
            continue
        row = {'key': key, 'sections': sections, 'volume': volume}
        if fade:
            row['fade'] = fade
        plan['beds'].append(row)
        if key != 'bed_water':
            bedded.update(sections)
    for name in old['order']:
        if name not in bedded:
            key, volume = FALLBACK_BED['hall' if name in HALLS else 'passage']
            plan['beds'].append({'key': key, 'sections': [name], 'volume': volume})
            notes.append(f'{name}: no bed of its own, keeps {key}')

    for loop in LOOPS:
        row = {k: v for k, v in loop.items() if k != 'fallback'}
        if not have(row['key']):
            if 'fallback' in loop:
                notes.append(f'{row["name"]}: {row["key"]} missing, keeps {loop["fallback"]}')
                row['key'], row['max'] = loop['fallback'], 65
            else:
                dropped.append(row['key'])
                continue
        plan['loops'].append(row)

    for key, sections, volume, dist, extra in SHOTS:
        if not have(key):
            dropped.append(key)
            continue
        row = {'key': key, 'sections': sections, 'volume': volume, 'dist': dist, 'cooldown': 40}
        row.update(extra)
        plan['shots'].append(row)

    keys = {r['key'] for group in ('beds', 'loops', 'shots') for r in plan[group]}
    pools = {name: sum(1 for r in plan['shots'] if name in r['sections']) for name in old['order']}
    NEW.mkdir(parents=True, exist_ok=True)
    out = NEW / ('plan.design.json' if everything else 'plan.json')
    out.write_text(json.dumps(plan, indent=1) + '\n')
    text = json.dumps(plan, separators=(',', ':'))
    print(f'{out.relative_to(ROOT)}: {len(plan["beds"])} beds, {len(plan["loops"])} loops, {len(plan["shots"])} shots, '
          f'{len(keys)} keys, {len(text)} characters minified')
    print('one-shots per section: ' + ', '.join(f'{k} {v}' for k, v in pools.items()))
    for note in notes:
        print('FALLBACK', note)
    if dropped:
        print('LEFT OUT (no passed master or no asset id): ' + ', '.join(sorted(set(dropped))))


if __name__ == '__main__':
    main()
