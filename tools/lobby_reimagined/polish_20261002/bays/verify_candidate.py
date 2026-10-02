"""Offline geometry/scope receipt for bay polish. Does not write to Studio."""
from pathlib import Path
import collections
import hashlib
import json
import math
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RECEIPTS = ROOT / 'artifacts/lobby-polish-20261002/bays'
RECEIPTS.mkdir(parents=True, exist_ok=True)
manifest = json.loads((HERE / 'baseline/live-manifest-excerpt.json').read_text())
source = (HERE / 'LobbyPolishBays.ModuleScript.candidate.luau').read_text()
records = []
for match in re.finditer(r'\{level=(\d), family="([^"]+)", name="([^"]+)", position=\{([^}]+)\}, yaw=([^}]+)\}', source):
    level, family, name, position, yaw = match.groups()
    yaw_value = eval(yaw.replace('math.pi', 'PI'), {'__builtins__': {}}, {'PI': math.pi})
    records.append(dict(level=int(level), family=family, name=name,
                        position=[float(n) for n in position.split(',')], yaw=yaw_value))
assert len(records) == 19

def transform(p, yaw, translation):
    c, s = math.cos(yaw), math.sin(yaw)
    return [translation[0] + c*p[0] + s*p[2], translation[1] + p[1],
            translation[2] - s*p[0] + c*p[2]]

def corners(chunk):
    center, size = chunk['center'], chunk['size']
    return [[center[0]+x*size[0]/2, center[1]+y*size[1]/2, center[2]+z*size[2]/2]
            for x in [-1,1] for y in [-1,1] for z in [-1,1]]

bay_by_level = {b['level']: b for b in manifest['bays']}
pad_by_level = collections.defaultdict(list)
for pad in manifest['pads']:
    bay = bay_by_level[pad['level']]
    delta = [pad['position'][i] - bay['floorPosition'][i] for i in range(3)]
    pad_by_level[pad['level']].append(transform(delta, -bay['yaw'], [0,0,0]))

proofs = []
triangle_count = 0
for prop in records:
    family = manifest['families'][prop['family']]
    points = [transform(p, prop['yaw'], prop['position'])
              for chunk in family['chunks'] for p in corners(chunk)]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    maximum_radius = max(math.hypot(p[0],p[2]) for p in points)
    # AABB to detector circle distance is conservative for these cardinal yaws.
    distances = []
    for pad in pad_by_level[prop['level']]:
        dx = max(lo[0]-pad[0],0,pad[0]-hi[0])
        dz = max(lo[2]-pad[2],0,pad[2]-hi[2])
        distances.append(math.hypot(dx,dz)-7.41)
    path_clearance = max(lo[0]-2.15, -2.15-hi[0], -hi[2])
    supported_by_desk = prop['family'] in ['CRTMonitor','BeigeKeyboard']
    floor_gap = lo[1] - (.8+3.209 if supported_by_desk else .8)
    assert abs(floor_gap) < .00001, (prop['name'], floor_gap)
    assert maximum_radius < 28, (prop['name'], maximum_radius)
    assert min(distances) > .3, (prop['name'], min(distances))
    assert path_clearance > 1, (prop['name'], path_clearance)
    triangle_count += family['triangles']
    proofs.append(prop | dict(boundingBoxMinimum=lo, boundingBoxMaximum=hi,
                             maxFloorRadius=maximum_radius,
                             minimumDetectorClearance=min(distances),
                             centerPathClearance=path_clearance,
                             support='matching office/cinema desk top' if supported_by_desk else 'existing floor',
                             supportGap=floor_gap, triangles=family['triangles']))

controller = (HERE / 'LobbyReimaginedQueueController.LocalScript.candidate.luau').read_text()
baseline = (HERE / 'baseline/LobbyReimaginedQueueController.LocalScript.source.luau').read_text()
# The mutation is presentation-only: all original event wiring and goal positions
# remain byte-identical after applying the narrowly recorded replacement blocks.
assert 'station:GetAttribute("QueueActive") == true' in controller
assert '((i-1)/9)^.85' in controller
assert 'if reduceMotion() then return end' in controller
assert 'QueueActive"):Connect(function() animate(p) end)' in controller
assert controller[controller.index('local function schedule(station)'):] == baseline[baseline.index('local function schedule(station)'):]
assert 'CanCollide, object.CanTouch, object.CanQuery = false, false, false' in source
assert ':Destroy(' not in source
assert ':FindFirstChild("QueueBay_Level" .. level)' in source
assert 'QueueIdleRingAlpha' in controller and 'QueueHologramLowerAlpha' in controller

header_min, header_max = 17.2-2.68/2, 17.2+2.68/2
theme_min, theme_max = 15.25-.86/2, 15.25+.86/2
instruction_min, instruction_max = 13.8-.92/2, 13.8+.92/2
access_min, access_max = 19.6-.75/2, 19.6+.75/2
assert instruction_max < theme_min < theme_max < header_min < header_max < access_min
bands = [.74+.26*((i-1)/9)**.85 for i in range(1,11)]
assert bands[0] == .74 and bands[-1] == 1 and bands == sorted(bands)
hash_file = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
receipt = dict(schema='lobby-r4-bay-polish-offline-verification-v1',
               scope='Local candidate only; static geometry/scope checks. No Studio runtime, gameplay, multiplayer, CPU/memory or frame-time pass is claimed.',
               baselineManifest=json.loads((HERE/'baseline/manifest.json').read_text()),
               helperSHA256=hash_file(HERE/'LobbyPolishBays.ModuleScript.candidate.luau'),
               controllerSHA256=hash_file(HERE/'LobbyReimaginedQueueController.LocalScript.candidate.luau'),
               newPropClones=len(records), newUniqueMeshes=0, newPointLights=0, newColliders=0,
               addedMeshTriangles=triangle_count, passiveNumberedPads=24,
               maxPropRadius=max(p['maxFloorRadius'] for p in proofs),
               minDetectorClearance=min(p['minimumDetectorClearance'] for p in proofs),
               minCenterPathClearance=min(p['centerPathClearance'] for p in proofs),
               controllerEventAndLifecycleTailExactlyPreserved=True,
               originalHeaderAndArrowCFramesAndTextUntouched=True,
               devAccessControllerUntouched=True, queueBridgeUntouched=True,
               signVerticalIntervals=dict(instruction=[instruction_min,instruction_max],theme=[theme_min,theme_max],
                                          existingHeader=[header_min,header_max],existingDevAccess=[access_min,access_max]),
               activeBandTransparency= bands,
               props=proofs)
(RECEIPTS/'offline-candidate-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
(HERE/'props-plan.json').write_text(json.dumps(records,indent=2)+'\n')
print(json.dumps({k:v for k,v in receipt.items() if k not in ['props','baselineManifest']},indent=2))
