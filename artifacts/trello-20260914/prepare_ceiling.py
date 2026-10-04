"""Prepare #67 against the captured repo source without touching Studio-owned files."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
REL = Path('StarterPlayer/StarterPlayerScripts/LobbyCeilingSweeps.LocalScript.lua')
source = (ROOT / REL).read_text(encoding='utf-8')
original = source
def replace(old, new):
    global source
    assert source.count(old) == 1, old
    source = source.replace(old, new)

replace('-- Occasional, local cyan sweeps across the lobby\'s two ceiling-light rows.',
        '-- Five occasional on/off patterns across the lobby\'s two ceiling-light rows.')
replace('local HIGHLIGHT = Color3.fromRGB(166, 255, 238)\n', '')
replace('  if item.light.Color == item.lastLightColor then item.light.Color = item.lightColor end\n  if item.light.Brightness == item.lastBrightness then item.light.Brightness = item.brightness end',
        '  if item.part.Material == item.lastMaterial then item.part.Material = item.material end\n  if item.light.Enabled == item.lastEnabled then item.light.Enabled = item.enabled end')
replace(' -- arriving before its flag must not be overwritten by a saved cyan value.',
        ' -- arriving before its flag must not be overwritten by a saved baseline.')
replace('     lightColor = light.Color, brightness = light.Brightness,',
        '     lightColor = light.Color, brightness = light.Brightness,\n     material = part.Material, enabled = light.Enabled,')
replace('local function pulse(coordinate, progress)\n -- Start and end outside the fixtures, with a soft, zero-slope edge.\n local front = -0.24 + progress * 1.48\n local distance = math.abs(coordinate - front) / 0.22\n return distance < 1 and (1 + math.cos(math.pi * distance)) / 2 or 0\nend',
        'local function lightIsOn(coordinate, progress)\n -- One broad dark band travels across the fixtures. Each switches off once\n -- for about 1.8 seconds, then on; the band starts and finishes outside them.\n local front = -0.24 + progress * 1.48\n return math.abs(coordinate - front) >= 0.22\nend')
replace('    or item.light.Color ~= (item.lastLightColor or item.lightColor)\n    or item.light.Brightness ~= (item.lastBrightness or item.brightness)) then',
        '    or item.part.Material ~= (item.lastMaterial or item.material)\n    or item.light.Color ~= item.lightColor\n    or item.light.Brightness ~= item.brightness\n    or item.light.Enabled ~= (if item.lastEnabled == nil then item.enabled else item.lastEnabled)) then')
replace('   local strength = pulse(patternCoordinate(active.pattern, item), progress)\n   -- Never darken the road or create a strobe: a broad highlight travels once.\n   item.part.Color = item.partColor:Lerp(HIGHLIGHT, strength * 0.65)\n   item.light.Color = item.lightColor:Lerp(HIGHLIGHT, strength * 0.65)\n   item.light.Brightness = item.brightness * (1 + strength * 0.45)\n   -- Read back native property precision for reliable ownership on restoration.\n   item.lastPartColor = item.part.Color\n   item.lastLightColor = item.light.Color\n   item.lastBrightness = item.light.Brightness',
        '   local on = lightIsOn(patternCoordinate(active.pattern, item), progress)\n   item.light.Enabled = on\n   -- Remove the fixture\'s neon emission as well as its real illumination.\n   item.part.Material = if on then item.material else Enum.Material.SmoothPlastic\n   item.part.Color = if on then item.partColor else item.partColor * 0.14\n   -- Read back native property precision for reliable ownership on restoration.\n   item.lastPartColor = item.part.Color\n   item.lastMaterial = item.part.Material\n   item.lastEnabled = item.light.Enabled')

for folder, content in [('ceiling-before', original), ('ceiling-proposed', source)]:
    target = HERE / folder / REL
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')
(HERE / 'ceiling-basis.json').write_text(json.dumps({
    'path': REL.as_posix(),
    'beforeCanonicalSha256': hashlib.sha256(original.encode()).hexdigest(),
    'proposedCanonicalSha256': hashlib.sha256(source.encode()).hexdigest(),
    'status': 'prepared; requires live Studio parity before integration',
}, indent=2), encoding='utf-8')
print('Prepared #67: five on/off patterns; original and hashes preserved.')
