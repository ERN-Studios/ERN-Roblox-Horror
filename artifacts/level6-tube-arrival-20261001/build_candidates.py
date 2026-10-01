import json, pathlib, hashlib, difflib

ROOT = pathlib.Path(__file__).parent
baseline = {x['path']: x for x in json.loads((ROOT/'native-before/scripts.json').read_text())}
plans = []
def edit(path, changes):
    old = baseline[path]['source']
    new = old
    for before, after in changes:
        assert new.count(before) == 1, (path, before[:100], new.count(before))
        new = new.replace(before, after)
    klass = baseline[path].get('class', baseline[path].get('className'))
    if not klass: klass = 'LocalScript' if path.startswith('StarterPlayer.') else ('Script' if path.endswith('Level6PreviewAccess') else 'ModuleScript')
    filename = path + '.' + klass + '.luau'
    for folder, data in [('before-source', old), ('candidate-source', new)]:
        (ROOT/folder).mkdir(exist_ok=True)
        (ROOT/folder/filename).write_text(data)
    (ROOT/'candidate-source'/ (filename+'.diff')).write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile=path+' BEFORE',tofile=path+' AFTER')))
    plans.append({'path':path,'class':klass,'before':old,'after':new,'beforeSha256':hashlib.sha256(old.encode()).hexdigest(),'afterSha256':hashlib.sha256(new.encode()).hexdigest()})

ref = baseline['ServerScriptService.Level 3 Systems.Level 3 World Builder']['source']
start = ref.index('local function makeArrivalElevator(')
end = ref.index('\nlocal function ', start+20)
tube = ref[start:end]
tube = tube[:tube.index('\n\t-- Low-friction parts communicate')]
comment_start = tube.index('\t-- LEVEL2_EXIT_TRANSITION_20260828')
comment_end = tube.index('\tlocal tubeLength', comment_start)
tube = tube[:comment_start] + '\t-- Match the authored Level 3 flume and its tall orange landing room.\n\t-- Level 6 preview enters upright at the outlet; production progression\n\t-- and the Level 2/3 slide controller remain owned by their existing systems.\n' + tube[comment_end:]
resume_start = tube.index('\t-- The resume frame:')
resume_end = tube.index('\tlocal rearPoint',resume_start)
tube = tube[:resume_start] + tube[resume_end:]
tube = tube.replace('Level 2 Exit Slide Continuation','Level 6 Poolrooms Arrival Tube').replace('Level 2 Exit Slide','Level 6 Arrival Tube').replace('Level 3 West Wall','Level 6 West Wall').replace('Level3_','Level6_')
tube = tube.replace('\tvisual:SetAttribute("Level6_Level2ExitTube", true)','\tvisual:SetAttribute("Level6_ArrivalTube", true)')
tube = tube.replace('\n\tvisual:SetAttribute("Level6_SlideSlipback", true)','')
tube = tube.replace('Vector3.new(.42, 14.8, 14.8)', 'Vector3.new(.42, 17, 17)')
tube += '''
	-- Spawn at the last six studs of the actual first runout plane, not the
	-- curve's centerline. Preview Runtime lifts this floor-relative marker 3.5.
	local spawnX = mouthX - 6
	local firstAxis = (pathPoints[2] - pathPoints[1]).Unit
	local down = (-Vector3.yAxis - firstAxis * (-Vector3.yAxis):Dot(firstAxis)).Unit
	local firstCenter = (pathPoints[1] + pathPoints[2]) * .5
	local floorPoint = firstCenter + down * radius
	local floorNormal = -down
	local floorY = floorPoint.Y - floorNormal.X * (spawnX - floorPoint.X) / floorNormal.Y
	local spawnPosition = Vector3.new(spawnX, floorY + .25, p.Z)
	local spawnCF = CFrame.lookAt(spawnPosition, spawnPosition + Vector3.xAxis)
	visual:SetAttribute("Level6_ArrivalSpawnDistanceFromMouth", 6)
	local spawn = part(parent, "Level6ElevatorSpawn", spawnCF,
		Vector3.new(8, .5, 8), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(spawn)
	spawn:SetAttribute("Level6_CompatibilityMarker", true)
	local mazeStart = part(parent, "Level6MazeStart", spawnCF,
		Vector3.new(2, .3, 2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(mazeStart)
	mazeStart:SetAttribute("Level6_CompatibilityMarker", true)
	return visual, spawn, mazeStart
end
'''
wb = baseline['ServerScriptService.Level 6 Systems.Level 6 World Builder']['source']
st = wb.index('local function makeArrivalElevator(')
en = wb.index('\nlocal function ',st+20)
edit('ServerScriptService.Level 6 Systems.Level 6 World Builder', [
    ('if room.Id == "Arrival" then return 12 end','if room.Id == "Arrival" then return 30 end'),
    ('\t-- The story-only Level 2 flume mouth opens behind the Level 6 spawn.\n\t-- Level 6 arrival has a closed west wall and a dev return prompt.', '\t-- The Level 6 arrival tube enters through its own west aperture.\n\tmap.Arrival.West = true'),
    (wb[st:en], tube.rstrip('\n')),
])
edit('ServerScriptService.Level 6 Systems.Level 6 Layout Generator', [
    ('D = Tuning.ArrivalDepth,\n\t\tH = 12,','D = Tuning.ArrivalDepth,\n\t\tH = 30,'),
])
edit('ServerScriptService.Level 6 Systems.Level 6 Visual Adapter', [
    ('local function theme(room): string\n', 'local function theme(room): string\n    if room.Role == "Arrival" then return "Orange" end\n'),
    ('    -- Hide all old rendering, including surface content which Transparency alone does not hide.\n    for _, object in ipairs(legacy) do\n', '    -- Keep the owned arrival tube, aperture seals and notice visible; the\n    -- Blender kit still replaces every other legacy room/corridor visual.\n    local arrivalTube = manifest.Elevator\n    for _, object in ipairs(legacy) do\n        if arrivalTube and arrivalTube:GetAttribute("Level6_ArrivalTube") == true\n            and object:IsDescendantOf(arrivalTube) then continue end\n'),
])

