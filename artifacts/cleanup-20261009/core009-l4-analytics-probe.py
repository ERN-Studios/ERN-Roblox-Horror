"""Replay existing real-source analytics fixtures plus captured L1-L4 fields.

Only temporary fixture files and this task's result JSON are written. The
candidate is evaluated in memory; canonical source and Studio remain untouched.
"""
from pathlib import Path
import hashlib
import json
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
fixture = runpy.run_path(str(ROOT / 'tools/tests/test_zyntra_analytics.py'))
baseline = fixture['MODULE']
needle = 'L0 = true, L1 = true, L2 = true, L3 = true,'
assert baseline.count(needle) == 1
candidate = baseline.replace(needle, needle + ' L4 = true,')
probe = r'''
-- Capture the actual fake-service payload from each real level hook.
for level = 1, 4 do
    local h = host()
    local player = newPlayer()
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, false)
    Analytics.Ready(player, level)
    Analytics.RoundStart(player, level)
    local started = lastCustom(h.Service, "zq_round_start")
    check(started ~= nil, "each level emits a round start")
    equal(started.Fields.CF01, "L" .. level, "round start preserves Level " .. level .. " attribution")
    clock.t += 12
    player:SetAttribute("Escaped", true)
    Analytics.Outcome(player, level, nil)
    local outcome = lastCustom(h.Service, "zq_round_outcome")
    check(outcome ~= nil, "each level emits an outcome")
    equal(outcome.Fields.CF01, "L" .. level, "outcome preserves Level " .. level .. " attribution")
end
print(string.format("L1-L4 captured analytics: %d total checks passed", checks))
'''
luau = Path('C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe')
results = {}
with tempfile.TemporaryDirectory(prefix='mongotv-core009-') as temporary:
    for label, module in [('before', baseline), ('candidate', candidate)]:
        script = '\n'.join((fixture['PRELUDE'], fixture['CONFIG'], fixture['BRIDGE'], module,
                            fixture['HOST'], fixture['TESTS'], probe))
        path = Path(temporary) / (label + '.luau')
        path.write_text(script, encoding='utf-8')
        result = subprocess.run([str(luau), str(path)], capture_output=True, text=True, timeout=60)
        results[label] = {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
                          'sourceSHA256': hashlib.sha256(module.encode('utf-8')).hexdigest()}

assert results['before']['returncode'] != 0
assert 'round start preserves Level 4 attribution: expected L4, got other' in results['before']['stderr']
assert results['candidate']['returncode'] == 0
assert 'L1-L4 captured analytics: 127 total checks passed' in results['candidate']['stdout'], results['candidate']['stdout']
results['scope'] = 'Fake AnalyticsService, actual production module and catalogue; no network, DataStore or Studio mutation'
results['candidateChange'] = 'Only ALLOWED.L4=true; no new Level5/6 event semantics'
(ROOT / 'artifacts/cleanup-20261009/core009-l4-analytics-probe.json').write_text(
    json.dumps(results, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({label: {'returncode': results[label]['returncode'], 'stdout': results[label]['stdout']}
                  for label in ['before', 'candidate']}))
