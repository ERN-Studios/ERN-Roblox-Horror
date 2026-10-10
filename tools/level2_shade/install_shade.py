"""Put the Level 2 shadow entity's assets into the place: ReplicatedStorage.Level2Shade (Studio in Edit mode).

    python3 tools/level2_shade/install_shade.py --scripts   # make the two empty script instances, if they are missing
    python3 tools/level2_shade/install_shade.py --dry       # say what would be uploaded and built
    python3 tools/level2_shade/install_shade.py             # upload new meshes, rebuild Meshes, update Sounds

Owner, 2026-10-10: a shadow entity for Level 2 that is seen on walls and pillars, creeps up from behind and, unseen,
becomes real and drags the player down. The game side is ServerScriptService."Level 2 Systems"."Level 2 Shade" and
StarterPlayerScripts."Level 2 Shade Client"; they are pushed like any other script (tools/mac_merge_push.py) AFTER
--scripts has made the empty instances. Without the folder this tool builds, both scripts do nothing.

- Meshes: artifacts/level2-shade-20261010/shade.json (tools/level2_shade/build_shade.py), uploaded as group Mesh assets
  through AssetService:CreateAssetAsync exactly as tools/level2_props/install_props.py does; ids are kept beside this
  file with the hash of the numbers they came from, so an unchanged mesh is not uploaded twice. A mesh uploaded this
  way KEEPS ITS OWN ORIGIN: the MeshPart's CFrame is the mesh's (0,0,0), not the middle of its box (seen in play on
  2026-10-10: a figure placed by its box centre stood 5.5 studs up the wall), and resizing scales about that point.
  Each template carries `BoxMin` and `BoxMax` (its box relative to that origin, in studs).
- Sounds: assets/level2-shade-audio-20261010/sound_ids.json (upload_audio.py). Only approved ids are installed; the
  entity runs silent without them. Sounds are the Shade's own: nothing is borrowed from another level.
The folder's Meshes child is rebuilt from scratch; Sounds is updated in place. Nothing else in the place is touched.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
sys.path.insert(0, str(ROOT / 'tools' / 'level2_props'))
from import_to_studio import Studio   # noqa: E402
from install_props import UPLOAD      # noqa: E402  the accepted EditableMesh upload block

UPLOAD = UPLOAD.replace('Level 2 Poolrooms wall lamp', 'Level 2 shadow entity')

EXPORT = ROOT / 'artifacts' / 'level2-shade-20261010' / 'shade.json'
IDS = HERE / 'mesh_ids.json'
SOUND_IDS = ROOT / 'assets' / 'level2-shade-audio-20261010' / 'sound_ids.json'
REVISION = 'L2_SHADE_20261010'
REQUIRED = ['Shade_Stand', 'Shade_Reach', 'Shade_Crawl', 'Shade_Hands', 'Shade_Rise', 'Shade_Claw', 'Shade_Arm',
            'Shade_ArmGrip', 'Shade_Pool']

SCRIPTS = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917, "wrong place")
local made = {}
local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found then
		assert(found.ClassName == class, name .. " exists with class " .. found.ClassName)
		return
	end
	local item = Instance.new(class)
	item.Name = name
	item.Parent = parent
	table.insert(made, name)
end
ensure(game:GetService("ServerScriptService"):WaitForChild("Level 2 Systems"), "Level 2 Shade", "ModuleScript")
ensure(game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"), "Level 2 Shade Client", "LocalScript")
return #made == 0 and "both script instances already exist" or ("made: " .. table.concat(made, ", "))
'''

BUILD = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917, "wrong place")
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SPEC = game:GetService("HttpService"):JSONDecode([==[%s]==])
local bank = ReplicatedStorage:FindFirstChild("Level2Shade")
if bank then assert(bank:IsA("Folder"), "ReplicatedStorage.Level2Shade is not a Folder") end
if not bank then
	bank = Instance.new("Folder")
	bank.Name = "Level2Shade"
end
bank:SetAttribute("Revision", SPEC.revision)
bank:SetAttribute("Built", "tools/level2_shade/install_shade.py")
if bank:GetAttribute("Enabled") == nil then bank:SetAttribute("Enabled", false) end   -- the switch: true once it is verified
bank:SetAttribute("ShadeLive", false)
bank:SetAttribute("ShadePhase", "idle")
bank:SetAttribute("ShadeTarget", 0)
bank:SetAttribute("ShadeSerial", 0)
local fresh = Instance.new("Folder")
fresh.Name = "Meshes"
local report = {}
for name, item in pairs(SPEC.meshes) do
	local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(item.id), {CollisionFidelity = Enum.CollisionFidelity.Box})
	part.Name = name
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow, part.Massless = true, false, false, false, false, true
	part.Material, part.Color = Enum.Material.Neon, Color3.new(0, 0, 0)
	part:SetAttribute("AssetId", item.id)
	part:SetAttribute("BoxMin", Vector3.new(item.min[1], item.min[2], item.min[3]))
	part:SetAttribute("BoxMax", Vector3.new(item.max[1], item.max[2], item.max[3]))
	local want = Vector3.new(item.size[1], item.size[2], item.size[3])
	table.insert(report, string.format("%%s %%.2f,%%.2f,%%.2f (export %%.2f,%%.2f,%%.2f)", name, part.Size.X, part.Size.Y, part.Size.Z, want.X, want.Y, want.Z))
	assert((part.Size - want).Magnitude < 0.05, name .. ": the uploaded mesh's box is not the exported one")
	part.Parent = fresh
end
local old = bank:FindFirstChild("Meshes")
if old then old:Destroy() end
fresh.Parent = bank
local sounds = bank:FindFirstChild("Sounds")
if not sounds then
	sounds = Instance.new("Folder")
	sounds.Name = "Sounds"
	sounds.Parent = bank
end
local added, changed = 0, 0
for key, row in pairs(SPEC.sounds) do
	local id = "rbxassetid://" .. row.id
	local sound = sounds:FindFirstChild(key)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name, sound.Volume = key, 0
		sound.Parent = sounds
		added += 1
	elseif sound.SoundId ~= id then
		changed += 1
	end
	sound.SoundId = id
	sound.Looped = row.loop
	sound:SetAttribute("MasterSHA256", row.sha)
	sound:SetAttribute("Provider", "ElevenLabs")
	sound:SetAttribute("Gain", row.gain)   -- what the client multiplies its volume by: the masters are not equally loud
end
bank.Parent = ReplicatedStorage
table.sort(report)
return string.format("INSTALLED %%s: %%d meshes; sounds %%d added, %%d re-pointed, %%d in the folder\\n%%s", SPEC.revision, #fresh:GetChildren(),
	added, changed, #sounds:GetChildren(), table.concat(report, "\\n"))
'''


def main():
    studio = Studio()
    if '--scripts' in sys.argv:
        print(studio.luau(SCRIPTS))
        return
    dry = '--dry' in sys.argv
    export = json.loads(EXPORT.read_text())['meshes']
    missing = [name for name in REQUIRED if name not in export]
    assert not missing, f'shade.json lacks {missing}'
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    meshes = {}
    for name in REQUIRED:
        item = export[name]
        known = ids.get(name, {})
        fresh = known.get('sha1') != item['sha1']
        if dry:
            print(f'{name:14s} {item["triangles"]:5d} tris  {"UPLOAD" if fresh else "known " + str(known.get("id"))}')
            continue
        if fresh:
            payload = json.dumps({k: item[k] for k in ('verts', 'normals', 'colours', 'tris')}, separators=(',', ':'))
            answer = studio.luau(UPLOAD % (json.dumps(name), 0, payload))
            assert answer.startswith('OK '), f'{name}: {answer}'
            ids[name] = {'id': int(answer.split()[1]), 'sha1': item['sha1']}
            IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
            print(f'{name:14s} -> {ids[name]["id"]}', flush=True)
        meshes[name] = {'id': ids[name]['id'], 'size': item['size'], 'min': item['bbox']['min'], 'max': item['bbox']['max']}
    sounds = {}
    levels_file = SOUND_IDS.parent / 'levels.json'
    levels = json.loads(levels_file.read_text())['sounds'] if levels_file.exists() else {}
    if SOUND_IDS.exists():
        for key, row in json.loads(SOUND_IDS.read_text()).items():
            if row.get('moderation') == 'Approved':
                sounds[key] = {'id': str(row['asset_id']), 'sha': row['master_sha256'], 'loop': key in ('shade_presence', 'shade_hands'),
                               'gain': levels.get(key, {}).get('gain', 1)}
    if dry:
        print(f'{len(sounds)} approved sounds would be installed')
        return
    print(studio.luau(BUILD % json.dumps({'revision': REVISION, 'meshes': meshes, 'sounds': sounds})))


if __name__ == '__main__':
    main()
