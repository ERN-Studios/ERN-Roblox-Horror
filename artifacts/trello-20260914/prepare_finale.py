"""Prepare card 75 without editing the shared Studio mirror while Claude owns the bridge."""
from pathlib import Path
import hashlib
import json
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
changes = []
def prepare(name, edits):
    rel = Path('ServerScriptService/Level 3 Systems') / name
    before = (ROOT / rel).read_text(encoding='utf-8')
    after = before
    for old, new in edits:
        assert after.count(old) == 1, old
        after = after.replace(old,new)
    for folder, text in [('finale-before',before),('finale-proposed',after)]:
        path = HERE / folder / rel
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(text,encoding='utf-8')
    changes.append({'path':rel.as_posix(),'beforeCanonicalSha256':hashlib.sha256(before.encode()).hexdigest(),
                    'proposedCanonicalSha256':hashlib.sha256(after.encode()).hexdigest()})

prepare('Level 3 Objective Controller.ModuleScript.lua', [
 ('\t\t\t\t\tlocal halfway = hall.Length * (hall.HalfwayProgress or .50)',
  '\t\t\t\t\t-- Start the finale as the first survivor commits to the open exit hall.\n\t\t\t\t\tlocal entryProgress = 4'),
 ('if along >= halfway and insideHallWidth and insideHallHeight then',
  'if along >= entryProgress and along <= hall.Length + 2.5\n\t\t\t\t\t\tand insideHallWidth and insideHallHeight then'),
 ('if eligibleCount == 0 or crossedCount ~= eligibleCount then return end',
  'if eligibleCount == 0 or crossedCount == 0 then return end'),
 ('\t-- authored final-hall reveal rather than the legacy hidden random-room spawn.',
  '\t-- level-entry finale spawn rather than a normal hidden random-room spawn.'),
])

helper = '''local function insideFinalHall(session: any, position: Vector3): boolean
 local hall = session.Manifest.FinalHall
 if type(hall) ~= "table" then return false end
 local forward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
 if forward.Magnitude <= .001 then return false end
 forward = forward.Unit
 local offset = Vector3.new(position.X - hall.StartPoint.X, 0, position.Z - hall.StartPoint.Z)
 local along = offset:Dot(forward)
 return along >= -2 and along <= hall.Length + 2
  and (offset - forward * along).Magnitude <= hall.Width * .5 + 2
  and math.abs(position.Y - hall.FloorY) <= hall.Height + 6
end

'''
prepare('Level 3 Mall Manager AI Controller.ModuleScript.lua', [
 ('-- A bounded repair for coarse navmesh points that hug an authored room wall.',
  helper + '-- A bounded repair for coarse navmesh points that hug an authored room wall.'),
 ('\tif session.FinalHallChase then return nil end',
  '\tif session.FinalHallChase and insideFinalHall(session, session.Root.Position) then return nil end'),
 ('\tif session.FinalHallChase then\n\t\t-- The finale is one straight, opened tunnel. Never route back through the\n\t\t-- Signal Hall room center before following the moving players.',
  '''\tif session.FinalHallChase and insideFinalHall(session, finalGoal)
\t\tand not insideFinalHall(session, session.Root.Position) then
\t\t-- From level entry, use the normal maze route to the open hall mouth.
\t\t-- A direct line to a distant runner would cut through the intervening rooms.
\t\tlocal hall = session.Manifest.FinalHall
\t\tfinalGoal = flat(hall.StartPoint + hall.Forward * 6, session.FloorY)
\t\tnavigationGoal = finalGoal
\tend
\tif session.FinalHallChase and insideFinalHall(session, session.Root.Position)
\t\tand insideFinalHall(session, finalGoal) then
\t\t-- Once both are in the straight opened tunnel, follow the runner directly.'''),
 ('\tif type(hall) ~= "table" or not hall.SpawnMarker or not hall.SpawnMarker.Parent then return nil end',
  '\tlocal entry = manifest.MazeStart\n\tif type(hall) ~= "table" or not entry or not entry.Parent then return nil end'),
 ('\tlocal position = Vector3.new(hall.SpawnMarker.Position.X, hall.FloorY, hall.SpawnMarker.Position.Z)\n\tif not spawnVolumeFits(position, spawnOverlapParams(records)) then\n\t\twarn("[Level 3 Mall Manager] authored final-hall spawn volume is blocked")\n\t\treturn nil\n\tend',
  '''\t-- The finale starts at the player's Level 3 entrance, never beside the exit.
\t-- Try a few clear points just inside the arrival room, avoiding the spawn pad.
\tlocal position: Vector3? = nil
\tlocal overlap = spawnOverlapParams(records)
\tfor _, distance in ipairs({8, 12, 16, 20}) do
\t\tlocal candidate = entry.Position + entry.CFrame.LookVector * distance
\t\tcandidate = Vector3.new(candidate.X, hall.FloorY, candidate.Z)
\t\tif spawnVolumeFits(candidate, overlap) then position = candidate; break end
\tend
\tif not position then
\t\twarn("[Level 3 Mall Manager] level-entry finale spawn volume is blocked")
\t\treturn nil
\tend'''),
])
(HERE/'finale-basis.json').write_text(json.dumps({'status':'prepared; Studio parity and physical chase test pending','files':changes},indent=2),encoding='utf-8')
print('Prepared #75: first survivor starts the exit run; entity spawns at level entry and navigates through the maze.')