edit('ServerScriptService.Level6PreviewAccess', [
    ('\t\t\terror("Preview join rejected: " .. tostring(reason))\n\t\tend', '\t\t\terror("Preview join rejected: " .. tostring(reason))\n\t\tend\n\t\t-- Orient once only after an authorized, successful Level 6 arrival.\n\t\ttransport:FireClient(player, "ArrivalFacing", upright(exit.CFrame), MODEL_NAME)'),
])
edit('StarterPlayer.StarterPlayerScripts.Level6PreviewTransport', [
    ('remote.OnClientEvent:Connect(function(nonce, target, modelName)\n', '''remote.OnClientEvent:Connect(function(nonce, target, modelName)
	if nonce == "ArrivalFacing" then
		if typeof(target) ~= "CFrame" or modelName ~= "Level 6 Generated World" then return end
		generation += 1
		local token = generation
		local character = player.Character
		task.spawn(function()
			local deadline = os.clock() + 3
			repeat
				if token ~= generation or player.Character ~= character then return end
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and player:GetAttribute("Level6InRound") == true
					and (root.Position - target.Position).Magnitude < 12 then
					local camera = workspace.CurrentCamera
					if not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
					local look = Vector3.new(target.LookVector.X, 0, target.LookVector.Z).Unit
					local focus = root.Position + Vector3.new(0, 1.5, 0)
					local distance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, .5, 12)
					camera.CFrame = CFrame.lookAt(focus - look * distance + Vector3.new(0, distance * .2, 0), focus)
					camera.Focus = CFrame.new(focus)
					return
				end
				task.wait(.05)
			until os.clock() >= deadline
		end)
		return
	end
'''),
])
(ROOT/'candidate-source/write-plan.json').write_text(json.dumps(plans,ensure_ascii=False))
(ROOT/'candidate-source/source-hashes.json').write_text(json.dumps([{k:v for k,v in p.items() if k not in ('before','after')} for p in plans],indent=2))
print(json.dumps([{k:v for k,v in p.items() if k not in ('before','after')} for p in plans],indent=2))
